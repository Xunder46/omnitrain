# 28 · One look for "nothing here yet"

Status 2026-10-13: Built, proved, reviewed with 27 and 29; Stats/Records/Exercise Progress now have OmniEmptyState assertions. Final: flutter test +4467 ~1, analyze 181.

Parent: `docs/plans/2026-10-12-25-ui-standards-refresh-plan/` (owner decision D2 = A, 2026-10-13). Starts after plan 27 is verified.
Sources: survey sheets s3 section 9, s6 F9, s7 N1, s8 F7-F8, s9 F7.

## Goal and acceptance

What the user sees afterwards: every screen or list that has nothing to show uses the same composition: a muted icon, a short
title, and one line saying what to do next. Titles keep today's wording. Where a screen had only a bare muted sentence, it gains
the icon and a one-line hint. The nutrition trend with nothing logged says "No data yet" instead of drawing a flat line at zero.

Out of scope: tiny inline notes inside a populated card (the profile sparkline "No history yet", the Stats strip line "No training
in the last N weeks", "1 day, log more to see a trend"): they stay and are listed as exceptions. Empty calendar month: the grid is
the content, no change.

## Decision Ledger

| Id | Decision |
|----|----------|
| D-28.1 | New `lib/widgets/common/omni_empty_state.dart`: `OmniEmptyState({required String title, String? hint, IconData icon = Icons.inbox_outlined, Widget? action, bool compact = false})`. Built from the dominant existing composition (`exercise_library_screen.dart:307` `_EmptyState`): centred column, icon 64 at `onSurface` 0.3 alpha, title `titleMedium` at 0.6 alpha, hint `bodyMedium` at 0.45 alpha. `compact: true` uses icon 40 and no scroll wrapper, for use inside a card. Non-compact wraps in `LayoutBuilder` + `SingleChildScrollView` like the library one so it never overflows at 320x568. All colours from `Theme.of(context).colorScheme`. |
| D-28.2 | Titles verbatim from today. Hints (new copy, flagged for owner QA): day list future "Add one with the button below." (past day: no hint), period list "Add one with the button below.", Foods I Eat title "Your Foods I Eat list is empty." hint "Tap the pencil to add foods." (the existing substring `Foods I Eat list is empty` stays findable), Exercise Progress "Log this exercise in a session to see its history.", add-food Library "Nothing is in the catalog right now.", no matches keeps `No matches for "<query>"` with hint "Try a different search.", nutrition trend "No data yet" / "Log food to see your trend." |
| D-28.3 | Existing hints keep their text (My Routines, exercise picker, library, Stats, Records, session overview). |
| D-28.4 | The two private `_EmptyState` classes are deleted. Scan guard: no `class _?EmptyState` in `lib/features` (the shared widget is the only one). |
| D-28.5 | The session list's empty case (centred Add-Exercise-and-Block bar, `workout_session_list_view.dart:425-440`) is an action surface, not a message: unchanged and listed as an exception. |

## Scenarios (red at base)

- S-2801 `OmniEmptyState` pumped (light and dark theme, 320x568): title, hint, icon found; compact variant has the smaller icon; no overflow.
- S-2802 Each of these, with empty data, finds exactly one `OmniEmptyState` with the title below (Mock-first, reuse each screen's existing
  test harness): DaySessionList past ("No sessions on this day.") and future ("No sessions planned yet."), PeriodList ("No training periods yet."),
  MyRoutines ("No Routines Yet"), ExercisePicker with no match ("No exercises found"), ExerciseLibrary ("No exercises found"),
  Stats / Records ("No sessions yet"), ExerciseProgress ("No history for this exercise"), AddFood Library / My Foods / no-match tabs,
  Nutrition Foods I Eat ("Your Foods I Eat list is empty."), RoutineSetup empty block ("No exercises in this block yet.").
- S-2803 Nutrition trend with no logged days: one `OmniEmptyState` "No data yet"; no `LineChart` with all-zero spots.
- S-2804 Scan: no `class _EmptyState` / `class _?\w*EmptyState` declaration in `lib/features` or `lib/widgets` other than `OmniEmptyState`.

## Phases (serial)

| Phase | Scope | Items |
|-------|-------|-------|
| 1 | `lib/widgets/common/**`, `lib/features/stats/**`, `lib/features/nutrition/widgets/nutrition_trend_card.dart`, `test/**` | widget + S-2801; Stats, Records, ExerciseProgress, trend (S-2803) |
| 2 | `lib/features/{calendar,period,routine}/**`, `test/**` | DaySessionList, PeriodList, MyRoutines, RoutineSetup block |
| 3 | `lib/features/{exercise,session,nutrition}/**` (not `widgets/nutrition_trend_card.dart`), `test/**` | ExercisePicker, ExerciseLibrary, SessionOverview, AddFood (3), Nutrition Foods I Eat; S-2804 scan |
| 4 | prover, reviewer, governor verify | |

Predicted production diff about 250 lines in 14 files. Predicted existing-test fallout: finders on the old empty-state `Text` widgets
(they still match: titles are verbatim) and nutrition trend tests asserting the zero line; builders list each.
