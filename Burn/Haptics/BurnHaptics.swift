//
//  BurnHaptics.swift
//

import CoreHaptics
import UIKit

/// The fire, felt.
///
/// The entire burn is described as one `CHHapticPattern` and handed over at
/// ignition rather than streamed frame by frame. CoreHaptics then runs it on its
/// own clock, so the rumble keeps time with the animation even if the render
/// loop stutters.
///
/// Haptics are silent on the Simulator — this needs a real device to feel.
///
/// Created and driven from the main thread by `ComposeView`.
final class BurnHaptics {
    static let isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var engine: CHHapticEngine?
    /// Held for the length of the burn: a released player stops mid-pattern.
    private var player: CHHapticPatternPlayer?

    /// Spin the engine up ahead of time so the first tap is not late.
    func prepare() {
        guard Self.isSupported, engine == nil else { return }
        do {
            let created = try CHHapticEngine()
            created.playsHapticsOnly = true
            created.isAutoShutdownEnabled = true
            created.resetHandler = { [weak self] in
                // Called on CoreHaptics' own queue. The system can tear the
                // engine down; drop ours and rebuild lazily on the next burn.
                DispatchQueue.main.async { self?.engine = nil }
            }
            try created.start()
            engine = created
        } catch {
            engine = nil
        }
    }

    func play(duration: TimeInterval) {
        guard Self.isSupported else {
            // Hardware without the haptic engine: at least mark the moment.
            fallbackThud()
            return
        }

        prepare()
        guard let engine else { return }

        do {
            let created = try engine.makePlayer(with: pattern(duration: duration))
            try engine.start()
            try created.start(atTime: CHHapticTimeImmediate)
            player = created
        } catch {
            player = nil
            fallbackThud()
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    /// One thump, for hardware without the haptic engine or when the pattern
    /// fails to build. Hopped to the main actor because `UIFeedbackGenerator` is
    /// UI-actor bound.
    private func fallbackThud() {
        DispatchQueue.main.async {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    private func pattern(duration: TimeInterval) throws -> CHHapticPattern {
        // A continuous rumble under the whole burn...
        var events = [
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35),
                ],
                relativeTime: 0,
                duration: duration
            )
        ]

        // ...crackling over the top, thinning out as the fire runs out of paper.
        let crackles = 8
        for index in 0..<crackles {
            let fraction = Double(index) / Double(crackles - 1)
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(
                            parameterID: .hapticIntensity,
                            value: Float(0.25 + 0.55 * (1 - fraction))
                        ),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85),
                    ],
                    relativeTime: duration * (0.08 + 0.84 * fraction)
                )
            )
        }

        // Catches quietly, roars, dies away.
        let intensity = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.15),
                .init(relativeTime: duration * 0.35, value: 1.0),
                .init(relativeTime: duration * 0.75, value: 0.65),
                .init(relativeTime: duration, value: 0.0),
            ],
            relativeTime: 0
        )

        return try CHHapticPattern(events: events, parameterCurves: [intensity])
    }
}
