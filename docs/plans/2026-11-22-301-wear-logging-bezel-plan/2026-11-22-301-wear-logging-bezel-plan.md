# Plan 301 — The Wear logging screen's first lines clear the round bezel (found on the emulator in plan 298)

On the round 192 dp emulator the logging screen's header (the exercise name, the counter, the `NN bpm` / countdown line) is left-aligned at the top-left, which on a circle is outside the visible face: the first words of "No exercise" and the heart-rate number were cut off. Plan 296 fixed the same defect on the Start screen with room above the first item. Geometry: the compact logging screen puts the name's box at x 8, y 2; on a 192 dp circle (radius 96, centre 96,96) its top-left corner is 128 dp from the centre, 32 dp outside the face, and a line at the very top of the circle can be at most about 100 dp wide (at y 14) to about 116 dp (at y 22, with a 2 dp margin). This plan lays the compact header out for a circle. Wrist Dart only (`lib/watch/logging/watch_logging_screen.dart`); no wire, phone, plugin or Swift change. Base commit: `.work/2026-11-22-301-wear-logging-bezel/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

Under `WatchLayout.compactBelow` (260 dp) the logging screen's header is centred and starts 22 dp from the top: the name row (name and the `n/N` counter) is at most 112 dp wide, the merged countdown and sensor line at most 144 dp wide, both centred, so every corner of both lines is inside the visible circle at 192 and 227 dp. The value rows and the `Log` button are unchanged except that the rows, which already scale down to the room they are given, get 20 dp less room. The large layout is unchanged.

Acceptance: S-30101..S-30105 green and each guard red without the change; the existing logging layout tests (`test/wear_logging_layout_test.dart`) and the pager and menu tests still pass; `flutter analyze` at most 174 issues, 0 errors; the Wear debug APK builds; the emulator shows the first line whole; Docs delta applied.

## Feature invariants

- Nothing is hidden: a long name ellipsizes inside its 112 dp, never wraps or overflows; the counter is always shown with its name.
- Every control still fits and is reachable: `Log` and `Menu` keep their sizes and positions on every effort kind at 192 and 227 dp (plan 282's guards).
- Large layout, the sensor line's content and the sensors' behaviour are unchanged.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-30101 | In the compact layout the screen's top padding is `WatchLoggingScreen.compactTopInset` = 22 dp (it was 2); left, right and bottom padding are unchanged. The roomy layout keeps its 4 dp. | `watch_logging_screen.dart` `build` |
| D-30102 | The compact header is centred: the name row is `mainAxisSize.min` inside a `ConstrainedBox(maxWidth: compactNameMaxWidth = 112)`, the merged line is centre-aligned inside a `ConstrainedBox(maxWidth: compactSensorMaxWidth = 144)`. The roomy header is as before. | geometry above |
| D-30103 | The value rows' existing `FittedBox.scaleDown` absorbs the lost 18 dp; nothing else changes size. | `_compactRows` |
| D-30104 | Not in scope: the rest screen, the menu and the other round-face corners (the `Log` button's lower corners, owner check 5), and a real device's inset API. | plan 282 |

## Input-reality checklist

1. **Writers.** None: presentation.
2. **Units.** Logical pixels; the test asserts rectangles against a circle.
3. **Lifecycle.** The header rebuilds every second with the countdown; a long name that arrives later ellipsizes in place.
4. **Settings changing while open.** None.
5. **Time.** A countdown line (`12:00 left`) and a sensor line (`130 bpm  ·  4.2 km`) can be present together: the merged line is one line under 144 dp or ellipsizes.
6. **Load.** None.
7. **Wording.** Unchanged.
8. **Slot competition.** The header, the rows and `Log` share 192 dp: the rows scale down by the 20 dp the header took.

Readers: `test/wear_logging_layout_test.dart` (S-28201..S-28208: fit, `Log`/`Menu` on screen and at least their heights, a worst-case header at 192x160, rows scaling) and the pager and menu tests render this screen at default test size (large layout). The existing tests are the regression set; any that pins a header position is listed in the evidence.

## Scenarios

`test/wear_logging_bezel_test.dart` (new; `testWidgets`, the harness of `wear_logging_layout_test.dart`; explicit pumps):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-30101 | 192 and 227 dp; a set slot named `Squat`; no sensors | the name's text box has all four corners inside the circle (distance from the centre at most radius − 2) | the header sits in the clipped corner |
| S-30102 | 192 and 227 dp; a long name (`Single Arm Dumbbell Romanian Deadlift`) and a page label `2/3` | the name row is at most 112 dp wide and centred, the name ellipsizes, `2/3` is shown, all corners inside the circle, no overflow | a long name reaches the bezel or the counter is lost |
| S-30103 | 192 and 227 dp; a heart-rate beat stored and a round countdown showing | the merged line (`… bpm` and `left`) is one line, at most 144 dp wide, centred, all corners inside the circle | the sensor line is clipped |
| S-30104 | 192 dp, all four effort kinds | no overflow; `Log` and `Menu` exactly where plan 282 puts them (heights 40 and 32; fully on screen) | the header displaces the controls |
| S-30105 | 300 dp (large layout) | the name is left-aligned at the surface inset and its box starts within 8 dp of the top | the large layout changed |

Guard families the lead proves by mutation: the compact top inset, the name and sensor max widths, the centring (both lines), the roomy layout's alignment, the counter's presence, the ellipsis.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — the header** (`crew-builder-watch`; scope `lib/watch/logging/watch_logging_screen.dart`). Exact code in the brief. About 50 lines.
2. **P2 — tests** (lead): the new file.
3. **P3 — docs** (lead), then **Lead:** analyze, the existing layout tests, the APK, the emulator look, the mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | On a screen shorter than 260 dp the logging screen's header is centred | S-30101 |
| docs/wear_os_app.md | ADDED | - | `test/wear_logging_bezel_test.dart` | S-30101 |

Owner check 5 gains the header: it is the corner clipping of the `Log` button plus the header (check 16's wording about the bezel covers the Start screen).

## Assumption Log

- The emulator and real Wear watches show a circular face of the same diameter as the screen's smaller side (192 dp here); the test models it as a circle of radius `size / 2` centred on the screen.
- The system's status area (time, battery) is not drawn over the app on Wear OS apps in the foreground.

## Progress

- [x] P1 the header (crew builder, 1.0 min; top inset moved 20 -> 22 by the lead after the circle test)
- [x] P2 tests (lead; S-30101..S-30105, 11 tests)
- [x] P3 docs (`docs/wear_os_app.md`: a section, a tests bullet, owner check 18)
- [x] Verify and prove: analyze 174 / 0; layout tests +36; APK builds; 9 of 9 mutants killed; the emulator shows the header whole
- [ ] (owner) check 18 in `docs/wear_os_app.md` on a real watch
