# Evidence — plan 160 (the wrist's own workout reaches the phone)

Developer agent run, 2026-11-14. Baselines, red→green tables, mutation proofs and
suite outputs. Nothing here is a plan decision; the plan is the source of truth.

## Baselines (before this run)

| Check | Baseline | Source |
|---|---|---|
| `lint` | 181 issues, all pre-existing `info` notices | brief |
| full `test` | ~7578 tests; a handful of pre-existing failures (none in this plan's files) | brief |
| corpus | 16 recordings + `manifest.json`, A-152a allowlisting the end id | plan |
| docs | every `docs/*.md` under 64 KiB (52 KiB soft) | `test/docs_indexing_contract_test.dart` |

## Phase 1 — the twin captures the session end

### Red before implementation

Written first, run before any `lib/` change:
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart --plain-name "plan 160"`
→ **red**: 8 new tests, all failing on the missing capture (`Expected: an object with length of <1> / Actual: []`).

`S-16008` (import side) was added second: `test/watch_session_import_test.dart --plain-name "S-16008"`
→ **red** for the same reason (no `session_end` row staged, so no session created).

### Green after implementation

| Run | Result |
|---|---|
| `test/watch_session_engine_test.dart --plain-name "plan 160"` | `00:00 +8: All tests passed!` |
| `test/watch_session_engine_test.dart` (whole file) | `00:00 +89: All tests passed!` |
| `test/watch_session_import_test.dart --plain-name "S-16008"` | `00:00 +1: All tests passed!` |
| `test/watch_session_import_test.dart` + `test/watch_session_end_owed_test.dart` | `00:01 +111: All tests passed!` |
| `test/watch_session_engine_test.dart` + `…import…` + `…end_owed…` (one run) | `+200` passed, exit 0 |

### Scenario → test map

| S-id | Test (file `test/watch_session_engine_test.dart`, group `plan 160 the twin's session_end`) |
|---|---|
| S-16001 | `S-16001 the wrist's own finish captures its end before the terminal row` |
| S-16002 | `S-16002 the wrist's own discard captures its end` |
| S-16003 | `S-16003 a second wrist finish stores and emits no second end`, `S-16003 a wrist finish after the phone's end keeps that end` |
| S-16004 | `S-16004 a phone snapshot that ends the session captures its end` |
| S-16005 | `S-16005 a phone lifecycle end captures its end with the payload's instant` |
| S-16006 | `S-16006 a first-hearing already-finished snapshot captures nothing` |
| S-16007 | `S-16007 the end is still owed after another session started` |
| S-16008 | `test/watch_session_import_test.dart`, group `S-16008 the end the twin captured imports as its finish` |

### Existing tests the legitimate new end broke (all in the plan's own file)

The new `session_end` is stored and emitted on every ending path, so nine
pre-existing assertions that pinned an exact frame list or an exact row list saw
one more item. Each was reconciled in `test/watch_session_engine_test.dart` (the
plan's file for Phase 1), never by weakening the assertion:

| Test | Reconciliation |
|---|---|
| `S-331 the rest is stopped at the end…` | emitted kinds `['set','rest']` → `['set','rest', WatchObservationKind.sessionEnd]` |
| `Closing a session abandoning keeps what was already logged…` | stored ids `['e-1','e-2']` → `[…, WatchSessionCapture.sessionEndId(id)]` |
| `S-212` (both arms) | replayed frames `hasLength(2)` → `hasLength(3)`; the live end frame is now `harness.emitted.last` |
| `S-322` (both occurrences) | `_emittedKinds` → `['set','rest', sessionEnd]` |
| `S-14640` | stored `entries` → `['e-1','end-s-w1']` |
| `S-14611` | stored `entries` → `['end-s-w1','entry-late']` |
| `S-14608` | `storedRows` → `['entry-1','end-s-w1','entry-2']` |

No test outside `test/watch_session_engine_test.dart` went red.

### Mutation proofs (each restored to the exact original, then re-run green)

`prove-red` cannot carry a `lib/` change (it carries test files only and the new
code does not exist at `HEAD`), so the guards were proven by mutation, as the
brief allows for new code.

| # | Mutation (original line → mutant) | Verdict |
|---|---|---|
| M1 | `_captureSessionEnd`: original guard kept; mutant `return;` inserted right after `if (!_isTerminal(status)) return;` | **RED** — `--plain-name "plan 160"` gave `+1 -7`; e.g. S-16001 `Expected: an object with length of <1> / Actual: []`, S-16007 `has too few elements (2 < 3)`. Restored. |
| M2 | `_sessionEndEvent`: original `_creationRow(sessionId)`; mutant falls back to `_session` (`_creationRow(sessionId) ?? _session`) | **INCONCLUSIVE in this fixture** — S-16006 stayed green: on a first-hearing already-finished snapshot no row exists for the unknown session before the capture, so the held-record dedupe refuses the capture for the same input the creation-row guard refuses. The guard is real but the real fixture cannot tell the two apart; recorded rather than stubbed, so S-16006 keeps its real fixture. Restored. |
| M3 | `_sessionEndEvent`: original `if (creation.source != 'watch') 'followed': true`; mutant a hardcoded `'followed': true` | **RED** — S-16001 `has different length and has extra map key 'followed'`. Restored. |
| M4 | `pendingObservations()`: original `_observations` (all sessions); mutant the current session's `observations` | **RED** — S-16007 `Expected: contains all of ['entry-1', 'end-w1', 'entry-2'] / Actual: ['entry-2']`. Restored. |

M1 proves the capture itself, M3 the `followed` rule, M4 the D-16005 widening;
M2 is reported as inconclusive, not as a pass.

## Phase 2 — replay parity, close A-152a: APPLIED, regeneration pending

The lift and the regeneration are one atomic change: removing the end-id
exclusion in `test/helpers/watch_replay_recorder.dart` makes every recorded
`expected` block stale, and the only way to refresh them is the D-15209 writing
run, which the standing rules forbid a check (and therefore me) to do.

Applied (three small edits):

1. `test/helpers/watch_replay_recorder.dart` — deleted
   `if (entryId == sessionEndId(id)) continue;` in `WristSummary.fromContents`,
   deleted the now-unused `WristSummary.sessionEndId` helper, and rewrote the
   `SessionSummary.entries` doc and the `WristSummary` class doc, which both
   described the exclusion.
2. `test/watch_replay_corpus_test.dart` — deleted the `A-152a` entry from
   `_manifest`'s `allowlist`, and `S-15201`'s F-2 assertion now expects the one
   entry an ended, set-less session carries:
   `[WatchSessionCapture.sessionEndId(sessions.keys.single)]` (id derived, not a
   literal).

Result of `.github/copilot/scripts/macos/gateway.sh test test/watch_replay_corpus_test.dart`:

| Test | Before the lift | After |
|---|---|---|
| `S-15201` a run records to a byte-stable file … | green | **red** on the fresh recording's `entries` (`['end-s-w-1']`, empty expected) → green once the assertion above was updated |
| `S-15202` every corpus recording replays … expected summary | green | **red**: `Expected …["w-entry-1",…] / Actual …["end-x-2","w-entry-1",…]` (`trace-s14501`) — the checked-in `expected` predates the end |
| `S-15202` a replay reproduces the recorded store row for row | green | green (the store's rows are unchanged; only the summary's `entries` moved) |
| `S-15203`, `S-15204` | green | green |
| `S-15207` the corpus is fresh | red (from Phase 1) | red: all 16 recordings stale |
| regenerate (skipped) | skipped | skipped |

`4 passed, 2 failed, 1 skipped`. Both reds are the recorded-data state, not the
code: `S-15202` replays the checked-in recordings against the checked-in
`expected`, so it clears in the same run that clears `S-15207`.

Remaining Governor action: `.github/copilot/scripts/macos/gateway.sh test test/watch_replay_corpus_test.dart --dart-define=REPLAY_CORPUS_WRITE=true`, then re-run that file and the full suite. Each ended session's `entries` gains `end-<sessionId>`; no event timeline changes (D-15202).

## Phase 1 follow-up — the 19 unpredicted reds, reconciled

Full suite before this pass: `+7567 -21` (19 twin reds, `S-15207`, one unrelated
`delete_focused_timer_test.dart`). After: **`+7586 -2`**, the two reds being
`S-15202`/`S-15207` above.

| File | Red | Fix | Result |
|---|---|---|---|
| `test/live_mirroring_test.dart` | 7 reconciliation watch fixtures saw one extra entry; 3 step-list tests saw an extra `observations_up` | the Dart runner now filters `entry.payload['kind'] != WatchObservationKind.sessionEnd`, exactly as the Swift `WatchLiveMirroringTests.assertConverged` does; the two step-list expectations gained the second `send:observations_up` | 62 passed |
| `test/watch_convergence_harness_test.dart` | S-14514 (the owed end re-offered once per window), S-14501/S-14505 (entry-id counts), B1 `drainOnlyHeal` (answers to the drained frames) | S-14514's fixture starts the session while the link is down (AL-7); the counting sets exclude `end-<sessionId>` with the equal-ids assertion kept; `drainOnlyHeal` now allows the three answer types | 31 passed |
| `test/watch_session_finish_test.dart` | S-322, S-331 expected `['set','rest']` | kind lists gained `WatchObservationKind.sessionEnd` | green (in the 86 below) |
| `test/watch_session_projection_test.dart` | S-183 case A expected no entries and nothing owed | `engine.entries` holds exactly the end; `pendingObservations()` carries one frame whose only event is the end | 86 passed with the file above |
| `test/watch_nutrition_quick_log_test.dart` | the closed emit set | set gained `WatchObservationKind.sessionEnd` | green |
| `test/watch_sensor_recording_test.dart` | the settled-session count | every observation is confirmed, `observations` `hasLength(2)` | green |
| `test/watch_reconciliation_cross_stack_test.dart` | S-335 kind list | list gained the end; the rest-list assertion still proves the end adds no rest | green |

No assertion was weakened: every change either follows the Swift side's existing
rule or adds the end to a list that already enumerated the session's frames.

| Run | Result |
|---|---|
| `test/watch_convergence_harness_test.dart` | `31 passed` |
| `test/live_mirroring_test.dart` | `62 passed` |
| `test/watch_session_projection_test.dart test/watch_session_finish_test.dart` | `86 passed` |
| `test/watch_replay_corpus_test.dart` | `4 passed, 2 failed, 1 skipped` (the stale corpus) |
| full `test` | **`7586 passed, 2 failed, 4 skipped`** |
| `lint` | `181 issues` (the baseline), none in a file this pass touched |
| `test/ui_standards_contract_test.dart` | green (no widget, colour, button or surface touched) |
| invariant grep | no match outside `lib/main.dart` (the composition root) |

`swift-test` not run: no `.swift` file changed by this pass. `prove-red` does not
apply: these are expectation reconciliations in existing tests whose guard is the
twin's new capture, already proven red by Phase 1's own red run and mutations M1/M3/M4.

## Phase 3 — un-skip S-14660

Removed the `skip:` argument and its blocking comment from
`test/watch_convergence_harness_test.dart`:
`.github/copilot/scripts/macos/gateway.sh test test/watch_convergence_harness_test.dart --plain-name "S-14660" --reporter expanded`
→ `00:00 +1: All tests passed!`

The red the comment described (a wrist session the phone never held reaching it
with no `session_end`) is gone: the twin now captures the end (Phase 1) and
re-offers it after another session starts (D-16005), so the phone imports the
wrist's own workout as its own finished workout.

## Phase 4 — docs

| File | Change |
|---|---|
| `docs/watch_session_capture.md` | the wrist-half intro no longer claims `lib/watch/` sends no session end; a paragraph states the twin's end shape and its rules, naming the group and each test; the two invariants gain the Dart verification |
| `docs/plans/2026-11-12-146c-…-plan.md` | its Open Item for S-14660 now records that plan 160 closed it, naming the un-skipped test |
| `docs/watch_session_sync.md` | no update required — it describes adoption and the `modality` the end carries, both unchanged |

`test/docs_indexing_contract_test.dart` and the full suite: see below.

## Closing checks

| Check | Result |
|---|---|
| `lint` | **181 issues** (the baseline), none in a file this run touched; the two `unnecessary_import` notices the new imports first introduced were removed. Re-run after the reconciliation pass: still 181 |
| full `test` | **`7586 passed, 2 failed, 4 skipped`** — both reds the stale corpus, cleared by the regeneration |
| `test/ui_standards_contract_test.dart` | green (the change touches no widget, colour, button or surface) |
| invariant grep `import .*hive_workout_repository` in `lib/state lib/features lib/widgets lib/core` | no match |
| `swift-test` | not run: this run changed no `.swift` file (the two Swift files already modified in the tree are pre-existing, not this run's) |
| residue | no scratch or probe file created; no mutation left applied (`grep MUTATION lib/watch/session` → none) |

## Full suite

Final run, after the 19 reds were reconciled and Phase 2's edits applied:
`.github/copilot/scripts/macos/gateway.sh test --reporter github` →
**`7586 passed, 2 failed, 4 skipped`** (log
`.work/gateway/test-20261114-175318-73033.log`).

| Failure | Status |
|---|---|
| `test/watch_replay_corpus_test.dart` `S-15202 every corpus recording replays … expected summary` | **expected** — the checked-in `expected` blocks predate the captured end; the regeneration clears it |
| `test/watch_replay_corpus_test.dart` `S-15207 the corpus is fresh` | **expected** — same cause |

Nothing else fails: the 19 unpredicted reds are gone, and the unrelated
`delete_focused_timer_test.dart` red the earlier baseline carried did not recur.

Earlier run in this plan (before this pass):
`05:25 +7567 ~4 -21: Some tests failed.` (log
`.work/gateway/test-20261114-172602-57392.log`), the 21 being `S-15207`, the 19
reds and that unrelated one.

`prove-red HEAD test <those 8 files> --reporter expanded` →
`+302 ~1 -1: Some tests failed.` — the single red at `HEAD` is
`S-14660 … Expected: not null / Actual: <null>`, i.e. the guard this plan exists
for; every other failure is caused by the change, not pre-existing.

The plan's own files, run alone: `test/watch_session_engine_test.dart` +
`test/watch_session_import_test.dart` + `test/watch_session_end_owed_test.dart`
→ `+200` passed; `test/watch_convergence_harness_test.dart --plain-name "S-14660"`
→ `+1` passed; `test/ui_standards_contract_test.dart` +
`test/docs_indexing_contract_test.dart` → `+54 All tests passed!`.

## Phase 2 follow-up 2 — the derived end id, the tags, the Swift reader, the doc

### The rule the canonicalizer now applies

`test/helpers/watch_replay_recorder.dart`, `ReplayCanonicalizer._canonicalString`,
in order: an ISO instant is aliased; a string beginning with
`WatchSessionCapture.endPrefix` whose remainder is digit-run- or UUID-shaped becomes
`end-<the session id's canonical form>` (recursive, so the alias is reused rather than
minted a second time); any other digit-run- or UUID-shaped string mints `x-<n>` in
first-appearance order; everything else is verbatim (`s-w-1`, `w-entry-1`). The
prefix is read from `WatchSessionCapture`, never spelled as a literal.

Before this rule, the recording side aliased `end-session-<epoch>` as an opaque
`x-<n>` while the replay side derived `end-<the aliased session id>`, so the two sides
could not agree on the same string by construction. `trace-s14501` records both the
opaque `x-10` and the derived `end-x-2`; the pair only becomes comparable now.

### The new guard

`test/watch_replay_corpus_test.dart`:
`S-15203 a derived session-end id canonicalizes to end-<the session id's alias>` —
records and replays a session whose id is a phone epoch, asserts both sides carry the
same `end-x-<n>`, asserts the order of arrival does not matter (end before session id),
asserts no raw digit run survives, and asserts an already-derived `end-x-2` passes
through unchanged.

The test cannot be proven at `HEAD`: `WatchSessionCapture` does not exist there, so
`prove-red HEAD test test/watch_replay_corpus_test.dart` compiles to an error rather
than a red. Mutation proof instead, on the canonicalizer:

| Mutation | Line | Verdict |
|---|---|---|
| `if (value.startsWith(WatchSessionCapture.endPrefix) && _isAliasable(...))` → `if (value.startsWith('__mutant__'))` | `watch_replay_recorder.dart` `_canonicalString` | **RED** — `S-15203 … Expected: 'end-x-1' / Actual: 'x-1'` |

The original line was restored exactly and the pair re-ran green (`+2 All tests
passed!`). No probe file was created.

### The declared tags, and why each changed

`test/watch_replay_corpus_test.dart`, `_Source` declarations — every recorded run now
ends a session, so runs whose phone-side `expected.entries` was empty now hold
`end-<sessionId>`:

| Source | Before | After |
|---|---|---|
| `trace-s14503` | `entry`, `frame-prefix` | + `refused-queued` (the run refuses one frame) |
| `trace-f2` | — | `entry` |
| `trace-f3` | `timer`, `frame-prefix` | + `entry` |
| `trace-f4` | `multi-session`, `frame-prefix` | + `entry` |
| `trace-f5` | `multi-session` | + `entry` |
| `trace-a1` | `multi-session` | + `entry` |

No source lost a tag, so no coverage floor dropped; `entry` is now covered by six more
sources. Tag declarations for run-only tags (`refused-queued`, `no-fault`) are
unchanged, and the file-visible ones are already green in `S-15204` against the
checked-in manifest.

### The Swift reader

`watch/watchos/Tests/WatchSessionEngineTests/WatchReplayTests.swift`: `readSummary(_:current:)`
lost its `excludingSessionEnd` parameter and the `isSessionEndObservation` filter both
sides of the comparison had, `isSessionEndObservation` is deleted, `testS15210` is
rewritten as `testS15210TheSessionEndIsHeldOnBothSides` (both wrists hold `end-<id>`
for every completed and abandoned session, and the full replay outcome has no class at
all), and `testS15211DroppingAnEndFromEitherSideIsReportedAsAnEntriesDiff` guards the
new truth by dropping the end from the Swift store and from the Dart recording in turn
and asserting an `entries` diff naming that id. `testS15205`'s entry count is 4 (three
entries plus the end). No canonicalizer change was needed on the Swift side: it reads
the stored aliases and derives its end id from the session id it already applied.

### Runs

| Run | Result |
|---|---|
| `test/watch_replay_corpus_test.dart` (S-15203 pair, `--plain-name "S-15203"`) | `+2 All tests passed!` |
| `test/watch_replay_corpus_test.dart` (whole file) | `+5 ~1 -2` — the two reds are `S-15202` and `S-15207`, cause unchanged (stale `expected`); the skip is the regeneration guard |
| `swift-test --filter WatchReplayTests` | compiles; **5 tests, 15 assertion failures**, every diff an `entries` list differing by exactly `end-x-2` / `end-x-9` / `end-x-6` — the stale recordings, as predicted. `testS15206` (`trace-f2`) already passes because that run's session id is the stable `s-w-1` and its recording holds `end-s-w-1` |
| `lint` | **181**, the baseline, none in a touched file |
| `test/docs_indexing_contract_test.dart` | `+13 All tests passed!` — the new prose names a test that exists |
| invariant grep `import .*hive_workout_repository` in `lib/state lib/features lib/widgets lib/core` | no match |

Diff footprint of this pass: `watch_replay_recorder.dart` 33, `watch_replay_corpus_test.dart`
65, `WatchReplayTests.swift` 148 (roughly half a rewrite of the replaced tests),
`watch_surface_transport.md` 18.

### What the regeneration must produce (prediction)

Command (Governor action):
`flutter test --dart-define=REPLAY_CORPUS_WRITE=true test/watch_replay_corpus_test.dart`

- Each ended session's `expected.entries` gains `end-<sessionId>` in sorted position
  for the ten stale recordings — `trace-s14501`, `trace-s14503`, `trace-f3`,
  `trace-f4`, `trace-f6`, `seed-1`, `seed-7`, `seed-50`, `seed-408`, `seed-857`.
- No event timeline changes, and no alias renumbers: with the derived rule the end id
  reuses the session's alias instead of minting one, and the end never appears in
  `events`, so nothing after it in first-appearance order moves.
- `manifest.json` gains the tag rows above.
- The six recordings that are fresh today (`trace-f2`, `trace-f5`, `trace-f7`,
  `trace-a1`, `trace-a2`, `seed-111`) stay unchanged apart from their manifest rows.
- After it: `S-15202`, `S-15207` and the five `WatchReplayTests` go green together,
  and `S-15204` stays green; expectations stay at or under 300 KB per recording.


