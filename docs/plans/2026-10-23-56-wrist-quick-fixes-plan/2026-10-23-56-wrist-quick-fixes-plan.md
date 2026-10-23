# Feature: 56 — wrist quick fixes: coloured buttons before the first sync, the food Crown, a bigger rest clock

> Status: BUILT, PROVED, DOCUMENTED AND REVIEWED 2026-10-23 (uncommitted; evidence and review beside the plan; owner device checks open, QA step 20). Owner: watch audit 3 (2026-10-23), fix order item 1, in chat. Series: with plan 57 (an empty Free workout can be cancelled). Base commit: `.work/2026-10-23-56/base.txt`. Working branch: the one checked out; never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 56 |
|---|---|---|
| Open the watch app before it has ever synced with the phone | every main button (routine, Log, rating pick, Log set) is grey | the same buttons wear the phone's default theme colour (Abyssal Neon cyan, `#2DE2E6`) with dark labels; after the first sync they wear the phone's real theme as today |
| The phone sends a theme colour the wrist cannot read (too dark, malformed) | grey buttons | the same cyan default |
| Turn the Crown on a food's portion screen | turning "up" (the direction that raises a set's reps on the logging screen) lowers the portion | turning that same direction raises the portion by half a serving per click (0.5 to 10 bounds unchanged) |
| Look at the rest screen | the rest clock is a small `title3` number | the rest clock is as large as the work clock on the logging screen (`largeTitle`, monospaced digits) |

Not changed: the Log button, confirm tap, the + / − buttons, portion bounds, the work clock, the ping, anything on the phone.

## Decision Ledger

- D-1 The wrist's default accent is the phone's default theme accent: `WatchAccent.fallbackHex = "#2DE2E6"` (`abyssalNeon`, `watch/contract/watch_accent_contract.json`, `lib/state/settings/settings_state.dart:79`). New `public static func worn(hex: String?) -> WatchAccent` in `WatchAccent.swift`: `usable(hex: hex) ?? usable(hex: fallbackHex)` (the fallback clears the 3.0 floor: contrast 13.13), returning the fallback when `usable` is nil. `usable(hex:)` is unchanged (its tests S-3712 stay).
- D-2 `ContentView.swift:401` becomes `.environment(\.watchAccent, WatchAccent.worn(hex: host.preferences.accentColorHex))`. `WatchAccentKey.defaultValue` (`WatchAccentStyle.swift`) becomes `WatchAccent.worn(hex: nil)` so a surface outside the root (previews) is cyan too. `watchProminent()` keeps its two branches (the nil branch is now only reachable by a test that injects nil); its header comment and the one in `ContentView.swift:398-400` are rewritten to say "no phone accent yet = the phone's default theme". The logger's armed-row outline (`WatchLoggingView.swift:254`, `accent?.color ?? Color.white`) therefore also wears cyan before the first sync; that is intended.
- D-3 `ios/OmniTrain Watch App/Assets.xcassets/AccentColor.colorset/Contents.json` gets the same colour as an explicit sRGB entry (components `0.176`, `0.886`, `0.902`, alpha `1.000`; `45/255`, `226/255`, `230/255`) so the system tint (bordered buttons, progress spinner, toggles) is not the empty-asset grey either.
- D-4 The Crown direction of the food portion follows the logger: positive Crown movement raises the value. The sign and detent math moves out of the watchOS-only model into a pure `enum WatchPortionCrown` (new file `WatchPortionCrown.swift`, platform-independent) so `swift test` can see it: `static func turn(from previous: Double, to position: Double) -> (detents: Int, position: Double)` where `detents = Int(((position - previous) / WatchMetricStepping.pointsPerDetent).rounded(.towardZero))` and `position = position - Double(detents) * WatchMetricStepping.pointsPerDetent`. Current code (`WatchNutritionView.swift:72-79`): `let rising = -(points - crownPosition)`; `let whole = (rising / Self.pointsPerDetent).rounded(.towardZero)`; `crownPosition = points + whole * Self.pointsPerDetent` — the minus sign is the bug; the "hand the Crown back a position near zero" part is kept (it keeps the `isContinuous` wrap at ±20 from ever being reached). `WatchNutritionModel.turn(to:)` calls the helper, stores `position` in `crownPosition`, and calls `state.stepPortion(detents)` when `detents != 0`. No new carry logic (the Crown delivers whole detents at `by: 1`).
- D-5 The rest clock (`WatchRestView.swift:72-74`, `Text(elapsed).font(.title3).fontWeight(.bold)`) becomes `.font(.largeTitle).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)`; the work readout (`WatchLoggingView.swift:129-131`) is `.largeTitle` + `.monospacedDigit()`. The governor measures the 40 mm layout (the rest screen also holds a caption, two 2-line labels and the Next button) before the unit closes; if it overflows, the fix is the labels' `lineLimit`, not a smaller clock.

## Readers listed

- `WatchAccent.usable(hex:)` callers: `ContentView.swift:401` (changes), `WatchAccentTests.swift:103,168-177`, `WatchRestPingTests.swift:526` (unchanged API).
- Source-text readers: `WatchRestLabelsTests.swift:305` and `WatchLoggedHapticTests.swift:171` read `WatchRestView.swift`; `WatchNutritionWiringSourceTests.swift` and `WatchCrownUnitTests.swift:128-175` (S-7504/S-7505) read `WatchNutritionView.swift` and `ContentView.swift`; S-7504 requires the line `static let pointsPerDetent` in `WatchNutritionView.swift` to borrow `WatchMetricStepping.pointsPerDetent`; the Crown call keeps `by: WatchNutritionModel.pointsPerDetent`.
- Scenario ids S-8601..S-8620 checked free (grep over `test docs watch lib`, 2026-10-23).
- `WatchNutritionModel` is watchOS-only: no package test constructs it; it is covered by the helper tests and one source guard.

## Core scenarios

`WatchAccentTests.swift` (add):
- S-8601 `WatchAccent.worn(hex: nil)` equals `WatchAccent(hex: "#2DE2E6")` and `labelIsDark` is true. Fails without the change (`worn` does not exist; with a nil-returning stub it fails the equality).
- S-8602 `worn(hex: "teal")` and `worn(hex: "#010203")` (malformed, too dark) equal the fallback.
- S-8603 for every row of `watch_accent_contract.json` (six themes), `worn(hex: row.hex)` equals that row's own accent, not the fallback (kills an "always cyan" mutant: five rows are not cyan).
- S-8604 source guard: `ContentView.swift` contains `WatchAccent.worn(hex: host.preferences.accentColorHex)` on the `.environment(\.watchAccent,` line and no `WatchAccent.usable(`; `AccentColor.colorset/Contents.json` parses and its first colour has `color-space` `srgb` and green component `0.886`.

`WatchPortionCrownTests.swift` (new):
- S-8611 `turn(from: 0, to: 1)` is `(detents: 1, position: 0)`; S-8612 `turn(from: 0, to: -1)` is `(-1, 0)` (a sign-flip mutant fails both).
- S-8613 `turn(from: 0, to: 0.4)` is `(0, 0.4)`; S-8614 `turn(from: 0.4, to: 1.4)` is `(1, 0.4)` (accuracy 1e-9); S-8615 `turn(from: 0, to: 3)` is `(3, 0)`.
- S-8616 source guard on `WatchNutritionView.swift`: the body of `func turn(to points: Double)` contains `WatchPortionCrown.turn(from: crownPosition, to: points)` and `state.stepPortion(` and does not contain `-(`.

`WatchRestSurfaceTests.swift` (add):
- S-8621 source guard: in `WatchRestView.swift` the `Text(elapsed)` modifier chain contains `.largeTitle` and not `.title3`; `WatchLoggingView.swift`'s `Text(readout)` chain contains `.largeTitle` too (the two clocks cannot drift apart again).

## Phases

All phases: `crew-builder-watch`, serial (one Swift package), run in order P1, P2, P3. Every builder brief opens with "Never run the full `flutter test`", carries "write the report first as a skeleton", and the Done list is `swift test --filter WatchSessionEngineTests` from `watch/watchos` plus the named filtered suites.

- P1 (≤6 items) accent default: `WatchAccent.swift` (`fallbackHex`, `worn`), `WatchAccentStyle.swift` (default value + comment), `ios/OmniTrain Watch App/ContentView.swift` (line 401 + comment 398-400), `AccentColor.colorset/Contents.json`, `WatchAccentTests.swift` S-8601..S-8604. Scope: `watch/watchos/Sources/WatchSessionEngine/WatchAccent.swift`, `.../WatchAccentStyle.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchAccentTests.swift`, `ios/OmniTrain Watch App/ContentView.swift`, `ios/OmniTrain Watch App/Assets.xcassets/AccentColor.colorset/Contents.json`.
- P2 (≤5 items) food Crown: new `WatchPortionCrown.swift`, `WatchNutritionView.swift` (`turn(to:)`, `select`/`deselect` unchanged), new `WatchPortionCrownTests.swift` S-8611..S-8616. Scope: those three files. Done also runs `--filter WatchCrownUnitTests` and `--filter WatchNutritionWiringSourceTests`.
- P3 (≤3 items) rest clock: `WatchRestView.swift` Text(elapsed), `WatchRestSurfaceTests.swift` S-8621. Done also runs `--filter WatchRestLabelsTests` and `--filter WatchLoggedHapticTests`.
- P4 `crew-docs-keeper`: the docs that state "no accent means the default look" / the nutrition Crown / the rest clock size (grep `docs/state_management/watch_surface*.md`, `docs/README.md`), after P1-P3 and before the review.

## Verify (governor)

`swift test` full in `watch/watchos` with the real count; `xcodebuild` of the watch app (the views compile only there); the invariant grep; mutations by the governor (sign flip, `worn` returning fallback always, `.title3` back); simulator on 40 mm: first-launch buttons cyan (delete the app's `preferences` or use a fresh install), the rest screen layout, the food Crown driven with computer-use if the Mac is unlocked, otherwise an `(owner)` check.

## Progress

All phases done 2026-10-23: see the evidence file.
