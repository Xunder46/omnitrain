# Evidence — watch-session-sync PR 2a, Phases 1–2 (the merge, and the live screen)

Developer run, Copilot CLI. Every figure below is observed output from
`.github/copilot/scripts/macos/gateway.sh`; nothing is inferred from a successful analyze.

## Baselines (governor-measured, before this phase)

| Check | Baseline |
|---|---|
| `gateway.sh test` (full) | `+3885 ~1` — 0 failures |
| `gateway.sh lint` | 196 issues, 0 errors |

## Phase 0: the tests

`test/watch_session_merge_test.dart` is new: one `_mergeTests(open:, close:)` body over the plan's
merge scenarios (S-9, S-10, S-11, S-12, S-13, S-19) plus two this phase had to pin down — S-14 (the
phone finished first) and D-17 (a merge names the efforts it wrote into) — run twice, a `Mock` group
over `MockWorkoutRepository` and a `Hive` group over `HiveWorkoutRepository`, for **16 tests**. Wired
the way `createWatchSync` wires them: the adoption bridge first, the inbox that asks it `holdsSession`
as `phoneOwnsSession`, the mirror behind the staging transport, and a real `WorkoutState` behind a
real `WatchIncomingRouter`.

Plain `test()`, Mock group run first (a red Mock group leaves the Hive group behind it hanging).

## Phase 0.3: red without the fix

The merge is a behaviour change, so the red run is the held branch reverted to PR 1's shape — the
plan's item 8. Mutation applied to `lib/core/services/watch_session_importer.dart`:

```dart
-    if (phoneOwnsSession) return _mergeHeld(watchSessionId, rows);
+    if (phoneOwnsSession) return const WatchSessionImport();
```

`gateway.sh test test/watch_session_merge_test.dart --plain-name Mock` → **+0 −6, all six red**, each
for the right reason (nothing merged, so nothing was written):

```
Mock S-9 a wrist set reaches the live phone session [E]
  Expected: ['obs-sl-1-0-reps', 'obs-sl-1-0-weight']
    Actual: []
  S-9 the wrist's set is one entry of the phone's own effort

Mock S-10 a redelivery, and a second set [E]
  Expected: ['obs-sl-1-0-reps', 'obs-sl-1-0-weight', 'obs-sl-1-1-reps', 'obs-sl-1-1-weight']
    Actual: []
  S-10 exactly two entries: the redelivery wrote no third

Mock S-11 the phone's own rows are the user's [E]
  Expected: [six rows]
    Actual: ['obs-sl-1-0-reps', 'obs-sl-1-0-weight', 'obs-sl-1-1-reps', 'obs-sl-1-1-weight']
  S-11 the wrist's set lands after the user's rows

Mock S-12 a slot the session does not have [E]
  Expected: not null
    Actual: <null>
  S-12 a row for a slot the session lacks is acknowledged

Mock S-13 a correction on a merged row [E]
  Expected: ['obs-sl-1-0-reps', 'obs-sl-1-0-weight']
    Actual: []
  S-13 the correction edits the entry, it does not add one

Mock S-19 a set logged while the phone was out of reach [E]
  Expected: ['obs-sl-1-0-reps', 'obs-sl-1-0-weight', 'obs-sl-1-1-reps', 'obs-sl-1-1-weight']
    Actual: []
  S-19 both sets land, once each

00:00 +0 -6: Some tests failed.
```

The exact original line was restored immediately after, and the same file was re-run green (below).
No step ended with the mutation applied.

### The second red proof: D-17

Writing the D-17 test exposed a real bug in this phase's own code, so it gets its own red run. The
first cut of `changedEffortIds` compared the pass's *overall* flag around each group:

```dart
final wasChanged = pass.changed;          // a bool
...
if (pass.changed != wasChanged) changedEffortIds.add(slot);
```

That flag is already `true` by the time any group is placed, because `_topUpRating` writes the
session's rating earlier in the same pass — so the merge named **no** effort at all whenever a rating
arrived with the set. The fix counts writes instead (`_Pass.writes`, with `changed` as a getter over
it), and compares the count:

```dart
final wasChanged = pass.writes;
...
if (pass.writes != wasChanged) changedEffortIds.add(slot);
```

Reverting exactly those two lines and running
`gateway.sh test test/watch_session_merge_test.dart --plain-name D-17` → **+0 −2**, both groups red:

```
Mock D-17 a merge names the efforts it wrote into [E]
  Expected: ['sl-1']
    Actual: []
  D-17 the merge names sl-1 — the rating top-up is not an effort

Hive D-17 a merge names the efforts it wrote into [E]
  Expected: ['sl-1']
    Actual: []

00:00 +0 -2: Some tests failed.
```

The two lines were restored exactly and the file re-run green (below).

## Phase 1: the change, item by item

| Item | Change | Verified by |
|---|---|---|
| 1 | `apply` gets a held branch — `if (phoneOwnsSession) return _mergeHeld(watchSessionId, rows);` — placed before the `endRow == null` early return, so a set that arrives before its end merges at once (D-13) | S-9, S-19 |
| 2 | `_mergeHeld`: candidates are the session's unapplied `origin: watch` effort rows parsed through `_Entry.parse(row, corrections)`; rows a staged `phone_deletion` names are dropped; the rest group by `sessionExerciseId`; each group's effort is resolved **by row id** (`efforts[slot]`), never `effortIdFor`; placed with the import's own primitives — `_EffortRows.read` (the effort's already-applied rows as `before`, the live ones as `now`), `_placeAroundUserRows`, `_createEntry` — under the existing effort id | S-9, S-10, S-11, S-13, S-19 |
| 3 | A group whose effort the session does not have is acknowledged and dropped; `_mergeHeld` never calls `_placeEffort` or `_segmentId`, so no session, segment or effort is created (D-14) | S-12 |
| 4 | The rating top-up (`_topUpRating`) and the summary attach (`_attachSessionSummary`) run exactly as an import runs them (D-19) — the attach now keys off "the end is unapplied", not "the end reads completed", which is what `run` does, so an abandoned wrist end with heart rate attaches its summary too; the session's own end is never written, so a phone session that already ended stays ended (G2/D-5); every row the pass looked at is `_markApplied` and returned in `appliedEntryIds` (D-18) | S-14 (still ended, both sets land), S-12 (dropped rows receipted), the rewritten `test/watch_session_finish_test.dart` cases (rating 4, still-ended session) |
| 5 | `WatchSessionImport.changedEffortIds` added, default `const []`, filled from the merge with the efforts it wrote (the import path leaves it empty) — counted per group off `_Pass.writes`, because the pass's overall flag is already true when a rating arrives in the same pass | the D-17 test, and its red run above |
| 6 | `_sessionScopedKinds` and both "the merge PR 3 owns" comments deleted | residue sweep below |
| 7 | `test/watch_session_merge_test.dart` — Mock + Hive groups, S-9…S-13, S-14, S-19 and D-17 | the runs below |
| 8 | Red without the fix | above |

Two supporting edits the held branch needed: `_Pass.end` is now nullable (a merge has no end, and
never reaches the code that reads one — `run`, `_createSession`, `_segmentId`, `_attachSessionSummary`
and `_attachSetBlockSummary` assert it with `!`), and the non-held `entries` list no longer carries
`!phoneOwnsSession`.

## Phase 1 runs

| Command | Result |
|---|---|
| `gateway.sh test test/watch_session_merge_test.dart --plain-name Mock` | `+8` — All tests passed! |
| `gateway.sh test test/watch_session_merge_test.dart` | `+16` — All tests passed! |
| `gateway.sh test test/watch_session_finish_test.dart test/watch_session_import_test.dart test/watch_capture_repository_parity_test.dart` | `+90` — All tests passed! |
| `gateway.sh test` (full) | `01:50 +3901 ~1: All tests passed!` |
| `gateway.sh lint` | 196 issues, 0 errors — the baseline |
| `gateway.sh test` (full, re-run on the frozen code) | `01:46 +3901 ~1: All tests passed!` |
| `gateway.sh lint` (re-run) | 196 issues, 0 errors |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches — the repo invariant |

Full suite 3885 → 3901 passing: **+16, exactly the new merge tests**. No previously passing test now
fails.

## Governor override: PR 1's G3 assertions, rewritten here

The brief overrides Phase 3 item 1 into this phase, because the merge turns those assertions red.
Rewritten in `test/watch_session_finish_test.dart` (+68/−34):

| Was | Now |
|---|---|
| case `G3 the wrist's entries for a session the phone owns are not lost` | `a set logged on the watch lands in the session the phone holds` |
| header map line 11 `G3 the wrist's entries are not lost → \`G3 ...\`` | `the wrist's sets merge into the session the phone holds, once (PR 2a) → \`a set logged on the watch ...\`` |
| `_expectOneEndedSession`: `getEffortObservations('sl-1')` is empty | `sl-1` and `sl-2` each hold `['obs-<slot>-0-reps', 'obs-<slot>-0-weight']` — the wrist's sets are rows of the phone's own efforts (D-14) |
| S-4 test 1: `sx-1`/`sx-2` staged, `appliedAtMs` null, not receipted | applied (`isNotNull`) and receipted (D-18) |
| S-4 test 2: `sx-2`'s `appliedAtMs` is null ("staged like any other") | `isNotNull` — an entry that arrives after the end merges like any other (D-13) |
| the case's `ladder` snapshot compared before/after ("does not rewrite the phone's own rows") | dropped: the set now does write rows. Replaced by explicit assertions that exactly one entry per effort exists, that a redelivery writes no second entry (D-15), that `sx-1` is applied and receipted, and that the merge creates no effort |
| the case's `receiptedEntryIds` is empty ("acknowledges nothing it has not used") | `contains('sx-1')` |

`test/watch_session_finish_test.dart` also no longer needs its `importedRows` snapshot in that case;
the helper is still used by the two G1 cases.

## Residue sweep (S-18's importer half)

`grep -rn "sessionScopedKinds\|PR 3" lib/core/services/watch_session_importer.dart` → no matches.

**Caution for Phase 3's sweep.** `lib/state/watch/live_session_mirror_state.dart:129` also declares a
`sessionScopedKinds` — a different, live constant (the mirror's "entry kinds that describe the session
as a whole", documented in `docs/state_management/watch_surface.md:64` and named in PR 1's plan at
`...pr1-plan.md:564` as the constant the importer's predicate mirrored). The importer's copy is gone;
the mirror's is not residue of the merge and must not be deleted. Phase 3's Done Criteria
(`grep -rn "sessionScopedKinds\|the merge PR 3 owns" lib/` returns nothing) will therefore need the
importer-scoped spelling, or this constant excluding.

## Footprint

`gateway.sh git-diff --stat` (untracked `test/watch_session_merge_test.dart` is not in it):

```
lib/core/services/watch_session_importer.dart | 247 ++++++++++++++++++++------
test/watch_session_finish_test.dart           | 102 +++++++----
2 files changed, 265 insertions(+), 84 deletions(-)
```

Importer alone: `1 file changed, 197 insertions(+), 50 deletions(-)`. The plan predicted ~180–220
production lines for this file; the extra comes from the two corrections this run added to the
already-written merge — the write counter behind `changedEffortIds`, and the summary attach matching
`run`'s condition. Everything is inside the plan's Predicted Files;
`test/watch_session_merge_test.dart` is new and `test/watch_session_finish_test.dart` is the
governor's override.

---

# Phase 2 — the live screen and the wiring

Baseline going in: Phase 1's frozen state, `gateway.sh test` full suite `+3901 ~1`, lint 196/0.

## Phase 2: the change, item by item

| Item | Change | Verified by |
|---|---|---|
| 1 | `SessionCoreIOMethods.refreshEfforts(Iterable<String> effortIds)` (`lib/state/workout/session_core_io.dart`): per named effort re-reads its observations, its round instances when `effortKind == 'round'`, its timed instances when `'timed'`/`'drill'`, its entry rests, and re-reads the effort's exercise into `_exerciseCache`; `_clearError()` on entry, exactly one `_notify()` on success, `_setError` on a throw. It calls no `clearAll` and never `loadSessionData`, so every timer already running survives | S-16 (observations and rest), red proofs 1–2 |
| 2 | `WorkoutState.refreshEfforts` — the public delegation, next to `loadSessionData` | S-16 |
| 3 | `WatchSessionAdoptionBridge.refreshHeldEfforts(sessionId, effortIds)` — returns early when there is no bound `WorkoutState` or `holdsSession(sessionId)` is false, else delegates. A session the phone does not hold is never refreshed | S-16 (not-held case), red proof 3 |
| 4 | `WatchSessionInbox` gains the constructor hook `onSessionRowsChanged(sessionId, effortIds)`, called in `_settleNow` only when `pass.changedEffortIds.isNotEmpty`, after the receipts are collected | S-16 (redelivery case), red proof 4 |
| 5 | `createWatchSync` passes `onSessionRowsChanged: adoption.refreshHeldEfforts` | S-16 end-to-end through the real router |
| 6 | `test/watch_session_merge_test.dart`: `_phone`'s inbox passes the same hook, and four tests join the file — three S-16 cases and S-17 (the unheld session still imports) — plus `_end`/`_rating` fixtures (header map updated) | the runs below |

## Phase 2: the tests

Four tests added to `_mergeTests`, so 4 × 2 groups = **8 new tests** (16 → 24 in the file):

| Test | Asserts |
|---|---|
| `S-16 the live screen shows the merged set and keeps a running rest` | after `recordRestStart('sl-1', 0)` and a `msg-set-1` set for `sl-1`: exactly **1** notification on `WorkoutState`; `sl-1`'s visible observations are `obs-sl-1-0-reps` = 8 and `obs-sl-1-0-weight` = 40.0; `sl-2` is empty; the rest list still holds the **same** record with `restEndMs == null` and `hasRestRecord('sl-1', 0)` true; no failures |
| `S-16 the refresh does nothing for a session the phone does not hold` | `refreshHeldEfforts('s-other', ['sl-1'])` → 0 notifications, `sl-1` unchanged |
| `S-16 a pass that wrote nothing does not refresh` | a redelivery of an already-applied row → 0 notifications |
| `S-17 a session the phone does not hold still imports unchanged` | the phone holds nothing; a set + rating 4 + end (heart rate 140/165) for `s-w1` arrive: one session `s-w1` exists, its rating is 4, its sensor summary is attached, its one effort holds reps 8 / load 40.0, the receipt names all three ids, and the live state notified **0** times |

The rest is asserted by record identity and open state, never by elapsed seconds: `WorkoutState`
builds `TimerManager` with the real clock, and the plan forbids real-clock thresholds in tests
(A-31).

## Phase 2: red without the fix

Each guard was shown red by mutating the production line, then restored to the exact original and
re-run green. Mutations were run one at a time, with `--plain-name` scoped to the single affected
test.

| # | Mutation | Red output | Restored |
|---|---|---|---|
| 1 | `refreshEfforts`: `_notify()` → `await loadSessionData()` (the whole-session reload) | `Expected: <1> Actual: <3>` — "the merge refreshes the touched effort once — a whole-session reload would notify more than once", Mock and Hive | yes |
| 2 | `refreshEfforts`: `_timerManager.clearAll()` added before `_notify()` | `Expected: an object with length of <1> Actual: []` — "nothing cleared the rest", Mock and Hive | yes |
| 3 | `refreshHeldEfforts`: guard reduced to `if (target == null) return;` | `Expected: <0> Actual: <1>` — "a session the phone does not hold is never refreshed", Mock and Hive | yes |
| 4 | `_settleNow`: hook called unconditionally, outside the `changedEffortIds.isNotEmpty` check | `Expected: <0> Actual: <1>` — "a redelivery writes nothing, so the hook never fires", Mock and Hive | yes |
| 5 | `WatchSessionImporter.apply`: held branch taken for every session (`phoneOwnsSession \|\| true`) | `Expected: ['s-w1'] Actual: []` — "the merge did not swallow the import" (S-17), Mock and Hive | yes |

Red proof 2 is a `clearAll` mutation rather than a `loadSessionData` one on purpose: a whole-session
reload re-reads the rests from the repository, so it does **not** drop an open rest record and would
not have failed the rest assertion. `clearAll` is the mutation that isolates "the refresh cleared the
running timer".

Red proof 5 is S-17's own: the regression only means something if a merge that takes an unheld
session is caught, and the import is exactly what it swallows.

Green re-run after the restores:

```
gateway.sh test test/watch_session_merge_test.dart --plain-name S-16
00:00 +6: All tests passed!          (Mock ×3, Hive ×3)
gateway.sh test test/watch_session_merge_test.dart --plain-name S-17
00:00 +2: All tests passed!          (Mock ×1, Hive ×1)
```

## Phase 2 runs

| Command | Result |
|---|---|
| `gateway.sh test test/watch_session_merge_test.dart --plain-name Mock` | `+12` — All tests passed! |
| `gateway.sh test test/watch_session_merge_test.dart --plain-name S-16` | `+6` — All tests passed! |
| `gateway.sh test test/watch_session_merge_test.dart --plain-name S-17` | `+2` — All tests passed! |
| `gateway.sh test test/watch_session_merge_test.dart test/watch_session_import_test.dart` | `+69` — All tests passed! |
| `gateway.sh test test/watch_session_merge_test.dart test/watch_session_import_test.dart test/watch_session_finish_test.dart` | `+75` — All tests passed! (before S-17 landed) |
| `gateway.sh test test/watch_session_finish_test.dart` | `+8` — All tests passed! (the PR 1 file is green: Phase 1's override rewrote G3, so the Done Criteria's "expected red" does not apply) |
| `gateway.sh test` (full) | `01:58 +3909 ~1: All tests passed!` |
| `gateway.sh lint` | 196 issues, 0 errors — the baseline, unchanged |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches — the repo invariant |

Full suite 3901 → 3909 passing: **+8, exactly the four new tests ×2 groups**. No previously passing
test now fails.

## Phase 2 footprint

`gateway.sh git-diff --stat` (untracked `test/watch_session_merge_test.dart` is not in it):

```
lib/state/watch/watch_session_adoption_bridge.dart | 16 +
lib/state/watch/watch_session_inbox.dart           | 15 +
lib/state/watch/watch_sync_wiring.dart             |  4 +
lib/state/workout/session_core_io.dart             | 53 +++
lib/state/workout/workout_state.dart               |  7 +
```

Production: 95 insertions across the five files the plan predicted. `test/watch_session_import_test.dart`
was not touched — item 5 allows S-17 as a named case in the merge test file, and it needs the merge
wiring this file's `_phone` carries (A-33). `test/watch_session_finish_test.dart` is unchanged from
Phase 1's override.

One line outside the plan's Predicted Files: `docs/state_management/workout_state.md`'s session
lifecycle method table gained a `refreshEfforts(effortIds)` row — the new public method made that
table stale, and leaving it out would have the doc describe a state surface that no longer exists.
The narrative doc edits stay with Phase 3 (`docs/watch_session_sync.md`, `watch_surface.md`).

---

# Phase 3 — PR 1's assertions, the docs, the sweep

## Item 1 — PR 1's assertions: verified, done in Phase 1

`test/watch_session_finish_test.dart`'s G3 case was rewritten by the governor override (see the
table above, and A-21). Confirmed by re-reading the file at the start of this phase: the case is
`a set logged on the watch lands in the session the phone holds`; it asserts the merged outcome — one
entry per effort on the phone's own rows (`obs-sl-1-0-reps`/`obs-sl-1-0-weight`), `sx-1` applied
(`appliedAtMs` non-null) and receipted, a redelivery staging no second row and writing no second
entry, the later end and rating applied, the merge creating no effort (`sl-1`, `sl-2` only, D-14),
and the session staying ended. The header scenario map points at it. Items 3–4 of the override list
all hold.

**One residue fixed.** Phase 1's override left the header map's
`G1 never resurrect a finished session → ...` line duplicated. One copy was removed and the merge
line kept; nothing else in the file changed. Doc-comment only — the file's test count is unchanged.

**One residue fixed.** Phase 1's override left the header map's
`G1 never resurrect a finished session → ...` line duplicated (the same line twice, lines 8 and 10 of
the map). One copy was removed; nothing else in the file changed. Doc-comment only — the file's test
count is unchanged.

## Item 4 — the residue sweep

| Command | Result |
|---|---|
| `grep -n "sessionScopedKinds\|the merge PR 3 owns" lib/core/services/watch_session_importer.dart` | **no matches** — the predicate and the deferral note are gone from the importer |
| `grep -rn "sessionScopedKinds" lib/state lib/features lib/widgets lib/core` | one match: `lib/state/watch/live_session_mirror_state.dart:129` — the mirror's live constant, left untouched (A-25) |
| `grep -rn "not merged\|staged and stay staged" docs/` | matches only under `docs/plans/` (the PR 2a plan's own task text and PR 1's plan/evidence) |
| `grep -rn "G3 the wrist\|staged, unreceipted" docs/*.md docs/state_management` | **no matches** — the docs set no longer names the removed case or the staged-only invariant |

The mirror's `sessionScopedKinds` (`lib/state/watch/live_session_mirror_state.dart:129`) is not
residue of the merge: it names the entry kinds a session snapshot must carry, is a live constant
documented at `docs/state_management/watch_surface.md:64`, and the importer's deleted copy mirrored
it. Left as it stands (A-25).

## Items 2–3 — the docs, rewritten and named

| Path | Size | Change |
|---|---|---|
| `docs/watch_session_sync.md` | under 20 KiB (the viewer returns it whole; the 64 KiB ceiling is asserted by `test/docs_indexing_contract_test.dart`) | Structure row now "Merging a wrist's set into the session the phone holds"; the "One session id, one row" invariant now states that a staged wrist effort row becomes a row of the effort the session already has under the row id the phone gave the slot (D-14) and is receipted; the "What does not sync" section's false bullets are rewritten — "not merged" / "staged and stay staged" / "attached only where the importer places an effort" are gone, the discarded-session limitation stays |
| `docs/state_management/watch_surface.md` | 39.3 KB (tool-reported) | the `WatchIncomingRouter` section's `G3` reference now names the merge case alongside `S-4`, `S-5`, `G1` |
| `docs/watch_session_capture.md` | under 20 KiB | **no update required** — its "two session-scoped kinds are staged" invariant is about the live inbox/mirror staging, which the merge did not touch (it is not the importer predicate) |
| `docs/state_management/workout_state.md` | under 20 KiB | **no update required** — the `refreshEfforts(effortIds)` row added in Phase 2 is accurate: a refresh of the named efforts, not a reload (S-16) |

Every `Verified by` line added in these edits names a test that exists in the tree: the merge cases
`S-9 a wrist set reaches the live phone session` and `S-12 a slot the session does not have` in
`test/watch_session_merge_test.dart`, `S-2 a running phone session is answered with its own ladder` in
`test/watch_session_projection_test.dart`, and
`a set logged on the watch lands in the session the phone holds` in `test/watch_session_finish_test.dart`.
Nothing unshipped or deferred is named, and no future PR is cited.

## Phase 3 runs

| Command | Result |
|---|---|
| `gateway.sh lint` | **196 issues, 0 errors** — the baseline, unchanged (log `.work/gateway/lint-20261005-201050-90970.log`) |
| `gateway.sh test <finish, merge, import, parity files>` | **`+114: All tests passed!`** |
| `gateway.sh test` (full) | **`01:48 +3909 ~1: All tests passed!`** — 0 failures, the same count Phase 1 and Phase 2 froze (log `.work/gateway/test-20261005-201151-91297.log`) |
| `gateway.sh test test/docs_indexing_contract_test.dart` | **`+9: All tests passed!`** — the docs guard: the ceiling, the warning band, relative links, orphan pages and the prohibited-prose patterns all hold after these edits |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches — the repo invariant |

These are the post-edit observations for this phase. Every Dart file was final before the targeted run
and the two full runs (this phase's only Dart edit was the comment line in
`test/watch_session_finish_test.dart`); lint ran with the plan file written (`flutter analyze` does not
read Markdown, so later evidence or plan prose cannot change its count); and the docs guard was re-run
after the evidence file's last edit. Phase 3 adds no tests (docs plus a
comment-only edit), so the full suite stays at 3909. No previously passing test now fails.

**Footprint of the whole PR** (`gateway.sh git-diff --stat`): the 12 files the plan predicted across
Phases 1–3 — 5 production files, 2 test files, `docs/watch_session_sync.md` (42 lines),
`docs/state_management/watch_surface.md` (5), `docs/state_management/workout_state.md` (1), the plan
and its evidence, plus the series index. Phase 3's own share is the three doc files, the plan, the
evidence file and one comment line in `test/watch_session_finish_test.dart`.

**Size measurement.** The exact byte counts of docs under 20 KiB cannot be obtained with the tools
available in this mode: the file viewer reports a size only for files it truncates, and the docs
guard prints only files near or over the 64 KiB ceiling. What is observed: the viewer returned each of
these files whole (so each is under its ~20 KiB truncation point), `watch_surface.md` is reported as
39.3 KB, and the guard's ceiling and warning-band tests pass (`+9`).

# Fix round 1 — Review 1's remediation (bounded)

Review 1's checklist is `2026-10-05-15b-watch-session-sync-pr2-plan.review.md` (warnings only). Four
items, in the order the brief gives them. The suite is at 3909 before this round; the round adds 3
test cases (2 of them run in both the `Mock` and `Hive` groups).

## Item 1 — S-15's fourth clause: the held session's summary

`test/watch_session_finish_test.dart`: its `_end(sessionId)` helper gained two optional named
parameters, `avgHeartRateBpm` and `maxHeartRateBpm`, emitted only when present, so the four existing
callers are byte-identical in behaviour (no test outside the merge case changed). The merge case
(`a set logged on the watch lands in the session the phone holds`) now ends the wrist's session with
`avgHeartRateBpm: 140, maxHeartRateBpm: 165` and asserts, after the end and the rating:

```dart
final summaries = await repository.getSensorSummariesForSession('s-w1');
expect(summaries.map((summary) => summary.id), ['sensor-session-s-w1'],
    reason: 'S-15 the held session\'s end attaches one session summary');
expect(summaries.single.avgHeartRateBpm, 140);
expect(summaries.single.maxHeartRateBpm, 165);
```

and, after the redelivered end/rating pair, that the session still has exactly one summary. The
scenario's remaining three clauses were already asserted by the case (`sx-1` an entry of `sl-1`, the
rating 4, the session's own end untouched, all three rows applied and receipted).

**Recorded, not absorbed:** the case's set fixture is `reps: 5, loadKg: 80`, not S-15's
`reps: 8, loadKg: 40`. A-32 said "S-15's exact fixture", which was false; A-32 now says what the case
actually runs. Changing the fixture to 8/40 would have made the case a different scenario for no
gain, so it was not changed.

## Item 2 — the abandoned end: the divergence, decided and pinned

The merge attaches the wrist's summary for an abandoned readable end; the import path (`apply` → the
`end.status != _completed` early return) consumes an abandoned end and attaches nothing. The brief's
decision (its option b) is kept: for a session the phone already holds, the wrist's heart rate was
measured during *that* session, and the phone's own end and lifecycle own the session's fate — a
discard takes the summary with the session. The divergence is written into A-27 (rewritten in place;
the false parity claim is gone) and pinned by a new test in `test/watch_session_merge_test.dart`,
`D-19 a held session takes the wrist's end summary, abandoned or not`: an abandoned end with heart
rate attaches `sensor-session-s-w1` once, the end is consumed (`appliedAtMs` non-null), and the
phone's session is still unended. It runs in both groups.

## Item 3 — the guard: an end the phone cannot read

`lib/core/services/watch_session_importer.dart`, `_mergeHeld`:

```dart
-    if (endRow != null && endRow.appliedAtMs == null) {
+    if (end != null && end.row.appliedAtMs == null) {
       await pass._attachSessionSummary();
     }
```

`_End.parse` returns null for an end without a readable `loggedAt`/`startedAt`/`endedAt`/`status`,
and `_attachSessionSummary` opens with `final end = this.end!`: the old guard let a row the phone
cannot read reach a null-check operator. The import path was already safe (it returns before `run`
when `end == null`); the merge needed the same spelling. The comment above it now says an unreadable
end attaches nothing.

**Red first.** A schema-valid `session_end` without `loggedAt` cannot travel the protocol (the
envelope schema requires it), so the test stages the malformed row directly with
`stageWatchInboxEntry` and then sends a set in the same pass, so both rows reach one merge. Observed
**before** the fix (`gateway.sh test test/watch_session_merge_test.dart --plain-name Mock`):

```
00:00 +8 -1: Mock D-19 an end the phone cannot read attaches no summary [E]
  the watch session inbox failed: Null check operator used on a null value
  package:matcher                                                fail
  test/watch_session_merge_test.dart 160:34                      _phone.<fn>
  package:omnitrain/state/watch/watch_session_inbox.dart 244:17  WatchSessionInbox.receive
00:00 +13 -1: Some tests failed.
```

**Green after the fix** (same command): `00:00 +14: All tests passed!`. The test asserts no failure
was reported (`phone.failures` empty, and the harness's `onFailure` is a `fail`), the set merged in
the same pass, the unreadable end consumed (`appliedAtMs` non-null — a row nothing can use is not one
the wrist re-sends forever), and no summary attached.

## Item 3 and item 2 — the mutation proofs

Both item 1's new assertions and item 2's case pass before any of this round's edits, so each was
shown load-bearing by mutation, restoring the exact original line afterwards.

| Mutation | Command | Observed |
|---|---|---|
| `_mergeHeld`: the `await pass._attachSessionSummary();` line commented out | `test test/watch_session_merge_test.dart test/watch_session_finish_test.dart --plain-name Mock` | **`+7 -1`** on `Mock D-19 a held session takes the wrist's end summary, abandoned or not`, `Expected: ['sensor-session-s-w1'] Actual: []`, `+13 -1: Some tests failed.` |
| the same mutation, finish file only | `test test/watch_session_finish_test.dart --plain-name "a set logged on the watch lands in the session the phone holds"` | **`+0 -1`**, `Expected: ['sensor-session-s-w1'] Actual: []`, reason `S-15 the held session's end attaches one session summary` |
| `_mergeHeld`: the guard gains `&& end.status == _completed` | `test test/watch_session_merge_test.dart --plain-name Mock` | **`+7 -1`** on the abandoned-end case, the same `Expected: ['sensor-session-s-w1'] Actual: []`, `+13 -1: Some tests failed.` |

**After restoring the original line exactly**, `test test/watch_session_merge_test.dart
test/watch_session_finish_test.dart`: **`+36: All tests passed!`** (the Hive group of the merge file
included). No mutation was left applied.

## Item 4 — the docs

`docs/watch_session_capture.md`, "Why an import waits for the session end" — one added clause pair:
a session the phone already holds is the exception, its wrist effort rows merge into the efforts that
session already has as they arrive with no end to wait for, and its end then adds only what the
phone's session does not have (its rating, and its heart-rate summary, an abandoned end included).
Cited `test/watch_session_merge_test.dart` (`S-9`, `D-19`), the doc set's style. This supersedes the
Phase 3 table row above that reads `docs/watch_session_capture.md ... no update required` and A-38's
closing sentence; A-39 records the correction. Structure, rationale and invariants elsewhere in the
file are unchanged, so nothing else was edited.

## Fix round 1 footprint

| Path | Change |
|---|---|
| `lib/core/services/watch_session_importer.dart` | the `_mergeHeld` guard (1 line) and its comment (2 lines) — within the plan's Predicted Files |
| `test/watch_session_merge_test.dart` | 2 new cases in `_mergeTests` (so 4 runs across both groups), `_end` gained an optional `status`, one line in the header scenario map |
| `test/watch_session_finish_test.dart` | `_end` gained two optional named parameters; the merge case's end carries heart rate and gained 5 assertions |
| `docs/watch_session_capture.md` | the one clause pair (item 4) |
| the plan, this evidence file | A-27/A-32 corrected, A-39 added, Progress line |

## Fix round 1 runs

| Command | Result |
|---|---|
| `gateway.sh test test/watch_session_merge_test.dart --plain-name Mock` (before the guard fix) | **`+8 -1` → `+13 -1: Some tests failed.`** — the red-first proof above |
| `gateway.sh test test/watch_session_merge_test.dart --plain-name Mock` (after the guard fix) | **`+14: All tests passed!`** |
| `gateway.sh test test/watch_session_merge_test.dart test/watch_session_finish_test.dart` | **`+36: All tests passed!`** — both groups of the merge file, and the finish file |
| the two mutation runs | **`+7 -1`** and **`+0 -1`** respectively; see the table above |
| the two runs after restoring the guard exactly | **`+36: All tests passed!`** |
| `gateway.sh lint` (first run) | **198 issues, 0 errors** — 2 above the baseline, both `use_null_aware_elements` on the new `_end` helper's collection-`if`; rewritten to the repo's `'key': ?value` idiom |
| `gateway.sh lint` (after that rewrite) | **196 issues, 0 errors** — the baseline (log `.work/gateway/lint-20261005-204823-17748.log`) |
| `gateway.sh test` (full) | **`01:48 +3913 ~1: All tests passed!`** — 0 failures: 3909 + 4 (the 2 new merge cases in each of the 2 groups); the finish file's added assertions are inside an existing case, so they add no count (log `.work/gateway/test-20261005-204911-17995.log`) |
| `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no matches — the repo invariant |
| `gateway.sh test test/docs_indexing_contract_test.dart` (re-run after the plan and evidence edits) | **`+9: All tests passed!`** — the ceiling, the warning band, relative links, reachability and the prohibited-prose patterns all hold with the doc clause and this section in place |

Both Dart files were final before the targeted runs and the full run; lint ran with the plan file in
its current state (`flutter analyze` does not read Markdown). No previously passing test now fails.

