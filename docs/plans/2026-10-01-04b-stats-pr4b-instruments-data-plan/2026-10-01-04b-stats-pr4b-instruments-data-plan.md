# Stats PR 4b — the Instruments data

> **Status:** READY — defaults applied; §Open questions lists every product choice the planner had to
> make, with the default this plan runs on.
> **Next handoff:** `@dba` — Phase 1 (the bulk sensor-summary read); then `@developer` — Phase 2 (the
> Instruments computation).
> **Series:** Stats PR 4 → `docs/plans/2026-09-30-04-stats-pr4-index.md`.
> **Provenance:** this plan, `docs/plans/2026-10-01-04b2-stats-pr4b2-instruments-list-plan/…` (the list on the Stats screen) and `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/…` (the Fuel row, NOT READY) replace the superseded single 4b plan, which measured 1,016 lines against the 800-line hard limit in `.github/agents/pr_scope_budget.md` §1. Decisions and scenarios keep their original ids (D-5xx, S-10xx); nothing here is renumbered.
> **Base:** `develop`. All work happens in place on `develop`. Executors never branch, stage, commit,
> merge or push (`docs/global_conventions.md`; index §Branch policy).
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` §"5. Instruments
> Layer: Native Metric per Effort Kind, Plus a Fuel Row" (the prompt block, its 11 Acceptance Criteria and
> its 7 Unit-Tests-Required bullets).
> **Evidence:** `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.evidence.md`
> — executors write baselines, suite output, mutation proofs and surface bumps there. **Never in this
> file.**
> **Binding conventions:** `docs/global_conventions.md`; `docs/design_system.md` (card-header typography,
> tokens, animation rules); `docs/navigation_contract.md` (`OmniNavigator` only); `docs/data_models.md`,
> `docs/db_integration.md` (the schema contract). Read them; they are not restated here.

---

## Scope check

Measured against `.github/agents/pr_scope_budget.md` (hard: >800 plan lines, >5 phases, >1,500 predicted
production lines; soft: >500 plan lines, >3 phases, >1 track, >20 decisions, >30 scenarios; **two or more
soft signals ⇒ split**).

| Signal | PR 4b as planned | Limit |
|---|---|---|
| Phases | 2 | >3 is soft |
| Tracks | 1 (the phone) | >1 is soft |
| Decisions defined here | 12 (D-501…D-516, minus the four in 4b2) | >20 is soft |
| Scenarios | 11 (S-1002…S-1010, S-1013, S-1018) | >30 is soft |
| Predicted production lines | ~370 (excluding tests and docs) | >1,500 hard |
| Plan length | this file, 598 lines (measured by reading it back) | >500 soft |

**One soft signal (plan length, 598 against the 500 soft limit). No hard limit. Within budget.**

Under `pr_scope_budget.md` §1 one soft signal is a flag, not a split: two or more are required. This plan is
two phases, one track, one surface, and its length is documentation of the data contracts 4b2 consumes — the
executable content is two phases.

**The split, and why (D-501).** The superseded file planned item 5 as one PR: 3 phases, ~700 predicted production lines, and 1,016 plan lines against an 800-line hard limit. Its two halves share nothing but the screen — the Instruments list reads `SensorSummary` through a new repository read and the exercise-metric layer; the Fuel row reads `ConsumedFood`, `NutritionTarget` and session completion. So item 5 ships as three plans, in this order:

| Plan | Scope | Depends on |
|---|---|---|
| **4b — this file** | The Instruments **data**: the bulk sensor-summary read on the repository, the two value types, `computeInstrumentSections`, the shared formatters. **No visible change on screen.** | 4a |
| **4b2** | The Instruments **list** on the Stats screen: the four widgets, the cap and `Show all`, the legacy wrapper key, the legacy test re-stabilisation. | 4b |
| **4b3** | The **Fuel row**. NOT READY: its decisions (D-520…D-527) and scenarios (S-1101…S-1110) are recorded; its phases are written when its turn comes. | 4b (shares the screen edit) |

4c (the removal of the five legacy sections) is unchanged and follows all three.

---

## What this PR does

Nothing changes on screen. This PR makes the data the Instruments list needs available and correct:

- one new repository read, `getSensorSummariesBySession()`, on the `WorkoutRepository` interface with a
  Hive implementation and a Mock twin — the first bulk read of `SensorSummary` in `lib/` (nothing reads
  `SensorSummary` today, and there is no bulk read);
- two value types in a new `lib/core/models/instrument_list.dart` — `InstrumentRow` and
  `InstrumentSectionData`;
- `StatsProgressService.computeInstrumentSections({required StatsWindow window})`: the window's sections
  ordered by distinct training days, each section's rows ordered by training days then name then id, each
  row's native value, its previous-range value for the change indicator, its cadence and its average heart
  rate;
- two shared formatters in `lib/features/stats/widgets/native_value_format.dart`:
  `nativeSecondaryLabel` (moved out of `ExerciseProgressScreen` with byte-identical output) and
  `formatNativeChange` (the change chip's text);
- their tests and the docs they invalidate.

**Why the data comes first.** The list cannot render a cadence or a heart rate until every summary is readable in one pass, and the ordering rules are pure service logic that a widget is a shell over. Phase 1 is independently shippable and green on its own (a repository read with no reader yet); Phase 2 leaves `computeInstrumentSections` tested and unused by any widget. Stopping after either phase leaves `develop` shippable with no half-applied user-visible change.

---

## Decision Ledger — PR 4b

Numbered D-5xx. Immutable once written: a change is a new superseding entry, never an edit.

| # | Decision (enforceable contract) |
|---|---|
| **D-501** | **The split.** The pack's item 5 ships as 4b (the Instruments data, this plan), then 4b2 (the Instruments list on the Stats screen), then 4b3 (the Fuel row). 4b, 4b2 and 4b3 all add; only 4c removes. The three-way form supersedes the two-way 4b/4b2 statement in the superseded single 4b plan: the single plan measured 1,016 lines against the 800-line hard limit, and its data half is separately shippable. |
| **D-502** | **4a is inherited unchanged.** 4a's D-401…D-416 stand. 4b changes no 4a behaviour and no 4a test expectation; the one exception is D-516, which moves a private label helper to a shared one **preserving its output string for every input**. |
| **D-504** | **Section ordering (supersedes D-403 for this list only).** A section's rank is the number of **distinct training days in the window on which an effort of that kind was logged** — the day key is the local-midnight day of the session's `startedAtMs`, the kind is `_sectionForKind(effort.effortKind)`, an effort with `exerciseId == null` is skipped, and only sessions with `endedAtMs != null` count. Sections sort by that count **descending**, ties broken by `ExerciseSection.values` order (resistance → cardio → isometric → sports). *Records & Trends keeps D-403's fixed order; the Instruments list is a "where did my training go" list, so it leads with the biggest block.* |
| **D-505** | **Section presence and row presence.** A section renders **iff it has ≥1 row**. A row exists for every exercise the window yields, including one whose `NativeValue` is the zero fallback (`_zeroValueFor`) because nothing was readable — that row shows the zero figure and **no sparkline** (it has no points). No exercise that was trained in the window is silently dropped. |
| **D-506** | **Row ordering.** Within a section, rows sort by `summary.points.length` **descending**, then `summary.name` ascending (ordinal, `compareTo`), then `summary.exerciseId` ascending. The point count is the window's training-day count for that exercise, so "most frequently trained first" is the count of days trained, not of sessions. |
| **D-508** | **The change indicator.** A row's indicator compares the exercise's own native value in the window against the same exercise's native value over **the immediately preceding range of the same calendar length**, both computed by `StatsProgressService.computeExerciseMetrics`. There is **no indicator** (the chip renders `'—'`) when (a) the exercise has no summary in the previous range, or (b) the previous range's `NativeMetric` differs from the window's (an exercise that was timed in one range and held in the other is not comparable). Otherwise the delta is `windowValue − previousValue`, and the chip renders arrow `↑` when the delta is `> 0`, `↓` when `< 0`, and `'—'` when `== 0`. Colour and typography are exactly `_buildGroupComparisonChip`'s (`lib/features/session/session_summary_screen.dart`): `primary` for `> 0`, `theme.colorScheme.error.withOpacity(0.8)` for `< 0`, `textMuted` for `'—'`; `labelSmall` + `FontWeight.w600`; right-aligned in a fixed `width: 92`. The sign is the **raw numeric sign** — no per-metric exception, so a slower pace (a larger seconds-per-km) reads `↑`. The chip widget itself is 4b2's; this plan computes the delta and owns `formatNativeChange`. |
| **D-509** | **The previous range is calendar arithmetic, never a duration.** With `dayCount = <the window's own day count>` (derived from the window's local-midnight bounds, `fromMs`→`toMs` inclusive), `prevToMs = window.fromMs.millisecondsSinceEpoch - 1` and `prevFromMs = DateTime(fromYear, fromMonth, fromDay - dayCount).millisecondsSinceEpoch`, where `fromYear/Month/Day` come from `DateTime.fromMillisecondsSinceEpoch(window.fromMs.millisecondsSinceEpoch)`. `DateTime(y, m, d − n)` — **never** `subtract(Duration(days: n))` — so a DST transition inside the range cannot shorten or widen it. |
| **D-511** | **Cadence — Cardio rows only.** Sum `steps` over the exercise's `timed_instance` `SensorSummary` rows in the window that carry a non-null `steps`, divided by (the sum of `actualDurationSecs` over **exactly those same instances** ÷ 60), rounded to the nearest whole number, rendered `'<n> steps/min'`. Not rendered when no such summary exists (never `'0 steps/min'`). |
| **D-512** | **Average heart rate — Cardio and Sports rows.** The mean of `avgHeartRateBpm` over the exercise's `timed_instance` summaries (Cardio) or `round_instance` summaries (Sports) in the window that carry a non-null value, rounded to the nearest whole number, rendered `'<n> bpm'`. Not rendered when no such summary exists (never `'0 bpm'`). Resistance and Isometric rows never show a heart rate. |
| **D-513** | **The bulk sensor read.** `Future<Map<String, List<SensorSummary>>> getSensorSummariesBySession()` is added to `WorkoutRepository` and implemented by both `HiveWorkoutRepository` and `MockWorkoutRepository`: every sensor summary on the device, keyed by `sessionId`, each group ordered **exactly** as `getSensorSummariesForSession` orders its list (scope per `SensorSummary.scopes`, then `windowStartMs`, then `targetId`); a session with no summaries has **no key**. Mock mirrors Hive value-for-value. No model changes, so `scripts/sqlite_schema.sql`, `scripts/sqlite_seed.sql` and `test/db_seed_test.dart` are untouched. |
| **D-514** | **Where the computation lives.** `StatsProgressService.computeInstrumentSections({required StatsWindow window})` returns the ordered sections and rows; the value types live in a new `lib/core/models/instrument_list.dart` (`InstrumentSectionData`, `InstrumentRow`) and 4a's `lib/core/models/exercise_metric.dart` is untouched. The service calls `computeExerciseMetrics` twice (window, previous range) plus one private pass for the section day counts. The screen calls it **once** in `_loadData()` and stores the result in a field; `build` does no computation. Nothing new is persisted. (The screen call is 4b2's edit; the signature is pinned here.) |
| **D-516** | **One label source, and one chip source.** (a) `ExerciseProgressScreen._secondaryLabel(NativeMetric?)` is promoted to `String? nativeSecondaryLabel(NativeMetric? metric)` in `lib/features/stats/widgets/native_value_format.dart`, with **the same output for every input** (`duration` → `'Total hold'`, `roundMinutes` → `'Total time'`, everything else `null`), and `ExerciseProgressScreen` calls it — so a secondary figure never reads two ways. (b) `StatsScreen._buildWindowChip` is extracted to `StatsWindowChip` in `lib/features/stats/widgets/window_chip.dart` with the identical key (`Key('stats_window_chip')`) and the identical text (`'· ${window.label}'`, `labelSmall` + `textMuted` + italic, `maxLines: 1`, ellipsis); the four legacy headers and the first Instruments section header use it. **Part (a) is implemented in this plan; part (b) is 4b2's.** |

**Decisions that belong to the sibling plans and are not restated here:** D-503 (the additive boundary and
the `stats_legacy_sections` wrapper key), D-507 (the cap and `Show all (n)`), D-510 (the sparkline) and
D-515 (the row's destination) are defined in 4b2's plan; D-520…D-527 (the Fuel row) are defined in 4b3's
plan.

**Ledger entries carried forward from 4a that bind this PR:** D-403 (superseded for this list by D-504),
D-405…D-408 (the native values the rows show), D-409 (nothing here creates a PR event), D-413
(`OmniNavigator`), D-416 (doc reconciliation).

---

## Feature invariants that bite in this PR

Project-wide rules live in `docs/global_conventions.md`; these are the ones this PR can break.

1. **Repository parity.** `MockWorkoutRepository` must mirror `HiveWorkoutRepository` value-for-value for
   `getSensorSummariesBySession` — same keys, same order inside each key. Proven by S-1004.
2. **The repository boundary.** No state, service or feature may touch a concrete store. The new read is
   declared on `WorkoutRepository` and consumed only through the interface.
3. **History is never rewritten.** The Instruments data reads; it writes nothing, migrates nothing and
   stamps nothing. `computeExerciseMetrics` filters by `startedAtMs` and never mutates a session.
4. **Nothing new is persisted.** No model field, no box, no schema change: `scripts/sqlite_schema.sql`,
   `scripts/sqlite_seed.sql` and `test/db_seed_test.dart` must pass **unmodified**.
5. **One number, one rendering.** Every figure this plan produces is formatted by
   `lib/features/stats/widgets/native_value_format.dart`; no service formats a number itself.

---

## Requirements

R-2 (pack AC-2…AC-4) A section is decided by the **logged effort kind**, never the session's modality tile.
R-3 (AC-5) A section is present only when the window contains work of that kind; ordering is D-504.
R-5 (AC-1, AC-7) Each row carries the exercise's native value and, when comparable, its change against the
exercise's own previous comparable value (D-508) — the value half of the row.
R-6 (AC-1) Cardio rows carry cadence when steps exist and average heart rate when available; Sports rows
carry average heart rate when available (D-511, D-512) — the computation half.
R-9 (pack Unit Tests) The top-N selection tests in `test/stats_progress_test.dart` are **not** updated in
this PR — see §Open Items O-1.
R-10 (pack Unit Tests) The weighted/bodyweight classification tests must pass unmodified.

The screen-side requirements (R-1, R-4, R-7, R-8) are 4b2's.

---

## Acceptance Criteria → scenarios

| AC | Statement | Scenario(s) | PR |
|---|---|---|---|
| AC-1 | squats + treadmill run + plank + BJJ → four sections with e1RM, estimated pace, cadence, longest hold, rounds and round-minutes | S-1007, S-1008 (the figures); S-1001 is the screen half, in 4b2 | 4b, 4b2 |
| AC-2 | a `set` effort in a Free Training session appears under Resistance | S-1006 | 4b |
| AC-3 | a Plank logged `timed` appears under Cardio with its duration; logged as a `hold` under Isometric | S-1006 | 4b |
| AC-4 | a timed effort inside a lifting session appears under Cardio; an Interval Run in a Sports session under Sports | S-1006 | 4b |
| AC-5 | a user who only lifts sees only Resistance | S-1013, S-1005 | 4b |
| AC-7 | the change indicator compares against the exercise's own previous comparable value; a first-ever appearance shows none | S-1009 | 4b |
| AC-12 | exercises outside the old top-N now appear as rows | S-1010 | 4b |
| AC-6, AC-8, AC-11 | the cap and `Show all`; the row tap; the old sections still appear | S-1016, S-1014, S-1015 | 4b2 |
| AC-9, AC-10 | the Fuel row's averages and target comparisons | S-1101…S-1104 | 4b3 |

---

## Scenarios — PR 4b (S-1002…S-1010, S-1013, S-1018)

Stable ids; never reused. Fixtures are stated as populations because an unstated population becomes a bug.
S-1001, S-1011, S-1012, S-1014, S-1015, S-1016 and S-1017 are 4b2's — they need the rendered screen, which
this PR does not change — and S-1101…S-1110 are 4b3's.

### S-1002: the bulk read groups by session and orders like the single-session read
- **Fixture:** session `s-x` holding summaries deliberately written out of display order — `('timed_instance','t2', windowStart 2000)`, `('timed_instance','t1', windowStart 1000)`, `('session','', windowStart 500)`, `('effort','e1', windowStart 1000)` — and session `s-y` holding none, plus a second session `s-z` holding one `round_instance` summary.
- **Trigger:** `await repo.getSensorSummariesBySession()`.
- **Flow:** none.
- **Expected outcome:** keys are exactly `{s-x, s-z}` (`s-y` absent); `s-x`'s list is in the order `session|`, `effort|e1`, `timed_instance|t1`, `timed_instance|t2` — the same order `getSensorSummariesForSession('s-x')` returns.
- **Edge case of:** none.

### S-1003: no summaries at all
- **Fixture:** a repository with sessions and exercises but zero sensor summaries.
- **Trigger:** `getSensorSummariesBySession()`.
- **Flow:** none.
- **Expected outcome:** an empty map (not null, no key with an empty list).
- **Edge case of:** S-1002.

### S-1004: Hive and Mock agree value-for-value
- **Fixture:** S-1002's population seeded identically in both harness stores.
- **Trigger:** `getSensorSummariesBySession()` on each.
- **Flow:** compare.
- **Expected outcome:** identical key sets and identical `(scope, targetId)` order inside every key.
- **Edge case of:** S-1002.

### S-1005: sections are ordered by training days in the window
- **Fixture:** (a) cardio on 3 distinct days (`timed` efforts on `ex-run`), resistance on 1 day (`set` on `ex-squat`); (b) the same fixture with the resistance session moved 30 days back (outside the window).
- **Trigger:** `computeInstrumentSections(window:)` for the 14-day window.
- **Flow:** none.
- **Expected outcome:** (a) `[cardio, resistance]` — cardio first despite `ExerciseSection`'s declaration order; (b) `[cardio]` only, with no empty Resistance section.
- **Edge case of:** none.

### S-1006: the section comes from the effort kind, not the session's modality
- **Fixture:** one window containing (a) a session with `modality: null` (Free Training) holding a `set` effort; (b) a `resistance_lifting` session holding a `timed` effort (a routine's treadmill warm-up); (c) a `timed` effort on an exercise named `'Plank'`; (d) a `drill` effort on the same exercise `'Plank'`; (e) a `round` effort inside a `sports` session.
- **Trigger:** `computeInstrumentSections(window:)`.
- **Flow:** none.
- **Expected outcome:** (a) → resistance; (b) → cardio; (c) → cardio with a duration figure; (d) → isometric with a hold figure — the **same exercise id appears in two sections**, each with its own value; (e) → sports. No section is chosen by `TrainingSession.modality` anywhere.
- **Edge case of:** none.

### S-1007: the native value per row is exactly 4a's, formatted by 4a's formatter
- **Fixture:** a weighted resistance exercise (5 reps × 100 kg), a bodyweight resistance exercise with an added weight, a cardio exercise with a distance, a cardio exercise with no distance, an isometric `hold`, an isometric `timed` effort, a sports `round` effort — all in the window.
- **Trigger:** `computeInstrumentSections(window:)`, then `formatNativeValue(row.summary.best, settings)` for each row.
- **Flow:** none.
- **Expected outcome:** every row's primary text equals `formatNativeValue` of the value `computeExerciseMetrics` reports for the same exercise and window; the bodyweight row's figure carries `'(+<weight>)'`; the added-weight-only figure never becomes a separate line; the isometric row's secondary line is `'Total hold <clock>'`; the sports row's is `'Total time <min> min'`.
- **Edge case of:** S-1001.

### S-1008: cadence and average heart rate
- **Fixture:** (a) a cardio exercise with two finished timed instances, 300 s and 600 s actual, whose `timed_instance` summaries carry `steps` 600 and 1200 and `avgHeartRateBpm` 140 and 150; (b) the same exercise with **no** summaries; (c) a sports exercise with two `round_instance` summaries carrying `avgHeartRateBpm` 146 and 150; (d) an isometric and a resistance exercise with summaries present.
- **Trigger:** `computeInstrumentSections(window:)`.
- **Flow:** none.
- **Expected outcome:** (a) cadence `'120 steps/min'` (1800 steps ÷ (900 s ÷ 60)) and `'145 bpm'`; (b) neither text present, and `'0 steps/min'` / `'0 bpm'` present nowhere; (c) `'148 bpm'` and no cadence; (d) neither figure on the isometric or resistance row even though summaries exist.
- **Edge case of:** S-1001.

### S-1009: the change indicator, and when it must not appear
- **Fixture:** a 7-day window (days 1–7 back) and its previous range (days 8–14 back): (a) `ex-a` trained in both with a higher window value; (b) `ex-b` trained in both with a lower window value; (c) `ex-c` trained only in the window; (d) `ex-d` trained in the window as a `drill` (hold) and in the previous range as a `timed` effort (duration) — same exercise, different `NativeMetric`; (e) `ex-e` trained in both with the same value; (f) `ex-f` trained in the previous range only.
- **Trigger:** `computeInstrumentSections(window:)`.
- **Flow:** none.
- **Expected outcome:** (a) delta `> 0`; (b) delta `< 0`; (c) no previous summary ⇒ no indicator; (d) metric mismatch ⇒ no indicator; (e) delta `== 0` ⇒ no indicator; (f) not a row at all. Separately: given `window.fromMs == DateTime(2026, 3, 8)` (local) and a 7-day window, the previous range is `prevToMs == window.fromMs.millisecondsSinceEpoch - 1` and `prevFromMs == DateTime(2026, 3, 1).millisecondsSinceEpoch` — D-509's calendar arithmetic, asserted directly rather than through a rendered string. The chip that renders the resulting `'—'`/arrow is 4b2's (`test/instrument_change_format_test.dart` proves the text this plan produces).
- **Edge case of:** S-1001.

### S-1010: row ordering, duplicate names and a zero-valued row
- **Fixture:** one section (resistance) with six exercises: `ex-3` trained on 3 days, `ex-2` on 2 days, `ex-1` on 1 day, `ex-0` trained in the window with **no readable value** (a `set` effort with no observation rows), and `ex-dup-a` / `ex-dup-b` both named `'Custom Press'`, each trained on 2 days.
- **Trigger:** `computeInstrumentSections(window:)`.
- **Flow:** none.
- **Expected outcome:** the row order is `ex-3`, then `ex-dup-a`, `ex-dup-b`, `ex-2` (the three 2-day rows by name then id), then `ex-1`, then `ex-0` last; the six rows are all present — the zero-valued row is not dropped (D-505) and has no points.
- **Edge case of:** S-1001.

### S-1013: a lifter-only user
- **Fixture:** resistance work only, on two days.
- **Trigger:** `computeInstrumentSections(window:)`.
- **Flow:** none.
- **Expected outcome:** one section (`resistance`) with the right rows; no `cardio`, `isometric` or `sports` section in the returned list. (The rendered half is 4b2's, S-1013's screen assertions there.)
- **Edge case of:** S-1005.

### S-1018: an exercise with a single session
- **Fixture:** one exercise, one session in the window, one finished instance, no previous-range history.
- **Trigger:** `computeInstrumentSections(window:)`.
- **Flow:** none.
- **Expected outcome:** one row, one point, a real native value, no previous value (so the chip will read `'—'` in 4b2), and `sessionCount == 1` — nothing is treated as missing or as an error.
- **Edge case of:** S-1009.

---

## Iteration 1

### Executor block (read before Phase 1)

**Step 0a — read these first.** `docs/global_conventions.md`; `docs/design_system.md` (§card-header
typography, tokens, animation rules); `docs/navigation_contract.md`; this file's §Decision Ledger,
§Feature invariants, §Scenarios and the phase you are implementing. Docs are claims, not truth: if
`lib/` disagrees with a doc, `lib/` wins and you note the disagreement in the evidence file.

**Step 0b — baseline before you touch anything.** Run `gateway.sh lint` and `gateway.sh test` and copy the
**verbatim** summary lines into the evidence file (§1). The tree this PR starts from is expected to read
`199 issues found.` with 0 errors, and `+3153 ~1: All tests passed!`. If the numbers differ, record what
you actually saw and say so — a different baseline is information, not a failure.

**Step 0c — the shell.** Only `.github/copilot/scripts/macos/gateway.sh` may be executed:
`gateway.sh list`, `lint`, `test`, `build`, `codegen`, `pub-get`, `format <paths>`, `git-status`,
`git-diff [<ref>] [--stat|--name-only|--name-status|--cached] [-- <path>...]`, `git-log [<count>] [<ref>]`,
`git-show <ref> [--stat]`. There is **no** `grep`, `cp`, `sed`, `mv`, `rm`, `/tmp` or plain `git` for you.
Use the built-in search tool for source sweeps, `view` for reads, and `gateway.sh git-diff --stat -- <path>`
for footprints. A command that fails twice the same way: stop and report.

**The nine rules.**

1. **Stay in the phase's Predicted Files.** A file not listed is out of bounds; a listed file you did not
   need to touch is a finding for the reviewer, not a silent omission. Record both in the evidence file.
2. **Red first.** Write the phase's tests before its production code, run them, and paste the failing
   output in the evidence file. A test that passes before the change proves nothing.
3. **Mutation proof.** Every phase with a rule to protect ends with the inverse-edit mutations listed in
   its Done Criteria: note the file's `git-diff`, make the listed edit with the edit tool, show the named
   test **failing**, apply the exact inverse, confirm the diff is back, run again, show it passing. Record
   the exact output. Mutations target **tracked** files — an edit to an untracked new file does not appear
   in `gateway.sh git-diff`, so use the file the phase names.
4. **Green means the suites ran.** `flutter analyze` passing is not a test run. Run `gateway.sh test`, read
   the pass/fail counts, paste them. A hang, a timeout or a killed run is a failure — say so.
5. **The analyzer bar is "none new".** 0 errors and no more than the baseline issue count. Every file the
   phase touches has 0 issues of its own.
6. **Docs trail code by zero phases.** Each phase updates the docs it invalidated, in that phase, and its
   Done Criteria include the claim-to-test row from §Doc-claim → test table.
7. **Ambiguity never stops you.** Pick the option most consistent with the Ledger and the invariants, then
   log it in §Assumption Log of this file as `A-n: decision — options considered — why`. The planner
   ratifies or reverts it.
8. **No new dependency, no new asset, no schema change, no migration, no feature flag.**
9. **Never branch, stage, commit, merge or push.** Work in place on `develop`.

**Doc checklist for this PR** (each item names the phase that owns it):
- [x] `docs/db_integration.md` — the new repository read (Phase 1)
- [x] `docs/state_management/services_and_utils.md` — `computeInstrumentSections` (Phase 2)
- [x] `docs/data_models.md` — `InstrumentSectionData`, `InstrumentRow` (Phase 2)
- [x] No file in `docs/` exceeds 64 KiB (`test/docs_indexing_contract_test.dart`; `docs/plans/` is exempt)
- [x] Every claim added above has a named test in §Doc-claim → test table

---

### Phase 1: The bulk sensor-summary read (@dba)

**Why first:** the rows cannot show cadence or heart rate until every summary is readable in one pass, and
this is the only repository change in the PR.

1. [x] In `test/helpers/repository_harness.dart`, add two helpers beside the existing seed helpers (which
       already provide `seedSession({sessionId, modality, isRolling, daysAgo})`, `seedExercise`,
       `seedWeightedSets`, `seedBodyweightSets`, `seedSetEffort`, `seedHoldEffort`, `seedRoundEffort`,
       `seedTimedEntries`, and the shared `fixtureStart`):
       - `SensorSummary sensorSummary({required String sessionId, required String scope, required String targetId, required int windowStartMs, required int windowEndMs, double? avgHeartRateBpm, double? maxHeartRateBpm, int? steps})`
         — `source: SensorSummary.sourceWatch`, `createdAtMs: fixtureStart`. Name the scope constants via
         `SensorSummary.scopeSession` / `scopeEffort` / `scopeTimedInstance` / `scopeRoundInstance`, never a
         bare string literal.
       - `Future<void> seedSensorSummary(WorkoutRepository repo, SensorSummary summary)` — a thin
         `repo.createSensorSummary(summary)`.
2. [x] Create `test/sensor_summaries_by_session_test.dart`. Structure it like
       `test/records_and_trends_screen_test.dart`: `for (final factory in harnessFactories) { final harness
       = factory(); group('Sensor summaries by session — ${harness.name}', …) }` with `setUp`/`tearDown`
       opening and closing the harness. Add S-1002, S-1003 and S-1004 as plain `test()`s.
3. [x] **Red run:** `gateway.sh test test/sensor_summaries_by_session_test.dart` — the file must fail to
       compile because `getSensorSummariesBySession` does not exist. Paste that error.
4. [x] In `lib/data/repositories/workout_repository.dart`, declare
       `Future<Map<String, List<SensorSummary>>> getSensorSummariesBySession();` beside
       `getSensorSummariesForSession`, with a doc comment stating: every sensor summary on the device,
       grouped by `sessionId`; each group in the same order `getSensorSummariesForSession` returns (scope
       per `SensorSummary.scopes`, then `windowStartMs`, then `targetId`); a session with no summaries has
       no key.
5. [x] Implement it in `lib/data/repositories/hive_workout_repository.dart` beside
       `getSensorSummariesForSession`: walk the sensor-summary box, decode with the same
       `SensorSummary.fromMap` path the single-session read uses, group by `sessionId`, and sort each
       group with a private static comparator that is **the same code** the single-session read sorts with
       (extract that comparator from `getSensorSummariesForSession` and call it from both, so the two
       orders cannot drift).
6. [x] Implement the Mock twin in `lib/data/repositories/mock_workout_repository.dart` the same way, over
       its own in-memory store, with the same extraction so both implementations share one comparator
       shape. Mock output must equal Hive's value-for-value (S-1004).
7. [x] **Green run:** the new file plus `test/watch_capture_repository_parity_test.dart` and
       `test/db_seed_test.dart`.
8. [x] Update `docs/db_integration.md`: add `getSensorSummariesBySession()` to the repository-read list
       beside `getRoundInstancesByEffort()`, one line naming its grouping/order rule and
       `test/sensor_summaries_by_session_test.dart` as its proof. State explicitly that no model, schema or
       seed file changed.

**Done Criteria** (run until green):
- `gateway.sh test test/sensor_summaries_by_session_test.dart` → all pass, 0 failures (paste the counts).
- `gateway.sh test test/watch_capture_repository_parity_test.dart test/db_seed_test.dart` → all pass.
- `gateway.sh test` → the whole suite passes, with the counts pasted (`+<n> ~<n>: All tests passed!`).
- `gateway.sh lint` → 0 errors, issue count ≤ the baseline from Step 0b.
- Search `lib/` for `getSensorSummariesBySession` → exactly 3 matches: the interface and the two
  implementations. Any other match means a caller bypassed the interface.
- Search `lib/data/repositories/` for `UnimplementedError` and `TODO` → no new hit.
- `gateway.sh git-diff --stat -- lib/data test/helpers test/sensor_summaries_by_session_test.dart docs/db_integration.md`
  → matches the Predicted Files exactly.
- **Mutation M0:** delete the grouping (return a single key of `''` holding every summary), run
  `test/sensor_summaries_by_session_test.dart`, show S-1002 failing, restore, show it passing.

**Predicted Files:** `lib/data/repositories/workout_repository.dart`,
`lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`,
`test/helpers/repository_harness.dart`, `test/sensor_summaries_by_session_test.dart`,
`docs/db_integration.md`.

---

### Phase 2: The Instruments computation (@developer)

**Why second:** the ordering rules, the change indicator and the sensor figures are pure service logic; the
widgets are a shell over them. Depends on Phase 1 (the sensor map).

1. [x] Create `lib/core/models/instrument_list.dart` (no Flutter imports, nothing persisted):
       - `class InstrumentRow { final ExerciseMetricSummary summary; final NativeValue? previousValue; final int? cadenceStepsPerMin; final int? averageHeartRateBpm; }`
         — `summary.best` is the value the row shows, `summary.points` is the sparkline, `previousValue`
         is the previous range's value for the same exercise (D-508) or null.
       - `class InstrumentSectionData { final ExerciseSection section; final List<InstrumentRow> rows; final int trainingDayCount; }`
         — `trainingDayCount` is D-504's rank, kept on the value so a test can assert the ordering key.
2. [x] Create `test/instrument_list_service_test.dart`, structured like
       `test/records_and_trends_screen_test.dart` (harness factories, `setUp`/`tearDown`, `seedSession`'s
       `daysAgo` for window/previous-range placement). Cover S-1005, S-1006, S-1007, S-1008, S-1009,
       S-1010, S-1013, S-1018. Use `DateTime.now()`-relative fixtures via `seedSession(daysAgo:)`, and one
       fixed-date fixture for S-1009's calendar assertion.
3. [x] Create `test/instrument_change_format_test.dart`: plain `test()`s for `formatNativeChange`'s three
       branches (positive, negative, zero) and for one metric of each formatting family (weight, reps,
       clock, rounds, minutes, pace), constructing `SettingsState(repo, fakePreferencesService())` the way
       the existing tests do. This is `formatNativeChange`'s proof while the chip that uses it lands in
       4b2.
4. [x] **Red run:** paste the compile failure for both new test files. — Written before the implementation by the interrupted run; its output was not captured. Red-ness is re-established by the M1–M3 mutation proofs (evidence §4 Phase 2).
5. [x] In `lib/core/services/stats_progress_service.dart`, extend `_HistoryIndex._loadHistory()` with a
       7th bulk read: `final sensorSummariesBySession = await _repository.getSensorSummariesBySession();`
       (mirror the existing six reads' style), and build a flattened
       `final Map<String, SensorSummary> sensorByTarget` keyed `'$scope|$targetId'` (a summary's
       `targetId` is unique within its scope), plus
       `SensorSummary? sensorFor(String scope, String targetId) => sensorByTarget['$scope|$targetId'];`.
6. [x] Add `Future<List<InstrumentSectionData>> computeInstrumentSections({required StatsWindow window})`:
       - `current = await computeExerciseMetrics(fromMs: window.fromMs.millisecondsSinceEpoch, toMs: window.toMs.millisecondsSinceEpoch)`.
       - the previous range from D-509 (`prevFromMs`, `prevToMs`), and
         `previous = await computeExerciseMetrics(fromMs: prevFromMs, toMs: prevToMs)`.
       - a private walk over the window's completed sessions' efforts for D-504's per-section distinct
         training-day count (reuse `_sectionForKind`, which is private but callable from a sibling method
         in the same class; skip efforts with a null `exerciseId`).
       - group `current` by `summary.section`; order the sections by D-504; order each section's rows by
         D-506; attach `previousValue` by matching `exerciseId` in `previous` and comparing
         `NativeValue.metric` (D-508).
       - attach cadence (D-511) and average heart rate (D-512) from `sensorFor` and the exercise's own
         timed/round instances in the window.
7. [x] Add `String? nativeSecondaryLabel(NativeMetric? metric)` to
       `lib/features/stats/widgets/native_value_format.dart` with 4a's exact mapping (`duration` →
       `'Total hold'`, `roundMinutes` → `'Total time'`, otherwise null), and delete
       `ExerciseProgressScreen._secondaryLabel`, calling the new function instead (D-516a). Change nothing
       else in `exercise_progress_screen.dart`.
8. [x] Add `String formatNativeChange(NativeMetric metric, double delta, SettingsState settings)` to the
       same file: `'↑ +<figure>'` when `delta > 0`, `'↓ -<figure>'` when `< 0`, `'—'` when `== 0`, where
       `<figure>` is the magnitude formatted by the same per-metric rule `formatNativeMetric` uses (a
       weight with the weight unit, reps as `'<n> reps'`, a clock for holds/durations, `'<n> rounds'`,
       `'<n> min'`, and for pace the clock per distance unit — reusing
       `nativeMetricDisplayValue`/the same conversion, never a second km↔mi constant). The sign is ASCII
       and comes from the raw numeric sign (D-508). This step is the superseded plan's Phase 3 Step 5,
       moved here so both formatters land with the data they belong to (see §Open Items O-5).
9. [x] **Green run** of the two new files plus `test/records_and_trends_screen_test.dart` and
       `test/exercise_progress_screen_test.dart` (4a's, to prove D-516a changed no output). — `test/exercise_progress_screen_test.dart` does not exist; 4a's `ExerciseProgressScreen` assertions live in `test/records_and_trends_screen_test.dart` (S-913…S-915), so the run covers the two new files plus that one: `+37: All tests passed!`
10. [x] Update `docs/state_management/services_and_utils.md` (add `computeInstrumentSections`, its inputs,
        the two `computeExerciseMetrics` calls and the section/row ordering rules, citing D-504/D-506) and
        `docs/data_models.md` (the two new value types in `lib/core/models/instrument_list.dart`; state that
        nothing is persisted and `lib/core/models/exercise_metric.dart` is unchanged).

**Done Criteria** (run until green):
- `gateway.sh test test/instrument_list_service_test.dart test/instrument_change_format_test.dart test/records_and_trends_screen_test.dart test/exercise_progress_screen_test.dart`
  → all pass (paste the counts).
- `gateway.sh test` → the whole suite passes (paste the counts).
- `gateway.sh lint` → 0 errors, ≤ baseline issues; `lib/core/models/instrument_list.dart`,
  `lib/core/services/stats_progress_service.dart` and `lib/features/stats/widgets/native_value_format.dart`
  each 0 issues.
- Search `lib/` for `SensorSummary` → the only readers are `stats_progress_service.dart` and the two
  repositories; no widget reads a sensor summary directly.
- Search `lib/features/stats/` for `_secondaryLabel` → gone (one label source, D-516a).
- `gateway.sh git-diff --stat -- lib/core lib/features/stats test docs` → matches the Predicted Files.
- **Mutation M1 (section order):** in `computeInstrumentSections`, replace the D-504 sort with
  `ExerciseSection.values` order; run the service test file; show S-1005 failing (its fixture has cardio on
  3 days and resistance on 1); restore; show it passing.
- **Mutation M2 (cadence denominator):** in the cadence helper, divide the summed `steps` by the minutes of
  **all** the exercise's timed instances in the window instead of only those carrying `steps`; run the
  service test file; show S-1008 failing; restore; show it passing.
- **Mutation M3 (the comparison):** in `computeInstrumentSections`, take `previousValue` from the window's
  own first point instead of the previous range's summary; run the service test file; show S-1009 failing;
  restore; show it passing.
- **Optional diagnostic M4:** replace D-509's `DateTime(y, m, d − n)` with `subtract(Duration(days: n))`
  and run S-1009's calendar assertion. This is only observable when the host timezone has a DST transition
  between the two dates; record the host `TZ` and the observed result either way, and do not claim a red
  run you did not see.

**Predicted Files:** `lib/core/models/instrument_list.dart` (new),
`lib/core/services/stats_progress_service.dart`, `lib/features/stats/widgets/native_value_format.dart`,
`lib/features/stats/exercise_progress_screen.dart`, `test/instrument_list_service_test.dart` (new),
`test/instrument_change_format_test.dart` (new), `docs/state_management/services_and_utils.md`,
`docs/data_models.md`.

---

## Files Affected (this PR)

| File | Phase | Change |
|---|---|---|
| `lib/data/repositories/workout_repository.dart` | 1 | the `getSensorSummariesBySession` declaration |
| `lib/data/repositories/hive_workout_repository.dart` | 1 | its implementation + the shared comparator |
| `lib/data/repositories/mock_workout_repository.dart` | 1 | the Mock twin |
| `test/helpers/repository_harness.dart` | 1 | `sensorSummary`, `seedSensorSummary` |
| `test/sensor_summaries_by_session_test.dart` | 1 | new — S-1002…S-1004 |
| `docs/db_integration.md` | 1 | the new read |
| `lib/core/models/instrument_list.dart` | 2 | new — the two value types |
| `lib/core/services/stats_progress_service.dart` | 2 | the sensor index, `computeInstrumentSections` |
| `lib/features/stats/widgets/native_value_format.dart` | 2 | `nativeSecondaryLabel`, `formatNativeChange` |
| `lib/features/stats/exercise_progress_screen.dart` | 2 | `_secondaryLabel` deleted, shared function used |
| `test/instrument_list_service_test.dart` | 2 | new — S-1005…S-1010, S-1013, S-1018 |
| `test/instrument_change_format_test.dart` | 2 | new — `formatNativeChange`'s branches |
| `docs/state_management/services_and_utils.md` | 2 | `computeInstrumentSections` |
| `docs/data_models.md` | 2 | the two value types |

**Nothing else.** In particular: no model field, no `scripts/sqlite_schema.sql`, no
`scripts/sqlite_seed.sql`, no `test/db_seed_test.dart`, no `lib/features/stats/stats_screen.dart` (that is
4b2's), no PR-path file, no `pubspec.yaml`, no `watch/`.

---

## Notes

**Phase dependency graph.** Phase 1 → Phase 2, strictly: Phase 2's service test seeds sensor summaries and
reads them through Phase 1's bulk read. Phase 1 is independently shippable and green on its own.

**Predicted intermediate states.**
- After Phase 1: `getSensorSummariesBySession` exists and is tested, with no production reader. `flutter
  analyze` may report an unused-parameter info in the repositories — acceptable at the baseline's info
  level, and gone by Phase 2.
- After Phase 2: `computeInstrumentSections` and `formatNativeChange` are tested and unused by any widget
  (same situation, and the reason Phase 2's Done Criteria run the whole suite rather than only the new
  files). The Instruments list is 4b2's.

**Legacy handling.** None needed: this series is single-release (4a D-402). No migration, no old-data
handling, no flag.

**The one place a reasonable implementer could drift.** The change chip's arrow for pace. A faster pace is a
*smaller* seconds-per-kilometre value, so a faster run reads `↓` and a slower one reads `↑`. That is
D-508's raw-sign rule and it matches `_buildGroupComparisonChip`; do not add a per-metric inversion. If the
owner wants "faster is up" for pace, that is a new decision (superseding D-508) and a new scenario, not an
implementer's choice.

---

## Open Items

- **O-1 (deferred to 4c, deliberately).** The pack's bullet *"Update or retire the top-N selection tests in
  `test/stats_progress_test.dart`"* is **not** done in this PR. 4b keeps `computeProgressData` and the five
  legacy sections, so those tests must pass **unmodified**; retiring them here would delete the guard on
  code that is still live. They are retired in 4c with the code they guard.
- **O-4 (4c).** The five legacy sections and `kTopLiftCount` / `kTopCardioCount` / `kRecentPRCount` /
  `kRecentTrainingDaysWindow` are still live after 4b and 4b2. 4c must prove no reader of the old
  representation remains.
- **O-5 (resolved here).** The superseded plan left `formatNativeChange`'s home open (its Phase 2 or
  Phase 3). Resolved: both shared formatters land in this plan's Phase 2, so 4b2 touches
  `native_value_format.dart` only if it needs to — it does not. Its proof is
  `test/instrument_change_format_test.dart`.
- **O-6 (4b2).** S-1012 (an empty window with a non-empty history) is 4b2's: its expected outcome is about
  the rendered screen, which this PR does not change. The superseded plan listed it under Phase 2's test
  coverage; it moves with the screen work.

---

## Progress

| Phase | Owner | State | Evidence |
|---|---|---|---|
| 1 — the bulk sensor-summary read | @dba | **Complete** | evidence §4 Phase 1: red compile failure → `+6: All tests passed!`; full suite `+3159 ~1: All tests passed!`; lint `199 issues found.` (0 errors, equal to baseline); M0 red `Actual: Set:['']` → restored `+6` |
| 2 — the Instruments computation | @developer | **Complete** | evidence §4 Phase 2: green `+37` (two new files + `records_and_trends_screen_test.dart`); full suite `+3183 ~1: All tests passed!`; lint `199 issues found.` (0 errors, equal to baseline); M1 → `+16 -2`, M2 → `+16 -2`, M3 → `+14 -4`, each restored to `+18`; M4 no red observed (host EDT, transition after the midnight boundary) |
| Review | @code-reviewer | not started | — |

---

## Assumption Log

Executors append here; the planner ratifies (promotes to a D-x) or reverts (opens a remediation item).
Empty is expected before Phase 1 starts.

| # | Phase | Decision | Options considered | Why | Verdict |
|---|---|---|---|---|---|
| A-1 | 1 | The harness `sensorSummary` helper fills `maxHeartRateBpm` from `avgHeartRateBpm` when a fixture names only the average. | (a) fill the max from the average; (b) require both; (c) leave the pair nullable as passed. | `SensorSummary._checkInvariants` refuses a summary whose average and maximum are not both present or both absent, and the plan's S-1008 fixture names only averages. (b) makes the helper unusable for that fixture; (c) throws at construction. | pending |
| A-2 | 2 | The `formatNativeChange` claim goes in `docs/state_management/services_and_utils.md` as the plan's §Doc-claim table says, and that document's scope line now names `lib/features/stats/widgets/native_value_format.dart`. | (a) put the claim where the plan says and widen the scope line by one path; (b) leave it undocumented because the file is outside the document's stated scope; (c) put it in `docs/data_models.md`. | (a) keeps the plan's claim-to-test table intact and honest; (b) drops a required doc entry; (c) is the wrong document for a formatter. | pending |
| A-3 | 2 | `docs/data_models.md` records `InstrumentSectionData` / `InstrumentRow` as derived types with their relationships, not as a field list. | (a) relationships + lifecycle, per the documentation standard; (b) the field table the plan's wording implies. | `docs/documentation_standard.md` §6.2 forbids per-class field tables in that document — the model source owns them. | pending |

---

## Feedback

**Review 1** — findings in
`2026-10-01-04b-stats-pr4b-instruments-data-plan.review.md`. Verdict: changes requested;
documentation only, one pass.

Fix checklist:
1. `docs/data_models.md:583` — delete the clause claiming the Stats screen renders an
   Instruments list. False: nothing under `lib/features/stats/` references the new types.
2. `docs/state_management/services_and_utils.md:274` — drop the present-tense reference to a
   rendered Instruments list.
3. `docs/state_management/services_and_utils.md:281` — the row rank is the count of days with a
   *readable* value; the zero-fallback row has none and sorts last (D-505, S-1010).
4. `docs/db_integration.md:63` — restate "no schema or seed change" as a durable contract rather
   than a statement about this diff.
5. `docs/data_models.md:583` — "A `InstrumentSectionData`" → "An".

Findings 5 and 7 (a per-row history re-walk; a calendar test running twice) are non-blocking and
may move to the next PR in the series.

*The owner writes here only to redirect product behaviour, contradict a D-x, or change scope; that
is the only thing that re-invokes the planner.*

---

## Doc-claim → test table

Every behavioural sentence the docs will gain, and the test that proves it. A claim with no test does not
ship; a doc that names a type, file or constant that does not exist is a blocker.

| Doc | Claim it will make | Test that proves it |
|---|---|---|
| `docs/db_integration.md` | `getSensorSummariesBySession()` returns every summary grouped by `sessionId`, each group in `getSensorSummariesForSession`'s order | `test/sensor_summaries_by_session_test.dart` S-1002, S-1003 |
| `docs/db_integration.md` | Mock and Hive agree value-for-value | S-1004 |
| `docs/db_integration.md` | no model, schema or seed file changed | `gateway.sh test test/db_seed_test.dart` green, unmodified |
| `docs/state_management/services_and_utils.md` | `computeInstrumentSections` returns the window's sections and rows from two `computeExerciseMetrics` calls | `test/instrument_list_service_test.dart` S-1005, S-1007 |
| `docs/state_management/services_and_utils.md` | sections are ordered by distinct training days in the window, descending, ties in declaration order | S-1005 |
| `docs/state_management/services_and_utils.md` | rows are ordered by training days, then name, then id | S-1010 |
| `docs/state_management/services_and_utils.md` | the change indicator compares with the immediately preceding range of the same calendar length, and is absent when the previous value is missing or on a different metric | S-1009 |
| `docs/state_management/services_and_utils.md` | cadence is Σ steps ÷ Σ minutes over the timed instances that carry steps | S-1008 |
| `docs/state_management/services_and_utils.md` | average heart rate is Cardio's timed-instance mean and Sports' round-instance mean | S-1008 |
| `docs/state_management/services_and_utils.md` | the change chip's text is `'↑ +<figure>'` / `'↓ -<figure>'` / `'—'`, magnitude formatted per metric | `test/instrument_change_format_test.dart` |
| `docs/data_models.md` | `InstrumentRow` / `InstrumentSectionData` fields, and that nothing is persisted | compile + S-1007 |

---

## Open questions (defaults applied)

Each of these is a product choice the planner had to make to keep the plan executable. The plan runs on the
**default**; the owner can veto any of them and the plan will be amended by superseding ledger entries.
The Fuel row's questions (the superseded plan's 17…23) and the screen questions (4, 7, 12, 13, 14, 16, 24)
are in the sibling plans; question 26 (the plan/evidence layout) is obsolete — the plans are folders.

1. **The split itself (D-501).** Default: item 5 ships as three plans — 4b (the data), 4b2 (the list), 4b3
   (the Fuel row). *Veto:* ship the data and the list as one PR and accept two soft budget signals.
2. **The change indicator's basis (D-508).** Default: the immediately preceding range of the same calendar
   length. *Alternatives:* the exercise's all-time previous best; a fixed 30-day lookback.
3. **The previous range's length (D-509).** Default: the window's own day count (14 for the default
   window), so a period-scoped window compares with the equally long period before it.
4. **Cadence's formula (D-511).** Default: Σ steps ÷ Σ minutes of the timed instances that carry steps, so
   an instance without steps cannot dilute the rate. *Alternative:* divide by the exercise's whole window
   duration.
5. **Average heart rate (D-512).** Default: mean of `avgHeartRateBpm` (not of `maxHeartRateBpm`), Cardio
   from timed instances and Sports from round instances. *Alternative:* a time-weighted mean.
6. **Row ordering (D-506).** Default: training days, then name, then id. *Alternative:* order by the native
   value (heaviest lift first).
7. **Section ordering (D-504).** Default: distinct training days in the window, descending — which
   **supersedes D-403's fixed order for this list only**. Records & Trends keeps the fixed order.
8. **The bulk read's shape (D-513).** Default: one map keyed by session, ordered like the single-session
   read. *Alternative:* a flat list the service groups.
9. **A row with no readable value (D-505).** Default: the row still appears, with the zero fallback and no
   points. *Alternative:* omit it.
10. **Pace's arrow direction (D-508).** Default: the raw numeric sign, so a slower pace reads `↑`.
    *Alternative:* invert for pace so faster reads `↑`.
11. **Deferring the top-N test update (O-1).** Default: defer to 4c, because the code those tests guard is
    still live in 4b.
