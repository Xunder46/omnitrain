# Evidence — 18a phone hardening

Plan: `2026-10-08-18a-phone-hardening-plan.md`. Implementers append to this file; the reviewer reads
it and appends its findings. One row per checklist item, with the command and the pasted counts.

## Baselines (taken before Phase 1)

| Check | Command | Result |
|---|---|---|
| Dart tests | `.github/copilot/scripts/macos/gateway.sh test` | 4061 tests, ~1 pre-existing failure (record the exact name here when re-measured) |
| Analyzer | `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors |
| Swift tests | `.github/copilot/scripts/macos/gateway.sh swift-test` | 335 tests / 0 failures |

## Phase 1 — no `initState` notifies during build (@developer)

| Item | Command | Result |
|---|---|---|
| Post-frame deferral in `WorkoutSessionScreen` | | pending |
| Contract test `test/initstate_notify_contract_test.dart` | | pending |
| S-150 widget test | | pending |

## Phase 2 — the summary never throws (@developer)

| Item | Command | Result |
|---|---|---|
| Guard in `computeSessionRestTimeMs` | | pending |
| S-153 test | | pending |

## Phase 3 — an end is never stored before its start (@developer)

| Item | Command | Result |
|---|---|---|
| Writers clamped | | pending |
| S-155 tests | | pending |

## Phase 4 — migration 14 → 15 (@dba)

| Item | Command | Result |
|---|---|---|
| Hive step + Mock step | | pending |
| `test/data_migration_test.dart` | | pending |
| S-156 test | | pending |

## Red → green (prove-red)

| Scenario | Command | At the base | After |
|---|---|---|---|
| S-150 | `gateway.sh prove-red <base-ref> test test/session_screen_build_phase_notify_test.dart -- lib/features/session/workout_session_screen.dart` | pending | pending |
| S-153 | `gateway.sh prove-red <base-ref> test test/session_summary_inverted_window_test.dart -- lib/core/services/session_summary_service.dart` | pending | pending |
| S-155 | `gateway.sh prove-red <base-ref> test test/session_window_never_inverted_test.dart -- lib/state/workout/session_core_lifecycle.dart` | pending | pending |
| S-156 | `gateway.sh prove-red <base-ref> test test/data_migration_test.dart -- lib/core/constants/data_version.dart lib/data/repositories/hive_workout_repository.dart` | pending | pending |

## Reviewer findings

Diff vs Predicted Files: 24 files, +1836/−84. In set: every `lib/`, `test/`, plan and evidence file the
plan predicted for P1–P4, plus `docs/global_conventions.md` (P1), `docs/session_summary.md` (P2) and
`docs/constants_reference.md` (P4). Out of set: `docs/modality_based_exercise_ui.md` +
`docs/state_management/workout_state.md` (P3, declared in Assumption 12) and
`docs/plans/2026-10-08-18-watch-qa-index.md` (P4, undeclared → F3). Nothing predicted was left
untouched.

Per-S-x conformance: S-150…S-156 each have a fixture-conformant test that fails at its phase base
(prove-red, below) and passes at HEAD.

Impact Check: all 8 rows re-run; cited line numbers drifted as expected; 7 `WorkoutSessionScreen`
construction sites and 2 `loadSessionData` callers the rows did not list were found and are
effect-equivalent — no unguarded surface (F4). Row 126 carries no grep command.

`WorkoutRepository` parity on the touched rows: the two step lists, the two repair bodies and their
outputs match; `test/data_migration_test.dart:581` compares the repositories' `.toMap()` on the same
fixture. The mirrored body is the required Mock/Hive twin, not a DRY violation.

Quantified defects: 0 blocker, 1 major (F1), 3 minor (F2–F4).

Assumption Log: 14 RATIFY, 15 RATIFY with a note, 13 RATIFY, 9 RATIFY, 12 REVERT in part; the
QA-index edit is an unrecorded change (ESCALATE). Details in `## Code review 1 (18a)`.

## Code review 1 (18a)

Range reviewed: `git diff 1665f64..HEAD` (committed only; commits `15bab66`, `323fcfe`, `bc96cd2`,
`a89fb4a`). The evidence tables at the top of this file are the seed template; the filled tables live in
`2026-10-08-18a-phone-hardening-plan.evidence.md`.

### Findings

F1 | major | `docs/state_management/workout_state.md:91`, `:95` — both rows weld a group name and a test
name into one backticked span (`S-155 writer table — every phone-owned writer leaves an ordered window
endSession clamps a start that lies ahead of the phone clock`), a string that is neither a group nor a
test, so neither citation can be resolved; the group is `S-155 writer table — every phone-owned writer
leaves an ordered window` and the tests are `endSession clamps a start that lies ahead of the phone
clock` (`test/session_window_never_inverted_test.dart:109`) and `updateSessionEndTime with a zero or
negative duration writes nothing` (`:139`). Fix: close the backtick after the group name, open a new one
for the test name. Guard: `test/docs_indexing_contract_test.dart` gains a rule that a backticked
citation naming a `test/…` file must resolve — the name that follows it in the span must appear verbatim
in that file's source. → @developer

F2 | minor | `docs/modality_based_exercise_ui.md:335` — the Save bullet now restates the clamp
(`endedAtMs = max(startedAtMs, startedAtMs + durationSecs × 1000)`, "(D-153; a stored end never precedes
its start)") with no verification pointer, while the sibling edits in `session_summary.md` and
`workout_state.md` name their tests; `docs/documentation_standard.md` §4.2 requires a pointer where
behaviour would otherwise be described. Fix: cite `test/session_window_never_inverted_test.dart`
(group `S-155 writer table — every phone-owned writer leaves an ordered window`) instead of the
expression; Assumption 12's claim that all three sites name the S-155 tests is false for this site →
REVERT that clause. Guard: the F1 citation rule, plus the existing pointer convention. → @developer

F3 | minor | `docs/plans/2026-10-08-18-watch-qa-index.md` (row 19) — rewritten by phase 4 (`a89fb4a`)
although the file is not in Predicted Files; the row describes the 19a/19b plans and their D-170…D-181 /
S-170…S-185, and the plan folder it names (`docs/plans/2026-10-08-19a-phone-authority-plan/`) is
untracked in this commit, so a reader of the committed tree cannot check the row. No product claim is
affected (planning artefact). Fix: record the edit in the plan's Assumption Log as intentional, or drop
it from this PR. → @developer (planner)

F4 | minor | plan `:122-127` — Impact rows 122 and 123 under-enumerate their readers and row 126 gives no
grep at all: `WorkoutSessionScreen` is also constructed at `session_overview_screen.dart:108/324`,
`session_summary_screen.dart:429`, `my_routines_screen.dart:253`, `day_session_list_screen.dart:275`,
`exercise_detail_screen.dart:35`, and `loadSessionData` is also called at `my_routines_screen.dart:244`
and `day_session_list_screen.dart:264`. I re-ran the sweep: every unlisted site receives the same
one-frame deferral, and all 104 `endedAtMs` sites in `lib/` are null-guards or arithmetic over completed
rows, so no unguarded surface exists — but the next reader should not have to re-derive that. Fix: add
the missing sites and row 126's grep command. → @developer

### Ordered answers

**1. Phase 1 order effects.** No first-frame reader sees anything different. Frame 1 renders the spinner
by field initializer (`workout_session_screen.dart:109`, `session_overview_screen.dart:43`) exactly as
before, and `_exercises` was empty during frame 1 before too — the old synchronous call could not await.
The 1 Hz ticker reads only `_currentSession`/`endedAtMs` (`workout_session_global_timer.dart:15`), which
the load does not write; `didChangeAppLifecycleState` re-loads on its own (`:1095` and siblings) and is
not a build-phase path; edit mode's `_computeStaticElapsed` (`workout_session_edit_mode.dart:12`) is
reached from UI actions after the first frame. `captureWatermark` (`workout_session_screen.dart:429`) is
edit-mode only and its *internal* order — watermark, then rows, then the snapshot that carries it
(`:497`), consumed by `recoverEntriesAppliedSince` (`session_core_lifecycle.dart:376-379`) — is
untouched: an entry that slips into the inbox during the one deferred frame is either already present in
the rows read a moment later, or still newer than the captured watermark and therefore replayed. Nothing
is lost. No pusher reads or mutates state expecting the load to have started: the five home-screen pushes
(`home_screen.dart:670/724/744/792/926`) are fire-and-forget, and the three other entry points await
their own `loadSessionData` *before* pushing (`my_routines_screen.dart:244/253`,
`day_session_list_screen.dart:264/275`, `session_overview_screen.dart:62/108`). The contract test's own
header documents its limits (textual scan, same-file hop, notifying methods flagged by name, calls
inside `addPostFrameCallback`/`Future.microtask`/`Future.delayed`/`scheduleMicrotask` skipped); it would
miss a notify reached through a service or under another name — which is why S-150…S-152 exist — and it
does not misfire on the three deferred sites (suite green).

**2. Phase 2–3 `endedAtMs` writers.** No path other than the documented exemption can store
end < start. The three phone writers: `endSession` (`session_core_lifecycle.dart:23`, clamped),
`updateSessionEndTime` (`:162`, clamped), `resetSessionTimerStart` writes no end (`:69` early return).
The only writer that stores an externally-sourced end is the importer `watch_session_importer.dart:517`,
which stores the wire's own start/end pair (`:516-517`) for a session the phone does not hold — D-153's
exemption, unchanged. The adoption bridge never stores a wrist time as an end: `_adopt` holds a *running*
row (`watch_session_adoption_bridge.dart:655`, `startedAtMs = atMs`, `endedAtMs` null) and `onLifecycle`
reads only `payload['state']`; a wrist `completed` therefore closes the phone row through
`endSession()` → `max(start, now)`. `endSession` is never called with the wrist's `at`. A wrist end can
only reach storage through the importer's wire pair, whose start is the wrist's own. `resetSessionTimerStart`
writing nothing for an ended session breaks no flow: its single production call site is
`workout_session_screen.dart:1463`, guarded by `first exercise && !editMode`; edit mode edits the end via
`updateSessionEndTime`, and a rolling or running session (`endedAtMs == null`) still moves its start —
asserted by `resetSessionTimerStart still moves a running session start`.

**3. Phase 4 migration.** Correct on every count checked. Key names and types match
`TrainingSession.toMap`; `_asStringMap` (`hive_workout_repository.dart:812`) is
`Map<String, dynamic>.from(raw as Map)` — a full copy, so the `put` of the whole map preserves every
other field and no field is dropped; running rows are skipped, so no in-progress session is closed;
ordered rows are skipped, so a second pass writes nothing (asserted for both repositories at
`test/data_migration_test.dart:581` and `:515`, including the exact write counts); the framework advances
the version per step, so a throw inside step 15 leaves the stored version at 14 and the next launch
re-runs the step — idempotent, never half-applied. Version bump: `data_version.dart:36` is 15; the shim
fires only at `storedVersion == 1` (`data_migration_service.dart:75-76`) and both repositories return at
most 14 from `getLegacyAppliedDataVersion()`, so a legacy device starts at 14 and runs step 15 exactly
once; no other `14` in `lib/` outside that legacy-marker ladder. `dataMigrationStepsForTest` is
`@visibleForTesting` (`hive…:331`, `mock…:301`) and has no production caller. Parity: step lists, bodies
and outputs match, and the test compares the two stores' `.toMap()`. Residual (theoretical): a stored
session map with a non-String key would throw inside `_asStringMap`; every row this app writes comes from
`TrainingSession.toMap()`, and a throw is retried, not lost.

**4. Test non-vacuity.** prove-red at the recorded bases: phase 1 base `1665f64` →
`test/initstate_notify_contract_test.dart` RED with the assertion naming all three trap sites, and
`test/session_screen_build_phase_notify_test.dart` RED `+1 -3` (S-150, S-151(a), S-152 fail on
`setState() or markNeedsBuild() called during build`; S-151(b) passes at the base by design — documented
negative guard, Assumption 2). Phase 2 base `15bab66` → `test/session_summary_inverted_window_test.dart`
RED `+1 -1`, S-153 failing with `int.clamp`'s own `ArgumentError`
(`session_summary_service.dart:33`). Phase 3 base `323fcfe` →
`test/session_window_never_inverted_test.dart` RED `+3 -2`, failing on the guarded invariant. Phase 4
base `bc96cd2` → `test/data_migration_test.dart` RED by compile error (the accessor does not exist at
the base), exactly as Assumption 15 records; that red proves the step is appended but cannot by itself
prove the repair assertion is non-vacuous — the recorded mutation table (3 mutations, including
move-the-start-instead-of-the-end and `>` instead of `>=`) and the Hive write-count/watch assertions
carry that, and I did not re-run mutations (brief). No vacuous test found; every new test asserts an
observable outcome (a throw, a stored pair, a write count), not a call.

**5. Documents.** `global_conventions.md:16` states a convention that holds and names guards that exist
(group `initStateNotifyContractTest` at `test/initstate_notify_contract_test.dart:238`, test at `:289`);
`session_summary.md:170-175` matches `session_summary_service.dart:19-34` and its citation
(S-153, `test/session_summary_inverted_window_test.dart:116`) resolves; `constants_reference.md:544` is
15, matching `data_version.dart:36`; `db_integration.md:156-215` remains true (no per-step table; the
append-a-step rule still describes the code); `state_management/workout_state.md:91/95` are true in
substance but unresolvable by name (F1); `modality_based_exercise_ui.md:335` is true as written but
pointer-less (F2). `test/docs_indexing_contract_test.dart` passed in the full run, so the 64 KiB ceiling
and its hex-literal / arrow-chain / roadmap checks hold.

**6. Hygiene, scope, Open questions.** Out-of-set files: the two phase-3 doc edits (declared) and the
QA-index edit (F3). Open questions 1–3 have their defaults implemented and asserted: the stat shows `0`
rather than throwing (S-153), the stored row is repaired by an appended step 15 (S-156), and a
wrist-ended session stays history (S-155). No other unrecorded guess found besides the QA-index edit.

### Checks

```
prove-red 1665f64 test test/initstate_notify_contract_test.dart      → RED (assertion names 3 sites)
prove-red 1665f64 test test/session_screen_build_phase_notify_test.dart → RED +1 -3
prove-red 15bab66 test test/session_summary_inverted_window_test.dart   → RED +1 -1 (ArgumentError)
prove-red 323fcfe test test/session_window_never_inverted_test.dart     → RED +3 -2
prove-red bc96cd2 test test/data_migration_test.dart                    → RED, compile error at base
gateway.sh test → 01:56 +4078 ~1: All tests passed!  (.work/gateway/test-20261007-233623-69361.log)
CONVENTIONS: PASS (3): timestamps are source data; reuse the canonical owner; the new build-phase rule.
             N/A (5): units, theme tokens, card chrome, effort-kind, instrument panel — no such code
             touched. FAIL: none.
DOC FALSIFICATION: ❌ REJECT (1) — state_management/workout_state.md:91,95 → F1.
DOC FALSIFICATION: 🟡 SCOPE — no checked document carries a §4.1 scope declaration, so rule 4 implicates
             all of them; the 14 that name a touched surface and the 5 changed docs were verified.
DOC STANDARD: ❌ REJECT — modality_based_exercise_ui.md:335 — class 5 / §4.2 — behaviour added with no
             verification pointer → F2.
IMPACT: 8 rows checked, 8 verified, 9 unlisted readers found (all effect-equivalent); row 126 has no
             grep → F4.
```

### Assumption Log adjudication

- 14 (S-002 edit `_lastLegacyMarkerVersion = 14`): **RATIFY** — the S-002 assertions
  (`test/data_migration_test.dart:186-250`) are its guard; promote to a numbered decision.
- 15 (phase-4 proof by mutation): **RATIFY with note** — the base red is a compile error, so keep the
  mutation record as the non-vacuity evidence and name the write-count assertions as the permanent guard.
- 12 (three doc sites name the S-155 tests): **REVERT in part** — false for
  `modality_based_exercise_ui.md:335` (F2).
- 13 (`updatedAtMs` untouched): **RATIFY** — deliberate, and the parity assertions fix the stored shape.
- 9, 2, 1: **RATIFY** — consistent with D-150/D-153; Assumption 2's base-green S-151(b) is a documented
  negative guard, not a vacuous test.
- Unrecorded: the QA-index rewrite → **ESCALATE** (F3).

VERDICT: CHANGES_REQUESTED

## Fix round 1

Answering F1–F4 (developer, docs only — no `lib/` or `test/` change). Every name cited below was
grep-verified in `test/session_window_never_inverted_test.dart`: group at `:89`, tests at `:109`,
`:140`.

- F1 fixed — `docs/state_management/workout_state.md:91/95` close the backtick after the group
  (`S-155 writer table — every phone-owned writer leaves an ordered window`) and open a new one for the
  test name; the same weld in this plan's evidence-file S-155 row was split too. The suggested
  docs-contract rule is **not done — separate PR** (out of scope for this fix round).
- F2 fixed — `docs/modality_based_exercise_ui.md:335` drops the restated `max(…)` expression for a
  pointer to `test/session_window_never_inverted_test.dart` (same group verbatim); Assumption 12's
  "all three sites name the S-155 tests" clause is corrected in the plan.
- F3 fixed — the QA-index row-19 rewrite is recorded as intentional in the plan's Assumption Log
  (entry 16); the edit stays in this PR.
- F4 fixed — plan Impact rows 122/123 list the nine unlisted sites (`WorkoutSessionScreen(` at
  `session_overview_screen.dart:108/324`, `session_summary_screen.dart:429`,
  `my_routines_screen.dart:253`, `day_session_list_screen.dart:275`, `exercise_detail_screen.dart:35`;
  `loadSessionData` at `my_routines_screen.dart:244`, `day_session_list_screen.dart:264`); row 126
  carries `grep -rn endedAtMs lib/` -> 104 sites in 23 files.

Checks on the fixed tree: `gateway.sh test test/docs_indexing_contract_test.dart` →
`00:00 +9: All tests passed!`; `gateway.sh lint` → `196 issues found` (0 errors; the single warning at
`lib/features/routine/routine_setup_screen.dart:1046` is pre-existing and untouched).
