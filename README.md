# Burn

An iOS app for letting go of a thought. Write down what's weighing on you, then
drag a lit match across the words and burn them — letter by letter, wherever you
touch. Characters go white-hot, char, and lift away as embers; the phone rumbles
under your finger.

The burn is the whole point, so it gets the most engineering attention: the fire
follows your hand rather than playing a canned animation.

---

## Requirements

- macOS with **Xcode 15+**
- **iOS 17+** target (needed for SwiftData and the SwiftUI APIs used here)
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

Check that `burn-crackle.wav` and `Assets.xcassets` landed in **Copy Bundle
Resources**.

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
│  ├─ ComposeView             Write/Burn modes, the frame loop, the drag
│  ├─ BurnCanvas              draws every character at its own heat, plus embers
│  ├─ MatchStick              the draggable match; FlameShape
│  ├─ JournalView             what's been let go; swipe to delete
│  └─ SettingsView            sound, haptics, keep-a-journal, clear
├─ Components/
│  ├─ FontFitter              measures + binary searches the largest fitting size
│  └─ GlyphLayout             per-character frames, with word wrapping
├─ Effects/FireModel          per-glyph heat + ember simulation; SplitMix64
├─ Haptics/BurnHaptics        looped continuous pattern, modulated live
├─ Audio/SoundPlayer          looping crackle, volume tracks how much is alight
└─ Resources/                 asset catalog + burn-crackle.wav
```

## How the burn works

There is no timeline. The fire depends on where the flame has *been* — a path, not
a clock — so the app keeps a simulation and advances it every frame.

1. `FontFitter` picks the largest point size at which the thought still fits the
   screen. `Text.minimumScaleFactor` only shrinks type; a short thought should
   also *grow*, so we measure candidates and binary search.
2. `GlyphLayout` lays the text out one character at a time at that size, wrapping
   greedily by word, and hands back a frame for every character. `Text` cannot
   tell you where its glyphs are — it draws a paragraph as one block — and the app
   has to answer "what is the flame touching?" sixty times a second.
3. Dragging moves a flame point, held **`MatchStick.reach` above the fingertip**:
   a hand covers whatever it touches, and you need to see the word you are about
   to lose.
4. `FireModel.tick` heats every character within `ignitionRadius` of the flame,
   with a smoothstep falloff so the centre burns fastest. Past `selfSustain` a
   character is alight and **keeps burning without the flame** — otherwise letting
   go would leave half-lit characters stuck orange forever.
5. `BurnCanvas` draws each character at its own heat: ink → white-hot → amber →
   ember → char, fading and lifting only over the last stretch so you can still
   read what is going. A blurred additive pass underneath is what makes hot
   characters look *lit* rather than merely orange. Embers are drawn in the same
   pass.
6. `BurnHaptics` loops one short continuous pattern and modulates its strength
   with a dynamic parameter, so the rumble tracks how much is alight while staying
   on CoreHaptics' own clock. `SoundPlayer` loops the crackle the same way and
   fades out when the last character goes.
7. When every non-whitespace character is consumed, the thought is recorded and
   the page resets to the prompt. Embers get ~0.9s to finish first.

Whitespace is laid out but never drawn or burned — setting fire to a space should
not count as progress, and requiring it would mean a burn never completes.

With nothing typed, the prompt itself is what burns. It is the quickest way to
learn the gesture, and it is never journalled: it was not anybody's thought.

### Tuning knobs

| What | Where |
|---|---|
| Flame size / how much it catches at once | `FireModel.ignitionRadius` |
| How fast a character catches | `FireModel.heatRate`, `.selfSustain` |
| How long it takes to burn away | `FireModel.burnRate` |
| Spark and smoke density | `FireModel.emberRate`, `.emberLimit` |
| Flame colours | `BurnPalette` in `BurnCanvas.swift` |
| Match size, flame reach above the finger | `MatchStick.size`, `.reach` |
| Flame silhouette | `FlameShape.rise` / `.fall` |
| Type size range | `FontFitter.minimumSize` / `.maximumSize` |
| Sound level | `SoundPlayer.volume`, `.floorLevel` |

## Verify it on device

Run through this once on real hardware:

- [ ] Type one word — the type grows big. Type a paragraph — it steps down to fit.
- [ ] Tap **Burn**: the keyboard leaves and the match appears at the bottom.
- [ ] Drag across a word. Characters under the flame go hot and burn away; the ones
      you missed stay put.
- [ ] The flame sits *above* your fingertip, so you can see what you are burning.
- [ ] Let go mid-burn — lit characters finish burning on their own.
- [ ] Sparks come off the characters that are actually alight, not the whole page.
- [ ] Haptics track how much is burning and stop when it is out (device only).
- [ ] Sound loops while burning, fades when it stops, sits under the room, and
      respects the ring/silent switch.
- [ ] Burn everything → the thought lands in **Journal** and the prompt returns.
- [ ] Burn the prompt itself without typing → nothing is journalled.
- [ ] Tap **Write** mid-burn — the fire resets and the keyboard comes back.
- [ ] Turn **Keep a journal** off — burning saves nothing.
- [ ] Turn sound and haptics off — the burn is silent and still.
- [ ] Settings ▸ **Reduce Motion** on → text still burns, no flying embers.

Unit tests (`⌘U`) cover the wrapping and centring in `GlyphLayout`, the whole
`FireModel` simulation (ignition, self-sustain, spread limits, ember caps, frame
clamping), the font-fitting search, and SwiftData save/delete. How it *looks* is
verified by eye.

### Performance note

`BurnCanvas` resolves one `Text` per visible character per frame. For thoughts of
a sentence or two that is comfortable, and it buys per-character colour for free.
If a very long paragraph ever drops frames, cache the resolved text per
(character, quantised heat) rather than resolving every frame.

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
