# Evidence — Stats PR 4b3 (the Fuel row)

> Plan: `2026-10-01-04b3-stats-pr4b3-fuel-row-plan.md` (same folder).
> Series index: `../../2026-09-30-04-stats-pr4-index.md`.
> Review findings go in `2026-10-01-04b3-stats-pr4b3-fuel-row-plan.review.md` (the reviewer creates it).
> **Nothing goes in the plan file** except its own Progress and Assumption Log rows.

Executors: append, never rewrite. Quote command output **verbatim** — the final summary line, plus the
failing lines for a red run or a mutation. A claim in this file with no pasted output is not evidence.

---

## §1 Baselines

### §1.1 Planner's run — 2026-10-01, before any phase was written

Taken with the only permitted shell command, the gateway:

```
.github/copilot/scripts/macos/gateway.sh lint
.github/copilot/scripts/macos/gateway.sh test
```

Verbatim final lines:

| Command | Exit | Final line | Reading |
|---|---|---|---|
| `gateway.sh lint` | 1 | `199 issues found. (ran in 3.1s)` | the expected non-zero: 199 pre-existing issues, **0 errors**. This is the analyzer bar: no more than 199, and every touched file at 0 issues. |
| `gateway.sh test` | 0 | `01:20 +3208 ~1: All tests passed!` | 3,208 passing, 1 skipped, 0 failing. |

**Do not treat these as your baseline.** Step 0b of the plan requires you to run both yourself and paste
what you actually saw; 4b2's tests and any later work will have moved the numbers. A different baseline is
information, not a failure. A baseline you did not take is a failure.

### §1.2 Executor's run — 2026-10-01, before Phase 1 was started (Step 0b)

```
.github/copilot/scripts/macos/gateway.sh lint
.github/copilot/scripts/macos/gateway.sh test
```

Verbatim final lines:

| Command | Exit | Final line | Reading |
|---|---|---|---|
| `gateway.sh lint` | 0 | `199 issues found. (ran in 3.3s)` | 199 pre-existing issues, **0 errors** — identical to the planner's run. The analyzer bar is ≤ 199 and every touched file at 0 issues. |
| `gateway.sh test` | 0 | `01:19 +3208 ~1: All tests passed!` | 3,208 passing, 1 skipped, 0 failing — identical to the planner's run. |

The tree has not moved since the planner's run: the brief's expected `199 issues found.` (0 errors)
and `+3208 ~1` are what this executor saw.

### §1.3 The shell, as it behaves in this checkout

- Invoke the gateway as `.github/copilot/scripts/macos/gateway.sh <cmd>`. A leading `./` was rejected by the
  harness on this checkout ("Permission denied and could not request permission from user"); the bare
  relative path works. Record it here if your run differs.
- Allowed subcommands: `list`, `lint`, `test [paths]`, `build`, `codegen`, `pub-get`, `format <paths>`,
  `git-status`, `git-diff [<ref>] [--stat|--name-only|--name-status|--cached] [-- <path>...]`,
  `git-log [<count>] [<ref>]`, `git-show <ref> [--stat]`. No `grep`, `cp`, `sed`, `mv`, `rm`, `/tmp` or
  plain `git`.
- A large output is written to a temp file and the path is printed; read it with `view` or search it with
  the built-in search tool.

---

## §2 Phase 1 — the NUTRITION card extraction (`@developer`)

### §2.1 Red run (before any production code)

Two red states, both observed and pasted below.

**(a) The compile failure.** `test/nutrition_trend_screen_test.dart` was written before any production code
(Rule 2), so it could not load at all. Reproduced verbatim by removing the screen's class name from the new
screen file (an **untracked** file, so no residue in `git-diff`), then inverted:

```
00:00 +0: loading /Users/irinakutsenko/Developer/omnitrain/test/nutrition_trend_screen_test.dart
test/nutrition_trend_screen_test.dart:189:19: Error: Method not found: 'NutritionTrendScreen'.
00:00 +0 -1: loading /Users/irinakutsenko/Developer/omnitrain/test/nutrition_trend_screen_test.dart [E]
  Failed to load "/Users/irinakutsenko/Developer/omnitrain/test/nutrition_trend_screen_test.dart":
  Compilation failed for testPath=/Users/irinakutsenko/Developer/omnitrain/test/nutrition_trend_screen_test.dart: test/nutrition_trend_screen_test.dart:189:19: Error: Method not found: 'NutritionTrendScreen'.
00:00 +0 -1: Some tests failed.
```

Exit 1. This is the same error the first write-time run produced.

**(b) The named assertion.** Once the file compiles, the S-1110(a) parity assertion is the test that can
fail. Its red run is M1 in §2.3 — verbatim, `+0 -2` with
`Actual: _WidgetPredicateWidgetFinder:<Found 0 widgets with widget matching predicate: []>` on both
harnesses.

#### §2.1.1 The first run of the file hung — diagnosis and fix

The first run of `test/nutrition_trend_screen_test.dart` **hung**: over seven minutes, zero output, no
`+n` counter. A hang is a failure, so it was diagnosed rather than re-run:

- A control run of an unrelated state test through the same gateway finished in under a second, so the
  environment and the gateway were not the cause.
- `--plain-name "zzz-no-such-test"` returned `No tests ran.` (exit 79), which proves the file itself
  compiles and loads.
- `--plain-name "Mock"` completed in `00:00` (3 of its 4 tests failing on real assertions);
  `--plain-name "Hive"` passed 4 and then stalled on the fifth. So the hang was in the Hive harness, on
  the seeding path.
- `--timeout` did **not** turn the hang into a failure. Only the `--plain-name` bisection found it.

**Cause 1 — repository I/O awaited inside a `testWidgets` body.** Seeding was called as
`await _seedFood(repo, …)` from inside the widget test. Hive's write future completes only after the real
file write, and real I/O never resolves under the `FakeAsync` that `testWidgets` installs, so the test never
finishes. The Mock harness hid this: its in-memory write completes on a microtask. **Fix:** every scenario
seeds in the `setUp` of its own group, never in a `testWidgets` body.

**Cause 2 — the two harnesses do not open the same fixture.** `MockWorkoutRepository.initialize()` seeds
`SeedData.sampleConsumedFoods()`, a **now-relative demo log roughly 23 days long**; `HiveWorkoutRepository`
opens empty. Assertions written against an empty log therefore failed on Mock for three different reasons
(the chart was never empty; the single-point case had many points; and the target line, saved a few days
back, fell in the *future* of Mock's earliest actuals day, so `getNutritionTargetForDate`'s backward walk
found nothing to project). **Fix:** `_clearConsumedFoods(repo)` — a
`getConsumedFoodsInRange(0, 4102444800000)` + `deleteConsumedFood` sweep — runs in `setUp` of every group,
so both harnesses start from a cleared log. After both fixes: `00:01 +10: All tests passed!`.

### §2.2 Suites after the phase

| Command | Exit | Final line (verbatim) |
|---|---|---|
| `gateway.sh lint` | 1 | `199 issues found. (ran in 1.6s)` |
| `gateway.sh test` | 0 | `01:25 +3218 ~1: All tests passed!` |
| `gateway.sh test test/nutrition_trend_screen_test.dart` | 0 | `00:01 +10: All tests passed!` |

Pre-existing Stats assertions, run **unmodified** — `test/screen_widget_test.dart`,
`test/header_standardization_test.dart`, `test/stats_progress_test.dart`:

| Command | Exit | Final line (verbatim) |
|---|---|---|
| `gateway.sh test test/screen_widget_test.dart test/header_standardization_test.dart test/stats_progress_test.dart` | 0 | `00:09 +385: All tests passed!` |

The phase's contract suites — `test/navigation_contract_enforcement_test.dart`,
`test/screen_overflow_contract_test.dart`, `test/docs_indexing_contract_test.dart` — run together with the
trio and the new file gave `+453: All tests passed!`; `test/docs_indexing_contract_test.dart` re-run **after**
the doc edits gave `00:00 +9: All tests passed!`.

**No surface height moved and no assertion was changed.** The move is figure-identical (S-1110(a)): the
Stats NUTRITION section and the trend screen render one widget from one set of inputs, so nothing to record
here.

Counts: `+3218 ~1` against §1.2's `+3208 ~1` — exactly the 10 new tests, no regression.

**Analyzer bar — one honest exception.** `0 errors`, and the total is `199` — identical to the baseline.
The three new `lib/` files are clean (`grep` for their paths over the lint output returns nothing).
`lib/features/stats/stats_screen.dart` does **not** sit at 0 issues; it carries one pre-existing warning,
the only one:

```
warning • The declaration '_ChartSeries' isn't referenced • lib/features/stats/stats_screen.dart:1313:7 • unused_element
```

It is not from this phase: `_ChartSeries` appears nowhere in `git-diff`, and no file in `lib/` or `test/`
references it. It was left alone rather than fixed, because the phase's Predicted Files say "Nothing else"
and Rule 5's bar is "none new" — which holds, since the count did not move. The Done-Criteria line
"each of the four touched `lib/` files at 0 issues" is therefore **not literally met**; it is reported
rather than worked around.

### §2.3 Mutation proofs

Both mutations target **`lib/features/stats/stats_screen.dart`**, which is tracked.

The diff before and after every mutation, verbatim:

```
lib/features/stats/stats_screen.dart | 853 +----------------------------------
 1 file changed, 20 insertions(+), 833 deletions(-)
```

| # | Edit | Test that must fail | Result |
|---|---|---|---|
| M1 | pass `const []` as the delegated card's trend points | S-1110(a) figure assertion | **fails, then green** — see below |
| M2 | pass no adherence data to the delegated card | the target-line assertion | **fails, then green** — see below |

**M1.** Edit, in `_buildNutritionSection`:

```dart
final trend = const <NutritionTrendPoint>[];
```

`gateway.sh test test/nutrition_trend_screen_test.dart --plain-name "plots the same calories actuals"`:

```
00:00 +0: Nutrition trend — Mock S-1110(a) the trend screen plots the same calories actuals as the Stats NUTRITION card
  Actual: _WidgetPredicateWidgetFinder:<Found 0 widgets with widget matching predicate: []>
00:00 +0 -1: Nutrition trend — Mock S-1110(a) the trend screen plots the same calories actuals as the Stats NUTRITION card [E]
00:00 +0 -1: Nutrition trend — Hive S-1110(a) the trend screen plots the same calories actuals as the Stats NUTRITION card
  Actual: _WidgetPredicateWidgetFinder:<Found 0 widgets with widget matching predicate: []>
00:00 +0 -2: Nutrition trend — Hive S-1110(a) the trend screen plots the same calories actuals as the Stats NUTRITION card [E]
00:00 +0 -2: Some tests failed.
```

Exit 1 — the parity assertion fails on **both** harnesses. Inverse applied
(`final trend = _progressData?.nutritionTrend ?? const [];`), diff back to `20 insertions(+), 833
deletions(-)`, `00:01 +10: All tests passed!`.

**M2.** Edit: `adherence: _nutritionAdherence,` → `adherence: null,`.
`gateway.sh test test/nutrition_trend_screen_test.dart --plain-name "both hosts draw the target line"`:

```
Expected: an object with length of <2>
  Actual: [
   Which: has length of <1>
00:00 +0 -2: Nutrition trend — Hive S-1110(a) both hosts draw the target line over the same actuals [E]
  Test failed. See exception logs above.
00:00 +0 -2: Some tests failed.
```

Exit 1 — the delegated card loses its target series (2 series → 1) on both harnesses. Inverse applied, diff
back to `20 insertions(+), 833 deletions(-)`, `00:01 +10: All tests passed!`.

### §2.4 Residue sweep

```
$ grep -rn "_kBottomAxisReservedSize\|_buildLegendItem\|_buildSinglePointCard" lib/ test/
lib/features/stats/exercise_progress_screen.dart:47:  static const double _kBottomAxisReservedSize = 20;
lib/features/stats/exercise_progress_screen.dart:215:      return _buildSinglePointCard(
lib/features/stats/exercise_progress_screen.dart:254:                  reservedSize: _kBottomAxisReservedSize,
lib/features/stats/exercise_progress_screen.dart:317:  Widget _buildSinglePointCard({
```

No copy is left in `stats_screen.dart`, and none in the nutrition files. The new primitives file declares
each name exactly once:

```
$ grep -rn "kChartBottomAxisReservedSize\|buildLegendItem\|buildSinglePointCard" lib/ | grep -v "^lib/widgets/chart/chart_primitives.dart"
lib/features/nutrition/widgets/nutrition_trend_card.dart:190, 378, 566   reservedSize: kChartBottomAxisReservedSize
lib/features/nutrition/widgets/nutrition_trend_card.dart:624            buildSinglePointCard(
lib/features/nutrition/widgets/nutrition_trend_card.dart:680, 700–702   buildLegendItem(
lib/features/stats/stats_screen.dart:339, 360, 385                      buildSinglePointCard(
lib/features/stats/stats_screen.dart:475, 700, 1061                     reservedSize: kChartBottomAxisReservedSize
lib/features/stats/stats_screen.dart:936, 942, 949                      buildLegendItem(
```

Every occurrence outside the primitives file is a **reader**, in the two intended hosts — the staying legacy
charts on the Stats screen and the moved nutrition card.

**One residue D-533 does not expect, and this phase did not create.**
`lib/features/stats/exercise_progress_screen.dart` holds its own private `_kBottomAxisReservedSize` and
`_buildSinglePointCard`. That file is **not in this phase's Predicted Files** and is **absent from
`git-diff`**, so those copies predate the move — they are the Exercise Progress screen's own, not a
duplicate the move produced. D-533's "no copy of any of the three may remain in `lib/`" is therefore not
literally met, and fixing it would mean editing a file outside the phase's scope (Rule 8 / the PR budget).
Flagged for the reviewer rather than absorbed.

### §2.5 Docs

All three Phase 1 doc rows are done:

| Doc | What changed |
|---|---|
| `docs/stats_screen.md` | The NUTRITION section now names `NutritionTrendCard` as the widget it renders and states that the same widget backs the trend screen, with the test that holds them together. Core Files gains the three new files. The Key Constants table is unchanged, as the checklist requires. |
| `docs/widget_catalog.md` | A new note paragraph beside the Instruments note: `NutritionTrendCard` and its path, feature-scoped but presentation-only, and the fact that the Stats NUTRITION section and the trend screen render the same widget. |
| `docs/navigation_and_screens.md` | A `NutritionTrendScreen` row in the Screen Inventory. Its entry point is Phase 2's, so the row does not claim one. |

No `docs/nutrition.md` — 4c owns it (D-534).

The §Doc-claim → test rows this phase's tests now cover:

| Doc | Claim | Test |
|---|---|---|
| `docs/stats_screen.md` | the NUTRITION section renders the extracted `NutritionTrendCard`, unchanged | S-1110(a) — `test/nutrition_trend_screen_test.dart`, and M1/M2 above |
| `docs/widget_catalog.md` | the extracted nutrition trend card and the trend screen, with their paths | S-1110(a) |
| `docs/navigation_and_screens.md` | the trend screen exists and renders the card | S-1109 (its toggle) — the *entry point* half of this row is Phase 2's |

`test/docs_indexing_contract_test.dart` is green after the edits (`00:00 +9: All tests passed!`), so the
prose added is inside the size ceiling and free of the flow-walkthrough and roadmap shapes that test
rejects.

---

## §3 Phase 2 — the Fuel row (`@developer`)

### §3.1 Red run (before any production code)

`test/fuel_row_screen_test.dart` was written first (Rule 2). Its first run was red in the shape pasted as
**(a)** below, and it is also the run that produced the hang diagnosed in §3.1.1. That write-time output was
**not** captured verbatim, so both red states below were **re-produced after the phase was green** — by
inverting production code, observing the failure, and restoring it. Each restore is confirmed by the
`git-diff` stat returning to its pre-mutation value.

**(a) The compile failure.** The test cannot load while `FuelSection` does not exist. Reproduced by renaming
the class and its constructor in `fuel_section.dart` — an **untracked** file, so the rename leaves no trace
in `git-diff` — then inverting it:

```
00:00 +0: loading /Users/irinakutsenko/Developer/omnitrain/test/fuel_row_screen_test.dart
lib/features/stats/stats_screen.dart:173:31: Error: The method 'FuelSection' isn't defined for the type '_StatsScreenState'.
 - '_StatsScreenState' is from 'package:omnitrain/features/stats/stats_screen.dart' ('lib/features/stats/stats_screen.dart').
Try correcting the name to the name of an existing method, or defining a method named 'FuelSection'.
                              FuelSection(
                              ^^^^^^^^^^^
00:00 +0 -1: loading /Users/irinakutsenko/Developer/omnitrain/test/fuel_row_screen_test.dart [E]
  Failed to load "/Users/irinakutsenko/Developer/omnitrain/test/fuel_row_screen_test.dart":
  Compilation failed for testPath=/Users/irinakutsenko/Developer/omnitrain/test/fuel_row_screen_test.dart: lib/features/stats/stats_screen.dart:173:31: Error: The method 'FuelSection' isn't defined for the type '_StatsScreenState'.
00:00 +0 -1: Some tests failed.
```

Exit 1. The error surfaces in `stats_screen.dart` rather than the test file because the test reaches the row
through the screen.

**(b) The named assertion.** With the file compiling, the row's existence is what every scenario asserts, so
the red state that matters is the wiring. Reproduced by gating the `FuelSection` block in
`lib/features/stats/stats_screen.dart` behind `if (false && _fuelSummary != null)`:

```
00:03 +6 -30: Fuel row — Hive S-1112 with no training period a different window leaves the figures alone [E]
  Test failed. See exception logs above.
  The test description was: a different window leaves the figures alone
00:03 +6 -30: Some tests failed.
```

Exit 1 — 30 of the 36 tests fail (15 scenarios × 2 harnesses; the 3 that survive are the row-absent ones).
The named assertion, `--plain-name "S-1101"`:

```
00:00 +0: Fuel row — Mock S-1101 the averages are the mean of the logged days, not of the window
The following StateError was thrown running a test:
Bad state: No element
#1      _fuelText (file:///Users/irinakutsenko/Developer/omnitrain/test/fuel_row_screen_test.dart:56:67)
#2      main.<anonymous closure>.<anonymous closure>.<anonymous closure> (file:///Users/irinakutsenko/Developer/omnitrain/test/fuel_row_screen_test.dart:284:18)
```

Inverse applied, `git-diff --stat` back to `171 insertions(+), 833 deletions(-)` across the two tracked
files, `00:02 +36: All tests passed!`.

#### §3.1.1 The first run of the file hung — diagnosis and fix

The write-time run **hung** on its Hive leg: it printed the Mock failures and then produced no further
output for four minutes and thirty-one seconds, ending with
`Bad state: Cannot close sink while adding stream` and a test that `did not complete`. A hang is a failure,
so it was diagnosed rather than re-run. (The two error strings are quoted from that run; the run was not
re-captured afterwards.)

**Cause — repository I/O awaited inside a `testWidgets` body.** The fixtures were originally seeded from
inside the test body. A widget-test body runs under the `FakeAsync` that `testWidgets` installs, where Hive's
write future — which completes only after the real file write — never settles. The Mock harness hid this:
its in-memory write completes on a microtask. **Fix:** every fixture is seeded, and every model read is
taken, in the `setUp` of the scenario's own group, never in a body.

This is the same failure mode Phase 1 recorded in §2.1.1, found independently in a second file, so it is a
property of the harness rather than of one test.

**Second fixture hazard, found in the same diagnosis.** `MockWorkoutRepository.initialize()` seeds
`SeedData.sampleConsumedFoods()`, a now-relative demo log; `HiveWorkoutRepository` opens empty. Every group
therefore clears the food log in `setUp` (`getConsumedFoodsInRange(0, 4102444800000)` + `deleteConsumedFood`)
and seeds at least one session — without a session the screen's zero-session empty state wins and no Fuel row
renders at all (D-525).

That precedence was **not** asserted when this section was first written; it is asserted by `S-1110(b)`,
added in fix round 1 (§5). Its observed run:

```
00:00 +0: Nutrition trend — Mock S-1110(b) the empty state renders and no Fuel row is in the tree
00:00 +1: Nutrition trend — Hive S-1110(b) the empty state renders and no Fuel row is in the tree
00:00 +2: All tests passed!
```

### §3.2 Suites after the phase

| Command | Exit | Final line (verbatim) |
|---|---|---|
| `gateway.sh lint` | 1 | `199 issues found. (ran in 2.6s)` |
| `gateway.sh test` | 0 | `01:17 +3254 ~1: All tests passed!` |
| `gateway.sh test test/fuel_row_screen_test.dart` | 0 | `00:02 +36: All tests passed!` |
| `gateway.sh test test/db_seed_test.dart` (unmodified and green) | 0 | `00:00 +9: All tests passed!` |
| `gateway.sh test test/navigation_contract_enforcement_test.dart test/screen_overflow_contract_test.dart test/docs_indexing_contract_test.dart` | 0 | `00:01 +58: All tests passed!` |

Counts: `+3254 ~1` against §2.2's `+3218 ~1` — exactly the 36 new tests (18 scenarios × the two harnesses),
no regression, and the skipped test is unchanged. `scripts/sqlite_schema.sql`, `scripts/sqlite_seed.sql` and
`test/db_seed_test.dart` are **unmodified** (absent from `gateway.sh git-status`): this phase persisted
nothing, as the plan's "Known exclusions" predicted.

**Analyzer bar — the same honest exception as Phase 1.** `0 errors`, total `199` — identical to the
baseline. The phase's own four `lib/` files at 0 issues; `lib/features/stats/stats_screen.dart` carries the
one pre-existing warning, which this phase moved from 1313 to 1336 without creating it:

```
warning • The declaration '_ChartSeries' isn't referenced • lib/features/stats/stats_screen.dart:1336:7 • unused_element
```

The Done-Criteria line "each of the four touched `lib/` files at 0 issues" is therefore **not literally
met**; it is reported, not worked around (Rule 5's bar is "none new", and the total did not move).

`gateway.sh format` ran over the five files this phase owns. `stats_screen.dart`'s stat is unchanged by it
(`43 insertions(+), 833 deletions(-)`, Phase 1's uncommitted refactor untouched); the service's went from
131 to 128 insertions, still 0 deletions.

### §3.3 Mutation proofs

M3–M5 target **`lib/core/services/stats_progress_service.dart`**; M6 (added in fix round 1, §5) targets
**`lib/features/stats/stats_screen.dart`**. Both are tracked. The diff stat of the mutated file before and
after each mutation, verbatim:

```
lib/core/services/stats_progress_service.dart | 128 ++++++++++++++++++++++++++
 1 file changed, 128 insertions(+)
```

M6's baseline is `lib/features/stats/stats_screen.dart | 876 ++---... 1 file changed, 43 insertions(+), 833 deletions(-)`.

| # | Edit | Test that must fail | Result |
|---|---|---|---|
| M3 | `_averageOf` divides by `kFuelWindowDays` instead of `points.length` | S-1101 | **fails** `+16 -20`, then green — see below |
| M4 | the visibility read uses `kFuelWindowDays` instead of `kFuelVisibilityDays` | S-1107(a) (the plan predicted S-1107(b)) | **fails** `+26 -10`, then green — see below |
| M5 | the `endedAtMs != null` predicate dropped from the training-day test | S-1105 | **fails** `+34 -2`, then green — see below |
| M6 | the zero-session precedence in `stats_screen.dart` reversed (`_totalSessions == 0` → `!= 0`) | S-1110(b) | **fails** `+0 -2`, then green — see §5 |

**M3.** `return total / points.length;` → `return total / kFuelWindowDays;`.
`gateway.sh test test/fuel_row_screen_test.dart --plain-name "S-1101"`:

```
00:00 +0: Fuel row — Mock S-1101 the averages are the mean of the logged days, not of the window
The following TestFailure was thrown running a test:
Expected: a numeric value within <0.001> of <1833.3333333333333>
  Actual: <785.7142857142857>
   Which:  differs by <1047.6190476190477>
```

Full file: `00:02 +16 -20: Some tests failed.` Exit 1. `785.7142857142857` is `5500 / 7` — the window mean,
against the logged-day mean `5500 / 3` — so the mutation is exactly the one the plan names. Inverse applied,
diff back to `128 insertions(+)`, `00:02 +36: All tests passed!`.

**M4.** `computeNutritionTrend(days: kFuelVisibilityDays)` → `days: kFuelWindowDays`.
`gateway.sh test test/fuel_row_screen_test.dart --plain-name "S-1107"`:

```
00:00 +0: Fuel row — Mock S-1107 13 days old renders
00:00 +0 -1: Fuel row — Mock S-1107 13 days old renders [E]
  Expected: not null
    Actual: <null>
  the fixture must produce a Fuel row
  test/fuel_row_screen_test.dart 248:9                main.<fn>.readModel
```

Full file: `00:02 +26 -10: Some tests failed.` Exit 1. **The plan's prediction is wrong about which leg
fails.** It says the mutation makes S-1107(b) fail; (b) is a 14-day-old row, hidden under both constants, so
it passes either way. The 10 failing legs are S-1103(a), S-1103(b), S-1104, **S-1107(a)** — a 13-day-old row
that must still render — and S-1111. The mutation is still caught, and by the assertion that pins the
boundary the constant actually governs; only the scenario id in the Done Criteria is mis-named. Inverse
applied, diff back to `128 insertions(+)`, `00:02 +36: All tests passed!`.

**M5.** `if (s.endedAtMs == null) continue;` deleted.
`gateway.sh test test/fuel_row_screen_test.dart --plain-name "S-1105"`:

```
00:00 +0: Fuel row — Mock S-1105 the split covers every logged day exactly once, and a running session is not a training day
The following TestFailure was thrown running a test:
Expected: <300>
  Actual: <400.0>
```

Full file: `00:02 +34 -2: Some tests failed.` Exit 1 — exactly the two S-1105 legs, no others. The running
session on day 5 moves into the training bucket and pulls the mean from `300` to `400`, which is the split's
double-count the plan warns against. This also proves `_loadHistory()` returns **in-progress** sessions, so
the predicate is load-bearing rather than defensive. Inverse applied, diff back to `128 insertions(+)`,
`00:02 +36: All tests passed!`.

### §3.4 Residue sweep

**Method, and its limitation.** This checkout has **no content-search tool available** to this executor:
`grep`, `sed` and `awk` are permission-denied by the sandbox, and the tool set carries no code-intelligence
or text-search primitive. The plan's Step 0c says to use "the built-in search tool"; that tool is not present
here, so the sweep was done by enumeration instead, in three parts:

1. **The complete changed-file set** — `gateway.sh git-status`, verbatim and unfiltered:

```
## develop...origin/develop [ahead 2]
 M docs/navigation_and_screens.md
 M docs/plans/2026-09-30-04-stats-pr4-index.md
 M docs/stats_screen.md
 M docs/widget_catalog.md
 M lib/core/services/stats_progress_service.dart
 M lib/features/stats/stats_screen.dart
?? docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/
?? lib/core/models/fuel_summary.dart
?? lib/features/nutrition/nutrition_trend_screen.dart
?? lib/features/nutrition/widgets/nutrition_trend_card.dart
?? lib/features/stats/widgets/fuel_section.dart
?? lib/widgets/chart/chart_primitives.dart
?? test/fuel_row_screen_test.dart
?? test/nutrition_trend_screen_test.dart
```

This phase owns `stats_progress_service.dart`, `stats_screen.dart` (both also carry Phase 1's uncommitted
refactor), `fuel_summary.dart`, `fuel_section.dart`, `fuel_row_screen_test.dart`, and the four `docs/` files.
The other entries are Phase 1's: `nutrition_trend_screen.dart`, `nutrition_trend_card.dart`,
`chart_primitives.dart`, `nutrition_trend_screen_test.dart`, and the plan folder itself. The two commits
develop is ahead of `origin` by are earlier PRs, not this phase.

2. **Directory enumeration of every place a second declaration could live.** `lib/core/models/` holds
   exactly one `fuel_summary.dart`; `lib/core/services/` holds exactly one `stats_progress_service.dart`;
   `lib/features/stats/widgets/` holds exactly one `fuel_section.dart`. There is **no barrel file** in
   `lib/core/models/` — the directory's ten files are the whole public surface, so `FuelSummary` can only be
   reached by a direct import. `lib/data/` holds no type registry (`FuelSummary` is derived and never
   persisted, so it needs no Hive adapter — same as its 4b sibling `instrument_list.dart`).

3. **The argument that closes the set.** None of the four names existed before this session, so a reference
   to any of them in another file would be *new content in that file*, which would make that file appear in
   `git-status`. The list above is therefore complete: the reader set is exactly the two `lib/` files that
   read them, plus the test.

**Result.** One declaration each:

| Name | Declared once in | Read by |
|---|---|---|
| `FuelSummary` | `lib/core/models/fuel_summary.dart` | `stats_progress_service.dart` (constructs it), `fuel_section.dart`, `test/fuel_row_screen_test.dart` |
| `computeFuelSummary` | `lib/core/services/stats_progress_service.dart` | `stats_screen.dart`, `test/fuel_row_screen_test.dart` |
| `kFuelWindowDays` | same file | `stats_progress_service.dart` (the window and the previous range), `fuel_section.dart` (the logged-days indicator), `test/fuel_row_screen_test.dart` |
| `kFuelVisibilityDays` | same file | `stats_progress_service.dart` only |

No copy of any of the four outside those files. Because the method is enumeration rather than a search, a
residue in a file that no test compiles would not be caught by it — the reviewer with a search tool should
re-run the sweep to confirm.

### §3.5 Docs

| Doc | What changed |
|---|---|
| `docs/stats_screen.md` | A `### Fuel` subsection after `### Instruments list`: the window and its previous range, logged-days-only averaging with the indicator, the target/previous-range comparison, the training/rest split, the absent-value dash rule, the visibility rule, the placement rationale and the formatting note — each pointing at `test/fuel_row_screen_test.dart` by scenario id. The Fuel section's window is a row in the "What Is (and Isn't) Windowed" table, `kFuelWindowDays` / `kFuelVisibilityDays` are in the Key Constants table, and `fuel_summary.dart` / `fuel_section.dart` / `computeFuelSummary()` are in Core Files. Version 2.6. |
| `docs/widget_catalog.md` | A "Note on the Stats screen's Fuel section" beside the Instruments and nutrition-card notes: `FuelSection` and its path, its inputs, that it reads no repository, and that its behaviour is verified by `test/fuel_row_screen_test.dart`. |
| `docs/navigation_and_screens.md` | The `NutritionTrendScreen` row now names its entry point (the Stats screen's Fuel section, S-1109), and the `StatsScreen` row lists the Fuel section. |
| `docs/state_management/nutrition_state.md` | **Not changed**, as the plan predicted. The row adds no state: it reads `StatsProgressService` and the repository, and D-530 puts the computation in the service. `lib/state/nutrition_state.dart` is absent from `git-status`. |
| `docs/plans/2026-09-30-04-stats-pr4-index.md` | One filename corrected (D-533): `stats_chart_primitives.dart` → `lib/widgets/chart/chart_primitives.dart`. Nothing else in that file was touched. |

No `docs/nutrition.md` — 4c owns it (D-534).

Every behavioural sentence added names its test; `test/docs_indexing_contract_test.dart` is green after the
edits (`00:01 +58: All tests passed!` together with the other two contract suites), so the prose is inside
the size ceiling and free of the flow-walkthrough and roadmap shapes that test rejects.

---

## §4 Open items carried out of the phases

Phase 1 decisions taken under Rule 7, each also in the plan's §Assumption Log:

- **A-1 — the `nutrition → stats` import direction.** `NutritionTrendCard` imports
  `../../stats/widgets/scrollable_trend_chart.dart`, so a `nutrition → stats` import exists until 4c, against
  D-532's one-way intent. `scrollable_trend_chart.dart` is not in the Predicted Files, so moving it would be
  new scope. The reviewer may prefer to move it now; it is a two-line import change plus the file move.
- **A-2 — the card renders the whole `OmniSurface`.** "Body only" was read as "not the header": the two hosts
  differ only in their header, so the surfaces are byte-identical and S-1110(a) compares like with like.
- **A-3 — the screen's subtitle is `'Full history'`.** The plan left the subtitle as `…`.
- **A-4 — the unused `context` parameter was dropped** from `_buildNutritionSection` and `_buildMacrosChart`.
- **A-5 — two pre-existing lint/copy residues were left in place.** `_ChartSeries` (unused, warned) in
  `stats_screen.dart` and the private `_buildSinglePointCard` in `exercise_progress_screen.dart`. Both files
  are outside the Predicted Files; the lint total is unchanged at 199. The third residue named here,
  `_kBottomAxisReservedSize`, was removed in fix round 1 (§5), and D-533 was amended to name the
  single-point card as its exception — see §2.2 and §2.4.

Nothing else was left vetoable: O-3 (the split) and O-11 are the planner's and were already resolved, and
O-10 is Phase 2's product question.

---

## §5 Fix round 1 (review 1)

Bounded by `.work/stats-pr4b3/brief-fix-1.md` to findings F-1…F-11. The review's findings 6, 7, 8 and 11 stay
deferred; they are now listed in the series index under **Carried into 4c**.

| Fix | What changed | Observed check |
|---|---|---|
| **F-1** (blocker, finding 1) | a new `S-1110(b)` group in `test/nutrition_trend_screen_test.dart`: food logged today, every session deleted in `setUp`, `computeFuelSummary()` read in `setUp` and asserted non-null in the body so the fixture cannot pass vacuously | `00:00 +2: All tests passed!` (both harnesses); `+0 -2` under mutation M6 |
| **F-2** (blocker, finding 2) | `docs/stats_screen.md`'s Fuel **Visibility** row now points S-1107 at `test/fuel_row_screen_test.dart` and S-1110(b) at `test/nutrition_trend_screen_test.dart` | `gateway.sh test test/docs_indexing_contract_test.dart` green |
| **F-3** (major, finding 3) | §3.1.1's sentence now says the precedence was **not** asserted when written and names `S-1110(b)` with its run pasted in | the run quoted in §3.1.1 is the run in this table's F-1 row |
| **F-4** (major, finding 4) | the three false soft-window comments deleted (`nutrition_trend_screen.dart` header and its line-44 comment, `nutrition_trend_card.dart`'s class and field docs). Comments only | both files are new in this PR, so the round's edits to them are comments only; full suite green |
| **F-5** (minor, finding 5) | `exercise_progress_screen.dart` imports `lib/widgets/chart/chart_primitives.dart`, reads `kChartBottomAxisReservedSize`, and its private `_kBottomAxisReservedSize` is deleted. `_buildSinglePointCard` untouched. D-533 amended to name the divergent variant | `gateway.sh test test/records_and_trends_screen_test.dart test/stats_progress_test.dart test/screen_overflow_contract_test.dart` → `00:04 +132: All tests passed!` (no `test/exercise_progress_screen_test.dart` exists) |
| **F-9** (nit, finding 9) | **no edit needed** — see below | the assertion the finding asks for is already in the tree |
| **F-10** (nit, finding 10) | §3.3's M4 row cites `S-1107(a)`, with the plan's wrong prediction noted in the same cell | — |
| **F-11** | four one-line bullets under **Carried into 4c** in `docs/plans/2026-09-30-04-stats-pr4-index.md`, covering findings 6, 7, 8 and 11. Nothing else in the index touched | `gateway.sh test test/docs_indexing_contract_test.dart` green |

**F-9 — the finding is inaccurate against the tree.** `test/fuel_row_screen_test.dart`'s S-1112 test already
asserts the absence the finding asks for, beside the chip count:

```dart
expect(
  find.descendant(
    of: _fuelSection,
    matching: find.byKey(const Key('stats_window_chip')),
  ),
  findsNothing,
);
```

`StatsWindowChip` renders its `Text` with exactly that key (`lib/features/stats/widgets/window_chip.dart`), so
the key-based descendant finder *is* the chip-type finder — a sixth chip anywhere on the screen cannot satisfy
it. The assertion predates the review (the file is unmodified by this round). No edit was made, and adding a
second, equivalent assertion would be churn.

**M6 — the mutation proof for F-1.** The mutation is the exact inverse of D-525's precedence, in
`lib/features/stats/stats_screen.dart` (tracked): `children: _totalSessions == 0 ? [empty state] : [...]` →
`_totalSessions != 0 ? [empty state] : [...]`, so a zero-session screen renders the full list and therefore the
Fuel row. Diff stat before, verbatim:

```
lib/features/stats/stats_screen.dart | 876 ++---------------------------------
 1 file changed, 43 insertions(+), 833 deletions(-)
```

`gateway.sh test test/nutrition_trend_screen_test.dart --plain-name "S-1110(b)"`:

```
00:00 +0 -1: Nutrition trend — Mock S-1110(b) the empty state renders and no Fuel row is in the tree
The following TestFailure was thrown running a test:
Expected: exactly one matching candidate
  Actual: _TextWidgetFinder:<Found 0 widgets with text "No sessions yet": []>
   Which: means none were found but one was expected
00:00 +0 -2: Nutrition trend — Hive S-1110(b) the empty state renders and no Fuel row is in the tree [E]
00:00 +0 -2: Some tests failed.
```

(Stack trimmed; the framework reports the failure at `test/nutrition_trend_screen_test.dart` line 271, the
empty-state assertion. The two `[E]` lines are abridged to the final summary.)

Exit 1, both harnesses, at the empty-state assertion. The `fuelSummary` non-null assertion above it **passed**,
which is the useful half: the fixture really does produce a Fuel row, so the failure is the screen's
precedence and not an empty fixture. Inverse applied, `gateway.sh git-diff --stat -- lib/features/stats/stats_screen.dart`
back to `43 insertions(+), 833 deletions(-)`, and the same command green: `00:00 +2: All tests passed!`.

**Suites after the round.**

| Command | Exit | Final line (verbatim) |
|---|---|---|
| `gateway.sh test test/nutrition_trend_screen_test.dart test/fuel_row_screen_test.dart test/docs_indexing_contract_test.dart` | 0 | `00:02 +57: All tests passed!` |
| `gateway.sh test test/records_and_trends_screen_test.dart test/stats_progress_test.dart test/screen_overflow_contract_test.dart` | 0 | `00:04 +132: All tests passed!` |
| `gateway.sh test test/docs_indexing_contract_test.dart test/navigation_contract_enforcement_test.dart test/nutrition_trend_screen_test.dart test/fuel_row_screen_test.dart` (re-run after the last doc edits) | 0 | `00:02 +58: All tests passed!` |
| `gateway.sh test` (last run of the round, after every edit) | 0 | `01:19 +3256 ~1: All tests passed!` |
| `gateway.sh lint` | 1 | `199 issues found. (ran in 2.9s)` |

`+3256 ~1` against §3.2's `+3254 ~1` is the new scenario's two harness legs, no regression, and the skipped
test is unchanged. `199 issues found.` is identical to §3.2, so the round added no issue of any severity; the
full suite compiling and passing is what rules out an `error` having replaced a lesser issue.

**Files changed in the round** (beyond the phase's own): `lib/features/nutrition/nutrition_trend_screen.dart`,
`lib/features/nutrition/widgets/nutrition_trend_card.dart` (comments only),
`lib/features/stats/exercise_progress_screen.dart` (the shared constant — the one `lib/` file outside the
Predicted Files this PR now edits, required by F-5), `test/nutrition_trend_screen_test.dart`,
`test/fuel_row_screen_test.dart` (unmodified), `docs/stats_screen.md`, `docs/plans/2026-09-30-04-stats-pr4-index.md`,
this plan and this file.
