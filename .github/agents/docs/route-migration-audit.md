# Route Migration Audit

Centralized route system migration completed for the `centralized-route-system` feature.
Post-migration grep for `MaterialPageRoute` and `PageRouteBuilder` in `lib/features/` and `lib/widgets/` returns **zero results**.

---

## Migrated Call Sites (31 total)

| # | File | Pre-migration line | Before | After |
|---|---|---|---|---|
| 1 | `lib/features/home/home_screen.dart` | 290 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutSessionScreen(...)))` | `OmniNavigator.push(context, (_) => WorkoutSessionScreen(...))` |
| 2 | `lib/features/home/home_screen.dart` | 346 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyRoutinesScreen(...)))` | `OmniNavigator.push(context, (_) => MyRoutinesScreen(...))` |
| 3 | `lib/features/home/home_screen.dart` | 366 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutSessionScreen(...)))` | `OmniNavigator.push(context, (_) => WorkoutSessionScreen(...))` |
| 4 | `lib/features/home/home_screen.dart` | 386 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutSessionScreen(...)))` | `OmniNavigator.push(context, (_) => WorkoutSessionScreen(...))` |
| 5 | `lib/features/home/home_screen.dart` | 456 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutSessionScreen(...)))` | `OmniNavigator.push(context, (_) => WorkoutSessionScreen(...))` |
| 6 | `lib/features/home/home_screen.dart` | 586 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkoutSessionScreen(...)))` | `OmniNavigator.push(context, (_) => WorkoutSessionScreen(...))` |
| 7 | `lib/features/home/home_screen.dart` | 750 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => CalendarScreen(...)))` | `OmniNavigator.push(context, (_) => CalendarScreen(...))` |
| 8 | `lib/features/home/home_screen.dart` | 768 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatsScreen(...)))` | `OmniNavigator.push(context, (_) => StatsScreen(...))` |
| 9 | `lib/features/home/home_screen.dart` | 780 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(...)))` | `OmniNavigator.push(context, (_) => ProfileScreen(...))` |
| 10 | `lib/features/home/home_screen.dart` | 792 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(...)))` | `OmniNavigator.push(context, (_) => SettingsScreen(...))` |
| 11 | `lib/features/calendar/calendar_screen.dart` | 163 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 12 | `lib/features/calendar/calendar_screen.dart` | 197 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 13 | `lib/features/calendar/calendar_screen.dart` | 213 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 14 | `lib/features/calendar/day_session_list_screen.dart` | 182 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 15 | `lib/features/calendar/day_session_list_screen.dart` | 269 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 16 | `lib/features/session/session_overview_screen.dart` | 96 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 17 | `lib/features/session/session_overview_screen.dart` | 331 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 18 | `lib/features/session/workout_session_finish.dart` | 161 | `Navigator.of(context).pushReplacement(MaterialPageRoute(...))` (via `_pushSessionReplacement`) | `OmniNavigator.pushReplacement(...)` (via `_pushSessionReplacement` in `workout_session_screen.dart`) |
| 19 | `lib/features/session/session_summary_screen.dart` | 301 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 20 | `lib/features/session/session_summary_screen.dart` | 320 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 21 | `lib/features/routine/my_routines_screen.dart` | 198 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 22 | `lib/features/routine/my_routines_screen.dart` | 213 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push(context, (_) => ...)` |
| 23 | `lib/features/routine/my_routines_screen.dart` | 298 | `Navigator.of(context).pushReplacement / popUntil + push` | `OmniNavigator.popUntil(...) + OmniNavigator.push(...)` |
| 24 | `lib/features/period/period_list_screen.dart` | 86 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push<bool>(context, (_) => ...)` |
| 25 | `lib/features/period/period_list_screen.dart` | 97 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push<bool>(context, (_) => ...)` |
| 26 | `lib/features/onboarding/onboarding_screen.dart` | 75 | `Navigator.of(context).pushReplacement(MaterialPageRoute(...))` | `OmniNavigator.pushReplacement(context, (_) => ...)` |
| 27 | `lib/widgets/pickers/exercise_picker_dialog.dart` | 175 | `Navigator.of(context).push(MaterialPageRoute(...))` | `OmniNavigator.push<Exercise>(context, (_) => ...)` |
| 28 | `lib/features/splash/omni_splash_screen.dart` | 77 | `Navigator.of(context).pushReplacement(PageRouteBuilder(..., transitionsBuilder: FadeTransition))` | `OmniNavigator.pushReplacementFade(context, (_) => ...)` |
| — | `lib/features/home/home_screen.dart` body | 166 | `body: OmniGradientBackground(child: ...)` | Removed — route-level gradient covers the full page |

Total migrated: 28 `Navigator.*` calls (27 push/pushReplacement + 1 `PageRouteBuilder`) plus 1 redundant body-level `OmniGradientBackground` removal across 31 call-site entries.

---

## Test Files Reviewed

| Test file | Decision | Rationale |
|---|---|---|
| `test/session_edit_duration_test.dart` | Left in place | Uses `MaterialPageRoute` as a setup-convenience harness to pump `WorkoutSessionScreen` inside a Navigator. Does not simulate real user navigation; migration would add no test coverage value. |
| `test/interaction_flow_test.dart` | Left in place | Uses `MaterialPageRoute` to push `ExercisePickerDialog` in a test scaffold. Setup convenience only; dialog's own navigation uses `OmniNavigator` in production. |
| `test/session_finish_timers_test.dart` | Left in place | Uses `MaterialPageRoute` to push `WorkoutSessionScreen` inside a helper. Setup convenience; real finish flow goes through `_pushSessionReplacement` → `OmniNavigator`. |
| `test/unsaved_changes_dialog_test.dart` | Left in place | Uses `MaterialPageRoute` to push `WorkoutSessionScreen` inside a helper. Setup convenience; production back-navigation uses `Navigator.pop`. |
| `test/screen_widget_test.dart` | Reviewed — no raw routes found | All navigation tested via `MaterialApp(home: ...)` pattern. |
| `test/state_test.dart` | Reviewed — no raw routes found | Pure state unit tests; no navigation code. |
| `test/widget_test.dart` | Reviewed — no raw routes found | No raw route construction. |
| `test/session_toolbar_rework_test.dart` | Reviewed — no raw routes found | No raw route construction. |
| `test/unsaved_changes_dialog_test.dart` | Reviewed — see row above | — |

---

## Post-Migration Grep Confirmation

Search: `MaterialPageRoute|PageRouteBuilder` in `lib/features/` and `lib/widgets/`

**Result: zero matches.**

```
$ grep -r "MaterialPageRoute\|PageRouteBuilder" lib/features/ lib/widgets/
(no output)
```
