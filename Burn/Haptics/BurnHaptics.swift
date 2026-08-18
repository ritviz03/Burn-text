//
//  BurnHaptics.swift
//

import CoreHaptics
import UIKit

/// The fire, felt — held at a level for as long as something is alight.
///
/// The burn used to be a fixed length, so it could be described as one pattern and
/// handed over at ignition. Dragging a match has no known end, so instead a short
/// continuous pattern loops and its strength is modulated live with a dynamic
/// parameter. That keeps the rumble on CoreHaptics' own clock — it does not stutter
/// with the render loop — while still answering to how much is burning.
///
/// Haptics are silent on the Simulator; this needs a real device to feel.
///
/// Created and driven from the main thread by `ComposeView`.
final class BurnHaptics {
    static let isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    /// Length of the looped rumble. Short, because it just repeats.
    private static let loopLength: TimeInterval = 2
    /// Don't resend a parameter for a change this small — `setLevel` is called
    /// every frame and CoreHaptics does not need 60 updates a second.
    private static let levelEpsilon: Double = 0.03

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var level: Double = 0

    /// Spin the engine up ahead of time so the first touch is not late.
    func prepare() {
        guard Self.isSupported, engine == nil else { return }
        do {
            let created = try CHHapticEngine()
            created.playsHapticsOnly = true
            // Left running while the screen is up: an auto-shutdown mid-burn would
            // drop the rumble.
            created.isAutoShutdownEnabled = false
            created.resetHandler = { [weak self] in
                // Called on CoreHaptics' own queue. The system can tear the engine
                // down; drop ours and rebuild lazily on the next touch.
                DispatchQueue.main.async {
                    self?.engine = nil
                    self?.player = nil
                    self?.level = 0
                }
            }
            try created.start()
            engine = created
        } catch {
            engine = nil
        }
    }

    /// Holds the rumble at `level` (0...1). Safe to call every frame.
    func setLevel(_ level: Double) {
        guard Self.isSupported else { return }
        let level = min(max(level, 0), 1)

        guard level > 0.001 else {
            stop()
            return
        }

        if player == nil { start() }
        guard let player else { return }

        guard self.level == 0 || abs(level - self.level) > Self.levelEpsilon else { return }
        self.level = level

        // Base intensity is 1, so the control parameter has the full range to work
        // with. Floored, so one smouldering letter is still felt.
        let parameter = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: Float(0.25 + 0.75 * level),
            relativeTime: 0
        )
        try? player.sendParameters([parameter], atTime: CHHapticTimeImmediate)
    }

    func stop() {
        guard player != nil else { return }
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        level = 0
    }

    private func start() {
        prepare()
        guard let engine else { return }
        do {
            let created = try engine.makeAdvancedPlayer(with: pattern())
            created.loopEnabled = true
            try engine.start()
            try created.start(atTime: CHHapticTimeImmediate)
            player = created
            level = 0
        } catch {
            player = nil
        }
    }

    private func pattern() throws -> CHHapticPattern {
        let rumble = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
            ],
            relativeTime: 0,
            duration: Self.loopLength
        )

        // A few crackles over the top so it is not a flat buzz. They loop with the
        // rumble, and the offsets are uneven enough not to sound metronomic.
        let crackles = [0.21, 0.58, 0.93, 1.34, 1.71].map { offset in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85),
                ],
                relativeTime: offset
            )
        }

        return try CHHapticPattern(events: [rumble] + crackles, parameters: [])
    }
}
