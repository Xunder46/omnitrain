# Review — Claude code-reviewer, 2026-09-28

**Verdict: BLOCKED on documentation only: 3 CRITICAL doc findings, all MECHANICAL.** The code does what
the plan asks:
- both stacks accept and refuse `distanceSource` identically;
- the import records the watch's source, or `entered` when the watch names none;
- a distance the phone wrote survives later syncs;
- timed instance ids no longer repeat;
- every guard invariant bites.

Fix the three doc claims, fold in F-5, correct the evidence, re-run the suites. There is no third review.

Layers in scope: `lib/core` (sync_protocol, services, utils), `lib/state/workout`, the watch protocol and
the Swift validator, the tests and test helpers, `docs/` and `PROTOCOL.md`. Layers skipped
(unchanged): models, repositories, features, widgets, theme, navigation.

## A. Observed runs (reviewer, this tree)

| Suite | Observed | Baseline | Delta |
|---|---|---|---|
| `flutter test` | `01:16 +3119 ~1: All tests passed!`, exit 0 | +3097 ~1 | +22 = 5 fixtures + 7 import tests (S-876, S-877, S-880 pure, S-880 writer ×2, S-878 ×2) + 10 guard runs |
| `flutter analyze` | `241 issues found.`, 0 errors, 0 in any touched file | 241 | 0 |
| `swift test` | `Executed 242 tests, with 0 failures`, exit 0 | 242 | 0. The fixtures are data-driven; M-R3 and M-R3b prove the Swift walk loads the valid fixture, `…on_round` and `…without_distance` |

The logs are `pr3b_review_*.log` in the reviewer's scratchpad. After the mutations, the tree was
byte-identical: the whole-diff SHA was `e3549bf…` before and after, and all 24 per-file SHAs matched.
After restoring, the new tests passed (+107, green) and Swift again reported 242 tests with 0 failures.

Phase-level runs: Phase 1's four files gave +145, exit 0. Phase 2's six files gave +137, exit 0. Phase 3's
guard plus docs-indexing gave +19, exit 0.

## B. The earlier review (2026-09-27): status

| # | Status in the tree |
|---|---|
| F-1 CRITICAL `distance_source.md:121` | **FIXED.** The absolute is deleted. `:125` now claims only that the source survives a restart and a snapshot/restore, pointed at S-802/S-805/S-821. |
| F-2 WARNING `:49` read as exclusive | **FIXED AS WORDED**, but the rewrite added behaviour with no pointer → C-2 |
| F-3 WARNING: the writer wasn't proven to use the helper | **FIXED.** A clock seam plus a writer test. I re-ran M6: it fails on Mock and Hive (`['timed-e-t-1-1000']`). |
| F-4 WARNING: the `updateEntryValue` I-c path | **FIXED IN CODE.** I re-ran M5: S-883 step 2a fails on both stores with `unsourced distance of 1500.0 m (I-c)`. But the fix made `workout_state.md:103` false (C-1), and the evidence names the wrong producer (W-2). |
| F-5 WARNING `workout_state.md:198` incomplete | **OPEN** (deferred). C-1 edits that page now, so fold it in → W-3 |
| F-6 SUGGEST freshness marker | **FIXED** (2026-09-27) |

## C. Mutations (copy-aside to the scratchpad, restored, SHA-verified)

| Id | Change | What failed | Observed value |
|---|---|---|---|
| M1 (plan) | The import always stores `entered` for a distance > 0 | S-876 only (+6 −1) | all three rows read `entered`; `(5000.0, entered) instead of (5000.0, gps)` |
| M2 (plan) | The Dart kind table drops `distanceSource` | the on-round fixture only (+71 −1) | `Expected: non-empty / Actual: []` |
| M-R3 | Swift drops the travels-with call | 6 assertions, all on `…without_distance.json` | `must not conform`; `expected code semantic_violation, got []`; `must not reach storage` |
| M-R3b | The Swift kind table changes from timed to round | 8: the valid fixture is refused, and the on-round fixture is accepted | shows that Swift loads the valid fixture |
| M-R4 | The import drops "absent means `entered`" | 5: S-877; S-878 on Mock and Hive; S-887 on Mock and Hive (guard I-c at step 0) | `(2500.0, null)`; `(1000.0, null)`; `unsourced distance of 3000.0 m (I-c)` |
| M-R5 (D-302) | A move rebuilds the distance row from the wire | 4: S-878 and S-887 on both stores. The existing `watch_session_import_test` stays green. | `(3000.0, estimated)` where 5200 `entered` is expected; `(3000.0, entered)` where 3500 |
| M-R6 (guard I-a) | A timed delete keeps its extra-weight row | 6: S-883, S-885 and S-886 on both stores, at the delete step | `holds 4 metric-extra-weight rows for 3 entries (I-a)` (and 3 for 2, 2 for 1) |
| M-R7 (guard I-b) | A set delete keeps its extra-weight row | 4: S-884 and S-887 on both stores, at the delete step | `entry 0 holds 0 metric-reps rows (I-b)` |

In every mutation, only the scenarios that name the broken rule fail, and each fails with the value the
defect predicts.

## D. Done Criteria

| Phase | Result |
|---|---|
| 1 | **PASS.** Four-file run +145, exit 0. Swift 242 tests, 0 failures. Full suite green. Analyzer 241, 0 errors; `message_validator.dart` has 0. |
| 2 | **PASS.** Six-file run +137, exit 0. `EntryRows.parseId` count is 1. No `indexOf('-')`. Full suite and analyzer green; the touched files have 0 issues. |
| 3 | **PASS**, with one PARTIAL:<br>• guard plus docs-indexing +19, exit 0;<br>• full suite, analyzer and Swift green;<br>• Step 3.8 sweep 7/7 as expected;<br>• M1 and M2 recorded.<br>The doc-claim table is **PARTIAL** (W-2). |

## E. File deviations

- **All predicted files are present.** No change touches `lib/watch/`, `watch/watchos/Sources/` (except
  the validator), `watch/contract/`, the UI, or any existing fixture file. `manifest.json` only appends.
- **`lib/state/workout/session_core_entry.dart` (+26), the F-4 fix: RATIFIED under D-339.** It adds
  `updateEntryValue` plus a private `_sourceAfterWrite`.
  - This is not a Phase 2 file, and the plan's escape hatch covers only those.
  - It is one function, follows 3a's `setEntryDistance` rule, and M5 proves it.
  - Its behaviour change went undocumented → C-1.
- **The `timer_manager.dart` `clock` seam (F-3): RATIFIED.** It goes beyond D-338's text, but it defaults
  to `DateTime.now` and only `addTimedEntry` reads it. The rest of that diff is exactly D-338: the helper
  and its call site.

## F. Owner decisions

| Decision | Result | Evidence |
|---|---|---|
| D-332 single release | PASS | No migration or back-compat code. The protocol version is untouched. `_knownDistanceSource` only drops a value the gate already refuses. |
| D-333 no corrected distance to the watch | PASS | S-875 is refused with `unexpected_field … distanceMeters` on both stacks. `PROTOCOL.md:256-258` states the rule. The phone's snapshot echoes the mirror's watch-sourced entries, not `WorkoutState` edits (`live_session_mirror_state.dart:266-278`). |
| `distanceSource` field | PASS | An optional three-value enum (`envelope.schema.json:218`). Timed-only and travels-with on both stacks, with identical wording and path. M2, M-R3, M-R3b. |
| Import mapping | PASS | S-876, S-877; M1, M-R4 |
| 3a/3a2 behaviour | PASS | The full suite is green, including `session_summary_distance_test` (D-319 rows; 0 removes the row), `stats_distance_estimate_test` ("est." and pace), `distance_source_test` S-806 (confirm), `entry_identity_test` and `entry_rows_test`. |
| Architecture | PASS | The importer and the state touch only `WorkoutRepository`. No model, schema or repository changed, so the SQL contract is unaffected. Every guard, S-878 and S-880 scenario runs on both Mock and Hive. |

## G. Findings, most severe first

- **C-1: CRITICAL, MECHANICAL (5c REJECT).** `state_management/workout_state.md:103` says `updateEntryValue`
  "preserves all existing fields including … `valueSource`". Since F-4, that is false for a distance.
  - Failure (a): a routine's distance target is written through `updateEntryValue`
    (`session_core_io.dart:270-297`) onto an unsourced 0 row. It is stored as 5000 `entered`; the doc says
    the null source is kept.
  - Failure (b): a 4200 `estimated` row is written to 0. The source is cleared; the doc says it is kept.
  - Fix: delete the `valueSource` clause. Point at `test/distance_source_test.dart` (`S-804` (a)) and
    `test/row_invariants_guard_test.dart` (S-883 steps 2a/2b).
- **C-2: CRITICAL, MECHANICAL (5c-2 REJECT; standard §4.2 and §5).** `distance_source.md:49-55`.
  - The new behaviour sentences have no pointer: `entered` for a value above 0 and none for 0 on
    `setEntryDistance`/`confirmEntryDistance`, and `updateEntryValue` keeping or supplying `entered`.
  - "Both" at `:55` now follows three writes.
  - `:52` calls `updateEntryValue` "the live screen's own timed write", while `:64-65` says the live screen
    has no distance field. The live screen only re-saves the stored value (`workout_session_screen.dart:998-1004`).
  - Failure: an agent reads a live-screen distance editor into the doc and builds against it.
  - Fix: keep the structural sentence (`SessionCore` owns the phone's distance writes) and delete the
    behaviour prose. Point at `distance_source_test.dart` (`S-805`, `S-804` (a)) and
    `row_invariants_guard_test.dart` (S-883 2a/2b). Fix "Both".
- **C-3: CRITICAL, MECHANICAL (5c REJECT).** `data_models.md:515` says "Two paths build their own ids
  instead: the watch import (below), and the routine-template defaults."
  - The template defaults build no ids. They read the effort's first stored row whatever its entry
    number (`session_summary_builder.dart:265-297`).
  - The wording comes from the plan (Step 3.6), but it is still false. Dropping "and read" also erased
    the page's only warning that a reader bypasses the rule.
  - Failure: an agent treats the template defaults as an id writer and misses that, on Hive, they read
    another entry's row.
  - Fix: "The watch import builds its own ids (below); the routine-template defaults read rows without
    the rule."
- **W-1: WARNING, MECHANICAL.** The guard's fixture doesn't discriminate.
  - `row_invariants_guard_test.dart` seeds with `seedExercise`, which only calls `createExercise`. Neither
    store keeps capabilities that way (`mock_workout_repository.dart:296-307`).
  - So "Bench Press (has load)" is treated as a bodyweight exercise. Its sets carry an extra-weight row on
    both stores (a probe showed it, and so did M-R7's bench failure), and so do S-887's imported bench sets.
  - Failure: the guard never exercises a loaded set's row shape (reps and weight, no extra weight).
  - Fix: call `setExerciseCapabilities` after seeding.
- **W-2: WARNING, MECHANICAL.** The evidence and the plan are out of step with the tree.
  - "Guard outcome" still says I-c held throughout, `session_core_entry.dart` is unmodified, and no fix was
    made.
  - The fix-round note names `addEntry`'s carry-forward as the producer and says the fix closes it "from
    either direction". Both are false. The screen never carries a distance
    (`workout_session_screen.dart:1134-1137`), and `addEntry(previousValues: {'distance': 2500.0})` still
    stores 2500 with no source (probe). By code reading, the reachable producer was routine distance
    targets written through `updateEntryValue`.
  - The doc-claim table has 6 stale line refs:
    - `watch_session_capture` :8→:4, :159→:151, :162→:154;
    - `distance_source` :65→:71, :121→:125;
    - `data_models` :535→:534.

    Its `:49` row lists pointers the doc doesn't carry.
  - Also stale:
    - the evidence says "All four mutations", but six are recorded;
    - the plan's Progress says "Final: 3117" (it's 3119);
    - the plan header still says "not started";
    - the Feedback says "swift test still owed" (now observed: 242 tests, 0 failures).
- **W-3: WARNING, MECHANICAL.** F-5 fold-in. C-1 edits `workout_state.md`, which is the trigger F-5 was
  waiting for. At `:198`, point `addTimedEntry`'s id rule at `test/distance_source_import_test.dart`
  (S-880).
- **S-1: SUGGEST, MECHANICAL.** A latent I-c hole.
  - `session_core_entry.dart:127-131` passes `previousValues['distance']` to `timedObservations` with no
    source.
  - Input `addEntry(run, previousValues: {'distance': 2500.0})` → a 2500 row with no source. Today's UI
    can't reach it.
  - Route: a follow-up (PR 3a3), with a guard step.
- **S-2: SUGGEST.** `PROTOCOL.md` Version history lists the fields the 2026-09-25 amendment added;
  `distanceSource` has no entry. Add it to that row or to a new amendment row.
- **N-1: NIT.** `logged_entry_rows.dart:79-82` says "a distance with no value carries none". The builder
  doesn't enforce that; its caller does.
- **N-2: NIT.** S-878 step (a) is a no-op by protocol (the same `eventId`, and "an event is never re-sent
  with different values"). Only step (b) bites (M4, M-R5), so don't count (a) as coverage of D-336.
- **N-3: NIT.** In `expectRowInvariants`, I-b skips rows whose id has no number, and I-a counts rows without
  pairing them. Acceptable under D-332.

## H. Tests

- No `testWidgets`, no real delays, no loose matchers.
- Assertions use exact lists and counts, and read the raw stored source rather than the resolved one.
- The one weakness is W-1.

## I. Docs

```
DOC FALSIFICATION: REJECT — state_management/workout_state.md:103 (C-1); data_models.md:515 (C-3)
DOC STANDARD:      REJECT — distance_source.md:49-55 behaviour without a pointer (C-2)
DOC FALSIFICATION: WARNING — state_management/workout_state.md:198 incomplete (F-5 → W-3)
DOC FALSIFICATION: PASS — watch_session_capture.md (:4, :151, :154), distance_source.md (:11, :71,
  :125), data_models.md (:534), db_integration.md, modality_based_exercise_ui.md, rest_tracking.md,
  state_management/services_and_utils.md, state_management.md
DOC FALSIFICATION: SCOPE — most docs carry no scope block. The set was searched for the changed
  symbols (WatchSessionImporter, TimerManager, addTimedEntry, updateEntryValue, EntryRows.parseId,
  LoggedEntryRows, valueSource/value_source, distanceSource, timed-<), and every hit was read.
```

- The plan's Step 3.8 sweep is 7/7 as expected, but its greps can't reach C-1 or C-3.
- `PROTOCOL.md:256` uses "never", but it cites the fixture that enforces it, so it's OK.
- All three edited docs keep their Scope paragraph first. They add no visuals, controls, code, JSON or
  roadmap, and every table row has the header's cell count.

## J. Conventions and architecture

- **PASS (4):**
  - repository interface only;
  - reuse the canonical owner (`EntryRows.parseId`, `EffortObservation.valueSources`/`sourceEntered`,
    `LoggedEntryRows`);
  - effort kind drives analytics;
  - canonical units (metres).
- **N/A (4):** theme tokens, card chrome and headers, buttons, instrument panel. No UI is touched.
- **Environment safety: PASS.** No `dart:io`, `Platform.is*` or SQLite import.
- **Dead code: none.** Every new member is referenced.

## K. Budget triage ("At review")

This PR has 6 substantive findings (3 CRITICAL, 3 WARNING), which is not more than 6. No DESIGN finding.
This is the PR's second review, so there is no third.

- **This PR, one round, no re-review:** C-1, C-2, C-3, W-1, W-2, W-3. To verify:
  - re-run `flutter test`, `flutter analyze` and the Step 3.8 sweep;
  - `grep -n "valueSource" docs/state_management/workout_state.md` must not claim that
    `updateEntryValue` preserves it;
  - `grep -n "build their own ids" docs/data_models.md` must print nothing.
- **Follow-up via conductor-v2 (PR 3a3):** S-1. Optional: S-2, N-1 to N-3.

---

# PR 3b review — `2026-09-27-03b-stats-pr3b-distance-source-import-plan.md`

Reviewed 2026-09-27 against the working tree on `develop` (executor records in
`…plan.evidence.md`). Verdict: **one blocking documentation claim**, plus two cheap
coverage gaps. One round of fixes, no split, no second review.

## 1. Scope

Layers in scope: `lib/core/sync_protocol`, `lib/core/services`, `lib/core/utils`,
`lib/state/workout`, the watch protocol (`watch/sync_protocol/`) and the Swift validator,
test helpers, `docs/`.

Layers skipped: `lib/data/models/`, `lib/data/repositories/`, `lib/features/`, `lib/widgets/`,
theme/tokens, navigation (untouched by this change).

## 2. Findings

| # | Severity | Where | What | Fix | Agent |
|---|---|---|---|---|---|
| F-1 | CRITICAL | `docs/distance_source.md:121` | The invariant "Only the Summary's write changes a source" is now **false**: the watch import writes a source (the watch's, or `entered`). The same document's own Scope (line 13) now names `WatchSessionImporter` as a writer, so the page contradicts itself. A doc that tells an agent "the import writes no source" is worse than a silent one. | Delete the absolute: keep only what `S-802`, `S-805` and `S-821` verify (a field-by-field copy keeps the source) and point the import's own write at `test/distance_source_import_test.dart` (S-876, S-877). Do not restate the import's behaviour here — the pointer is the fix. | @developer |
| F-2 | WARNING | `docs/distance_source.md:49` | "`SessionCore` owns the write that records a source" — a structural claim now narrower than the page's own Scope. Not false (SessionCore owns *a* write), but it reads as exclusive. | Narrow to the phone's write, or drop the ownership framing and leave `setEntryDistance`/`confirmEntryDistance` named. | @developer |
| F-3 | WARNING | `lib/state/workout/timer_manager.dart:409` | AC-4's wiring is unproven: `uniqueTimedInstanceId` is referenced only by its definition, this call site and S-880's three direct calls. Reverting the call site to the old literal id leaves the whole suite green. | In the guard's S-883, capture the effort's instance ids before step 4 and assert the id added at step 4 is not among them. Either way, a test must fail if the call site goes away. | @developer |
| F-4 | WARNING | `lib/state/workout/session_core_entry.dart:256` vs the guard | I-c ("a distance row greater than 0 has a source") holds today, but nothing pins the one path that could break it: `updateEntryValue(effortId, k, 'distance', x)` preserves the row's existing source, so a positive write onto a null-source row would be unsourced. It is safe today only because the live screen's `previousValues` never carries a distance for `timed`/`drill` (`lib/features/session/workout_session_screen.dart:1135`) and the Summary writes through `setEntryDistance`. Both facts are untested. **Not a bug**: no reachable writer produces a positive unsourced distance and I could not observe one. | Add one guard step that writes a distance through `updateEntryValue` and asserts I-c still holds, so a future change to `_buildPreviousValues` cannot silently break the invariant the guard claims. | @developer |
| F-5 | WARNING | `docs/state_management/workout_state.md:198` | Incomplete: the `addTimedEntry` row of the Timed Management table is silent about the id rule the method now applies. It says nothing false. | No edit in this PR. Fold into the next touch of that page, as a named test pointer rather than prose. | — (next touch) |
| F-6 | SUGGEST | `docs/watch_session_capture.md:299` | The freshness marker still reads `2026-09-26` while the page gained two invariants today. | Bump it, if the repo's convention is to bump on edit. | @developer |

## 3. Acceptance criteria (Step 5a)

| Criterion | Verdict | Evidence |
|---|---|---|
| AC-1 `distanceSource` accepted with a distance on a timed entry, refused elsewhere | PASS | S-871–S-874 red→green on both stacks; five fixtures in the manifest; M2 and M3 prove both kind tables are load-bearing. |
| AC-2 the wire can't carry a phone-side distance change | PASS | S-875 green before and after; the `correct_entry` correction has no distance field. |
| AC-3 the import stores the watch's source or `entered`; no source without a distance | PASS | S-876, S-877, with the **raw** stored source asserted — which is what makes M1 and M4 bite. |
| AC-4 a phone-written distance survives a redelivery and a move; instance ids never repeat | PARTIAL | S-878 PASS on Mock and Hive. S-880 proves the helper but not that the writer uses it → F-3. |
| AC-5 no sequence creates a leftover, stray or unsourced row | PASS | S-883–S-887, `expectRowInvariants` after every step, green on unfixed code (F-6/F-7 NOT APPLICABLE), and the mutation of the set-delete path fails S-884 and S-887 on both stores — so the guard is not vacuous. F-4 notes the one path it does not cover. |

## 4. Scenarios (Step 5b)

PASS — all 14 register entries (S-871–S-878, S-880, S-883–S-887) map to a fixture or a test, each
asserts its register's stated outcome, and all pass. Counted mechanically: five scenario ids in
`fixtures/manifest.json`, nine in the two new test files, none missing.

## 5. Doc falsification and standard (Steps 5c, 5c-2)

```
DOC FALSIFICATION: REJECT (1) — distance_source.md:121 — "Only the Summary's write changes a
  source" is untrue: the import also writes one, so this change made the claim false → delete the
  absolute, keep the copy-keeps-the-source half, point the import's write at
  test/distance_source_import_test.dart
DOC FALSIFICATION: WARNING (2) — distance_source.md:49 ownership narrower than its own Scope;
  state_management/workout_state.md:198 incomplete (no false claim)
DOC FALSIFICATION: PASS (6 verified) — watch_session_capture.md, distance_source.md (except the two
  rows above), data_models.md, db_integration.md, state_management/services_and_utils.md,
  state_management/workout_state.md
DOC FALSIFICATION: SCOPE (34 docs) — no Scope declaration, so all were treated as implicated and
  searched for the changed symbols (WatchSessionImporter, TimerManager, EntryRows.parseId,
  value_source, captureFieldKinds, timed-<, message_validator); every hit was read. Adding Scope
  paragraphs is how to narrow this, never guessing a skip.
DOC STANDARD: PASS — no prohibited content added to docs/. The added lines are
  behaviour statements with test pointers: no values, no visuals, no control inventory, no roadmap,
  no copied code, and no absolute word introduced without a guard.
```

The `data_models.md` edit is the model for F-1's fix: it removed a false clause ("build **and read**
their own ids") rather than editing a description into a corrected one, and kept the pointer that
proves the remaining claim.

## 6. Architecture

| Layer | Verdict | Note |
|---|---|---|
| `lib/core/` (protocol, services, utils) | PASS | `message_validator.dart` and `watch_session_importer.dart` carry 0 `package:flutter` imports; the importer still depends on `WorkoutRepository` only; no storage access; no new dependency. |
| `lib/state/workout/` | PASS | `uniqueTimedInstanceId` is a pure static helper over `Iterable<String>`; `addTimedEntry` still writes through the repository; no UI, no direct storage. |
| `lib/features/`, `lib/widgets/` | PASS | Untouched, as the plan requires. |
| Buttons (screen rule) | N/A | No screen, widget or header touched. |
| Dead code | PASS | Both new members are referenced (`_knownDistanceSource` by `_Entry.parse`, `uniqueTimedInstanceId` by `addTimedEntry`); no unreferenced class introduced. `AppState` is not adjacent to this change. |
| Environment safety | PASS | No `dart:io`, no `Platform.is*`, no SQLite import; the Swift change is shared-source only. |

## 7. Tests

```
MISSING: test/row_invariants_guard_test.dart (S-883) — the timed-instance id wiring (F-3)
MISSING: test/row_invariants_guard_test.dart — updateEntryValue(effortId, k, 'distance', x) (F-4)
```

No stale tests: every cited test file exists, and the full suite is 3117 passed, 0 failed, up from
3097 (five fixtures, five Phase 2 tests, ten guard runs).

## 8. DRY and clean code

- The travels-with rule and the kind table appear twice, Dart and Swift. That is the two-stack
  design (H2, H3) with deliberately identical wording, and M2/M3 prove each side is load-bearing —
  not a violation.
- `_knownDistanceSource` gives the defensive read a name and a home beside `_real`/`_ms`; the
  unknown value can only come from a peer the gate would already refuse. Good.
- `uniqueTimedInstanceId` takes named parameters and keeps the id shape; the imported-id form is
  documented as never passed to it. Good.
- No new magic numbers, no nesting introduced, no commented-out code.

## 9. Global conventions

```
PASS (3): Reuse the canonical owner — EntryRows.parseId replaces the importer's local prefix parser
  (D-337), EffortObservation.valueSources/sourceEntered are reused rather than re-declared, and the
  import writes through the shared LoggedEntryRows rather than a second row builder;
  Effort-kind drives analytics — I-a/I-b key off effortKind and D-335 keys the source off the timed
  entry's own distance; Units + canonical storage — metres stay canonical, no unit label or
  conversion added.
N/A (3): Theme tokens only, Card chrome / headers, Instrument panel — no screen, widget, header,
  colour or visual value is touched.
N/A (1): Timestamps are source data — no elapsed or completion derivation changed; the id helper
  takes the caller's clock rather than reading one.
```

## 10. Scope budget triage

Five findings: one CRITICAL doc claim, two cheap test additions, one incomplete-doc warning, one
suggestion. Under six, no DESIGN finding spans layers, and no second review round is needed.

**Fix in this PR, one round:** F-1 (blocking), F-2 (same file, same edit), F-3 and F-4 (assertions
in an existing test file). F-6 is optional.

**Deferred:** F-5 — touch that table row when `workout_state.md` is next edited rather than opening
a PR for one line.

No follow-up PR required. Re-running the full suite after the fixes is sufficient; this review does
not need to be repeated.
