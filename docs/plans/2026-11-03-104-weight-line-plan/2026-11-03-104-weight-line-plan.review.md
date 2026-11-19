# Review: 2026-11-03-104-weight-line-plan · P1, P2a, P2b, P3 · base..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 4 · tests: not re-run — the brief states the lead ran the full suite, `flutter analyze` and the contract tests; the touched test files are green with +88 on both harnesses (Mock and Hive)
Diff vs Predicted Files: outside: `docs/README.md`, `docs/design_system.md`, `docs/navigation_and_screens.md` (doc cross-reference edits; see finding 3). `lib/core/services/stats_progress_service.dart` and `test/stats_dst_day_arithmetic_test.dart` are the other session's dirty files, ignored per the brief.
## Findings

## Answers to the brief's questions

**Q1 — unlisted production behaviour: none.** `weight_trend.dart`, `weight_trend_service.dart`, `weight_trend_row.dart`, `settings_state.dart`, `settings_screen.dart` and `stats_screen.dart` match the plan's "Exact production code" line for line (constants, the UTC re-read spacing, the `!= 'false'` read with `defaultValue: 'true'`, the STATS section after WORKOUT, the `_load` gate on `completedSessions > 0`, the build condition `_weightTrend != null && widget.settingsState.showWeightTrend`). The screen already wraps its body in a `ListenableBuilder` on `settingsState` (stats_screen.dart:251), so no listener was needed — as the plan anticipated.

**Q2 — rule walk: no wrong figure, sign or spurious trend found.**
- Window edges: `fromMs` is local midnight of today−27, `endMs` local midnight of tomorrow; a weigh-in at 23:59 today is inside (`< endMs`), one at 28 days ago 12:00 is outside (tested, S-17701(e)); the first day at 00:00 (today−27 00:00) is inside and 27 days from today.
- A weigh-in at 23:59 yesterday: included; its UTC date is yesterday, so the spacing counts whole calendar days correctly.
- Two weigh-ins on the same day: `apart` = 0 < 7 → null.
- A clock-change day inside the window: the dates are re-read as UTC before the difference, so a 23-hour day cannot read as 6 days (tested; see finding 4 for the test's zone dependence).
- A non-kg unit: filtered by `unitId == MetricIds.unitKg` ('unit-kg', the canonical unit `ProfileMeasurements.bodyweight` also writes); the widget converts for display. The test's `unit-lb` literal is a synthetic non-kg id, which is all the filter test needs.
- `weightTrendLine` rounding edges: 0.05 → `toStringAsFixed(1)` = "0.1" → `+0.1`/`−0.1` (sign taken from the raw change, magnitude from the rounded abs, so −0.049 reads `no change`, never `−0.0`); 0.049 → "0.0" → `no change`; −0.05 → `−0.1`. Consistent at all three edges.

**Q3 — the screen.** With the Fuel row absent, the Instruments list empty or the Mix layer absent, the Weight block still draws: it is an independent `if` in the ListView's non-empty branch, after whatever blocks exist. With no completed session the screen takes the empty-state branch (`_totalSessions == 0`), where the block is not even reachable, and `_load` sets `_weightTrend` null in that case — no state shows it without a session. It hides when the trend is null (fewer than two usable weigh-ins, closer than 7 days, or a repository throw) or the switch is off. Flipping the switch while Stats is open or after returning applies without a reload: `showWeightTrend` is read in `build` inside the `ListenableBuilder` on `settingsState`, and `_weightTrend` is computed on every load regardless of the switch, so flipping it back on needs no reload either. One placement note: finding 1.

**Q4 — assertions and docs.** No assertion was found satisfied for the wrong reason:
- S-17701(e) uses 81.0/80.0 rather than the plan's 80.8/80.2 for the 28-days-ago fixture; the assertion (null) is unaffected and the boundary still kills M2.
- The switch-off, one-weigh-in and 6-days-apart `findsNothing` tests would each hold with the block simply broken, but the positive test in the same file (`findsOneWidget` + exact line text) is the other half of each pair, and the brief records M1/M7 killed by the lead's pass.
- S-17706's `find.byType(Switch).at(1)` is not luck: settings_screen.dart has exactly four `Switch` widgets — Effort Rating (:859), Weight on Stats (:885), then HEALTH's `Write workouts` (:923) and `Read body weight` (:937); the SOUNDS rows and Notification Permission have none, and the WATCH section is absent in the test (`watchLinkState` null). `.at(1)` is the Weight on Stats switch deterministically.
- The empty-state assertion `find.text('No sessions yet')` matches the real empty-state title (stats_screen.dart:407).
- Docs: every sentence I read against the code is true and cites tests that exist with exact names — `S-17701 weightTrend`, `S-17702 weightTrendLine`, `S-17703 WeightTrendService — Mock`/`— Hive` (harness names are exactly 'Mock'/'Hive' in `repository_harness.dart`), the two S-17704 test names in `settings_state_test.dart`, `S-17705 the Weight block — Mock/Hive`, `S-17706 the Weight on Stats switch — Mock` › `the row sits after Effort Rating and flips only its own setting`. Exception: finding 2.

**Q5 — user-visible changes not in the plan: none.** The only new strings are the plan's own: `STATS`, `Weight on Stats`, `Show your weight change over the last 4 weeks`, the `Weight` card header, and the line copy. Nothing on Settings moved — the WORKOUT block is untouched and the new section is a pure insertion before APPLE WATCH; the first Switch of the screen stays Effort Rating's.

## Findings

1. [Minor] lib/features/stats/stats_screen.dart:360-369 — when both the Fuel row and the Weight block show, the `Weight` header sits with zero gap below the Fuel card: `FuelSection` has no trailing spacer and the Weight `if` follows the Fuel block's closing `]` directly, while every other adjacent pair on the screen is separated by `SizedBox(height: 24)`. A user sees the Weight header flush against the Fuel surface. This is the plan's own snippet, so it is an owner decision, not a builder deviation. Fix: a `const SizedBox(height: 24)` before the Weight block (or after `FuelSection`). Guard: none practical (layout gaps are not asserted in this suite); a widget test asserting `getTopLeft(weight_trend).dy − getBottomRight(fuel_section).dy >= 24` would do it.
2. [Minor] docs/design_system.md:189 — the Stats row now lists "the Weight block's `Weight`" among headers "Verified by" a test list that contains no test asserting that header: `test/weight_trend_screen_test.dart` finds the block by key `weight_trend`, never `find.text('Weight')`. A maintainer relying on the row would believe the new header is pinned by the listed tests. Fix: add `test/weight_trend_screen_test.dart` to the row's verification list (or assert the header text in the S-17705 positive test). Guard: `find.text('Weight')` inside the S-17705 positive test.
3. [Minor] docs/navigation_and_screens.md:199 (also docs/README.md:69, docs/design_system.md:189) — three doc files edited outside the plan's Docs delta and outside every phase's write scope. The added Weight-block content is true against the code, but the navigation row also rewrites the Signals gating sentence ("the signals that read the load wait for four of the last 12 weeks… the others speak from the first session"), which is not this plan's change. Fix: none needed for the Weight content; the Signals rewrite should be confirmed by whoever owns the Signals work. Guard: none.
4. [Minor] test/weight_trend_test.dart:139-155 — the spring-forward test's power against M3 depends on the runner's timezone observing DST: on a UTC runner (a typical CI image) Mar 5→Mar 12 noon is exactly 168 hours, so the test passes with the mutant `lastDay.difference(firstDay).inDays` in place too. The lead's pass killed M3 on this machine (established), but a future regression would not be caught on such a runner. Fix: a comment naming the zone requirement, or skip the assertion when the zone has no March DST shift; Dart cannot fix a zone without a package. Guard: the test itself, zone-dependent.

## Assumption Log rulings
- "Independent review of 2026-11-03: … `getMeasurementHistory('bodyweight')` returns the entries (kg canonical…)" — ratify: the service reads exactly that, and the filter matches the canonical unit `ProfileMeasurements.bodyweight` writes ('unit-kg').
- "Defaults taken: block under Fuel; switch in a new STATS Settings section…; the figures use the user's weight unit; a rounded-zero change reads `no change`" — ratify: all four implemented as stated and tested.
- "Not run on a device or simulator" — ratify: stands; the Fuel→Weight gap (finding 1) is exactly the kind of layout a test cannot see.
- The log is non-empty; no builder assumption needed a new ruling.

## Docs delta
- docs/stats_screen.md "no Instruments list, no Fuel row and no Weight block" -> applied
- docs/stats_screen.md "Otherwise it is five blocks in a fixed order" -> applied
- docs/stats_screen.md "[Weight block](#weight-block)" after the Fuel row clause -> applied
- docs/stats_screen.md ADDED "### Weight block" -> applied
- docs/profile_and_measurements.md "the Mix, Signals, Instruments, Fuel and Weight blocks" -> applied
- docs/profile_and_measurements.md ADDED "The weight line on Stats" -> applied
- docs/theme_and_settings.md ADDED "Weight on Stats" -> applied
- docs/state_management/app_state.md ADDED `_showWeightTrend` -> applied
- docs/state_management/app_state.md ADDED `showWeightTrend` -> applied
- Doc edits the table does not name: docs/README.md (Stats Screen row gains the Weight block), docs/design_system.md (Stats header row gains `Weight`), docs/navigation_and_screens.md (StatsScreen row gains the Weight block and rewrites the Signals sentence) — see finding 3.

## Scenario coverage
S-17701 -> test/weight_trend_test.dart · group `S-17701 weightTrend` (constants + 9 tests: 27 days, 6 days, exactly 7, one/none, 28-days-ago outside, lb+height filtered, reverse order, three entries, spring-forward)
S-17702 -> test/weight_trend_test.dart · group `S-17702 weightTrendLine` (fall, rise, ±0.04 no change, lbs label)
S-17703 -> test/weight_trend_test.dart · groups `S-17703 WeightTrendService — Mock` and `S-17703 WeightTrendService — Hive` (no entries; two 14 days apart)
S-17704 -> test/settings_state_test.dart · `S-17704 SettingsState defaults the weight line to on`, `S-17704 SettingsState persists and reloads the weight line switch`
S-17705 -> test/weight_trend_screen_test.dart · group `S-17705 the Weight block — Mock` and `— Hive` (kg line + below Fuel, lbs line, switch off, one weigh-in, 6 days apart, no completed session)
S-17706 -> test/weight_trend_screen_test.dart · group `S-17706 the Weight on Stats switch — Mock` · `the row sits after Effort Rating and flips only its own setting`
