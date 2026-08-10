//
//  EmberParticles.swift
//

import SwiftUI

/// Sparks and smoke lifting off the burn front.
///
/// Every particle is a pure function of its index and the burn's seed, so there
/// is no per-frame state to keep, nothing to allocate, and the same thought
/// burns the same way twice. Drawn in one `Canvas` pass.
struct EmberParticles: View {
    /// The burn's eased progress, 0...1.
    let progress: Double
    let seed: Double
    var count: Int = 110

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let seedBits = UInt64(bitPattern: Int64(seed * 4096))

            for index in 0..<count {
                let spark = ember(index: index, seed: seedBits)
                let age = progress - spark.ignition
                guard age > 0, age < spark.life else { continue }

                let t = age / spark.life // 0 at birth, 1 at death
                let fade = (1 - t) * (1 - t)

                let x = (spark.x + spark.drift * t) * size.width
                // Embers rise, and rise faster as they lose mass.
                let y = (spark.y - spark.rise * pow(t, 0.7)) * size.height

                let radius = spark.isSmoke
                    ? spark.radius * (0.8 + 2.6 * t)
                    : spark.radius * (1 - 0.55 * t)
                guard radius > 0.05 else { continue }

                let box = CGRect(
                    x: x - radius,
                    y: y - radius,
                    width: radius * 2,
                    height: radius * 2
                )

                if spark.isSmoke {
                    context.fill(
                        Path(ellipseIn: box),
                        with: .color(.white.opacity(fade * 0.05))
                    )
                } else {
                    // Fresh sparks are near-white, cooling through orange to red.
                    let colour = Color(
                        hue: 0.09 - 0.07 * t,
                        saturation: 0.55 + 0.45 * t,
                        brightness: 1
                    )
                    context.fill(Path(ellipseIn: box), with: .color(colour.opacity(fade)))
                }
            }
        }
    }

    private struct Ember {
        var x: Double
        var y: Double
        var ignition: Double
        var life: Double
        var rise: Double
        var drift: Double
        var radius: Double
        var isSmoke: Bool
    }

    private func ember(index: Int, seed: UInt64) -> Ember {
        var rng = SplitMix64(state: seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)

        let x = rng.nextUnit()
        let y = rng.nextUnit()
        let isSmoke = rng.nextUnit() < 0.35

        // Light up when the fire arrives, give or take a little, so the sparks
        // trail the front rather than forming a clean line along it.
        let jitter = (rng.nextUnit() - 0.5) * 0.12
        let ignition = min(max(BurnField.ignition(x: x, y: y) + jitter, 0), 1)

        return Ember(
            x: x,
            y: y,
            ignition: ignition,
            life: isSmoke ? 0.30 + 0.28 * rng.nextUnit() : 0.12 + 0.20 * rng.nextUnit(),
            rise: isSmoke ? 0.30 + 0.45 * rng.nextUnit() : 0.10 + 0.30 * rng.nextUnit(),
            drift: (rng.nextUnit() - 0.35) * 0.10,
            radius: isSmoke ? 6 + 10 * rng.nextUnit() : 0.9 + 2.0 * rng.nextUnit(),
            isSmoke: isSmoke
        )
    }
}

/// Small, fast, deterministic generator. Seeded per particle so the field can be
/// rebuilt from nothing on every frame.
private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1, using the top 53 bits.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
