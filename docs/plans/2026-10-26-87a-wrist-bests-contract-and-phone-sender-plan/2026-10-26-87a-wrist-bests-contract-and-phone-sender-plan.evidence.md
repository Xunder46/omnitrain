# 87a evidence

Planner research run, 2026-10-26, base commit 530995d40dd3170d6d20026d8bf2e8665e677e53.
The planner ran no gateway checks (research-only run); implementers record their lint/test/analyze
baselines here before their first change. `flutter analyze` exits non-zero on this repo while it
carries pre-existing info notices — compare issue counts, do not chase them.

## Brief verification items (a)–(f)

### (a) Largest existing frame and the transport's size limit vs `maxItems` 300 (D-2)

- No size limit exists in the repo's transport layer: grep for `limit|size|maxLength|65536|65535`
  over `lib/core/platform/watch_transport.dart`, `lib/core/platform/watch_connectivity_channel.dart`
  and `packages/omnitrain_watch_link/` finds no payload-size guard. The plugin
  (`packages/omnitrain_watch_link/ios/Classes/OmniTrainWatchLinkPlugin.swift`, `sendMessage` :90,
  `transferUserInfo` :122) passes the dictionary straight to `WCSession`.
- The only bound is the platform's documented `WCSession.sendMessage` payload ceiling (~65 KB),
  which this repo does not enforce (Open question 6 in the plan).
- Largest existing frame: a full `exercises_down` batch of 100 catalog exercises
  (`WatchReferenceSync.buildExercisesDown`, `lib/core/utils/watch_reference_sync.dart:217`).
- A 300-entry bests frame ≈ 300 × ~80 B ≈ 24 KB — the same order as that batch, far under 65 KB.
- Conclusion: ONE frame, never batched (batching would break D-3's newest-frame-wins: a wrist
  applying batch 2 would drop batch 1's entries). The builder caps at 300, ordered by exerciseId
  ascending (D-9/D-12). Recorded as D-9.

### (b) Every reader of the files this changes

- `watch/sync_protocol/schemas/envelope.schema.json` type enum (:17-29): read by both validators'
  type gates and by the fixture suites (`test/sync_protocol_fixtures_test.dart:170`,
  `SyncProtocolFixturesTests.swift:31`). Additive enum value.
- `lib/core/sync_protocol/message_validator.dart`: `messageTypes` const list (:107) — read by
  `test/sync_protocol_fixtures_test.dart:169-181` ("gives every message type a schema and a valid
  fixture"), so the schema + valid fixture must land in the same change. Semantic switch (:275-306)
  `default: return const []` — additive case only.
- `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`: `messageTypes` (:50-63),
  semantic switch default (:197). Grep over `watch/watchos/Tests` for `messageTypes`: zero matches —
  no Swift test enumerates the list.
- `test/sync_protocol_fixtures_test.dart` and `SyncProtocolFixturesTests.swift` are MANIFEST-DRIVEN
  (`test/...:148` "lists every fixture file on disk, exactly once", :169, :196; Swift :31
  `testEveryValidFixtureConforms`, :49 `testEveryInvalidFixtureIsRejectedAsStated`) — no test-code
  edits; they extend themselves from `manifest.json`.
- `SyncProtocolValidatorTests.swift`: no family-count assertions (only S-165 rest rules) — no change.
- Frame-counting tests (bests appended as the LAST frame of the routines answer):
  - `test/watch_sync_changed_only_test.dart`: S-9202 (:294) asserts `transport.sent` isEmpty →
    becomes "exactly one frame, type bests_down". All others use `take(3)`/`ofType`/`batchIndices`
    and survive: S-9201 (:263), S-9204a/b/c (:409+), S-9205, S-9206a/b/c, S-9207, S-9209, S-9210,
    S-15203, S-15207, S-9211 (stamps filter `_referenceFrames`), S-9212.
  - `test/watch_sync_request_handler_test.dart`: S-3850 (:277) and S-3857 (:303) exact lists
    `['preferences_down','foods_down','routines_down']` → gain `'bests_down'`; S-3851 (:331) and
    S-7101 (:474) `types.skip(3)` `everyElement('exercises_down')` → "batches then one bests_down";
    S-7103 (:566) exact list → gains `'bests_down'`; S-3852/S-3853 (batchIndices), S-3854 (:390
    `ofType('exercises_down') isEmpty`), S-7104/S-7105 (`take(3)`/`ofType`) survive.
  - `test/watch_transport_test.dart`: S-003 (:671-679) `types.skip(3)` `everyElement` → adjust.
  - Grep: exactly three `everyElement('exercises_down')` sites — handler :332, :474; transport :679.
  - `test/watch_session_projection_test.dart` S-9213 (:814-894): all `ofType`-based — survives.
  - `test/watch_message_order_test.dart` S-9301: handler order, not frame count — survives.

### (c) Dart twin / `lib/watch/session/watch_records.dart`

- `lib/watch/start/watch_sync_orchestrator.dart` `receive` (:141-157) has `default: return false` —
  unknown types are ignored; `preferences_down` also has no case (precedent).
- `lib/watch/session/watch_records.dart` sealed `WatchRecord.fromJson` (:168-180) throws on unknown
  recordType but only sees record types the twin stores; `bests_down` never reaches it.
- D-6's default "no twin change" CONFIRMED — no case needed.

### (d) Send placement in `_sendRoutines`

- `lib/state/watch/watch_sync_request_handler.dart:121`. The exercise-list section holds three
  early returns (:171 held-version, :186 `batches.isEmpty`, :193 `exercisesVersion == version`)
  that would skip a bests send placed after them. D-11: extract the section into
  `_sendExerciseList` keeping its early returns; `_sendRoutines` then sends bests and returns true.
  Bests is the LAST frame, sent on every request, independent of `since`, of the bundle stamp, of
  the version early return and of a batch-refusal break; the return value stays `true` on every
  path (S-87a-7).
- Built from a fresh `StatsProgressService(_repository)` per request: the service caches one
  history snapshot per instance (`docs/state_management/services_and_utils.md:243`), so a held
  instance would serve stale bests (S-87a-8). Matches the standing pattern
  (`session_summary_service.dart:258`, `stats_screen.dart:111`).

### (e) Bulk method parity

- `getAllTimeBestE1RM` (:2149) and `getAllTimeBestReps` (:2220) are identical walks: completed
  sessions (`endedAtMs != null`) → `_loadHistory().segmentsOf(session.id)` → `effortsOf(segment.id)`
  → filter `effortKind == 'set'` + exerciseId → `observationsOf(effort.id)` →
  `ObservationGrouper.groupByEffortKind('set', observations)` (`lib/core/utils/observation_grouper.dart:24`)
  → entries `entry['weight'] as num? ?? 0.0`, `entry['reps'] as int? ?? 0`.
  e1RM axis: `epley1RM(weight, reps)` (:2121, null when weight <= 0 or reps <= 0), track max.
  Reps axis: `if (weight != 0.0) continue; if (reps > best) best = reps`.
- The bulk method `getAllTimeBests()` (phase 2 item 1) fuses the two walks over one `_loadHistory()`
  pass; S-87a-5's parity test (phase 2 item 4, model S-T-001 `test/services_test.dart:552`) is the
  structural guard.

### (f) Docs that name the handler's frames or the message families

- `docs/watch_session_sync.md` names NO message family: grep `foods_down|preferences_down|
  exercises_down` over it — zero matches. The seed's phase-1 "docs/watch_session_sync.md mention"
  looks misplaced (Open question 2).
- Docs that DO name the frames: `docs/state_management/watch_reference_data.md:174` ("the three
  reference frames"), `docs/state_management/watch_surface.md:544` (handler section),
  `docs/state_management/nutrition_state.md:180` (foods context, not edited here).
- `docs/data_models.md` does not name handler frames.
- `watch/sync_protocol/PROTOCOL.md`: message-family table row (beside `exercises_down`'s), a
  normative sentence for D-3's newest-frame rule (beside the `preferences_down` note :100-101), and
  a version-history row in the 2026-10-23/10-24 style (:745-748), additive language.
- Spec tests constrain PROTOCOL.md edits: every referenced `schemas/…`/`fixtures/…` path must exist
  and every rejection code must be documented (`test/sync_protocol_fixtures_test.dart:820-860`).

## Validator dialect constraints (schema design)

- Supported keywords (`message_validator.dart:84-89`): type, const, enum, required, properties,
  additionalProperties, items, minItems, maxItems, minLength, maxLength, minimum, maximum, pattern,
  allOf, oneOf, `$ref`. NO `anyOf`, NO `exclusiveMinimum`; `oneOf` is exactly-one (:1010-1040).
- Consequences: "at least one of e1rmKg/repsBest" and the `> 0` bounds are semantic-layer rules
  (D-14); `repsBest: 12.5` → `invalid_type` (`type: integer`); unknown field → `unexpected_field`;
  `origin: "watch"` → `invalid_const_value`; 301 entries → `constraint_violation`.
- Swift mirror: `SyncProtocolValidator.swift` messageTypes :50, semantic default :197, rejection
  helper `rejection(SyncRejectionCode.semanticViolation, path, message)`.

## Other verified facts

- Fixture suites are manifest-driven in both stacks — no test-code edits for new fixtures
  (evidence under (b)).
- `test/helpers/sync_protocol_harness.dart` `loadProtocolValidator()` (:63) loads ALL schema files
  from `watch/sync_protocol/schemas/` recursively — sent frames in handler tests can be validated
  against the real schema (S-87a-11).
- `WatchSyncProgress.swift:31 replyTypes` does not include `bests_down` and is NOT touched (87b's);
  a bests arrival will not extend the Sync spinner.
- `WatchSyncOrchestrator.swift` `receive` default (:184) ignores unknown types — acceptance (4)
  holds with no Swift source change except the validator.
- Builder style confirmed: `WatchReferenceSync.buildFoodsDown` (`watch_reference_sync.dart:542`)
  is a static method using `phoneEnvelope(type:, messageId: 'msg-foods-<ms>', sentAt:, payload:)`.
- Manifest invalid-fixture entry shape: `{path, type, expectedCode, expectedReasonContains,
  scenario?, note?}` (`manifest.json` :161+).
- `StatsProgressService` construction pattern: constructed at the call site with the repository
  (six existing sites, grep `StatsProgressService(` over `lib/`).

## Phase 1 implementation evidence (developer, 2026-10-26)

Baseline: no implementer check had run before this phase. `swift-test` and `lint` baselines taken
with the phase's own change in place; nothing else in Phase 1 touches Dart `lib/` logic.

### Red → green table

| Run | Command | Result |
|---|---|---|
| RED (fixtures + manifest only, no schema/validators) | `gateway.sh test test/sync_protocol_fixtures_test.dart` | 132 passed, **10 failed** — the 3 valid fixtures rejected, the 7 invalid ones reported `unknown_message_type` instead of their code |
| GREEN | same command | **142 passed, 0 failed** |
| prove-red (Dart) | `gateway.sh prove-red 530995d40dd3170d6d20026d8bf2e8665e677e53 test test/sync_protocol_fixtures_test.dart -- <manifest + 11 fixtures>` | `gateway: prove-red: RED AT 530995d40dd3170d6d20026d8bf2e8665e677e53 (exit 1)` — 10 assertion failures (`Expected: contains 'semantic_violation' / Actual: ['unknown_message_type']`; the valid fixtures rejected) |
| prove-red (Swift) | `gateway.sh prove-red 530995d40dd3170d6d20026d8bf2e8665e677e53 swift-test --filter SyncProtocolFixturesTests -- <manifest + schema + 11 fixtures>` | `gateway: prove-red: RED AT 530995d40dd3170d6d20026d8bf2e8665e677e53 (exit 1)` — `testEveryValidFixtureConforms` 3 failures, `testEveryInvalidFixtureIsRejectedAsStated` 14 failures (17 total) |
| Swift GREEN | `gateway.sh swift-test --filter SyncProtocolFixturesTests` | Executed 6 tests, **0 failures** |
| Swift full | `gateway.sh swift-test` | Executed **1073 tests, 0 failures** |
| Dart full | `gateway.sh test` | `05:38 +5744 ~2: All tests passed!` — **5744 passed, 2 skipped, 0 failed** |
| UI standards | `gateway.sh test test/ui_standards_contract_test.dart` | **29 passed** (no UI file touched) |
| lint | `gateway.sh lint` | `180 issues found`, all pre-existing info notices; zero lines mentioning `message_validator` or `sync_protocol`, so no new issue |

### Fixture → code table (D-14)

| Fixture | Verdict | Code | Path |
|---|---|---|---|
| `valid/bests_down.json` | accept | — | — |
| `valid/bests_down_empty.json` | accept | — | — |
| `valid/bests_down_both_axes.json` | accept | — | — |
| `invalid/bests_down_entry_without_axis.json` | reject | `semantic_violation` | `$.payload.bests[1]` (entry `ex-squat`, the one carrying neither number) |
| `invalid/bests_down_zero_e1rm.json` | reject | `semantic_violation` | `$.payload.bests[0]` |
| `invalid/bests_down_duplicate_exercise.json` | reject | `semantic_violation` | `$.payload.bests[2]` (the second `ex-bench`) |
| `invalid/bests_down_fractional_reps.json` | reject | `invalid_type` | `$.payload.bests[0].repsBest` |
| `invalid/bests_down_unknown_field.json` | reject | `unexpected_field` | `$.payload.unit` |
| `invalid/bests_down_watch_origin.json` | reject | `invalid_const_value` | `$.origin` |
| `invalid/bests_down_over_300.json` | reject | `constraint_violation` | `$.payload.bests` |

Both validators emit identical wording for the four semantic rules (`entry carries neither e1rmKg
nor repsBest`, `the same exerciseId appears twice: <id>`, `e1rmKg must be greater than 0`,
`repsBest must be at least 1`), so the shared `expectedReasonContains` matches on both stacks.

### Diff footprint

`git-diff --stat`: `message_validator.dart` +63, `PROTOCOL.md` +16, `manifest.json` +74,
`envelope.schema.json` +1, `SyncProtocolValidator.swift` +62 — 216 insertions, 0 deletions; the 12
new files are `git-status` untracked. Nothing outside the plan's Predicted Files.

## Phase 2 implementation evidence (developer, 2026-10-26)

Base commit `530995d40dd3170d6d20026d8bf2e8665e677e53`. Baselines before the change: `lint` 180
pre-existing info notices (none in the Phase 2 files); full suite 5744 passed, 2 skipped.

New file: `test/stats_bests_builder_test.dart` — 11 plain `test()` cases, group
`StatsProgressService.getAllTimeBests` (S-87a-1 bulk over the whole history, S-87a-2 both axes,
S-87a-3 bodyweight reps, S-87a-14 through-hold and non-`set` efforts contribute nothing, S-87a-5
bulk-vs-per-exercise parity, S-87a-9 the 300 cap) and group `WatchReferenceSync.buildBestsDown`
(S-87a-1, 2, 3, 14, 9, each frame run through `jsonDecode(jsonEncode(...))` into the real schema
validator).

### Red run (before any implementation)

`gateway test test/stats_bests_builder_test.dart` failed to compile:

```
Error: Member not found: 'WatchReferenceSync.buildBestsDown'.
Error: The method 'getAllTimeBests' isn't defined for the type 'StatsProgressService'.
```

### Red → green table

| Run | Command | Result |
|---|---|---|
| Phase 0 red | `test test/stats_bests_builder_test.dart` | compile failure above — RED |
| prove-red | `prove-red HEAD test test/stats_bests_builder_test.dart` at `530995d4` | **RED AT 530995d4** (exit 1) — compile/load error: the new members cannot compile without the change |
| green 1 | `test test/stats_bests_builder_test.dart` | 10 passed, 1 failed — `generatedAt` expectation used the harness `isoUtc` (strips ms) |
| green 2 | `test test/stats_bests_builder_test.dart` | 10 passed, 1 failed — expected entry order `[bench, push-up, squat]`; D-12 order is `compareTo`, so squat sorts first |
| green 3 | `test test/stats_bests_builder_test.dart` | **11 passed, 0 failed** |
| done-criteria | `test test/stats_bests_builder_test.dart test/services_test.dart` | **66 passed, 0 failed** |
| full suite | `test` | **5755 passed, 2 skipped, "All tests passed!"** (+11 on the 5744 baseline) |
| lint | `lint` | 180 issues, exit 1 — same count as baseline; zero matches for `stats_bests_builder_test`, `stats_progress_service`, `watch_reference_sync` |
| UI standards | `test test/ui_standards_contract_test.dart` | 29 passed, 0 failed |

### Mutation record

The new members make the test file uncompilable without the change, so the prove-red above is the
compile variant; the reps-axis rule is proved by mutation instead. Original line in
`getAllTimeBests`:

```dart
            if (weight == 0.0 && reps > repsBest) repsBest = reps;
```

Mutant: `if (reps > repsBest) repsBest = reps;` — every weighted set also feeds the reps axis.

| Failing test | Expected | Actual |
|---|---|---|
| `S-87a-1 … bulk bests for the whole history` | bench `reps` 0 | 8 |
| `S-87a-5 … bulk bests agree with the per-exercise bests` | reps axis agrees for `exercise-bench-press` | bench reps 8 |
| `S-87a-1 … frame carries only the axes that exist` | `containsKey('repsBest')` false | true |

Line restored exactly; `test test/stats_bests_builder_test.dart` green again (11 passed).

### Diff footprint

`git-diff --stat`: `stats_progress_service.dart` +52, `watch_reference_sync.dart` +55 — additive only,
no lines removed. Nothing outside the plan's Predicted Files; the Phase 1 contract files, `lib/state`,
the handler and `watch/` are untouched by this phase.

## Phase 3 implementation evidence (developer, 2026-10-27)

Base commit `530995d40dd3170d6d20026d8bf2e8665e677e53`. Baselines before the change: `lint` 180
pre-existing info notices (none in the Phase 3 files); full suite 5755 passed, 2 skipped.

### Production change

`lib/state/watch/watch_sync_request_handler.dart` (+42):

- The exercise-list section of `_sendRoutines` moved verbatim into
  `_sendExerciseList({required String? exercisesVersion, required int? revision})`, its three
  `return true;` becoming `return;` (its `heldExercises` early return, the `batches.isEmpty` return,
  the version return and the batch loop are unchanged).
- `_sendRoutines` then sends the bests and returns: a fresh `StatsProgressService(_repository)` per
  request (the service caches one history snapshot for its lifetime, so a held instance would send
  bests from before the last workout — D-11), `getAllTimeBests()`, then
  `WatchReferenceSync.buildBestsDown(bests: …)` through `_transport.send`, stamped with `_clock()`.
  It sits outside the `if (since == null || since.isBefore(stamp))` bundle block, so it is the last
  frame of every answer (D-4/D-13).

### Red run (before any implementation)

`gateway test` over the three predicted test files: **`+89 -13`**, every failure reporting fewer
frames than expected (`.work/gateway/test-20261026-235654-69748.log`), e.g.

```
S-87a-6 a since-current request is answered with none of the three bundle frames and exactly one bests_down [E]
  Expected: ['bests_down']
    Actual: []
```

### Red → green table

| Run | Command | Result |
|---|---|---|
| Phase 0 red | `test` (handler, changed-only, transport, idle reads) | `+89 -13` — 13 frame-counting tests red |
| green (fixture fix 1) | same four files | `+100 -2` — S-87a-8 and S-87a-11 still saw an empty `bests` |
| green (fixture fix 2) | same four files | **`+102`, 0 failed** (`.work/gateway/test-20261027-000119-78987.log`) |
| done criteria | `test` (six files: the four above + projection + message order) | **`+177`, 0 failed** (`.work/gateway/test-20261027-000218-81611.log`) |
| lint | `lint` | `180 issues found` — the baseline count, exit 1 on the pre-existing notices only (`.work/gateway/lint-20261027-000224-81941.log`) |
| UI standards + docs indexing | `test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` | `+42`, 0 failed |
| full suite 1 | `test` | `+5760 ~2 -1` — one red, `test/logger_feedback_controls_test.dart` `S-5115: the rest chip keeps its running look on the rolling list view`, a file and area this change does not touch (`.work/gateway/test-20261027-000312-84757.log`) |
| flaky check | `test test/logger_feedback_controls_test.dart --plain-name S-5115` | `+2`, 0 failed in isolation — the red is load-dependent, not a regression |
| full suite 2 | `test` | **`+5761 ~2: All tests passed!`** — 5761 passed, 2 skipped, 0 failed (+6 on the 5755 baseline = the six new tests) (`.work/gateway/test-20261027-000821-92300.log`) |

### prove-red verdict

`gateway prove-red 530995d40dd3170d6d20026d8bf2e8665e677e53 test` over the four test files
(`.work/gateway/test-20261027-000240-82962.log`):

```
gateway: prove-red: RED AT 530995d40dd3170d6d20026d8bf2e8665e677e53 (exit 1).
```

14 failures at the base tree, each an assertion on the missing frame rather than a load error — the
six new S-87a tests plus all eight adjusted frame-counting assertions, e.g.

```
S-87a-6 … [E]  Expected: ['bests_down']  Actual: []
S-9202 … [E]   Expected: ['bests_down']  Actual: []
S-3850 … [E]   Expected: ['preferences_down', 'foods_down', 'routines_down', 'bests_down']
               Actual:   ['preferences_down', 'foods_down', 'routines_down']
```

### Mutation record

The bests send moved inside the bundle block, which is exactly the behaviour D-4 forbids:

```dart
    // original
    final bests = await StatsProgressService(_repository).getAllTimeBests();
```

became `if (since == null || since.isBefore(stamp)) { … }` around the four bests lines.

| Failing test | Expected | Actual |
|---|---|---|
| `S-87a-6 a since-current request is answered with none of the three bundle frames and exactly one bests_down` (`test/watch_sync_request_handler_test.dart:970`) | `['bests_down']` | `[]` |

The mutant left the other five S-87a tests green (they use a first request, whose `since` is null), so
S-87a-6 is the guard that pins the every-request rule. Line restored exactly; the group re-ran
**`+6`, 0 failed**, and `grep MUTANT` over the handler finds nothing.

### Residue sweep

- `everyElement('exercises_down')` / exact three-frame lists: the three predicted sites (handler
  S-3851, S-7101; transport S-003) adjusted; zero stale readers remain.
- One **unpredicted** stale reader: `test/watch_sync_idle_reads_test.dart` `S-10405` asserted
  `transport.sent, isEmpty`. The same mechanical read-based adjustment (now "exactly one frame, of
  type `bests_down`", test renamed) — logged as A-14. S-3852/S-3853, S-3854, S-7104/S-7105,
  S-9201..S-9212 (other than S-9202), `watch_session_projection_test.dart` S-9213 and
  `watch_message_order_test.dart` S-9301 survive unchanged.
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`: no
  matches (only `lib/main.dart`, the composition root, imports it).

### Docs

- `docs/state_management/watch_reference_data.md` (+26/-1): "the three reference frames" lost its
  number, and a new `### The bests close every answer` subsection states the rule and names
  S-87a-6, S-87a-7, S-87a-8, S-87a-11, S-87a-12, S-87a-13 and S-9202 by group and test name.
- `docs/state_management/watch_surface.md` (+11/-2): the handler section names `bests_down`, the
  per-request service and the per-request clock; the verified-by list gains the new group.
- `docs/watch_session_sync.md` not edited (it names no message family — plan item 6, Open question 2).
- `test/docs_indexing_contract_test.dart` green, so both pages stay inside the size limit.

### Diff footprint

`git-diff --stat` for this phase: `watch_sync_request_handler.dart` +42,
`watch_sync_request_handler_test.dart` +358, `watch_sync_changed_only_test.dart` ±14,
`watch_transport_test.dart` ±4, `watch_sync_idle_reads_test.dart` ±9,
`watch_reference_data.md` +26/-1, `watch_surface.md` +11/-2 — 436 insertions, 28 deletions. The only
path outside the plan's Predicted Files is `test/watch_sync_idle_reads_test.dart` (the unpredicted
third-party reader above, adjusted, not weakened). Nothing in `lib/watch/`, `WatchSyncProgress.swift`
or `watch/` was touched.

### Fixture note (cost two green rounds)

`EntryRows.setGroups` (`lib/core/utils/entry_rows.dart`) groups observations by the first integer in
the row id (`numberInId(row.id)`) and silently drops rows whose id has no number. A seeded set
fixture must therefore carry one (`obs-<effort>-0-reps` / `-0-weight`, as
`test/stats_bests_builder_test.dart` does); with ids like `obs-<effort>-reps`,
`ObservationGrouper.groupByEffortKind('set', …)` returns `[]` and `getAllTimeBests()` is empty while
every repository getter returns the seeded rows. Recorded as A-13.

### Final verification (after the mutation was restored and the docs written)

| Check | Result |
|---|---|
| `lint` | `180 issues found`, exit 1 on the pre-existing info notices — the baseline count, none in a touched file (`.work/gateway/lint-20261027-001444-1940.log`) |
| `test test/ui_standards_contract_test.dart` | **29 passed, 0 failed** (no UI file and no allowlist entry touched) |
| `test test/docs_indexing_contract_test.dart` | **13 passed, 0 failed** (both edited pages, the plan and this file are inside the ceiling and reachable) |
| full suite | `+5761 ~2: All tests passed!` (`.work/gateway/test-20261027-000821-92300.log`) |
| invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → nothing |

