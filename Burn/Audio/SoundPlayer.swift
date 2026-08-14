//
//  SoundPlayer.swift
//

import AVFoundation

/// Crackle and whoosh under the burn.
///
/// Created and driven from the main thread by `ComposeView`.
final class SoundPlayer {
    /// The bundled fire clip.
    ///
    /// `Burn/Resources/burn-crackle.wav` is synthesised by
    /// `Tools/make_burn_sound.py` — good enough to develop against, but swap in
    /// a licensed recording before shipping.
    static let burnResource = "burn-crackle"
    static let burnExtension = "wav"

    /// Sits under the room rather than on top of it.
    static let volume: Float = 0.62

    /// How long after the fire starts the sound should begin.
    ///
    /// The clip's attack lands on its first sample, but the flame front needs a
    /// moment to become visible — the eased curve starts slow — so playing on the
    /// same frame reads as though the sound arrives before the fire.
    static let burnLeadIn: TimeInterval = 0.8

    /// `burnLeadIn`, capped to half the burn.
    ///
    /// The Reduce Motion burn is only 0.45s long, and a flat 0.8s lead-in would
    /// schedule the sound for after it had already finished — i.e. silence.
    static func leadIn(for duration: TimeInterval) -> TimeInterval {
        min(burnLeadIn, duration * 0.5)
    }

    private var player: AVAudioPlayer?

    /// Loads the clip and configures the session. Cheap to call repeatedly.
    func prepare(resource: String = Self.burnResource, withExtension ext: String = Self.burnExtension) {
        // `.ambient` keeps the app polite: it obeys the ring/silent switch and
        // mixes with whatever the user is already listening to instead of
        // stopping it. Mixing is implicit in this category — passing
        // `.mixWithOthers` explicitly is rejected, and because this call is
        // `try?` that would silently leave the session on the process default
        // (`.soloAmbient`), which does not mix at all.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)

        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            // Nothing bundled — the app stays perfectly usable in silence.
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = Self.volume
        // Required before `play(atTime:)` can schedule accurately.
        player?.prepareToPlay()
    }

    /// Starts the clip, optionally `delay` seconds from now.
    ///
    /// Scheduled through `play(atTime:)` on the audio device's own clock rather
    /// than a `Task.sleep`, so the start lands where it should even if the main
    /// actor is busy laying out the first frames of the burn.
    func play(after delay: TimeInterval = 0) {
        prepare()
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.currentTime = 0
        if delay > 0 {
            player.play(atTime: player.deviceCurrentTime + delay)
        } else {
            player.play()
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
    }
}
