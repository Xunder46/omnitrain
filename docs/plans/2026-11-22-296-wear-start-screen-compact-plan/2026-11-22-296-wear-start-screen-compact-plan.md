# Plan 296 — The Wear Start screen fits a small round watch (found on the emulator, plan 280 owner check 5)

On the Wear OS emulator (small round, 192 dp) the Start screen showed a "BOTTOM OVERFLOWED" banner. Measured with a throwaway widget probe at the real sizes (192, 227 and a 300 dp control), with the phone's real-size buttons (56 dp) and the screen's pinned layout (routine list in an `Expanded` above four pinned buttons):

| Size | Setup | Result |
|---|---|---|
| 192 dp | Sync, Free workout, Log food, routines synced | no overflow, but the routine list has **zero height**: no routine can be started |
| 192 dp | the same plus the debug Diagnostics button and the phone reachable (`Search on phone`) | overflow **96 px** |
| 227 dp | Sync, Free workout, Log food, routines synced | the first routine is just visible |
| 227 dp | the same plus Diagnostics and the reachable hint | overflow **45 px**, no routine visible |
| 300 dp | everything | fits |

So at 192 dp (and 227 dp with the phone in range) the user cannot start a routine from the Start screen. The logging surface got a compact layout in plan 282 (under 260 dp); the Start screen never did. This plan gives it the same rule. Wrist UI only (`lib/watch/start/watch_start_screen.dart`); no wire, phone, plugin or Swift change. Base commit: `.work/2026-11-22-296-wear-start-screen-compact/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On a screen shorter than `WatchLayout.compactBelow` (260 dp) the Start screen is one scrolling list: the routines first, then `Sync`, `Free workout`, `Log food`, `Diagnostics` (debug and profile builds) and the `Search on phone` hint, each button 40 dp tall (`WatchLayout.compactButtonHeight`) with the tap area not padded up, a 4 dp gap between items, and 16 dp of room above the first and below the last item for the round bezel (added after the emulator showed the bezel clipping the first line). Nothing overflows at 192 or 227 dp whatever is on, the first routine is always visible at the top, and every button can be scrolled to and pressed. On a taller screen the layout is exactly today's (pinned buttons, scrolling routine list, 56 dp buttons).

Acceptance: S-29601..S-29606 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the same probe numbers re-run on the changed screen show no overflow at 192, 227 or 300 dp; the Wear debug APK builds; Docs delta applied (including the doc split below).

## Feature invariants

- Large-screen layout unchanged: the same widgets in the same order, 56 dp buttons.
- No behaviour change: every button calls what it called; the routines are the same list in the same order.
- `WatchPrimaryButton` and `WatchUtilityButton` keep their defaults (non-compact, 56 dp) for every other caller.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29601 | Under `WatchLayout.compactBelow` the Start screen is one `ListView.separated` (routines, then the action buttons, then the hint) with a 4 dp separator; at or above it the existing `Column` is used unchanged. | `watch_start_screen.dart` 61-103; plan 282 D-28201 |
| D-29602 | `WatchPrimaryButton` and `WatchUtilityButton` gain `compact` (default false): the height is `WatchLayout.compactButtonHeight` (40) instead of `OmniTheme.buttonPrimaryHeight` (56) and the tap area is `MaterialTapTargetSize.shrinkWrap` so Material does not pad it back to 48. | `watch_controls.dart` 18-30; plan 282 lessons |
| D-29603 | Routines stay first in the compact list: starting a routine is the screen's main action; the utilities follow. With many routines a user scrolls to `Free workout`; that cost is accepted (the pinned layout gave routines no room at all). | measured table above |
| D-29604 | The empty-state sentence becomes `WatchStartScreen.nothingSyncedLabel` and is used by both layouts. | `_nothingSynced` 105-115 |
| D-29605 | Not in scope: other watch screens at 192 dp (the picker, the nutrition screen, the menu were measured by earlier plans or are separate), and the system's round-bezel clipping of corners (owner check 5). | plan 282 |

## Input-reality checklist

1. **Writers.** None: a presentation change.
2. **Units.** Logical pixels; sizes asserted exactly (a `FittedBox` hides a size change).
3. **Lifecycle.** The list rebuilds when routines sync in (the paths notify as today); the compact choice is read from `MediaQuery` on each build, so a size change (the emulator's) switches layout live.
4. **Settings changing while open.** None.
5. **Time.** None.
6. **Load.** A handful of items; `ListView` builds lazily.
7. **Wording.** Unchanged strings.
8. **Slot competition.** The whole point: five to seven items compete for 184 dp; scrolling resolves it.

Readers: callers of the two button classes (`grep -rn "WatchPrimaryButton\|WatchUtilityButton" lib test`): the Start screen, the exercise picker and the session menu use them non-compact; `test/watch_session_start_test.dart` and `test/watch_nutrition_quick_log_test.dart` render the Start screen at the default 800x600 test size (large layout, unchanged).

## Scenarios

`test/wear_start_screen_compact_test.dart` (new; `testWidgets`, explicit pumps, no `pumpAndSettle`; a `WatchSessionStartPaths` subclass that returns a given routine list and a settable `phoneReachable`):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29601 | 192 and 227 dp, four routines, Sync, Log food, Diagnostics, phone reachable | no exception; `Routine 0` is visible and its button is 40 dp tall | the routines get no room, or the screen overflows |
| S-29602 | 192 dp, no routines, everything on | no exception; the empty sentence shows; dragging the list up reaches `Diagnostics` and the hint | the empty state overflows or the buttons cannot be reached |
| S-29603 | 192 dp, four routines, everything on; scroll to each button and tap `Sync`, `Free workout` (the picker opens), `Log food`, `Diagnostics` | each callback fires once | a button is unreachable or does nothing |
| S-29604 | 192 dp, one routine | the order from the top is the routine, `Sync`, `Free workout`, `Log food` | the routine is not first |
| S-29605 | 192 dp | the `Sync` button is exactly 40 dp tall and 8 dp inside each edge (compact); the tap area is not padded to 48 | the compact height or the shrink-wrap is missing |
| S-29606 | 300 dp (large), four routines, everything on | no exception; the screen contains a `Column` and an `Expanded` ListView of the routines; `Sync` is exactly 56 dp tall; the hint shows | the large layout changed |

Guard families the lead proves by mutation: the compact switch, the 40 and 56 heights, the shrink-wrap, the order (routines first), the empty-state text in both layouts, the separator, the hint's presence.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — the compact Start screen** (`crew-builder-watch`; scope `lib/watch/start/watch_start_screen.dart`). Exact code in the brief. About 90 lines.
2. **P2 — tests** (lead): the new file.
3. **P3 — docs** (lead): one paragraph; first split `docs/wear_os_app.md` (51,792 bytes, the band is 52,428): move the four sections about the phone's settings, the effort rating, the effort-rating prompt and the accent colour whole into `docs/wear_os_app_phone_settings.md`, leave a pointer paragraph and the README row.
4. **Lead:** analyze, the probe re-run, the APK, a look on the emulator, the mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | On a screen shorter than 260 dp the Start screen is one scrolling list | S-29601 |
| docs/wear_os_app.md | ADDED | - | `test/wear_start_screen_compact_test.dart` | S-29601 |
| docs/wear_os_app.md | ADDED | - | The phone's settings, the effort rating and the accent colour moved to | S-29601 |

The split moves whole sections verbatim; the checks that read their sentences are the plans' own tests (unchanged). `docs/README.md` gets one row for the new page.

## Assumption Log

- The emulator reports the same 384x384 at 320 dpi (192 dp) as a real small round Wear OS watch; real watches clip the corners of a round face (owner check 5).
- The probe's 56 dp buttons match what ships: `OmniTheme.buttonPrimaryHeight` is 56 and both buttons set `minimumSize` to it.
- Moving sections between doc pages needs no test change: nothing in `test/` reads those sections by position (grep before the split).

## Progress

- [x] P1 the compact Start screen (crew builder, 1.7 min; the 16 dp bezel padding added by the lead after the emulator showed a clipped first line)
- [x] P2 tests (lead; S-29601..S-29607, 9 tests)
- [x] P3 docs and the split (`docs/wear_os_app.md` 38 KB, new `docs/wear_os_app_phone_settings.md` 15 KB, README row, owner check 16)
- [x] Verify and prove: analyze 174 / 0; Wear APK builds; 20 of 20 mutants killed; the emulator shows no overflow and every button reachable
- [ ] (owner) check 16 in `docs/wear_os_app.md` on a real watch
