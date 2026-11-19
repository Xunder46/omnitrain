# Review: plan 248 · P1-P2 (planned rows start from a play button on today only) · 38a66c39..working tree

Verdict: APPROVE WITH FIXES
Counts: blocker 2 · major 0 · minor 2 · tests: not run here — the brief forbids the full `flutter test`; the lead's scoped run (43 tests, per brief) is taken as given
Diff vs Predicted Files: outside: `test/food_catalog_load_test.dart` (see finding 4)
## Findings

1. [Blocker] `test/routine_session_modality_test.dart:581` — S-12203 still taps the planned row text (`find.text('Plan Today 122')`) and asserts `workoutState.hasActiveSession` is true with the routine's Focus stamp. After plan 248 the row tap opens the edit sheet and starts nothing, so `hasActiveSession` stays false and the first expectation fails: a green test goes red, violating the acceptance criterion "no new red in the full suite against the base failing set" (the file is not in `.work/windows-base-failing-tests.txt`). The plan lists this file under Readers but its "Existing tests changed" list omits it. Failure scenario: run the file, S-12203 throws at the `hasActiveSession` expect. Fix: replace the tap with `tester.tap(find.byTooltip('Start session'))` — the fixture's plan is on today and routine-linked, so the button renders and the Focus-stamp assertions then exercise the same start path they did before. Guard: the test itself.
2. [Blocker] `test/screen_widget_test.dart:4764` — the test "edit planned session opens shared form with session type toggle" taps `find.byIcon(Icons.edit_outlined).first` on a planned row of today. The pencil no longer exists (`day_session_list_screen.dart` has no `Icons.edit_outlined` left; only `play_arrow`, `delete_outline`, `close`, `event_*`), so the finder returns nothing and `tester.tap` throws a StateError: a green test goes red. Same acceptance violation; the plan lists `screen_widget_test` under Readers but does not update this tap. Fix: tap `find.text('Planned Test')` (the row tap now opens the same sheet); the following `Edit Session` / `Session Type` expectations stay valid. Guard: the test itself.
3. [Minor] `test/day_planned_start_button_test.dart:190-193` — S-24802 asserts `expect(workoutState.currentSession, isNull)` twice in a row; the comment explains the second one reads the session through `WorkoutState` because the repository has no `getActiveSession`, but both lines call the same getter, so the second assertion proves nothing the first did not. A maintainer reading the test wonders what differs. Fix: delete the duplicate and keep the comment on the single assertion.
4. [Minor] `test/food_catalog_load_test.dart:270` — an unexplained out-of-scope change (`byId['chicken_thigh']!.fat!` → `.fat`). The `fat` field is non-nullable (`lib/data/models/models.dart:1852`), so the edit is a correct `unnecessary_non_null_assertion` cleanup, but nothing in the plan or brief names it; it does not belong to plan 248's diff. Fix: either revert it or have the owner claim it in the plan's record; do not let it ride silently in this plan's working tree.

## Assumption Log rulings

The plan has no separate Assumption Log table; the Input-reality checklist and Open items carry the assumptions.

- IR-1 Writers (nothing in this change writes): ratify — verified in the diff; `_startPlanned`'s body is byte-identical apart from the rename.
- IR-4 Time (a screen left open across midnight keeps yesterday's play button until rebuild, accepted, Open item 3): ratify — `onStart` is decided at build (`day_session_list_screen.dart:176-190`); `_isTodayOrFuture` is a live getter (`:66`), so a post-midnight rebuild also removes the play and bin consistently. No code change asked for.
- Fixture substitution in S-24801 (`currentSession` asserted instead of `hasActiveSession`, per the established fact that a no-effort session is not "active"): ratify — the test comments the substitution and additionally pins `endedAtMs == null`, which is stronger than the plan's wording.
- Stale-term sweep ("nothing else outside plans/history/releases"): ratify — my own grep of `docs` for `Edit session|pencil|tapping a planned|Planned-session tap|planned entry starts|starts the workout` found only unrelated features (nutrition food-library pencils, the session-edit "Edit Session" screen, the watch's planned workout row in `docs/state_management/watch_surface_wrist_logging.md:151`).

## Scenario coverage

- S-24801 -> `test/day_planned_start_button_test.dart` · "S-24801: today, the Start button starts the workout; the row has no edit tooltip and the play sits left of the bin" | covered (asserts behaviour: `WorkoutSessionScreen` open, `currentSession` non-null with `endedAtMs` null, dx ordering, no `Edit session` tooltip)
- S-24802 -> same file · "S-24802: today, tapping the planned row opens the edit sheet and starts nothing" | covered (`Edit Session` sheet, no `WorkoutSessionScreen`, no session) — would fail against the old row-tap-starts code
- S-24803 -> same file · "S-24803: tomorrow, the row shows only the bin and the tap opens edit" | covered (mutation (a) killed: `Start session` findsNothing on a future date)
- S-24804 -> same file · "S-24804: yesterday, the row is read-only and the tap does nothing" | covered (mutations (b) and (h) killed)
- S-24805 -> same file · "S-24805: today with a running workout, Start asks first, Cancel keeps it, and the row tap opens edit with no prompt" | covered (prompt key found, cancel preserves the running id, row tap opens the sheet with no prompt)
- S-24806 -> same file · "S-24806: today, the bin asks for confirmation and cancelling leaves the row, the play button and no workout" | covered (mutation (f) killed: the bin opens the delete dialog, not the edit sheet, and the play button survives)

## Answers to the brief's five questions

1. Nothing in `lib` still calls the pencil: no `onEdit` on `_SessionRow` and no `Edit session` tooltip anywhere in `lib` (grep). In `test` the only `'Edit session'` occurrences are the new file's `findsNothing` guards plus the unrelated session-edit screen group in `session_edit_duration_test.dart:160`. In current `docs` no sentence names the pencil or the row-tap start on the day list.
2. No new power. The old `_tapPlanned` had no date guard inside the body, so yesterday's build behaved exactly like today's play button: a screen left open across midnight keeps a start affordance for a now-past plan either way until the next rebuild. The plan accepts this (Open item 3). `_isTodayOrFuture` is recomputed per build, so a later rebuild removes the stale button.
3. `OmniDateUtils.isToday` (`lib/core/utils/date_utils.dart:95-99`) truncates both sides to local midnight (`DateTime(date.year, date.month, date.day)` vs the same of `DateTime.now()`), so a non-midnight `widget.date` cannot break it. The calendar grid also passes local midnights. Safe.
4. All six tests assert behaviour, not presence: S-24801 taps the button and checks the workout screen and session state; S-24802/03/04 tap the row and check the sheet/nothing; S-24805 checks the prompt and the preserved running id; S-24806 checks the delete dialog and the surviving row. No assertion would pass against the old row-tap-starts code — the closest, S-24802's `find.byType(WorkoutSessionScreen), findsNothing`, directly fails there.
5. The four docs sentences match the screen (verified against the diff and the code). No other current-doc sentence is now false: `docs/modality_based_exercise_ui.md:702` still holds (the start path is unchanged); `docs/calendar_periods.md:68-70,294` and `docs/navigation_and_screens.md:222` are the updated sentences themselves.

## Docs delta

| Doc | Change | Status |
|---|---|---|
| `docs/calendar_periods.md` | row 1 (allow-list sentence) | applied |
| `docs/calendar_periods.md` | row 2 (planned-entry tap -> edit sheet, play button starts) | applied |
| `docs/calendar_periods.md` | row 3 (supporting-flows item 5) | applied |
| `docs/navigation_and_screens.md` | row 4 (DaySessionListScreen purpose) | applied |

Doc edits the table does not name: none found in `docs/`; the plan file's own What-changed prose and the screen's Dart doc comment (`day_session_list_screen.dart:28-36`) were also updated, which the table need not list.

## Not run on Windows

- `gateway.cmd build` (iOS) and `swift-test` need a Mac — not applicable to this plan's scope.
- The full `flutter test` was not run by this review (the brief forbids it); findings 1 and 2 are read statically and both are deterministic failures.

## Lead dispositions

1. Blocker `routine_session_modality_test.dart` S-12203 tapped the row: FIXED (taps `Start session`); passes.
2. Blocker `screen_widget_test.dart` "edit planned session opens shared form" tapped the removed pencil: FIXED (taps the row text `Planned Test`, which now opens the same sheet); passes.
3. Minor duplicate `currentSession` assertion in S-24802: FIXED.
4. Minor `test/food_catalog_load_test.dart` change: not part of this plan; the file was already modified before this unit started and is left unstaged.
