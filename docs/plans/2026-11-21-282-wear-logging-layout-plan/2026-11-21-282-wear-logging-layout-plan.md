# Plan 282 — The Wear logging surface fits 192 and 227 dp watches

Follow-up of plan 281 (D-28115, known limit): "the Wear logging surface's own layout does not fit a 227 dp screen (overflow 25 px) or a 192 dp one (60 px)". The owner started it as its own task on 2026-11-21 ("Do this task here"). Wrist only, `lib/watch/`. No wire, phone, storage or schema change. Base commit: `.work/2026-11-21-282-wear-logging-layout/base.txt`; the working tree still carries plan 281 uncommitted (its files are not touched here except `lib/watch/app/wear_app.dart`, where 281 already edited). Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On a Wear watch whose screen is 227 dp or 192 dp tall, with a session running, the logging surface (all four effort kinds) shows everything without overflowing: the exercise name, the value rows (at most two), the `Log` button and the shell's `Menu` button below it are all fully on screen, and `Log` is tappable. Measured before the change (throwaway probe, 2026-11-21, `RenderFlex overflowed`): 227 dp: set 25 px, timed 25, drill 25, round 9; 192 dp: set 96, timed 132, drill 132, round 80.

What the user sees on a small watch (the compact look, screens under 260 dp tall):
- the value rows are tighter: smaller numerals, the label and its unit on one line ("Weight · kg"), smaller step buttons;
- the countdown line and the sensor line (when both exist) share one line;
- `Log` is 40 dp tall instead of 56, `Menu` 32 dp instead of 48;
- if something still does not fit (a long header), the rows scale down a little instead of overflowing.
On a bigger screen (the phone-sized harness, tests at 800x600) nothing changes.

Acceptance: S-28201..S-28208 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; `test/watch_logging_surfaces_test.dart`, `test/wear_app_test.dart`, `test/wear_menu_screen_test.dart`, `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart` green; no new red in the full suite; Docs delta applied.

## Feature invariants

- Controls keep working exactly as before: a drag or a crown turn over a row dials its value, the step buttons step, `Log` logs (S-28205, S-28206). The compact look changes sizes, never behaviour.
- The large layout is byte-for-byte the old one (S-28207).
- Nothing outside `lib/watch/` changes; the Apple wrist is not touched.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28201 | One rule decides the compact look: the screen is shorter than 260 dp (`WatchLayout.compactBelow`, read with `MediaQuery.sizeOf(context).height`). 192 and 227 dp watches are compact, a phone-sized window is not. The rule lives in `lib/watch/widgets/watch_controls.dart` next to the other shared wrist pieces. | `watch_logging_screen.dart` build; `watch_controls.dart` (`WatchStepButton`); real Wear screens are 192-240 dp |
| D-28202 | Overflow is prevented by scaling, not scrolling: in the compact look the value rows sit in a `FittedBox(fit: BoxFit.scaleDown)` inside the `Expanded`. A scroll view is rejected: each row already owns the vertical drag and the crown (`onVerticalDragUpdate`, `onPointerSignal`), so a scroller would fight them. | `watch_logging_screen.dart` `_row` (the `Listener` and `GestureDetector`) |
| D-28203 | Compact sizes: `Log` 40 dp (`WatchLayout.compactButtonHeight`), `Menu` 32 dp (`WatchLayout.compactMenuHeight`) with no extra tap padding, step buttons 36 dp with a 22 dp icon, numerals `titleLarge` bold (22 sp), screen padding vertical 2. They are below the 48 dp Wear touch guideline; that is an owner check (step 1 of the new checks), not hidden. | probe: pinned parts at 192 dp must leave at least about 90 dp for two rows |
| D-28204 | Compact header and rows copy: the exercise name uses `labelMedium`; the countdown (`02:30 left`) and the sensor line join with `  ·  ` on ONE line (one `Text`, one line, ellipsis); a row's unit joins its label (`Weight · kg`, no separate unit line). The large look keeps the separate lines and texts exactly. | `watch_logging_screen.dart` `_header`, `_row` |
| D-28205 | The shell's `Menu` button reads the same rule, so the shell builds its surface under the `MaterialApp` (a `Builder` in `home`) where `MediaQuery` exists: `_surface(BuildContext)`. The shell's own context is above the `MaterialApp` and has no `MediaQuery`. | `wear_app.dart` `build`, `_surface` |
| D-28207 | The compact `Log` button also carries `tapTargetSize: shrinkWrap`: without it Material draws a 40 dp `minimumSize` button 48 dp tall (found by the fix-round tests, which measured `Actual: <48.0>`). The shell's `Menu` and the step buttons already carried it. | `watch_logging_screen.dart` `_logButton`; `wear_logging_layout_test.dart` S-28202 |
| D-28206 | The rest surface is not changed: probe arithmetic (name 20 + Next 56 + padding 8 + the new 32 Menu) fits 192 dp, and S-28207b proves it. | `watch_rest_screen.dart` `build` |

## Input-reality checklist

1. **Writers.** The screen reads `state.fields`, `exerciseName`, the round timer and `sensorLabels`; the layout adds no writer.
2. **Lifecycle.** A session with no exercise (`fields` empty) shows no rows: the compact `FittedBox` must accept an empty column without throwing (S-28203).
3. **Settings changing while open.** Units change the unit label text (`kg`/`lb`, `km`/`mi`), so a longer unit is covered by the ellipsis and the scale-down net.
4. **Time.** A round countdown appearing mid-screen adds a header line: S-28204 lays out the worst header (name + countdown + sensors) at 192 dp.
5. **Load.** One `LayoutBuilder` and one `FittedBox` per frame; nothing per row.
6. **Words.** The only changed copy is the compact joins (D-28204); grep of docs for `Weight` unit lines: none quoted.
7. **Competition.** `Log` and `Menu` share the bottom of the screen; both rects are measured inside the viewport (S-28202).

## Scenarios

All in `test/wear_logging_layout_test.dart` (new), Mock-first, view size set with `tester.view.physicalSize` and `devicePixelRatio = 1.0`, restored in `addTearDown`.

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28201 | `WearApp` over a one-slot session of each effort kind (`set`: reps+load, `timed`: time+distance, `drill`: hold+load, `round`: rounds), at 227x227 and 192x192 | `tester.takeException()` is null after boot (no overflow) | probe: overflow 9 to 132 px on every one of the 8 combinations |
| S-28202 | same 8 combinations | the `Log` button's and the `Menu` button's rects both lie fully inside the view (bottom at most the view height), do not overlap, `Log` is at least 40 dp and `Menu` at least 32 dp tall | `Log` is pushed past the bottom edge by the overflowing column |
| S-28203 | a session whose only slot has no capabilities and no exercise rows (`fields` empty) at 192x192 | no exception; `Log` is present and disabled | an empty `FittedBox` child could throw; guards the compact branch |
| S-28204 | `WatchLoggingScreen` alone in a 192 wide by 160 tall box (192 dp watch minus a 32 dp Menu), round timer running and a sensor line present (heart rate, distance, pace), `round` effort | no exception; name, merged line, both rows and `Log` all inside the box | the three-line header plus two rows needs about 276 dp |
| S-28205 | compact `set` surface at 192x192: tap `More Reps` (tooltip) once, then deliver a `PointerScrollEvent` of -64 over the Reps row | the Reps numeral goes up by 1 and then by 2 more detents | passes without the change too (guard: scaling keeps the controls live and hit-testable) |
| S-28206 | compact `set` surface at 192x192: tap `Log` | exactly one logged entry in `engine.entries` for the slot | without the change the `Log` button lies below the view and the tap misses (probe: the tap never reached the rest surface) |
| S-28204b | the S-28204 fixture at 192x140 (a crowded header that leaves the rows about 62 dp for 88 dp of rows) | every row label sits below the merged line, every step button above `Log` | without the `FittedBox` scale-down the rows spill out of their space |
| S-28208 | compact `set` surface at 192x192 | `Load · kg` joined (`find.textContaining(' · kg')` once), no separate `kg` text | the compact row shows the unit on its own line |
| S-28207 | the same `set` surface at the default 800x600 | the unit line `kg` is its own `Text`; `Log` is 56 dp tall; `Menu` is at least 48 dp tall | passes without the change too (guard: the large layout did not change) |
| S-28207b | after a logged set the rest surface at 227 and 192 dp | no exception; `Next` and `Menu` rects inside the view | passes without the change too (guard for D-28206) |

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "write the report FIRST as a skeleton". Serial.

1. **P1 — production** (`crew-builder-watch`; scope `lib/watch/widgets/watch_controls.dart`, `lib/watch/logging/watch_logging_screen.dart`, `lib/watch/app/wear_app.dart`). Exact code is in the brief. About 90 changed lines. Done: `flutter analyze` on the three files, `test/watch_logging_surfaces_test.dart`, `test/wear_app_test.dart`, `test/wear_menu_screen_test.dart` green.
2. **P2 — the guard test file** (`crew-builder-watch`; scope `test/wear_logging_layout_test.dart`). Copies `_Harness`, the channel mocks and `_open` from `test/wear_menu_screen_test.dart`. S-28201..S-28207b.
3. **P3 — docs** (`crew-docs-keeper`, no test run): the Docs delta.
4. **Lead:** mutation pass, throwaway PNG probe at 227/192 (a look at it), full suite, review.

Predicted production code about 90 lines in 3 files, one track: inside the budget.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | The logging surface does not yet fit a 192 dp or 227 dp screen | On a screen under 260 dp tall the logging surface takes a compact look | S-28201 |
| docs/wear_os_app.md | MODIFIED | (unguarded: decision D-28115 in the plan — it overflows with its bottom | (decisions D-28201..D-28207 in plan 282; guarded by | S-28202 |
| docs/wear_os_app.md | MODIFIED | button); the menu itself fits both. To see the menu without a watch, | `test/wear_logging_layout_test.dart`). To see the menu without a watch, | S-28202 |
| docs/wear_os_app.md | MODIFIED | 5. (owner) the logging surface at 192 dp and 227 dp (the known limit above) | 5. (owner) the logging surface at 192 dp and 227 dp: every control on screen and big enough to hit | S-28202 |

Stale-term sweep: `grep -rIn "does not yet fit\|known limit" docs | grep -v "docs/plans\|docs/history\|docs/releases"` — hits only `docs/wear_os_app.md` 205 and 280 (the rows above).

## Assumption Log

- Probe numbers (2026-11-21, throwaway `test/zz_probe_wear_layout_test.dart`, deleted before review): see Goal. Rest surface not reached by the probe (the Log tap missed at 192 dp), so S-28207b is the first proof for D-28206.
- Fields per effort kind are at most two (`EffortDefaults` primary + secondary metrics: set 2, timed 2, round 2, drill 2).
- Round bezel clipping (the corners of a full-width button) is not addressed here; it is an owner check on a real watch.

## Progress

- [x] P1 production
- [x] P2 guard tests
- [x] P3 docs
- [x] Mutation pass, PNG look, full suite, review
