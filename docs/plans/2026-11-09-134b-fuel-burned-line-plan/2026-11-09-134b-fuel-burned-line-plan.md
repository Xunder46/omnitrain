# Plan — 134b: the Fuel card says what its lines mean and shows the calories burned per session

**Status**: built, reviewed (phone review: 134d folder) and verified 2026-11-09; uncommitted. Evidence: `docs/plans/2026-11-09-134e-wrist-rest-calories-plan/2026-11-09-134e-wrist-rest-calories-plan.evidence.md` (one file for 134b to 134e).
**Binding conventions**: `docs/global_conventions.md`, `docs/design_system.md`.
**Base commit**: `ff398e1a7ec18409d9fc8c890bf35d2fde656e69` (branch `claude_develop`; 134a is in the same uncommitted tree and is required: `SessionEnergy` and `getSessionEnergy`).
**Parent plan**: `docs/plans/2026-11-08-134-calories-burned-plan/2026-11-08-134-calories-burned-plan.md` (decisions 1 to 8 of its Overview are settled; do not re-ask).

## Overview

Owner (2026-11-08): the Fuel card's `Training 1950 kcal · 123 g` / `Rest 1652 kcal · 123 g` lines are confusing ("what does it mean"); make them clear, and add the average calories burned per session over the same 7 finished days so the owner can see how much they burn next to how much they eat. No "eaten minus burned" number anywhere.

What the user sees after this unit (Stats, FUEL card, below `N/7 days logged`):

```
Training days: 1950 kcal · 123 g protein
Rest days: 1652 kcal · 118 g protein
Burned per session: ~310 kcal · 5 sessions
```

`~` appears when any session in the average is an estimate (a watch-measured session has none; until plan 134c every value is an estimate). A side with no data reads `—`: `Rest days: —`, `Burned per session: —`.

## Goal and acceptance

The three lines above, computed over the same window as the card's other averages (the 7 finished days ending yesterday). Acceptance: S-13430 .. S-13435.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13430 | `FuelSummary` gains three fields with defaults so existing constructors keep compiling: `double? burnedKcalAverage = null`, `int burnedSessionCount = 0`, `bool burnedIsEstimate = false`. Doc comments say: the mean of the stored active kcal over the window's finished sessions that have an energy row; null when none has one | `lib/core/models/fuel_summary.dart:83-101`; the only constructor callers are `computeFuelSummary` and `test/fuel_section_widget_test.dart:45` (grep `FuelSummary(`) |
| D-13431 | `StatsProgressService.computeFuelSummary` fills them from a new private `_burnedInWindow(DateTime from, DateTime to)` using the SAME session rule as `_trainingDayKeys`: a session counts when `endedAtMs != null` and the local day of `startedAtMs` is in `[windowStart, yesterday]` (inclusive, by `OmniDateUtils.startOfDayMs`). For each such session it reads `_repository.getSessionEnergy(session.id)`; a session without a row is skipped from both the sum and the count (a session with no body weight logged has no row). `burnedKcalAverage` = unrounded mean of `activeKcal`; `burnedSessionCount` = rows used; `burnedIsEstimate` = at least one used row has `source == SessionEnergy.sourceEstimated`. Computed whenever the summary exists; the card draws it only under the existing `showsAverages` gate | `stats_progress_service.dart:2115-2194` `computeFuelSummary`, `:2213` `_trainingDayKeys` (rule to mirror); `lib/data/models/models.dart` `SessionEnergy`; 134a D-13401, D-13402 |
| D-13432 | `FuelSection`: `kFuelTrainingLabel = 'Training days'`, `kFuelRestLabel = 'Rest days'`; `_split` returns `'$label: ${_whole(calories)} kcal · ${_whole(protein)} g protein'`, and `'$label: —'` (`kFuelAbsent`) when either value is null. A new static `_burned(...)` returns `'Burned per session: ${tilde}${_whole(average)} kcal · $count session(s)'` (`1 session`, `N sessions`), `tilde` = `'~'` when `burnedIsEstimate`, and `'Burned per session: —'` when `burnedKcalAverage == null`. New caption key `fuel_burned`, drawn after `fuel_split_rest`, inside the same `if (summary.showsAverages)` block. The three lines may wrap to two lines (`maxLines: 2` on these captions only; the other captions stay `maxLines: 1`) | `fuel_section.dart:10, 13, 65-68, 240-259, 339-347` |
| D-13433 | No subtraction anywhere: no figure, text or key combines eaten and burned. A guard test (S-13435) asserts the card's text holds no `net` / `surplus` / `deficit` wording | owner decision 8 |
| D-13434 | kcal only: the app has no energy-unit setting (grep `kJ` / `energyUnit` in `lib/` found none to honour). Whole-number display (`round()`), same as the card's other figures | the lead's grep |

## Scenarios

Both repositories run S-13430 .. S-13433 (`harnessFactories`, plain `test()`); S-13434 and S-13435 are widget tests on a hand-built `FuelSummary` (no repository).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13430 | window sessions (via `seedSession`): d1 estimated 300.0, d3 measured 400.0, d6 estimated 500.0. Outside or excluded: d0 estimated 9000.0 (today), d8 estimated 7000.0 (before the window), a rolling unfinished session on d2 (`isRolling: true`, which `seedSession` leaves unended) with a row of 8000.0. Food: three logged days d1, d2, d3 (any calories) so the summary exists | `burnedKcalAverage` exactly 400.0, `burnedSessionCount` 3, `burnedIsEstimate` true | the fields do not exist |
| S-13431 | arm test for `burnedIsEstimate`: (a) d1 and d2 sessions both `measured` (250.0 and 350.0); (b) d1 `measured`, d2 `estimated` | (a) average 300.0, count 2, `burnedIsEstimate` false; (b) true | the summary has no estimate flag at all |
| S-13432 | d1 session with a row 300.0, d2 session with NO row, d3 session with a row 500.0; then, in a second case, sessions d1 and d2 with no rows at all | first: average 400.0, count 2 (the row-less session is in neither sum nor count); second: `burnedKcalAverage` null, count 0, `burnedIsEstimate` false | no rule for row-less sessions |
| S-13433 | the window's day edges: a session on d7 (the window's first day, `daysAgo: 7`) with a row 100.0 counts; d8 (daysAgo 8) with 900.0 does not; d1 with 300.0 counts | average 200.0, count 2 | no window rule (proves both ends: d7 in, d8 out) |
| S-13434 | `FuelSection` on a hand-built summary (3+ logged days): training 1950 kcal / 123 g, rest 1652 / 118, burned 310.4 over 5 sessions estimated | texts exactly `Training days: 1950 kcal · 123 g protein`, `Rest days: 1652 kcal · 118 g protein`, `Burned per session: ~310 kcal · 5 sessions`; then the same with `burnedIsEstimate` false and count 1, burned 310.4: `Burned per session: 310 kcal · 1 session`; null burned: `Burned per session: —`; rest side null: `Rest days: —`; with only 2 logged days none of the three keys exists | old wording and no burned line |
| S-13435 | the same rendered card, every `Text` on it | none of them contains `net`, `surplus`, `deficit`, `left to burn` (case-insensitive); and the burned line's text contains no digit that is a subtraction of the calories figure (asserted by the exact-text checks of S-13434) | guard of D-13433 (the lead proves it by adding a net line as a mutation) |

The existing assertions of the old wording are updated in the same change (readers list below).

## Phases (outline)

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 data | crew-builder-app | `lib/core/models/fuel_summary.dart`, `lib/core/services/stats_progress_service.dart` (one new private method + the constructor call), new `test/fuel_burned_summary_test.dart` | serial first |
| P2 card | crew-builder-app | `lib/features/stats/widgets/fuel_section.dart`, `test/fuel_section_widget_test.dart`, `test/fuel_row_screen_test.dart` | after P1 |
| P3 docs | crew-docs-keeper | the Docs delta rows | after P2 |

### P1 data (one crew-builder-app run)

Write the report FIRST as a skeleton, then fill it. Never run the full `flutter test`.

1. New `test/fuel_burned_summary_test.dart` with S-13430 .. S-13433, red first (the fields do not exist, so it fails to compile: that is the red).
2. `fuel_summary.dart`: add the three fields of D-13430 after `restProteinAverage` (constructor: `this.burnedKcalAverage, this.burnedSessionCount = 0, this.burnedIsEstimate = false`, not `required`).
3. `stats_progress_service.dart`: add `_burnedInWindow` beside `_trainingDayKeys` and pass its three results in the `FuelSummary(...)` call (lines ~2169-2193). Code to write (adjust names to the file's imports; `SessionEnergy` is in `models.dart`, already imported there):

```dart
  /// The completed sessions that started on a day in `[from, to]` and carry an
  /// energy row: their mean active kcal, how many that is, and whether any of
  /// them is an estimate. A session without a row (no body weight was logged
  /// when it ended) is in neither the mean nor the count.
  Future<({double? average, int count, bool estimated})> _burnedInWindow(
    DateTime from,
    DateTime to,
  ) async {
    final sessions = (await _loadHistory()).sessions;
    final fromDay = OmniDateUtils.startOfDayMs(from);
    final toDay = OmniDateUtils.startOfDayMs(to);
    var total = 0.0;
    var count = 0;
    var estimated = false;
    for (final s in sessions) {
      if (s.endedAtMs == null) continue;
      final day = OmniDateUtils.startOfDayMs(
        DateTime.fromMillisecondsSinceEpoch(s.startedAtMs),
      );
      if (day < fromDay || day > toDay) continue;
      final row = await _repository.getSessionEnergy(s.id);
      if (row == null) continue;
      total += row.activeKcal;
      count++;
      if (row.source == SessionEnergy.sourceEstimated) estimated = true;
    }
    return (
      average: count == 0 ? null : total / count,
      count: count,
      estimated: estimated,
    );
  }
```

   and in `computeFuelSummary`, after `final target = ...`: `final burned = await _burnedInWindow(windowStart, yesterday);` and in the constructor call `burnedKcalAverage: burned.average, burnedSessionCount: burned.count, burnedIsEstimate: burned.estimated,`.
4. Run `bash .github/copilot/scripts/macos/gateway.sh test -- test/fuel_burned_summary_test.dart`, then `-- test/fuel_summary_window_test.dart`, then `-- test/fuel_row_screen_test.dart`; paste the counts.

Done: all three green; `flutter analyze` issue count equal to the baseline (181), 0 errors; no other file changed.

### P2 card (one crew-builder-app run)

Write the report FIRST as a skeleton. Never run the full `flutter test`. No layout change beyond the briefed lines.

1. Update `test/fuel_section_widget_test.dart`: its `_summary` helper gains the three burned parameters (named, defaulted); add S-13434 and S-13435 (hand-built summary, `_pumpFuel`, the existing finder style by key). Red first.
2. `fuel_section.dart`: `kFuelTrainingLabel = 'Training days'`, `kFuelRestLabel = 'Rest days'`; `_split` per D-13432; add `static String _burned(double? average, int count, bool estimated)`; give `_caption` an optional `int maxLines = 1` and pass `maxLines: 2` for the three lines; draw `fuel_burned` after `fuel_split_rest`. Update the class doc comment's first paragraph to say the row also shows the average burned per session.
3. Update `test/fuel_row_screen_test.dart`: every literal `'Training 300 kcal · 30 g'`, `'Rest 580 kcal · 58 g'`, `'Training $_kAbsent'`, `'Rest $_kAbsent'`, `'Rest 300 kcal · 30 g'` (lines ~487, 538-541, 583-586, and any others a grep for `Training ` / `Rest ` finds) becomes the new wording (`'Training days: 300 kcal · 30 g protein'`, `'Rest days: —'`, ...).
4. Run the three fuel test files named in P1 plus `bash .github/copilot/scripts/macos/gateway.sh test -- test/ui_standards_contract_test.dart`; paste counts.

Done: all green; analyze equal to baseline.

### P3 docs (one crew-docs-keeper run)

Run no test. Execute the Docs delta table; the QA list does not apply.

## Readers to update (found by the lead)

| Reader | What it reads | Action |
|---|---|---|
| `test/fuel_row_screen_test.dart` | the rendered `Training` / `Rest` strings (S-1105 487-488, S-1106 538-541 and 583-586) | new wording (P2 item 3) |
| `test/fuel_section_widget_test.dart` | `FuelSummary(...)` constructor, `fuel_split_*` keys | helper gains burned params (P2 item 1) |
| `test/fuel_summary_window_test.dart` | service fields only | untouched |
| `test/stats_fuel_horizon_screen_test.dart`, `nutrition_trend_screen_test.dart`, `records_nutrition_entry_test.dart` and the layer tests | the card's presence and keys | untouched; the full suite proves it |
| `docs/stats_screen.md`, `docs/widget_catalog.md`, `docs/data_models.md` | the card's lines | Docs delta |

## Input-reality checklist

1. **Writers**: energy rows are written by `ActiveEnergyService.settle` (`estimated`) and, from plan 134c, by the watch importer (`measured`). A session with no body weight has no row and is skipped (D-13431).
2. **Lifecycle**: unfinished sessions are excluded (`endedAtMs == null`), as for training days. A row that appears after the card was loaded (a late watch session) shows on the next load; the Stats screen's reload-while-open gap is a known deferred item (2026-11-04 sweep, item 2), not changed here.
3. **Settings**: nothing the card reads changes while it is open except the data; no unit setting exists for energy (D-13434).
4. **Time**: a session counts on the local day it STARTED, exactly like a training day (a session that starts 23:50 yesterday counts for yesterday); the window and `windowStart` are the card's own.
5. **Cost**: `_loadHistory()` is the cached index the card's training-day rule already loads; one `getSessionEnergy` read per in-window session (about 7 to 14 in-memory gets).
6. **Words** (owner-visible): `Training days:`, `Rest days:`, `protein`, `Burned per session:`, `~`, `sessions`, `—`. Old wording found by grep in docs: `docs/stats_screen.md:412, 617, 622`, `docs/widget_catalog.md:43`, `docs/data_models.md:493`.
7. **Competition**: the card gains one caption below the split; no other slot moves.

## Feature invariants

- Eaten and burned are never combined (D-13433).
- The burned average counts only sessions that have a stored value and only finished ones in the window (D-13431).
- A measured-only average carries no `~`; any estimate puts the `~` on (S-13431).

## Existing-functionality impact

| Touch | What reads it today | Effect | Guarded by |
|---|---|---|---|
| `fuel_summary.dart` | `computeFuelSummary`, `FuelSection`, one test helper | three defaulted fields | S-13430 |
| `stats_progress_service.dart` `computeFuelSummary` | `stats_screen.dart:145`, the fuel tests | one private method, three constructor arguments | S-13430..S-13433 |
| `fuel_section.dart` | the Stats screen, layer tests | wording, one caption, `maxLines` on three captions | S-13434, the fuel row tests |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | The burned line is drawn only when the card shows averages (3 or more logged food days) | it sits in the same block as the other lines; a burned average beside a food average is the owner's request |
| A-2 | A mixed average (some measured, some estimated) carries `~` | the number includes an estimate; the owner has not seen this edge |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/stats_screen.md | MODIFIED | `**Training / rest split.** The window's logged days are partitioned into days` | `**Training days and rest days.** The window's logged days are partitioned into days` | S-13434 |
| docs/stats_screen.md | ADDED | - | `**Burned per session.**` | S-13430, S-13431, S-13432, S-13433 |
| docs/stats_screen.md | MODIFIED | `the training / rest split, and the not-enough-logged-days sentence` | `the training-days and rest-days lines, the burned-per-session line, and the not-enough-logged-days sentence` | S-13434 |
| docs/stats_screen.md | MODIFIED | `the previous range's, the training / rest split, the targets, and` | `the previous range's, the training / rest split, the burned-per-session average, the targets, and` | S-13430 |
| docs/widget_catalog.md | MODIFIED | `in two rows), the training / rest split, and` | `in two rows), the training-days and rest-days lines, the burned-per-session line, and` | S-13434 |
| docs/data_models.md | MODIFIED | `rest split of each; and the day's calorie, protein, carbs and fat targets, with` | (`burnedKcalAverage`, `burnedSessionCount`, `burnedIsEstimate`); and the day's | S-13430 |

Stale-term sweep (done by the lead, 2026-11-09): `grep -rIn "kFuelTrainingLabel\|kFuelRestLabel\|fuel_split\|Training / rest\|training / rest\|rest split" docs` outside `docs/plans`, `docs/history`, `docs/releases` found `docs/widget_catalog.md:43`, `docs/data_models.md:493`, `docs/stats_screen.md:412, 617, 622` (all rows above). `docs/stats_screen.md:622` keeps its words `the training / rest split` inside the New marker by design (the model still carries the split).

## Progress

| Item | What | Status |
|---|---|---|
| P1.1 | red test `test/fuel_burned_summary_test.dart` | Planned |
| P1.2 | `FuelSummary` fields | Planned |
| P1.3 | `_burnedInWindow` and the constructor call | Planned |
| P1.4 | green P1 | Planned |
| P2.1 | red widget scenarios | Planned |
| P2.2 | `FuelSection` wording and burned line | Planned |
| P2.3 | row test strings | Planned |
| P2.4 | green P2 | Planned |
| P3 | Docs delta rows | Planned |
