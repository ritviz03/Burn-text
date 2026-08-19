//
//  ComposeView.swift
//

import SwiftUI

/// Write a thought, then burn it with a match you drag across the words.
///
/// Two modes, because a keyboard and a drag gesture cannot share a screen: in
/// **Write** the field is focused and the match rests at the bottom; in **Burn**
/// the keyboard goes away, the text is drawn character by character, and the match
/// follows your finger.
///
/// Nothing here is on a timer. The fire is a function of where the flame has been,
/// so a frame loop advances `FireModel` and the view simply draws whatever state
/// it is in.
struct ComposeView: View {
    private enum Mode { case writing, burning }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(Setting.soundEnabled) private var soundEnabled = true
    @AppStorage(Setting.hapticsEnabled) private var hapticsEnabled = true

    @State private var text = ""
    @State private var mode: Mode = .writing
    @State private var fire = FireModel()
    @State private var layout = GlyphLayout()
    @State private var fontSize: CGFloat = 44
    @State private var textOrigin: CGPoint = .zero
    @State private var box: CGSize = .zero
    /// Where the flame is, in `box` coordinates. `nil` when nothing is touching.
    @State private var flame: CGPoint?
    @State private var phase: Double = 0
    @State private var hasDragged = false
    @State private var haptics = BurnHaptics()
    @State private var sound = SoundPlayer()
    @FocusState private var isWriting: Bool

    /// Shared by the editor and the burning copy, so the type does not jump.
    private let fitter = FontFitter()

    static let prompt = "burn negative thought"

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// With nothing typed, the prompt itself is what burns — the quickest way to
    /// learn the gesture.
    private var isPlaceholder: Bool { trimmed.isEmpty }
    private var displayText: String { isPlaceholder ? Self.prompt : trimmed }

    var body: some View {
        ZStack {
            background
            page
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { modeToggle } }
        .onAppear {
            warmUp()
            isWriting = true
        }
        .task(id: mode) { await run() }
    }

    // MARK: - Page

    private var page: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                switch mode {
                case .writing: editor
                case .burning: burnStage
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onChange(of: proxy.size, initial: true) { _, size in
                box = size
                relayout()
            }
        }
        .padding(.horizontal, 24)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            TextField(Self.prompt, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(fitter.swiftUIFont(ofSize: fontSize))
                .foregroundStyle(BurnPalette.ink)
                .multilineTextAlignment(.center)
                .focused($isWriting)
                .tint(.orange)
                .onChange(of: text) { _, _ in relayout() }
            Spacer(minLength: 0)
        }
        .frame(width: box.width, height: box.height)
        .contentShape(Rectangle())
        .onTapGesture { isWriting = true }
    }

    private var burnStage: some View {
        ZStack(alignment: .topLeading) {
            BurnCanvas(
                layout: layout,
                fire: fire,
                font: fitter.swiftUIFont(ofSize: fontSize),
                origin: textOrigin
            )
            .frame(width: box.width, height: box.height)

            MatchStick(phase: phase, isLit: true)
                .allowsHitTesting(false)
                .position(MatchStick.centre(forTipAt: flame ?? restingTip))
                .animation(flame == nil ? .easeOut(duration: 0.45) : nil, value: flame == nil)

            if !hasDragged {
                hint
            }
        }
        .frame(width: box.width, height: box.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    hasDragged = true
                    // Hold the flame above the fingertip: a hand covers whatever
                    // it touches, and you need to see the word going.
                    flame = CGPoint(x: value.location.x, y: value.location.y - MatchStick.reach)
                }
                .onEnded { _ in flame = nil }
        )
    }

    private var hint: some View {
        Text("drag the match across your words")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(width: box.width)
            .position(x: box.width / 2, y: max(box.height - 132, 24))
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    /// Where the match sits when nobody is holding it.
    private var restingTip: CGPoint {
        CGPoint(x: box.width / 2, y: max(box.height - 58, 0))
    }

    private var modeToggle: some View {
        Button {
            switch mode {
            case .writing:
                isWriting = false
                hasDragged = false
                relayout()
                fire.reset(glyphCount: layout.glyphs.count)
                mode = .burning
            case .burning:
                stopFeedback()
                flame = nil
                fire.reset(glyphCount: layout.glyphs.count)
                mode = .writing
                isWriting = true
            }
        } label: {
            // Labelled with the mode you are going to, as in the reference.
            Text(mode == .writing ? "Burn" : "Write")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.04, blue: 0.05), Color(red: 0.09, green: 0.05, blue: 0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Layout

    private func relayout() {
        guard box.width > 1, box.height > 1 else { return }
        let size = fitter.fittedSize(for: displayText, in: box)
        let laid = GlyphLayout.make(
            text: displayText,
            font: fitter.font(ofSize: size),
            maxWidth: box.width
        )
        fontSize = size
        layout = laid
        textOrigin = CGPoint(x: 0, y: max((box.height - laid.size.height) / 2, 0))
        fire.resize(glyphCount: laid.glyphs.count)
    }

    // MARK: - The frame loop

    /// Advances the fire while in Burn mode, and closes the burn out when the last
    /// character goes. Cancelled automatically when the mode changes or the view
    /// disappears.
    private func run() async {
        guard mode == .burning else { return }

        var last = Date.now
        /// Counts down once everything has burned, so the embers get to finish.
        var settling: Double?

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }

            let now = Date.now
            let dt = now.timeIntervalSince(last)
            last = now
            guard dt > 0 else { continue }

            phase += dt
            // `origin` translates `layout`'s glyph frames into the same screen
            // space `flame` is already in — see the doc comment on `tick`.
            fire.tick(dt: dt, flame: flame, layout: layout, origin: textOrigin, reduceMotion: reduceMotion)
            updateFeedback()

            if settling == nil, fire.hasBurnedEverything(in: layout) {
                settling = reduceMotion ? 0.25 : 0.9
            }
            if var remaining = settling {
                remaining -= dt
                if remaining <= 0 {
                    finish()
                    return
                }
                settling = remaining
            }
        }
    }

    // MARK: - Feedback

    private func warmUp() {
        if hapticsEnabled { haptics.prepare() }
        if soundEnabled { sound.prepare() }
    }

    /// Fire is open-ended now, so the rumble and the crackle are held at a level
    /// that tracks how much is alight rather than played as a fixed pattern.
    private func updateFeedback() {
        let alight = min(Double(fire.burningCount) / 9.0, 1.0)
        if hapticsEnabled { haptics.setLevel(alight) } else { haptics.setLevel(0) }
        if soundEnabled { sound.setLevel(alight) } else { sound.setLevel(0) }
    }

    private func stopFeedback() {
        haptics.stop()
        sound.stop()
    }

    // MARK: - Finishing

    private func finish() {
        stopFeedback()
        flame = nil
        text = ""
        mode = .writing
        relayout()
        fire.reset(glyphCount: layout.glyphs.count)
        isWriting = true
    }
}

#Preview {
    NavigationStack {
        ComposeView()
    }
    .preferredColorScheme(.dark)
}
