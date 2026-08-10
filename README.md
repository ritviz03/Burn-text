# Burn

An iOS app for letting go of a thought. Write down what's weighing on you, watch
it fill the screen, then tap **Burn** and watch it actually burn — a fire front
eats across the letters, embers lift off, the phone rumbles, and it's gone.

The burn is the whole point, so it gets the most engineering attention: a real
Metal shader, not a fade.

---

## Requirements

- macOS with **Xcode 15+**
- **iOS 17+** target (needed for SwiftUI Metal shader modifiers *and* SwiftData)
- A **physical device** to feel the haptics — they are silent on the Simulator
- No third-party dependencies. Everything is first-party Apple frameworks.

## Getting started

The Xcode project is generated rather than committed, so it never causes merge
conflicts. [XcodeGen](https://github.com/yonaskolb/XcodeGen) builds it from
`project.yml`:

```sh
brew install xcodegen   # once
xcodegen generate       # creates Burn.xcodeproj
open Burn.xcodeproj
```

Then set your team under **Signing & Capabilities** (or fill in
`DEVELOPMENT_TEAM` in `project.yml`) and hit Run.

<details>
<summary>No XcodeGen? Build the project by hand</summary>

1. Xcode ▸ File ▸ New ▸ Project ▸ **iOS App**
2. Name it `Burn`, Interface **SwiftUI**, Storage **SwiftData**, min deployment **iOS 17**
3. Delete the generated `ContentView.swift` and `BurnApp.swift`
4. Drag the `Burn/` folder into the project (Create groups, add to the `Burn` target)
5. Drag `BurnTests/` into a new **Unit Testing Bundle** target

Check that `Burn.metal` landed in **Build Phases ▸ Compile Sources** and
`burn-crackle.wav` and `Assets.xcassets` in **Copy Bundle Resources**.

</details>

Signing note: a free Apple ID runs the app on your own device (7-day
provisioning) and on the Simulator. TestFlight and the App Store need the paid
Apple Developer Program.

## Layout

```
Burn/
├─ BurnApp.swift              @main; builds the SwiftData container
├─ RootView.swift             the one screen, plus journal + settings sheets
├─ Models/ReleasedThought     @Model — text + timestamp, on device only
├─ Views/
│  ├─ ComposeView             write, tap Burn, run the burn, save, reset
│  ├─ BurnView                one clock → shader progress + ember field
│  ├─ JournalView             what's been let go; swipe to delete
│  └─ SettingsView            sound, haptics, keep-a-journal, clear
├─ Components/
│  ├─ FontFitter              measures + binary searches the largest fitting size
│  ├─ AutoSizingText          draws text at that size
│  └─ EmberParticles          sparks and smoke, one Canvas pass
├─ Effects/
│  ├─ Burn.metal              the dissolve shader
│  ├─ BurnField.swift         Swift mirror of the shader's constants
│  └─ BurnCurve.swift         duration + easing of the 0…1 timeline
├─ Haptics/BurnHaptics        one CHHapticPattern, handed over at ignition
├─ Audio/SoundPlayer          AVAudioPlayer, `.ambient` session
└─ Resources/                 asset catalog + burn-crackle.wav
```

## How the burn works

The classic **noise → step → alpha** dissolve, on the GPU:

1. `FontFitter` picks the largest point size at which the thought still fits the
   screen. `Text.minimumScaleFactor` only shrinks type; a short thought should
   also *grow*, so we measure candidates and binary search.
2. `TimelineView(.animation)` ticks every frame. Elapsed time becomes one eased
   `progress` value from 0 to 1 (`BurnCurve`).
3. `Burn.metal` builds a noise field over the view — four octaves of value noise,
   biased left-to-right so the page catches at a corner and a front travels
   across it. Per pixel it compares the field against an advancing threshold:
   - **behind the front** → fully transparent (ash)
   - **inside the band** → white-hot, then ember orange, then char
   - **ahead of it** → the original ink, untouched
4. `EmberParticles` draws sparks and smoke from the *same* progress value, using
   `BurnField.ignition(x:y:)` — the Swift mirror of the shader's sweep — so
   sparks light up where the fire actually is.
5. `BurnHaptics` hands CoreHaptics one pre-built pattern at ignition (a
   continuous rumble with an intensity curve, plus crackle transients) rather
   than streaming per-frame updates, so the rumble keeps time even if the render
   loop stutters.

Only pixels that already have ink are burned, which keeps the fire on the
letters instead of scorching a rectangle around them.

### Tuning knobs

| What | Where |
|---|---|
| Burn length | `BurnCurve.duration` |
| Easing | `BurnCurve.progress(elapsed:duration:)` |
| Front direction / raggedness | `kBurnSweepX`, `kBurnSweepY`, `kBurnSweepWeight` in `Burn.metal` |
| Glow band width | `BurnField.edgeBand` |
| Flame colours | `whiteHot` / `ember` / `charred` in `Burn.metal` |
| Spark count and behaviour | `EmberParticles.count`, `ember(index:seed:)` |
| Type size range | `FontFitter.minimumSize` / `.maximumSize` |

`BurnField.swift` and the `constant` block at the top of `Burn.metal` describe
the same field. Change one, change the other.

## Verify it on device

Run through this once on real hardware:

- [ ] Type one word — the type grows big. Type a paragraph — it steps down to fit.
- [ ] Tap **Burn**: the keyboard leaves, the text settles, *then* the fire starts.
- [ ] The front travels across the letters; sparks appear where it is, not elsewhere.
- [ ] Haptics ramp up and fade with the flame (device only).
- [ ] Sound plays, and respects the ring/silent switch.
- [ ] The thought lands in **Journal** with a timestamp; swipe deletes it.
- [ ] Turn **Keep a journal** off — burning saves nothing.
- [ ] Turn sound and haptics off — the burn is silent and still.
- [ ] Settings ▸ **Reduce Motion** on → a quick fade, no shader, no sparks.

Unit tests (`⌘U`) cover the font-fitting search, the burn easing, the ignition
field, and SwiftData save/delete. The effect itself is verified by eye.

### If the text doesn't dissolve cleanly

The one genuinely uncertain piece is applying an alpha-erasing `colorEffect`
directly to `Text`. `BurnView` calls `.drawingGroup()` first to flatten the
glyphs into a single layer, which is normally enough. If you see the text
disappear all at once, not at all, or with per-glyph seams, render it to an
image and dissolve that instead — same shader, more predictable compositing:

```swift
// In BurnView.dissolving(progress:), replace AutoSizingText + .drawingGroup()
// with an ImageRenderer snapshot taken once when the burn starts.
```

## Generated assets

Two files in `Burn/Resources/` are drawn/synthesised by scripts rather than
authored, so they can be regenerated and diffed:

| Asset | Script |
|---|---|
| `burn-crackle.wav` | `python3 Tools/make_burn_sound.py` |
| `Assets.xcassets/AppIcon.appiconset/AppIcon.png` | `python3 Tools/make_app_icon.py` |

Both are pure-stdlib Python (no Pillow, no numpy) and deterministic. The icon is
a flame silhouette evaluated per pixel and hand-encoded as PNG — deliberately
without an alpha channel, since iOS rejects app icons that carry one. Tune the
shape with the `RISE` / `FALL` / `WIDTH` constants at the top of the script.

## Replacing the sound

`Burn/Resources/burn-crackle.wav` is synthesised, not recorded — filtered noise
with an amplitude envelope and random crackle transients, generated by
`Tools/make_burn_sound.py` (deterministic; re-run it to regenerate). It's good
enough to develop against. Swap in a licensed or royalty-free recording of the
same length before shipping, keeping the filename, or update
`SoundPlayer.burnResource`.

## Not built yet

Accounts, sync, iCloud, widgets, notifications, onboarding, and localization.
