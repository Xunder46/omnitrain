# Route Migration Audit

> **HISTORY — DO NOT TREAT AS CURRENT STATE.**
> This document is the historical record of the original `centralized-route-system` migration (May–June 2026). It is preserved here for the audit trail only.
> The navigation contract is now enforced by the automated test `test/navigation_contract_enforcement_test.dart`. If this audit and the automated test ever disagree, the test wins.
> **Current source of truth:** [`.github/agents/docs/navigation_contract.md`](../navigation_contract.md).
> **Last reconciled against source:** 2026-06-29 (no claim in this audit was modified; the audit is read-only history).

---

Centralized route system migration completed for the `centralized-route-system` feature.
Post-migration grep for `MaterialPageRoute` and `PageRouteBuilder` in `lib/features/` and `lib/widgets/` returns **zero results** (including the Hub sheet — see addendum below).

> **Status note (June 2026):** This document is the historical record of the
> original migration. It is **no longer the enforcement mechanism** for the
> navigation contract. The contract is now enforced automatically by
> `test/navigation_contract_enforcement_test.dart`, which fails the build if
> any `MaterialPageRoute(` or `PageRouteBuilder(` construction is added to
> `lib/features/` or `lib/widgets/` outside `lib/core/navigation/`. See
> `.github/agents/docs/navigation_contract.md` ("Enforcement") for details.
> If the audit and the automated test ever disagree, the test wins.

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

**Result (as of original migration)**: zero matches in `lib/features/`.

The Hub sheet (`lib/widgets/hub/hub_sheet.dart`) was intentionally
left out of the original migration per its separate owner; it
still used `MaterialPageRoute` for its five internal transitions
and was tracked separately. The Add Food alignment (see first
addendum below) kept `lib/features/nutrition/` at zero matches.
The Hub sheet has since been aligned (see second addendum below)
so the audit now reports zero matches across both `lib/features/`
and `lib/widgets/`.

---

## Addendum — Add Food navigation alignment (June 2026)

Two more `Navigator.of(context).push(MaterialPageRoute(...))` call sites
in `lib/features/nutrition/add_food_screen.dart` were aligned to the
standard navigation path after the original migration landed. Both
predated the migration but were missed by the original audit because
the corresponding screens (`_NewFoodFormScreen`,
`_LegacyLibraryEditScreen`) were private `AddFoodScreen` siblings
added in a later iteration.

| # | File | Pre-alignment line | Before | After |
|---|---|---|---|---|
| 29 | `lib/features/nutrition/add_food_screen.dart` | 121 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => _NewFoodFormScreen(...)))` (from `_openNewFoodForm` — `+ New Food` bottom CTA) | `OmniNavigator.push<void>(context, (_) => _NewFoodFormScreen(...))` |
| 30 | `lib/features/nutrition/add_food_screen.dart` | 893 | `Navigator.of(context).push(MaterialPageRoute(builder: (_) => _LegacyLibraryEditScreen(...)))` (from `_UserFoodRowState._openEdit` legacy branch — pre-D-2 custom row tap) | `OmniNavigator.push<void>(context, (_) => _LegacyLibraryEditScreen(...))` |

**Why**: Without the `OmniRoute` `opaque = true` +
`OmniGradientBackground` wrapper, the outgoing `AddFoodScreen` and
the incoming sub-screen were both painted during the slide — the
momentary "two screens overlapping" frame observed in the Add Food
area. After alignment, both sub-screens fully occlude the host
during the transition, matching every other screen push in the
app.

**Test coverage**: two widget tests in
`test/screen_widget_test.dart` (`+ New Food bottom CTA pushes the
new-food form via OmniRoute (S-N1)` and `Legacy library-only custom
food row tap pushes the legacy edit shim via OmniRoute (S-N2)`)
capture the actual pushed `Route` via a `NavigatorObserver` and
assert it is an `OmniRoute<void>`, not a `MaterialPageRoute<void>`.

Total migrated: 30 `Navigator.*` calls (29 push/pushReplacement + 1
`PageRouteBuilder`) plus 1 redundant body-level
`OmniGradientBackground` removal across 33 call-site entries.

---

## Addendum — Hub sheet navigation alignment (June 2026)

Five more `Navigator.of(context).push(MaterialPageRoute(...))` call
sites in `lib/widgets/hub/hub_sheet.dart` were aligned to the
standard navigation path after the Add Food addendum landed.
These were the five destinations the Hub sheet offers — they were
called out in the original migration audit as "tracked separately"
because the Hub sheet's owner was the home screen, not a feature
screener. The screen they're hosted in is the quick-access Hub
sheet surfaced from the home-screen logo tap.

| # | File | Pre-alignment line | Before | After |
|---|---|---|---|---|
| 31 | `lib/widgets/hub/hub_sheet.dart` | 67 | `Navigator.of(context).push(MaterialPageRoute(builder: (context) => CalendarScreen(...)))` (Calendar tile) | `OmniNavigator.push(context, (_) => CalendarScreen(...))` |
| 32 | `lib/widgets/hub/hub_sheet.dart` | 84 | `Navigator.of(context).push(MaterialPageRoute(builder: (context) => StatsScreen(...)))` (Stats tile) | `OmniNavigator.push(context, (_) => StatsScreen(...))` |
| 33 | `lib/widgets/hub/hub_sheet.dart` | 94 | `Navigator.of(context).push(MaterialPageRoute(builder: (context) => NutritionScreen(...)))` (Nutrition tile) | `OmniNavigator.push(context, (_) => NutritionScreen(...))` |
| 34 | `lib/widgets/hub/hub_sheet.dart` | 104 | `Navigator.of(context).push(MaterialPageRoute(builder: (context) => ProfileScreen(...)))` (Profile tile) | `OmniNavigator.push(context, (_) => ProfileScreen(...))` |
| 35 | `lib/widgets/hub/hub_sheet.dart` | 114 | `Navigator.of(context).push(MaterialPageRoute(builder: (context) => SettingsScreen(...)))` (Settings tile) | `OmniNavigator.push(context, (_) => SettingsScreen(...))` |

**Why**: Without the `OmniRoute` `opaque = true` +
`OmniGradientBackground` wrapper, the outgoing `HubSheet` and the
incoming destination screen were both painted during the slide —
the momentary "two screens overlapping" frame observed on every
Hub sheet launch. The navigation contract originally cited the
Hub sheet as the canonical symptom; this alignment removes the
last raw `MaterialPageRoute` usage from `lib/widgets/` so the
Hub sheet transitions are visually indistinguishable from every
other screen push in the app.

**Layout guard**: the Hub sheet's layout, the five destinations
it offers, its `MaintenanceTile` grid, and how it is opened /
dismissed are unchanged. A regression test in
`test/hub_interaction_test.dart` (`HubSheet exposes one
maintenance item per documented destination`) pins the
destination set so future refactors cannot silently add or
remove a tile while keeping the navigation contract aligned.

**Test coverage**: five widget tests in
`test/hub_interaction_test.dart` (`HubSheet.{Calendar, Stats,
Nutrition, Profile, Settings} tile pushes via OmniNavigator`) plus
the layout-guard test exercise the production code path and
capture the actual pushed `Route` via a `NavigatorObserver`,
asserting each push is `OmniRoute<dynamic>` and not
`MaterialPageRoute<dynamic>`.

Total migrated: 35 `Navigator.*` calls (34 push/pushReplacement + 1
`PageRouteBuilder`) plus 1 redundant body-level
`OmniGradientBackground` removal across 38 call-site entries.
