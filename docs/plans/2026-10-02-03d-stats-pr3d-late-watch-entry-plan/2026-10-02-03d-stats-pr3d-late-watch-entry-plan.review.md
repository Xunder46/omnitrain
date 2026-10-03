# Code Review — Stats PR 3d: late watch entry survives Edit Session Discard

**Base**: `c25617a9` (branch `develop`, ahead 1)
**Plan**: `2026-10-02-03d-stats-pr3d-late-watch-entry-plan.md` (359 lines)
**Evidence**: `2026-10-02-03d-stats-pr3d-late-watch-entry-plan.evidence.md` (396 lines)
**Diff**: 18 modified tracked files + 1 new test file; additive throughout (parity file gained lines only; probe `+12 −12`).

**Layers in scope**: models (`lib/core/models/`), repositories (`lib/data/repositories/`), state (`lib/state/`), features (`lib/features/session/`), wiring (`lib/main.dart`), tests, `docs/`
**Layers skipped**: `lib/widgets/`, `lib/core/services/`, `lib/core/utils/`, `lib/core/constants/` — untouched (`watch_session_importer.dart` is a *caller* of the new method, not a changed file)

## Verdict: CHANGES_REQUESTED

The mechanism is correct, idempotent, environment-safe and architecture-clean; the 24 new state-layer tests are genuine and pass. Two things block: the evidence records a test run that never happened, and the feature's only production wiring has no test.

---

## Findings

### 1. 🔴 BLOCKER — plan/evidence vs code — S-1411 has no test, and the evidence claims a red→green run for it
- `…-plan.md:107` maps A13 to `S-1411, S-1412`; `…-plan.md:185` defines S-1411 as a direct cross-store comparison (both stores' bench rows, round rows, timed instances and inbox rows equal by `toMap()`).
- `…-plan.md:226` (Phase 1) writes S-1401–S-1410, S-1413, S-1414; `…-plan.md:239` (Phase 2) adds only S-1412. **No phase writes S-1411.**
- `…-evidence.md:43` nevertheless records `S-1411 … FAIL (expected) … PASS`, and `…-evidence.md:73` states "S-1411 and S-1412 are Phase 2's; they are not in this file and are not counted here." The two statements contradict each other.
- `grep -rn "S-1411" test/` returns nothing. The scenario does not exist.
- Parity is *substantively* covered — the probe runs every scenario on both stores (`test/watch_session_edit_restore_late_entry_test.dart:322`) with identical absolute expectations, so a store divergence fails — but the scenario as specified (a direct `toMap()` comparison) is not implemented, and A13 is substantiated only by its repository half (S-1412).
- **Fix** (either is cheap): write the S-1411 comparison, **or** remove S-1411 from the register, re-map A13 to S-1412, and delete the S-1411 row from the evidence table. → @developer

### 2. 🟡 MAJOR — test coverage — the feature's only production wiring is untested
- `lib/features/session/workout_session_screen.dart:424-427` is where the watermark is actually captured (guard `widget.editMode && _editSnapshot == null`, then `appliedWatchEntryIds()`); `:491` is where it enters the snapshot.
- Every test reaches the watermark through the probe's own `_enterEditMode` helper instead. Deleting lines 424-427, or inverting the guard, leaves all 24 probe tests green while the feature is dead on device.
- The probe is otherwise honest: it reproduces the production order (`loadHistoricalSession` → watermark → `loadSessionData()` → `snapshotSessionState()`) with the real `WatchSessionInbox` injected as the recovery handle.
- **Fix**: one `testWidgets` in `test/interaction_flow_test.dart` that enters edit mode on a real `WorkoutSessionScreen` and discards — enough to fail if the screen stops reading the watermark. → @developer

### 3. 🟡 MINOR — docs §4.2 — `docs/watch_session_capture.md:98-100`
The added Rationale sentence (the restore "un-marks exactly that entry and runs one ordinary import pass … recovers it at the next import pass for that session") is a behavioural claim with no verification pointer. Not treated as a blocker here because the Invariant at `:193-200` carries the pointer for the same behaviour, and the sentence matches the unchanged Rationale prose beside it at `:92-94`. If it stays, add the test pointer or fold it into the Invariant. → @developer

### 4. 🟡 MINOR — doc accuracy — `docs/watch_session_capture.md:98-100`
"The un-mark is durable … recovers it at the next import pass for that session" holds only if a pass runs for that session. `WatchSessionInbox.resume` settles only sessions with an unapplied `session_end` (`lib/state/watch/watch_session_inbox.dart`, `getWatchSessionIdsWithUnappliedEnd`). For a session whose end was already applied, recovery waits on the wrist re-sending — which it does until receipted, so nothing is lost, but the sentence overstates the guarantee. → @developer

### 5. 🟡 MINOR — 5c SCOPE — `docs/watch_session_capture.md:3-19`
The scope block names the watch modules (`watch_session_inbox.dart`, `watch_session_importer.dart`, `logged_entry_rows.dart`, `watch_incoming_router.dart`, `watch_sync_wiring.dart`) but the document now also describes the Edit Session restore, which lives in `lib/state/workout/session_core_lifecycle.dart` — outside the declared scope. Widen the scope block, or move that prose. → @developer

### 6. 🟡 MINOR — plan accuracy — the Executor block's M1 expectation is wrong
The plan's Executor block states M1 must make S-1409 fail. `…-evidence.md` records M1 making **S-1410** fail, with S-1409 staying green (re-applying every applied row also re-applies the pre-edit deletion, so S-1409 still passes). The evidence explains and accepts the deviation and the mutation still proves the watermark is load-bearing — but the plan's Executor text now misstates which test it targets. → @developer

### Carried (not counted in the six)
- 💡 NIT — the stamp-clearing transformation is written twice, at `lib/data/repositories/hive_workout_repository.dart:3137-3143` and `lib/data/repositories/mock_workout_repository.dart:2287-2290`. Hive's trailing `toMap()` is required (it stores maps); the duplicated `'applied_at_ms'` literal and parse-and-reserialise are not. A `WatchInboxEntry.copyWith(appliedAtMs: null)` would centralise it. Non-blocking. → @dba
- `scripts/sqlite_schema.sql:1601` stale comment — already recorded as O-4.1 and deliberately deferred; pre-existing, outside this PR.
- `docs/plans/2026-10-02-05a-…` / `05b-…` untracked folders — other planners' artifacts, not this PR's.
- `lib/state/app_state.dart` unreferenced `AppState` — known pre-existing WARNING, not touched here.

---

## Step 5a — Acceptance criteria

| # | Scenario | Located at | Result |
|---|---|---|---|
| A1, A2 | S-1401 | probe `:333` | ✅ late set returns; user's set gone |
| A3 | S-1402 | probe `:387` | ✅ effort + instance + summary return |
| A4 | S-1403 | probe (S-1403 test) | ✅ deleted-during-edit entry returns |
| A5 | S-1404 | probe (S-1404 test) | ✅ returns as the wrist sent it |
| A6 | S-1405 | probe (S-1405 test) | ✅ both return |
| A7, A8 | S-1406 | probe `:603-643` | ✅ second sync and wrist re-send duplicate nothing |
| A9 | S-1407 | probe `:652` | ✅ no-op, nothing lost |
| A10 | S-1408 | probe (S-1408 test) | ✅ Save keeps both (`_saveEditChanges` untouched) |
| A11 | S-1409 | probe (S-1409 test) | ✅ pre-edit deletion stays deleted |
| A12 | S-1410 | probe (S-1410 test) | ✅ late correction and late deletion recovered |
| A13 | S-1411, S-1412 | parity file `:524` only | ⚠️ **partial** — see finding 1 |
| A14 | S-1413 | probe `:850` | ✅ no late entry → untouched |
| A15 | S-1414 | probe `:883` | ✅ null watermark → nothing recovered |

## Step 5b — Scenario register cross-check

S-1401…S-1410, S-1413, S-1414 — each has a `test()` asserting the register's stated outcome, on both stores, passing (24/24 per the evidence and the governor's baseline).
S-1412 — `test/watch_capture_repository_parity_test.dart:524`, asserts the four stated outcomes.
**S-1411 — no test. WARNING, and the evidence's red→green row for it is false.** (Finding 1.)

## Step 5c — Documentation falsification

Implicated: every document whose declared scope intersects the changed files, plus (per rule 4) every document with no parseable scope block. Verified against post-change source: the six edited docs, `rest_tracking.md`, `navigation_and_screens.md`, `watch-app-setup-and-qa.md`, `state_management.md`, `constants_reference.md`, `design_system.md`, `stats_screen.md`, `session_summary.md`, `modality_tracking.md`, `README.md`. Result:

- ✅ PASS — no false claim found. `rest_tracking.md:237`'s "the snapshot carries no rest records" still holds (the inbox stages no rest kind). `navigation_and_screens.md` and `watch-app-setup-and-qa.md` still correctly describe `createWatchSync`'s existing handles. The six edited docs name only types and tests that exist.
- 🟡 WARNING — `docs/state_management/services_and_utils.md:577-579` describes `WatchSyncGraph` as "the mirror, and the inbox behind the one capability a screen needs" — still true of what a *screen* needs, and the paragraph added directly below at `:583-587` supplies the second handle, so the reader is corrected. Incomplete rather than false.
- 🟡 SCOPE — `docs/watch_session_capture.md` — declared scope narrower than content; verified anyway. See finding 5.
- ⚠️ CONFLICT — none between documents.

## Step 5c-2 — Documentation standard

**✅ PASS — no prohibited content added.** The six edited docs add structure, rationale, invariants and vocabulary only. No hex literals or visual values, no arrow-chain walkthroughs, no control inventory, no restated numerics, no pasted code or SQL, no roadmap or unshipped-change notes. `docs/watch_session_capture.md:193-200` and `docs/state_management/workout_state.md` state the new invariant with a named test pointer, which is the required form. The only §4.2 gap is finding 3.

## Step 5d — Global conventions

```
PASS (2 rules): Timestamps are source data — the recovery re-imports through the existing importer, which stamps each row from the entry's logged time; no new local counters.
                Reuse the canonical owner — the recovery reuses WatchSessionInbox + WatchSessionImporter rather than rebuilding import logic; the new write goes through the repository interface.
N/A  (5 rules): no unit-bearing value (Units), no styling (Theme tokens), no card chrome (OmniSurface/OmniCardHeader), no analytics keying (Effort-kind drives analytics), no UX surface (Instrument panel) — the diff touches state, data and wiring only.
FAIL: none
```

## Architecture, environment and clean code

- **Models** — `session_edit_snapshot.dart:65,81`: one nullable `Set<String>?` field plus constructor param, no Flutter/platform imports, immutable. ✅
- **Repositories** — `clearWatchInboxApplied` on the interface (`workout_repository.dart:778`), Hive and Mock. Both return `Future<void>`; Mock stays in-memory with no SQLite or platform import; skip rules are identical (absent → skip, already-null → skip, never creates). ✅
- **State** — the recovery is reached through `WatchLateEntryRecovery` (`watch_session_inbox.dart:89`) declared on the inbox, so `SessionCore` depends on an interface, not the concrete inbox. `WorkoutState` is a pure delegator (`:106-108`). ✅
- **Features** — the screen reads state via its injected `WorkoutState`; no repository or storage access added. ✅
- **Environment safety** — `main.dart` passes `watchSync?.lateEntryRecovery`; null on web/desktop/Android leaves the restore byte-identical to pre-fix behaviour (D-803, probe S-1414). The bootstrap reorder (`WorkoutState` now built after `createWatchSync`) is safe: nothing between the old and new positions referenced `workoutState`, and every `createWatchSync` dependency is defined earlier. ✅
- **Retired-runtime contract** — no schema, `models.dart` or SQL change; `sqflite` untouched. ✅
- **Idempotence** — `WatchSessionImporter.apply` processes only `unapplied` rows, `_Pass` uses deterministic ids with existence guards, and `_topUpRating` (`watch_session_importer.dart:356-363`) is a no-op when the session already carries the rating, so un-marking a late row cannot duplicate rows or double-apply a rating. `_attach` is put-if-absent. ✅
- **No dead code** introduced; no unrelated reformatting; no scratch or probe files outside the two named artifacts.
- **Buttons** — not run: no screen or button was touched.

---

Critical: 1 | Major: 1 | Minor: 4 | Carried: 4

→ @developer: findings 1, 2, 3, 4, 5, 6 — all are one-test or one-paragraph fixes; no re-review loop expected.
→ @dba: the carried `copyWith` nit only, if you want it in this PR.
