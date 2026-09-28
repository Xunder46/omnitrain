# Feature: Stats PR 3b — The protocol carries a distance's source, and the watch import records it

> Status: READY (Iteration 1, not started).
> Next handoff: Copilot (DeepSeek V4.1 Flash, local, in this checkout), Step 0 → Phase 1 → 2 → 3, then
> `/code-reviewer`.
> Series: PR 3b. Index: `.github/agents/plans/2026-09-26-03-stats-pr3-distance-series-index.md`.
> Base: `develop` (PR 3a2 is merged). Work directly on `develop`.
> Branch policy (owner): all work happens on `develop`. Never create, switch or delete a branch. Copilot never
> commits, merges or pushes.
> Evidence: `2026-09-27-03b-stats-pr3b-distance-source-import-plan.evidence.md` (baselines, facts H1–H12, the
> tables you fill). The reviewer writes `…plan.review.md`. Source of scope: the series index row "3b"; the
> 3a2 review §8 (F-6, F-7, 3a2 O-2, 3a2 O-4); the owner's answers of 2026-09-27.
> Scope check (2026-09-27): under 500 lines, 3 phases. Tracks are the phone plus the sync contract (the Swift
> validator rides with the contract), which is one soft signal. 10 decisions, 14 scenarios, about 200
> predicted production lines, no missing prerequisite. Within budget.

## What this PR does

1. **The protocol gains `distanceSource`** (`gps`, `entered` or `estimated`) for a timed entry's
   `distanceMeters`. It is allowed only on a `timed` entry that also has `distanceMeters`, and both validators
   enforce this with the same wording. The watch doesn't send it yet; PR 3c does.
2. **The watch import stores the source** on the distance row: the watch's value, or `entered` when it sent
   none (today every watch distance is dialled by hand). A timed entry without a distance gets no source.
3. **A guard test** replays add, edit, delete, skip, duplicate-block and watch-import sequences, and after
   every step checks for leftover, stray or unsourced rows. It closes 3a2's F-6 and F-7, or finds the path.
4. **Two small fixes:** the import reads row ids with `EntryRows.parseId` (3a2 O-2), and a new timed entry
   never takes an instance id another entry already holds (3a2 O-4).

Nothing visible changes on the phone: no screen, widget or header is added or changed.

## Decision Ledger

Immutable; changes are made by superseding entries.

| ID | Decision | Source |
|---|---|---|
| **D-332** | **Single release.** The whole Stats redesign ships at once. No user data exists for any of it, so nothing needs old-data handling, migration or backward compatibility. That includes the watch↔phone protocol: both apps ship together, and the protocol version stays 1. | Owner, 2026-09-27 |
| **D-333** | **The phone never sends a corrected distance to the watch.** A `correct_entry` correction carries no distance; S-875 pins it. | Owner (Q2), 2026-09-27 |
| **D-334** | **The field `distanceSource`.**<br>• Value: `gps`, `entered` or `estimated` (3a D-301).<br>• On a `timed` entry only. Message: `distanceSource is carried only by timed entries; <entryId> is a <kind> entry`.<br>• Only together with `distanceMeters`. Message: `distanceSource travels with distanceMeters; <entryId> carries no distanceMeters`.<br>• Optional in 3b. PR 3c makes it required when the watch sends it. | Claude |
| **D-335** | **Import mapping.** For a timed entry with `distanceMeters` greater than 0, the stored `value_source` is the wire `distanceSource`, or `entered` when it is absent. A watch that sends no source dialled the distance by hand, since watch-started sessions never run GPS (evidence H6). No distance means no source. PR 3c removes the "absent means `entered`" rule. | Claude |
| **D-336** | **A later sync never changes a distance the phone wrote**, neither its value nor its source. That covers a redelivery and an entry move, which re-keys rows by copying them whole. It enforces 3a D-302 for the import. | Claude |
| **D-337** | **The import reads ids with `EntryRows.parseId`** (3a2 O-2). The import keeps its own numbering: dense, and it appends at the highest number plus 1. | Claude |
| **D-338** | **Unique instance ids** (3a2 O-4). `TimerManager.addTimedEntry` keeps the id shape `timed-<effortId>-<entryIndex>-<ms>`. If that exact id already exists among the effort's instances, it adds 1 to `<ms>` until the id is free. Imported ids (`timed-<sessionId>-<entryId>`) don't change. | Claude |
| **D-339** | **The row guard** (F-6 and F-7, given D-332).<br>• After every step: I-a (timed: one distance row and one extra-weight row per instance; hold: one extra-weight row per instance); I-b (set: every entry-number group has exactly one reps row and one weight row, and at most one extra-weight row); I-c (every distance row greater than 0 has a source).<br>• If everything passes on current code, F-6 and F-7 close as NOT APPLICABLE.<br>• If a sequence fails, the fix is allowed only as a one-function change that follows 3a2's rules (deleting an entry removes all its rows; a new row takes the highest number plus one). Otherwise STOP. | Owner-directed; Claude |
| **D-340** | **Docs.** Edit only:<br>• `watch/sync_protocol/PROTOCOL.md` (Phase 1);<br>• `.github/agents/docs/watch_session_capture.md`, `distance_source.md` and `data_models.md` (Phase 3).<br>No index page changes, because 3b adds no widget, screen or header. Old-data wording elsewhere is left for PR 3a3. | Claude |
| **D-341** | **Proof.** Record at least 2 named mutations using the copy-aside method (M1, M2; M3 and M4 are recommended), and a doc-claim table with a test pointer for every edited behaviour sentence. | Owner-directed |

## Invariants that bite in this PR

- **Parity:** Mock and Hive give identical results wherever a scenario says Mock/Hive.
- **One wording per refusal,** identical on the Dart and Swift validators.
- **Unchanged:** the phone UI; everything in `lib/watch/` and `watch/watchos/Sources/` except
  `SyncProtocolValidator.swift`; `watch/contract/*.json`; every existing fixture file (add new ones only).

## Acceptance Criteria

- **AC-1:** `distanceSource` is accepted with a distance on a timed entry and refused anywhere else
  (S-871–S-874). **AC-2:** the wire can't carry a phone-side distance change (S-875).
- **AC-3:** the import stores the watch's source or `entered`, and no source without a distance (S-876, S-877).
- **AC-4:** a phone-written distance survives a redelivery and a move (S-878); instance ids never repeat
  (S-880). **AC-5:** no sequence creates a leftover, stray or unsourced row (S-883–S-887).

## Scenarios

**Fixture envelope** (every Phase 1 fixture unless it says otherwise): `"protocolVersion": 1`,
`"sessionId": "s-ds"`, `"type": "observations_up"`, `"origin": "watch"`, `"sentAt": "2026-09-27T11:00:00Z"`,
and a unique `"messageId"`. **Timed entry base:** `"kind": "timed"`, `"sessionExerciseId": "sx-run"`,
`"exerciseId": "ex-run"`, `"startedAt"` 20 minutes before `"loggedAt"`, and `"eventId"` equal to
`"entryId"`.

### Scenarios for Phase 1: the protocol

#### S-871: A timed entry carries `distanceSource` with its distance
- Fixture: `watch/sync_protocol/fixtures/valid/observations_up_distance_source.json`. Three timed entries:
  - `e-ds-gps`: loggedAt `2026-09-27T10:30:00Z`, `distanceMeters` 5000, `distanceSource` `"gps"`;
  - `e-ds-entered`: loggedAt `2026-09-27T10:31:00Z`, 3000, `"entered"`;
  - `e-ds-est`: loggedAt `2026-09-27T10:32:00Z`, 4200, `"estimated"`.
- Expected: accepted by both validators.
- Must fail if the schema has no `distanceSource` property. It is then refused with `unexpected_field`.

#### S-872: `distanceSource` on a round is refused
- Fixture: `invalid/observations_up_distance_source_on_round.json`. One entry `e-ds-round`: `"kind":
  "round"`, `"sessionExerciseId": "sx-bjj"`, `"exerciseId": "ex-bjj"`, `startedAt` `…10:25:00Z`, `endedAt` and
  `loggedAt` `…10:30:00Z`, `roundNumber` 1, `distanceMeters` 800, `distanceSource` `"gps"`.
- Expected: `semantic_violation`, with a reason containing `distanceSource is carried only by timed
  entries`.
- Must fail if either stack's kind table lacks `distanceSource`. The fixture is then accepted.

#### S-873: `distanceSource` without a distance is refused
- Fixture: `invalid/observations_up_distance_source_without_distance.json`. One timed entry `e-ds-nodist`
  (loggedAt `…10:30:00Z`) with `distanceSource` `"entered"` and no `distanceMeters`.
- Expected: `semantic_violation`, with a reason containing `distanceSource travels with distanceMeters`.
- Must fail if either stack lacks the travels-with rule.

#### S-874: An unknown source is refused
- Fixture: `invalid/observations_up_distance_source_unknown.json`. One timed entry `e-ds-bad` with
  `distanceMeters` 3000 and `distanceSource` `"pedometer"`.
- Expected: `invalid_enum_value`, with a reason containing `pedometer`.
- Must fail if the property is a free string instead of the three-value enum.

#### S-875: A correction cannot carry a distance (D-333)
- Fixture: `invalid/structure_change_correction_distance.json`, with `"type": "structure_change"`,
  `"origin": "phone"` and `"payload": {"changeId": "chg-ds-1", "changes": [{"kind": "correct_entry",
  "entryId": "e-ds-entered", "correction": {"distanceMeters": 5200}}]}`.
- Expected: `unexpected_field`, with a reason containing `distanceMeters`.
- Green before and after.
- Must fail if a correction ever gains a distance field.

### Scenarios for Phase 2: the import and instance ids

**Import setup.**
- Mock repository with `seedCaptureCatalog(repository)`, which provides `ex-run` "Run" and `ex-bench`
  "Barbell Bench Press".
- An inbox built as `_inbox` is in `test/watch_session_import_test.dart:59-76`. Deliver one message per
  event (`_deliverEach`, `:78-88`).
- End with `session_end`: startedAt `…10:00:00Z`, endedAt `…11:30:00Z`.

#### S-876: The import stores each source the watch sent
- Events: timed `e-g` (loggedAt `…10:30:00Z`, 5000, `"gps"`); timed `e-n` (`…10:52:00Z`, 3000,
  `"entered"`); timed `e-s` (`…11:14:00Z`, 4200, `"estimated"`); then `session_end`.
- Expected: the Run effort's distance rows, in entry order, are 5000 `gps`, 3000 `entered` and 4200
  `estimated`.
- Must fail if the import ignores the wire value. All three would then read the same.

#### S-877: A dialled distance is stored as `entered`; no distance gets no source
- Events: timed `e-d` (`…10:30:00Z`, `distanceMeters` 2500, no `distanceSource`); timed `e-z`
  (`…10:52:00Z`, no `distanceMeters`); then `session_end`.
- Expected: rows 2500 `entered`, and 0.0 with no source.
- Must fail if the 2500 row has no source, or if the 0.0 row has one.

#### S-878: A distance the phone wrote survives every later sync (Mock/Hive)
- Events: timed `e-r` (`…10:30:00Z`, 3000, `"estimated"`), then `session_end`.
- Then:
  - `WorkoutState.loadHistoricalSession` loads the session;
  - the phone calls `setEntryDistance(<Run effort id>, 0, 5200.0)`;
  - (a) re-deliver `e-r`'s event with a new messageId;
  - (b) deliver a late timed `e-early` (`…10:05:00Z`, 1000, no source), which moves `e-r` to entry 1.
- Expected (after each step, reload with `loadHistoricalSession` and read `getEffortDistanceEntries`):
  after (a), entry 0 is 5200 `entered`; after (b), the entries are [1000 `entered`, 5200 `entered`].
- Green before and after (evidence H8).
- Must fail if a move rebuilds the row from the wire (entry 1 reads 3000 `estimated`) or drops its source.

#### S-880: A new timed entry never reuses an instance id (pure)
- The helper `TimerManager.uniqueTimedInstanceId({existingIds, effortId, entryIndex, nowMs})`:
  - (a) existing {`timed-e-t-1-1000`}, arguments (`e-t`, 1, 1000) → `timed-e-t-1-1001`;
  - (b) existing {`timed-e-t-1-1000`, `timed-e-t-1-1001`} → `timed-e-t-1-1002`;
  - (c) existing {} → `timed-e-t-1-1000`.
- Must fail if the helper returns the plain id: (a) would give `timed-e-t-1-1000`.

### Scenarios for Phase 3: the row guard

Each runs on Mock and Hive (`harnessFactories`, `test/helpers/repository_harness.dart`); on Hive, `restart()`
and reload after every step, then call `expectRowInvariants` (I-a, I-b, I-c; Step 3.1). Seed exercises with
`seedExercise(repo, id:, name:, capabilities:)`: `ex-run` "Easy Run" [`time`, `distance`], `ex-bench` "Bench
Press" [`reps`, `sets`, `load`], `ex-pull` "Pull-up" [`reps`, `sets`], `ex-plank` "Plank" [`hold`].

#### S-883: A phone timed sequence
- Setup: `createNewSession(modality: 'cardio_endurance')`; `addExerciseToSession` with "Easy Run", which
  gives 1 entry.
- Steps:
  1. `addEntry` × 3;
  2. `setEntryDistance(run, 2, 3000.0)`;
  3. `deleteEntry(run, 0)`;
  4. `addEntry(run)`;
  5. `updateEntryValue(run, 1, 'extra-weight', 5.0)`;
  6. `deleteEntry(run, 1)`.
- End: 3 entries; distances [0, 0, 0]; extra weights [0, 0, 0]; 3 distance rows and 3 extra-weight rows.
- Must fail if a delete leaves a row behind (4 distance rows at the end).

#### S-884: A phone set sequence
- Setup: `createNewSession(modality: 'resistance_lifting')`; "Bench Press" (has `load`) and "Pull-up" (no
  `load`), each with 3 sets from `addExerciseToSession` plus `addEntry` × 2.
- Steps:
  1. `updateEntryValue(bench, 1, 'reps', 9)`;
  2. `markSetSkipped(bench, 2)`;
  3. `deleteEntry(bench, 0)`;
  4. `addEntry(bench)`;
  5. `updateEntryValue(pull, 1, 'extra-weight', 5.0)`;
  6. `deleteEntry(pull, 0)`;
  7. `addEntry(pull)`.
- End: Bench reps are [9, 0 (skipped), 10]; Pull-up extra weights are [5.0, 0.0, 0.0].
- Must fail if a Pull-up delete leaves its extra-weight row. A 4th group, with no reps, would appear.

#### S-885: A hold sequence
- Setup: `createNewSession(modality: 'isometric_stretching')`; "Plank" with 3 holds.
- Steps:
  1. `updateEntryValue(plank, 2, 'extra-weight', 7.0)`;
  2. `deleteEntry(plank, 0)`;
  3. `addEntry(plank)`.
- End: extra weights [0.0, 7.0, 0.0]; 3 extra-weight rows.
- Must fail if the hold's write numbers its row with the set rule (3a2 F-4). The end would then be
  [7.0, 0.0, 0.0] or 2 rows.

#### S-886: Duplicating a block
- Setup:
  - `createNewSession(isRolling: true)`, then `addSessionBlock()`;
  - "Easy Run" (2 entries), assigned to the block with `assignEffortToBlock`;
  - `setEntryDistance(run, 1, 2000.0)`;
  - "Bench Press" (2 sets), in the same block.
- Steps:
  1. `cloneSessionBlock(blockId)`;
  2. `deleteEntry(copyRun, 0)`;
  3. `addEntry(copyRun)`.
- End: the source run's distances are [0, 2000]; the copy's are [2000, 0].
- Must fail if the copy's added row takes a number the copy already holds.

#### S-887: A watch import, phone edits, then late watch entries
- Import, as in the Phase 2 setup:
  - timed `e-r` (Run, `…10:30:00Z`, 3000, no source);
  - sets `e-b1` (`…10:40:00Z`) and `e-b2` (`…10:45:00Z`) on Bench, each reps 5 with `loadKg` 80;
  - `session_end` (`…10:00:00Z`–`…11:00:00Z`).
- Then load the session, and apply these steps:
  1. `setEntryDistance(run, 0, 3500.0)`;
  2. `deleteEntry(bench, 0)`;
  3. `addEntry(bench)`;
  4. deliver a late set `e-b3` (`…10:50:00Z`, reps 6);
  5. deliver a late timed `e-r0` (`…10:05:00Z`, 1000, no source).
- End: Run is [1000 `entered`, 3500 `entered`]; Bench reps are [5, 10, 6].
- Must fail if the late set takes a row number the phone's added set holds. I-b then fails.

## Iteration 1

### Executor block

Read this first. Every rule you need is here.

**Step 0a — preconditions. If any check fails, STOP and report.**
1. `git branch --show-current` prints `develop`.
2. `git cat-file -e develop:lib/core/utils/entry_rows.dart && git cat-file -e
   develop:test/entry_identity_test.dart && echo ok` prints `ok`. That shows PR 3a2 is on `develop`.
3. `git log develop -5 --format=%s`: copy the lines into the evidence file (the 3a2 commit subject).
4. `git status --short | grep -v "^.. .github/agents/plans/"` prints nothing.

**Step 0b — branch:** stay on `develop`. Never create or switch branches (owner policy).

**Step 0c — baselines. STOP if any test fails or a run hangs for 10 minutes.**
- `flutter test > /tmp/pr3b_base.log 2>&1; echo "exit $?"; tail -2 /tmp/pr3b_base.log` should give about
  `+3097 ~1: All tests passed!`. Record the exact line.
- `flutter analyze > /tmp/pr3b_base_an.log 2>&1; tail -1 /tmp/pr3b_base_an.log` should give `241 issues
  found.`. Record it.
- `cd watch/watchos && swift test > /tmp/pr3b_base_swift.log 2>&1; grep "Executed" /tmp/pr3b_base_swift.log |
  tail -1` should give `Executed 242 tests, with 0 failures`.

**Rules for every step.**
- Do one numbered step at a time, and do only what it says.
- Never commit, merge, push or delete a branch unless the owner asks. The owner merges and deletes.
- Edit only the files listed in the current phase's Predicted Files. If you need another file, STOP and
  report.
- **Red proof (copy-aside method; never use `git stash` — this checkout holds old stashes):** write each new
  test before its fix and run it. It must fail as its scenario says. Record the failure line in the evidence
  red→green table. If it passes when it should fail (and it isn't marked "green before and after"), STOP and
  report.
- **Mutation method (copy-aside):**
  1. `cp <file> /tmp/<name>.orig`;
  2. make the one mutation;
  3. run the named test and record the failing value;
  4. `cp /tmp/<name>.orig <file>`;
  5. re-run and see green.
- Never loosen an existing assertion. If an existing test must change, STOP and report.
- Use plain `test()` for state and import tests; there are no widget tests in this PR.
- If `test/helpers/repository_harness.dart` and `test/helpers/watch_capture_import_harness.dart` are both
  imported, write `hide seedExercise` on the second import. Both files define it.

**Doc checklist.** Apply it to every doc edit (Phase 1 Step 1.9, Phase 3 Steps 3.4–3.6):
1. The doc keeps its **Scope.** paragraph first. If you add content that paragraph doesn't cover, widen it.
2. No visuals, values or labels: no colours, sizes, on-screen strings, or numbers defined in code.
3. No control inventories: no lists of buttons, gestures or fields.
4. No copied code, field lists, JSON or SQL.
5. No roadmap or scheduled-change notes: no "will", "later", "planned", "not yet", and no PR numbers.
6. Every behaviour sentence ends with a pointer: ``Verified by `test/<file>.dart` (S-8xx).`` Delete any
   behaviour sentence that has no pointer.
7. No absolute words ("only", "every", "never", "all", "nothing else", "single", "one write") unless the
   same sentence cites a guard test that enforces the claim.
8. Every table row has the same number of cells as the header.
9. Add each added or changed behaviour sentence to the evidence doc-claim table (doc:line, sentence,
   pointer, guard).

### Phase 1: The protocol field (Copilot)

1.1. [ ] Create the five fixture files described in S-871–S-875 under `watch/sync_protocol/fixtures/`
     (`valid/` or `invalid/`, as named), using the fixture envelope above.
1.2. [ ] Add five entries to `watch/sync_protocol/fixtures/manifest.json`:
     - `{"path": "valid/observations_up_distance_source.json", "type": "observations_up", "scenario":
       "S-871"}`;
     - for each invalid fixture: its `path`, `type`, `scenario`, and the `expectedCode` and
       `expectedReasonContains` from its scenario.
1.3. [ ] Red run. `flutter test test/sync_protocol_fixtures_test.dart > /tmp/pr3b_red1.log 2>&1` must fail on
     S-871–S-874. S-875 passes. Record the failures.
1.4. [ ] In `watch/sync_protocol/schemas/envelope.schema.json`, `$defs.entry.properties`, after
     `"distanceMeters"`, add the property `"distanceSource"`, with `"enum": ["gps", "entered", "estimated"]`
     and a one-line `"description"`.
1.5. [ ] In `lib/core/sync_protocol/message_validator.dart`, map `_captureFieldKinds`: add the entry
     `'distanceSource': ['timed'],` right after `'steps': ['timed'],`.
1.6. [ ] In the same file, in `_captureRejections`, next to the `_heartRatePairRejections` call, add this
     rule: an entry with `distanceSource` and no `distanceMeters` gives `SyncProtocolRejection(code:
     _semanticViolation, path: '$at.distanceSource', message: 'distanceSource travels with distanceMeters;
     $entryId carries no distanceMeters')`.
1.7. [ ] In `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`, `captureFieldKinds`: add
     `("distanceSource", ["timed"]),` right after `("steps", ["timed"]),`.
1.8. [ ] In the same Swift file, in `captureRejections`, next to `heartRatePairRejections`, add the same rule
     with path `"\(at).distanceSource"` and the same message text as Step 1.6.
1.9. [ ] `watch/sync_protocol/PROTOCOL.md`:
     - in the "Session capture (normative)" table, add the row `` | `distanceSource` | `timed`, with
       `distanceMeters` | Where the distance came from: `gps`, `entered` or `estimated` | ``;
     - after the table, add the sentence "A phone-side change to a distance is never sent to the watch: a
       `correct_entry` correction carries no distance (`fixtures/invalid/structure_change_correction_distance.json`)."

**Red → green:** S-871–S-874 fail at Step 1.3 and pass after Steps 1.4–1.8. S-875 is green before and after.

**Done Criteria:**
- `flutter test test/sync_protocol_fixtures_test.dart test/watch_session_engine_test.dart
  test/live_mirroring_test.dart test/watch_reconciliation_cross_stack_test.dart > /tmp/pr3b_p1.log 2>&1; echo
  "exit $?"` → exit 0.
- `cd watch/watchos && swift test > /tmp/pr3b_p1_swift.log 2>&1; grep "Executed" /tmp/pr3b_p1_swift.log |
  tail -1` → `Executed 242 tests, with 0 failures`.
- The full `flutter test` → exit 0 and `All tests passed!`.
- `flutter analyze` → at most 241 issues and 0 errors; `message_validator.dart` has 0.

**Predicted Files:** the 5 new fixture files; `watch/sync_protocol/fixtures/manifest.json`;
`watch/sync_protocol/schemas/envelope.schema.json`; `lib/core/sync_protocol/message_validator.dart`;
`watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`; `watch/sync_protocol/PROTOCOL.md`; the
evidence file.

### Phase 2: The import records the source; unique instance ids (Copilot)

2.1. [ ] Create `test/distance_source_import_test.dart` with S-876, S-877, S-878 and S-880, as plain
     `test()`s.
     - Copy `_repository`, `_inbox`, `_deliverEach`, `_set` and `_end` from
       `test/watch_session_import_test.dart:52-152`.
     - Add a `_timed(entryId, {loggedAt, distanceMeters, distanceSource})` builder:
       - kind `timed`, `sessionExerciseId` `sx-run`, `exerciseId` `ex-run`;
       - `startedAt` 20 minutes before `loggedAt`, `endedAt` equal to `loggedAt`;
       - omit `distanceMeters` and `distanceSource` when null.
     - Run S-878 on Mock and on Hive, using `harnessFactories`.
2.2. [ ] Red run. `flutter test test/distance_source_import_test.dart > /tmp/pr3b_red2.log 2>&1`:
     - S-876 must fail (the sources are null);
     - S-877 must fail (the 2500 row has no source);
     - S-880 must fail to compile (the helper is missing);
     - S-878 passes (green before and after).
     Record the results.
2.3. [ ] In `lib/core/utils/logged_entry_rows.dart`, `timedObservations`, add the named parameter
     `String? distanceSource` (default null), and pass it as `valueSource:` on the distance row only.
2.4. [ ] In `lib/core/services/watch_session_importer.dart`, class `_Entry`:
     - add the field `final String? distanceSource;` and its constructor parameter;
     - where `distanceMeters: _real(payload['distanceMeters'])` is parsed, add `distanceSource:` set to
       `payload['distanceSource']` when it is one of `'gps'`, `'entered'`, `'estimated'`, else null.
2.5. [ ] In the same file, at the timed branch that calls `LoggedEntryRows.timedObservations(... distanceMeters:
     entry.distanceMeters ?? 0.0 ...)`, pass `distanceSource:` as follows: when `(entry.distanceMeters ?? 0) >
     0`, use `entry.distanceSource ?? EffortObservation.sourceEntered`; otherwise null.
2.6. [ ] In the same file, in `_observationsByIndex`:
     - keep the `if (!row.id.startsWith(prefix)) continue;` line;
     - replace the `indexOf('-')` / `int.tryParse` parsing with `final parsed = EntryRows.parseId(row.id); if
       (parsed == null) continue;`;
     - use `parsed.number` as the index and `parsed.metricKey` as the metric key;
     - add `import '../utils/entry_rows.dart';`.
2.7. [ ] In `lib/state/workout/timer_manager.dart`:
     - add the static helper `uniqueTimedInstanceId({required Iterable<String> existingIds, required String
       effortId, required int entryIndex, required int nowMs})`. It starts from
       `'timed-$effortId-$entryIndex-$nowMs'` and adds 1 to the ms part while the id is in `existingIds`;
     - `addTimedEntry` uses it with the ids of `existing`.

**Red → green:** S-876, S-877 and S-880 fail at Step 2.2 and pass after Steps 2.3–2.7. S-878 is green before
and after; mutation M4 proves it bites.

**Done Criteria:**
- `flutter test test/distance_source_import_test.dart test/watch_session_import_test.dart
  test/watch_capture_contract_test.dart test/watch_capture_repository_parity_test.dart
  test/watch_session_edit_restore_summaries_test.dart test/entry_identity_test.dart > /tmp/pr3b_p2.log 2>&1;
  echo "exit $?"` → exit 0.
- `grep -c "EntryRows.parseId" lib/core/services/watch_session_importer.dart` → 1 or more.
- `grep -n "indexOf('-')" lib/core/services/watch_session_importer.dart` → no line inside
  `_observationsByIndex`.
- The full `flutter test` → exit 0. `flutter analyze` → at most 241 issues and 0 errors; each file touched in
  this phase has 0.

**Predicted Files:** `test/distance_source_import_test.dart` (new); `lib/core/utils/logged_entry_rows.dart`;
`lib/core/services/watch_session_importer.dart`; `lib/state/workout/timer_manager.dart`; the evidence file.

### Phase 3: The row guard, docs, sweep and mutations (Copilot)

3.1. [ ] Create `test/helpers/row_invariants.dart` with `Future<void> expectRowInvariants(WorkoutRepository
     repository, String sessionId, {required String step})`. For every effort of the session:
     - **I-a** timed: the count of `metric-distance` rows equals the count of timed instances, and so does
       the count of `metric-extra-weight` rows. Drill (hold): the count of extra-weight rows equals the count
       of timed instances.
     - **I-b** set: group the rows by `EntryRows.numberInId(row.id)`. Each group has exactly one
       `metric-reps` row and one `metric-weight` row, and at most one `metric-extra-weight` row.
     - **I-c** every `metric-distance` row with `valueReal` greater than 0 has a non-null `valueSource`.
     - Every failure message starts with `step`.
3.2. [ ] Create `test/row_invariants_guard_test.dart` with S-883–S-887. Each runs on every
     `harnessFactories` entry. On Hive, call `restart()` and reload after every step. Call
     `expectRowInvariants` after every step, then assert the scenario's end state. For S-887, reuse the Phase 2
     builders from `test/distance_source_import_test.dart`: copy them, don't import across test files.
3.3. [ ] Run `flutter test test/row_invariants_guard_test.dart > /tmp/pr3b_guard.log 2>&1`.
     - **If every test passes:** write in the evidence "F-6 and F-7: NOT APPLICABLE — the guard passed on
       unfixed code", with the tail line.
     - **If a test fails:** record the step and the invariant. Fix it only if the fix changes one function
       and follows "deleting an entry removes all its rows" and "a new row takes the highest number plus one".
       Otherwise STOP and report.
3.4. [ ] `.github/agents/docs/watch_session_capture.md`:
     - under "Invariants", add two bullets:
       - "The import stores the source a timed entry's distance arrived with, or `entered` when it arrived
         with none; a timed entry with no distance gets no source. Verified by
         `test/distance_source_import_test.dart` (S-876, S-877)."
       - "A later sync leaves a distance the phone wrote as it is: its value and its source. Verified by
         `test/distance_source_import_test.dart` (S-878)."
     - in the doc's Scope paragraph, add that it covers the distance source the import stores.
3.5. [ ] `.github/agents/docs/distance_source.md`:
     - replace the whole paragraph that starts "**Why a missing source reads as `entered`.**" (about 5
       lines, ending "recorded by an older writer.") with: "**Why a missing source reads as `entered`.**
       The Summary writes `entered`, and the watch import stores the source the watch sent, or `entered`
       when it sent none, because a watch that sends no source dialled the distance by hand. Verified by
       `test/distance_source_import_test.dart` (S-876, S-877).";
     - widen the Scope paragraph to name `WatchSessionImporter` as a writer of the source.
3.6. [ ] `.github/agents/docs/data_models.md`:
     - replace "Two paths build and read their own ids instead" with "Two paths build their own ids
       instead";
     - replace "parses ids with its own prefix reader" with "reads ids with `EntryRows.parseId`";
     - in that paragraph's existing "Verified by" sentence, add ``and `test/row_invariants_guard_test.dart`
       (S-887)`` after ``(`A-51`)``.
3.7. [ ] Run the doc checklist (items 1–9 in the executor block) on the three docs, and fill the evidence
     doc-claim table.
3.8. [ ] Stale-claim sweep. Run each command and record the output in the evidence table.
     - `grep -rn "the watch import write" .github/agents/docs/` → no output.
     - `grep -rn "own prefix reader" .github/agents/docs/` → no output.
     - `grep -rn "build and read their own ids" .github/agents/docs/` → no output.
     - `grep -rln "distanceSource" .github/agents/docs/` → no output. The docs name the stored source
       `value_source`; the wire name lives in PROTOCOL.md.
     - `grep -rn -i "back to the watch" .github/agents/docs/` → no output.
     - `grep -rn "timed-<" .github/agents/docs/` → any line found must not claim that instance ids can
       repeat.
     - `git diff --name-only develop | grep -E "docs/(README|widget_catalog|design_system|navigation_and_screens)\.md"`
       → no output. 3b adds no widget, screen or header.
3.9. [ ] Mutations (copy-aside method). Record each in the evidence mutation table.
     - **M1 (required):** in `watch_session_importer.dart` Step 2.5, always pass `EffortObservation.sourceEntered`
       for a distance greater than 0. `test/distance_source_import_test.dart` S-876 must fail (`gps` or
       `estimated` expected, `entered` found).
     - **M2 (required):** in `message_validator.dart`, delete `'distanceSource': ['timed'],`.
       `test/sync_protocol_fixtures_test.dart` must fail on `observations_up_distance_source_on_round.json`.
     - **M3 (recommended):** in `SyncProtocolValidator.swift`, delete `("distanceSource", ["timed"]),`.
       `swift test` must report a failure in `SyncProtocolFixturesTests`.
     - **M4 (recommended):** in `watch_session_importer.dart`, in the move (re-key) path that copies `toMap()`
       under a new id, add `'value_source': null` to the copied map. S-878 must fail (entry 1 has no source).

**Red → green:** S-883–S-887 are guards. If Step 3.3 passes on unfixed code, record NOT APPLICABLE. If one
fails, that failure is the red run for its fix.

**Done Criteria:**
- `flutter test test/row_invariants_guard_test.dart test/docs_indexing_contract_test.dart >
  /tmp/pr3b_p3.log 2>&1; echo "exit $?"` → exit 0.
- The full `flutter test` → exit 0. `flutter analyze` → at most 241 issues and 0 errors.
- `swift test` → `Executed 242 tests, with 0 failures`.
- Every command in Step 3.8 gives its expected output.
- M1 and M2 are recorded with their failing values.
- The doc-claim table has a row for every sentence added in Steps 1.9 and 3.4–3.6.

**Predicted Files:** `test/helpers/row_invariants.dart` (new); `test/row_invariants_guard_test.dart` (new);
`.github/agents/docs/watch_session_capture.md`, `distance_source.md`, `data_models.md`; the evidence file. A
fix from Step 3.3 may add one Phase 2 lib file; name it in the evidence.

## Files Affected (whole PR)

The union of the three Predicted Files lists. Not touched: everything in `lib/watch/` and
`watch/watchos/Sources/` except the validator, `watch/contract/`, the phone UI, and every existing fixture.

## Notes

- **Dependency graph:** 1 → 2 → 3. Phase 2's tests need Phase 1's schema; Phase 3's guard needs Phase 2.
- **Why the watch is not in 3b:** watch sessions never run GPS, so "absent means `entered`" is true today
  (D-335). PR 3c sends the field, makes it required, adds GPS for wrist sessions, the estimate and indoor
  vs outdoor, and removes D-335's absent rule.
- **Given D-332,** once Step 3.3 passes, 3a and 3a2's old-data handling moves to PR 3a3 (phone only, nothing
  visible): the missing-source-reads-`entered` rule, non-timed distance rows, 3a-style suffixed ids, the
  sequential grouping fallback, missing-row filling, and "leftover" wording.

## Open Items

- **O-1:** PR 3a2 must be on `develop` before Step 0 can pass. The owner commits and merges it.
- **O-2:** after 3b, plan PR 3a3 (the cleanup above plus the save-as-routine defaults) and the O-17 PR.
- **O-3:** `addEntry`'s `previousValues?['distance']` carry-forward writes a distance row with no
  source. No screen populates `previousValues['distance']` for a timed/drill entry today, so the path
  is unreachable; deferred to PR 3a3 per the owner (S-1, second review round).

## Progress

Baselines (evidence §1): 3097 passed, 1 skipped; analyzer 241 issues, 0 errors; Swift 242, 0 failures.
Final: 3117 passed, 1 skipped; analyzer 241 issues, 0 errors; Swift 242, 0 failures.

- [x] Step 0: preconditions, branch, baselines — passed after the owner merged 3a2 into `develop`;
      no branch created (owner directed work on `develop`)
- [x] Phase 1: protocol field on both validators — 5 fixtures; S-871–S-874 red → green, S-875 green
      throughout; Dart 72 passed, Swift 242
- [x] Phase 2: import records the source; unique instance ids — S-876, S-877, S-880 red → green
- [x] Phase 3: row guard (F-6 and F-7: **NOT APPLICABLE** — the guard passed on unfixed code, and a
      temporary mutation proved it bites), docs, sweep, mutations M1–M4
- [x] Review: `/code-reviewer` — first round (F-1–F-6) and second round (C-1–C-3, W-1–W-3, S-2,
      minor items) both fixed; S-1 deferred to PR 3a3 (Open Item O-3)

## Assumption Log

<!-- Executors append here: decision, options considered, choice and why. At most 3 lines each. -->

- **Step 0b skipped.** The plan says create `feature/stats-pr3b-distance-source-import`; the owner
  directed work to continue directly on `develop`. No branch was created; the owner still merges.
- **S-878 read through both layers.** The plan says "green before and after", but its step (b) checks
  the *late* entry's source too, which Step 2.5's absent-means-`entered` rule supplies, so S-878 was
  red before the fix. Kept red-first as written; M4 covers the half that was already green.
- **S-878 asserts the raw source, not just the resolved one.** `DistanceSource.resolve` maps null to
  `entered`, so an assertion on the resolved value alone would pass for an unsourced row and M4 could
  not bite. The test reads the stored rows for those steps and the state reader for the pairing.

## Feedback

Full findings: `2026-09-27-03b-stats-pr3b-distance-source-import-plan.review.md`. One round; no
split and no re-review. Fix checklist:

- [x] **F-1 (CRITICAL, blocking)** — `docs/distance_source.md:121`: the false absolute is deleted;
      the invariant keeps only what `S-802`/`S-805`/`S-821` verify.
- [x] **F-2** — same file, `:49`: the write paragraph names both phone paths and no longer reads as
      exclusive.
- [x] **F-3** — `TimerManager` takes an optional `clock`; a writer test drives add → delete → add on
      a standing clock. Proof: M6.
- [x] **F-4** — `updateEntryValue` derives a distance row's source from the value it writes; the
      guard's S-883 gained steps 2a/2b. Proof: M5 — which showed this was a real hole.
- [x] Re-ran `flutter test` (`+3119 ~1`), `flutter analyze` (241, 0 errors) and the stale sweep; no
      re-review. **`swift test` still owed** — the Swift tree is unchanged by the fix round.
- Deferred: F-5 (`docs/state_management/workout_state.md:198`) on that page's next edit. F-6 done.

### Review — Claude code-reviewer, 2026-09-28

The findings are in the top section of `…plan.review.md`. One round, no re-review. The code is correct;
the blockers are docs only.

- [x] **C-1 (CRITICAL)** `docs/state_management/workout_state.md:103`: delete the `valueSource` clause, and point at `S-804` (a) and S-883 2a/2b.
- [x] **C-2 (CRITICAL)** `docs/distance_source.md:49-55`: replace the behaviour prose with pointers (`S-805`, `S-804` (a), S-883 2a/2b), and fix "Both".
- [x] **C-3 (CRITICAL)** `docs/data_models.md:515`: say that the import builds its own ids and that the template defaults read rows without the rule.
- [x] **W-1** In the guard's `setUp`, store each exercise's capabilities with `setExerciseCapabilities`.
- [x] **W-2** Fix the evidence: the guard outcome, the F-4 producer, the doc-claim line refs and the mutation count. Fix the plan's Progress and header.
- [x] **W-3** `docs/state_management/workout_state.md:198`: point the `addTimedEntry` id rule at S-880.
- [x] Re-run `flutter test`, `flutter analyze`, the Step 3.8 sweep and the two greps in review §K.
- [x] Follow-up (conductor-v2, PR 3a3): S-1, the `addEntry` distance carry-forward — recorded as Open Item O-3, not fixed.
