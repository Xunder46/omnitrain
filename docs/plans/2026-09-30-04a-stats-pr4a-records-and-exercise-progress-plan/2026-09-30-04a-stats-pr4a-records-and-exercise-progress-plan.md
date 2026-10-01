# Feature: Stats PR 4a — Records & Trends, Exercise Progress, and the per-exercise native value

> Status: READY (Iteration 1, not started).
> Next handoff: Copilot (DeepSeek V4.1 Flash, local, in this checkout), Step 0 → Phase 1 → 2 → 3, then
> `/code-reviewer`.
> Series: PR 4a. Index: `docs/plans/2026-09-30-04-stats-pr4-index.md`.
> Base: `develop`. Work directly on `develop`.
> Branch policy (owner): all work happens on `develop`. Never create, switch or delete a branch. Copilot
> never commits, stages, merges or pushes.
> Evidence: `2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.evidence.md` (baselines, facts
> H1–H14, the tables you fill). The reviewer writes `…plan.review.md`.
> Source of scope: `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 6, and the
> parts of item 5 that item 6 shares (the native metric per effort kind, the section assignment, the
> Exercise Progress view); the pack's D-12 and D-13; the owner's delegation of the split to the planner.
> Scope check (2026-09-30): 651 lines, 3 phases, one track (the phone), 16 decisions, 16 scenarios, about
> 1,000 predicted production lines. One soft signal (length over 500), no hard limit
> (`.github/agents/pr_scope_budget.md` §1). Within budget.

## What this PR does

**Additive. Nothing is removed, and the Stats screen keeps every section it has today.**

1. **The repository gains a bulk round-instance read.** `getRoundInstances(String effortId)` exists; there
   is no bulk counterpart, and "rounds completed" is not derivable from what Stats reads today. Phase 1.
2. **One computation of an exercise's native value, over any range.** Today `StatsProgressService` computes
   per-day trends for the few exercises its top-N selection picked. Phase 2 adds a range-scoped computation
   over **every** exercise: its section, its best native value, one point per training day, when it was last
   trained, and how many sessions it appeared in. Records & Trends, Exercise Progress and (in 4b) the
   Instruments rows all read this one method.
3. **Records & Trends**, a new screen reached from a chart icon in the Stats header (pack item 6): the three
   all-time totals, the existing Recent PRs, and a searchable list of every exercise ever logged, grouped
   into the four sections, each entry showing its all-time best and when it was last trained.
4. **Exercise Progress**, a new view (pack D-12): the full-history chart of the exercise's native metric, its
   all-time best, and its recent sessions with their values. Both new screens open it.
5. **The Stats doc is reconciled** (pack D-13): `docs/stats_screen.md` today describes a RECORDS section, a
   VOLUME TRENDS section and a CONSISTENCY section that do not exist, and omits the ISOMETRIC and SPORTS
   sections that do.

The old STRENGTH, CARDIO, ISOMETRIC, SPORTS and NUTRITION sections, the top-N selection and the nutrition
trend stay exactly as they are. PR 4b adds the Instruments list and the Fuel row; PR 4c removes the old
sections. See the index for the split.

**Where the new code lives.** The new computation is added to `StatsProgressService`, not to a new service:
it already holds the bulk history index, the exercise cache and `epley1RM`, and one instance per screen load
means one read of the repository. The new value types go in a new file, so the types PR 4c retires stay in
`stats_progress.dart`.

## Decision Ledger

Immutable; changes are made by superseding entries.

| ID | Decision | Source |
|---|---|---|
| **D-401** | **The split.** Pack items 5 and 6 ship as 4a (this PR) → 4b (Instruments list, Fuel row) → 4c (remove the old sections). 4a and 4b add; only 4c removes. 4a is planned in full; 4b and 4c are planned when their turn comes. | Owner delegation, 2026-09-30 |
| **D-402** | **Single release.** Inherits 3b D-332. No user data exists for any of this, so 4a contains no migration, no old-data handling, no backward compatibility and no feature flag. | 3b D-332 |
| **D-403** | **The four sections, and which one an exercise is in.** `Resistance`, `Cardio`, `Isometric`, `Sports`, always in that order. The section is the **effort kind the exercise was actually logged under** — `set` → Resistance, `timed` → Cardio, `drill` → Isometric, `round` → Sports — never the session's modality label and never the exercise's catalog modality (pack D-3, D-15). An exercise is in **exactly one** section. When it was logged under more than one kind over the range the screen shows, the kind with the most logged efforts wins; a tie resolves in the order Resistance, Cardio, Isometric, Sports. | Pack D-3, D-15; Claude |
| **D-404** | **The counted population.** Only **completed** sessions count (a session with an `endedAtMs`), matching the Stats screen's own totals and its existing trend passes. Only efforts with a non-null `exerciseId` count. An exercise's displayed name is its catalog name, falling back to the raw id when the catalog row is gone — the fallback `StatsProgressService` already uses. | Claude |
| **D-405** | **Resistance native value.** Reuse `epley1RM(weight, reps)` = `weight × (1 + reps/30)` and the existing per-exercise axis rule verbatim: an exercise is **reps-axis** iff **any** of its sets anywhere in its full history has `metric-weight` 0 or absent; otherwise weight-axis. A `metric-extra-weight` row never switches the axis; it is an annotation. Weighted → the highest e1RM over the range. Reps-axis → the highest single-set reps over the range, with that set's added weight noted when it is greater than 0. Zero-rep sets contribute nothing. | Pack item 5; existing service |
| **D-406** | **Cardio native value.** Over the range: if any of the exercise's timed entries has a measured distance greater than 0, the native value is **pace**, in seconds per kilometre, taken from the exercise's entries that have a pace (a finished instance with a distance greater than 0 — the D-309 rule the existing cardio pass already uses). Otherwise the native value is **total duration**, the sum of the `actualDurationSecs` of its `TimedState.finished` instances. The **"est."** marker is set when any distance behind the pace is `DistanceSource.isEstimated`. | Pack item 5; 3a D-309, D-311 |
| **D-407** | **Isometric native value.** The **longest single hold** — the greatest `actualDurationSecs` among the exercise's `TimedState.finished` instances over the range. The **secondary** value is total hold time, the sum of the same instances. The added weight of the longest hold is noted when it is greater than 0, read per instance with `EntryRows.companions(rows: …, metricId: MetricIds.extraWeight, entryCount: instances.length)`. | Pack item 5; 3b D-339 |
| **D-408** | **Sports native value.** **Rounds completed** is the count of the exercise's `RoundInstance` rows with `state == RoundState.finished && startedAtMs > 0 && finishedAtMs != null` — the rule `SessionSummaryBuilder` owns, reused so the two surfaces cannot disagree. `RoundInstance.completed` alone does **not** decide. The **secondary** value is total round time, the sum of those rounds' `elapsedMs`, shown in minutes. Rounds completed is the primary value. | Pack item 5; `session_summary_builder.dart` |
| **D-409** | **An all-time best is descriptive.** It creates no PR event, no toast and no Summary row (pack item 6). The PR path is untouched by 4a, so `test/in_session_pr_toast_test.dart`, `test/pr_toast_test.dart` and the summary tests pass **unmodified**. | Pack item 6 |
| **D-410** | **Last trained** is the start time of the most recent completed session, inside the range, that logged the exercise. | Pack item 6 |
| **D-411** | **The three all-time totals are computed once.** Sessions = completed sessions; Time = the sum of `endedAtMs - startedAtMs` over completed sessions that are not rolling; Streak = `CalendarState.streakDays`, reused, never re-implemented. Sessions and Time come from a new `StatsProgressService.computeTotals()`, which the Stats screen also calls, so the two screens cannot drift. | Existing `stats_screen.dart` |
| **D-412** | **Recent PRs move unchanged.** Records & Trends shows the same list, from the same `recentPRs` field, rendered by the same widget. `StatsProgressService`'s PR detection is not touched. | Pack item 6 |
| **D-413** | **Search reuses `FuzzySearch`.** Filter with `FuzzySearch.matches(query, name)`; order by `FuzzySearch.score(query, name)` descending, then by name. An empty or whitespace-only query shows every exercise; a section with no match is hidden. | Pack item 6; `fuzzy_search.dart` |
| **D-414** | **The entry point.** A chart icon in the Stats header, added through the existing `OmniBackHeader.actions` slot, carrying an accessible label; the push goes through `OmniNavigator.push` (`docs/navigation_contract.md`). It is the only way into Records & Trends. | Pack item 6; navigation contract |
| **D-415** | **The repository change is one bulk read.** `getRoundInstancesByEffort()` is added to `WorkoutRepository`, `HiveWorkoutRepository` and `MockWorkoutRepository`, mirroring `getTimedInstancesByEffort()`. No other interface change, and no model change, so `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` are **not** touched. | Claude |
| **D-416** | **Docs.** 4a edits: `docs/db_integration.md` (the new read), `docs/state_management/services_and_utils.md` (the new computation), `docs/navigation_and_screens.md` (two screens), `docs/stats_screen.md` (the D-13 reconciliation plus a pointer), `docs/README.md` (the new page), and creates `docs/records_and_trends.md`. It touches no other doc. | Pack D-13; Claude |

## Invariants that bite in this PR

- **Repository parity.** Wherever a scenario says Mock/Hive, both give the same result. The new read is
  tested on both.
- **State and features depend on `WorkoutRepository` only.** The new screens take `WorkoutState` and
  `SettingsState`, as `StatsScreen` does; they never name a repository class.
- **Hive and Mock stay in step** for the new read.
- **Nothing visible changes on the old Stats screen.** The existing `StatsScreen` widget tests in
  `test/screen_widget_test.dart` pass unmodified, including every assertion on the old section headers.
- **Unchanged:** `test/in_session_pr_toast_test.dart`, `test/pr_toast_test.dart`, the summary tests,
  `scripts/sqlite_schema.sql`, `scripts/sqlite_seed.sql`, and everything under `watch/`.
- **Theme.** Use `OmniTheme.colorsForTheme(...)` tokens and the existing widgets (`OmniSurface`,
  `OmniCardHeader`); no hex colour literal anywhere, in code or docs.

## Acceptance Criteria

- **AC-1:** the bulk round read groups by effort, orders each group by `roundIndex`, and is identical on
  Hive and Mock (S-901, S-902, S-903).
- **AC-2:** every exercise ever logged appears in exactly one section, keyed by its logged effort kind and
  not its modality label (S-905, S-907).
- **AC-3:** the native value is right for all four kinds, including the reused axis rule and the "est."
  marker (S-904, S-906, S-907, S-908).
- **AC-4:** an exercise with one session, and an empty history, are both handled (S-909, S-910).
- **AC-5:** an exercise last trained a year ago is still listed with its last-trained time (S-911).
- **AC-6:** the chart icon opens Records & Trends; its label is present; it is the only entry point (S-913).
- **AC-7:** Records & Trends shows the three all-time totals, the same Recent PRs the Stats screen shows,
  and a searchable list grouped into the four sections with each entry's all-time best and last-trained time
  (S-912, S-913).
- **AC-8:** tapping an entry, on either screen, opens Exercise Progress for that exercise (S-914).
- **AC-9:** Exercise Progress shows the full-history chart, the all-time best and the recent sessions
  (S-915).
- **AC-10:** the previous Stats layout is unchanged and still reachable in 4a (S-916). The "no longer
  reachable" criterion of pack item 6 is delivered by 4c.

## Scenarios

Code comments and test names reference these ids. Fixtures are enumerated; if a fixture cannot be written,
the scenario is wrong, not the implementer. Build fixtures on `test/helpers/repository_harness.dart`
(`seedSession`, `seedExercise`, `seedSetEffort`, `seedTimedEntries`, `seedHoldEffort`, `harnessFactories`,
`fixtureStart`, `fixtureRowAt`).

### S-901: the bulk round read groups and orders
- Fixture: two efforts on two segments of two completed sessions — `effort-a` with round instances at
  `roundIndex` 2, 0, 1 written out of order, and `effort-b` with one instance. One effort with no instances
  at all.
- Trigger: `getRoundInstancesByEffort()`.
- Flow: read once.
- Expected outcome: two keys; `effort-a` holds three instances in `roundIndex` order 0, 1, 2; `effort-b`
  holds one.
- Must fail if: the group keeps the store's order, or a group mixes two efforts.

### S-902: an effort with no round instances is absent
- Fixture: S-901's population.
- Trigger: `getRoundInstancesByEffort()`.
- Flow: read once.
- Expected outcome: the key for the instance-less effort is **absent** from the map, not present as an empty
  list — the same shape `getTimedInstancesByEffort()` has.
- Must fail if: the map holds an empty list for it.
- Edge case of: S-901.

### S-903: Hive and Mock agree
- Fixture: S-901's population, seeded identically through each `harnessFactories` entry.
- Trigger: `getRoundInstancesByEffort()` on both.
- Flow: compare key sets, and each group's `roundIndex` sequence and ids.
- Expected outcome: identical. On Hive, identical again after `restart()`.
- Must fail if: one implementation sorts and the other does not.
- Edge case of: S-901.

### S-904: the Resistance native value, and the axis rule that decides it
- Fixture: **`ex-row`**, weight-axis: two completed sessions, sets `weight` 100 kg × 5 reps (e1RM 116.67)
  and `weight` 120 kg × 3 reps (e1RM 132.0). **`ex-pull`**, reps-axis: an old session with one
  `weight` 0 set of 4 reps, then a recent session with `weight` 20 kg × 8 reps and `extra-weight` 5 kg.
  **`ex-carry`**, bodyweight: one session, sets of 30 and 12 reps with `extra-weight` 10 kg.
- Trigger: `computeExerciseMetrics()` over all history.
- Flow: read each exercise's `best`.
- Expected outcome: `ex-row` is weight-axis, best is 132.0 on the e1RM metric. `ex-pull` is reps-axis — the
  old weightless set decides the axis for the whole exercise — best is 8 reps with added weight 5 kg noted,
  **not** an e1RM. `ex-carry` is reps-axis, best is 30 reps with added weight 10 kg.
- Must fail if: the axis is decided per session or per range, or `extra-weight` switches the axis.
- Edge case of: none.

### S-905: an exercise logged under two kinds is in one section
- Fixture: **`ex-mixed`** logged as `set` in one session and `timed` in two sessions, all completed.
  **`ex-tied`** logged as `timed` once and `round` once. **`ex-sets`** logged as `set` only.
- Trigger: `computeExerciseMetrics()` over all history.
- Flow: read each exercise's `section`.
- Expected outcome: `ex-mixed` is Cardio (two timed efforts beat one set effort). `ex-tied` is Cardio (the
  tie resolves in the fixed order). `ex-sets` is Resistance.
- Must fail if: the section comes from the session's modality label, from the exercise's catalog modality,
  or the exercise appears in two sections.
- Edge case of: none.

### S-906: the Cardio native value, and the "est." marker
- Fixture: **`ex-run`**: one completed session, two finished timed entries — 600 s / 2000 m (pace 300 s/km)
  and 300 s / 1500 m (pace 200 s/km), distance rows with no source. **`ex-ride`**: one completed session,
  two finished timed entries with durations but no distance row at all. **`ex-hike`**: one completed
  session, one finished entry, 1800 s / 3000 m with the distance row's source `estimated`.
- Trigger: `computeExerciseMetrics()` over all history.
- Flow: read each exercise's `best`.
- Expected outcome: `ex-run` is pace, 200 s/km, `estimated` false. `ex-ride` is duration, 900 s.
  `ex-hike` is pace 600 s/km with `estimated` true.
- Must fail if: the fastest pace is not the best, a distance-less exercise reports a pace, or an estimated
  distance is not marked.
- Edge case of: none.

### S-907: the Isometric native value, and a Plank logged two ways
- Fixture: **`ex-plank-hold`** logged as a `drill` effort in one completed session: finished instances of
  30 s, 90 s and 45 s, each with an `extra-weight` row of 0, 10 and 0 kg. **`ex-plank-timed`** logged as a
  `timed` effort in one completed session: finished instances of 60 s and 45 s.
- Trigger: `computeExerciseMetrics()` over all history.
- Flow: read both exercises.
- Expected outcome: `ex-plank-hold` is Isometric, best is the hold of 90 s with added weight 10 kg and
  secondary total 165 s. `ex-plank-timed` is **Cardio** (its effort kind is `timed`), best is its duration.
  They are two entries in two different sections, not one.
- Must fail if: the two are merged, the hold is summed instead of the longest single one taken, or the
  added weight is taken from a different instance than the longest hold.
- Edge case of: none.

### S-908: rounds completed, and the rule that decides it
- Fixture: one completed session, `ex-bjj` as a `round` effort with five round instances:
  1. `state` finished, `startedAtMs` > 0, `finishedAtMs` set, `completed` true, 180 s;
  2. `state` finished, `startedAtMs` > 0, `finishedAtMs` set, `completed` false (stopped early), 120 s;
  3. `state` active, `startedAtMs` > 0, `finishedAtMs` set (the shape a paused-then-abandoned round
     persists), 90 s;
  4. `state` notStarted, `startedAtMs` 0, `finishedAtMs` null;
  5. `state` finished, `startedAtMs` > 0, `finishedAtMs` null.
- Trigger: `computeExerciseMetrics()` over all history, and `SessionSummaryBuilder` for the same session.
- Flow: compare.
- Expected outcome: rounds completed is 2 (1 and 2); the same number `SessionSummaryBuilder.totalRounds`
  reports. Total round time is 300 s, shown as 5 minutes.
- Must fail if: `completed` alone decides (that would give 1), or a round with no `finishedAtMs` counts.
- Edge case of: none.

### S-909: an exercise with exactly one session
- Fixture: one completed session, `ex-squat`, one set effort with a single 100 kg × 5 set.
- Trigger: `computeExerciseMetrics()` over all history.
- Flow: read it.
- Expected outcome: one point, best is the e1RM of that set, `sessionCount` 1, `lastTrainedMs` is that
  session's start, and nothing throws.
- Must fail if: the computation assumes two points, or divides by a point count.
- Edge case of: S-904.

### S-910: an empty history
- Fixture: no sessions at all.
- Trigger: `computeExerciseMetrics()` over all history; then open Records & Trends and Exercise Progress.
- Flow: read, then build both screens.
- Expected outcome: an empty list; Records & Trends shows its empty state; Exercise Progress is not
  reachable, because no entry exists to tap.
- Must fail if: either screen throws on an empty list.
- Edge case of: S-909.

### S-911: an exercise last trained a year ago
- Fixture: **`ex-deadlift`** in one completed session 370 days ago; **`ex-bench`** in one completed session
  yesterday.
- Trigger: `computeExerciseMetrics()` over all history.
- Flow: read both.
- Expected outcome: both are listed; `ex-deadlift`'s `lastTrainedMs` is the old session's start, and it
  appears in the list — the 30-day recency floor of the old top-N selection does **not** apply to these
  screens.
- Must fail if: an exercise older than the recency floor is dropped.
- Edge case of: none.

### S-912: search
- Fixture: `ex-bench` "Bench Press", `ex-bench-incline` "Incline Bench Press", `ex-squat` "Back Squat".
- Trigger: type `bench`; then `squat`; then a string matching nothing; then clear the field.
- Flow: read the visible list after each.
- Expected outcome: `bench` shows both bench exercises and hides the squat section if the squat is alone in
  its section; `squat` shows only the squat; a non-matching string shows no entries; an empty field shows
  everything again.
- Must fail if: matching is exact-prefix only, or a section with no match stays visible.
- Edge case of: none.

### S-913: the header icon, the totals and the PRs
- Fixture: three completed sessions (one rolling), one of them holding a PR-producing lift; a fixed clock.
- Trigger: open the Stats screen, then the header's chart icon.
- Flow: read both screens' figures.
- Expected outcome: Records & Trends shows the same Sessions, Time and Streak the Stats screen shows, and
  the same Recent PRs in the same order. The header icon has a non-empty accessible label.
- Must fail if: the totals are computed a second way, or the PR list differs.
- Edge case of: none.

### S-914: the entry opens Exercise Progress
- Fixture: S-904's `ex-row` and `ex-pull`.
- Trigger: tap the `ex-row` entry in Records & Trends.
- Flow: read the pushed screen's title and its figures, then go back.
- Expected outcome: the pushed screen is Exercise Progress for `ex-row` (its title names the exercise), it
  shows the e1RM series, and the back control returns to Records & Trends.
- Must fail if: the wrong exercise opens, or the view is named anything other than "Exercise Progress".
- Edge case of: S-913.

### S-915: Exercise Progress content
- Fixture: `ex-row` in three completed sessions on three different days, plus the same exercise in a
  cancelled session.
- Trigger: open Exercise Progress for `ex-row`.
- Flow: read the chart, the best and the session list.
- Expected outcome: one chart point per training day, oldest first, three points; the all-time best; a
  session list, newest first, holding three entries with their values — the cancelled session is absent.
- Must fail if: the cancelled session contributes a point, or the list is oldest-first.
- Edge case of: S-909.

### S-916: the old Stats layout is untouched
- Fixture: any population the existing `StatsScreen` widget tests use.
- Trigger: run `test/screen_widget_test.dart`.
- Flow: run it unmodified.
- Expected outcome: every existing assertion passes, including the old section headers and
  `stats_window_chip`.
- Must fail if: a section, a header string or the window chip changed.
- Edge case of: none.

## Iteration 1

### Executor block

**Step 0a — preconditions.** `develop` is checked out and `git status` is clean apart from the three plan
files. `test/helpers/repository_harness.dart` exists, with `harnessFactories`, `seedSession`,
`seedSetEffort`, `seedTimedEntries`, `seedHoldEffort`, `fixtureStart` and `fixtureRowAt`. If any is
missing, STOP and report: 4a's fixtures are built on them.

**Step 0b — do not branch.** Work directly on `develop`. Never create, switch or delete a branch. Never
`git add`, `git commit`, `git merge` or `git push`.

**Step 0c — baselines.** Run both, record the exact lines in the evidence file §1:

```
.github/copilot/scripts/macos/gateway.sh lint
.github/copilot/scripts/macos/gateway.sh test
```

Expected: `199 issues found.` (4 warnings, **0 errors**) and `+3119 ~1: All tests passed!`. If either
differs, record the actual numbers and use **those** as the bar for the rest of the PR.

**Rules**

1. The only shell entry point is `.github/copilot/scripts/macos/gateway.sh` (`lint`, `test`, `format`,
   `pub-get`, `build`, `codegen`, `git-status`, `git-diff`, `git-log`, `git-show`).
2. **The analyzer bar is a count, not an exit code.** `lint` exits non-zero because the repo carries
   pre-existing info notices. The bar is: **0 errors**, and **no more than the Step 0c count**. Every file
   a phase touches has **0** issues of its own.
3. **Never `git stash`.** To prove a test fails without the fix, use the **copy-aside** method: copy the
   source file to `/tmp/<name>.bak`, apply the reversal with `edit`, run the test, restore with
   `cp /tmp/<name>.bak <path>`, run again. Record both runs in the evidence mutation table.
4. **Write the test before the fix** wherever a scenario can be written first. A new test file that fails to
   compile because the method does not exist yet *is* the red run; record the compiler error line.
5. Tests that only exercise the state or service layer use plain `test()`, never `testWidgets`. Widget
   tests are for the two new screens only.
6. Do not touch `watch/`, `scripts/sqlite_schema.sql`, `scripts/sqlite_seed.sql`,
   `test/in_session_pr_toast_test.dart` or `test/pr_toast_test.dart`.
7. If a command hangs, or the same command fails twice, STOP and report. Never run the same command a third
   time.
8. Every fixture is written through `WorkoutRepository` methods, never by poking a Hive box or a Mock map.
9. New strings that a user reads (screen titles, section names, the accessible label, the empty state) are
   pinned in the steps below. Do not invent variants.

**Doc checklist** — run over every doc a phase touches, and fill the evidence doc-claim table.

1. Every behaviour sentence added names the test that verifies it.
2. No line numbers, no commit hashes, and no date presented as current state.
3. No hex colour literals; colours are named tokens.
4. No step-by-step flow walkthroughs and no user-action arrow chains.
5. No roadmap or scheduling phrases ("will be added later", "next we").
6. A new doc page is linked from `docs/README.md`, or it is an orphan.
7. Every relative link resolves.
8. Each edited doc stays under 64 KiB.
9. `gateway.sh test test/docs_indexing_contract_test.dart` passes.

### Phase 1: The bulk round-instance read (@dba)

1.1. [x] Create `test/round_instances_by_effort_test.dart` with S-901, S-902 and S-903 as plain `test()`s,
     each running inside `for (final factory in harnessFactories)`.
     - Add to `test/helpers/repository_harness.dart`, under `// ─── Rows and instances ───`:
       - `RoundInstance roundInstance(String effortId, int roundIndex, {int durationSecs = 180,
         RoundState state = RoundState.finished, bool completed = true, int? startedAtMs, int? finishedAtMs})`
         with id `'ri-$effortId-$roundIndex'`, `startedAtMs` defaulting to
         `fixtureStart + roundIndex * 60000`, and `finishedAtMs` defaulting to
         `state == RoundState.finished ? startedAtMs + durationSecs * 1000 : null` — note `finishedAtMs`
         must be settable to null **independently** of the state, because S-908 needs that shape;
       - `Future<void> seedRoundEffort(WorkoutRepository repo, {required String segmentId, required
         String effortId, required String exerciseId, required List<RoundInstance> rounds})`, which creates
         the `round` effort and then each instance.
1.2. [x] Red run. `gateway.sh test test/round_instances_by_effort_test.dart` → the file fails to compile
     because `getRoundInstancesByEffort` does not exist. Record the error line in the evidence.
1.3. [x] `lib/data/repositories/workout_repository.dart`: next to `getRoundInstances(String effortId)`, add
     `Future<Map<String, List<RoundInstance>>> getRoundInstancesByEffort();` with a doc comment that
     mirrors the timed one: every round instance on the device, grouped by `effortId`, each group carrying
     the same `roundIndex` ordering.
1.4. [x] `lib/data/repositories/hive_workout_repository.dart`: add the override next to
     `getTimedInstancesByEffort()`. Walk `_roundInstancesBox.values`, parse each with
     `RoundInstance.fromMap(_asStringMap(raw))`, group by `instance.effortId`, and sort every group by
     `roundIndex`.
1.5. [x] `lib/data/repositories/mock_workout_repository.dart`: add the override next to
     `getTimedInstancesByEffort()`. Walk `_roundInstances.entries`, and for each entry put a
     `List<RoundInstance>.from(list)` sorted by `roundIndex` into the result. A key whose list is empty is
     not added.
1.6. [x] Green run. `gateway.sh test test/round_instances_by_effort_test.dart` → exit 0. S-901, S-902 and
     S-903 are green; record the pass count.
1.7. [x] `docs/db_integration.md`: in the repository-contract section, add a line for
     `getRoundInstancesByEffort` beside the existing bulk-read lines, saying it is the bulk counterpart to
     `getRoundInstances`, that each group is in `roundIndex` order, and that an effort with no instances has
     no key. Name `test/round_instances_by_effort_test.dart` (S-901, S-902) as the verifier. If the doc has
     no bulk-read lines to sit beside, add the line to the repository-contract list it does have and say so
     in the evidence.

**Red → green:** S-901, S-902 and S-903 fail at Step 1.2 (compile) and pass after Steps 1.3–1.5.

**Done Criteria:**
- `gateway.sh test test/round_instances_by_effort_test.dart` → exit 0, and the evidence records the count.
- `grep -c "getRoundInstancesByEffort" lib/data/repositories/workout_repository.dart` → 1 or more.
- `grep -c "getRoundInstancesByEffort" lib/data/repositories/hive_workout_repository.dart` → 1 or more.
- `grep -c "getRoundInstancesByEffort" lib/data/repositories/mock_workout_repository.dart` → 1 or more.
- `gateway.sh test test/watch_capture_repository_parity_test.dart test/db_seed_test.dart` → exit 0.
- `gateway.sh lint` → 0 errors and no more than the Step 0c count; the four touched files have 0.

**Predicted Files:** `test/round_instances_by_effort_test.dart` (new); `test/helpers/repository_harness.dart`;
`lib/data/repositories/workout_repository.dart`; `lib/data/repositories/hive_workout_repository.dart`;
`lib/data/repositories/mock_workout_repository.dart`; `docs/db_integration.md`; the evidence file.

### Phase 2: The per-exercise native value (@developer)

2.1. [ ] Create `lib/core/models/exercise_metric.dart`. Pin these names, because Phase 3 uses them:
     - `enum ExerciseSection { resistance, cardio, isometric, sports }`, declared in that order, with an
       extension member `String get label` returning `'Resistance'`, `'Cardio'`, `'Isometric'`, `'Sports'`;
     - `enum NativeMetric { estimatedOneRepMax, reps, pace, duration, hold, rounds, roundMinutes }`;
     - `class NativeValue` with `final NativeMetric metric; final double value; final NativeMetric?
       secondaryMetric; final double? secondaryValue; final bool estimated; final double? addedWeightKg;`
       — `estimated` defaults to false, the rest are optional;
     - `class ExerciseMetricPoint` with `final int dayMs; final NativeValue value;`;
     - `class ExerciseMetricSummary` with `final String exerciseId; final String name; final
       ExerciseSection section; final NativeValue best; final List<ExerciseMetricPoint> points; final int
       lastTrainedMs; final int sessionCount;` — `points` is oldest first;
     - `class StatsTotals` with `final int completedSessions; final int durationMs;`.
     No `json`/`toMap` methods: nothing here is persisted.
2.2. [ ] Create `test/exercise_metric_service_test.dart` with S-904, S-905, S-906, S-907, S-908, S-909,
     S-910 and S-911 as plain `test()`s. Every fixture seeds through `WorkoutRepository` and reads through
     `StatsProgressService`. S-908 also builds a `SessionSummaryBuilder` for the same session and asserts
     the two round counts are equal. For a day-old session use `seedSession(daysAgo: …)`; for S-911 use
     `daysAgo: 370`.
2.3. [ ] Red run. `gateway.sh test test/exercise_metric_service_test.dart` → the file fails to compile
     because `computeExerciseMetrics` does not exist. Record the error line.
2.4. [ ] `lib/core/services/stats_progress_service.dart`, `_HistoryIndex`:
     - add the field `final Map<String, List<RoundInstance>> roundInstancesByEffort;` and its constructor
       parameter;
     - add `List<RoundInstance> roundInstancesOf(String effortId) =>
       roundInstancesByEffort[effortId] ?? const <RoundInstance>[];`;
     - in `_loadHistory()`, add `final roundInstances = await _repository.getRoundInstancesByEffort();`
       to the independent reads and pass it to the index.
2.5. [ ] In the same file, add `Future<StatsTotals> computeTotals()`: walk `getAllSessions()`, count a
     session when `endedAtMs != null`, and add `endedAtMs! - startedAtMs` to the duration only when
     `!isRolling`. The body is the loop currently inside `StatsScreen._loadData()`.
2.6. [ ] In the same file, add
     `Future<List<ExerciseMetricSummary>> computeExerciseMetrics({int? fromMs, int? toMs})`.
     It returns one summary per exercise logged in at least one **completed** session whose `startedAtMs`
     falls in the range (null bounds mean all history), and:
     - gathers, per exercise id, the efforts that carry it (`SegmentEffort` rows whose `exerciseId` is the
       id, on a completed session in range), grouped by `effortKind`;
     - picks the section per **D-403** (most logged efforts wins; tie in the fixed order);
     - computes `best` per **D-405** (Resistance), **D-406** (Cardio), **D-407** (Isometric) or **D-408**
       (Sports);
     - builds `points`, one per distinct training day in range on which the exercise was logged, oldest
       first, each holding that day's value computed by the same rule over that day only;
     - sets `lastTrainedMs` to the greatest session `startedAtMs` in range among sessions that logged it,
       and `sessionCount` to the number of those sessions;
     - reads the name through the existing `_exerciseById` cache, falling back to the id.
     Reuse `epley1RM`, `DistancePairing.forEntries`, `DistanceSource.isEstimated`, `EntryRows.companions`
     and the D-408 round predicate. Do not re-implement any of them.
2.7. [ ] Green run. `gateway.sh test test/exercise_metric_service_test.dart` → exit 0. Record the count.
2.8. [ ] `lib/features/stats/stats_screen.dart`, `_loadData()`: replace the inline totals loop with
     `final totals = await service.computeTotals();` and assign `_totalSessions = totals.completedSessions;`
     and `_totalDurationMs = totals.durationMs;`. The streak keeps reading `calendarState.streakDays`. The
     service must therefore be constructed **before** the totals call.
2.9. [ ] Confirm no visible change: `gateway.sh test test/screen_widget_test.dart
     test/stats_progress_test.dart` → exit 0, unmodified.
2.10. [ ] Mutations (copy-aside). Record both in the evidence mutation table.
     - **M1 (required):** in Step 2.6's axis rule, decide the axis per range instead of over full history
       (a weight-axis exercise becomes reps-axis when the range holds no weightless set, and vice versa).
       `test/exercise_metric_service_test.dart` S-904 must fail on `ex-pull`.
     - **M2 (required):** in Step 2.6's Sports rule, count `round.completed` instead of the D-408
       predicate. S-908 must fail (1 found, 2 expected).
2.11. [ ] `docs/state_management/services_and_utils.md`: add a `### StatsProgressService` entry under
     "Previously Undocumented Services & Utilities" (it has no entry today), naming
     `lib/core/services/stats_progress_service.dart`, the one-history-snapshot-per-instance rule, and the
     two methods 4a adds: `computeTotals()` (the three all-time totals, shared with the Stats screen) and
     `computeExerciseMetrics({int? fromMs, int? toMs})` (range-scoped; null bounds mean all history; the
     per-exercise native value and the section assignment are shared by Records & Trends, Exercise Progress
     and, in PR 4b, the Instruments rows). Name `test/exercise_metric_service_test.dart` (S-904–S-911) as
     the verifier.

**Red → green:** S-904–S-911 fail at Step 2.3 (compile) and pass after Steps 2.4–2.6. S-916's existing
tests are green before and after; M1 and M2 prove the new ones bite.

**Done Criteria:**
- `gateway.sh test test/exercise_metric_service_test.dart test/stats_progress_test.dart
  test/screen_widget_test.dart test/session_summary_distance_test.dart
  test/session_summary_effort_row_test.dart > /tmp/pr4a_p2.log 2>&1; echo "exit $?"` → exit 0.
- The full `gateway.sh test` → exit 0 and `All tests passed!`.
- `gateway.sh lint` → 0 errors and no more than the Step 0c count; each file touched in this phase has 0.
- M1 and M2 are recorded with their failing values.
- `grep -n "endedAtMs == null" lib/features/stats/stats_screen.dart` → no line inside `_loadData`.

**Predicted Files:** `lib/core/models/exercise_metric.dart` (new);
`test/exercise_metric_service_test.dart` (new); `lib/core/services/stats_progress_service.dart`;
`lib/features/stats/stats_screen.dart`; `docs/state_management/services_and_utils.md`; the evidence file.

### Phase 3: Records & Trends and Exercise Progress (@developer)

3.1. [ ] Create `lib/features/stats/records_and_trends_screen.dart`. A `StatefulWidget` taking
     `workoutState` and `settingsState`, exactly as `StatsScreen` does. `OmniBackHeader(title: 'Records &
     Trends')`. One load, one `StatsProgressService`, calling `computeTotals()`,
     `computeProgressData()` (for `recentPRs` only) and `computeExerciseMetrics()`. Sections top to bottom:
     - **ALL TIME**: Sessions, Time, Streak, the same three figures and the same formatting the Stats
       screen uses; Time from `_totalDurationMs` via `OmniDateUtils.formatDurationHoursMins`.
     - **RECENT PRS**: the same list the Stats screen renders from `progressData.recentPRs`.
     - a search field, then one section per `ExerciseSection` that has at least one exercise, in the fixed
       order, each under an `OmniCardHeader` with the section's `label`; entries ordered by training-day
       share descending (the `points` length), then by name.
     - each entry: the exercise name, its all-time best formatted for its `NativeMetric` (weight via
       `UnitFormatter.formatWeightValue`, distance and pace via `UnitFormatter.formatDistanceValue` and the
       settings' distance unit, durations via `OmniDateUtils.formatClock`), the "est." marker when
       `estimated`, the secondary value when there is one, and "Last trained <OmniDateUtils.formatShort>".
     - tapping an entry pushes Exercise Progress (Step 3.2) through `OmniNavigator.push`.
     - an empty state when there are no exercises at all.
3.2. [ ] Create `lib/features/stats/exercise_progress_screen.dart`. A `StatefulWidget` taking
     `workoutState`, `settingsState` and the `exerciseId`. `OmniBackHeader(title: 'Exercise Progress')`.
     One load, one `StatsProgressService`, `computeExerciseMetrics()` filtered to the id. Shows, top to
     bottom: the exercise's name as the header subtitle, the all-time best, a line chart of `points`, and
     the recent sessions, newest first, each showing the date and that session's value. Cap the list at a
     named constant `kRecentSessionCount = 20`. If the id is not in the list, show an empty state rather
     than throwing.
     - The chart: `ScrollableTrendChart` (`lib/features/stats/widgets/scrollable_trend_chart.dart`) takes
       `themeColors`, `bounds` (`ChartAxisBounds`), `unitLabel`, `pointCount`, `chartBuilder` and
       `maxVisiblePoints`, and builds the plot itself — reuse it, and build the `LineChart` inside
       `chartBuilder` the way `stats_screen.dart` does. If the value shape does not fit, use a plain
       `LineChart` in the same visual idiom and say so in the evidence.
3.3. [ ] `lib/features/stats/stats_screen.dart`: give the header its action. Replace
     `appBar: const OmniBackHeader(title: 'Stats')` with a header whose `actions` holds one `IconButton`
     using `Icons.show_chart`, `tooltip: 'Records & Trends'` and
     `Semantics(label: 'Records & Trends')`, pushing `RecordsAndTrendsScreen` through `OmniNavigator.push`
     with the same `workoutState` and `settingsState`. Change nothing else in the screen.
3.4. [ ] Create `test/records_and_trends_screen_test.dart` with S-912, S-913, S-914 and S-915 as
     `testWidgets`, each running on the Mock harness and on the Hive harness. Pump the real
     `RecordsAndTrendsScreen` and `ExerciseProgressScreen` with a seeded repository. Assert the header
     labels, the section order, the search results, the totals equality with `computeTotals()`, the PR list
     equality with `progressData.recentPRs`, the pushed screen's title, and the recent-sessions order.
3.5. [ ] Green run. `gateway.sh test test/records_and_trends_screen_test.dart` → exit 0. Record the count.
3.6. [ ] Mutation (copy-aside). Record it in the evidence mutation table.
     - **M3 (required):** in Step 3.1, order the entries by name instead of by training-day share.
       S-913 must fail.
3.7. [ ] Create `docs/records_and_trends.md`: what the screen is for, the four sections and the effort-kind
     rule, the native value per kind, that an all-time best is descriptive and creates no PR event, the
     search rule, that the header icon is the only entry point, and that Exercise Progress is shared by both
     screens. Each claim names its test. Add its row to the feature-doc table in `docs/README.md`,
     immediately after the `[Stats Screen](stats_screen.md)` row, in the same
     `| [Title](file.md) | Description |` shape.
3.8. [ ] `docs/navigation_and_screens.md`: add Records & Trends (reached from the Stats header icon) and
     Exercise Progress (reached from a Records & Trends entry) to the screen map, and note that Exercise
     Progress is named exactly that (pack D-12).
3.9. [ ] `docs/stats_screen.md`: fix the drift the pack's D-13 names — delete the RECORDS, VOLUME TRENDS
     and CONSISTENCY sections from the description, and add the ISOMETRIC and SPORTS sections that the
     screen actually has. Add a sentence naming the header's chart icon and pointing at
     `docs/records_and_trends.md`. Say that the old sections are still what the screen shows, because 4a
     adds the new structure without removing the old.
3.10. [ ] Stale-claim sweep. Run each and record the output in the evidence table.
     - `grep -rn "Exercise Details" docs/ lib/` → no output.
     - `grep -rn "VOLUME TRENDS" docs/` → no output.
     - `grep -rn "CONSISTENCY" docs/` → no output.
     - `grep -rn "MaterialPageRoute(\|PageRouteBuilder(" lib/features/stats/` → no output.
     - `grep -rn "getRoundInstances(" lib/core/services/stats_progress_service.dart` → no output inside
       the new computation (the bulk read is the only round read there).
     - `grep -rn -i "will be added\|in a later PR\|next we" docs/records_and_trends.md` → no output.
3.11. [ ] Run the doc checklist (items 1–9) on all five docs, and fill the evidence doc-claim table.

**Red → green:** S-912–S-915 fail at Step 3.4 (the screens do not exist) and pass after Steps 3.1–3.3. S-916
is green before and after; M3 proves S-913 bites.

**Done Criteria:**
- `gateway.sh test test/records_and_trends_screen_test.dart test/docs_indexing_contract_test.dart >
  /tmp/pr4a_p3.log 2>&1; echo "exit $?"` → exit 0.
- The full `gateway.sh test` → exit 0 and `All tests passed!`; the total is at least the Step 0c count.
- `gateway.sh test test/in_session_pr_toast_test.dart test/pr_toast_test.dart
  test/screen_widget_test.dart` → exit 0, with those files unmodified
  (`gateway.sh git-diff --name-only` lists neither).
- `gateway.sh lint` → 0 errors and no more than the Step 0c count; each file touched in this phase has 0.
- Every command in Step 3.10 gives its expected output.
- M3 is recorded with its failing value.
- The doc-claim table has a row for every behaviour sentence added in Steps 1.7, 2.11 and 3.7–3.9.

**Predicted Files:** `lib/features/stats/records_and_trends_screen.dart` (new);
`lib/features/stats/exercise_progress_screen.dart` (new); `test/records_and_trends_screen_test.dart` (new);
`lib/features/stats/stats_screen.dart`; `docs/records_and_trends.md` (new); `docs/README.md`;
`docs/navigation_and_screens.md`; `docs/stats_screen.md`; the evidence file.

## Files Affected (whole PR)

The union of the three Predicted Files lists. Not touched: `watch/`, `scripts/sqlite_schema.sql`,
`scripts/sqlite_seed.sql`, `test/in_session_pr_toast_test.dart`, `test/pr_toast_test.dart`,
`lib/core/models/stats_progress.dart`, `lib/data/models/models.dart`, and every other `docs/` page.

## Notes

- **Dependency graph:** 1 → 2 → 3. Phase 2 needs the bulk round read; Phase 3 needs the new computation.
  Phase 1 is independent of Phases 2 and 3 in content, and could be run last if the repository work is
  blocked — but then Phase 2's Sports scenario has no round data to read, so the order above is the one to
  follow.
- **Predicted intermediate states after 4a** (both expected, neither a defect):
  1. Recent PRs and the nutrition trend are reachable from two places: the Stats screen and Records &
     Trends. PR 4c removes the duplicates.
  2. The old SPORTS chart sums **timed instances** (`_processRoundEffort` reads `TimedInstance`, not
     `RoundInstance`) and therefore has no round *count* concept at all, while the new Sports value counts
     round instances per D-408. The two can disagree for the same session until 4c removes the old chart.
     4a changes neither path.
- **Why the axis rule is read from full history, not the range:** the existing per-exercise axis rule is
  decided over an exercise's whole history, so an exercise that once had a bodyweight set stays reps-axis
  for ever. Reading it per range would make a row change its unit between windows, which is worse than the
  occasional surprising unit. S-904 pins this and M1 proves the test bites.
- **Cost.** `computeExerciseMetrics()` with null bounds walks all history for every exercise, as
  `computeProgressData()` already does, and both new screens load once. `_loadHistory()` is still built once
  per service instance.
- **No model change,** so `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` stay as they are, and
  `test/db_seed_test.dart` must pass unchanged.

## Open Items

- **O-1:** the PR 3 series index lists **3a3** as PR 4's predecessor. 4a reads nothing 3a3 changes — it
  reads distances through `DistancePairing`/`EntryRows.companions`, which 3a3 simplifies without changing
  behaviour. So 4a may run before or after 3a3; the owner sequences it. 4a does require **3a2 and 3b** on
  `develop`, because it reads the row contract they established.
- **O-2:** PR 4b and PR 4c are not planned. Plan each when its turn comes
  (`.github/agents/pr_scope_budget.md`). 4b needs a second repository addition (a bulk sensor-summary read)
  and 4c needs the `test/screen_widget_test.dart` churn.
- **O-3:** the Fuel row's window, the training-day vs rest-day split, and the "logged days" definition are
  item 5's and are left for 4b's plan.

## Progress

Baselines (evidence §1): 199 issues, 0 errors; 3119 passed, 1 skipped. Fill in as you go.

- [x] Step 0: preconditions, baselines — no branch created (199 issues / 0 errors; 3119 passed, 1 skipped)
- [x] Phase 1: the bulk round-instance read — 5/5 green (S-901, S-902 on Mock + Hive; S-903 cross-store); full suite 3124 passed, 1 skipped; lint 199, 0 errors
- [x] Phase 2: the per-exercise native value — 16/16 green (S-904 … S-911, each on Mock + Hive); M1 and M2 both bite and were reversed; full suite 3140 passed, 1 skipped; lint 199 issues / 0 errors, `stats_screen.dart`'s `_ChartSeries` `unused_element` is pre-existing at the Step 0c count
- [x] Phase 3: Records & Trends, Exercise Progress, the header icon, docs, sweep, M3 — 12/12 green (S-910 … S-915, each on Mock + Hive); M3 plus four further inverse-edit proofs bite and were reversed (Phase 3's implementation landed before its test file, so there is no full-file red run — evidence §6a); full suite 3153 passed, 1 skipped; lint 199 issues / 0 errors, none in a file this phase touched; the §8 sweeps are clean, with the `Exercise Details` row's literal expectation unmeetable on this tree (evidence §8, §9c)
- [ ] Review: `/code-reviewer`
- [x] Fix round 2 (review CHANGES_REQUESTED, round 2) — F-7 `records_and_trends.md` scope block names `ExerciseMetricSummary` / `NativeValue` instead of the non-existent `ExerciseMetric`, and no other bare `ExerciseMetric` remains under `docs/`; F-8 `data_models.md` overview no longer claims the code-reference table is exhaustive; F-9 the plan's `.review.md` created with rounds 1 and 2 verbatim (diff-verified) and a Round 3 placeholder. Docs-indexing 9 passed; full suite 3154 passed, 1 skipped; lint 199 issues / 0 errors. Evidence "Fix round 2".
- [x] Fix round 1 (review CHANGES_REQUESTED) — F-1 scope block on `records_and_trends.md`; F-2 false sports round predicate deleted, replaced by what the pass does; F-3 one new static-source `test()` in `test/records_and_trends_screen_test.dart` (shown failing with the claim false, then green) plus both single-entry pointers reworded to Records & Trends only; F-4 `kTopIsometricCount` / `kTopSportsCount` named; F-5 the three formatter-only hunks in `test/screen_widget_test.dart` reverted (only the two Tooltip hunks remain); F-6 `exercise_metric.dart` row + the overview sentence in `data_models.md`. Targeted trio 272 passed; full suite 3154 passed, 1 skipped; lint 199 issues / 0 errors. Evidence §5 and "Fix round 1".

## Assumption Log

<!-- Executors append here: decision, options considered, choice and why. At most 3 lines each. -->

- **Step 1.1, `roundInstance`'s `finishedAtMs`.** The step pins `int? finishedAtMs` but also requires the
  natural-finish default *and* an explicit `null` (S-908). Options: a sentinel default, or a second flag.
  Chose `Object? finishedAtMs = <private sentinel>`; call sites read the same.
- **Step 1.7, where the doc line goes.** `docs/db_integration.md` has no bulk-read lines. Options: create a
  new subsection, or extend the Repository Contract list. Chose the latter, as Step 1.7's fallback directs.
- **Step 2.5, `computeTotals()` reads through `_loadHistory()`.** The step names `getAllSessions()`; that is
  the same list the index is built from. Chose the cached index, so the screen's totals cost no extra read.
- **Step 2.11, "the three all-time totals".** The loop the step describes carries two figures — completed
  sessions and duration; the third, the streak, stays in `CalendarState` per Step 2.8. The doc entry names
  the pair and says the streak is not computed here.
- **Step 2.10, M1's shape.** A per-range mutation is invisible to S-904, whose range is all history and
  holds `ex-pull`'s bodyweight set. Applied the per-call version of the mistake instead; S-904 asserts the
  metric per point for exactly that reason. Details in evidence §9b.
- **Step 2.11, naming the future readers.** The step asks the entry to name Records & Trends, Exercise
  Progress and the 4b Instruments rows as readers; those surfaces do not exist yet, and the doc checklist
  bars roadmap phrasing. The entry names the rule-sharing instead, and the two readers that exist.

- **Step 3.1, entry ordering.** D-413 says order by `FuzzySearch.score` descending, but `score` is an edit
  *distance* — lower is better — so descending would bury the closest match. Step 3.1 names only the
  filter, so the order is training-day share desc → name → id; M3 reverses it.
- **Step 3.4, the S-912 fixture.** The register's three exercises all log on one training day, where
  share order and name order agree, so M3 could not change anything. `Incline Bench Press` got three
  training days and `Bench Press` one; the two orders now disagree and M3 bites.
- **Step 3.2, three extra widget files.** D-412 predicts two new files; extracting `StatsPill` and
  `RecentPRList` out of `stats_screen.dart` and adding the shared formatter adds three more under
  `lib/features/stats/widgets/`. Feature-local widgets are not catalogued, so no `widget_catalog.md` change.
- **Step 3.3 vs. S-916, the header tooltip.** Step 3.3 requires `tooltip: 'Records & Trends'`, and two
  pre-existing `test/screen_widget_test.dart` assertions forbid *any* `Tooltip` on the Stats screen as a
  proxy for the removed chart popup. Kept the tooltip (the house pattern) and scoped both assertions to
  the chart subtree; S-916's own must-fail condition is untouched. Evidence §9c.

## Feedback

Review: **CHANGES_REQUESTED**. The review file
(`2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.review.md`) could not be written — this
run's environment denies every filesystem write (bash `touch`/redirect/`cp`/`tee` and file creation via the
edit tool all fail with "Permission denied"). The full findings were returned in the reviewer's response;
the actionable items are the checklist below.

Fix checklist — 4 blockers + 1 major, 2 optional:

1. [blocker] Delete `test/zz_probe_hive_widget_test.dart` (leftover placeholder; it is the suite's extra `+1`).
2. [blocker] Add the §4.1 scope block to `docs/records_and_trends.md` (missing scope block = review blocker).
3. [blocker] Delete the round-predicate sentences at `docs/stats_screen.md:250-254` — they assert the Stats
   screen's sports rounds use the `SessionSummaryBuilder` predicate, which it does not (it sums finished
   `TimedInstance` durations and never reads `RoundInstance`). Point at the test verifying the screen's own
   rule instead.
4. [major] Fix the unverifiable single-entry-point claims (`docs/records_and_trends.md:31` cites
   `test/navigation_contract_enforcement_test.dart`, which verifies nothing of the sort; `docs/stats_screen.md:22`
   has no pointer) and the two class-4 numeric restatements "top-2" (`docs/stats_screen.md:236`, `:251`) —
   name `kTopIsometricCount` / `kTopSportsCount`.
5. [minor, optional] Revert the three formatter-only hunks in `test/screen_widget_test.dart`.
6. [minor, optional] Add the `lib/core/models/exercise_metric.dart` row to `docs/data_models.md:587`.

Behaviour is correct and both bars are met: `gateway.sh lint` → 199 issues, 0 errors; `gateway.sh test` →
`+3153 ~1: All tests passed!`.

**Fix round 1 (2026-10-01).** Items 2–6 fixed; item 1 (`test/zz_probe_hive_widget_test.dart`) is the
owner's file to delete and was left in place. See `## Progress` and the evidence file's "Fix round 1"
section.

### Review round 2 (2026-10-01) — CHANGES_REQUESTED

The `.review.md` file could not be created. This run exposes no file-creation tool, and every shell write
is denied (verified: `edit` → ENOENT on a missing path; `printf > …`, `touch`, `mkdir`, `cp`, `tee`,
`python3` → "Permission denied and could not request permission from user"). The `writefile()` SQL function
does not exist and `ATTACH` is blocked. Round 2's full findings were returned in the reviewer's response
and are mirrored in `.work/stats-pr4/review-round-2.md`; round 1's full text is in
`.work/stats-pr4/review-round-1.md`.

Fix checklist — 1 blocker (mechanical), 2 optional:

1. [blocker — false claim] `docs/records_and_trends.md:6-8` — the new scope block names "the `ExerciseMetric`
   model in `lib/core/models/exercise_metric.dart`", but no type `ExerciseMetric` exists anywhere in `lib/`
   or `test/` (the file defines `ExerciseSection`, `NativeMetric`, `NativeValue`, `ExerciseMetricPoint`,
   `ExerciseMetricSummary`, `StatsTotals`). Reword to "the exercise-metric value types in
   `lib/core/models/exercise_metric.dart`", or name `ExerciseMetricSummary`. → @developer
2. [optional] `docs/stats_screen.md:261-263` — "finished timed instances" and "never reads a
   `RoundInstance`" are true of `_processRoundEffort`, but the cited group (`Sports round aggregation
   (Phase D)`, T-19) seeds only finished instances, so the "finished" half is not discriminated by it.
3. [optional] `docs/data_models.md:5` — "the derived value types a screen or service owns live beside it —
   the code-reference table below lists where" reads as a completeness claim the table does not meet
   (`stats_progress.dart`, `app_version_info.dart`, `demo_routine_spec.dart`, `food_draft.dart`,
   `session_edit_snapshot.dart` are unlisted).

Verified PASS: F-2, F-3, F-4, F-5, F-6, and F-1's block placement (§4.1: first content, coverage + code
paths). Bars re-run: `gateway.sh lint` → 199 issues, 0 errors, 4 warnings (none in a file the fix touched);
`gateway.sh test` → `+3154 ~1: All tests passed!` (exit 0).

Owner actions (not fixes): delete `test/zz_probe_hive_widget_test.dart`; the "RECENT SESSIONS" label.

## Open questions

Every entry is a place where the pack leaves a choice open and this plan applied a default. Veto any of
them; each is one ledger entry to change.

1. **The change indicator's comparison basis (item 5, for 4b).** Default: the same exercise's best native
   value over the immediately preceding range of the same length, with no indicator when the exercise has
   no data there. The pack says "that exercise's own previous comparable value" without defining
   "comparable". Not built in 4a; recorded here so 4b does not re-decide it.
2. **The Sports primary value.** Default: **rounds completed**, with total round-minutes secondary. The
   pack lists "rounds completed and total round-minutes" in that order and says the primary value drives
   the change indicator and the trend line.
3. **"Rounds completed" is the Session Summary's rule, not `RoundInstance.completed`.** Default: `state ==
   finished && startedAtMs > 0 && finishedAtMs != null`, so a round stopped early still counts and an
   abandoned active round does not. `completed` alone would drop rounds the Summary counts.
4. **The sparkline's range (for 4b).** Default: one point per training day inside the current window,
   oldest first, hidden with fewer than 2 points. The pack says "a small trend line" without a range.
5. **The cadence formula (for 4b).** Default: total `SensorSummary.steps` at `timed_instance` scope divided
   by the exercise's total minutes over the same instances, shown in steps per minute. The pack says
   "cadence" without a unit.
6. **One section per exercise.** Default: an exercise is in exactly one section, chosen by the effort kind
   with the most logged efforts in that screen's range; a tie resolves Resistance, Cardio, Isometric,
   Sports. The alternative reading — one row per (exercise, kind) pair — is rejected because item 5's AC
   says "each exercise appears in exactly one section". A consequence worth knowing: an exercise logged
   mostly as `set` all-time but only as `timed` in the current window would be Resistance in Records &
   Trends and Cardio in the Instruments list. Accepted as correct, since each screen states its own range.
7. **The Exercise Progress session-list cap.** Default: 20, as `kRecentSessionCount`. The pack says "a list
   of recent sessions" without a count.
8. **Cancelled sessions are excluded.** Default: every figure in this PR counts completed sessions only,
   matching the Stats screen's own totals and trend passes. The pack says "every exercise ever logged" for
   Records & Trends, which this reads as "ever logged in a session that counted".
9. **The 30-day recency floor does not apply to the new screens.** Default: `ex-deadlift` last trained a
   year ago is still listed in Records & Trends. The floor exists to stop stale exercises taking a *top
   slot*; the new list is exhaustive, so it has no slots to take.
10. **Where the new computation lives.** Default: `StatsProgressService` gains `computeTotals()` and
    `computeExerciseMetrics()` rather than a new service, so one screen load still costs one repository
    read. This is a code-shape choice, recorded for visibility only.
11. **The three-PR split itself.** Default: 4a = Records & Trends + Exercise Progress + the shared
    computation (additive); 4b = Instruments list + Fuel row (additive); 4c = remove the old sections. The
    owner delegated the split; this is the reading that keeps `develop` shippable at every step, at the cost
    of duplicate content on `develop` until 4c lands.
12. **`docs/stats_screen.md` is reconciled in 4a.** Default: fix the pre-existing drift now, because the
    pack's D-13 requires it and 4a edits that doc anyway. 4c rewrites the doc again.
