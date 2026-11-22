# Plan 287 — The Wear OS wrist pages between exercises (plan 280 open item 2)

Owner request (2026-11-21): "continue the Wear OS development"; the next item in plan 280's order is the swipe pager. Wrist only (`lib/watch/`). No wire, phone, storage, schema or Swift change. Base commit: `.work/2026-11-21-287-wear-swipe-pager/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

What a user sees on a Wear watch with a running session of two or more exercises: the logging surface shows one exercise and a small `2/3` counter next to its name. A horizontal swipe moves to the neighbouring exercise: a swipe to the left goes to the next exercise, which slides in from the right edge; a swipe to the right goes to the previous one, which slides in from the left edge. A swipe past either end does nothing (no wrap). A short touch or a mostly vertical drag does not page. While a work clock (elapsed, hold or round) is running there is no paging: the swipe gives a short vibration and the words `An effort is running` for 1.5 seconds. A session with one exercise shows no counter and does not page. The rest surface is not paged. A move the user did not make (the phone, the menu, the rest screen's Next) shows the new exercise at once with no slide. With the system's reduced-motion setting the slide is a plain fade. `Log` after a swipe writes to the exercise on screen.

Acceptance: S-28701..S-28721 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; `test/wear_app_test.dart`, `test/wear_menu_screen_test.dart`, `test/watch_logging_surfaces_test.dart`, `test/wear_logging_layout_test.dart`, `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart` green; no new red in the full suite; Docs delta applied.

## Feature invariants

- The pager is a rule over the menu, not a second way to move the session: a settled swipe is `WatchMenuState.jump` (the engine's `selectExercise`), so the engine stays append-only and the phone hears the same `exercise_advanced` lifecycle it hears for a menu jump (the Apple `WatchPagerModel`, `docs/state_management/watch_surface_wrist_pager.md`).
- Rows and position are read from the menu on every access, never cached.
- Copy and numbers come from the Apple `WatchPagerCopy` (`lockedNotice` = the menu's `lockedCaption`, `noticeSeconds` 1.5, `slideSeconds` 0.2); the Dart names match.
- All new files are in `lib/watch/logging/`; nothing in `lib/state`, `lib/features` or the phone transport changes.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28701 | New plain class `WatchPagerState` (`lib/watch/logging/watch_pager_state.dart`), the Dart `WatchPagerModel` minus the focus: `rows`, `pageCount`, `currentIndex`, `currentSlotId`, `isLocked`, `showsPager` (`pageCount > 1 && !isLocked`), `pageLabel` (`n/N` when `pageCount > 1`), `neighbourIndex(of, towardsNext:)` (null when not shown or off either end), `land(index)`, `noteLockedSwipe()`, `noticeVisible(at)`. It owns no session structure and mints no ids. A constants class `WatchPagerCopy` sits beside it. | `WatchPagerModel.swift` 24-90; `watch_menu_state.dart` `rows`, `isLocked`, `jump` |
| D-28702 | `land(index)`: false for an index off the ladder; true, no frame, for the current page; for a locked session false and the notice starts; else `menu.jump(rows[index].slotId)`. The lock is read from the menu's own `isLocked` (D-28105), so a running rest never locks. | `WatchPagerModel.land` 70-79; `watch_menu_state.dart` 120-130, 147-150 |
| D-28703 | **Deviation from Apple, stated:** no `focusSlotId`. The Apple focus shows the swiped-to page before the engine's select lands (plan 52 D-5). The Dart logging state reads `engine.currentExercise` on every build and the in-memory move is one awaited transition, so the Wear pager awaits the jump, and **while a landing is in flight the logger is wrapped in `AbsorbPointer`** so `Log` cannot write to the exercise being left. A second swipe during a landing is ignored (Apple: the newest settled page wins). No change to `WatchLoggingState`. | `watch_logging_state.dart` 358 `_slot => _engine.currentExercise`; `watch_session_engine.dart` 384-394 `selectExercise`; `WatchLoggingState.swift` 851-875 |
| D-28704 | New widget `WatchLoggingPager` (`lib/watch/logging/watch_logging_pager.dart`) wraps `WatchLoggingScreen`. One horizontal-drag recogniser (`GestureDetector`, `HitTestBehavior.translucent`) sums `delta.dx`; on drag end the swipe counts when `abs(sum) > 24` (Apple: 24 points, `abs(across) > abs(down)` is the recogniser's own job in Flutter: the metric rows use only vertical drags, `watch_logging_screen.dart` 295-297, so the two never compete). Negative sum = next. A swipe plays `HapticFeedback.selectionClick`; a locked one plays `HapticFeedback.heavyImpact`. | `WatchLoggingPagerView.swift` 110-121, 130-140; `watch_logging_screen.dart` 287-297 |
| D-28705 | The logger is keyed by the current slot id and switched with an `AnimatedSwitcher` of `slideSeconds`. The slide is built only for the user's own swipe: the swipe records the target slot id and the side; at build the slide is built only when the current slot id equals that recorded target, else the child is shown with no transition (as built: the switcher keeps one constant duration and each page has its own number as key, because a zero-duration switcher left two entries for one exercise alive after a swipe onward and straight back, S-28725). The incoming child slides from the swiped side combined with a fade; the outgoing child is removed at once (Apple `removal: .identity`). With `MediaQuery.disableAnimations` the incoming child only fades. | `WatchLoggingPagerView.swift` 94-108; plan 85 D-1..D-3 |
| D-28706 | `WatchLoggingScreen` gains an optional `pageLabel` (default null). The header's first line becomes a row: the name (ellipsised, `Flexible`) and, when given, the label directly after it, not at the far edge: the top of a round face is narrow and clips a far-right corner. Nothing else in the screen changes; the label also shows while locked (Apple `single` passes `pager.pageLabel`). | `watch_logging_screen.dart` 194-215; `WatchLoggingPagerView.swift` 128 |
| D-28707 | The shell mounts the pager only on the logging surface: `_surface` builds `WatchLoggingPager(menu: _menu, logging: _logging, onMoved: _menuChanged)` where it built `WatchLoggingScreen(state: _logging)`. The rest surface is unchanged (Apple's pager is the logging view only). `_menu` is the one the Menu button already uses, so the pager and the menu share one rule. | `wear_app.dart` 105-109, 305-309 |
| D-28708 | The locked notice is drawn over the logger by the pager (`Text` in a rounded black 80 % box, as Apple) and disappears 1.5 s after the swipe through a pager-owned `Timer` (cancelled on dispose): the shell's one-second tick is not relied on. | `WatchLoggingPagerView.swift` 142-150 |
| D-28709 | Rejected: a `PageView` of one logger per exercise. Every page would build its own `WatchLoggingScreen` (own ticker, haptics, rotary accumulators) and a settled swipe would still have to call `jump`; the Apple pager is one logger over the menu's rule, and so is this one. | `WatchLoggingPagerView.swift` 25-29 |

## Input-reality checklist

1. **Writers.** The current index: the engine only, through `selectExercise` (pager and menu), `advanceExercise` (the rest screen's Next), the phone's `exercise_push` and `structure_change`. The pager writes through `jump` and nothing else. The recorded swipe target is the pager's only own state.
2. **Lifecycle.** One exercise (no pager); an exercise added from the menu while the pager shows (page count grows on the next build: S-28709); a slot the phone removes (count shrinks, a stale target makes `land` return false); the session ending while a landing is in flight (the pager is unmounted, `mounted` check before `setState`); app killed and relaunched (nothing stored: the pager is stateless).
3. **Settings changing while open.** None affect paging. Reduced motion is read per build (`MediaQuery.disableAnimations`).
4. **Time.** The notice ends at `swipe + 1.5 s` (`instant < until`); the pager's own `Timer` repaints it away; a work clock that finishes on the phone unlocks paging on the next build.
5. **Cost.** `rows` walks `engine.entries` once per row on every call (`watch_menu_state.dart` 98-104). The pager reads `rows` once per build and once per swipe, never per frame; the shell already rebuilds once a second.
6. **Words.** The counter `n/N` and the notice copy come from the Apple copy; stale wording: `docs/wear_os_app.md` 514 (the Apple-only list), the shell header comment in `wear_app.dart` 12-16.
7. **Slot competition.** The counter shares the name's line (ellipsised name, label kept); measured at 192x192 and 227x227 dp with a throwaway probe before the owner sees it (checklist (o)). The pager adds one recogniser; the rotary `Listener` and vertical drag of the rows are untouched (S-28712).

## Scenarios

Phase 1 state (`test/watch_pager_state_test.dart`, new, plain `test()`), fixture: an in-memory engine with an active session of slots `sx-a, sx-b, sx-c`, index as stated:

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28701 | index 1 | `pageCount` 3, `currentIndex` 1, `currentSlotId` `sx-b`, `pageLabel` `2/3`, `showsPager` true | the class does not exist |
| S-28702 | one slot | `showsPager` false, `pageLabel` null, `neighbourIndex(of: 0, towardsNext: true)` null | a one-exercise session pages or shows a counter |
| S-28703 | index 0; an `elapsed` timer running | `isLocked` true, `showsPager` false, `neighbourIndex` null; a running `rest` timer instead: `showsPager` true | the lock is not read, or a rest locks |
| S-28704 | `neighbourIndex`: (0, previous), (2, next), (1, next), (1, previous) | null, null, 2, 0 | the pager wraps, or runs off an end |
| S-28705 | index 0; `await land(2)` | true; engine index 2; exactly one `session_lifecycle` frame `exercise_advanced` with `exerciseIndex` 2 | `land` does not move the session |
| S-28706 | index 1; `await land(1)` | true; no frame; index 1 | the current page re-selects and emits |
| S-28707 | locked; clock fixed at T; `await land(1)`; then `noticeVisible` at T+1.49 s and at T+1.5 s | false; index unchanged; true; false | a locked swipe moves, or the notice never starts/ends |
| S-28708 | `land(9)` and `land(-1)` | false; nothing changes | an index off the ladder throws or moves |
| S-28709 | pager built over 3 slots; `paths.addExerciseToEnd(<a fourth>)` | `pageCount` 4 and `pageLabel` `1/4` without rebuilding the pager | the rows are cached |

Phase 2 widget (`test/wear_pager_screen_test.dart`, new; the Wear screen helpers in `test/wear_menu_screen_test.dart` are the model; in-memory store, Mock-first, no Hive):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28710 | `WatchLoggingPager` over 3 slots, index 0; drag -80 px horizontally, settle | engine index 1; the header shows the second name and `2/3` | no recogniser, or the direction is inverted |
| S-28711 | index 1; drag +80 | index 0 | direction inverted |
| S-28712 | index 0; drag +80; index 2; drag -80 | index unchanged both times; no lifecycle frame | the pager wraps |
| S-28713 | index 0; drag -20; and a vertical drag of 80 px starting on a metric row | index 0 both times | the threshold is missing, or a vertical drag pages |
| S-28714 | an `elapsed` timer running; drag -80 | index unchanged; `An effort is running` visible; after 1.6 s it is gone | a locked swipe moves, or the notice stays |
| S-28715 | one slot; drag -80 | nothing changes; no counter text | a one-exercise session shows a counter |
| S-28716 | swipe to the second exercise, tap `Log` | the new effort's `sessionExerciseId` is `sx-b` | `Log` writes to the exercise left |
| S-28717 | store whose slot write is held by a `Completer`; drag -80; before completing, tap `Log` | no effort is logged; after completing, tapping `Log` logs against `sx-b` | the landing does not absorb input (D-28703) |
| S-28718 | `menu.jump('sx-c')` called directly, pump | the logger shows the third exercise and `3/3`; no `SlideTransition` in the tree | a move the user did not make animates, or the pager does not follow |
| S-28719 | drag -80, first frame after the landing | the incoming `SlideTransition`'s position dx is 1.0; for a right swipe -1.0 | the slide enters from the wrong side |
| S-28720 | `MediaQuery(disableAnimations: true)`; drag -80 | no `SlideTransition`; a `FadeTransition` shows the new exercise | reduced motion still slides |

Phase 2 shell (`test/wear_app_test.dart`, `test/watch_logging_surfaces_test.dart`, added to):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28721 | the shell over a 3-exercise running session: drag -80 on the logging surface; then a running rest (`Log`, rest shown) and drag -80 on the rest surface | index 1 and `Menu` still shown; the rest surface leaves the index alone; a header counter appears only when `pageLabel` is passed (`WatchLoggingScreen` alone shows none) | the shell does not mount the pager, or pages the rest surface |

Guard families the lead proves by mutation: the 24 px threshold and its `>`, the sign of the direction, the no-wrap bounds, the lock read, the notice window, the `AbsorbPointer`, the slide-side flag, the duration-zero rule for non-swipe moves, the reduced-motion branch, the removal-at-once branch.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "write the report FIRST as a skeleton". Serial (the files share the shell and the screen).

1. **P1 — state and widget** (`crew-builder-watch`; scope `lib/watch/logging/watch_pager_state.dart`, `lib/watch/logging/watch_logging_pager.dart`, `lib/watch/logging/watch_logging_screen.dart`, `lib/watch/app/wear_app.dart`). Exact code in the brief. About 200 lines.
2. **P2a — state tests** (`crew-builder-watch`; scope `test/watch_pager_state_test.dart`). S-28701..S-28709.
3. **P2b — widget tests** (`crew-builder-watch`; scope `test/wear_pager_screen_test.dart`, `test/wear_app_test.dart`). S-28710..S-28721, by copying the named helper block.
4. **P3 — docs** (`crew-docs-keeper`, no test run).
5. **Lead:** measure the layout probe, mutation pass, full suite, analyze, plan-lint.

Predicted production code about 200 lines in 4 files, tests about 350 lines: inside the budget (pr-scope-guard to run at acceptance).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | The Apple wrist hosts more: the swipe pager between exercises, the | The Apple wrist hosts more: the | S-28721 |
| docs/wear_os_app.md | ADDED | - | ## The exercise pager | S-28710 |
| docs/wear_os_app.md | ADDED | - | `test/wear_pager_screen_test.dart` | S-28710 |
| docs/wear_os_app.md | ADDED | - | 9. (owner) on a Wear emulator or watch: swipe between the exercises | S-28710 |

The new section is short and points to `docs/state_management/watch_surface_wrist_pager.md` for the shared rule, naming only the Wear differences (no focus; the logger is absorbed while a landing runs; no Crown binding). Stale-term sweep: `grep -rIn -i -E "\bpager\b" docs | grep -v "docs/plans\|docs/history\|docs/releases"` hits only the Apple pager docs (`state_management/watch_surface_wrist*.md`, which stay true for the Apple wrist) and `docs/wear_os_app.md` 514 (the row above). Plan 280's open item 2 is a plan record (the keeper adds "built by plan 287"). The `wear_app.dart` header comment (lines 12-16) is code and is fixed in P1.

## Assumption Log

- `WatchMenuState.jump` returns false while a work clock runs or the session is not active, so `land` needs no lock check of its own beyond starting the notice (`watch_menu_state.dart` 147-150).
- `InMemoryWatchSessionStore` is what the existing Wear screen tests use; a held write for S-28717 is a subclass overriding the one method `_transitionTo` calls to persist the session (the builder finds it; if it cannot in one try the lead writes S-28717).
- The Wear OS system swipe-to-dismiss is NOT a test-visible fact: `LaunchTheme`/`NormalTheme` parent `Theme.Light.NoTitleBar` (`android/app/src/main/res/values/styles.xml`), not a Wear theme, so a right swipe may or may not be taken by the platform. Marked `(owner)` check 9: if the OS takes the right swipe, the follow-up is a product call (a fallback control), not a silent change.

## Progress

- [x] P1 production (crew builder; lead edits: page key, constant duration, failing-write recovery)
- [x] P2a state tests (lead; S-28701..S-28709)
- [x] P2b widget tests (lead; S-28710..S-28727)
- [x] P3 docs (lead; `docs/wear_os_app.md`, plan 280 item 2)
- [x] Verify and prove (analyze 174; 28 tests green; 23 of 23 mutants killed)
- [ ] Review: not run by the crew (gateway hangs here); lead read the final code
- [ ] (owner) check 9 in `docs/wear_os_app.md` on a Wear emulator or watch
