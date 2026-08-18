//
//  FireModelTests.swift
//

import CoreGraphics
import XCTest

@testable import Burn

final class FireModelTests: XCTestCase {
    /// A synthetic layout with exact frames, so the physics can be asserted on
    /// without depending on font metrics.
    ///
    /// Characters sit in a row of 20x30 cells starting at the origin.
    private func row(_ text: String) -> GlyphLayout {
        var glyphs: [GlyphLayout.Glyph] = []
        for (index, character) in Array(text).enumerated() {
            glyphs.append(
                GlyphLayout.Glyph(
                    character: character,
                    index: index,
                    frame: CGRect(x: CGFloat(index) * 20, y: 0, width: 20, height: 30),
                    line: 0
                )
            )
        }
        return GlyphLayout(
            glyphs: glyphs,
            size: CGSize(width: CGFloat(text.count) * 20, height: 30),
            lineHeight: 30
        )
    }

    /// The same, but with cells spaced further apart than `ignitionRadius`, so
    /// each character can be lit without catching its neighbours.
    private func spacedRow(_ text: String) -> GlyphLayout {
        let cell = FireModel.ignitionRadius * 2
        var glyphs: [GlyphLayout.Glyph] = []
        for (index, character) in Array(text).enumerated() {
            glyphs.append(
                GlyphLayout.Glyph(
                    character: character,
                    index: index,
                    frame: CGRect(x: CGFloat(index) * cell, y: 0, width: cell, height: 30),
                    line: 0
                )
            )
        }
        return GlyphLayout(
            glyphs: glyphs,
            size: CGSize(width: CGFloat(text.count) * cell, height: 30),
            lineHeight: 30
        )
    }

    private func centre(of layout: GlyphLayout, at index: Int) -> CGPoint {
        CGPoint(x: layout.glyphs[index].frame.midX, y: layout.glyphs[index].frame.midY)
    }

    /// Runs `seconds` of simulation at 60fps.
    private func run(
        _ fire: inout FireModel,
        seconds: Double,
        flame: CGPoint?,
        layout: GlyphLayout,
        reduceMotion: Bool = false
    ) {
        let step = 1.0 / 60.0
        for _ in 0..<Int(seconds / step) {
            fire.tick(dt: step, flame: flame, layout: layout, reduceMotion: reduceMotion)
        }
    }

    // MARK: - Heating

    func testNothingBurnsWithoutAFlame() {
        let layout = row("abc")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 1, flame: nil, layout: layout)
        XCTAssertEqual(fire.burningCount, 0)
        XCTAssertTrue(fire.glyphHeat.allSatisfy { $0 == 0 })
    }

    func testAFlameFarAwayDoesNothing() {
        let layout = row("abc")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 1, flame: CGPoint(x: 900, y: 900), layout: layout)
        XCTAssertEqual(fire.heat(at: 0), 0)
    }

    func testTheCharacterUnderTheFlameHeatsFastest() {
        let layout = row("abcdef")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 0.05, flame: centre(of: layout, at: 0), layout: layout)
        XCTAssertGreaterThan(fire.heat(at: 0), fire.heat(at: 1))
        XCTAssertGreaterThan(fire.heat(at: 1), fire.heat(at: 5))
    }

    /// The behaviour the whole mechanic depends on: once a character has caught, it
    /// keeps burning after the match has moved on. Without this, letting go would
    /// leave half-lit characters stuck orange forever.
    func testACharacterKeepsBurningOnceTheFlameLeaves() {
        let layout = row("abc")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)

        run(&fire, seconds: 0.2, flame: centre(of: layout, at: 0), layout: layout)
        let caught = fire.heat(at: 0)
        XCTAssertGreaterThan(caught, FireModel.selfSustain, "should be alight by now")

        run(&fire, seconds: 0.2, flame: nil, layout: layout)
        XCTAssertGreaterThan(fire.heat(at: 0), caught, "it should carry on without the flame")
    }

    func testACharacterOnlyTouchedBrieflyDoesNotCatch() {
        let layout = row("abc")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        // A single frame at the very rim of the radius.
        let edge = CGPoint(x: layout.glyphs[0].frame.midX + FireModel.ignitionRadius - 1, y: 15)
        fire.tick(dt: 1.0 / 60.0, flame: edge, layout: layout)
        run(&fire, seconds: 1, flame: nil, layout: layout)
        XCTAssertLessThan(fire.heat(at: 0), FireModel.consumed)
    }

    func testHeatNeverExceedsConsumed() {
        let layout = row("a")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 6, flame: centre(of: layout, at: 0), layout: layout)
        XCTAssertEqual(fire.heat(at: 0), FireModel.consumed)
    }

    func testWhitespaceNeverBurns() {
        let layout = row("a b")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 3, flame: centre(of: layout, at: 1), layout: layout)
        XCTAssertEqual(fire.heat(at: 1), 0, "a space should not catch")
    }

    /// A stalled frame — backgrounded, or a slow first render — must not jump the
    /// fire forward by the whole gap.
    func testALongStallIsClamped() {
        let layout = row("a")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        fire.tick(dt: 30, flame: centre(of: layout, at: 0), layout: layout)
        XCTAssertLessThan(fire.heat(at: 0), FireModel.consumed, "30s should not land in one step")
    }

    // MARK: - Finishing

    func testHasBurnedEverythingOnlyOnceItHas() {
        // Spaced out, so lighting the first character cannot reach the second.
        let layout = spacedRow("ab")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        XCTAssertFalse(fire.hasBurnedEverything(in: layout))

        run(&fire, seconds: 3, flame: centre(of: layout, at: 0), layout: layout)
        XCTAssertFalse(fire.hasBurnedEverything(in: layout), "'b' is still there")

        run(&fire, seconds: 3, flame: centre(of: layout, at: 1), layout: layout)
        XCTAssertTrue(fire.hasBurnedEverything(in: layout))
    }

    /// Fire reaching the letters either side is deliberate, not a leak: the flame
    /// has a radius, and a burn that only ever took the one character dead-centre
    /// would feel like a cursor rather than a fire.
    func testFireSpreadsToNeighboursWithinTheRadius() {
        let layout = row("abc")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 3, flame: centre(of: layout, at: 0), layout: layout)
        XCTAssertEqual(fire.heat(at: 1), FireModel.consumed, "a neighbour 20pt away should catch")
    }

    func testFireDoesNotReachBeyondTheRadius() {
        let layout = spacedRow("ab")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 3, flame: centre(of: layout, at: 0), layout: layout)
        XCTAssertEqual(fire.heat(at: 1), 0, "and nothing beyond it should")
    }

    /// Spaces can never burn, so requiring them would mean a burn never completes.
    func testFinishingIgnoresSpaces() {
        let layout = row("a b")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 3, flame: centre(of: layout, at: 0), layout: layout)
        run(&fire, seconds: 3, flame: centre(of: layout, at: 2), layout: layout)
        XCTAssertTrue(fire.hasBurnedEverything(in: layout))
    }

    func testAnEmptyPageIsNeverFinished() {
        let layout = row("")
        var fire = FireModel()
        fire.reset(glyphCount: 0)
        XCTAssertFalse(fire.hasBurnedEverything(in: layout))
    }

    // MARK: - Embers

    func testEmbersComeOffBurningCharacters() {
        let layout = row("abcd")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 0.5, flame: centre(of: layout, at: 0), layout: layout)
        XCTAssertFalse(fire.embers.isEmpty)
    }

    func testEmbersAreCapped() {
        let layout = row(String(repeating: "x", count: 40))
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        for index in 0..<40 {
            run(&fire, seconds: 0.1, flame: centre(of: layout, at: index), layout: layout)
        }
        XCTAssertLessThanOrEqual(fire.embers.count, FireModel.emberLimit)
    }

    func testEmbersRise() {
        let layout = row("abc")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 0.5, flame: centre(of: layout, at: 0), layout: layout)
        // Embers spawn inside the text row (y 0...30) and climb out of it. Checking
        // against the band rather than one ember's start avoids depending on which
        // particles are still alive.
        XCTAssertTrue(fire.embers.contains { $0.y < 0 }, "embers should climb clear of the text")
    }

    func testReduceMotionDropsTheEmbersButStillBurns() {
        let layout = row("abc")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 0.5, flame: centre(of: layout, at: 0), layout: layout, reduceMotion: true)
        XCTAssertTrue(fire.embers.isEmpty, "no flying debris under Reduce Motion")
        XCTAssertGreaterThan(fire.heat(at: 0), 0, "but the text should still burn")
    }

    // MARK: - Resizing

    func testResizeKeepsExistingHeat() {
        let layout = row("abc")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 0.2, flame: centre(of: layout, at: 0), layout: layout)
        let before = fire.heat(at: 0)

        fire.resize(glyphCount: 6)
        XCTAssertEqual(fire.glyphHeat.count, 6)
        XCTAssertEqual(fire.heat(at: 0), before, accuracy: 0.0001, "a relayout should not put the fire out")
        XCTAssertEqual(fire.heat(at: 5), 0)
    }

    func testResetClearsEverything() {
        let layout = row("abc")
        var fire = FireModel()
        fire.reset(glyphCount: layout.glyphs.count)
        run(&fire, seconds: 0.5, flame: centre(of: layout, at: 0), layout: layout)

        fire.reset(glyphCount: layout.glyphs.count)
        XCTAssertTrue(fire.embers.isEmpty)
        XCTAssertEqual(fire.burningCount, 0)
        XCTAssertTrue(fire.glyphHeat.allSatisfy { $0 == 0 })
    }
}

final class SplitMix64Tests: XCTestCase {
    func testSameSeedGivesSameSequence() {
        var a = SplitMix64(state: 42)
        var b = SplitMix64(state: 42)
        for _ in 0..<20 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDoublesStayInRange() {
        var rng = SplitMix64(state: 7)
        for _ in 0..<500 {
            let value = rng.double(in: -3...9)
            XCTAssertGreaterThanOrEqual(value, -3)
            XCTAssertLessThanOrEqual(value, 9)
        }
    }
}
