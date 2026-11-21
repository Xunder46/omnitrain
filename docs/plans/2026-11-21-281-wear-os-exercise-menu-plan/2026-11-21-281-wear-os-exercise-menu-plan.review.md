# Review: plan 281 · Wear OS exercise menu · 7df0076..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 3 · tests: not re-run (brief forbids); lead/governor counts 93 + 21 menu-screen green, `flutter analyze` at the 174 baseline with 0 errors, mutation pass 49 mutants / 37 killed first time / 12 survived / 11 re-killed / 1 equivalent (the `!_isActive` guard in `WatchMenuState.finish`)
Diff vs Predicted Files: conforms; outside: `docs/plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md` (1 line, the "Later PRs" entry corrected in the plan-281 wording, self-annotated "(Corrected 2026-11-21 by plan 281)")

## Answers to the brief's five questions

1. **`WatchMenuState` vs Apple.** `rows` matches `deriveMenuRows` exactly (ladder order, unreadable slots skipped, clamped `isCurrent`, efforts counted by `sessionExerciseId`, `countLabel` never `0 logged`). `isLocked` matches (elapsed/hold/round via `timerFor`, `state != stopped`, rest never locks). `addExercise` matches Apple's guard (`status == active` → `addExerciseToEnd`). `finish` and `discard` match apart from the two documented deviations (D-28106: a running work clock counts as work and is not logged — Apple's `finish()` logs it via `logging.log()`; D-28107: no rating prompt — Apple ends through `rating.end()`). `jump` and `discard` carry an extra `_isActive` early return Apple does not spell: on a non-active session Apple's own engine guards make the call a no-op, so the observable result is the same (the mutation pass ratified the `finish` one as equivalent); the other two are the same shape and I rule them equivalent, not deviations needing a decision.
2. **`WatchMenuScreen` async discipline.** Correct. Every post-`await` continuation is behind `!mounted` (`_jump`, `_end`, `_discard`) or `!mounted || _closing` (`_onTick`); `onChanged` is only reached while mounted. `_closeToStart` cannot run twice: `_closing` is set synchronously before `popUntil`, and the ticker is cancelled in the same synchronous run. The tick-versus-tap races resolve safely: a question page open when the phone ends the session is popped by the menu's own `popUntil` (the `Dialog.fullscreen` route is on the same navigator), the awaiting `_confirm` returns `null` → `_end` sees `!confirmed` and a disposed state and stops; S-28129b pins exactly this. A tap during the 1 s refresh is a plain `setState` behind the pushed routes; a tap whose engine write loses a race (phone removed the slot) returns false, changes nothing, and pops nothing (S-28133, S-28114).
3. **Stateful picker.** The start screen's use is unchanged beyond the double-tap guard: `watch_start_screen.dart:149` passes neither `keepPosition` nor anything new, so the default `false` keeps `addExerciseToSession`. `_adding` is reset before the rethrow, so a failed add leaves the screen usable; on success it stays true but the route pops in the next line. If the engine write succeeds and `context.mounted` is already false, `_adding` stays true — but the route is leaving, so no reachable tap is swallowed. `onExerciseAdded` throwing after the pop is pre-existing behaviour, unchanged in kind. Note: S-28131/S-28131b pin the picker's default flag, not the start screen's call site (finding 3).
4. **`wear_app.dart`.** `_openMenu` and `_openNutrition` are reachable only from buttons rendered inside `build` (both gated surfaces), so they cannot run before the first frame installs the navigator; the `?.` would silently no-op only in a state no user input can reach. `_boot`'s `finally` runs `_syncTicker` only inside `if (mounted)`, so a dispose during the restore skips it safely, and the following `transport.start()` block re-checks `!mounted`. One nit, harness-only: `late final _navigator` shadows a later widget update's different `navigatorKey`; since `MaterialApp` reads the same field the shell stays self-consistent, so no finding.
5. **Docs.** The double-tap sentence names S-28134 and S-28134b, both present and saying what they check. The start-picker sentence names tests that exist but do not drive the start screen (finding 3). The full-screen-question sentence names tests that exist but none asserts the full-screen form (finding 1). Every other behaviour sentence in the new sections names a test that exists in the diff; the "menu closes by the system back gesture" claim is covered by owner check 2, not by a test, and is not presented otherwise.

## Findings

1. [Major] `docs/wear_os_app.md` (## The exercise menu, the Finish/Discard paragraph) — the sentence "The Finish and Discard questions are a full-screen page rather than a centred dialog" reads as covered ("the screen tests above exercise both questions...") while no test asserts the full-screen form: S-28123/S-28123b/S-28129b pass with any dialog shape, so a revert of `_ConfirmScreen` to `AlertDialog` (decision D-28113) keeps all 21 screen tests green. Fix: one guard test asserting the confirm surface is a `Dialog.fullscreen` (or that `AlertDialog` is absent while the question shows), or mark the sentence `(unguarded: decision D-28113)` as the 192 dp sentence does. Guard: that new test.
2. [Minor] `test/wear_app_test.dart:7` — the file's scenario-mapping header still says "S-28021 a running session shows the logging surface, with the stopgap End" while the test below was rewritten to "S-28120 ... Menu" and `End` is asserted gone; a reader of the header is told the opposite of what the file now pins. Fix: update the two header lines (S-28021/S-28022 wording).
3. [Minor] `docs/wear_os_app.md` (## The exercise menu, the Add Exercise paragraph) — "The start screen's free-workout picker is unchanged" is backed by S-28131/S-28131b, which build `WatchExercisePickerScreen` directly in a bare `MaterialApp`; no test drives the picker through `watch_start_screen.dart`'s `_startFreeWorkout`, so a one-word regression (`keepPosition: true` at that call site) would be green everywhere. Fix: reword the sentence to the picker's default, or add the start screen's push to an existing start test. Guard: a start-test tapping the picker through `WatchStartScreen`.
4. [Minor] `docs/wear_os_app.md` (shell section, the `navigatorKey` paragraph) — "which is what lets the start surface's nutrition quick-log open; before that repair `Navigator.of(context)` had no navigator above the shell" names no test, and no test opens nutrition through the shell (grep over `test/wear_app_test.dart` finds only harness construction). Fix: mark the claim as covered by "Checks on a watch" item 4 or `unguarded`.

## Assumption Log rulings

- Entries (a)–(e): ratify — every symbol the rulings name is in the files this run saw (`timerFor`, `entries` projection, `advanceExercise`, `_add`, `fromSlot`, `abandonSession`, `WatchUtilityButton`); `endLabel` survives nowhere in `lib/` or the docs the sweep covers.
- The wrist-starts-no-work-clock ruling: ratify — the only Dart timers the logging surfaces start are the rest and the round follow-on, as D-28106 assumes.
- S-28133/S-28134/S-28135 appended, all guarded: ratify — all three tests are in the diff.
- The equivalent-mutant ruling (`!_isActive` in `finish`): ratify — the engine's terminal guard makes `finishSession` on an ended session a no-op, and the same reasoning covers the guards in `jump` and `discard` (see answer 1).

## Scenario coverage

- S-28101..S-28105 (+S-28105b) → `test/watch_session_menu_engine_test.dart`, named tests.
- S-28110..S-28119b (+S-28112f, a paused clock still locks) → `test/watch_menu_state_test.dart`, named tests.
- S-28120, S-28121 → `test/wear_app_test.dart` (rewritten from S-28021/S-28022).
- S-28122..S-28131 → `test/wear_menu_screen_test.dart`, named tests; S-28122b/S-28123b/S-28125b/S-28129b/S-28131b extras each guard a real edge.
- S-28132 → `test/wear_os_config_test.dart` group.
- S-28133..S-28135, S-28136 → `test/wear_menu_screen_test.dart`, named tests.
- D-28113's full-screen form → MISSING (finding 1). D-28115 → documented unguarded, as the plan says.

## Docs delta

- docs/wear_os_app.md "A stopgap End" -> applied
- docs/wear_os_app.md "control under the logging surface finishes the workout; it stands in for the" -> applied
- docs/wear_os_app.md REMOVED "Apple wrist's exercise menu until that menu is ported." -> applied
- docs/wear_os_app.md "menu, the effort-rating prompt, the personal-record banner, the water bar, the" -> applied
- docs/wear_os_app.md ADDED "## The exercise menu" -> applied
- docs/wear_os_app.md ADDED "End Session asks Finish Workout? only when a logged effort or a running work clock is there" -> applied
- docs/wear_os_app.md ADDED "A clock the phone started is not logged by the wrist's End" -> applied
- docs/wear_os_app.md ADDED "## Checks on a watch" -> applied
- docs/wear_os_app.md ADDED "The Finish and Discard questions are a full-screen page" -> applied (but see finding 1)
- docs/wear_os_app.md ADDED "flutter run -d macos -t lib/watch/debug/wear_menu_debug_main.dart" -> applied
- docs/wear_os_app.md ADDED "The logging surface does not yet fit a 192 dp or 227 dp screen" -> applied
- docs/watch-app-setup-and-qa.md "the exercise menu (a" -> applied
- docs/watch-app-setup-and-qa.md "stopgap End control finishes the workout), the effort-rating prompt, the" -> applied
- Doc edits the table does not name: the shell-section rewrite (the `navigatorKey`/nutrition sentence and the "restored at launch" ticker clause), the three new test-file bullets in the suite list, and the Doc-freshness date bump 2026-11-20 → 2026-11-21 — all present in the diff, all consistent with the code.
