//
//  SoundPlayer.swift
//

import AVFoundation

/// Crackle under the fire, held at a level rather than played as a one-shot.
///
/// The burn has no fixed length any more — it lasts as long as there is something
/// alight — so the clip loops and its volume tracks how much is burning. It fades
/// out when the last character goes rather than cutting off.
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
    /// Level below which the fire counts as out.
    static let silence: Double = 0.001
    /// Even one smouldering letter should be audible, so the level maps onto
    /// `floor...1` rather than `0...1`.
    static let floorLevel: Float = 0.35
    static let fadeOut: TimeInterval = 0.35

    private var player: AVAudioPlayer?
    private var isRunning = false
    private var fade: Task<Void, Never>?

    /// Loads the clip and configures the session. Cheap to call repeatedly.
    ///
    /// The defaults are spelled `SoundPlayer.` rather than `Self.`: a default
    /// argument is evaluated at the call site, where the dynamic `Self` of a class
    /// is not known, so the compiler rejects it — `final` makes no difference.
    func prepare(
        resource: String = SoundPlayer.burnResource,
        withExtension ext: String = SoundPlayer.burnExtension
    ) {
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
        player?.numberOfLoops = -1
        player?.volume = 0
        player?.prepareToPlay()
    }

    /// Holds the crackle at `level` (0...1). Safe to call every frame.
    func setLevel(_ level: Double) {
        let level = min(max(level, 0), 1)

        guard level > Self.silence else {
            fadeOutAndPause()
            return
        }

        prepare()
        guard let player else { return }

        fade?.cancel()
        fade = nil

        if !isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            player.currentTime = 0
            player.play()
            isRunning = true
        }

        let scaled = Self.floorLevel + (1 - Self.floorLevel) * Float(level)
        // Assigned rather than ramped, so it overrides any fade still in flight.
        player.volume = Self.volume * scaled
    }

    /// Stops immediately, without a fade. For leaving the screen.
    func stop() {
        fade?.cancel()
        fade = nil
        isRunning = false
        player?.stop()
        player?.currentTime = 0
        player?.volume = 0
    }

    private func fadeOutAndPause() {
        guard isRunning, fade == nil, let player else { return }
        isRunning = false
        player.setVolume(0, fadeDuration: Self.fadeOut)
        fade = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.fadeOut + 0.05))
            guard !Task.isCancelled else { return }
            player.pause()
        }
    }
}
