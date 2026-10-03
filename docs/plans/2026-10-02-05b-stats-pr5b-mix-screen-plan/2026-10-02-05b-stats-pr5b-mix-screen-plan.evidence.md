# Evidence — Stats PR 5b (the Mix layer on the Stats screen)

> Companion to `2026-10-02-05b-stats-pr5b-mix-screen-plan.md`. **Evidence only.** No decisions,
> no findings, no plan text. Executors append here; the reviewer reads here. Findings go in
> `2026-10-02-05b-stats-pr5b-mix-screen-plan.review.md`.

## 1. Baselines (Step 0b)

Recorded by the planner against `develop` **before 5a**; the executor re-runs them after 5a and
quotes the real lines. The test count is expected to have grown by 5a's tests.

| Command | Recorded baseline (planner, pre-5a) | Executor's run | Verbatim final line |
|---|---|---|---|
| `gateway.sh lint` | 0 errors, 196 issues | re-run at part A | `196 issues found. (ran in 2.8s)` — no new issue |
| `gateway.sh test` | `+3227 ~1: All tests passed!` | part A's run is not a baseline (the Mix block is wired and five older files still assert the pre-Mix layout) | `01:19 +3393 ~1 -15: Some tests failed.` — see §10.4 |

## 2. Red runs (Step 0c) — required

| Phase | Test file | Command | Observed failure (paste) | Then green (paste) |
|---|---|---|---|---|
| 1 | `test/mix_layer_screen_test.dart` | `gateway.sh test test/mix_layer_screen_test.dart` | PENDING | |

## 3. Inverse-edit mutations — required, on tracked files

| # | Tracked file | Mutation | Test that must fail | Observed | Reverted |
|---|---|---|---|---|---|
| M1 | `lib/features/stats/stats_screen.dart` | the Mix block moved below the ALL TIME card | S-1601 in `test/mix_layer_screen_test.dart` | PENDING | |
| M2 | `lib/core/constants/modality_colors.dart` | the cardio and resistance accents swapped | S-1611 (and S-1602) in `test/mix_layer_screen_test.dart` | PENDING | |

## 4. Per-scenario results

Both harnesses for every row. Seeding in `setUp`; Hive never seeded inside a `testWidgets` body.

| Scenario | Surface | Result |
|---|---|---|
| S-1601 (Mix first, above ALL TIME) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1602 (bar split, largest first, legend) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1603 (one measure label twice, chip on the header) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1604 (no bare modality name in the legend) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1605 (time measure, note, no usual bar) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1606 (load measure, usual bar, no note) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1607 (unrated count in words, or absent) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1608 (8 stacked columns, current marked and named) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1609 (the strip reads the bar's measure and split) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1610 (hidden with no measurable time) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1611 (lifting-only: one full-width segment, one-segment stacks) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1612 (exactly two chips; Fuel still has none) | `test/mix_layer_screen_test.dart`, `test/instrument_list_screen_test.dart`, `test/fuel_row_screen_test.dart` | PENDING |
| S-1613 (one window, shared with the Instruments list) | `test/mix_layer_screen_test.dart` | PENDING |
| S-1614 (no chart, no legacy name, no coaching copy) | `test/mix_layer_screen_test.dart`, `test/stats_legacy_removal_test.dart` | PENDING |
| S-1615 (overflow: 375×667 @1.3 and 440×956 @1.0) | `test/mix_layer_screen_test.dart`, `test/screen_overflow_contract_test.dart` | PENDING |
| S-1616 (refreshed by the one load pass) | `test/mix_layer_screen_test.dart` | PENDING |

## 5. Re-stabilised existing tests

Heights, chip counts and locators only. **No assertion text changed.** Record the diff line and
the reason for each.

| File | Change | Reason | Assertion meaning unchanged |
|---|---|---|---|
| `test/screen_widget_test.dart` | PENDING | the Mix card is the first `OmniSurface`; content pushed down | yes |
| `test/instrument_list_screen_test.dart` | PENDING | a second `StatsWindowChip` now exists | yes |
| `test/fuel_row_screen_test.dart` | PENDING | the same | yes |

## 6. Doc-claim → test table

| Doc | Claim (abbreviated) | Test that asserts it |
|---|---|---|
| `docs/stats_screen.md` | the Mix layer is the first block, above ALL TIME | `test/mix_layer_screen_test.dart` (S-1601) |
| `docs/stats_screen.md` | the bar splits by modality, largest first | `test/mix_layer_screen_test.dart` (S-1602) |
| `docs/stats_screen.md` | one measure label on both blocks | `test/mix_layer_screen_test.dart` (S-1603, S-1609) |
| `docs/stats_screen.md` | the legend reads `'<label> <pct>%'` | `test/mix_layer_screen_test.dart` (S-1604) |
| `docs/stats_screen.md` | the baseline note appears in the time measure only | `test/mix_layer_screen_test.dart` (S-1605, S-1606) |
| `docs/stats_screen.md` | the usual bar appears in the load measure only, labelled `'usual'` | `test/mix_layer_screen_test.dart` (S-1606, S-1611) |
| `docs/stats_screen.md` | the unrated line appears only above 0 | `test/mix_layer_screen_test.dart` (S-1607) |
| `docs/stats_screen.md` | the strip is 8 weeks, stacked by modality, with the current one marked | `test/mix_layer_screen_test.dart` (S-1608, S-1609) |
| `docs/stats_screen.md` | the layer hides with no measurable time | `test/mix_layer_screen_test.dart` (S-1610) |
| `docs/stats_screen.md` | a lifting-only window is one segment, and its weeks stack one segment | `test/mix_layer_screen_test.dart` (S-1611) |
| `docs/stats_screen.md` | the screen carries two window chips | `test/mix_layer_screen_test.dart` (S-1612), `test/instrument_list_screen_test.dart` |
| `docs/stats_screen.md` | the layer lays out at every supported viewport and text scale | `test/mix_layer_screen_test.dart` (S-1615) |
| `docs/widget_catalog.md` | `MixLayerSection` is presentation-only and reads no repository | `test/mix_layer_screen_test.dart` (whole suite) |
| `docs/widget_catalog.md` | the layer's behaviour is verified by its test file | `test/mix_layer_screen_test.dart` (whole suite) |

## 7. Name collision sweep

| Name | Hits found | Files |
|---|---|---|
| `MixLayerSection` | PENDING | |
| `mix_layer` | PENDING | |
| `mix_week_current` | PENDING | |
| `mix_week_` | PENDING | |
| `_segment_` | PENDING | |
| `usual` | PENDING | |
| `TRAINING MIX` | PENDING | |
| `by time` | PENDING | |
| `by load` | PENDING | |
| `Load baseline` | PENDING | |
| `unrated session` | PENDING | |

Planner's pre-check (2026-10-02): `'unrated'` already appears as prose in `docs/session_summary.md`,
`docs/calendar_periods.md`, `lib/core/utils/session_feeling_utils.dart` and
`test/session_summary_effort_row_test.dart` — as vocabulary, never as this layer's rendered string.
No `lib/` or `test/` file carries any other name above.

## 8. Footprint

`gateway.sh git-status` must list nothing outside the plan's Predicted Files.

| Phase | Files touched | Out-of-bounds | Notes |
|---|---|---|---|
| 1 part A | `lib/features/stats/widgets/mix_layer.dart`, `test/mix_layer_screen_test.dart`, the evidence file, the plan file | none | `gateway.sh git-status` lists only 5a's and 5b's Predicted Files; the three re-stabilisation targets are still unmodified |
| 1 part B | PENDING | | |
| 2 | PENDING | | |

## 9. Suite output

| Phase | Command | Final line |
|---|---|---|
| 1 | `gateway.sh test test/mix_layer_screen_test.dart` | PENDING |
| 1 | `gateway.sh test test/screen_widget_test.dart test/instrument_list_screen_test.dart test/fuel_row_screen_test.dart test/stats_legacy_removal_test.dart test/header_standardization_test.dart` | PENDING |
| 1 | `gateway.sh test test/screen_overflow_contract_test.dart test/palette_legibility_contract_test.dart` | PENDING |
| 2 | `gateway.sh test` | PENDING |

## 10. Phase 1 part A — the widget, the screen and the widget tests (2026-10-03)

Scope: Phase 1 steps 1–7. Steps 8–11 (S-1615's overflow half, the re-stabilisation of the three
older test files, the two doc updates) are part B and were not run.

### 10.1 Red run

| Command | Final line | Failure classes |
|---|---|---|
| `gateway.sh test test/mix_layer_screen_test.dart --plain-name "Mock"` | `00:01 +3 -18: Some tests failed.` | 16 × `RenderFlex overflowed by 2.0 pixels on the bottom`; 1 × S-1609's strip loop asserting the current column's semantics label against a pattern with no `' (in progress)'` suffix; 1 × S-1611's zero-share check, which `'Resistance 100%'` satisfies |

### 10.2 Green

| Command | Final line |
|---|---|
| `gateway.sh test test/mix_layer_screen_test.dart --plain-name "Mock"` | `00:00 +21: All tests passed!` |
| `gateway.sh test test/mix_layer_screen_test.dart --plain-name "Hive"` | `00:01 +21: All tests passed!` |
| `gateway.sh lint` | `196 issues found. (ran in 2.8s)` — identical to the Step 0b baseline, no new issue |
| `gateway.sh test test/stats_legacy_removal_test.dart test/palette_legibility_contract_test.dart` | `00:02 +10: All tests passed!` |

### 10.3 Changes and their reasons

| File | Change | Reason |
|---|---|---|
| `lib/features/stats/widgets/mix_layer.dart` | the current week's 1 dp border moved from `decoration:` to `foregroundDecoration:` | a background decoration's border insets its child by 2 dp; the column's segments sum to the full 64 dp, so the bordered column alone overflowed. `foregroundDecoration` paints over the child and insets nothing |
| `test/mix_layer_screen_test.dart` | `_columnBorder` reads `container.foregroundDecoration` | follows the widget change |
| `test/mix_layer_screen_test.dart` | S-1609's two strip loops stop at `kMixStripWeeks - 1`; the load loop asserts the current column's `' (in progress)'` label explicitly | D-931 pins the suffix on the current column |
| `test/mix_layer_screen_test.dart` | S-1611's zero-share check is `RegExp(r'(^|\s)0%$')` | `contains('0%')` matched `'Resistance 100%'` |
| `test/mix_layer_screen_test.dart` | six groups seed in `setUp` (S-1603 twin, S-1606 twin, S-1607 A/B/C, S-1609 time/rated, S-1610 rolling) | repository seeding inside a `testWidgets` body runs under `FakeAsync`, where Hive's file I/O never settles; the Hive half hung at S-1603 while Mock (in-memory) never did. S-1616 keeps its `tester.runAsync` seed |

### 10.4 One full run

`gateway.sh test` → `01:19 +3393 ~1 -15: Some tests failed.`
Baseline for this unit (5a's close, pre-wiring): `01:20 +3364 ~1: All tests passed!` — 29 new tests,
15 failures.

All 15 are knock-on from the Mix block becoming the first body element. None is in
`test/mix_layer_screen_test.dart`. Listed, not edited, in part A.

| File | Test | Observed |
|---|---|---|
| `test/screen_widget_test.dart` | aggregate totals reflect seeded completed sessions | `Found 0 widgets with text "SESSIONS"` |
| `test/screen_widget_test.dart` | rolling sessions are excluded from duration aggregates | `Found 0 widgets with text "2"` |
| `test/screen_widget_test.dart` | S-005 guard: no feeling scalar / pill / tile appears in the ALL TIME summary stat row | `Found 0 widgets with text "SESSIONS"` |
| `test/instrument_list_screen_test.dart` (Mock + Hive) | S-1011 the Instruments list is the period window and the chip says so | `Found 2 widgets with key [<'stats_window_chip'>]` |
| `test/fuel_row_screen_test.dart` (Mock + Hive) | S-1112 chip | `Found 2 widgets with key [<'stats_window_chip'>]` |
| `test/fuel_row_screen_test.dart` (Mock + Hive) | renders at 320×568 | `FlutterError: A RenderFlex overflowed by 27 pixels on the right.` |
| `test/fuel_row_screen_test.dart` (Mock + Hive) | renders at 390×844 & 2.0 text scale | `FlutterError: A RenderFlex overflowed by 210 pixels on the right.` |
| `test/records_and_trends_screen_test.dart` (Mock + Hive) | S-913 the header icon opens Records & Trends with the same figures | `Expected: contains 'SESSIONS'` — the Mix block's strings now lead the body's text list |

The two overflow rows are not the chip count. The erroring widget is
`Row … lib/widgets/layout/omni_card_header.dart:53`, creator chain `Row ← Padding ←
OmniCardHeader ← Column ← Padding ← DecoratedBox ← Container ← OmniSurface-[<'mix_layer'>] ←
MixLayerSection`: at 320 dp the card leaves 238 dp and `'TRAINING MIX'` + `StatsWindowChip` need
265 dp. `OmniCardHeader` lays its `actions` out as a non-flex `Row(mainAxisSize: min)` inside the
header's outer `Row`, so it is laid out at unbounded width and the caller cannot constrain it
(a `Flexible` there trips the unbounded-flex assertion). The Instruments header carries the same
chip and is exposed by the same narrow case; the Mix header is simply the first block rendered
without one. The fix belongs to `OmniCardHeader` or `StatsWindowChip` — both outside this plan's
Predicted Files, so part A records it and does not absorb it (plan Open Items).

---

## 11. Phase 1 part B — S-1615, re-stabilisation, docs (2026-10-03)

### 11.1 S-1615 — the overflow half

New fixture `_seedDensest`: a period-scoped window holding a rated 75-minute session with all four
modalities (set + 15 min each of cardio, isometric, sports), a 4-week rated baseline behind it (so
the measure is load and the usual bar renders), and an unrated 5-minute lifting session in the
window (so the unrated line renders). `pumpStats` gained an optional `textScale` and now wraps the
screen in `MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)))`.

Two cases, the same matrix `test/screen_overflow_contract_test.dart` uses: `375×667 @ 1.3` and
`440×956 @ 1.0`. Each installs a `FlutterError.onError` that collects any `overflowed` message,
pumps, restores the handler, then asserts the collected set is empty, `takeException()` is null,
the densest layer really rendered (bar, usual bar, `usual` label, current week), and every layer
sub-widget is no wider than the card.

| Run | Command | Result |
|---|---|---|
| Red (before the `OmniCardHeader` fix) | `gateway.sh test test/fuel_row_screen_test.dart --plain-name "320x568"` | `FlutterError: A RenderFlex overflowed by 27 pixels on the right.` |
| Green | `gateway.sh test test/mix_layer_screen_test.dart --plain-name "S-1615"` | `00:00 +4: All tests passed!` |
| Green (whole file) | `gateway.sh test test/mix_layer_screen_test.dart` | `00:02 +46: All tests passed!` |

### 11.2 The `OmniCardHeader` fix (out of Predicted Files — recorded, not absorbed silently)

`lib/widgets/layout/omni_card_header.dart` laid its `actions` out as a non-flex
`Row(mainAxisSize: min)` inside the header's outer `Row`, so the cluster was laid out at unbounded
width and no caller could constrain it. The actions cluster is now `Flexible(fit: FlexFit.loose)`
and each action inside it is `Flexible(fit: FlexFit.loose)`, so a chip ellipsizes instead of
overflowing. This is the narrow-width fix the plan's Open Items left to the implementer; it is
shared by the Mix header and the Instruments header, so it is a `lib/widgets/` change rather than a
Mix-layer one. Added to the plan's Predicted Files.

### 11.3 Re-stabilised existing tests

Heights, chip counts and locators only. **No assertion text changed.**

| File | Change | Reason | Assertion meaning unchanged |
|---|---|---|---|
| `test/screen_widget_test.dart` | `find.byType(OmniSurface).first` → `find.byKey(const Key('all_time_card'))` (3 sites) | the Mix card is now the first `OmniSurface` | yes — same card, named by key instead of by position |
| `test/screen_widget_test.dart` | surface heights `400×900` → `400×1600` (2 sites), `400×1200` → `400×1600` (1 site) | the Mix block pushes the ALL TIME card down past the lazy `ListView`'s build window | yes — the assertions still target the same widgets, now laid out |
| `test/instrument_list_screen_test.dart` | S-1011 chip assertion `findsOneWidget` → `findsNWidgets(2)`, plus the ancestor-header title set `{'TRAINING MIX', 'Resistance'}`; stale `// One chip:` comment corrected | a second `StatsWindowChip` now exists, on the Mix header | yes — the chip still names the resolved window, and the Instruments header is still one of its two hosts |
| `test/fuel_row_screen_test.dart` | S-1112 chip assertion `findsOneWidget` → `findsNWidgets(2)`, plus the ancestor-header title set; the Fuel-row-has-no-chip assertion kept | the same | yes |
| `test/records_and_trends_screen_test.dart` | S-913's first `_textsUnder(find.byType(OmniSurface).first)` → `find.byKey(const Key('all_time_card'))`; the post-navigation locator left alone | the Mix block's strings now lead the body's text list | yes — the same all-time figures are compared before and after the push |

`test/stats_legacy_removal_test.dart` untouched: its `find.text('Resistance') findsOneWidget` and
its `_kForbiddenFragments` source guard on `stats_screen.dart` are the contracts D-921 and D-925
are written around.

### 11.4 Doc-claim → test table (part B rows)

| Doc | Claim (abbreviated) | Test that asserts it |
|---|---|---|
| `docs/stats_screen.md` | the body is four blocks, the Mix layer first | `test/mix_layer_screen_test.dart` (S-1601) |
| `docs/stats_screen.md` | the layer fits the narrowest viewport at 1.3× and the tallest at 1.0× | `test/mix_layer_screen_test.dart` (S-1615) |
| `docs/stats_screen.md` | the layer is refreshed by the screen's one load pass | `test/mix_layer_screen_test.dart` (S-1616) |
| `docs/stats_screen.md` | the layer reads the same window as the Instruments list | `test/mix_layer_screen_test.dart` (S-1613) |
| `docs/stats_screen.md` | the screen carries two window chips | `test/mix_layer_screen_test.dart` (S-1612), `test/instrument_list_screen_test.dart` (S-1011) |
| `docs/stats_screen.md` | the layer is windowed; the ALL TIME card and the Fuel row are not | `test/mix_layer_screen_test.dart` (S-1601, S-1613) |
| `docs/design_system.md` | the Stats screen's first card header is `TRAINING MIX`, carrying the window chip | `test/mix_layer_screen_test.dart` (S-1601, S-1612) |
| `docs/navigation_and_screens.md` | `StatsScreen` renders a Mix layer describing the window's mix | `test/mix_layer_screen_test.dart` (S-1601) |
| `docs/widget_catalog.md` | `MixLayerSection` is presentation-only, reads no repository, host is the Stats screen | `test/mix_layer_screen_test.dart` (whole suite) |

### 11.5 Name collision sweep

| Name | Hits found | Files |
|---|---|---|
| `MixLayerSection` | 4 | `lib/features/stats/stats_screen.dart`, `lib/features/stats/widgets/mix_layer.dart`, `docs/widget_catalog.md`, `docs/stats_screen.md` |
| `mix_layer` | 8 | `lib/features/stats/stats_screen.dart`, `lib/features/stats/widgets/mix_layer.dart`, `test/mix_layer_screen_test.dart`, `docs/widget_catalog.md`, `docs/design_system.md`, `docs/state_management/services_and_utils.md`, `docs/training_load.md`, `docs/stats_screen.md` |
| `mix_week_current` | 2 | `lib/features/stats/widgets/mix_layer.dart`, `test/mix_layer_screen_test.dart` |
| `mix_week_` | 2 | the same two |
| `_segment_` | 8 | `lib/core/constants/block_types.dart`, `lib/core/services/exercise_library_service.dart`, `lib/features/home/widgets/nutrition_summary_card.dart`, `lib/features/stats/widgets/mix_layer.dart`, `lib/data/models/models.dart`, `test/db_seed_test.dart`, `test/mix_layer_screen_test.dart`, `test/home_nutrition_summary_card_test.dart` |
| `usual` | 8+ | `lib/core/constants/modality_config.dart`, `lib/core/utils/rest_notification_service.dart`, `lib/core/models/training_load.dart`, `lib/core/services/stats_progress_service.dart`, `lib/mock/seed_data.dart`, `lib/features/nutrition/widgets/nutrition_primer_sheet.dart`, `lib/features/stats/widgets/mix_layer.dart`, `lib/state/nutrition/nutrition_primer_state.dart` |
| `TRAINING MIX` | 5 | `lib/features/stats/widgets/mix_layer.dart`, `test/fuel_row_screen_test.dart`, `test/instrument_list_screen_test.dart`, `test/mix_layer_screen_test.dart`, `docs/design_system.md` |
| `by time` | 6 | `lib/mock/seed_data.dart`, `lib/features/stats/widgets/mix_layer.dart`, `test/mix_layer_screen_test.dart`, `docs/rolling_sessions.md`, `docs/README.md`, `docs/modality_tracking.md` |
| `by load` | 2 | `lib/features/stats/widgets/mix_layer.dart`, `test/mix_layer_screen_test.dart` |
| `Load baseline` | 2 | the same two |
| `unrated session` | 7 | `lib/core/utils/session_feeling_utils.dart`, `lib/features/stats/widgets/mix_layer.dart`, `test/session_summary_effort_row_test.dart`, `test/watch_session_summary_integration_test.dart`, `test/training_load_test.dart`, `test/mix_layer_screen_test.dart`, `docs/session_summary.md` |

No collision: every hit is either this feature's own file, a doc that describes it, or the
pre-existing vocabulary the planner's pre-check already recorded (`usual`, `unrated`, `by time`).
`_segment_` is the generic test-key suffix the strip shares with unrelated widgets; the strip's own
keys are namespaced `mix_week_<i>_segment_<j>`.

### 11.6 Footprint

| Phase | Files touched | Out-of-bounds | Notes |
|---|---|---|---|
| 1 part B | `test/mix_layer_screen_test.dart`, `test/screen_widget_test.dart`, `test/instrument_list_screen_test.dart`, `test/fuel_row_screen_test.dart`, `test/records_and_trends_screen_test.dart`, `lib/widgets/layout/omni_card_header.dart`, `docs/stats_screen.md`, `docs/widget_catalog.md`, `docs/design_system.md`, `docs/navigation_and_screens.md`, the evidence file, the plan file | `lib/widgets/layout/omni_card_header.dart` (justified, §11.2), `test/records_and_trends_screen_test.dart` (the plan's step 9 names it), `docs/design_system.md` and `docs/navigation_and_screens.md` (stale claims the Mix layer falsified) | all four added to the plan's Predicted Files |

### 11.7 Suite output

| Phase | Command | Final line |
|---|---|---|
| 1 part B | `gateway.sh lint` | `196 issues found. (ran in 2.6s)` — unchanged baseline, no new issue |
| 1 part B | `gateway.sh test test/mix_layer_screen_test.dart` | `00:02 +46: All tests passed!` |
| 1 part B | `gateway.sh test test/screen_widget_test.dart test/instrument_list_screen_test.dart test/fuel_row_screen_test.dart test/records_and_trends_screen_test.dart` | `00:11 +357: All tests passed!` (the five files together) |
| 1 part B | `gateway.sh test test/screen_overflow_contract_test.dart test/palette_legibility_contract_test.dart test/stats_legacy_removal_test.dart test/header_standardization_test.dart test/docs_indexing_contract_test.dart` | `00:03 +131: All tests passed!` |
| 1 part B | `gateway.sh test` | `01:19 +3412 ~1: All tests passed!` |

---

## 12. Phase 2 — guards, residue sweep, doc-claim pass, full suite (2026-10-03)

### 12.1 The four structural guards

All four live in `test/mix_layer_screen_test.dart`, inside the existing
`for (final factory in harnessFactories)` loop, so each runs on both harnesses (8 tests).
The file went from `+46` to **`+54: All tests passed!`**.

New top-level members: `_kSectionLabels` (derived from `ExerciseSection.values`' labels),
`_kSectionAccents` (a literal `label → ModalityColors` map), `_legendSections()`,
`_listSections()`, `_usualIndices()`. Two imports added:
`package:omnitrain/core/models/exercise_metric.dart` and
`package:omnitrain/features/stats/widgets/instrument_list.dart`.

| Guard | Fixture | What it pins |
|---|---|---|
| `Guard — one modality mapping` (step 1) | `_seedEveryModality` | the legend's section set == the Instruments header section set — one mapping, so the layer cannot drift from the list |
| `Guard — no bare modality name` (step 2) | `_seedDensest` | each of the four labels is `findsOneWidget`, a descendant of `InstrumentList`, and `findsNothing` under `mix_layer`; `'usual'` is not a section label |
| `Guard — the layer draws no chart and no colour of its own` (step 3) | `_seedDensest` | no `CustomPaint`/`LineChart`/`ScrollableTrendChart` under `mix_layer`; bar segment *i* colour == `_kSectionAccents[legend[i]]`; every usual-bar and strip segment colour ∈ the four accents |
| `Guard — the strip stacks by modality` (step 4) | `_seedStrip` | the mixed week renders exactly 2 segments in data order with the right accents; each lifting-only week exactly 1 |

`_kSectionAccents` is written out literally (referencing the constants) rather than derived from
the widget, which is what makes guard 3 a real assertion — a mis-bound section fails rather than
matching itself.

**First run of the guards:** `Bad state: No element` at `_segmentColor` in guard 3, because the
guard iterated `Key('mix_usual_segment_$i')` for `i` in 0..7 unconditionally. The usual bar only
carries the modalities it has, so the fix was `_usualIndices()`, which reads the present keys.
Guards 1, 2 and 4 passed on the first run.

### 12.2 `OmniCardHeader` narrow-width test (S-001c)

Added at the end of the `OmniCardHeader – unit` group in `test/header_standardization_test.dart`.
At `narrow = 320.0` with a long action label: no RenderFlex overflow (collected via a temporary
`FlutterError.onError`, exactly as S-1615 does), the header's own width ≤ 320, the long label's
width at 320 < its width at `wide = 2000.0` (it ellipsized), and a short label has identical width
at both widths (its natural size survives).

| Command | Result |
|---|---|
| `gateway.sh test test/header_standardization_test.dart` | `00:00 +1: All tests passed!` (the new test alone) |
| `gateway.sh test test/header_standardization_test.dart` | `00:02 +65: All tests passed!` (the file) |

### 12.3 Inverse-edit mutations

Every mutation was applied, run, then restored in the immediately following action; each restore
was confirmed by re-reading the spot and matching `git-diff --stat` against the pre-mutation stat.
No step ended with a mutation applied.

| # | File | Edit | Pre-mutation stat | Result |
|---|---|---|---|---|
| 3 | `lib/widgets/layout/omni_card_header.dart` | replace the `Flexible` cluster with the old plain `Row(children: effectiveActions)` | `18 ++++++---- … 14 insertions(+), 4 deletions(-)` | `00:02 +64 -1` — exactly `S-001c … [E]` reddens. Restored; stat matched; rerun `00:02 +65: All tests passed!` |
| M1 | `lib/features/stats/stats_screen.dart` | move the Mix block below the ALL TIME card | `22 ++++++++++++++++++++++ 1 file changed, 22 insertions(+)` | `00:02 +52 -2` — `S-1601 the layer is the first block, above ALL TIME` reddens on Mock and Hive. Restored; stat matched; rerun `+54: All tests passed!` |
| M2 | `lib/core/constants/modality_colors.dart` | swap the `cardioEndurance`/`resistanceLifting` initialisers | clean (tracked, no other change) | **`00:02 +54: All tests passed!` — NEUTRAL.** See 12.4 |
| M2′ | `lib/features/stats/widgets/mix_layer.dart` | swap the resistance/cardio bindings in `_sectionColors` | clean | `00:02` — **12 failures**: `S-1602`, `S-1606`, `S-1608`, `S-1611`, `Guard — the layer draws no chart and no colour of its own`, `Guard — the strip stacks by modality`, each on Mock and Hive. Restored; `line 53: ExerciseSection.resistance: ModalityColors.resistanceLifting` verified; rerun `+54` |

### 12.4 M2 as the plan specifies it is neutral (deviation, reported)

The plan names M2's inverse edit as the negative control for guard 3. As written — swapping the two
initialisers in `ModalityColors` — it does **not** redden anything. `ModalityColors.cardioEndurance`
and `ModalityColors.resistanceLifting` are read by *both* the widget
(`MixLayerSection._sectionColors`) and the guards (`_kSectionAccents`, and the direct
`ModalityColors.resistanceLifting` reads in S-1602/S-1611), so swapping the initialisers moves the
expectation and the render together. No test in the repo pins a literal `43A047`/`5B9BD5` — only
`docs/plans/modality-color-consolidation-plan.md` names those values, and a plan file is not a
test.

The *equivalent* control is a swap on one side only, and it was run as M2′ above: swapping the
section→colour bindings in `mix_layer.dart` reddens 12 tests, including both of the new colour
guards. Guard 3 is therefore genuinely load-bearing; M2's literal form is not a usable control.
This is logged in the plan's Assumption Log.

### 12.5 Residue sweep

`gateway.sh list`, `git-status` and `git-diff` were run, then `lib/`, `test/` and `docs/` were
searched for every name this PR or 5a introduced and for the strings the layer renders.

| Name / string | Hits | Verdict |
|---|---|---|
| `StatsWindowChip` | one implementation (`lib/features/stats/widgets/window_chip.dart`), two hosts (`mix_layer.dart:124`, `instrument_list.dart:79`) | one implementation — the two hosts are the pinned two chips (S-1612) |
| effort→section mapping | one — `_sectionForKind` at `lib/core/services/stats_progress_service.dart:1123-1133` | no second mapping |
| `EffortKind` / `effortKind` in `lib/features/stats/` | none | the layer never names an effort kind |
| `mix_layer.dart:53-56` | a section→**colour** map only | not a second section mapping |
| `find.byType(OmniSurface).first` | one left, `test/records_and_trends_screen_test.dart:418`, on *Records & Trends* | unaffected by the Mix card; the Stats locator is now `Key('all_time_card')` |
| `three blocks` / `one chip` about the Stats body | none — `docs/widget_catalog/nutrition_widgets.md:28` says "three blocks" about **nutrition** | no stale claim |
| `by time` | `lib/mock/seed_data.dart:3743`, `docs/rolling_sessions.md:41`, `docs/README.md:176`, `docs/modality_tracking.md:428` | coincidental prose, not competing labels |
| `StatsWindow`, `resolveWindow`, `InstrumentSectionData`, `computeInstrumentSections` | one declaration each (`stats_progress.dart`, `stats_progress_service.dart`, `instrument_list.dart`) | no second home |
| `sessionLoadMinutes`, `mixSegments`, `baselineBlockStarts`, `sessionLoadByModality`, `sessionTimeByModality` | declared in `lib/core/models/training_load.dart`; called from `stats_progress_service.dart` | declared once, called — no restatement |

**No reader of a replaced representation survives.** The sweep found no residue.

### 12.6 Doc-claim pass

Every scenario the docs cite exists and passes: `S-1208` (`test/stats_legacy_removal_test.dart`),
`S-1112` (`test/fuel_row_screen_test.dart`), `S-1011` (`test/instrument_list_screen_test.dart`),
`S-001c` (`test/header_standardization_test.dart`), `S-1601…S-1616`
(`test/mix_layer_screen_test.dart`). 5a's doc sentences were checked too:
`docs/README.md`'s link to `training_load.md` resolves, and `docs/constants_reference.md` and
`docs/data_models.md` cite `test/training_load_test.dart` — the group they name
(`the constants (D-908, D-917, D-934)`, line 521) exists and passes.

Four sentences in `docs/stats_screen.md` were **false** and are corrected:

| Was | Is | Why |
|---|---|---|
| the usual bar cited `S-1607` | cites `(S-1606, S-1611)` | `S-1606` is the usual bar; `S-1607` is the unrated line |
| the strip sentence did not say what an empty week draws | "A week with no work draws its column with no stack segment in it" | the widget draws no segment for a zero-total week |
| the Fit sentence claimed the legend/`usual` ellipsizes | "with nothing it draws wider than the card that holds it" | the legend is not the thing that fits; the sentence described behaviour the widget does not have |
| the bar's shares were "time" | the shares are the window's own measure by modality (time in the time measure, load in the load measure), citing `(S-1602, S-1609)` | `computeMixLayer` sets `measureBySection = measure == MixMeasure.load ? windowLoad : _minutesBySection(windowTime)` |

One invariant sentence was added to `docs/design_system.md` after the header property table:
"The `actions` cluster is bounded rather than intrinsic: a long action label ellipsizes instead of
overflowing the header row at a narrow width, and a short action keeps its natural size. Verified by
`test/header_standardization_test.dart` (`S-001c`)." The `design_system.md` table row for the Stats
screen already cites `S-1601`/`S-1612` and stays true.

### 12.7 Footprint

| Phase | Files touched | Out-of-bounds | Notes |
|---|---|---|---|
| 2 | `test/mix_layer_screen_test.dart` (the four guards), `test/header_standardization_test.dart` (`S-001c`), `docs/stats_screen.md` (four corrections), `docs/design_system.md` (the `actions` invariant), the evidence file, the plan file | `test/header_standardization_test.dart` and `docs/design_system.md` — both already added to Predicted Files by part B (§11.6) | the four mutation targets were restored exactly and carry no net Phase 2 change |

`gateway.sh git-status` after Phase 2 lists 17 modified files and 8 untracked entries — every one
inside the plan's Predicted Files or the two plan folders. Nothing outside. No scratch file was
created. No commit, staging or branch was made.

### 12.8 Suite output

| Phase | Command | Final line |
|---|---|---|
| 2 | `gateway.sh lint` | `196 issues found. (ran in 2.3s)` — unchanged baseline, no new issue |
| 2 | `gateway.sh test test/mix_layer_screen_test.dart` | `00:02 +54: All tests passed!` |
| 2 | `gateway.sh test test/header_standardization_test.dart` | `00:02 +65: All tests passed!` |
| 2 | `gateway.sh test test/docs_indexing_contract_test.dart test/palette_legibility_contract_test.dart test/navigation_contract_enforcement_test.dart` | `00:02 +11: All tests passed!` |
| 2 | `gateway.sh test` (run once, in full) | `01:18 +3421 ~1: All tests passed!` |

Baseline from §1/§11.7 was `01:19 +3412 ~1`. The growth is **+9**: the four guards × two harnesses
(8) plus `S-001c` (1). Nothing else moved; no 5a test is in the delta because 5a was already in the
baseline. The `~1` is the pre-existing skip.

---

## 13. Fix round 1 — review findings 1–5, plus one carried item (2026-10-03)

Review: `2026-10-02-05b-stats-pr5b-mix-screen-plan.review.md` (VERDICT: CHANGES_REQUESTED).

| # | Finding | File | What changed | Command | Observed |
|---|---|---|---|---|---|
| 1 | major — the actions cluster became a flex sibling of the title | `lib/widgets/layout/omni_card_header.dart` | the outer `Row` is wrapped in a `LayoutBuilder`; the actions `Row` (key kept, `mainAxisSize.min`, per-action `Flexible(fit: loose)`) is wrapped in `ConstrainedBox(maxWidth: constraints.maxWidth * 0.5)`; the title stays `Expanded`; no cap when `constraints.maxWidth` is infinite | `gateway.sh test test/header_standardization_test.dart` | `00:02 +67: All tests passed!` |
| 1 | new title-side case | `test/header_standardization_test.dart` | `S-001c (title)`: with a short action the title width == `header width − action width` (pre-PR arithmetic) and > half | same | green |
| 1 | new real-action case | `test/header_standardization_test.dart` | `S-001c (real action)`: `OutlinedButton.icon` with a long label at 320 dp / 1.3× throws no overflow, the action is ≤ half, the title ≥ half | same | green |
| 2 | minor — the Mix layer carried no condition | `docs/stats_screen.md` | the four-block sentence now reads "the Mix layer when the window holds measurable time" and cites `S-1610` | doc | — |
| 3 | minor — `S-1610` cited for the note/unrated line | `docs/stats_screen.md` | dropped `S-1610` from the note/unrated bullet; it is now cited only against the layer's hidden state (finding 2) | doc | — |
| — | carried — deleted blank line | `docs/stats_screen.md` | restored the blank line between the Instruments-header paragraph and "The list is data-driven…" | doc | — |
| 5 | nit — the `actions`-cluster sentence was silent on the cap | `docs/design_system.md` | states the cluster takes at most half the header and the title keeps the rest, naming the `S-001c` cases; no pixel values | doc | — |
| 4 | nit — Phase 2 Predicted Files omitted the header test | `…-plan.md` | added `test/header_standardization_test.dart` (the `S-001c` cases) | doc | — |
| 6 | nit — `S-1615` horizontal assertion | — | no action; left as is | — | — |

### 13.1 Mutation red runs (finding 1)

| Mutation | Applied to | Command | Observed |
|---|---|---|---|
| A — replace the new structure with the pre-PR plain `Row(children: effectiveActions)` | `lib/widgets/layout/omni_card_header.dart` | `gateway.sh test test/header_standardization_test.dart --plain-name "S-001c"` | RED: `S-001c … [E]` and `S-001c (real action) … [E]` ("A RenderFlex overflowed by 507 pixels on the right.") |
| B — make the cluster `Flexible(fit: loose)` against the title again (the pre-fix structure) | `lib/widgets/layout/omni_card_header.dart` | `gateway.sh test test/header_standardization_test.dart --plain-name "S-001c (title)"` | RED: `S-001c (title) … [E]` — expected `closeTo(234.5, 0.5)`, actual `160.0` (the 50/50 split) |

Both mutations were restored exactly in the next action and the spots read back; the widget carries no net mutation.

### 13.2 Fix-round suite output

| Command | Final line |
|---|---|
| `gateway.sh test test/header_standardization_test.dart` (green, after the fix) | `00:02 +67: All tests passed!` |
| `gateway.sh test` on the eight header-affected files (`header_standardization`, `fuel_row_screen`, `instrument_list_screen`, `mix_layer_screen`, `session_summary_distance`, `profile_cleanup`, `profile_screen`, `screen_widget`) | `00:12 +471: All tests passed!` |
| `gateway.sh lint` | `196 issues found. (ran in 2.5s)` — unchanged baseline |
| `gateway.sh test test/docs_indexing_contract_test.dart test/palette_legibility_contract_test.dart test/navigation_contract_enforcement_test.dart` | `00:00 +11: All tests passed!` |
| `gateway.sh test` (run once, in full) | `01:38 +3423 ~1: All tests passed!` |

Full-suite baseline was `01:18 +3421 ~1` (§12.8). The growth is **+2** — exactly this fix's two new
`S-001c` cases; nothing else moved. `S-1259`–`S-1261` (Fuel row narrow/large-text) and `S-1615` (Mix
fit) stayed green inside the eight-file run.
