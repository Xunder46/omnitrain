# Feature: Stats PR 3a2 — Entry identity: every edit, delete and distance lands on the chosen entry

> Status: IMPLEMENTED (Iteration 1). Phases 1–3 complete; reviewed with CHANGES REQUESTED, and the
> in-PR findings (F-1–F-5, F-8, F-9, N-1, N-2) fixed in one round.
> Next handoff: owner review of the diff, then merge into `develop`. The findings routed to a follow-up
> PR (F-6, F-7, O-4, the routine-template defaults) are Open Items O-4 to O-7.
> Series: PR 3a2 of the PR 3 series. Index: `.github/agents/plans/2026-09-26-03-stats-pr3-distance-series-index.md`.
> Base: `develop`, which contains PR 3a as commit 4bb4afb (or a re-titled copy with the same tree).
> Branch policy (owner, 2026-09-27): only `develop` and `main` persist. This PR's branch is created by an
> explicit executor step (Step 0b). After review, the owner merges it into `develop` and deletes it.
> Binding conventions: `.github/agents/docs/global_conventions.md`; `CLAUDE.md` ("Verification is observed
> output"); `.github/agents/docs/documentation_standard.md` (every doc edit); `.github/agents/pr_scope_budget.md`.
> Read first: `.github/agents/docs/data_models.md` (observation ids), `.github/agents/docs/distance_source.md`,
> `.github/agents/docs/watch_session_capture.md` (the watch import numbers its own rows),
> `.github/agents/docs/state_management/workout_state.md`.
> Evidence: `2026-09-27-03a2-stats-pr3a2-entry-identity-plan.evidence.md`. It holds the baselines and the
> code facts G1–G13, and executors append to it. Review findings go in `…plan.review.md`.
> Source of scope: PR 3a's Open Item O-3, review findings F-5, F-6, N-3 and N-4, and O-4 (the SQL contract);
> the set-path defects found while planning (G2–G4); the owner's answers of 2026-09-27 (Q1–Q4).
> Scope check (2026-09-27): about 460 lines, 3 phases, one track (the phone), 12 decisions, 18 scenarios,
> about 350 predicted production lines, no missing prerequisite. No soft signal; within budget.

## Overview

**The defect.** An entry's saved rows are found in one of two ways:
- by their position in a list whose order depends on the store. Hive returns `…-10-…` before `…-2-…` (G1).
- by an id built from the entry's current display position, although ids are never renumbered (G4, G5).

So after a session is reopened with 11–12 entries of one exercise, or after a delete, reads and writes can
hit another entry's rows. Findings covered: F-5, F-6, O-3 and N-4 from 3a; the set paths (G2–G4); timed
deletion and adding (G5); duplicated blocks (G9).

**The fix.**
- One entry rule for every phone reader and writer (D-324).
- New rows are numbered past the highest existing number (D-325).
- A delete removes exactly that entry's rows (D-326).
- No stored row is renamed, deleted or migrated otherwise (D-322).

**What users see.**
- Deleting sets or timed entries, live or in Edit Session, removes exactly the chosen entry. A timed entry's
  distance goes with it.
- In a reopened session with 11–12 entries of one exercise, edits, skips and the list order are right.
- A distance typed on the Summary stays with its entry through later deletes and adds.
- A duplicated block's entries can be edited and deleted like any other.

## Resolved Decisions (Ledger)

Immutable; changes are made by superseding entries. D-324 and D-325 bind the rest of the series.

| ID | Decision | Source |
|---|---|---|
| **D-320** | **Q1: the set-path defects are fixed here, each only once proven.** The items:<br>• SP-1: the wrong set is deleted after an earlier delete (S-851, S-852);<br>• SP-2: an edit lands on another set in a reopened 11–12-set session (S-853);<br>• SP-3: the same for a skip (S-854);<br>• SP-4: bodyweight sets 11–12 are out of order after reopening (S-843);<br>• SP-5: a late extra weight's row joins the wrong set (S-857).<br>Each item's scenario is written first and run on unfixed code. An item whose scenario passes there is **DROPPED**: its fix is not made, and Progress and the evidence file record the drop with the passing output. | Owner, 2026-09-27 |
| **D-321** | **Q2: only distances that belong to an entry count.** The Stats daily distance and pace count a distance only when D-324 pairs it with an entry. A leftover never counts. This ratifies 3a review N-3. | Owner, 2026-09-27 |
| **D-322** | **Q3: leftovers stay stored, untouched and ignored.** Nothing in this PR deletes, renames or migrates an existing row, except that deleting an entry deletes that entry's own rows (D-326). | Owner, 2026-09-27 |
| **D-323** | **Q4: PR 2's D-134 and D-135 are confirmed.** They are recorded in the series index and the PR 2 plan. No 3a2 work. | Owner, 2026-09-27 |
| **D-324** | **The entry rule.** Every phone read or write of an entry's rows finds them this way — never by raw list position, never by an id built from a display position.<br>• **Entry number:** the digits just before a metric key at the end of the id, `obs-<effortId>-<n>-<metricKey>`, optionally followed by `-<digits>` (3a's D-313 suffix). Metric keys are the values of `MetricIds.metricIdToKey`. Any other id has no number. One shared parser serves the phone; the watch import keeps its own (O-2).<br>• **Set efforts:** entry k is the k-th group of rows that share an entry number, groups in ascending number. If any of the effort's rows has no number, the effort keeps today's sequential grouping (legacy).<br>• **Timed and hold efforts:** entry k is the timed instance at position k, by `entryIndex`. Its row of each companion metric (distance, extra weight) is the k-th row of that metric. Rows are ordered by entry number, then `createdAtMs`, then id; rows with no number follow in the store's order. A row placed past the last entry is a **leftover** (D-321, D-322).<br>• Supersedes 3a D-312. The order of numbered rows is unchanged; the rule now covers every companion metric and sets. | Claude |
| **D-325** | **Numbering new rows.**<br>• Every new row takes the entry number 1 + the highest among the effort's rows, or 0 when there are none. That covers each new set, timed or hold entry, and every row the distance write creates.<br>• When the distance write fills several unpaired entries (3a D-313's filling), they are numbered upward in entry order.<br>• An extra-weight row created for an existing set takes that set's own number.<br>• No suffix is ever minted, which supersedes 3a D-313's `-<nowMs>` rule (F-5). An existing suffixed id reads as its number. | Claude |
| **D-326** | **Deleting an entry.**<br>• Deleting entry k removes exactly the rows D-324 assigns to it, and nothing else: for a set, the k-th group; for a timed or hold entry, the k-th row of each companion metric, found before the instance is removed.<br>• No row is renamed.<br>• This replaces the id-prefix deletes in `deleteEntry` and `TimerManager.deleteTimedEntry`. A set effort on the legacy fallback keeps today's positional delete. | Claude |
| **D-327** | **One path.**<br>• These go through D-324: `updateEntryValue`, `markSetSkipped`, `deleteEntry`, `TimerManager.deleteTimedEntry`, the distance writes, `ObservationGrouper`'s set grouping, `SessionSummaryBuilder` (set extra weight, timed and hold companions), the Summary's DISTANCE rows and the Stats pace pairing.<br>• `DistancePairing.forEntries` stays, as a thin delegate for its callers and 3a's tests. `entryNumberInId` is removed. | Claude |
| **D-328** | **Distance entries (F-6, N-4).**<br>• One state operation returns an effort's distance entries, each with its row (or none) and its display number. The Summary builds its rows from it, and the distance writes address the same list.<br>• For a timed effort, the entries are its timed instances.<br>• For any other kind (D-319's data-safety clause), they are only the distance rows greater than 0, in D-324 order. "· n" appears only when there are two or more. | Claude |
| **D-329** | **Duplicated blocks.** A copied row's id is its source id with the effort id replaced: `obs-<newEffortId>-<n>-<metricKey>`. A source id with no entry number keeps a fresh unique id. Hive and Mock behave identically. | Claude |
| **D-330** | **SQL contract (O-4).** The value CHECK allows at most one of `value_int`, `value_real`, `value_text`. `value_bool` is a flag the model writes on every row (0 or 1). No model change; a test inserts rows exactly as `toMap` writes them. | Claude |
| **D-331** | **Docs.**<br>• `data_models.md` gains an "Entry identity" relationship section: the rule, the numbering, and the watch import's own numbering, with test pointers.<br>• `distance_source.md` drops the D-313 suffix and defers pairing to that section.<br>• `state_management/workout_state.md`, `session_summary.md`, `stats_screen.md` and `db_integration.md` change only where they describe pairing, deletion, leftovers or the CHECK.<br>• All per `documentation_standard.md`. | Claude |

## Feature Invariants

- **Parity.** Every scenario marked Hive/Mock ends identical on both. Hive is reopened between steps where
  stated.
- **One rule.** No phone code indexes the raw observation list or builds an id from a display position.
  The only phone file that parses an observation id is `lib/core/utils/entry_rows.dart` (S-860; the Phase
  3 residue check).
- **Nothing is rewritten behind the user's back.** No row is renamed or migrated; only a deleted entry's own
  rows are deleted (D-322, D-326).
- **Unchanged:**
  - the watch import (`lib/core/services/watch_session_importer.dart`), and everything under `watch/`,
    `lib/watch/` and `lib/core/sync_protocol/`;
  - the PR definition and the values Stats computes for sets;
  - the effort rating, the calendar, and 3a's D-319 row rule.

## Acceptance Criteria

- **AC-1:** one rule reads every id shape the app has written (S-841) and gives the same entries on Hive and
  Mock at 12 entries (S-842, S-843, S-844).
- **AC-2:** new rows never collide or overwrite (S-845); a 3a suffixed id sits at its number (S-846);
  duplicated blocks stay addressable (S-847).
- **AC-3:** deleting sets or timed entries removes exactly the chosen entry, live and reopened (S-851, S-852,
  S-855, S-856).
- **AC-4:** edits and skips land on the chosen set in reopened 12-set sessions (S-853, S-854); a late extra
  weight joins its own set (S-857).
- **AC-5:** leftovers never show, never count and stay stored (S-858).
- **AC-6:** the Summary's rows and its writes agree, and a lone legacy row carries no number (S-859).
- **AC-7:** a scripted add, delete and edit sequence on 12-entry efforts, reopened between steps, ends
  identical on Hive and Mock and matches the expected list (S-860).
- **AC-8:** every row the app writes fits the SQL contract (S-861).

## Scenarios

**Shared fixtures.**
- **FX-12SETS:** set effort `e-row`, on exercise `ex-row` "Row", which has `load`. 12 sets with rows
  `obs-e-row-<n>-reps` = n+1 and `obs-e-row-<n>-weight` = 10(n+1) kg, for n = 0–11, created in order
  (`createdAtMs` = 1000 + n).
- **FX-12PULL:** set effort `e-pull`, on `ex-pull` "Pull-up", which has no `load`. 12 sets with reps = n+1,
  weight 0 and extra weight = n kg (ids `obs-e-pull-<n>-{reps,weight,extra-weight}`).
- **FX-12TIMED:** timed effort `e-run`, on `ex-run` "Easy Run". 12 finished instances (`entryIndex` 0–11, 60 s
  each), with `obs-e-run-<n>-distance` = (n+1)×100 m and `obs-e-run-<n>-extra-weight` = n kg.
- **Reopened:** rows stored on Hive, the repository closed and reopened, then `loadHistoricalSession`
  (harness G13).
- **Mock:** the same rows in Mock, loaded the same way.
- **Live:** built through `WorkoutState` in the test (`createNewSession`, `addExerciseToSession`,
  `addEntry`).

### Scenarios for Phase 1: the rule and new-row numbering

#### S-841: Every id shape reads its number
- Fixture (pure): `obs-e1-3-reps`, `obs-e1-3-extra-weight`, `obs-e1-3-round-duration`,
  `obs-effort-1727000000000-0-11-weight`, `obs-e1-4-distance-1727000000123`, `obs-e1-x-reps`, and a UUID.
- Expected: 3, 3, 3, 11, 4, none, none.

#### S-842: 12 weighted sets read the same on Hive and Mock
- Fixture: FX-12SETS in a completed session; Reopened and Mock.
- Expected: the grouper's entry k is reps k+1 and weight 10(k+1), for k = 0–11, on both. Green before and
  after; it guards weighted sets against the change.

#### S-843: 12 bodyweight sets group by number (SP-4)
- Fixture: FX-12PULL; Reopened and Mock.
- Expected: the grouper's entry k is reps k+1 and extra weight k, on both.
- Red today on Hive: the order is 0, 1, 10, 11, 2, … (the sequential fallback, G3).

#### S-844: 12 timed entries pair their companions by the rule
- Fixture: FX-12TIMED; Reopened and Mock.
- Expected: the rule pairs entry k with distance (k+1)×100 m and extra weight k, on both.

#### S-845: New rows never collide
- Fixture: Live, on Mock and on Hive. Timed effort `e-t` with 3 entries: distances 1000, 2000 and 3000
  `entered`, rows numbered 0–2.
- Trigger: `deleteEntry('e-t', 0)`, then `addEntry('e-t')`.
- Expected, read back from the repository: the new entry's rows are `obs-e-t-3-distance` and
  `obs-e-t-3-extra-weight`; rows -1- and -2- still hold 2000 and 3000; the entries pair [2000, 3000, 0].
- Red today: the add mints number 2 and overwrites the stored 3000 m row. The in-memory list keeps a stale
  duplicate, so assert on the repository's rows.

#### S-846: A 3a suffixed id sits at its number (F-5)
- Fixture: Reopened and Mock. Timed effort `e-f5` on "Easy Run", with 5 finished instances and distance
  rows, `createdAtMs` in the order listed:
  - `obs-e-f5-1-distance` 0.0, `obs-e-f5-2-distance` 0.0, `obs-e-f5-3-distance` 0.0;
  - `obs-e-f5-3-distance-9000` 2000.0 `entered`;
  - `obs-e-f5-4-distance` 0.0.
- Expected: the paired distances are [0, 0, 0, 2000, 0].
- Red today: [0, 0, 0, 0, 2000]; the suffixed row sorts last.

#### S-847: Duplicated blocks stay addressable
- Fixture: a rolling session, on Mock and on Hive. Block `b-1` holds set effort `e-s` (3 sets, reps 5, 6 and
  7, rows numbered 0–2) and timed effort `e-d` (2 entries, 1000 and 2000 m `entered`).
- Trigger: `cloneSessionBlock('b-1')`; then set the copy's set entry 1 to reps 60.
- Expected:
  - every copied row is named `obs-<newEffortId>-<n>-<metricKey>`, with the source's n, value and source;
  - the copy's sets read 5, 60 and 7, and the source's sets are unchanged;
  - the copy's distances pair [1000, 2000].
- Red today: the copied ids are random UUIDs.

### Scenarios for Phase 2: writes, deletes and the remaining readers

#### S-851: Deleting two sets removes the chosen ones, live (SP-1)
- Fixture: Live Resistance session, on Mock and on Hive. `ex-bench` "Bench Press" (with `load`), three sets
  logged with reps 5, 6 and 7.
- Trigger: `deleteEntry(e, 0)`, then `deleteEntry(e, 1)`. The second call targets reps 7, the second of the
  two remaining sets.
- Expected: one set left, with reps 6.
- Red today (code reading, G4): reps 7 is left.

#### S-852: The same on a reopened session (SP-1)
- Fixture: a completed session with those three sets; Reopened and Mock.
- Trigger: the same two deletes; restart; reload.
- Expected: one set, reps 6, after the restart too.

#### S-853: An edit in a reopened 12-set session lands on its set (SP-2)
- Fixture: FX-12SETS completed; Reopened and Mock.
- Trigger: `updateEntryValue('e-row', 2, 'reps', 99)`, as Edit Session's save calls it; restart; reload.
- Expected: row -2- reads 99, and row -10- still reads 11, on both.
- Red today on Hive: row -10- reads 99.

#### S-854: A skip in a reopened 12-set session (SP-3)
- Fixture: FX-12SETS; Reopened and Mock.
- Trigger: `markSetSkipped('e-row', 2)`.
- Expected: row -2- has reps 0 and is marked skipped; row -10- is untouched.
- Red today on Hive: row -10- is changed instead.

#### S-855: Deleting the first timed entry twice keeps each distance with its entry
- Fixture: a completed Cardio session; Reopened and Mock. Timed effort `e-run4`, "Easy Run", with 4 finished
  entries: distances 1000, 2000, 3000 and 4000 `entered`, extra weights 0.
- Trigger: `deleteEntry('e-run4', 0)`, twice.
- Expected:
  - two entries remain, pairing [3000, 4000];
  - the effort holds exactly 2 distance rows and 2 extra-weight rows;
  - the Summary shows `Easy Run · 1` `3.00` `KM` and `Easy Run · 2` `4.00` `KM`.
- Red today: the second delete removes no row, so the 2000 m row pairs with entry 0 and gives [2000, 3000].

#### S-856: 3a's F-5 sequence, live and reopened
- Fixture: Live Cardio session, on Mock and on Hive. "Easy Run" with 4 entries, all distances 0.
- Trigger:
  - `deleteEntry(0)`, then `addEntry`;
  - set entry 3 (the new "· 4") to 2000 m;
  - `addEntry` again;
  - on Hive, restart and `loadHistoricalSession`.
- Expected:
  - entry 3 holds 2000 m `entered`, and entry 4 has no distance;
  - no id carries a suffix, and the distance row numbers are unique;
  - the Summary shows `Easy Run · 4` `2.00` `KM` and `Easy Run · 5` `—`.
- Red today: the first add overwrites a row (G5), so the 2000 m is not on "· 4". By code reading it lands
  on "· 3"; assert only the expected result.

#### S-857: A late extra weight joins its own set (SP-5)
- Fixture: a completed session; Reopened and Mock. Bodyweight set effort `e-dip`, "Dip", with rows for set
  numbers 0 and 2 only (a gap from an old delete). Each set has reps and weight rows; only set 0 has an
  extra-weight row.
- Trigger: `updateEntryValue('e-dip', 1, 'extra-weight', 5.0)`. Entry 1 is set number 2.
- Expected: `obs-e-dip-2-extra-weight` = 5.0 is created; the effort shows two sets, the second with extra
  weight 5.0.
- Red today: the created id is `obs-e-dip-1-extra-weight`.

#### S-858: Leftovers never show, never count, and stay stored (D-321, D-322)
- Fixture: a completed Cardio session dated 1 day ago. Timed effort `e-lo`, "Easy Run": 1 finished instance
  (1800 s); distance rows `obs-e-lo-0-distance` 5000.0 and `obs-e-lo-7-distance` 1000.0 (a leftover).
- Trigger: open the Summary; set the one entry to 5.5; open Stats. The widget run is on Mock; the Hive
  storage check runs at the state layer.
- Expected:
  - the Summary shows one row, `Easy Run` `5.50` `KM`;
  - Stats reads `Distance: 5.50 km` and `Pace: 327 s/km`;
  - `obs-e-lo-7-distance` is still stored at 1000.0.
- Green before and after: it pins D-321 and D-322.

#### S-859: The Summary's rows and writes agree; a lone legacy row has no number (F-6, N-4)
- Fixture: a completed `isometric_stretching` session on Mock. Drill `Plank` (two holds), with legacy
  distance rows `obs-e-pl-0-distance` 0.0 and `obs-e-pl-1-distance` 400.0.
- Trigger: open the Summary; tap `Plank`; enter `0`; Ok.
- Expected:
  - before: exactly one row, named `Plank` (not `Plank · 2`), showing `0.40` `KM`;
  - after: row -1- is 0.0 with no source, row -0- is untouched, and the DISTANCE section is gone.
- Red today: the row reads `Plank · 2`.

#### S-860: The class guard — a scripted sequence ends identical on Hive and Mock
- Fixture: FX-12SETS and FX-12TIMED in one completed session; Reopened and Mock. On Hive, restart and
  reload after every step.
- Trigger:
  1. delete set entry 0;
  2. delete set entry 5;
  3. set set entry 1's reps to 77;
  4. add a set (defaults: reps 10);
  5. skip set entry 3;
  6. delete timed entry 0;
  7. delete timed entry 0;
  8. set timed entry 2's distance to 2500 m;
  9. add a timed entry.
- Expected, on both:
  - set reps [2, 77, 4, 0, 6, 8, 9, 10, 11, 12, 10], with entry 3 skipped;
  - timed distances [300, 400, 2500, 600, 700, 800, 900, 1000, 1100, 1200, none];
  - every surviving row is exactly the one the sequence left: `obs-e-row-<n>-{reps,weight}` for n in
    {1, 2, 3, 4, 5, 7, 8, 9, 10, 11}, the added set 12 with its own `-extra-weight` row, and
    `obs-e-run-<n>-{distance,extra-weight}` for n in 2…12; no row of a deleted entry remains.

### Scenario for Phase 3: the contract

#### S-861: Every row the app writes fits the SQL contract (O-4)
- Fixture: `EffortObservation.toMap()` rows for a reps row (8, not skipped), a skipped reps row (0), a weight
  row (60.0), a distance row (4873.6, `estimated`) and an extra-weight row (5.0); plus one row with both
  `value_int` and `value_real` set.
- Trigger: insert each into `test/db_seed_test.dart`'s in-memory schema.
- Expected: the five app rows insert as written, and the mixed row is refused.
- Red today: all five are refused.

### Scenarios for the review round (F-4, F-5)

#### S-862: A set reads its own added weight (F-5)
- Fixture (Reopened and Mock): a bodyweight effort of 3 sets, reps 1–3, weight 0, extra weight stored for
  sets 1 and 2 only (1 kg and 2 kg).
- Trigger: read the session list's entries.
- Expected, on both: added weight [none, 1, 2] — the same figures Stats and the PR read.
- Red before the fix: [1, 2, 2], because the overlay paired added weight by row position.

#### S-863: A hold reads its own added weight (F-4)
- Fixture: a `drill` effort of 2 holds with a legacy distance row at number 0 and a stored extra-weight row
  at number 1 holding 7 kg.
- Trigger: type 5 kg on hold 2.
- Expected, on both: the 7 kg row is untouched, a new row at number 2 holds 5 kg, and the holds read
  [7, 5].
- Red before the fix: the new row took number 1 and overwrote the 7 kg (holds read [5, nothing]).

#### S-864: The later of two row-less holds keeps its value (F-4)
- Fixture: a `drill` effort of 2 holds whose only row is a distance row at number 0.
- Trigger: type 5 kg on hold 2.
- Expected, on both: hold 1 gets a zero row and hold 2's own row holds 5 kg (holds read [0, 5]).
- Red before the fix: the row took the next free number and hold 1 showed the 5 kg.

## Iteration 1

**Executor block (Copilot, local).**
- **Step 0a — preconditions. STOP and report if any fails.**
  - `git branch --show-current` prints `develop`.
  - `git status --short` prints nothing outside `.github/agents/plans/` (uncommitted plan files are expected;
    they carry over to the branch and are committed with this PR).
  - `develop` contains PR 3a: `git merge-base --is-ancestor 4bb4afb develop` exits 0. If the owner
    re-titled that commit, `git log --format='%h %T' develop | grep "$(git rev-parse '4bb4afb^{tree}')"`
    finds it instead.
- **Step 0b — branch:** `git switch -c feature/stats-pr3a2-entry-identity`, cut from `develop`. Record it in
  the evidence file.
- **Step 0c — baseline:** `flutter test > /tmp/pr3a2_base.log 2>&1; echo "exit $?"; tail -2
  /tmp/pr3a2_base.log` must end with `+3052 ~1: All tests passed!`. Record it together with
  `flutter analyze`'s tail.
- **Branch policy:**
  - commit on this branch only if the owner asks;
  - never merge, push or delete a branch. After review, the owner merges into `develop` and deletes the
    branch.
- **Scope and runs:**
  - work one phase at a time, and stop when its Done Criteria are green;
  - redirect suite output to a log and read only its tail;
  - a run that hangs for 10 minutes is a failure.
- **Red before green:** show each new test red on unfixed code: copy the changed source file aside, revert
  the change in place, run, restore the copy, run again; record both results in the evidence file. Never
  `git stash` here (this checkout holds older stashes; a pop after an empty push applies one of them).
  Writing the test before the fix is the simplest way to get the red run.
- **D-320 gate:** in Phase 1 write S-843 first, and in Phase 2 write S-851–S-854 and S-857 first. Run them on
  unfixed code before fixing anything. Any scenario that passes there: mark its SP item DROPPED in Progress,
  quote the passing output in the evidence file, and make no fix for it.
- **Existing tests:** never loosen an existing assertion. If one must change, record the old and new
  assertion and the D-id that forced it in the evidence file.
- **Ambiguity:** decide, then log it in the Assumption Log (3 lines at most).
- **Test style:** plain `test()` for state tests.
- **Conventions:** state uses the `WorkoutRepository` interface only; use theme tokens; nothing listed under
  "Unchanged" is touched.

### Phase 1: The entry rule and new-row numbering (Copilot)

1. [x] New `lib/core/utils/entry_rows.dart` (pure Dart): the D-324 parser, set grouping, companion pairing
   and leftovers. `DistancePairing` in `lib/core/utils/distance_source.dart` delegates to it. Remove
   `entryNumberInId`.
2. [x] `lib/core/utils/observation_grouper.dart`: set grouping uses the shared parser, so `…-extra-weight`
   rows group by number. The sequential fallback stays for efforts whose rows don't all carry a number.
3. [x] `lib/state/workout/session_core_entry.dart`: D-325 numbering in `addEntry` (sets, timed, hold) and in
   the distance write's fill and create path. `_nextSetEntryIndex` uses the shared parser. No suffix.
4. [x] `cloneSessionBlock` in `lib/data/repositories/hive_workout_repository.dart` and
   `lib/data/repositories/mock_workout_repository.dart`: D-329 copied ids.
5. [x] New `test/helpers/repository_harness.dart`: the `_Harness`/`_MockHarness`/`_HiveHarness` pattern from
   `test/distance_source_test.dart:30-120`, plus seeders for FX-12SETS, FX-12PULL and FX-12TIMED. New
   `test/entry_rows_test.dart`: S-841–S-847 on Mock and Hive.
6. [x] Docs: the `data_models.md` "Entry identity" section (rule, numbering, pointers to S-841–S-847), and
   the `distance_source.md` pairing and suffix text (D-331).

**Red → green.**
- S-843 fails on Hive with order 0, 1, 10, 11, … (D-320 gate for SP-4).
- S-845 fails because the stored 3000 m row is overwritten.
- S-846 fails: [0, 0, 0, 0, 2000].
- S-847 fails because of the UUID ids.
- S-841 and S-844 fail until item 1 exists.
- S-842 is green before and after.

**Done Criteria:**
- `flutter test test/entry_rows_test.dart test/distance_source_test.dart test/utils_test.dart >
  /tmp/pr3a2_p1.log 2>&1; echo "exit $?"; tail -2 /tmp/pr3a2_p1.log` → exit 0.
- `flutter test > /tmp/pr3a2_full.log 2>&1` → exit 0, `+N ~1: All tests passed!` with N ≥ 3052 plus the new
  tests; the skip count stays 1.
- `flutter analyze > /tmp/pr3a2_an.log 2>&1` → at most 242 issues and 0 errors; each touched file at or
  below its evidence §1 ceiling.
- `git diff --name-only develop` stays within the Predicted Files.

**Predicted Files:** `lib/core/utils/entry_rows.dart` (new); `lib/core/utils/distance_source.dart`;
`lib/core/utils/observation_grouper.dart`; `lib/state/workout/session_core_entry.dart`;
`lib/data/repositories/hive_workout_repository.dart`; `lib/data/repositories/mock_workout_repository.dart`;
`test/helpers/repository_harness.dart` (new); `test/entry_rows_test.dart` (new);
`.github/agents/docs/data_models.md`, `distance_source.md`; the evidence file.

### Phase 2: Writes, deletes and the remaining readers go through the rule (Copilot)

1. [x] `lib/state/workout/session_core_entry.dart`: `updateEntryValue` and `markSetSkipped` address entry k
   by D-324. A set's missing extra weight is created with that set's number (D-325). The legacy fallback is
   kept.
2. [x] `deleteEntry` (sets) in `session_core_entry.dart`, and `TimerManager.deleteTimedEntry` in
   `lib/state/workout/timer_manager.dart`: D-326.
3. [x] `lib/state/workout/session_summary_builder.dart`: the set extra-weight overlay, the timed companions
   and the hold companions are paired by D-324.
4. [x] D-328 distance entries: one operation in `session_core_entry.dart`, delegated from
   `lib/state/workout/workout_state.dart`. `lib/features/session/session_summary_screen.dart` builds its rows
   from it; the distance writes use the same list; `_distanceEntryCount` is removed.
5. [x] `lib/core/services/stats_progress_service.dart`: the pace pairing goes through D-324, with leftovers
   excluded (D-321).
6. [x] New `test/entry_identity_test.dart` (plain `test()`, Mock and Hive): S-851–S-857, S-860, and the
   state half of S-858.
7. [x] New `test/entry_identity_summary_test.dart` (widgets, Mock): the Summary checks of S-855 and S-856,
   S-858, and S-859.
8. [x] Docs: `state_management/workout_state.md`, `session_summary.md` (legacy-row naming) and
   `stats_screen.md` (leftovers don't count), per D-331.

**Red → green.**
- D-320 gate first: S-851, S-852 (SP-1), S-853 (SP-2), S-854 (SP-3) and S-857 (SP-5) must fail on unfixed
  code with the failures stated in their scenarios. Otherwise the item is DROPPED.
- S-855 fails, pairing [2000, 3000].
- S-856 fails because the 2000 m is not on "· 4".
- S-859 fails, reading `Plank · 2`.
- S-860 fails on Hive at step 2 or later.
- S-858 is green before and after.

**Done Criteria:**
- `flutter test test/entry_identity_test.dart test/entry_identity_summary_test.dart test/state_test.dart
  test/session_summary_distance_test.dart test/stats_distance_estimate_test.dart
  test/watch_session_edit_restore_summaries_test.dart > /tmp/pr3a2_p2.log 2>&1` → exit 0.
- The full suite and the analyzer run as in Phase 1: `session_summary_screen.dart` at 10 issues or fewer,
  `session_core.dart` at 1 or fewer.
- The diff stays within the Predicted Files.

**Predicted Files:** `lib/state/workout/session_core_entry.dart`; `lib/state/workout/timer_manager.dart`;
`lib/state/workout/session_summary_builder.dart`; `lib/state/workout/workout_state.dart`;
`lib/features/session/session_summary_screen.dart`; `lib/core/services/stats_progress_service.dart`;
`test/entry_identity_test.dart` (new); `test/entry_identity_summary_test.dart` (new);
`.github/agents/docs/state_management/workout_state.md`, `session_summary.md`, `stats_screen.md`; the
evidence file.

### Phase 3: Contract, docs and residue (Copilot)

1. [x] `scripts/sqlite_schema.sql`: the D-330 CHECK. `test/db_seed_test.dart`: S-861.
2. [x] `.github/agents/docs/db_integration.md`: the CHECK line (D-331).
3. [x] Residue check:
   - `grep -rln "RegExp(r'obs-" lib` lists only `lib/core/utils/entry_rows.dart`;
   - `grep -rn "entryNumberInId\|_distanceEntryCount\|-\$atMs" lib` finds nothing.

**Red → green.** S-861 fails today, because all five app rows are refused.

**Done Criteria:**
- `flutter test test/db_seed_test.dart test/docs_indexing_contract_test.dart > /tmp/pr3a2_p3.log 2>&1` →
  exit 0.
- The full suite and the analyzer run as in Phase 1.
- The residue greps come back as stated.
- The diff stays within the Predicted Files.

**Predicted Files:** `scripts/sqlite_schema.sql`; `test/db_seed_test.dart`;
`.github/agents/docs/db_integration.md`; the evidence file.

## Files Affected (whole feature)

The union of the three Predicted Files lists. Existing tests change only by gaining cases
(`test/db_seed_test.dart`), unless an assertion encoded a defect this PR fixes. Any such change is recorded
with its D-id.

## Notes

- **Dependency graph:** 1 → 2 → 3. Phase 2 needs Phase 1's rule and numbering. Phase 3 is independent, and
  could run first if needed.
- **Intermediate states:**
  - After Phase 1, set readers and new-row numbering follow the rule, while writes and deletes are still
    positional. That mismatch already exists today for weighted sets. The PR lands as a whole.
  - After Phase 2, every phone path follows the rule.
- **Existing data:**
  - Sets with gaps and 3a-suffixed ids read correctly.
  - A leftover already in old data is paired by the rule and can't always be told apart from a real row. The
    rule decides, and nothing is deleted (D-322).
- **Watch import compatibility:** the import numbers its own rows densely and appends at the highest number
  plus 1 (G10), which is compatible with D-325. 3b re-verifies this and converges the parsers (O-2).
- **Non-goals:**
  - the importer and the watch;
  - EntryRest records;
  - template targets;
  - 3a's test-fidelity nits (review N-5).

## Open Items

- **O-1 — Re-titling 4bb4afb.** The owner may re-title the commit; Step 0a allows for it.
- **O-2 — For 3b: converge the watch import's id parser** (`_observationsByIndex`, G10) on
  `entry_rows.dart`, and re-verify importer top-ups after phone deletes (with PR 2 O-17).
- **O-3 — `develop` is 1 commit ahead of origin.** Copilot runs locally, so this doesn't block. The owner
  pushes when they choose.
- **O-4 — `TimerManager.addTimedEntry` can mint an instance id it already holds.** The id is
  `timed-<effortId>-<index>-<ms>`, so an add after a delete collides when both calls land in the same
  millisecond: the stored instance is overwritten and the effort ends one instance short. Found by S-856
  on Hive after a restart; needs its own design (the id is derived by `WatchSessionImporter`), so it is
  out of this PR. New phase for 3b. S-856 now waits 2 ms before the add that would collide.
- **O-5 — For the follow-up PR (review F-6): a copied block can leave a row the next add adopts.**
  `cloneSessionBlock` copies every row, leftovers included, so a copied effort can carry an unpaired row
  that a later add's numbering steps onto (a 2000 m distance moving from entry 4 to entry 3). Needs a
  decision about what a copy does with a leftover.
- **O-6 — For the follow-up PR (review F-7): a number group with no reps row counts as a set.**
  `EntryRows.setGroups` counts every numbered group, so a weight-only group shows as an empty set. Needs a
  rule for which groups are entries.
- **O-7 — For the follow-up PR (review F-1): the routine-template defaults build and read their own ids.**
  Save-as-routine rebuilds ids from entry positions, outside the rule; fold it in when the follow-up
  touches the template path.

## Progress

Baselines (evidence §1): 3052 passed, 1 skipped; analyzer 242 issues, 0 errors; Swift 242 (untouched).

- [x] Step 0: preconditions, branch and baseline — branch `feature/stats-pr3a2-entry-identity`, cut from
      `develop` (contains 4bb4afb); baseline reproduced exactly (`+3052 ~1`, analyzer 242)
- [x] Phase 1: entry rule, numbering and duplicated blocks — **Complete** (SP-4 fixed; evidence §3)
- [x] Phase 2: writes, deletes and readers — **Complete** (SP-1, SP-2, SP-3, SP-5 each reproduced and
      fixed; none dropped; evidence §3)
- [x] Phase 3: contract, docs and residue — **Complete** (`+3091 ~1`, analyzer 242; evidence §3)
- [x] Review: `/code-reviewer` — **CHANGES REQUESTED** (findings in `…plan.review.md`)
- [x] Review fixes: F-1–F-5, F-8, F-9, N-1, N-2 — **Complete** (evidence §4)

Suite after the whole PR and the review round: `flutter test` → `01:27 +3097 ~1: All tests passed!` (exit 0);
`flutter analyze` → 241 issues, 0 errors. Every phase's and every fix's red run is recorded in the
evidence file (§3, §4).

## Assumption Log

<!-- Executors append here: decision, options considered, choice and why. At most 3 lines each. The
     reviewer marks each entry RATIFIED (promoted to a D-3xx) or REVERT. -->

1. **Timed and hold companions moved to Phase 1.** Options: leave them for Phase 2 as planned, or route
   them with the rule now. Chose now, because S-844 was red on Hive for the same store-order reason as
   S-843, so leaving it would have left two phases sharing one defect. (Copilot, 2026-09-27)
2. **The legacy fallback keys on "any row unnumbered", not "the metric row is unnumbered".** Chose the
   effort-wide reading the grouper used over D-324's literal per-row reading, so reader and writer cannot
   disagree about whether an effort is addressable. (Copilot, 2026-09-27)
3. **`_getMetricsPerEntry` is retained** for the legacy positional delete only. Options: delete it with
   the id-prefix path, or keep it for the fallback D-326 preserves. Chose keep. (Copilot, 2026-09-27)
4. **S-856's reopened half waits out O-4.** The instance-id collision in Open Items is out of scope, so the
   test puts a 2 ms gap before the add that would collide and then asserts the full five-entry list on the
   reopened session. (Copilot, 2026-09-27)

## Feedback

Review (2026-09-27): `2026-09-27-03a2-stats-pr3a2-entry-identity-plan.review.md` — **CHANGES REQUESTED**.
Follow-ups are in its §8 and Assumption Log rulings in its §9. Fixed in this PR, in one round, no re-review;
the red→green runs are in evidence §4.

- [x] F-1 `data_models.md:513-515`: delete the "one place" and "every reader and writer" clauses; point at tests.
- [x] F-2 `stats_best_load_investigation.md:587-593`: delete open question 5; point at `entry_rows_test.dart` S-843.
- [x] F-3 add test pointers to `workout_state.md:103/106/203` (fix :203's cells) and `data_models.md:532-534` (A-51); widen `distance_source.md`'s scope.
- [x] F-4 `session_core_entry.dart:273-276, :371`: hold/timed extra weight numbered past the highest, with fill; S-863, S-864 (Mock and Hive).
- [x] F-5 `session_summary_builder.dart:394-404`: a numbered set reads its own extra-weight row; S-862 (Mock and Hive).
- [x] F-8 `_clonedRowId` (Hive, Mock): keep a source id's suffix; S-847 gained a suffixed row.
- [x] F-9 tighten S-847 (timed copy ids), S-855 (named rows), S-856 (reopened half, full list) and S-860 (row ids).
- [x] N-1 and N-2: the stale Stats comment; plan and evidence hygiene, and the unused `db_seed_test.dart` parameter.

- [x] F-1 `data_models.md:513-515`: delete the "one place" and "every reader and writer" clauses; point at tests.
- [x] F-2 `stats_best_load_investigation.md:587-593`: delete open question 5; point at `entry_rows_test.dart` S-843.
- [x] F-3 add test pointers to `workout_state.md:103/106/203` (fix :203's cells) and `data_models.md:532-534` (A-51); widen `distance_source.md`'s scope.
- [x] F-4 `session_core_entry.dart:273-276, :371`: hold/timed extra weight numbered past the highest, with fill; add probe E's scenario, Mock and Hive.
- [x] F-5 `session_summary_builder.dart:394-404`: a numbered set reads its own extra-weight row; add probe A's scenario, Mock and Hive.
- [x] F-8 `_clonedRowId` (Hive, Mock): keep a source id's suffix; add a suffixed row to S-847.
- [x] F-9 (optional) tighten S-847, S-855, S-856 (reopened half) and S-860 (review §7).
- [x] N-1 and N-2: the stale Stats comment; plan and evidence hygiene (review §7).
