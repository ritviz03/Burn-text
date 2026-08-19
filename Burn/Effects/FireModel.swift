//
//  FireModel.swift
//

import CoreGraphics
import Foundation

/// The state of the fire: how hot each character is, and the embers coming off it.
///
/// Advanced by `tick` once per frame rather than derived from a clock, because the
/// fire now depends on where the user has *been* — a path, not a timeline. A
/// character the flame touched keeps burning after the flame moves on.
///
/// Pure value semantics and no view or UIKit dependency, so the whole simulation
/// can be stepped and asserted on in tests.
struct FireModel {
    // MARK: - Tuning

    /// How close the flame has to be, in points, to start heating a character.
    static let ignitionRadius: Double = 46
    /// Heat gained per second by a character directly under the flame.
    static let heatRate: Double = 2.6
    /// Past this much heat a character is alight and no longer needs the flame.
    static let selfSustain: Double = 0.12
    /// Heat gained per second once alight. ~0.9s from catching to gone.
    static let burnRate: Double = 1.15
    /// Heat at which a character stops being drawn.
    static let consumed: Double = 1.0

    static let emberLimit = 240
    /// Embers per second, per burning character.
    static let emberRate: Double = 14
    /// Beyond this many burning characters the ember rate stops climbing.
    static let emberSourceLimit = 24

    // MARK: - State

    struct Ember {
        var x: Double
        var y: Double
        var riseSpeed: Double
        var drift: Double
        var age: Double = 0
        var life: Double
        var radius: Double
        var isSmoke: Bool
        /// Phase offset so embers do not wander in lockstep.
        var wobble: Double

        var progress: Double { min(max(age / life, 0), 1) }
        var isDead: Bool { age >= life }
    }

    /// Heat per glyph, parallel to `GlyphLayout.glyphs`.
    private(set) var glyphHeat: [Double] = []
    private(set) var embers: [Ember] = []

    private var rng = SplitMix64(state: 0x9E37_79B9_7F4A_7C15)
    /// Fractional embers carried between frames, so a low rate still emits.
    private var emberCarry: Double = 0

    // MARK: - Queries

    /// Characters currently alight but not yet gone.
    var burningCount: Int {
        glyphHeat.reduce(into: 0) { total, value in
            if value > 0 && value < Self.consumed { total += 1 }
        }
    }

    var isAlight: Bool { burningCount > 0 }

    func isConsumed(_ glyphIndex: Int) -> Bool {
        guard glyphIndex < glyphHeat.count else { return false }
        return glyphHeat[glyphIndex] >= Self.consumed
    }

    func heat(at glyphIndex: Int) -> Double {
        guard glyphIndex < glyphHeat.count else { return 0 }
        return glyphHeat[glyphIndex]
    }

    /// True once every character that *can* burn has. Whitespace is skipped: a
    /// page of burned words with spaces left over is still finished.
    func hasBurnedEverything(in layout: GlyphLayout) -> Bool {
        let burnable = layout.glyphs.indices.filter { !layout.glyphs[$0].character.isWhitespace }
        guard !burnable.isEmpty else { return false }
        return burnable.allSatisfy { $0 < glyphHeat.count && glyphHeat[$0] >= Self.consumed }
    }

    // MARK: - Lifecycle

    /// Resets for a fresh layout. Called when the text or its size changes.
    mutating func reset(glyphCount: Int) {
        glyphHeat = Array(repeating: 0, count: glyphCount)
        embers.removeAll(keepingCapacity: true)
        emberCarry = 0
    }

    /// Keeps existing heat while the glyph count grows or shrinks, so re-laying
    /// out mid-burn (a rotation, a font change) does not put the fire out.
    mutating func resize(glyphCount: Int) {
        guard glyphCount != glyphHeat.count else { return }
        if glyphCount < glyphHeat.count {
            glyphHeat.removeLast(glyphHeat.count - glyphCount)
        } else {
            glyphHeat.append(contentsOf: Array(repeating: 0, count: glyphCount - glyphHeat.count))
        }
    }

    // MARK: - Simulation

    /// Advances the fire by `dt` seconds.
    ///
    /// - Parameters:
    ///   - flame: where the flame tip is on screen, or `nil` when the user is not
    ///     touching. Characters already alight carry on either way.
    ///   - layout: glyph frames in the *layout's own* space — `(0, 0)` at the top
    ///     of the laid-out text, regardless of where that text is centred on
    ///     screen.
    ///   - origin: where the layout's `(0, 0)` lands on screen — the same value
    ///     the view passes to `BurnCanvas` to draw it in the right place. Without
    ///     this, `flame` (screen space) and a glyph's frame (layout space) are not
    ///     comparable: whenever the text is not pinned to the screen's top-left,
    ///     the flame would visibly touch a letter while this method kept
    ///     measuring the distance to a phantom copy of the text sitting wherever
    ///     the untranslated layout would place it — silently never igniting
    ///     anything.
    mutating func tick(
        dt: Double,
        flame: CGPoint?,
        layout: GlyphLayout,
        origin: CGPoint = .zero,
        reduceMotion: Bool = false
    ) {
        guard dt > 0 else { return }
        resize(glyphCount: layout.glyphs.count)
        // A long stall (backgrounded, or a slow first frame) should not teleport
        // the fire forward.
        let step = min(dt, 1.0 / 20.0)

        let spread = reduceMotion ? Self.burnRate * 2.2 : Self.burnRate

        for index in layout.glyphs.indices {
            let glyph = layout.glyphs[index]
            if glyph.character.isWhitespace { continue }

            var value = glyphHeat[index]
            if value >= Self.consumed { continue }

            if let flame {
                let centre = CGPoint(x: origin.x + glyph.frame.midX, y: origin.y + glyph.frame.midY)
                let dx = Double(flame.x - centre.x)
                let dy = Double(flame.y - centre.y)
                let distance = (dx * dx + dy * dy).squareRoot()
                if distance < Self.ignitionRadius {
                    // Smoothstep falloff: hottest dead centre, nothing at the rim.
                    let near = 1 - distance / Self.ignitionRadius
                    let falloff = near * near * (3 - 2 * near)
                    value += step * Self.heatRate * falloff
                }
            }

            if value >= Self.selfSustain {
                value += step * spread
            }

            glyphHeat[index] = min(value, Self.consumed)
        }

        stepEmbers(step: step, layout: layout, reduceMotion: reduceMotion)
    }

    private mutating func stepEmbers(step: Double, layout: GlyphLayout, reduceMotion: Bool) {
        for index in embers.indices {
            var ember = embers[index]
            ember.age += step
            ember.y -= ember.riseSpeed * step
            // Embers wander rather than travel straight up.
            ember.x += (ember.drift + sin(ember.age * 3.4 + ember.wobble) * 14) * step
            // Buoyancy bleeds off as they cool.
            ember.riseSpeed *= 1 - min(step * 0.85, 0.9)
            embers[index] = ember
        }
        embers.removeAll { $0.isDead }

        // Reduce Motion keeps the burn but drops the flying debris.
        guard !reduceMotion else { return }

        let sources = layout.glyphs.indices.filter { index in
            guard !layout.glyphs[index].character.isWhitespace else { return false }
            let value = glyphHeat[index]
            return value > 0.08 && value < Self.consumed
        }
        guard !sources.isEmpty else {
            emberCarry = 0
            return
        }

        let rate = Double(min(sources.count, Self.emberSourceLimit)) * Self.emberRate
        emberCarry += rate * step
        var toSpawn = Int(emberCarry)
        emberCarry -= Double(toSpawn)
        toSpawn = min(toSpawn, Self.emberLimit - embers.count)
        guard toSpawn > 0 else { return }

        for _ in 0..<toSpawn {
            let glyph = layout.glyphs[sources[Int(rng.next() % UInt64(sources.count))]]
            let isSmoke = rng.double(in: 0...1) < 0.28
            embers.append(
                Ember(
                    x: Double(glyph.frame.minX) + rng.double(in: 0...Double(glyph.frame.width)),
                    y: Double(glyph.frame.minY) + rng.double(in: 0...Double(glyph.frame.height)),
                    riseSpeed: isSmoke ? rng.double(in: 26...54) : rng.double(in: 52...118),
                    drift: rng.double(in: -18...18),
                    life: isSmoke ? rng.double(in: 1.1...1.9) : rng.double(in: 0.55...1.25),
                    radius: isSmoke ? rng.double(in: 1.8...3.6) : rng.double(in: 0.8...2.2),
                    isSmoke: isSmoke,
                    wobble: rng.double(in: 0...6.283)
                )
            )
        }
    }
}

/// Small, fast, seedable PRNG.
///
/// Used instead of `Double.random` so a burn can be replayed exactly in a test.
struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `range`.
    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
