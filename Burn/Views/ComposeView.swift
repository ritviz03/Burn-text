//
//  ComposeView.swift
//

import SwiftData
import SwiftUI

/// One thought, one button.
///
/// The whole app lives here: write, tap Burn, watch it go. There is no submit
/// step — what you type is already what is on screen, sized to fill it.
struct ComposeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(Setting.soundEnabled) private var soundEnabled = true
    @AppStorage(Setting.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(Setting.keepsJournal) private var keepsJournal = true

    @State private var text = ""
    @State private var burn: BurnRun?
    @State private var haptics = BurnHaptics()
    @State private var sound = SoundPlayer()
    @FocusState private var isWriting: Bool

    /// Shared by the editor and the burning copy, so the type does not jump when
    /// the fire takes over.
    private let fitter = FontFitter()

    private static let prompt = "What's weighing on you?"

    var body: some View {
        VStack(spacing: 0) {
            canvas
            burnButton
        }
        .background(background)
        .onAppear(perform: warmUp)
        // Cancelled automatically if a new burn starts or the view goes away.
        .task(id: burn?.id) {
            guard let run = burn else { return }
            do {
                try await Task.sleep(for: .seconds(run.duration))
            } catch {
                return
            }
            finish(run)
        }
    }

    // MARK: - Pieces

    private var canvas: some View {
        ZStack {
            if let burn {
                BurnView(
                    text: burn.text,
                    startedAt: burn.startedAt,
                    duration: burn.duration,
                    seed: burn.seed,
                    fitter: fitter,
                    reducesMotion: reduceMotion
                )
            } else {
                editor
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping anywhere on the page starts writing.
            if burn == nil { isWriting = true }
        }
    }

    private var editor: some View {
        GeometryReader { proxy in
            let size = fitter.fittedSize(for: text, in: proxy.size)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                TextField(Self.prompt, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(fitter.swiftUIFont(ofSize: size))
                    .multilineTextAlignment(.center)
                    .focused($isWriting)
                    .tint(.orange)
                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var burnButton: some View {
        Button(action: ignite) {
            Label("Burn", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(canBurn ? Color.white : Color.secondary)
                .padding(.vertical, 17)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(buttonFill))
        }
        .buttonStyle(.plain)
        .disabled(!canBurn)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        // Get out of the way while the page is burning.
        .opacity(burn == nil ? 1 : 0)
        .animation(.easeOut(duration: 0.35), value: burn == nil)
    }

    private var buttonFill: LinearGradient {
        LinearGradient(
            colors: canBurn
                ? [Color(red: 1.00, green: 0.44, blue: 0.10), Color(red: 0.82, green: 0.14, blue: 0.04)]
                : [Color.white.opacity(0.08), Color.white.opacity(0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.04, blue: 0.05), Color(red: 0.11, green: 0.05, blue: 0.03)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Burning

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canBurn: Bool {
        !trimmed.isEmpty && burn == nil
    }

    private func warmUp() {
        if hapticsEnabled { haptics.prepare() }
        if soundEnabled { sound.prepare() }
    }

    private func ignite() {
        let thought = trimmed
        guard !thought.isEmpty, burn == nil else { return }

        // Put the keyboard away first. The paragraph re-fits as the screen opens
        // up, and it should settle before the fire touches it — which also gives
        // the tap a beat of anticipation.
        isWriting = false
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            start(thought)
        }
    }

    private func start(_ thought: String) {
        guard burn == nil else { return }

        let duration = reduceMotion ? BurnCurve.reducedMotionDuration : BurnCurve.duration
        burn = BurnRun(
            text: thought,
            startedAt: .now,
            duration: duration,
            seed: .random(in: 0..<128)
        )

        // The sound comes in a beat after the fire, not with it — see
        // `SoundPlayer.burnLeadIn`. Haptics stay on the ignition frame: the thump
        // is the tap's acknowledgement.
        if soundEnabled { sound.play(after: SoundPlayer.leadIn(for: duration)) }
        if hapticsEnabled { haptics.play(duration: duration) }
    }

    private func finish(_ run: BurnRun) {
        // A newer burn may have replaced this one.
        guard burn?.id == run.id else { return }

        if keepsJournal {
            modelContext.insert(ReleasedThought(text: run.text, releasedAt: run.startedAt))
            try? modelContext.save()
        }

        // Deliberately no `sound.stop()` here. The clip is as long as the burn, so
        // now that it starts a beat late, stopping on the last frame would cut the
        // crackle off mid-sound. Letting it ring out over the cleared screen reads
        // as embers dying down. A burn cannot be interrupted — `ignite()` refuses
        // while one is in flight — so there is nothing to overlap with, and the
        // next `play` rewinds the same player anyway.
        //
        // The haptic pattern is duration-bounded so it has already run out, but
        // stopping releases the player — and actually cuts it short if this burn
        // was interrupted rather than finished.
        haptics.stop()
        // No animation needed: by now every pixel of the text is already gone.
        text = ""
        burn = nil
    }

    /// A burn in flight.
    private struct BurnRun: Identifiable {
        let id = UUID()
        let text: String
        let startedAt: Date
        let duration: TimeInterval
        let seed: Double
    }
}

#Preview {
    ComposeView()
        .modelContainer(for: ReleasedThought.self, inMemory: true)
        .preferredColorScheme(.dark)
}
