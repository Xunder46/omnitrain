# Evidence — Stats PR 4c (remove the legacy Stats sections, the screen half)

Executors append here. Nothing in this file is a decision; decisions live in the plan.

## Planner baselines (2026-10-01, before any edit)

| Command | Output (verbatim, final line) |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh lint` | `199 issues found. (ran in 3.1s)` |
| `.github/copilot/scripts/macos/gateway.sh test` | `01:21 +3256 ~1: All tests passed!` |

The 199 issues include exactly 4 warnings; the other 195 are `info`-level lints (deprecations,
`prefer_const`, etc.):

| Warning | Location | Dies in |
|---|---|---|
| `The declaration '_ChartSeries' isn't referenced` | `lib/features/stats/stats_screen.dart:1336:7` | 4c Phase 1 |
| `The value of the local variable 'isometricWindow' isn't used` | `test/screen_widget_test.dart:4449:13` | 4c Phase 1 (inside the retired range 4001–4913) |
| `The value of the local variable 'sportsWindow' isn't used` | `test/screen_widget_test.dart:4450:13` | 4c Phase 1 (same range) |
| `The matched value type 'UnsavedChangesAction' can never be equal to this constant of type 'Null'` | `lib/features/routine/routine_setup_screen.dart:1046:12` | not in this series (pre-existing, out of bounds) |

**Expected counts:** after 4c Phase 1 → **197**; after 4c Phase 2 → **196**. The bar is ≤199 with no
errors; a count above 199 means a removal left an unused import/element/local behind.

## Planner measurements (line numbers used by the plan)

| File | Lines | Notes |
|---|---|---|
| `lib/features/stats/stats_screen.dart` | 1,391 | ~1,104 deleted |
| `lib/core/services/stats_progress_service.dart` | 2,342 | untouched in 4c (4c2's) |
| `lib/core/models/stats_progress.dart` | 356 | untouched in 4c (4c2's) |
| `test/screen_widget_test.dart` | 12,018 | the `StatsScreen` group spans 2588–4914 |
| `test/stats_distance_estimate_test.dart` | ~530 | all but S-836 (497–507) retires |
| `docs/stats_screen.md` | 679 / 37,999 bytes | rewritten in Phase 3, ≤64 KiB |

### `test/screen_widget_test.dart` — the `StatsScreen` group retirement table (Phase 1, step 11)

| Range | Lines | Action | Reason |
|---|---|---|---|
| 2588–2749 | 162 | keep | helpers |
| 2750 | 1 test | keep | AppBar title |
| 2760 | 1 test | keep | zero state (its `find.text('STRENGTH')` `findsNothing` stays true) |
| 2778 | 1 test | keep | aggregate totals |
| 2824 | 1 test | keep | rolling sessions excluded |
| 2863–3458 | 596 | **retire** | cardio section + strength cards + the chart guards |
| 3459, 3510, 3592, 3624, 3640 | 5 tests | keep | feeling guards |
| 3542–3591 | 50 | **retire** | asserts a removed section |
| 3672–3826 | 155 | **retire** | asserts removed sections |
| 3827–3973 | 147 | **retire** | the two inline-toggle tests: they build a `SegmentedButton` themselves inside `tester.pumpWidget`, reference no app widget, and exist only for the deleted NUTRITION card's toggle. The real toggle (`lib/features/nutrition/widgets/nutrition_trend_card.dart:109`) is covered by `test/nutrition_trend_screen_test.dart`, which pumps the real screen. |
| 3974 | 1 test | keep, **reworded** | was "app: only one SegmentedButton exists (all toggles except Nutrition deleted)" — vacuous once the card is gone. Becomes "Stats renders no SegmentedButton" with `findsNothing`. |
| 4001–4913 | 913 | **retire** | the multi-modality / all-sections block (also carries the two unused-local warnings) |

Total retired: 1,861 lines / 21 tests. Kept: 10 tests (one reworded).

**Correction (planner, 2026-10-01).** This table first listed 3827 and 3906 as kept and 19 tests as
retired. Reading the two tests showed both construct their own `SegmentedButton` in an isolated
`MaterialApp` and assert on Flutter's built-in — they assert nothing about the app once the NUTRITION
card is gone. They are retired. The line ranges above are contiguous and were checked test by test;
`2863–3458` and `3672–3826` contain no surviving assertion.

### `lib/features/stats/stats_screen.dart` — delete map (pre-edit line numbers, bottom-up)

| Lines | Member | Note |
|---|---|---|
| 184–200 | the trailing separator + `Column(key: Key('stats_legacy_sections'))` | Fuel becomes the last child |
| 1334–1344 | `_ChartSeries` | the file's one warning |
| 1347–1391 | `_LinearScale` | |
| 1311–1328 | `_formatNumber`, `_paceForDisplay`, `_distanceForDisplay` | cardio display helpers |
| 1249–1269 | `_buildSectionEmptyState` | four readers, all in deleted sections |
| 563–1248 | the cardio / isometric / sports builders and helpers | see the plan's step 5 |
| 261–562 | the STRENGTH builders and helpers | see the plan's step 6 |
| **kept** | `_buildEmptyState` 1270–1304, `_formatDuration` 1305–1310 (read at 233) | |

Imports deleted (each verified to have no surviving reader): `fl_chart` (1),
`chart_axis_helper.dart` (9), `unit_formatter.dart` (11), `chart_primitives.dart` (20),
`edge_aware_date_label.dart` (21), `nutrition_trend_card.dart` (23), `recent_pr_list.dart` (26),
`scrollable_trend_chart.dart` (27), `window_chip.dart` (29).

## Executor evidence

### Phase 1 (@developer)

- [x] `gateway.sh format` output → `Formatted test/screen_widget_test.dart`,
  `Formatted test/stats_distance_estimate_test.dart`, `Formatted 3 files (2 changed) in 0.10 seconds.`
- [x] `gateway.sh lint` final line → `196 issues found. (ran in 2.8s)`, 0 errors, and no issue of any
  severity in the three changed files. The plan predicted 197, but its own subtraction is
  `199 − _ChartSeries − the two unused locals = 196`; the run reports 196, which is the bar (≤199, 0
  errors). The 4th baseline warning (routine_setup_screen) is still there and out of bounds.
- [x] `gateway.sh test test/screen_widget_test.dart test/stats_distance_estimate_test.dart` final line →
  `00:08 +230: All tests passed!`
- [x] `gateway.sh git-diff --name-status` file list → `lib/features/stats/stats_screen.dart`,
  `test/screen_widget_test.dart`, `test/stats_distance_estimate_test.dart` — the three Predicted Files —
  plus `docs/plans/2026-09-30-04-stats-pr4-index.md`, which the **planner** edited for the 4c/4c2 split
  before this phase (the brief's item 1 declares it). No executor edit touched it.
  `git-diff --stat`: `stats_screen.dart` 1136 (1,391 → 269 lines), `screen_widget_test.dart` 2277,
  `stats_distance_estimate_test.dart` 530 (→ 27 lines); 264 insertions / 3,783 deletions in total.
- [ ] `+N ~1` for the full suite — not applicable in Phase 1: five files still assert the legacy
  sections and fail until Phase 2, as the plan's declared intermediate state says.

**Ranges actually retired** (bottom-up, text-anchored): 4001–4913 + the dangling
`// ── Phase E: Isometric and Sports sections ──` banner; 3827–3973 + the `// D-1:` comment block;
3672–3826; 3542–3591; 2863–**3427**. The plan's 2863–3458 stops 31 lines early: 3429–3457 is the
Effort-rating banner plus `seedFeelingSession`, read by the five kept feeling-guard tests. Every test
in the range still retires. Helpers that lost their last reader were deleted under D-616:
`seedStrengthDays`, `seedCardioDays` (inside 2863–3458) and `seedTimedEffort`, `seedSetEffort` (only
the retired tests called them). `seedCompletedSession`, `pumpStatsScreen` and `seedFeelingSession` stay.

`test/stats_distance_estimate_test.dart` is reduced to S-836 alone (239 lines → 27): S-831, S-832, the
single-point-card group, S-835 and S-837 retired, the fixture helpers and the 11 orphaned imports
removed, and the file header rewritten to name only the surviving guard. Phase 2 deletes the file.

### Phase 2 (@developer)

- [x] Full-suite final line → `01:29 +3229 ~1: All tests passed!` (and `01:27 +3229 ~1: All tests passed!`
  on the pre-mutation-proof run of the same tree)
- [x] `gateway.sh git-diff -- test/in_session_pr_toast_test.dart test/pr_toast_test.dart` → empty
  (`+41: All tests passed!` for the pair; the PR-toast path is untouched by the retirement)
- [x] The S-018 eyebrow-list derivation → `const ['ALL TIME']`. S-018's fixture
  (`test/header_standardization_test.dart`) seeds sessions whose entries carry no effort rows, so
  `_instrumentSections` is empty and `InstrumentList` never renders; the only `OmniCardHeader` left
  on the screen is the `ALL TIME` eyebrow. The three legacy eyebrows (`STRENGTH`, `CARDIO`,
  `NUTRITION`) no longer exist anywhere, which is why they are not in the expected list.
- [x] `gateway.sh test test/stats_legacy_removal_test.dart` → `00:00 +8: All tests passed!`
- [x] `gateway.sh format` → `Formatted 6 files (2 changed) in 0.10 seconds.` on the six touched files
  during the work, and `Formatted 7 files (0 changed) in 0.10 seconds.` on the re-verification pass over
  those six plus the guard.
- [x] `gateway.sh lint` → `196 issues found. (ran in 5.0s)`, 0 errors; the only `warning` is the
  pre-existing `constant_pattern_never_matches_value_type` at
  `lib/features/routine/routine_setup_screen.dart:1046:12` (an unmodified file); the other 195 are
  `info`. Bar ≤199 met.

**Test-count reconciliation (fix round 1 — by test name).** `+N` excludes skipped tests (proved:
`gateway.sh test test/profile_navigation_test.dart` → `+0 ~1: All tests skipped.` — one declaration
with `skip: true`). This block first carried declaration-level arithmetic that was wrong by two and
recorded the printed line as `+3230 ~1`. The reconciliation below is name-level, against the
governor's exact name diff (`.work/stats-pr4c/test-name-diff.md`, produced with the JSON reporter in
a scratch worktree).

| Removed names, by file | Count |
|---|---|
| `test/screen_widget_test.dart` (21 retired tests; one name — the vacuous toggle test — is re-added under a new title) | 22 |
| `test/stats_distance_estimate_test.dart` (S-831 a/b, S-832, S-835 ×3, S-836 renamed, S-837, the single-point card ×3) | 11 |
| `test/instrument_list_screen_test.dart` (S-1012, S-1015 × Mock/Hive) | 4 |
| `test/nutrition_trend_screen_test.dart` (S-1110(a) × Mock/Hive, two names each) | 4 |
| `test/entry_identity_summary_test.dart` (S-858) | 1 |
| `test/header_standardization_test.dart` (S-005) | 1 |
| **Total removed** | **43** |

| Added names, by file | Count |
|---|---|
| `test/stats_legacy_removal_test.dart` (**new** — 2 source guards + 6 behavioural, 3 fixtures × 2 harnesses, including the transcribed S-836 under its `S-1209 source guard` title) | 8 |
| `test/instrument_list_screen_test.dart` (the four retitled absence tests) | 4 |
| `test/nutrition_trend_screen_test.dart` (one trend-only test per harness) | 2 |
| `test/entry_identity_summary_test.dart` (the retitled S-858) | 1 |
| `test/screen_widget_test.dart` (`Stats renders no SegmentedButton`) | 1 |
| **Total added** | **16** |

| Item | Tests |
|---|---|
| HEAD baseline (`+3256 ~1` = 3,257 names) | 3,257 |
| Removed | −43 |
| Added | +16 |
| **Names on the tree after 4c** | **3,230** |
| of which declared `skip: true` (not counted in `+`) | 1 |
| **Printed by the runner** | **`+3229 ~1`** |

Net −27, with no residual: every name removed and every name added is attributed to a file above.

**Out-of-bounds finding.** `test/entry_identity_summary_test.dart` (S-858) asserted the deleted
cardio card's `Distance:`/`Pace:` rows on the Stats screen and was **not** in the phase's Predicted
Files; it failed only in the full suite. Phase 1's deletion removed exactly those two source lines
(`'Distance: ${value.toStringAsFixed(2)} $distUnit$estimateSuffix'` and
`'Pace: ${displayPace.toStringAsFixed(0)} s/$distUnit$estimateSuffix'`). Fixed by the same method as
the five plan-named files — both assertions flipped to `findsNothing`, the test retitled to the
absence premise. Flagged to the Governor: a retirement the plan's test sweep missed.

**Red→green proof (step 21).** Each mutation was applied to `lib/features/stats/stats_screen.dart`,
run against `test/stats_legacy_removal_test.dart`, then reverted; `git-diff --stat` after each revert
returns to `1 file changed, 7 insertions(+), 1129 deletions(-)` and the guard returns to `+8`.

| Mutation | Result | Exact output |
|---|---|---|
| M-1 re-add `const Column(key: Key('stats_legacy_sections'), children: [])` after the `ALL TIME` header | `00:00 +3 -5: Some tests failed.` — source guard fails, then the four non-empty-fixture behavioural tests (Mock + Hive × *all kinds of history* / *sessions but no food*). The two *zero completed sessions* tests pass, correctly: the empty-state branch never renders the key. A second M-1 form — the same key on a `Column` whose children carried the five legacy titles — failed **7 of 8** (`00:00 +1 -7: Some tests failed.`): the fragment source guard plus all six behavioural absence loops, with only the km↔mi guard passing. Its key check passed because a zero-height *leading* child of the `ListView` is not reported by `find.byKey` (Assumption Log note 9). | `Expected: no matching candidates` / `Actual: _KeyWidgetFinder:<Found 1 widget with key [<'stats_legacy_sections'>]: [Column-[<'stats_legacy_sections'>](direction: vertical, …, renderObject: RenderFlex#5c180 relayoutBoundary=up5)]>` / `Which: means one was found but none were expected` — thrown at `stats_legacy_removal_test.dart:371` inside `expectNoLegacySurface`. The source guard failed first with `D-606(b): \`stats_legacy_sections\` must never return to lib/features/stats/stats_screen.dart — the legacy layout is removed, not hidden`. |
| M-2 add `const _miPerKm = 0.621371;` after the imports | `00:00 +7 -1: Some tests failed.` — only the km↔mi source guard fails; all six behavioural tests pass (the literal is inert without a reader). | `00:00 +1 -1: S-1209 source guard S-836 the Stats screen holds no km↔mi constant [E]` / `Expected: false` / `Actual: <true>` / `D-314: the conversion belongs to UnitFormatter.metresPerUnit, never to a literal in this file (0.621371)` at `stats_legacy_removal_test.dart:321:9` |

**Footprint.** No production file changed in Phase 2 (`lib/features/stats/stats_screen.dart` is
Phase 1's diff, byte-identical after both mutation reverts). Test-side: the five plan-named files plus
`test/entry_identity_summary_test.dart` (out-of-bounds, above) plus the new
`test/stats_legacy_removal_test.dart`.

### Phase 3 (@developer)

- [x] `docs/stats_screen.md` new line count and byte size (≤64 KiB) → **309 lines**, from the diff's
  final hunk header `@@ -670,10 +301,9 @@` (the file was 679 lines before). Byte size is **not
  directly measurable**: no `gateway.sh` subcommand exposes a file size, `--numstat` is refused, and
  no other shell command was run. It is bounded instead — the whole file was read back with no
  truncation, so it is under the reader's 20 KB threshold, and
  `test/docs_indexing_contract_test.dart` passes both its 64 KiB ceiling and its
  80 %-of-ceiling warning band (51,200 bytes), so it is under 51,200 bytes. Churn as reported by
  `gateway.sh git-diff --stat`: `docs/stats_screen.md | 642 ++------`.
- [x] `gateway.sh test test/docs_indexing_contract_test.dart test/stats_legacy_removal_test.dart test/screen_widget_test.dart` final line → `00:08 +246: All tests passed!`
- [x] The residue sweep's expected residuals (only `test/stats_legacy_removal_test.dart` string literals)
  → confirmed, by the three means the plan allows, since **no grep tool exists in this runtime**:
  (a) the source guard in `test/stats_legacy_removal_test.dart` reads
  `lib/features/stats/stats_screen.dart` and fails on any of the eight retired identifiers
  (`stats_legacy_sections`, `_buildStrengthSection`, `_buildCardioSection`, `_buildIsometricSection`,
  `_buildSportsSection`, `_buildNutritionSection`, `_ChartSeries`, `_LinearScale`) or on the km↔mi
  literal — it passes, so none of them survives in that file; (b) `gateway.sh git-diff --name-only`
  shows `lib/features/stats/stats_screen.dart` as the only `lib/` change in the whole series, so no
  other production file was touched that could carry them; (c) the full suite is green, which
  includes the absence assertions. The eight names remain in the tree **only** as the guard's own
  string literals and in its failure messages, which is the expected residual. This is a
  source-of-evidence sweep, not an exhaustive text search: the runtime has no search primitive, so
  no claim is made about files outside the Predicted Files beyond what (b) and (c) cover.

**Docs swept (Phase 3, step 25).** The sweep widened past the phase's Predicted Files
(`docs/stats_screen.md`, `docs/README.md`) because the plan's own rationale — "a claim elsewhere
that a removed section still renders" — is not bounded by those two files. Widening is recorded in
the plan's Assumption Log (entries 10–13) and the phase is still **Complete**; the reviewer is the
right place to overturn any of the widened edits.

| Doc | Touched? | What changed |
|---|---|---|
| `docs/stats_screen.md` | rewritten | Version 3.0; legacy sections, charts, PR list and effort-rating block deleted |
| `docs/README.md` | yes | Stats Screen index row now describes the post-4c screen |
| `docs/distance_source.md` | yes | Three dangling verification claims reconciled |
| `docs/records_and_trends.md` | yes | Two Stats-screen clauses removed (PRs live here now) |
| `docs/widget_catalog.md` | yes | Window-chip row, nutrition-card note + heading, Fuel heading, `ScrollableTrendChart` row |
| `docs/design_system.md` | yes | Stats header row |
| `docs/app_philosophy.md` | yes | Audit note "Fuel row"; "plus SQLite tables" dropped |
| `docs/navigation_and_screens.md` | yes | `StatsScreen` + `NutritionTrendScreen` rows; anchor → `#fuel-row` |
| `docs/profile_and_measurements.md` | yes | Two clauses |
| `docs/session_summary.md` | yes | Two "…the Stats screen use" clauses trimmed |
| `docs/data_models.md` | yes | `PRAchievement` row no longer says the Stats screen renders PRs |

| Doc | Checked, no claim needed changing |
|---|---|
| `docs/state_management.md` | index: no removed-section claim |
| `docs/state_management/app_state.md` | read in full: `SettingsState`'s Effort Rating toggle is a Settings/prompt feature, not a Stats section |
| `docs/state_management/services_and_utils.md` | `StatsProgressService` + `computeInstrumentSections` + the shared formatters sections: all still describe what survives |
| `docs/state_management/nutrition_state.md` | no Stats claim |
| `docs/widget_catalog/nutrition_widgets.md` | no Stats claim |
| `docs/widget_catalog/feature_primitives.md` | no Stats claim |
| `docs/constants_reference.md` | no Stats claim |
| `docs/theme_and_settings.md` | toggle only |
| `docs/stats_best_load_investigation.md` | dated investigation; left unchanged (flagged for the reviewer in Assumption Log note 13) |

Not read in Phase 3: `docs/state_management/workout_state.md`,
`docs/widget_catalog/{home_screen,layout_and_inputs,session_widgets}.md`,
`docs/navigation_contract.md`, `docs/watch_session_capture.md`, `docs/watch-app-setup-and-qa.md`,
`docs/future-work.md`, `docs/memories/*`, `docs/history/*`, `docs/releases/*`.

---

# Fix round 1 — review findings F-1…F-8

Source: `.work/stats-pr4c/brief-fix-1.md` — six findings from the code review plus two
lost-guard findings (retired tests that guarded behaviour which still exists).

| ID | Finding | Fix | Check observed |
|---|---|---|---|
| F-1 | Plan did not declare its delivered footprint | Plan states the footprint and the Files Affected table | matches `gateway.sh git-status` |
| F-2 | Test-count claim was wrong | `+3230 ~1` → `+3229 ~1` in plan **and** evidence; the count arithmetic replaced by a name-level table built from `.work/stats-pr4c/test-name-diff.md` | both files read `+3229 ~1` |
| F-3 | Comment in `lib/features/stats/stats_screen.dart` named a second caller of `_loadData` that does not exist | clause removed | comment now matches the single call site |
| F-4 | `docs/stats_screen.md` streak row named an icon and a three-day threshold (presentation detail) | prose deleted; the row points at `test/screen_widget_test.dart` | doc-standard violation removed |
| F-5 | `docs/stats_screen.md` claimed a loading spinner that no test covers | sentence deleted | doc-standard violation removed |
| F-6 | Plan Assumption 12 cited a test that does not exist | amended to cite `test/instrument_list_screen_test.dart` | cited file exists |
| F-7 | Lost guard: PR weight-unit conversion | new guard in `test/records_and_trends_screen_test.dart` | red → green (below) |
| F-8 | Lost guard: Calories/Macros toggle at max text scale | new guard in `test/nutrition_trend_screen_test.dart` | red → green (below) |

## F-7 / F-8 — the two new guards

Both tests sit inside their file's existing `for (final factory in harnessFactories)` loop, so each
test **body** runs once per harness. Added: 2 test names, 4 runs.

**F-7** — `test/records_and_trends_screen_test.dart`, group `Recent PRs weight unit`, test
`a PR row reads the record in pounds when the weight unit preference is pounds`.
`setUp` seeds `ex-bench` (Bench Press), a 100 kg × 5 set (`s-lbs`, 2 days ago) and
`settingsState.setPreferredWeightUnit('lbs')`. The test asserts the `RecentPRList` texts contain
`Recent PRs`, `Bench Press` and `_e1RmLabel(100, 5, settingsState)` — `257.2 lbs`, guarded by an
`endsWith('lbs')` fixture check — and that no text under the list ends in `kg`.

- Red proof: `lib/features/stats/widgets/recent_pr_list.dart` mutated to
  `final displayE1Rm = pr.e1Rm!;` → `00:01 +10 -2: Some tests failed.` on both harnesses, with
  `Expected: contains '257.2 lbs'` / `Actual: ['Recent PRs', 'Bench Press', '116.7 lbs', 'Sep 29, 2026']`.
  Mutation reverted; `gateway.sh git-diff` shows the file unmodified.

**F-8** — `test/nutrition_trend_screen_test.dart`, group `Calories / Macros labels at max text scale`,
test `both labels lay out on one line at 5.0 x text`. `pumpTrend` gained optional `surface` /
`textScale` parameters; the scaler is applied **inside** `MaterialApp` because `WidgetsApp`
re-inserts `MediaQuery.fromView` over any outer override. The test pumps at `Size(1400, 3000)` with
`TextScaler.linear(5.0)` and asserts each toggle label measures `closeTo(oneLine.height, 1)`, where
`oneLine` is a `TextPainter` built from the label's own style.

- Red proof: `lib/features/nutrition/widgets/nutrition_trend_card.dart` mutated to wrap the Calories
  label in `const SizedBox(width: 40, …)` → `00:01 +10 -2: Some tests failed.` on both harnesses, with
  `Expected: a numeric value within <1> of <100.0>` / `Actual: <200.0>` /
  `Calories wrapped onto more than one line`. Mutation reverted; file restored.
- Measured: one line at 5.0× is `100.0` px tall; a wrapped label is `200.0`.
- The pump installs a local `FlutterError.onError` filter for `overflowed` messages, because at 5.0×
  the trend chart's pinned y-axis overflows **vertically by 332 px** (`_PinnedYAxis` in
  `lib/features/stats/widgets/scrollable_trend_chart.dart` is a fixed-height band holding 9 px tick
  labels). That is the chart's geometry, not the toggle's; it is pre-existing and unrelated to 4c
  (reported under Open questions in the fix-round response; the brief scopes this round to F-1…F-8
  only). Precedent for the filter: `test/screen_overflow_contract_test.dart`.
- The width/truncation half of the retired guard is not carried over: the test font is fictional
  (every glyph a full em wide, per `test/screen_overflow_contract_test.dart`), so a measured width is
  not a statement about the shipped font. Height is, and height is what the guard asserts.
- The 1400 px measuring surface is required because `SegmentedButton` splits the available width
  equally and the test font's glyphs are a full em wide: at 5.0× `Calories` needs ≈560 px, so the
  existing 400 px `_kTallViewport` cannot be reused.

## Verification (fix round 1)

| Command | Final line observed |
|---|---|
| `gateway.sh test test/records_and_trends_screen_test.dart test/nutrition_trend_screen_test.dart test/docs_indexing_contract_test.dart test/stats_legacy_removal_test.dart` | `00:01 +45: All tests passed!` |
| `gateway.sh test` (full suite, exit 0) | `01:29 +3233 ~1: All tests passed!` |
| `gateway.sh lint` | `196 issues found. (ran in 2.9s)` |

- Lint detail: 0 errors, 1 pre-existing `warning` (`lib/features/routine/routine_setup_screen.dart:1046`,
  untouched by this series), 195 `info`. Bar was ≤199 issues with 196 expected — met, unchanged by the
  two new tests (neither test file appears in the analyzer output).
- Count reconciliation: the suite moved `+3229 ~1` → `+3233 ~1`. The brief predicted `+3231 ~1` (+2);
  the observed delta is +4 because both new tests live inside their file's `harnessFactories` loop and
  therefore execute once per harness. 2 new test names, 4 new runs. `~1` is unchanged (the single
  `skip: true` declaration is not in either touched file).
