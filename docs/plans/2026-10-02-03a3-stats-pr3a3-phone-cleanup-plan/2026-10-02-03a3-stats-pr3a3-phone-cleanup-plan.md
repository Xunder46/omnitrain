# Feature: Stats PR 3a3 — phone-only cleanup

> Status: READY — Iteration 1 active
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md` (read first). Also binding for this PR:
> `docs/documentation_standard.md`, `docs/data_models.md` § Entry Identity and § `valueSource`,
> `docs/distance_source.md`, `docs/session_summary.md`, `docs/state_management/workout_state.md`,
> `docs/README.md`, `.github/agents/pr_scope_budget.md`.
> Evidence: `2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.evidence.md` (baselines, greps).
> Findings: `2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.review.md` (reviewer only).
> The owner works directly on `develop`. Executors never commit, stage, merge or push.
> Executors have `create`, `edit`, read tools and `gateway.sh` (`list`, `lint`, `test [paths]`,
> `format <paths>`, `pub-get`, `git-status`, `git-diff`, `git-log`, `git-show`) — no plain git, no
> grep, and no way to delete or move a file. Anything to delete goes in **Governor actions** below.

## Overview

Stats PR 3a/3a2/3b built one rule for entry identity and one for distance sources. PR 3a3 removes
the rules the phone can no longer reach: the fallbacks and legacy representations that only the
retired SQLite runtime or a hand-edited box could produce. Nothing a user can do changes.
The handoff's *missing-row filling* item is **withdrawn**: entry pairing is positional among an
effort's rows of one metric, so the fill is what keeps a later entry's value on its own row — it is
live phone behaviour, not old-data handling (D-712).
The phone's own writes keep producing exactly the same rows, the Summary and Stats keep showing the
same numbers, and the watch import's rules are untouched.

Three housekeeping items ride along: two class docs that describe callers that no longer exist, and
the PR 3 series index, which still says 3b is READY.

**Budget.** 3 phases, 1 track (@developer — no schema, model, repository, migration or seed change),
13 ledger entries (D-707 superseded by D-712), 19 scenarios, ~110 predicted production lines.
Inside the soft budget in `.github/agents/pr_scope_budget.md` §1.

**Explicitly out of scope** (recorded, not done — see § Out of scope).

## Resolved Decisions (Ledger)

**D-701.** A distance row that holds a value always carries a source; a zero distance carries none,
because zero is absence. Nothing resolves a missing source for display: `DistanceSource.resolve` is
deleted and `isEstimated` is the only reader of a stored source. The import's wire rule (an absent
source on the wire means `entered`) is unchanged — it is 3b's, not this PR's.

**D-702.** `addEntry` never carries a distance forward. `previousValues['distance']` is not read; a
new timed entry starts at 0 m with no source. Carry-forward stays for reps, weight, duration, extra
weight and round duration. This is the last path that could create a positive distance row with no
source, so D-701 holds only together with it.

**D-703.** A distance entry exists only on a `timed` effort. `EntryRows.distanceEntries` takes rows
and an entry count and returns one entry per numbered distance row; `WorkoutState.
getEffortDistanceEntries` returns an empty list for any other effort kind. The 3a safety clause "a
stored distance is never hidden" is withdrawn: a distance row stored on a non-timed effort (only a
hand-edited box can hold one) is not shown, not counted, and not deleted.

**D-704.** No id carries a suffix. An id is `obs-<effortId>-<n>-<metricKey>` exactly. A suffixed id
therefore carries no number, which by D-705 means it belongs to no entry. No writer mints one, so
this only affects rows that already exist. Supersedes 3a D-313's optional `-<digits>`.

**D-705.** A row whose id carries no number belongs to no entry. `EntryRows.setGroups` groups the
numbered rows only; an unnumbered row is in no group and is ignored by every reader, but it stays
stored. `SetRows.number` is non-nullable and `_sequentialGroups` is deleted. `ordered`/`_compareByEntry`
keep a total order over any list (an unnumbered row sorts last) because a copied block can produce
one — only the wording changes.

**D-706.** Every entry is addressed by its number; there is no positional fallback.
`_entriesAreNumbered` is deleted (a `round` effort holds no rows, so the set lookup already returns
null for it). `_rowIndexEntryOwns` is: `timed`/`drill` → the entry's own companion row; anything
else → the row of the set numbered *k*. `deleteEntry` deletes the rows of the set the caller chose
and returns when there is no such set. `SessionCore._getMetricsPerEntry` is deleted with its only
caller.

**D-707. SUPERSEDED by D-712 — do not build against this entry.** `_fillEntriesBefore` is deleted.
Both of its call sites number the row they write with `EntryRows.nextNumber(observations)`; a write
never creates rows for other entries.

**D-708.** A routine draft reads each entry's own row. `buildTemplateDraftExercises`' `timed` and
`drill` branches take entry 1's extra-weight row from `EntryRows.companions`, never the first raw row
in store order; its set branch keeps reading `EntryRows.setGroups`, never a `createdAtMs` sort. The
branch adds and removes no target: no distance target is added to a timed or drill template.

**D-709.** The words "leftover" and "legacy" leave the distance and entry-identity vocabulary in
`lib/` and `docs/`; the text describes the app's own rules. Every behaviour sentence names a test
that exists after this PR (`docs/documentation_standard.md`); no line numbers, hex values or roadmap
phrases. Test *names* are not renamed — the `S-` id is the stable handle.

**D-710.** Housekeeping is doc-only: `scrollable_trend_chart.dart`'s class doc names its real
callers, `food_catalog_loader.dart`'s doc names the one repository that loads the asset plus the seed
generator, and the series index records 3a, 3a2, 3b and PR 4 as done with 3a3 in progress and 3d's
plan path.

**D-711.** `ObservationGrouper.groupByEffortKind`'s `default:` branch stays: a `switch` on `String`
needs a total branch, and `test/utils_test.dart` pins it as dispatch behaviour. Only its comment
changes. The `timed` and `drill` arms of that switch are **live** — they are the positional pairers
(`for (i = 0; i < observations.length; i += 2)`, pairing by metric check) that build the Summary's
timed/drill entries, the routine draft and Stats' volume, and they ignore the entry rule entirely.
They are the brief's item 8 "outside the entry rule" surface and are **not** touched by this PR: the
only entry-rule reader this PR changes is the routine draft's extra-weight read (D-708). The `round`
arm is the one dead pairer — a `round` effort's entries come from `RoundInstance` records, never from
rows — and it is recorded under § Out of scope, not deleted.

**D-712 (supersedes D-707).** `_fillEntriesBefore` **stays** in
`lib/state/workout/session_core_entry.dart`, exactly as at HEAD, with both call sites unchanged
(`updateEntryValue`'s extra-weight branch and `setEntryDistance`). Entry pairing is positional among
an effort's rows of one metric, so the fill is what keeps a later entry's value on its own row: a
write on entry *k* first gives every earlier entry that holds no row of that metric a zero-valued
row, numbered upward, and then numbers its own row after them. It is live phone behaviour, not
old-data handling. Its doc comment carries neither "legacy" nor "leftover", so it is unchanged
(D-709). R-6 is dropped and the handoff's *missing-row filling* item is withdrawn from 3a3. Guards:
`test/entry_identity_test.dart` `S-864`, `test/row_invariants_guard_test.dart` `S-883` and
`test/distance_source_test.dart` `S-807` ("missing rows are filled in position"), all at their HEAD
text.

**D-713.** `EntryRows.companions` pairs **numbered rows only**: it orders the rows of the metric
whose id carries a number and pairs the *i*-th with entry *i*; an unnumbered row is never paired,
occupies no position, and stays stored. `ordered` keeps its total order (an unnumbered row sorts
last). No live writer produces an unnumbered row, so nothing live changes. The callers are
`EntryRows.distanceEntries` (→ `WorkoutState.getEffortDistanceEntries`, the Summary, Stats pace and
`setEntryDistance`), the routine draft's extra-weight read (D-708) and `_fillEntriesBefore`'s
`paired` argument. `_fillEntriesBefore` needs no change: its loop consumes `companions` /
`distanceEntries` output, and its `number` comes from `EntryRows.nextNumber`, which already ignores
unnumbered rows (`numberForNewRow` reads `numberInId`). Guards: `S-1305`, `S-1306`.

## Feature Invariants

- **No visible change.** For every state the app's own writes can produce, the Summary, Stats,
  Instruments and the routine draft render the same values before and after. Any difference is a
  defect, not an improvement.
- **A stored row is never lost.** Every rule removed here removes *readers*, never rows: no phase
  deletes an observation, and `deleteEntry`/`deleteTimedEntry` keep deleting exactly the rows of the
  entry the user chose.
- **The fill stays.** A write on entry *k* fills only the earlier entries that hold no row of that
  metric, and never changes a row that already exists (D-712).
- **Repository parity.** `HiveWorkoutRepository` and `MockWorkoutRepository` stay value-for-value
  identical for everything this PR touches (ids, numbers, sources, pairing).
- **Docs trail code by zero phases.** Each phase updates the docs it invalidates, in the same phase.
- **The watch import is not touched.** `WatchSessionImporter` numbering and its absent-source rule
  are out of scope (PR 3c/3d).

## Requirements

| id | Requirement |
|----|-------------|
| R-1 | `DistanceSource.resolve` and the "a missing source reads as `entered`" claim are gone; only `isEstimated` reads a stored source (D-701). |
| R-2 | `EntryRows.distanceEntries` and `getEffortDistanceEntries` are timed-only; the non-timed distance branch and its "never hidden" claim are gone (D-703). |
| R-3 | `_idPattern` matches no suffix; the clone path keeps minting a fresh id for a row whose id it cannot parse (D-704). |
| R-4 | Set grouping is by number only; an unnumbered row belongs to no entry (D-705). |
| R-5 | No positional fallback remains in ownership, deletion or metric lookup (D-706). |
| R-7 | `addEntry` does not carry a distance forward (D-702). |
| R-8 | The routine draft reads entry 1's own row for `timed` and `drill` and numbered groups for `set` (D-708). |
| R-9 | The "leftover"/"legacy" wording is gone from `lib/` and `docs/` in the distance and entry-identity vocabulary (D-709). |
| R-10 | The two stale class docs and the series index are corrected (D-710). |
| R-11 | No dead reader of a removed representation remains anywhere in `lib/` (residue sweep, Phase 3). |

## Acceptance Criteria

| id | Acceptance criterion | Scenarios |
|----|----------------------|-----------|
| AC-1 | No `DistanceSource.resolve` exists in `lib/` and no `lib/` or `test/` caller of it remains (R-1). | S-1301, S-1302 |
| AC-2 | The only ways to store a positive distance are a phone write and the import, and both record a source (R-2, R-7). | S-1303, S-1304, S-1315 |
| AC-3 | No write mints a suffixed id; a suffixed row pairs with nothing and stays stored (R-3). | S-1305, S-1306 |
| AC-4 | An unnumbered row is in no entry, is not deleted, and never becomes one (R-4). | S-1305, S-1307 |
| AC-5 | Deleting entry *k* removes exactly *k*'s rows, and a write on an entry whose predecessors all hold a row of that metric changes no other row (R-5). | S-1308, S-1309, S-1310 |
| AC-6 | A draft built from a store whose rows are out of entry order matches the entry-1 values (R-8). | S-1311–S-1314, S-1317 |
| AC-7 | The named docs read as the app behaves and name tests that exist (R-9, R-10). | each phase's doc steps |
| AC-8 | No `lib/` reader of a removed rule remains (R-11). | Phase 3 step 9 |
| AC-9 | `flutter analyze` and `flutter test` are green, with no new findings and no lost coverage. | every phase's Done Criteria |
| AC-10 | A write on a later entry whose predecessors hold no row of that metric lands on that entry, and the earlier entries keep their own values (D-712, R-5). | S-1318, S-1319 |

## Scenarios

### S-1301: a stored distance with no source reads with no source
- Fixture: one `timed` effort, one numbered distance row `obs-e-1-0-distance` = 5000.0 with
  `valueSource` null, written straight through the repository (Mock and Hive).
- Trigger: read the row through `EntryRows.distanceEntries` / the Summary / Stats pace.
- Expected outcome: the row reads 5000.0 m with `valueSource` null, `DistanceSource.isEstimated`
  false, `toMap()['value_source']` null; no reader substitutes `entered`.
- Edge case of: none (supersedes `S-801`'s resolve half).

### S-1302: the import's absent source still stores `entered`
- Fixture: a watch wire payload for a `timed` entry with a distance and no source key.
- Trigger: import it, then read the stored row.
- Expected outcome: the stored row carries `entered` and reads as `entered`; nothing changed on the
  wire path. (Guards that D-701 did not reach the import.)
- Edge case of: none. **Retained existing test** — `test/distance_source_import_test.dart` `S-876` /
  `S-877` at HEAD, unchanged; the guard that the import's absent-source rule still stores `entered`.

### S-1303: a distance row is never created or shown on a non-timed effort
- Fixture: a `drill` effort with 2 entries, 60 s each, extra-weight rows only; plus an adversarial
  same-shape `drill` effort carrying a stored 400.0 m distance row (the pre-3a3 shape).
- Trigger: open the post-workout Summary for both; call `getEffortDistanceEntries` for both.
- Expected outcome: no DISTANCE section for either, both lists empty, the adversarial row still
  stored and unchanged.
- Edge case of: none (supersedes `S-818d` and `S-819`).

### S-1304: adding an entry after a distance was recorded starts empty
- Fixture: a `timed` effort with one entry holding 2500.0 m, source `entered`.
- Trigger: `addEntry(effortId, previousValues: {'distance': 2500.0})`.
- Expected outcome: the new entry's distance row is 0.0 with no source; no positive row without a
  source exists on the effort.
- Edge case of: none (3b review S-1).

### S-1305: a row with no number pairs with nothing and stays stored
- Fixture: a `timed` effort with 2 instances; distance rows `obs-e-1-0-distance` = 0.0 and
  `obs-e-1-1-distance-9000` = 2000.0 (adversarial suffixed id).
- Trigger: `EntryRows.numberInId`, `EntryRows.distanceEntries`, the Summary.
- Expected outcome: the suffixed id yields no number; `EntryRows.distanceEntries` returns
  `[0.0, 0.0]` — entry 0 reads 0.0 and entry 1 reads no row, because only numbered rows pair
  (D-713); the 2000.0 row is still stored after every read and after a clone.
- Edge case of: none.

### S-1306: a copied block whose source holds a suffixed row
- Fixture: a block with a `timed` effort whose distance rows include a suffixed id, plus a set
  effort with numbered rows.
- Trigger: copy the block (`_clonedRowId` path, Hive and Mock).
- Expected outcome: the copied suffixed row gets a fresh unique id and pairs with no entry (D-713:
  only numbered rows pair); every other copied row keeps the source's number and metric key; source
  and target both stay readable.
- Edge case of: S-1305.

### S-1307: an unnumbered set row is in no entry
- Fixture: a `set` effort with rows `obs-e-1-0-reps` = 10, `obs-e-1-0-weight` = 50, plus a
  UUID-keyed reps row = 8 (adversarial).
- Trigger: `EntryRows.setGroups`, `buildExercisesWithEntries`, the session screen's entry list.
- Expected outcome: exactly one entry (10 reps, 50 kg); the UUID row appears in no entry and is
  still stored; `SetRows.number` is non-null for every group.
- Edge case of: none.

### S-1308: deleting a set deletes its own rows only
- Fixture: a `set` effort with 3 numbered groups 0, 1, 2, each reps + weight.
- Trigger: `deleteEntry(effortId, 1)`.
- Expected outcome: only number 1's rows are gone; 0 and 2 survive unchanged; the effort still reads
  2 entries, in number order.
- Edge case of: none.

### S-1309: deleting a timed entry leaves nothing for the next entry to adopt
- Fixture: a `timed` effort with 2 entries, each with a distance row (entry 0 = 1000.0,
  entry 1 = 2000.0) and an extra-weight row.
- Trigger: delete entry 0, then `addEntry`.
- Expected outcome: the new entry is empty (0.0 m, no source, no adopted rows); entry 1 keeps
  2000.0 and its own rows.
- Edge case of: none (3a2 O-5).

### S-1310: a write on a later entry creates no earlier rows
- Fixture: a `timed` effort with 3 entries whose distance rows are 0.0, 0.0, 0.0.
- Trigger: `setEntryDistance(effortId, 2, 1500.0)`, then `updateEntryValue(effortId, 2,
  'extra-weight', 8.0)`.
- Expected outcome: only entry 2's rows change; the row count is unchanged; entries 0 and 1 still
  read 0.0 with no source. (The fill does not run here: every earlier entry already holds a distance
  row — D-712.)
- Edge case of: none.

### S-1311: a draft reads entry 1's own row when the store returns rows out of entry order
- Fixture: a `timed` effort with 2 entries; rows created in the order *entry 1's* extra-weight
  (12.0) then *entry 0's* (5.0), so `_observations[effort.id].first` is entry 1's row.
- Trigger: `buildTemplateDraftExercises` (save-as-routine) on both stores.
- Expected outcome: the draft's extra-weight target is 5.0, and the effort's own entries still read
  5.0 and 12.0.
- Edge case of: none (3a2 O-7, 3b review S-1).

### S-1312: the same, for a `drill` effort
- Fixture: a `drill` effort with 2 entries, extra-weight rows created out of entry order
  (entry 1 = −10.0 first, then entry 0 = −20.0).
- Trigger: `buildTemplateDraftExercises`.
- Expected outcome: the drafted extra-weight target is −20.0.
- Edge case of: S-1311.

### S-1313: a set draft uses numbered groups, not `createdAtMs`
- Fixture: a `set` effort with 3 sets whose rows carry `createdAtMs` in descending entry order.
- Trigger: `buildTemplateDraftExercises`.
- Expected outcome: the targets are in entry order (reps and weight of set 1, then 2, then 3).
- Edge case of: none.

### S-1314: a round effort's draft is unchanged
- Fixture: a `round` effort with 3 rounds and a planned round duration.
- Trigger: `buildTemplateDraftExercises`.
- Expected outcome: `rounds` = 3 and the round duration target is the planned one; nothing else.
- Edge case of: none.

### S-1315: an effort with no distance
- Fixture: a `timed` effort with 2 entries and no distance rows; and a session with no efforts.
- Trigger: open the Summary; open the Stats screen; save as a routine.
- Expected outcome: no distance target and no distance row; no empty-string or `0.00` row is
  invented.
- Edge case of: none.

### S-1316: confirming a distance twice is idempotent
- Fixture: a `timed` entry holding 3000.0 m with source `estimated`.
- Trigger: `confirmEntryDistance` twice; re-read through both repositories.
- Expected outcome: 3000.0 m, source `entered`, one row, same id and `createdAtMs`, one `updatedAtMs`
  bump per write; no new rows.
- Edge case of: none.

### S-1317: a 30-entry timed effort with distances on entries 1 and 3
- Fixture: a `timed` effort at `WorkoutConstants.maxEntriesPerEffort` entries, distance rows only on
  entries 0 and 2 (values 1000.0 and 3000.0), rows stored in an order that is not entry order.
- Trigger: open the Summary; read the Stats pace; save as a routine.
- Expected outcome: the Summary lists 30 rows in entry order with 1.00 and 3.00 in place and
  `SessionDistanceCard.absentValue` elsewhere; Stats counts 4000.0 m for the session; the draft reads
  entry 0's own extra weight.
- Edge case of: S-1310.

### S-1318: editing a later hold's extra weight while an earlier hold has no row
- Fixture: a `drill` effort with 2 entries and no extra-weight rows at all (the
  `test/entry_identity_test.dart` `S-864` fixture, unchanged).
- Trigger: `updateEntryValue(effortId, 1, 'extra-weight', 5.0)` — the second hold.
- Flow: the write fills entry 1's missing extra-weight row with a zero, numbered upward, then
  numbers its own row after it (D-712).
- Expected outcome: `{'obs-e-side-1-extra-weight': 0.0, 'obs-e-side-2-extra-weight': 5.0}` and the
  entries read `[0.0, 5.0]` — hold 2 keeps 5.0.
- Edge case of: none. **Retained existing test** — `test/entry_identity_test.dart` `S-864` at HEAD,
  unchanged; the guard that proves D-712.

### S-1319: a distance set on a later entry of a phone-built timed effort
- Fixture: a `timed` effort built by the phone's own `addEntry` three times (the
  `test/row_invariants_guard_test.dart` `S-883` fixture, unchanged).
- Trigger: `setEntryDistance(effortId, 2, 3000.0)`, then the rest of S-883's sequence (edits,
  deletes, an add, an extra weight).
- Expected outcome: the 3000 m row is the one the third entry owns and the one `deleteEntry(1)`
  removes; every row count and entry value S-883 asserts is unchanged.
- Edge case of: none. **Retained existing test** — `test/row_invariants_guard_test.dart` `S-883` at
  HEAD, unchanged; the guard that proves D-712.

## Iteration 1

### Phase 1: a distance always carries a source (@developer)

1. [x] In `lib/core/utils/distance_source.dart`, delete `DistanceSource.resolve` and its doc comment
       (`/// The source [stored] resolves to. A row with no source — every row written before the
       field existed, and every row the phone or the watch import writes today — reads as entered.`).
       Keep `isEstimated`. Rewrite the `DistanceSource` class doc to say what it is now: `isEstimated`
       answers whether a stored value is the watch's estimate; a distance that holds a value always
       carries a source (D-701).
2. [x] In the same file, replace the `DistancePairing.forEntries` doc's last sentence (`a row past the
       last entry is a leftover that no entry owns`) with `a row placed past the last entry belongs to
       no entry: it pairs with nothing` (D-709).
3. [x] In `lib/core/utils/entry_rows.dart`, delete the non-timed branch of `distanceEntries` and its
       `bool timed` parameter; keep the timed arm. Update the method doc and the `setEntryDistance`
       doc comment in `lib/state/workout/session_core_entry.dart` that repeats the "the entries are
       the distance rows themselves" claim (D-703).
4. [x] In `lib/state/workout/session_core_entry.dart`, `getEffortDistanceEntries`: return
       `const <DistanceEntry>[]` when the effort's kind is not `timed`; otherwise build one entry per
       `TimedInstance` with its own row from `EntryRows.companions` (D-703). Keep the entry indices
       the writes address unchanged (D-328).
5. [x] In `lib/state/workout/session_core_entry.dart`, `addEntry`: stop reading
       `previousValues?['distance']`; the new timed entry's distance row is always 0.0 with no source.
       Leave every other carry-forward key as it is (D-702).
6. [x] Restore `_fillEntriesBefore` exactly as at HEAD (the executor already deleted it; the
       working-tree diff shows the original) and leave both call sites as they are at HEAD: the
       extra-weight branch of `updateEntryValue` calls it with `EntryRows.companions(...)`, and
       `setEntryDistance` calls it with `[for (final entry in entries) entry.row]`. Its doc comment
       carries neither "legacy" nor "leftover", so it is unchanged (D-712, D-709).
7. [x] In `lib/core/utils/entry_rows.dart`, delete the optional `(?:-\d+)?` from `_idPattern`; make
       `companions` pair numbered rows only — filter the metric's rows to those whose id carries a
       number before `ordered`, so an unnumbered row occupies no position and is never paired
       (D-713); and in the `companions` doc replace `A row past the last entry is a leftover: it
       pairs with nothing and is ignored` with `A row placed past the last entry belongs to no
       entry: it pairs with nothing and is ignored`, adding that only numbered rows pair (D-704,
       D-709, D-713). Do not touch `_clonedRowId` in either repository: its
       `EntryRows.parseId(sourceId) == null → fresh id` rule already covers a suffixed id. In
       `lib/data/repositories/hive_workout_repository.dart` and `mock_workout_repository.dart`, delete
       only the F-8 sentence in each `_clonedRowId` doc comment (D-704).
8. [x] In `lib/data/models/models.dart`, correct the `EffortObservation` class doc and the
       `valueSource` doc: a distance with a value carries a source; a zero carries none; nothing reads
       an absent source as `entered` (D-701). Do not change any model code, `toMap` or `fromMap`.
9. [x] Tests, `test/distance_source_test.dart`: rewrite `S-801`'s resolve assertions to S-1301
       (a stored row with no source reads with no source and is not estimated) and delete the
       "resolves to `entered`" invariant line from the file's doc comment. Restore `S-807` to its
       HEAD text and title (`S-807 missing rows are filled in position`, expecting
       `[0.0, 0.0, 1500.0]` with `paired[1]` the filled `obs-e-gap-1-distance` and `paired[2]` the
       written `obs-e-gap-2-distance`) — the executor rewrote it to the withdrawn D-707 rule. Keep
       `S-802`–`S-806` and `S-808` as they are. Add S-1316 to this file if it is not already covered
       by `S-806`.
10. [x] Tests, `test/distance_source_import_test.dart`: `_readDistances` becomes
        `(entry.metres, entry.row?.valueSource)` typed `(double, String?)`; update its callers. The
        `S-876`/`S-877` expectations stay unchanged — the import always writes a source for a positive
        distance (S-1302).
11. [x] Tests, `test/session_summary_distance_test.dart`: retire `S-818d` and `S-819` (their fixture
        stores a distance row on a `drill` effort, which D-703 makes unreachable and unshowable) and
        replace them with S-1303. Keep `S-815` — zero-removal on a Cardio entry still covers the
        removal rule. Keep the file's `_seedSession` distance support: `S-823` (a plank tracked
        through Cardio) still needs it.
12. [x] Tests, `test/entry_rows_test.dart`: in `S-846`'s fixture drop the `obs-e-f5-3-distance-9000`
        row and in `S-847`'s fixture drop `obs-e-d-3-distance-9000`, and drop the assertions that name
        them (S-846 is otherwise superseded by `S-844`/`S-845`). Keep `S-847`'s clone assertions for
        the numbered rows. Add S-1305's `numberInId` assertion and S-1306 (D-704, D-713).
13. [x] Tests, `test/entry_identity_summary_test.dart`: retire `S-859` — its fixture is a `drill`
        effort with a lone unnumbered distance row, so D-703 makes it show nothing at all. Cover the
        surviving intent ("a row with no number pairs with nothing and stays stored") in S-1305, and
        keep `S-855`, `S-856` and `S-858` (their fixtures are sets or Cardio-tracked entries).
14. [x] Tests, `test/row_invariants_guard_test.dart`: add a step to the existing row-invariant guard
        that calls `addEntry(effortId, previousValues: {'distance': 2500.0})` on a timed effort and
        asserts the effort holds no distance row with a positive value and no source (S-1304). This is
        the structural guard for D-701 + D-702 and must live in the guard file, not in a one-off test.
15. [x] Docs: `docs/distance_source.md` — rewrite the `DistanceSource` paragraph (drop `resolve`,
        keep `isEstimated`, name `test/distance_source_test.dart` (`S-1301`)); **keep** the fill
        paragraph ("When the edited entry has no row of its own, the write first fills every earlier
        unpaired entry…"), the "**Why the write fills earlier gaps**" rationale and the "Entries with
        no row of their own are filled in position" invariant — they describe live behaviour (D-712)
        — and make each name the tests that assert it (`S-807`, `S-864`, `S-883`); replace "On an
        effort that is not timed, the entries are the distance rows themselves" with the timed-only
        rule (`S-1303`); rewrite the invariant bullets that mention resolving a missing source and a
        reader "resolving its source through `DistanceSource`"; rewrite the "Why a missing source
        reads as `entered`" rationale to the import's wire rule only (`S-1302`); delete the **Legacy
        distance** vocabulary entry and rename **Leftover row** to **Unpaired row** (D-703, D-709,
        D-712).
16. [x] Docs: `docs/session_summary.md` — drop the "**A stored distance is never hidden**" bullet and
        the `S-818d`/`S-819` test-list entries; replace "a leftover row that shows nowhere (`S-858`)
        and a lone legacy row that carries no number (`S-859`)" with "a row that belongs to no entry
        (`S-858`)"; drop `S-859` (D-703, D-709).
17. [x] Docs: `docs/data_models.md` — the `valueSource` paragraph ("an absent source means the row was
        written by a path that did not record one, which reads as `entered`") becomes the D-701 rule
        with `S-1301` named; in § Entry Identity, drop the optional-suffix sentence and the "No suffix
        is ever minted; an existing suffixed id reads as its number" sentence, and drop `S-859` from
        the phone's test list (D-701, D-704, D-709).
18. [x] Docs: `docs/state_management/workout_state.md` — `setEntryDistance`'s row **keeps** "earlier
        unpaired entries are filled first, numbered upward" (live, D-712) and names `S-807` and
        `S-883`; `updateEntryValue`'s row keeps "a hold's or a timed entry's missing predecessors are
        filled first" and names `S-864`; `getEffortDistanceEntries`' row gains the timed-only rule
        and loses `S-859`; `addEntry`'s row states that a distance is not carried forward (D-702,
        D-703, D-712).

**Done Criteria** (run until green): `flutter analyze` → the same 196 issues and 0 errors;
`flutter test` → all pass, count ≥ `+3227 ~1`; `flutter test test/distance_source_test.dart
test/distance_source_import_test.dart test/session_summary_distance_test.dart
test/entry_rows_test.dart test/entry_identity_summary_test.dart test/entry_identity_test.dart
test/row_invariants_guard_test.dart` → all pass.

**Red first.** Every new test in this phase (S-1301's rewrite, S-1303, S-1304's guard step, S-1305,
S-1306) is written into its file and shown failing with `gateway.sh test <file>` before the code step
that satisfies it. Quote each red run in the evidence file.

**This phase must fail if** any inverse edit is made and the tests still pass: (a) restore the
non-timed arm of `distanceEntries` → S-1303 fails; (b) restore `previousValues?['distance']` in
`addEntry` → S-1304's guard step fails; (c) delete `_fillEntriesBefore` again → S-864, S-883 and
S-807 fail on both repositories (the executor's own run, recorded in the evidence file); (d) drop
the numbered-only filter from `companions` → S-1305 and S-1306 fail. Record every run in the
evidence file.

**Predicted Files**: `lib/core/utils/distance_source.dart`, `lib/core/utils/entry_rows.dart`,
`lib/data/models/models.dart`, `lib/state/workout/session_core_entry.dart`,
`lib/data/repositories/hive_workout_repository.dart`, `lib/data/repositories/mock_workout_repository.dart`,
`test/distance_source_test.dart`, `test/distance_source_import_test.dart`,
`test/session_summary_distance_test.dart`, `test/entry_rows_test.dart`,
`test/entry_identity_summary_test.dart`, `test/row_invariants_guard_test.dart`,
`test/watch_session_import_test.dart`,
`docs/distance_source.md`, `docs/session_summary.md`, `docs/data_models.md`,
`docs/state_management/workout_state.md`.

### Phase 2: entry identity is the number, never a position (@developer)

**Do not touch `_fillEntriesBefore`** (D-712): it stays in `lib/state/workout/session_core_entry.dart`
with both call sites unchanged. No step in this phase deletes or inlines it.

1. [x] In `lib/core/utils/entry_rows.dart`, make `SetRows.number` a non-nullable `int` and rewrite its
       doc; delete `_sequentialGroups` and the `if (number == null) return _sequentialGroups(listed)`
       early return in `setGroups`, so the groups are the numbered rows in ascending number (D-705).
2. [x] In the same file, update the class doc, the `setGroups` doc and `ordered`'s "Rows with no
       number follow" wording: an unnumbered row belongs to no entry, sorts last so `ordered` stays a
       total order, and is never deleted. Keep `_compareByEntry`'s null branch — it is what makes the
       order total (D-705).
3. [x] In `lib/state/workout/session_core_entry.dart`, delete `_entriesAreNumbered` entirely, and in
       `_rowIndexEntryOwns` delete the positional branch: `timed`/`drill` → `EntryRows.companions`,
       otherwise → `_setRowsAt(rows, entryIndex)?.rowFor(metricId)` (D-706).
4. [x] In the same file, `deleteEntry`: delete the positional fallback, keep the numbered path, and
       return when the group is null — the method must delete exactly the chosen set's rows (D-706).
5. [x] In `lib/state/workout/session_core.dart`, delete `_getMetricsPerEntry`; its only caller was the
       positional fallback deleted in step 4. Confirm with a repository-wide search for the symbol
       before deleting (D-706).
6. [x] In `lib/core/utils/observation_grouper.dart`, correct the `default:` comment only — the branch
       stays and the test pins it as dispatch (D-711). In `lib/state/workout/session_summary_builder.dart`,
       the "legacy fallback" comment above the `EntryRows.setGroups` call is corrected to state the
       real rule: an unnumbered row is in no group, so a group's own row is its numbered row (D-709).
7. [x] Tests, `test/utils_test.dart`: give `_obs` an `entryIndex` parameter (default `0`) and mint
       `obs-e-<entryIndex>-<n>-<metricKey>`-shaped ids instead of `obs-${metricId.hashCode}`, so the
       grouper suite exercises numbered grouping. Re-run all 8 set-grouping tests plus the
       "unknown effortKind falls back to set grouping" test; they must pass with the same expectations
       (D-705, D-711).
8. [x] Tests, `test/utils_test.dart`: retire "odd number of observations drops the trailing one" —
       it asserts the sequential rule, and a lone reps row is now an entry with weight 0.0. Replace it
       with S-1307 (an unnumbered row is in no entry) and record the reason in the file's comment.
9. [x] Tests, add S-1308 (`deleteEntry` on a 3-set effort removes only the chosen set's rows) and
       S-1309 (deleting a timed entry leaves nothing for the next entry to adopt) to
       `test/entry_identity_test.dart`, and S-1310 to `test/distance_source_test.dart` (D-706).
10. [x] Docs: `docs/data_models.md` § Entry Identity — "on an effort any of whose rows has no number,
        the sequential grouping of the legacy data applies instead" becomes the D-705 rule; "rows with
        no number follow in the store's own order" stays but is explained as a total order for
        unowned rows (S-1307, S-1308).
11. [x] Docs: `docs/distance_source.md` — the "**Why the write fills earlier gaps**" rationale and the
        "Entries with no row of their own are filled in position" invariant **stay** (live, D-712);
        only the D-709 word fixes apply. (The planner found no "sequential" mention in this file —
        the sequential-grouping wording lives in `docs/data_models.md`, step 10.) No change was needed:
        `grep -n "leftover\|legacy\|sequential"` → 0 hits.
12. [x] Docs: `docs/stats_best_load_investigation.md` — drop "(a 3a suffix included)" from the
        `ObservationGrouper` resolution note; the grouper reads the number in the id (D-704).

**Done Criteria** (run until green): `flutter analyze` → the same 196 issues and 0 errors;
`flutter test` → all pass, count ≥ `+3227 ~1`; `flutter test test/utils_test.dart
test/entry_rows_test.dart test/entry_identity_test.dart test/entry_identity_summary_test.dart
test/state_test.dart test/services_test.dart` → all pass.

**Red first.** S-1307, S-1308, S-1309 and S-1310 are written into their files and shown failing with
`gateway.sh test <file>` before the code step that satisfies each. Quote each red run in the evidence
file.

**This phase must fail if** either inverse edit is made and the tests still pass: (a) restore the
`_sequentialGroups` early return in `setGroups` → S-1307 fails; (b) restore the positional branch of
`_rowIndexEntryOwns` → S-1308 fails. Record both runs in the evidence file.

**Predicted Files**: `lib/core/utils/entry_rows.dart`, `lib/core/utils/observation_grouper.dart`,
`lib/state/workout/session_core.dart`, `lib/state/workout/session_core_entry.dart`,
`lib/state/workout/session_summary_builder.dart`, `test/utils_test.dart`,
`test/entry_identity_test.dart`, `test/entry_rows_test.dart`, `test/distance_source_test.dart`,
`test/state_test.dart`, `test/services_test.dart`, `test/data_tracking_fixes_test.dart`,
`test/in_session_pr_toast_test.dart`,
`docs/data_models.md`, `docs/distance_source.md`, `docs/stats_best_load_investigation.md`.

**Added during implementation** (unnumbered `obs-` fixtures that now belong to no entry):
`test/state_test.dart`, `test/services_test.dart`, `test/data_tracking_fixes_test.dart`,
`test/in_session_pr_toast_test.dart`.

### Phase 3: routine drafts, housekeeping, residue sweep (@developer)

1. [x] In `lib/state/workout/session_summary_builder.dart`, `buildTemplateDraftExercises`: the
       `timed`/`drill` branch reads entry 1's extra-weight row through
       `EntryRows.companions(rows: observations, metricId: MetricIds.extraWeight, entryCount: ...)`
       instead of `_observations[effort.id].first` / `companionObs.first.valueReal`; keep every target
       it already produces and add none. The `set` branch keeps `EntryRows.setGroups`. Do **not** touch
       `_buildEntriesForEffort`'s `createdAtMs` sort: it has three call sites (`computeSessionSummary`,
       the `buildTemplateDraftExercises` fall-through, and `_buildTemplateTargetsFromObservations`),
       and the sort is what makes the positional pairers deterministic for a store that returns rows
       out of entry order. Correct only the "legacy fallback" comment above the `setGroups` call
       (D-708, D-709).
2. [x] Tests: add S-1311 and S-1312 to `test/state_test.dart` (rows stored out of entry order for
       `timed` and `drill`), S-1313 (`set` with descending `createdAtMs`), S-1314 (a `round` effort's
       draft unchanged) and S-1315 (no distance at all). Keep the existing
       `buildTemplateDraftExercises includes extra-weight target for timed` test as S-1311's happy
       path (D-708).
3. [x] Docs: `docs/data_models.md` § Entry Identity — delete the "**The routine-template defaults read
       rows without the rule.**" paragraph in full (the defect it documents no longer exists) and keep
       the phone's test-list sentence with the `S-1311`–`S-1313` names added (D-708).
4. [x] Docs: `docs/session_summary.md` § Save as Routine and `docs/state_management/workout_state.md`'s
       `buildTemplateDraftExercises` row — the draft's source of each target is the entry's own row,
       named with the test names from step 2. Do not add a distance target to a timed or drill
       template (D-708).
5. [x] Housekeeping: `lib/widgets/chart/scrollable_trend_chart.dart` — the class doc's "Replaces the
       fixed-width rendering for every stats chart on [StatsScreen] (strength e1RM, strength volume,
       cardio pace, cardio duration, nutrition calories, nutrition macros) and the profile measurement
       history sheet" becomes the real caller list: `measurement_history_chart_sheet.dart`,
       `nutrition_trend_card.dart`, `exercise_progress_screen.dart` (D-710). Do not link to a private
       class; name the widgets the way the file does.
6. [x] Housekeeping: `lib/data/datasources/food_catalog_loader.dart` — "Both the Hive-backed
       production repository and the in-memory Mock repository go through this loader" becomes: the
       Hive-backed repository loads the asset through `loadFromAsset`; the Mock repository reads the
       generated `lib/mock/food_catalog_seed.dart`, which
       `scripts/generate_food_catalog_seed.dart` produces from the same JSON using `parseCatalogJson`
       (D-710). Keep `parseCatalogJson`'s doc accurate for both users (tests and the generator).
7. [x] Housekeeping: `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` — drop the
       "missing-row filling" bullet from 3a3's scope line (withdrawn, D-712); record 3a, 3a2 and
       3b as DONE and committed, PR 4 as done, 3a3 as in progress with the path
       `docs/plans/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.md`,
       and O-17 as **3d** with its plan path
       `docs/plans/2026-10-02-03d-stats-pr3d-late-watch-entry-plan/2026-10-02-03d-stats-pr3d-late-watch-entry-plan.md`.
       Do not open or edit that plan. Replace the stale "241 issues" risk line with the current
       baseline (196 issues, 0 errors) and refresh the trailing "Scope check (2026-09-27)" line (D-710).
8. [x] Tests: add S-1316 (confirming twice is idempotent) and S-1317 (a 30-entry timed effort with
       distances on entries 1 and 3, rows stored out of order) to
       `test/distance_source_test.dart` and `test/session_summary_distance_test.dart` (D-701, D-706).
9. [x] Residue sweep — search `lib/` and `test/` for every symbol and phrase this PR retired and
       record the result in the evidence file: `DistanceSource.resolve`, `_sequentialGroups`,
       `_entriesAreNumbered`, `_getMetricsPerEntry`, `previousValues?['distance']`,
       `distanceEntries(` callers passing a kind, `_buildEntriesForEffort`, and the words `leftover`
       and `legacy` in the distance/entry-identity vocabulary. `_fillEntriesBefore` is **not** in
       this list: it stays (D-712). Expected: zero hits in `lib/`; in
       `test/`, only the words in test *names* and in unrelated domains (`create_new_exercise.md`,
       `db_integration.md`, `stats_legacy_removal_test.dart`, nutrition and profile docs) (D-709,
       R-11).
10. [x] Record the `ObservationGrouper` positional pairers in § Out of scope with the evidence: the
        `timed` and `drill` arms are live (called with those kinds from `session_summary_builder.dart`,
        `session_summary_service.dart` and `stats_progress_service.dart`) and pair by position, so they
        are the item-8 surface this PR deliberately leaves alone; the `round` arm is the only dead one.
        Do not change any of the three (D-711).

**Done Criteria** (run until green): `flutter analyze` → the same 196 issues and 0 errors;
`flutter test` → all pass, count ≥ `+3227 ~1`; `flutter test test/state_test.dart
test/services_test.dart test/session_summary_distance_test.dart test/distance_source_test.dart
test/docs_indexing_contract_test.dart` → all pass.

**Red first.** S-1311, S-1312, S-1313, S-1314, S-1315, S-1316 and S-1317 are written into their files
and shown failing with `gateway.sh test <file>` before the code step that satisfies each. Quote each
red run in the evidence file.

**This phase must fail if** either inverse edit is made and the tests still pass: (a) restore the
`_observations[effort.id].first` read in the `timed`/`drill` draft branch → S-1311 fails; (b) restore
the `createdAtMs` sort in the set draft branch → S-1313 fails. Record both runs in the evidence file.

**Predicted Files**: `lib/state/workout/session_summary_builder.dart`, `test/state_test.dart`,
`test/distance_source_test.dart`, `test/session_summary_distance_test.dart`,
`lib/widgets/chart/scrollable_trend_chart.dart`, `lib/data/datasources/food_catalog_loader.dart`,
`docs/data_models.md`, `docs/session_summary.md`, `docs/state_management/workout_state.md`,
`docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md`.

## Governor actions

No file is created, deleted, moved or renamed by this PR. Every change is an edit inside an existing
file, and every deletion listed in the phases is a *code* deletion inside a file. If an executor
believes a file must be deleted, stop and report instead of proceeding.

## Out of scope — recorded, not done

- `ObservationGrouper._groupTimedObservations` and `_groupDrillObservations`: **live** positional
  pairers. `groupByEffortKind` is called with `'timed'`/`'drill'` from
  `session_summary_builder.dart` (`_buildEntriesForEffort`, `buildTemplateDraftExercises`),
  `session_summary_service.dart` (`_computeVolumeFromObservations`) and `stats_progress_service.dart`,
  and those arms pair rows by position (`i += 2`), ignoring the entry rule. They are the brief's item
  8 "outside the entry rule" surface; converting them to `EntryRows.companions` is a separate PR with
  its own test fallout, and this PR's brief is "no visible change". Recorded, not done.
- `ObservationGrouper._groupRoundObservations`: the one dead pairer — a `round` effort's entries come
  from `RoundInstance` records, so no caller can reach it with rows. Not in this PR's brief; the
  `default:` branch stays (D-711).
- The watch import's numbering and its absent-source rule (`WatchSessionImporter`): PR 3c/3d.
- `DistancePairing`: a live delegate (`StatsProgressService` reads it). Only its doc wording changes.
- Test *names* that use the word "leftover" (`S-858`'s title): the `S-` id is the stable handle;
  renaming is churn with no reader (D-709).
- "legacy" outside the distance and entry-identity vocabulary (`create_new_exercise.md`,
  `db_integration.md`, `profile_and_measurements.md`, nutrition docs, `stats_legacy_removal_test.dart`):
  different meanings, untouched.
- 3a2 O-6 (a number group with no reps row counting as a set) — unreachable from any UI; stays open.
- The handoff's *missing-row filling* item: **withdrawn** (D-712). Entry pairing is positional among
  an effort's rows of one metric, so the fill is what keeps a later entry's value on its own row — it
  is live phone behaviour, not old-data handling. `_fillEntriesBefore` stays as at HEAD, and `S-807`,
  `S-864` and `S-883` keep asserting it.
- Migration, old-data handling and back-compat: 3b D-332 (no user data exists).

## Files Affected (whole feature)

`lib/core/utils/distance_source.dart`, `lib/core/utils/entry_rows.dart`,
`lib/core/utils/observation_grouper.dart`, `lib/data/models/models.dart`,
`lib/state/workout/session_core.dart`, `lib/state/workout/session_core_entry.dart`,
`lib/state/workout/session_summary_builder.dart`,
`lib/data/repositories/hive_workout_repository.dart`,
`lib/data/repositories/mock_workout_repository.dart`,
`lib/widgets/chart/scrollable_trend_chart.dart`,
`lib/data/datasources/food_catalog_loader.dart`;
`test/distance_source_test.dart`, `test/distance_source_import_test.dart`,
`test/session_summary_distance_test.dart`, `test/entry_rows_test.dart`,
`test/entry_identity_test.dart`, `test/entry_identity_summary_test.dart`,
`test/row_invariants_guard_test.dart`, `test/utils_test.dart`, `test/state_test.dart`;
`docs/distance_source.md`, `docs/data_models.md`, `docs/session_summary.md`,
`docs/state_management/workout_state.md`,
`docs/stats_best_load_investigation.md`,
`docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md`.

## Notes

- **Dependency graph.** Phase 1 → Phase 2 → Phase 3, strictly sequential: Phase 2's wording depends on
  Phase 1's edits in the same two files, and Phase 3's draft fix needs Phase 2's `companions` reading
  to be the only pairing rule. There is no useful reordering — Phase 1 carries the only data-safety
  change, so it goes first.
- **Intermediate states.** After Phase 1 the app is fully consistent (no reader of `resolve` exists);
  after Phase 2 the sequential grouping is gone but the draft still reads raw store order, which is
  invisible for every state the app can produce. No phase leaves a red suite.
- **Why no @dba.** No model, repository interface, schema, seed or migration change: `scripts/
  sqlite_schema.sql` and `scripts/sqlite_seed.sql` stay as they are, so `test/db_seed_test.dart` is
  untouched. The two repository edits are doc comments.
- **Test count.** The phases retire 4 tests and add S-1303–S-1317, so the final count exceeds the
  baseline's `+3227 ~1`. A *lower* count is a defect.
- **DeepSeek executors cannot delete files or run grep.** Every search in a step is expressed as a
  request to the implementer's own file reads, or as `gateway.sh git-diff`/`git-status` output. If a
  step needs a search the tool cannot do, the executor reads the file and reports the result.

## Progress

| Phase | Owner | State | Notes |
|-------|-------|-------|-------|
| 1 — a distance always carries a source | @developer | Complete | 18/18 steps; all suites green; four inverse edits failed then reverted green |
| 2 — entry identity is the number | @developer | Complete | 12/12 steps; all suites green; both inverse edits failed then reverted green |
| 3 — drafts, housekeeping, sweep | @developer | Complete | 10/10 steps; all suites green; inverse edit (a) failed then reverted green; (b) unsatisfiable — see A-3a3-P3-1 |

## Assumption Log

*(Executors append here. Conductor marks each RATIFIED — promoted to a D-x — or REVERT — remediation.)*

**A-3a3-P1-1 — `test/watch_session_import_test.dart` is a Phase 1 Predicted File.**
Its 5000 m re-pointed to the live `setEntryDistance(run, 1, 5000.0)` path (D-702); assertions unchanged. **RATIFY or REVERT?**

**A-3a3-P1-2 — must-fail-if (c) overstates S-883.**
Deleting `_fillEntriesBefore` fails S-864 and S-807 but not S-883 (its entry already owns an extra-weight row at step 5); S-883 stays as a guard. **RATIFY or REVERT?**

**A-3a3-P2-1 — must-fail-if (b) needs an unnumbered fixture.**
S-1308's numbered fixture leaves the restored positional branch green; S-1308 gained "an unnumbered set effort has no entry to delete", red under the inverse. **RATIFY or REVERT?**

**A-3a3-P2-2 — S-1309 and S-1310 are guards, not red-first.**
S-1309 pins D-702 and S-1310 pins D-712; both green at the Phase 2 baseline; recorded in the evidence file. **RATIFY or REVERT?**

**A-3a3-P2-3 — four test files added to Phase 2 Predicted Files.**
`state_test`, `services_test`, `data_tracking_fixes_test` and `in_session_pr_toast_test` built unnumbered set-row ids; each got a numbered id, no assertion weakened. **RATIFY or REVERT?**

**A-3a3-P3-1 — must-fail-if (b) is unsatisfiable; the `set` draft branch is the fall-through.**
The `set` branch *is* the `createdAtMs` fall-through and `setGroups` re-sorts by number, so inverse edit (b) was green; detail in the evidence file. **RATIFY or REVERT?**

**A-3a3-P3-2 — `lib/core/utils/observation_grouper.dart` added to Phase 3 Predicted Files.**
Step 1's comment fix is in this file, not `session_summary_builder.dart`; one comment line, no code. **RATIFY or REVERT?**

**A-3a3-P3-3 — S-1315's wording overstates two things.**
A `timed` effort always yields one Summary row per entry, and the timed draft branch intercepts before `EffortDefaults`; S-1315 asserts the reachable half. **RATIFY or REVERT?**

**A-3a3-P3-4 — S-1317 is a guard, not red-first.**
The phone's own `addEntry` writes the fixture's zero rows, so the pairing is already correct at the Phase 3 baseline; S-1317 pins D-701/D-706. **RATIFY or REVERT?**

## Feedback

Review round 1 — **CHANGES_REQUESTED**. Findings: `2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.review.md`.

- [x] F-1 — removed the false `parseCatalogJson` claim in `lib/data/datasources/food_catalog_loader.dart`; the comment now names only the two real readers and the tests.
- [x] F-2 — the series index now marks 3d PLANNED (plan READY) with its plan path, and drops the stale `3a3` dependency from the PR 4 row.
- [x] F-3 — plan trimmed below the 800-line ceiling (Assumption Log to the 3-line cap, suite output to the evidence file, Progress notes to one line per phase).
- [x] F-4 — S-1315, S-1317 and S-1304 registers now state exactly what their tests assert.
- [x] F-5 — S-1302 marked as a retained existing test (`S-876`/`S-877`); `test/distance_source_test.dart`'s header now lists S-1310 instead of S-1302.
- [x] F-6 — deleted the stale `A-3a3-P2-4` (tmp probe) entry.
- [x] F-7 — accepted as is; `test/utils_test.dart` formatting churn untouched.
- [x] F-8 — corrected the `models.dart` comment to the surrounding rule (a distance that holds a value always carries a source).

## Open questions

Every question the planner could not settle from the repository, with the default applied in the plan.
The owner may veto any of them; each is a product-visible or scope choice, not a technical one.

1. **Item 8's "distance defaults" — is a distance *target* wanted in a saved routine?**
   `EffortDefaults.getDefaultTargets('timed')` includes distance and
   `_buildTemplateTargetsFromObservations` would produce one, but the timed/drill branch intercepts
   first, so a saved routine never gets a distance target. **Default applied:** no — the branch keeps
   its current target set (D-708). Adding one is new visible behaviour, and this PR's brief is "no
   visible change".
2. **`ObservationGrouper`'s `default:` branch — remove or keep?** The brief's item 4 names
   `observation_grouper.dart` "Fallback". **Default applied:** keep the branch, correct only its
   comment (D-711) — a `switch` on `String` needs a total branch, and
   `test/utils_test.dart`'s "unknown effortKind falls back to set grouping" pins it as intended
   dispatch behaviour. Removing it would delete a test the brief did not ask to retire.
3. **The grouper's positional pairers — remove now?** The `timed` and `drill` arms are **live**
   (`groupByEffortKind` is called with those kinds from `session_summary_builder.dart`,
   `session_summary_service.dart` and `stats_progress_service.dart`) and pair rows by position,
   ignoring the entry rule; the `round` arm is dead. **Default applied:** leave all three, recorded
   under § Out of scope — they are the brief's item 8 "outside the entry rule" surface, converting
   them is a separate PR with its own test fallout, and this PR's brief is "no visible change".
4. **Item 8's "rebuild ids from entry positions" — is there an id rebuild to fix?** The planner found
   none: the draft path reads ids that `getExercisesWithEntries` already built under the entry rule,
   and the defect is the raw-first read plus the `createdAtMs` sort. **Default applied:** treat the
   read order as the whole defect (D-708); no id-minting code is changed.
5. **`DistancePairing` — delete the delegate too?** It is a thin wrapper over `EntryRows.companions`.
   **Default applied:** keep it — `StatsProgressService` reads it, so it is live; only its doc wording
   changes.
6. **Item 3 — does `_clonedRowId` need a code change?** **Default applied:** no. Its
   `EntryRows.parseId(sourceId) == null → fresh id` rule already covers a suffixed id, so F-8 becomes
   moot once D-704 lands; only the F-8 sentence in each doc comment goes.
7. **Item 7 — remove `previousValues?['distance']` or guard it?** **Default applied:** remove it
   (D-702) and add the guard step in `test/row_invariants_guard_test.dart` (S-1304). Guarding a path no
   screen can reach would leave the dead read in place.
8. **Retiring `S-818d`, `S-819` and `S-859` loses three tests.** **Default applied:** retire them
   (their fixtures store a distance row on a `drill` effort, which D-703 makes unreachable and
   unshowable) and replace their intent with S-1303 and S-1305. `S-815` keeps the removal rule
   covered.
9. **3a2 O-5 (a copied block leaves a row the next add adopts) — dead or moot?** **Default applied:**
   moot, no change. `deleteTimedEntry` and `deleteEntry` delete the entry's own rows, so nothing is
   left to adopt (S-1309 pins it).
10. **3a2 O-6 (a number group with no reps row counts as a set) — dead or moot?** **Default applied:**
    still technically reachable only through `updateEntryValue`'s extra-weight branch when
    `_setNumberAt` returns null, and no UI drives it. Left open, no change: the cleanup does not remove
    its cause, and the brief says not to expand scope to fix it.
11. **Test names that use the word "leftover" (`S-858`) — rename?** **Default applied:** no. The `S-`
    id is the stable handle and renaming is churn with no reader (D-709); the governor's name-level
    test diff will see an unchanged name.
12. **D-707 withdrawn, D-712/D-713 added after the executor's observation.** The executor's Phase 1
    run showed that deleting `_fillEntriesBefore` breaks `S-864` and `S-883` on both repositories in
    normal phone flows, and that `EntryRows.companions` still paired an unnumbered row (`S-1305`,
    `S-1306`). **Default applied:** D-712 keeps the fill as at HEAD (R-6 dropped, the handoff's
    *missing-row filling* item withdrawn) and D-713 makes `companions` pair numbered rows only. Two
    consequences the brief did not name, both derived from the code: `test/distance_source_test.dart`
    `S-807` (rewritten by the executor to the withdrawn rule) is restored to its HEAD text, and
    `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md`'s 3a3 scope line drops its
    "missing-row filling" bullet. Vetoable.
