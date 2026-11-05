# Playful theme: "Pond Day"

Status: implemented for build 92 (branch `feat/playful-theme`). Written 2026-11-04 against `main`.

## Implementation notes (build 92)

Where the shipped values differ from the tables below, and why:

- **Default appearance is `.light`**, not `.system`. `Theme.Appearance` now has three cases: `light` (Pond Day, the default), `system` and `dark` (Night Pond). People who picked `system` or `dark` in an earlier build keep their choice, because `@AppStorage` only falls back to the default when nothing is stored.
- **`critical` is `#A3246B` / `#FF8CCB`**, not `#A8235C` / `#FF8DB8`. The spec's berry sits at hue 334 to 337, which is only 23 to 26 degrees from Stop red, and its own proposed test asks for 30. The shipped berry is at hue 327 (light) and 327 (dark) and still clears 4.5:1 on every ground.
- **`actionInk` (orange as a word) in dark is `#FFA04F`**, not `#FF8A2E`. `#FF8A2E` is 4.20:1 on the dark selection wash; `#FFA04F` clears every dark ground (4.89:1 at the lowest). The orange FILL in dark is still `#FF8A2E`.
- **`textSecondary` is `#34454A` / `#CFE0E0`.** The spec names two text weights; the app uses three, so secondary sits between `textPrimary` and `textMuted` (`textTertiary`).
- **`lavenderInk` is `#6E5689`** so training text clears 4.5:1 on the selection wash.
- **Token names.** The old `actionSecondary` ("orange as text") is renamed `actionInk`. The new fills are `actionYellow`, `actionTeal` and `actionLavender` rather than `secondaryAction`/`tealAction`/`lavenderAction`, so no old call site can silently change meaning.
- **The transport Drive/Stop/Reset bar no longer exists** (build 92 removed it). The red disc is the only Stop on Play and the pill is the Stop on sheets; Stop red is used for nothing else.

## Why

The owner's note: the palette is "incredibly not on brand with microduck itself. Try to mimic the colors of the microduck pollen marketing pages or our own app icon (which is great). It should be a playful theme, easy to use, kid-friendly."

What the Play screen shows today (TestFlight screenshots, 2026-11-04):

- A near-black ground (`backgroundPrimary` dark `#0D1417`, and the stage clear colour `UIColor(white: 0.11)` = `#1C1C1C`).
- A grey 3D floor (`white: 0.30` deck, `0.42` and `0.62` grid lines).
- Duck Orange on every filled control: the four face buttons, Drive, Stop and Reset, and the Go button. When everything is the action colour, nothing is.
- Dark navy stick pads (`surfaceInteractive` dark `#132226`) that read as holes.
- A red Stop disc (`StopMetric.red` = `#DB1F1F`) next to an orange button that is also labelled Stop.

The hues in `Palette.swift` are already the icon's hues. The problem is how they are used: the app defaults to dark (`Theme.defaultAppearance = .dark`), it has no light ground anyone sees, and one accent does every job. The icon is the opposite: a bright teal sky, a cream shell, thick ink outlines, and orange, yellow and lavender each in one small place. This theme copies that arrangement.

## Where the colours come from

### Our app icon

`DuckStudio/Assets.xcassets/AppIcon.appiconset/icon-1024.png`, sampled with PIL (point samples plus a k-means cluster of the non-background pixels; the background is 64% of the image).

| Colour | Hex | Where in the icon | Share of the duck |
|---|---|---|---|
| Icon sky (teal) | `#75C6C7` | The whole background | 64% of the image |
| Ink | `#081317` / `#0C1619` | Every outline, the pupil, the neck and leg joints | 46% |
| Shell cream | `#F9EFDE` (`#FCF4E4` body, `#F6E8D1` head) | Head dome and body block | 23% |
| Beak orange | `#FE7B16` (cluster `#EF6F0D`) | Beak, upper feet | 13% |
| Beak shadow | `#CC4C00` | Underside of the beak | small |
| Eye yellow | `#FFAF09` (cluster `#FCAB0D`) | Eye ring | 8% |
| Foot yellow | `#FEBE1B` (cluster `#FDC21A`) | Soles of the feet | 1% |
| Wing lavender | `#B494C5` (cluster `#B393C4`) | Hip and wing pieces | 4% |
| Shell shade | `#E7D2B2` | Shaded side of the body | 2% |
| Joint grey | `#6A6C6E`, `#939091` | Servo horns | 3% |

### Pollen Robotics' Microduck pages

Source: `https://pollen-robotics.com/microduck/` and `https://pollen-robotics.com/microduck/press-kit/`. Hex values come from the page's inline CSS (counts are occurrences in the page).

| Colour | Hex | How the page uses it |
|---|---|---|
| Hero black | `#08080C` (106) | Hero background, text outlines, sticker borders |
| Ink | `#101018` (77) | Body text on cream, button borders |
| Duck orange | `#FF7A2F` (39) | Top app bar (`--AppBar-background`), tab underline, `--sunburst-tint`, primary button fill |
| Sunny yellow | `#FFD23F` (29) | Display headline colour, scrolling ticker band, secondary button fill |
| Hot pink | `#FF2FA8` (27) | Offset "sticker" shadows (`box-shadow: 9px 9px 0`), chromatic text shadow |
| Cyan | `#2FF0E6` (19) | Offset shadows, chromatic text shadow |
| Paper | `#FAF8F2` (16) | Light content sections |
| Cream chip | `#F2ECDD` (14) | Tags and chips with a 2px ink border |
| Lavender | `#9D87E8` (6) | Accent headline, card shadow |
| Orange ink | `#C2500A` (5) | Orange text on light |

The page's style is "sticker": flat fills, thick ink borders (2 to 4 px), and hard offset shadows. Display type is Anton, body is DM Sans. The Hugging Face org card (`https://huggingface.co/pollen-robotics`) uses a yellow to red gradient. The GitHub README (`https://github.com/pollen-robotics/microduck`) leads with a product shot of the four colourways.

### The physical duck

Sampled from Pollen's product images (`/assets/microduck/squad.webp`, `pack-robot.webp`, `stickers/duck-head-mark.webp`, and the GitHub README hero):

| Part | Hex (cluster) | Notes |
|---|---|---|
| Orange beak, band and feet | `#DE5A13`, `#F3590F`, `#F28A1C` | The orange in photos runs warmer and redder than the icon's |
| Yellow beak and head (yellow colourway) | `#F2CA2E`, `#F5B411`, `#F2A408` | The yellow head on the Practice duck in our stage |
| Sky-blue shell (teal colourway) | `#A0DBE4` | Close to the icon sky |
| Lavender shell | `#7D7AA7`, `#817A9E` | Duller than the icon's lavender |
| White or cream shell | `#ECE3D3`, `#DFDBCE` | Never pure white |
| Product backdrop | sky `#B0C5D6`, wooden desk `#CD925C` | |

The icon, the website and the hardware agree: a cream shell, an orange beak, yellow eye and feet, teal or sky, a little lavender, all held together by near-black ink. Nobody in that family uses a grey floor or a black page.

## Design rules

1. **Light first.** The default look is a bright pond-teal page with cream cards, like the icon. Dark is a "night pond" variant: deep teal-navy, never black.
2. **One orange per screen region.** Beak Orange is the primary action only. Every other filled control takes a different duck colour.
3. **Ink outlines, like the icon.** Every filled control gets a 2pt Icon Ink outline (`#10191C`). This is the icon's and Pollen's signature, and it also solves contrast: light fills like orange (2.33:1) and yellow (1.43:1) cannot carry a 3:1 boundary against a light page, but the outline is 15.9:1.
4. **Ink labels on bright fills.** Orange, yellow, teal, lavender and green fills all carry ink text (6.8:1 or better). White text appears on exactly one colour: Stop red.
5. **Stop is the only red.** One value, `#D92A2A`, in both schemes. It is the biggest red element on every screen, and no other token, prop or game piece uses red. Stop is also told apart without colour: it is the only white-on-colour control, the only disc in the top bar, and it always carries the square stop glyph. That matters because orange and red are close for people with protanopia (luminance ratio between them is only 1.87:1).
6. **Chunky, round, soft.** Bigger radii, a 3pt "lip" under pressable shapes that collapses on press, and soft blurred shadows. Headings and button labels in SF Rounded.

## The palette

Name, light hex, dark hex, source.

| Token | Light | Dark | Role | Source |
|---|---|---|---|---|
| `background` | `#E6F5F4` Pond Mist | `#10262B` Night Pond | Page ground, 3D stage sky | Icon sky `#75C6C7`, lightened (light) and taken to deep teal (dark) |
| `surface` | `#FFFBF2` Shell Cream | `#183338` | Cards, panels, the transport bar | Icon shell `#FCF4E4`, Pollen paper `#FAF8F2` |
| `surfaceRaised` | `#FFFFFF` | `#204048` | Sheets, popovers, the camera controls column, secondary buttons | White as elevation only |
| `selection` | `#CDEBE9` | `#1F4950` | Selected segment and row wash (always with a mark too) | Icon sky, tinted |
| `primaryAction` | `#FF7A1A` Beak Orange | `#FF8A2E` | The one main action: Drive, Go, the A button | Icon beak `#FE7B16`, Pollen `#FF7A2F` |
| `primaryActionLip` | `#CC4C00` | `#B84A00` | 3pt lip under a primary fill | Icon beak shadow `#CC4C00` |
| `secondaryAction` | `#FFC328` Sunny Feet | `#FFC93D` | Second-tier filled actions: Reset, chips, Y button | Icon feet `#FEBE1B`, Pollen `#FFD23F` |
| `tealAction` | `#75C6C7` Icon Sky | `#7FD3D3` | X button, selected-mode fill, brand moments | Icon background |
| `lavenderAction` | `#B494C5` Wing Lavender | `#C4A8D8` | B button, training, stick pads' rim in dark | Icon wing `#B494C5`, Pollen `#9D87E8` |
| `onFill` | `#10191C` | `#10191C` | Label and glyph on every bright fill | Icon ink `#081317`, Pollen ink `#101018` |
| `outline` | `#10191C` | `#0A1416` | 2pt outline on every filled control (in dark it reads as a crisp shadow; the fills carry their own contrast) | Icon outlines |
| `stickPad` | `#EEE6F6` Lavender Cloud | `#2B2D4A` | Thumb pad well | Icon wing lavender, very pale (light) or dusk (dark) |
| `stickPadRim` | `#10191C` (2pt) | `#9C8CC8` (2pt) | Pad outline | |
| `stickKnob` | `#FFC328` with ink outline and a white catchlight | `#FFC93D` | The thumb knob, drawn as the duck's eye | Icon eye ring |
| `textPrimary` | `#10191C` | `#FFF6E6` | Body text, titles | Icon ink, icon cream |
| `textMuted` | `#4A5B60` | `#A7C4C6` | Captions, pad labels, hints | Ink, lifted toward teal |
| `tealInk` | `#2B6E70` | `#7FD3D3` | Teal used as text or links; focus ring in light | Icon sky, darkened to text weight |
| `orangeInk` | `#A84B05` | `#FF8A2E` | Orange as text (the tab tint, links) | Pollen orange ink `#C2500A`, darkened |
| `success` (live) | fill `#3DBE74`, text `#1D7344` | `#5ED39A` | Connected and live dots, "done" | Not in the brand; a leaf green that stays clear of teal |
| `warning` | fill `#FFC328`, text `#8A5B00` | `#FFC93D` | Low battery, "check this" | Feet yellow; ink version for text |
| `critical` (error text) | `#A8235C` Berry | `#FF8DB8` | Refusals and error text | Chosen at hue 334 so it is never mistaken for Stop (hue 0) |
| `stop` | `#D92A2A` | `#D92A2A` | Emergency stop disc only, with white glyph, 3pt white ring and 2pt ink outer outline | Owner rule |
| `focus` | `#10191C` | `#FFC93D` | 3pt focus ring, 2pt offset | |
| `separator` | `#C3DCDA` | `#2E5258` | Hairlines (decoration only) | |

### Face buttons and transport bar (the Play screen)

| Control | Fill | Label |
|---|---|---|
| A | `primaryAction` orange | ink |
| B | `lavenderAction` | ink |
| X | `tealAction` | ink |
| Y | `secondaryAction` yellow | ink |
| Drive / Pause | `primaryAction` orange | ink |
| Stop (transport, zeroes the command) | `surfaceRaised` white, ink outline | ink, `stop.circle` glyph in ink |
| Reset | `secondaryAction` yellow | ink |
| Stop disc (top bar) | `stop` red | white |
| Go (Tell and Auto) | `primaryAction` orange | ink |
| Suggestion chips (Stand Up, Sit Down) | `surface` cream, ink outline | ink, glyph in `orangeInk` |
| Mode switch (Drive, Tell, Auto) | `surface` track, selected segment `tealAction` | ink |

The transport Stop does stop the duck (it calls `halt()`), so it must never look disabled or quiet. White with an ink outline is the most "plain button" look in the set and stays obvious, but it does not borrow the emergency red. If the owner would rather the two stops look alike, the alternative is to drop the transport Stop and let the disc be the only one; giving both the same red would break the "one red" rule.

### 3D practice floor

The duck is cream and white with a yellow head, and the ball is orange. A teal playmat makes all three pop and matches the icon's sky.

| Element | Light | Dark | Today |
|---|---|---|---|
| Sky (stage clear colour) | `#E6F5F4` (= `background`) | `#10262B` (= `background`) | `UIColor(white: 0.11)` |
| Deck (playmat) | `#A8DCD9` | `#1F4A50` | `UIColor(white: 0.30)` |
| Minor grid | `#93D0CC` | `#2A5C62` | `UIColor(white: 0.42)` |
| Major grid | `#6DB9B5` | `#3D767C` | `UIColor(white: 0.62)` |
| Origin and heading marker | `#FF7A1A` | `#FF8A2E` | `UIColor(red: 1, green: 0.45, blue: 0.2)` |
| Blocks and props | `#F9EFDE` shell cream, roughness 0.9 | same | `UIColor(red: 0.62, green: 0.56, blue: 0.48)` |
| Walls | `#B494C5` lavender | `#7D6E9E` | `UIColor(red: 0.44, green: 0.48, blue: 0.56)` |
| Ball | `#FF7A1A` | `#FF8A2E` | `.systemOrange` |
| Contact shadow | `#10191C` at 35% | black at 55% | `white: 0.02, alpha: 0.55` |
| Fill light tint | `#FFF6E6` (warm) | `#CFE6FF` | `(0.8, 0.86, 1)` |

Labels drawn over the floor ("Move", "Turn") stay legible on the deck (`textMuted` on `#A8DCD9` is 4.70:1; `textPrimary` is 11.80:1), but they should still sit on a `surface` chip because the 3D view can show anything behind them.

## Shape, depth and type

- **Radii** (change `Palette.Radius`): chip 6 to 10, control 10 to 16, card 14 to 22, group 20 to 28, sheet 28 to 32. Buttons stay capsules.
- **Outline:** 2pt `outline` on every filled control, card in the controller overlay, stick pad and the Stop disc (outside its white ring).
- **Lip:** a 3pt solid offset below each filled control in a darker shade of its fill (`primaryActionLip` for orange; for yellow `#D99A00`, teal `#4FA3A4`, lavender `#8F70A3`). On press the label and fill move down 3pt and the lip disappears. This is the "chunky toy button" feel and it replaces the current brightness change.
- **Soft shadow** under cards and the transport bar: light `#10191C` at 12%, y 4, blur 12; dark black at 40%, y 4, blur 16. No hard offset neon shadows (the Pollen site uses them, but on a phone they compete with the 3D stage).
- **Type:** SF Rounded (`.fontDesign(.rounded)`) for titles, section headings, button labels and the face-button letters, at system text styles so Dynamic Type still works. Body text can stay SF Pro, or go rounded too; both are legible. Heavier weights for labels on fills (`.headline` bold). No bundled fonts.

## Contrast table

WCAG 2.x relative-luminance ratios, computed with the standard formula (script in the scratchpad, results below). Body text needs 4.5:1; large text and button labels need 3:1 (all labels below clear 4.5 anyway); a control's boundary needs 3:1 (SC 1.4.11).

### Text on grounds

| Pair | Light | Dark |
|---|---|---|
| `textPrimary` on `background` | 15.90 | 14.67 |
| `textPrimary` on `surface` | 17.26 | 12.47 |
| `textPrimary` on `surfaceRaised` | 17.83 | 10.37 |
| `textPrimary` on `stickPad` | 14.67 | 12.41 |
| `textPrimary` on `selection` | 14.14 | 9.20 |
| `textPrimary` on floor deck | 11.80 | 9.09 |
| `textMuted` on `background` | 6.34 | 8.51 |
| `textMuted` on `surface` | 6.88 | 7.23 |
| `textMuted` on `surfaceRaised` | 7.10 | 6.01 |
| `textMuted` on `stickPad` | 5.85 | 7.20 |
| `textMuted` on `selection` | 5.63 | 5.34 |
| `textMuted` on floor deck | 4.70 | 5.27 |
| `tealInk` on `background` | 5.25 | 9.11 |
| `tealInk` on `surface` | 5.70 | 7.75 |
| `tealInk` on `selection` | 4.67 | n/a |
| `orangeInk` on `background` | 5.10 | 6.69 |
| `orangeInk` on `surface` | 5.53 | 5.69 |
| `orangeInk` on `surfaceRaised` | 5.72 | n/a |
| `success` text on `background` | 5.22 | 8.44 |
| `success` text on `surface` | 5.67 | 7.17 |
| `warning` text on `background` | 5.24 | 10.25 |
| `warning` text on `surface` | 5.68 | 8.71 |
| `critical` on `background` | 6.12 | 7.31 |
| `critical` on `surface` | 6.64 | 6.21 |

All pass AA for body text.

### Labels on fills

| Pair | Light | Dark |
|---|---|---|
| `onFill` on `primaryAction` | 6.84 | 7.58 |
| `onFill` on pressed orange `#E8670C` | 5.41 | n/a |
| `onFill` on `secondaryAction` | 11.11 | 11.61 |
| `onFill` on `tealAction` | 9.05 | 10.32 |
| `onFill` on `lavenderAction` | 6.78 | 8.44 |
| `onFill` on `success` fill | 7.48 | 9.56 |
| white on `stop` `#D92A2A` | 4.87 | 4.87 |

All pass AA for body text, so they pass large-text AA for buttons with room to spare.

### Boundaries (3:1 for controls)

| Pair | Light | Dark | Verdict |
|---|---|---|---|
| `primaryAction` fill on `background` | 2.33 | 6.69 | Light fails alone; the 2pt ink outline carries it (15.90) |
| `secondaryAction` fill on `background` | 1.43 | 10.25 | Same: outline carries it in light |
| `tealAction` fill on `background` | 1.76 | 9.11 | Same |
| `lavenderAction` fill on `background` | 2.35 | 7.45 | Same |
| `success` fill on `background` | 2.12 | 8.44 | A dot always has a word beside it |
| `outline` on `background` | 15.90 | n/a | Pass |
| `outline` on floor deck | 11.80 | n/a | Pass |
| `stop` on `background` | 4.34 | 3.23 | Pass |
| `stop` on floor deck | 3.22 | 2.00 | Dark fails alone; the white ring (15.74 on dark) and ink outline carry it |
| `stickPad` on `background` (dark) | n/a | 1.18 | Rim `#9C8CC8` carries it: 5.25 on ground, 4.44 on the pad |
| `focus` on `background` | 15.90 | 10.25 | Pass |
| `focus` on `surface` | 17.26 | 8.71 | Pass |
| orange vs Stop red | 1.87 | 2.07 | Colour alone does not separate them; label colour (ink vs white), shape and glyph do |

## Migration plan

The app already has the right architecture for this: every colour value lives in `StudioKit/Sources/StudioKit/Palette.swift`, `swift test` checks contrast in `PaletteTests.swift`, and `DuckStudio/Sources/Theme.swift` only maps tokens to `Color`. A palette swap is mostly a values change in one file plus the tests that pin today's values. The work below should land on a branch cut from `main` after `feat/build-92` merges, because that branch is editing the views listed here.

### 1. Token values: `StudioKit/Sources/StudioKit/Palette.swift`

- Brand constants (lines 165 to 183): `microduckTeal` `#69C7C8` to `#75C6C7` (icon sample); `duckOrange` `#FF7A12` to `#FF7A1A`; `lensYellow` `#FFB51B` stays as the eye, add `feetYellow` `#FFC328`; `warmCream` `#F6F0E4` to `#FFFBF2`; `microduckLavender` `#A98BCD` to `#B494C5`; `mechanicalCharcoal` `#111A1D` to `#10191C`. Add `pondMist` `#E6F5F4`, `nightPond` `#10262B`, `stopRed` `#D92A2A`, `berry` `#A8235C`.
- Inks (lines 194 to 214): `orangeInk` to `#A84B05`, `tealInk` to `#2B6E70`, `yellowInk` to `#8A5B00`, `greyInk` (tertiary) to `#4A5B60`. Update the ratios quoted in the doc comments.
- `Token` enum (line 239): add `secondaryAction` fill semantics (today `actionSecondary` is "orange as text"; rename that to `actionInk` and use `actionSecondary` for the yellow fill), plus `tealAction`, `lavenderAction`, `onFill`, `outline`, `stickPad`, `stickPadRim`, `stop`, `stageSky`, `stageDeck`, `stageGridMinor`, `stageGridMajor`. Classify each in `isText`, `isFill`, `isTextGround`, `takesEveryTextToken`.
- `color(_:in:)` (lines 391 to 470): new values from the palette table above. `backgroundPrimary` becomes Pond Mist / Night Pond; `backgroundSecondary` becomes `#D8EEEC` / `#0B1D21`; `surfaceInteractive` becomes `selection`; `critical` becomes Berry; `separator` per table.
- `fillEdge` (line 492): instead of "orange in light only", return `outline` for every fill in light (and `stickPadRim` for the pad in dark).
- `Radius` (lines 538 to 548): new values from "Shape, depth and type".

### 2. Tests: `StudioKit/Tests/StudioKitTests/PaletteTests.swift`

These pin today's specific values or claims and will need rewriting, not just new numbers: `testDuckOrangeOnCreamIsTheOnlyFillThatBorrowsAnEdge` (208), `testNotOneBrandAccentIsLegibleAsTextOnWarmCream` (231), `testOnCreamTheBrandAccentsDoNotEvenReachTheShapeBar` (251), `testTheGreyTheBriefSpecifiedForLightTertiaryTextWasBelowTheBar` (284), `testTheDarkGreyTheBriefSpecifiedMissedTheElevatedSurface` (309), `testTheInkVariantsMatchTheirDocumentedRatios` (474), `testTheActionColourIsDuckOrangeInBothSchemes` (508), `testANestedShapeTakesExactlyTheNextRadiusDown` (628). Add: `testStopRedIsUsedByNoOtherToken`, `testEveryLabelOnAFillIsInkExceptStop`, `testEveryLightFillHasAnInkOutline`, `testCriticalHueIsAtLeast30DegreesFromStop`.

### 3. Mapping and defaults: `DuckStudio/Sources/Theme.swift`

- Add `static let` mappings for each new token (next to lines 70 to 175).
- Line 333: `defaultAppearance = .dark` to `.system`, and change `Appearance` to offer `system`, `light`, `dark` only if the owner wants a pinned light. The comment above it says the default moves to `.system` "the day the count reaches sixty-one" designed screens; this theme is that change, so it should ship with a pass over the screens below.
- Line 352: `.tint(Theme.actionSecondary)` to `.tint(Theme.actionInk)` (the renamed orange-as-text token).
- Add `.fontDesign(.rounded)` in `MicroduckTheme.body` (line 345 onward), or apply it to headings and buttons only.

### 4. Components: `DuckStudio/Sources/DesignComponents.swift`

- Line 110 `DesignFixed.onAction`: becomes `Theme.onFill` (same ink value; make it a token so the tests see it).
- Lines 344 to 420 `PrimaryActionStyle`: take a `fill` parameter (orange, yellow, teal, lavender, raised) instead of always `Theme.actionPrimary`; draw the 2pt outline always in light; add the 3pt lip and the press-down offset in place of `.brightness(pressDelta)`. Keep `.primaryAction`, `.primaryActionMoves`, `.primaryActionPad` and add `.secondaryAction*` and `.faceButton(_:)`.

### 5. Play screen: `DuckStudio/Sources/DriveView.swift` (line numbers from `main`; `feat/build-92` moves them)

- 2402: face buttons `.buttonStyle(.primaryActionPad)` to `.faceButton(.a/.b/.x/.y)` with the four fills.
- 3072 Drive: stays `.primaryActionMoves` (orange).
- 3102 transport Stop: `.primaryActionMoves` to `.raisedActionMoves` (white, ink outline, ink glyph).
- 3124 Reset: `.primaryActionMoves` to `.secondaryActionMoves` (yellow).
- 4279 `ThumbPad`: `pad.fill(Theme.surfaceInteractive)` to `Theme.stickPad`, rim `Theme.stickPadRim` 2pt; `JointNode` knob drawn as the yellow eye.
- 1194, 1715: `.ultraThinMaterial` capsules to `Theme.surface` with soft shadow (frosted glass over a bright teal floor reads as grey).
- 2347: mode-switch selection `Theme.surfaceInteractive` to `Theme.tealAction` fill with ink label.

### 6. Stop: `DuckStudio/Sources/StopPill.swift`

- 181: `StopMetric.red = Color(red: 0.86, green: 0.12, blue: 0.12)` to `Theme.stop` (`#D92A2A`). This is the only place the value should exist.
- 139, 142, 167, 169, 170: keep white glyph and white ring; add a 2pt `Theme.outline` stroke outside the ring.

### 7. Hard-coded colours that bypass tokens

A grep of `DuckStudio/Sources` on `main` finds 85 literal colour constructors (`Color(red:`, `UIColor(red:`, `UIColor(white:`, `.init(white:`) and about 90 system-named colours (`.orange`, `.systemYellow`, `.black.opacity`). Most are in the 3D scenes and the soccer game. The ones that matter for this theme:

**Practice stage (`DuckStage.swift`), replace with stage tokens:**

- 441 sky `.init(white: 0.11)` to `stageSky`
- 463 fill light `(0.8, 0.86, 1)` to warm `#FFF6E6` in light
- 473 contact shadow `white: 0.02, alpha: 0.55` to `outline` at 35% (light)
- 675 deck `white: 0.30` to `stageDeck`
- 680, 681 grid `white: 0.42`, `0.62` to `stageGridMinor`, `stageGridMajor`
- 709, 714 origin and heading marker `(1, 0.45, 0.2)` to `primaryAction`
- 738, 739 ball `.systemOrange` and prop `white: 0.55` to `primaryAction` and shell cream
- 785 block `(0.62, 0.56, 0.48)` to shell cream `#F9EFDE`
- 789 wall `(0.44, 0.48, 0.56)` to lavender
- 828 `(1, 0.78, ...)` target marker and 897 `(0.35, 0.75, ...)` path marker to `secondaryAction` and `tealAction`
- 613, 614, 628 goal posts and pitch lines: keep white; on a light deck add an ink edge or use `#FFFFFF` at full opacity

**AR stage (`ARDriveStage.swift`):** 461 `(1, 0.45, 0.2)` to `primaryAction`; 483 `(0.35, 0.75, 1)` to `tealAction`; 501 white stays.

**Controller and sheets (status dots):**

- `ControllerView.swift` 103 `.green`, 104 `.orange`, 105 `.gray` to `success`, `warning`, `textMuted` (orange must not mean "connecting" when it means "press me")
- `ControllerView.swift` 93, 158, 218 `.ultraThinMaterial` to `surface`
- `DuckSheetView.swift` 113, 114 `.green` / `.gray` to `success` / `textMuted`
- `ShootLabView.swift` 115, 117 `Color.black.opacity(0.55)` and `.white` to a `surface` chip with `textPrimary`
- `DuckCameraView.swift` 182 `.thinMaterial` to `surface`

**Mini-games, red and orange conflicts:**

- `SlalomView.swift` 388 `.systemRed` (missed gate) to `critical` Berry: red is Stop only
- `SlalomView.swift` 367, 389 `.systemYellow` to `secondaryAction`
- `DuckGolfView.swift` 375 `.systemGreen` to `success`
- `FetchView.swift` 288 `.systemOrange` to `primaryAction`
- `DuckSoccerView.swift` HUD overlays 113 to 385 (`.white`, `.black.opacity(0.55)`, `.yellow`, `.teal`, `Color.secondary`), 643 `Color.green`, 801 to 1029 banner colours, 1347 and 1621 `.color(.black)` sky, 1811, 1824, 1837, 2022 to 2025, 2089 to 2111 `.systemYellow` / `.systemTeal` / `.systemGreen` / `.systemOrange` team and prop colours, 1765 net mesh. Map the team colours to `secondaryAction` (home) and `tealAction` (away), the HUD scrims to `surface` chips, and the sky to `stageSky`.

**Leave as they are (deliberate environment skins or camera backgrounds):**

- `SoccerStadium.swift` (36 literals: stadium skins `pastel`, `vaporwave`, `arcade`, `saturday`), but change line 35 and 36 `homeGoal`/`awayGoal`/`ball` to the tokens above so the ball is the same orange everywhere.
- `DuckLabStage.swift` 158 to 191 (`meadow`, `dusk`, `arcade`, `alpine`, `park` stage themes). Consider adding a `pond` theme from the stage table and making it the default.
- `BowBridgeScene.swift` (7 literals, a scene).
- `PoseCaptureView.swift` 577, 616, 671 and `MacARKitStandIn.swift` 100: black camera backgrounds, correct as black.
- `MyMicroduckView.swift` 613 and `SimHeadCameraRenderer.swift` 105: they turn data (colourway RGB, rendered pixels) into colours, not styling.

### 8. Asset catalog: `DuckStudio/Assets.xcassets`

- `AccentColor.colorset/Contents.json` holds `#FF7A2F` (light) and `#FF8B3A` (dark). `project.yml` sets no `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`, and no Swift code reads it, so it only affects places the system picks it up by default. Set it to `orangeInk` (`#A84B05` light, `#FF8A2E` dark) so any system control that falls back to it sets readable orange text, or delete it and rely on `.tint` in `Theme.swift`. Do not add per-token colour sets: `Theme.swift` explains why values live in `Palette.swift`, where tests can reach them.
- `AppIcon.appiconset`: no change. The theme is built from it.
- Optional: a `LaunchBackground` colour set at `#E6F5F4` / `#10262B` so the launch screen matches the first frame, if the launch screen is configured to use one.

### 9. Order of work

1. `Palette.swift` values, new tokens, and `PaletteTests.swift` (runs on the Pi with `swift test` in `StudioKit`).
2. `Theme.swift` mappings, tint, rounded type. Default stays `.dark` until step 5.
3. `DesignComponents.swift` button styles with outline and lip; `StopPill.swift`.
4. `DriveView.swift`, `DuckStage.swift`, `ControllerView.swift`, `DuckSheetView.swift` (the Play screen and its stage).
5. Flip `defaultAppearance` to `.system` once the Play, Moves and Studio tabs have been looked at in light on a device.
6. Mini-games and soccer.
7. Compile-check with `xcodebuild archive ... CODE_SIGNING_ALLOWED=NO`, then fold into the next planned TestFlight build rather than a build of its own.
