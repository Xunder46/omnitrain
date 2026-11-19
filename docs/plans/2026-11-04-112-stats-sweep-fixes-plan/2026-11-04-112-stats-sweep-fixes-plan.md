# 112 — Two gaps from the Stats input sweep: the Mix note and the wrist's food day

Status: SEEDED by the lead 2026-11-04 (no architect run: exact production text below; test text sits in the builder briefs).
Base commit: `.work/2026-11-04-112-stats-sweep-fixes/base.txt` (837a4031). Track: phone only (`lib/`, `test/`, `docs/`).
Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart` (another session's DST hunks), `test/stats_dst_day_arithmetic_test.dart`, `.claude/commands/crew.md`, `.github/copilot/crew-rules.md`.
Series: Stats input sweep 2026-11-03 (scouts 111), items 1 and 3. Owner answers 2026-11-04: **fix 1 and 3; item 2 (Stats open while a watch session or Health weigh-in arrives) is deferred**; same-name exercises stay merged in Recent PRs; a positive and a caution card together are fine unless they contradict. Committing is pre-approved when verified (`commit-ok.txt`).
Out of scope: item 2, Recent PRs identity, same-topic card pairs, the food read cost (measured 2026-11-04: 2.5 ms per read at 2,190 stored rows, 8.2 ms at 6,570, Hive on the Mac).

## Goal and acceptance

What a user sees after this PR:

1. **Mix note.** When the Training Mix shows time instead of effort because more than a quarter of the last four weeks of training is unrated (even though 4 or more weeks are rated), a note under the legend says so: `Showing time for now. Effort needs most of the last 4 weeks rated.` Before, the strip silently showed time. With fewer than 4 rated weeks the note is unchanged (`... Effort appears once 4 weeks are rated (N of 4 so far).`); under the effort measure there is still no note.
2. **Wrist food on the right day.** A food quick-logged on the watch is filed on the day the user tapped it, not the day the phone received it. A food logged at 23:55 on the wrist and delivered at 00:10 lands on the earlier day (its row says that day, with that day's saved targets); a delivery on the same day, or one with no usable time, lands on today as before. A repeat delivery still leaves one row per food per day.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-18601 | The note's condition changes from `!_isLoad && layer.ratedWeeks < kTrainingLoadMinRatedWeeks` to `!_isLoad`; its text is the old sentence while `layer.ratedWeeks < kTrainingLoadMinRatedWeeks`, otherwise the new sentence. The key stays `mix_baseline_note`. No service change: the layer already says it is on time; time with 4+ rated weeks can only come from the unrated-share rule (`stats_progress_service.dart` ~line 845, `kTrainingLoadMaxUnratedShare`) | `mix_layer.dart` |
| D-18602 | New `NutritionState.logConsumedFoodOnDay(Food, double amount, {required DateTime loggedAt})` for a day BEFORE today: finds the one row for `(sourceFoodId, that local day)` through `getConsumedFoodsInRange(dayMs, dayMs)` and updates its amount, otherwise creates a row with `dateMs` = that day's local midnight, `loggedAtMs` = `loggedAt`, targets from `getNutritionTargetForDate(dayMs)` (default `NutritionTarget()` when null). It never touches `_consumedToday` (today's ring). A `loggedAt` on or after today delegates to `logConsumedFoodAt` | `nutrition_state.dart` |
| D-18603 | The ConsumedFood snapshot construction in `logConsumedFood` moves into a private `_snapshotFor(...)` used by both methods; `logConsumedFood`'s behaviour stays byte-identical (existing tests are the proof) | `nutrition_state.dart` |
| D-18604 | The bridge reads `event['loggedAt']` (ISO string; `DateTime.tryParse`, then `.toLocal()`). The day is "today" (existing `logConsumedFoodAt` path) when `loggedAt` is null, unparseable, later than `_clock()`, or on the same local date as `_clock().toLocal()`; otherwise `logConsumedFoodOnDay` | `watch_nutrition_log_bridge.dart` |
| D-18605 | The comparison uses the bridge's injected clock, not `DateTime.now()`, so the existing quick-log tests (clock and `loggedAt` both on 2026-07-13) keep taking the today path | `watch_nutrition_log_bridge.dart` |
| D-18606 | Tests that store a row run under Mock AND Hive (store-order dependence, playbook (i)); Hive taps never run inside `testWidgets` | tests |

## Exact production code

`lib/features/stats/widgets/mix_layer.dart`, the block at ~line 186 (CURRENT lines):

```dart
          if (!_isLoad && layer.ratedWeeks < kTrainingLoadMinRatedWeeks) ...[
            const SizedBox(height: _tightGap),
            Text(
              'Showing time for now. Effort appears once '
              '$kTrainingLoadMinRatedWeeks weeks are rated '
              '($_ratedWeeks of $kTrainingLoadMinRatedWeeks so far).',
              key: const Key('mix_baseline_note'),
```

becomes

```dart
          if (!_isLoad) ...[
            const SizedBox(height: _tightGap),
            Text(
              layer.ratedWeeks < kTrainingLoadMinRatedWeeks
                  ? 'Showing time for now. Effort appears once '
                        '$kTrainingLoadMinRatedWeeks weeks are rated '
                        '($_ratedWeeks of $kTrainingLoadMinRatedWeeks so far).'
                  : 'Showing time for now. Effort needs most of the last '
                        '4 weeks rated.',
              key: const Key('mix_baseline_note'),
```

(the rest of the `Text(...)` — `maxLines: 2`, ellipsis, style — stays).

Nutrition and bridge code are in the P1 brief (exact text).

## Scenarios

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-18601 | Stats screen, Mock, the fixture of plan 100's S-17309 (rated weeks in 4 distinct weeks, but unrated sessions over a quarter of the window time) so the measure is time with `ratedWeeks >= 4` | `mix_baseline_note` is present and its text is exactly `Showing time for now. Effort needs most of the last 4 weeks rated.` | the note's condition requires `ratedWeeks < 4`, so nothing renders |
| S-18602 | Same data with the unrated share just inside the limit (exactly 25% unrated, load measure) | no `mix_baseline_note` | guards the other side: the new branch must not show under load |
| S-18603 | Existing S-3204 fixtures (fewer than 4 rated weeks) | text unchanged: `... Effort appears once 4 weeks are rated (N of 4 so far).` | the ternary must keep the old branch (mutant: always the new sentence) |
| S-18604 | Bridge, Mock + Hive: clock `2026-07-14 00:10` local, event `loggedAt` `2026-07-13 23:50` local, food with amount | one row, `dateMs` = 2026-07-13 local midnight, `loggedAtMs` = the event time; `NutritionState.consumedToday` unchanged (empty) | without the change the row lands on the receive day (today) |
| S-18605 | Same event delivered twice, second with a different servings value | still one row for that food and day, its amount is the second value | the past path must keep one row per food per day |
| S-18606 | A target saved for 2026-07-13 that differs from the current one | the row's four frozen targets are 2026-07-13's | targets must come from that day |
| S-18607 | Event `loggedAt` later than the clock; event with no `loggedAt`; event with `loggedAt: 'not a time'` | each lands on today (consumedToday gains the row) | the three guards of D-18604 (one test per arm) |
| S-18608 | State level, Mock + Hive: `logConsumedFoodOnDay` for a day before today, then again for the same food and day | one stored row; second call updates the amount; a third call for another food adds a second row | the day-uniqueness arm |
| S-18609 | State level: `logConsumedFoodOnDay` with a `loggedAt` today | delegates: the row is in `consumedToday` | the delegate arm |

## Phases

| Phase | Agent | Write scope | Items | Order |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/state/nutrition_state.dart`, `lib/state/watch/watch_nutrition_log_bridge.dart` | 3 | first, parallel with P3 |
| P3 | crew-builder-app | `lib/features/stats/widgets/mix_layer.dart` | 1 | first, parallel with P1 |
| P2 | crew-builder-app | `test/nutrition_log_on_day_test.dart` (new), `test/watch_nutrition_quick_log_test.dart` | S-18604..S-18609 | after P1 |
| P4 | crew-builder-app | `test/mix_layer_screen_test.dart` | S-18601..S-18603 | after P3 |
| P5 | the lead | `docs/stats_screen.md`, `docs/state_management/nutrition_state.md`, `docs/state_management/watch_surface_nutrition.md` | the Docs delta rows | after P2 and P4 |
| P6 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P5 |

Readers: the Mix note text is asserted in `test/stats_rated_weeks_screen_test.dart:182`, `test/mix_layer_screen_test.dart:982`, `:2485`, `:2502` and found by key in `test/stats_mix_horizon_screen_test.dart:318`; the existing quick-log tests use `loggedAt` `2026-07-13T17:00:00Z` with a clock of `2026-07-13T12:00Z` (same local day in a negative-offset zone: the builder checks the zone the suite runs in and, if the two straddle a local midnight there, sets the fixture's clock and `loggedAt` to the same hour). If the full suite finds another reader, a closed fix brief adds its file.
Done criteria: touched tests green with real counts (Mock and Hive for the stored behaviour); `flutter analyze` not above 181; full `flutter test` green apart from the known flaky red (S-R3); invariant grep clean; `docs_indexing_contract_test.dart` and `ui_standards_contract_test.dart` green; `plan-lint.py after` clean.
Mutations (lead): M1 note condition back to `!_isLoad && layer.ratedWeeks < ...`; M2 the ternary always the old sentence; M3 always the new sentence; M4 bridge ignores `loggedAt` (always `logConsumedFoodAt`); M5 bridge treats a future `loggedAt` as a past day; M6 `logConsumedFoodOnDay` skips the existing-row lookup; M7 targets from today (`getNutritionTarget`-style) instead of that day; M8 `logConsumedFoodOnDay` writes into `_consumedToday`.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/stats_screen.md | MODIFIED | 4 weeks are rated (N of 4 so far).`; under the load measure no note renders. | `Showing time for now. Effort needs most of the last 4 weeks rated.` | S-18601 |
| docs/state_management/nutrition_state.md | ADDED | - | `logConsumedFoodOnDay(Food, double amount, {required DateTime loggedAt})` | S-18608 |
| docs/state_management/nutrition_state.md | MODIFIED | is written here through `logConsumedFoodAt`, | on the day the wrist logged it | S-18604 |
| docs/state_management/watch_surface_nutrition.md | MODIFIED | events into the phone's own day log through `NutritionState.logConsumedFoodAt`. | `NutritionState.logConsumedFoodOnDay` | S-18604 |

## Progress

- [x] P1 nutrition state and bridge
- [x] P3 Mix note
- [x] P2 tests for the wrist food day
- [x] P4 tests for the Mix note
- [x] P5 docs
- [x] P6 review
- [x] lead: verify, mutations, full suite

## Assumption Log

- 2026-11-04 lead: owner chose to fix sweep items 1 and 3 and defer 2. The note's new sentence is the lead's default (observable wording; owner told in the report).
- 2026-11-04 lead: the scout's item 3 claim was verified: the wrist event carries `loggedAt` (`WatchSessionEngine.swift` ~line 1397) and the bridge ignored it.
- 2026-11-04 lead: timing probe (throwaway, deleted): `getConsumedFoodsInRange` costs 2.5 ms per read at 2,190 rows and 8.2 ms at 6,570 rows on Hive on the Mac, so the three reads per Stats load are not a performance problem and are not changed.
- 2026-11-04 lead: results. Mutations M1-M13 (note condition, both sentences, bridge ignoring `loggedAt`, future/missing/unreadable `loggedAt`, same-day check without month or year, on-day lookup, targets from today, write into today's cache, delegate arm) each failed a test after one tests-only fix (M11, the month, survived first: every test used a clock one day after the tap; two tests added). Review: APPROVE WITH FIXES, one minor (the target read moved after an await in `logConsumedFood`; restored in a one-line fix). The full suite found three readers the seed did not list (`watch_session_queue_test` S-9722, `watch_transport_test` S-002, `watch_water_log_test` S-94a-19): a fixed 2026-07-13 wrist event meeting a phone bridge on the real clock; fixed by passing the wiring's `clock` to the nutrition bridge (`watch_sync_wiring.dart`, null keeps the real clock in the app) and a bridge clock in the water test. Final: full suite +6369 ~2, 0 failed; `flutter analyze` 181 (baseline); invariant grep clean; contract tests +54; plan-lint after clean.
