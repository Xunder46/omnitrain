# 100 — Every Stats block says what period it covers, in words

Status: SEEDED by the lead 2026-11-02 (no architect run: the seed carries exact code and exact test text). Base commit:
`.work/2026-11-02-100-stats-block-horizons/base.txt` (HEAD c8f254b8 + the crew commit 07829d0d).
Track: phone only (`lib/`, `test/`, `docs/`). Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart`,
`test/stats_dst_day_arithmetic_test.dart` (another session's DST work).
Owner request 2026-11-02 "Group 2: make each block say what it is", items 5-8. The owner said: take defaults, commits pre-approved.

## Goal and acceptance

What a user sees after this PR, on the Stats screen:

1. **Horizon in words, once per block, no chip.** The Training Mix card's first line reads `Last 4 weeks. Your training split by time
   spent.` (or `... by how hard each session felt.`); its week strip is titled `Last 8 weeks, week by week`. The Instruments
   block's one caption starts `Last 4 weeks.`. The Fuel card's first line reads `Last 7 days`. The italic `· Last 4 weeks` chip is gone
   everywhere. The empty-window card already names the period in its one line and carries no chip either.
2. **Instruments caption and dashes.** The caption under the first section header is one plain line, `Last 4 weeks. Change is against the
   4 weeks before.` A row with nothing to compare against reads `new`; a change of exactly zero still reads the dash.
3. **ALL TIME leaves the Stats screen.** Sessions / Time / Streak stay on Records & Trends only. The Stats screen is Mix, Signals,
   Instruments, Fuel.
4. **The unrated line is gone** from the Mix card (it was not tappable). The "Showing time for now ... (N of 4 so far)" note stays.

Not in this PR: moving the streak to Home or Profile (owner: "if you want it visible daily"); a tappable "sessions to rate" list;
Records & Trends blocks; Signals cards (each card is about its own period).

## Owner decisions taken as defaults (listed in the report)

- O-5 Horizon sentence form: first line of the card, a full stop after the horizon (`Last 4 weeks. ...`), taken from `StatsWindow.label`.
- O-6 `new` is shown when the previous range has no comparable value (no summary, or a different metric); zero change keeps the dash.
- O-7 ALL TIME stays on Records & Trends (owner's pick). The streak is not moved anywhere (Records & Trends already shows it).
- O-8 The unrated line is dropped, not made tappable (a tappable version needs a new "sessions to rate" list; not built).
- O-9 Signals gets no horizon line; Records & Trends is untouched.

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-17301 | `StatsWindowChip` is deleted: file `window_chip.dart` (governor deletes it after P1) and its four uses. The horizon is `StatsWindow.label`, plain text | `mix_layer.dart` (2 uses), `instrument_list.dart` (1 use) |
| D-17302 | Mix explainer: `'${window.label}. Your training split by how hard each session felt.'` / `'${window.label}. Your training split by time spent.'`; strip title `'Last $kMixStripWeeks weeks, week by week'` | `mix_layer.dart` `_explainer`, strip title |
| D-17303 | Instruments caption: `'${window.label}. Change is against the ${_span(window.dayCount)} before.'`; `_span` is whole weeks when `dayCount % 7 == 0` (`1 week`, `4 weeks`), else days (`1 day`, `10 days`); no literal 28 or 4 | `instrument_list.dart` `_caption` |
| D-17304 | `InstrumentChangeChip` reads `new` (not `—`) when `label` is null. `formatNativeChange(…, 0)` still returns `—` (unchanged) | `instrument_row.dart:141` |
| D-17305 | Stats screen drops the ALL TIME header and card, `_buildAggregateCard`, `_formatDuration`, the `CalendarState` streak load and the fields `_totalDurationMs`, `_streakDays`. `computeTotals()` stays: `_totalSessions == 0` still picks the empty state. `StatsPill` stays (Records & Trends uses it) | `stats_screen.dart` |
| D-17306 | `MixLayerSection` drops `_unratedNote` and its `mix_unrated_note` block. `MixLayerData.unratedSessionCount` stays on the model (service tests read it); no UI reads it | `mix_layer.dart:90`, `:226` |
| D-17307 | Fuel card gets a first line `Last ${StatsProgressService.kFuelWindowDays} days` (key `fuel_horizon`), above the averages and above the not-enough-days sentence | `fuel_section.dart` `build` |
| D-17308 | Test names that existed keep their `S-nnnn` group ids so the docs' citations stay valid; only names that assert a removed thing are renamed (list in P3) | tests |

## Exact production code (P1)

`lib/features/stats/widgets/mix_layer.dart`

1. `_explainer` becomes
   ```dart
   String get _explainer => _isLoad
       ? '${window.label}. Your training split by how hard each session felt.'
       : '${window.label}. Your training split by time spent.';
   ```
2. Both `OmniCardHeader(title: 'TRAINING MIX', actions: [StatsWindowChip(...)])` become `const OmniCardHeader(title: 'TRAINING MIX')`
   (the empty-window one at `:164` and the main one at `:184`). Delete `import 'window_chip.dart';`.
3. Delete the getter `_unratedNote` (`:87-100` with its doc comment) and the block `if (layer.unratedSessionCount > 0) ...[ ... ]`
   (`:226-237`: the `SizedBox`, the `Text` with key `mix_unrated_note`).
4. The strip title text `'Week by week · last $kMixStripWeeks weeks'` becomes `'Last $kMixStripWeeks weeks, week by week'`.

`lib/features/stats/widgets/instrument_list.dart`

5. Delete `import 'window_chip.dart';`. The header becomes `OmniCardHeader(title: section.section.label)` (no `actions`). Replace `_caption`:
   ```dart
   /// Whole weeks when the window is a multiple of seven days, otherwise days.
   static String _span(int days) {
     if (days % 7 == 0) {
       final weeks = days ~/ 7;
       return weeks == 1 ? '1 week' : '$weeks weeks';
     }
     return days == 1 ? '1 day' : '$days days';
   }

   /// The one line under the first header: the window in words, then what the
   /// change is measured against (D-17303).
   Text _caption(BuildContext context) {
     final window = widget.window;
     return Text(
       '${window.label}. Change is against the ${_span(window.dayCount)} before.',
       key: const Key('instrument_caption'),
       style: Theme.of(
         context,
       ).textTheme.labelSmall?.copyWith(color: widget.themeColors.textMuted),
     );
   }
   ```
   Update the class doc comment of the old caption (it described the line and the change).

`lib/features/stats/widgets/instrument_row.dart`

6. `static const String _noChange = '—';` becomes `static const String _newLabel = 'new';` and `label ?? _noChange` becomes
   `label ?? _newLabel`. The class doc says: reads `new` when there is no comparable previous value; a change of exactly zero is
   formatted by `formatNativeChange` as the dash.

`lib/features/stats/stats_screen.dart`

7. Remove `_totalDurationMs`, `_streakDays`, the `CalendarState` construction and `streakDays` read in `_loadData`, their
   `setState` assignments, `const OmniCardHeader(title: 'ALL TIME'), _buildAggregateCard(...), const SizedBox(height: 24),` in the
   list, the methods `_buildAggregateCard` and `_formatDuration`, and every import that becomes unused (`date_utils.dart`,
   `calendar_state.dart`, `omni_card_header.dart`, `stats_pill.dart` if nothing else in the file uses them; `flutter analyze` says which).
   `_totalSessions` and `computeTotals()` stay.

`lib/features/stats/widgets/fuel_section.dart`

8. In the card's inner `Column` (`children:` at the `if (summary.showsAverages) ...[` line), insert first:
   ```dart
   _caption(
     theme,
     key: const Key('fuel_horizon'),
     text: 'Last ${StatsProgressService.kFuelWindowDays} days',
   ),
   const SizedBox(height: 8),
   ```

Governor, after P1: delete `lib/features/stats/widgets/window_chip.dart` (`rm`), then `flutter analyze` for broken imports.

## Scenarios

Fixtures are the ones of the existing tests named in each row (copy their pump helper; do not invent a new harness). `Fails
without the change` is checked by `prove-red` at the base commit.

| Id | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-17301 | Mix card, time measure (the `mix_layer_screen_test.dart` time-measure fixture), window `Last 4 weeks` | `mix_explainer` reads exactly `Last 4 weeks. Your training split by time spent.`; `find.byKey(Key('stats_window_chip'))` finds nothing on the whole screen | explainer lacks the horizon; the chip exists |
| S-17302 | Same, load measure (rated weeks ≥ 4 fixture of `mix_layer_screen_test.dart`) | `mix_explainer` reads `Last 4 weeks. Your training split by how hard each session felt.` | same |
| S-17303 | Mix card with weeks | `mix_strip_title` reads `Last 8 weeks, week by week` | old text `Week by week · last 8 weeks` |
| S-17304 | Stats screen with sessions in two sections (the `instrument_list_screen_test.dart` fixture) | exactly one `instrument_caption`, text `Last 4 weeks. Change is against the 4 weeks before.`; no `stats_window_chip` | old caption `Line: each training day ... · Change: vs the 28 days before it` |
| S-17305 | `InstrumentList` with three rows: no previous value; previous equal to the window's; previous different | the three `instrument_change_<id>` texts read `new`, `—`, and an arrow figure | the first reads `—` |
| S-17306 | `InstrumentList` with a hand-built `StatsWindow` of 10 days, label `Custom`; twin 7 days; twin 1 day | captions `Custom. Change is against the 10 days before.`, `... the 1 week before.`, `... the 1 day before.` | caption text differs |
| S-17307 | Stats screen with history | no `ALL TIME` text, no `all_time_card`, no `STREAK`; the order is Mix, Signals (or locked), Instruments, Fuel. Twin: Records & Trends still shows ALL TIME with Sessions, Time, Streak | Stats still draws the card |
| S-17308 | Twin: Stats with no completed session | first-use empty state, unchanged | guards `_totalSessions` still read |
| S-17309 | Mix card with unrated sessions, load measure AND time measure | no `mix_unrated_note`; under the time measure with fewer than 4 rated weeks `mix_baseline_note` is still shown | note present |
| S-17310 | Fuel card with averages; twin with fewer than `kFuelMinLoggedDays` logged days | `fuel_horizon` reads `Last 7 days` in both; `fuel_logged_days` unchanged | no horizon line |
| S-17311 | Fuel twin: `kFuelWindowDays` is the source of the number | the text is built from the constant (the test reads `StatsProgressService.kFuelWindowDays`) | guards a hard-coded 7 |
| S-17312 | Empty-window card (S-17006's fixture in `stats_four_week_window_screen_test.dart`) | `mix_window_empty` reads `No training in the last 4 weeks. Last session: Sep 28.`; no `stats_window_chip`; `Last 4 weeks.` as an explainer is absent | chip was present |
| S-17313 | Source guard | no file under `lib/features/stats` contains `StatsWindowChip` or `stats_window_chip`; `window_chip.dart` does not exist | file exists |
| S-17314 | Records & Trends tests | stay green untouched | guards the screen that keeps ALL TIME |

## Phases

| Phase | Agent | Write scope | Items | Serial/parallel |
|---|---|---|---|---|
| P1 | crew-builder-app | `lib/features/stats/stats_screen.dart`, `lib/features/stats/widgets/mix_layer.dart`, `lib/features/stats/widgets/instrument_list.dart`, `lib/features/stats/widgets/instrument_row.dart`, `lib/features/stats/widgets/fuel_section.dart` | the eight edits above | first |
| P2a | crew-builder-app | new `test/stats_mix_horizon_screen_test.dart` | S-17301, S-17302, S-17303, S-17309, S-17312; helpers copied from `stats_four_week_window_screen_test.dart` and `stats_rated_weeks_screen_test.dart` | after P1; parallel with P2b, P2c |
| P2b | crew-builder-app | new `test/stats_fuel_horizon_screen_test.dart` | S-17310, S-17311; helpers copied from `fuel_row_screen_test.dart` | after P1; parallel |
| P2c | crew-builder-app | new `test/stats_instruments_horizon_screen_test.dart` | S-17304, S-17305, S-17306, S-17307, S-17308, S-17313; the hand-built list pattern of `instrument_list_screen_test.dart` (~L1090) | after P1; parallel |
| P3 | crew-builder-app | the existing test files the red run names | fixture and assertion changes only, no production edit; group ids kept (D-17308) | after P2 |
| P4a | crew-docs-keeper | `docs/stats_screen.md` | rows 1-32 of the Docs delta | after P3 |
| P4b | crew-docs-keeper | `docs/widget_catalog.md`, `docs/design_system.md`, `docs/navigation_and_screens.md`, `docs/signals.md` | the rows for those docs | parallel with P4a (disjoint scopes) |

Test renames agreed now (so the docs can cite them): in `mix_layer_screen_test.dart` group `S-1612 exactly two window chips, and the Fuel
row has none` becomes `S-1612 the window is named in words, not by a chip`; in `stats_four_week_window_screen_test.dart` the test `the
bar reads the 28-day window and the chip never names the period` becomes `the bar reads the 28-day window and the explainer never names
the period`; the `S-3205` tests (unrated line) are deleted and replaced by S-17309.

Done criteria: touched test files green with real counts; `flutter analyze` issue count not above 181 (baseline, 0 errors); full
`flutter test` green apart from files the other session owns; invariant grep clean; `ui_standards_contract_test.dart` and
`docs_indexing_contract_test.dart` green; `plan-lint.py after` clean. Prover mutations: `_span` weeks branch (`~/ 7` → `~/ 4`);
`_newLabel` back to the dash; explainer drops `${window.label}`; fuel horizon hard-coded `7`; ALL TIME block re-added.

## Docs delta

Markers are exact one-line phrases. `-` = none. Docs not listed here are checked by the keeper's search for the old terms
`ALL TIME`, `chip`, `StatsWindowChip`, `unrated line`, `Week by week`, `no-change dash` outside `docs/plans`, `docs/history`, `docs/releases`.

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/stats_screen.md | MODIFIED | no Signals layer, no ALL TIME card, no Instruments list | no Signals layer, no Instruments list | S-17307 |
| docs/stats_screen.md | MODIFIED | it is five blocks in a fixed order | it is four blocks in a fixed order | S-17307 |
| docs/stats_screen.md | MODIFIED | no block beyond those five | no block beyond those four | S-17307 |
| docs/stats_screen.md | MODIFIED | [ALL TIME card](#all-time-card) | the [Instruments list](#instruments-list) | S-17307 |
| docs/stats_screen.md | MODIFIED | The Mix layer is the first block in the body, above the ALL TIME card, and there | The Mix layer is the first block in the body, and there | S-17307 |
| docs/stats_screen.md | MODIFIED | One sentence under the card's title says what the bars are: | One sentence under the card's title names the window, then says what the bars are: | S-17301, S-17302 |
| docs/stats_screen.md | ADDED | - | Last 4 weeks. Your training split by time spent. | S-17301 |
| docs/stats_screen.md | ADDED | - | Last 4 weeks. Your training split by how hard each session felt. | S-17302 |
| docs/stats_screen.md | MODIFIED | **The note and the unrated line.** | **The note.** | S-17309 |
| docs/stats_screen.md | REMOVED | An unrated line says what the missing ratings do to the figures | - | S-17309 |
| docs/stats_screen.md | REMOVED | S-3205 the unrated line says which measure | - | S-17309 |
| docs/stats_screen.md | REMOVED | the unrated line | - | S-17309 |
| docs/stats_screen.md | MODIFIED | Week by week · last 8 weeks | Last 8 weeks, week by week | S-17303 |
| docs/stats_screen.md | MODIFIED | carries its own `StatsWindowChip` naming it | names it in the first words of its explainer | S-17301 |
| docs/stats_screen.md | REMOVED | the second of the screen's two chips | - | S-17301 |
| docs/stats_screen.md | MODIFIED | window and the chip never | window and the explainer never | S-17301 |
| docs/stats_screen.md | MODIFIED | it draws the header, the chip and one line | it draws the header and one line | S-17312 |
| docs/stats_screen.md | MODIFIED | and above the ALL TIME card, and there is exactly one of it | and above the Instruments list, and there is exactly one of it | S-17307 |
| docs/stats_screen.md | REMOVED | ### ALL TIME card | - | S-17307 |
| docs/stats_screen.md | REMOVED | One surface holding three pills: | - | S-17307 |
| docs/stats_screen.md | REMOVED | Current consecutive-day streak via | - | S-17307 |
| docs/stats_screen.md | REMOVED | asserts the `STREAK` pill inside the `ALL TIME` card | - | S-17307 |
| docs/stats_screen.md | MODIFIED | first of them carries the window chip, so the scope of the readout is never | the caption under the first one names the window | S-17304 |
| docs/stats_screen.md | MODIFIED | the change is against the 28 days before it | Change is against the 4 weeks before. | S-17304 |
| docs/stats_screen.md | ADDED | - | Last 4 weeks. Change is against the 4 weeks before. | S-17304 |
| docs/stats_screen.md | MODIFIED | it reads the no-change dash rather than a | it reads `new` rather than a | S-17305 |
| docs/stats_screen.md | ADDED | - | a change of exactly zero reads the dash | S-17305 |
| docs/stats_screen.md | MODIFIED | reads the same no-change dash the Instruments rows use | reads a dash; the Instruments rows read new instead | S-17305 |
| docs/stats_screen.md | MODIFIED | so it carries no `StatsWindowChip`. | and its first line reads `Last 7 days`. | S-17310 |
| docs/stats_screen.md | MODIFIED | the ALL TIME card and the [Fuel row](#fuel-row) sit | the [Fuel row](#fuel-row) sits | S-17307 |
| docs/stats_screen.md | REMOVED | ALL TIME card (Sessions / Time / Streak) | - | S-17307 |
| docs/stats_screen.md | MODIFIED | ### On-screen Window Label | ### Naming the Window | S-17301 |
| docs/stats_screen.md | REMOVED | inline chip reading | - | S-17301 |
| docs/stats_screen.md | REMOVED | Those two are the chip's only hosts | - | S-17301 |
| docs/stats_screen.md | MODIFIED | S-1612 exactly two window chips | S-1612 the window is named in words | S-17301 |
| docs/stats_screen.md | REMOVED | StatsWindowChip | - | S-17313 |
| docs/stats_screen.md | REMOVED | window_chip.dart | - | S-17313 |
| docs/stats_screen.md | MODIFIED | The ALL TIME stat pill, shared with Records & Trends | The ALL TIME stat pill, used by Records & Trends and Exercise Progress, not by this screen | S-17307 |
| docs/stats_screen.md | MODIFIED | builds one `CalendarState` and one | builds one `StatsProgressService` | S-17307 |
| docs/stats_screen.md | MODIFIED | asks the service for the all-time totals (`computeTotals()`), the | asks the service whether any session exists (`computeTotals()`), the | S-17308 |
| docs/stats_screen.md | REMOVED | (created internally by `StatsScreen`) | - | S-17307 |
| docs/widget_catalog.md | REMOVED | the unrated line | - | S-17309 |
| docs/widget_catalog.md | MODIFIED | Week by week · last 8 weeks | Last 8 weeks, week by week | S-17303 |
| docs/widget_catalog.md | MODIFIED | the explainer sentence naming the measure in words | the explainer sentence naming the window and the measure in words | S-17301 |
| docs/widget_catalog.md | REMOVED | StatsWindowChip | - | S-17313 |
| docs/design_system.md | MODIFIED | (carrying the window chip in actions); `SIGNALS`; `ALL TIME`; | ; `SIGNALS`; | S-17307 |
| docs/design_system.md | MODIFIED | the first of them carrying the window chip in actions; and | and | S-17301 |
| docs/navigation_and_screens.md | MODIFIED | between the Mix layer and the ALL TIME card | between the Mix layer and the Instruments list | S-17307 |
| docs/navigation_and_screens.md | REMOVED | all-time sessions, total training time and current streak in the ALL TIME card, | - | S-17307 |
| docs/signals.md | MODIFIED | never follows the Stats window chip | never follows the Stats window | S-17301 |

## Progress
- [x] P1 — production edits (8 items); lint 181 = baseline
- [x] governor — `window_chip.dart` deleted, analyze 181
- [x] P2a/P2b/P2c — `stats_mix_horizon_screen_test.dart` (+12 bodies), `stats_fuel_horizon_screen_test.dart` (+6), `stats_instruments_horizon_screen_test.dart` (+17), green on Mock and Hive
- [x] P3a-d — ~20 existing test files adapted; 2 of 127 reds remain: `records_and_trends_screen_test.dart` S-915 (red at the base too, DST drift in the shared `seedSession`, not this unit)
- [x] P4a/P4b — docs; `plan-lint after` clean (50 rows)
- [x] prove — every new guard RED at 07829d0d for the stated reason; two twins green at base by design
- [x] mutations — 9 of 10 killed; M9 (hard-coded 7 for `kFuelWindowDays`) is behaviourally identical
- [x] review — APPROVE WITH FIXES: 1 blocker (a false "used only by Records & Trends" docs sentence, fixed and re-linted), 1 minor (positional card lookup in `screen_widget_test.dart`, follow-up)

## Assumption Log
- Baseline `flutter analyze`: 181 issues, 0 errors (info notices only), run at HEAD 07829d0d on 2026-11-02 with the other session's
  two files dirty.
- `MixLayerData.unratedSessionCount` stays; after this PR no widget reads it (service tests do). Left for the owner to retire.
- Under the load measure, unrated sessions are still left out of the bar, now without a line saying so (owner item 8: drop it).
