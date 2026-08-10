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
        player?.prepareToPlay()
    }

    func play() {
        prepare()
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.currentTime = 0
        player.play()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
    }
}
