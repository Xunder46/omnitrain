# Feature: 121b — a watch clock the phone already logged never starts the next interval

> Status: Iteration 1 active (planned 2026-11-05, no code yet)
> Next handoff: @crew-builder-app (Phase 0, red tests)
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Builds on: `docs/plans/2026-10-20-43b2-shared-timer-phone-receives-plan/` (D-1 target, D-2 adoption, A-2), `docs/plans/2026-10-20-43c-finish-once-plan/` (D-2 duplicate rule for entries, D-3 the wrist does not echo a clear), commit 31523a49 (the grow rule in `needsIntervalFor`).
> Siblings planned in parallel, not this scope: 120, 121a (a watch hold keeps running after the phone logs it: wrist side; it may change what the wrist re-reports, this plan holds whatever it re-reports), 122. Re-validate line numbers before briefing: another session edits the tree.
> Evidence: `2026-11-05-121b-stale-watch-timer-adopted-into-next-interval-plan.evidence.md`; review: `...plan.review.md` (both beside this file, created by the first writer).

## Goal and acceptance

**What the owner sees today (the bug).** You start an interval (or a hold, or a round) on the watch; the phone shows it running. You log it on the phone. The watch still has its own copy of that clock (the clear did not reach it, or the watch keeps showing it). Later the watch reports that old clock again (you pause it on the watch, the phone app restarts, or the watch re-sends its session). The phone then starts the exercise's **next** interval by itself, counting from the old start: a clock you never started, already minutes in, and your rest count-up after the logged interval stops. If you had already started the next interval on the phone, its clock jumps back to the old start.

**After 121b.** A watch clock whose start matches an interval the phone has already logged for that exercise is recognised as that logged interval and ignored: the next interval stays "not started" (or keeps its own clock), the rest keeps counting. A clock the watch genuinely starts for the next interval still starts it on the phone.

**Cause (verified 2026-11-05).** `lib/state/workout/timer_manager.dart`: `TimerManager.needsIntervalFor` (~:319-353) holds the rule "a finished interval with the same start (within `_sameStartToleranceMs`) means the phone already logged this timer", but returns early `if (anyUnfinished) return false;` (~:349), so the rule only runs when EVERY interval is finished. `TimerManager.adoptRemoteTimer` (~:283) then dispatches to `_adoptRemoteTimed` (~:355) / `_adoptRemoteRound` (~:391), which pick the target with `_targetIndex` (~:432: in-progress first, else first not-finished) and never look at finished intervals. A not-started target is written `active`/`paused` with the stale start; an in-progress target is overwritten when the stale start is earlier (`remote.startedAtMs >= old.startedAtMs` is the only refusal, ~:371-374 / ~:407-410); both paths call `closeAllOpenRestsInSessionInMemory()` first (~:376 / ~:413). Covers `elapsed` (timed), `hold` (drill, same `_adoptRemoteTimed`) and `round`.

**How a stale copy gets re-applied.** `WatchTimerAdoption._adoptOnce` (`lib/state/watch/watch_timer_adoption.dart` ~:117-163) skips a frame whose sorted JSON equals `_applied[kind]`; the mirror (`LiveSessionMirrorState`, in memory only) keeps the wrist's last report because the wrist never echoes a clear it received (43c D-3, Swift S-333). The stale copy is re-applied whenever its encoding differs from `_applied`: the wrist pauses or resumes it, the phone graph is rebuilt (app restart: `_applied` empty, the wrist's snapshot re-delivers it), or any field of the frame changes. Consequence today: the zombie interval also defeats 43c D-2 later (the wrist's eventual log of T is a duplicate of the finished interval, so the zombie is never finished).

## Decision Ledger

- **D-1 The logged-timer rule.** In `TimerManager.adoptRemoteTimer`, after the existing kind-pairing check (`timed`↔`elapsed`, `drill`↔`hold`, `round`↔`round`) and before any targeting, rest closing or write: when the named effort currently holds a FINISHED interval (`TimedInstance.state == TimedState.finished` for `timed`/`drill`; `RoundInstance.state == RoundState.finished` for `round`) with `startedAtMs > 0` and `|startedAtMs − remote.startedAtMs| <= TimerManager._sameStartToleranceMs` (inclusive), the remote is that logged interval: return `false`; nothing is written (memory or repository), no rest is closed, `SessionCore.adoptRemoteWorkTimer` neither grows the effort nor bumps `watchRefreshRevision` nor notifies. Applies whatever the other intervals' states are (not-started, active, paused, finished), and whether the remote is running or paused.
- **D-2 One rule, two callers.** `needsIntervalFor` and `adoptRemoteTimer` decide "already logged" through the same predicate, so the grow path and the write path cannot disagree. `needsIntervalFor` keeps its own grow condition (no unfinished interval left) unchanged.
- **D-3 What the rule compares (derived, vetoable).** Only the named effort's own intervals as held now; matching is by start, never by index or id (a delete that re-indexes intervals changes nothing); another effort's finished interval with the same start does not count; a finished interval the user DELETED is not remembered, so a remote whose start matched only the deleted interval adopts as today (43b2 D-1). Why no memory: the phone no longer holds that log, and if the watch still runs that clock, showing it is the shared-timer promise; a memory would need new session-scoped state. Veto before Phase 1 if the owner wants a deleted log to keep blocking.
- **D-4 Unchanged rules (regression-pinned).** 43b2 D-1 target (in-progress, else first not-finished); the earlier start wins (O-3) for an in-progress interval, including one whose own start is within the tolerance of the remote (D-1 looks at finished intervals only); a paused remote adopts paused (S-6104); a stopped remote is ignored (43c D-4); the grow rule (S-6105, S-6117); `WatchTimerAdoption` remembers a refused frame as applied and does not retry it.
- **D-5 Tolerance.** The existing `_sameStartToleranceMs` in `timer_manager.dart` (the 43c A-2 argument: no interval is started, finished and the next started within that window on either device). Not changed; not merged with the importer's own constant (`watch_session_importer.dart` ~:1139, different layer).
- **D-6 Out of scope.** No wire, Swift, push (`watch_timer_push.dart`), importer, screen or model change. What the wrist shows is 121a's.

## Feature Invariants

- A finished interval and the intervals after it are never written by a remote timer whose start is the finished interval's start.
- `MockWorkoutRepository` and `HiveWorkoutRepository` hold identical rows after every scenario (the Mock and Hive groups assert the stored rows, not only memory).
- A refused adoption is invisible: no write, no revision bump, no notification, the session's open rest stays open.

## Requirements and Acceptance Criteria

- AC-1 A stale copy of a logged timer (running or paused, `elapsed`/`hold`/`round`) never starts or rewinds another interval of the same exercise — S-12151, S-12152, S-12154, S-12155, S-12156, S-12157, S-12161, S-12171, S-12172.
- AC-2 The tolerance edge is exact (inclusive, both directions) — S-12153.
- AC-3 Nothing else moves on a refusal: rest open, no resync, redelivery idempotent — S-12158, S-12162, S-12173.
- AC-4 Legitimate adoption is intact: first-unfinished target, earlier start wins, other slot, deleted log, grow — S-12153d/e, S-12154b, S-12155b, S-12159, S-12160, S-12161b, S-12163, S-12164, S-12174, plus existing S-6101..S-6106, S-6111..S-6118, S-9923, S-6321..S-6341.

## Existing-Functionality Impact

| Touched surface | Readers (grep) | Effect | Guarded by |
|---|---|---|---|
| `TimerManager.adoptRemoteTimer` | `grep -rn "adoptRemoteTimer\b" lib` → `session_core_io.dart:289` only | refuses logged starts | D-1, S-12151.. |
| `TimerManager.needsIntervalFor` | `grep -rn "needsIntervalFor" lib test` → `session_core_io.dart:282` only; no direct test | same answers (refactor to shared predicate) | S-6105 (both tests), S-6117 (both), S-12163, S-12164 |
| `WorkoutState.adoptRemoteWorkTimer` | `grep -rln "adoptRemoteWorkTimer" lib test` → `watch_timer_adoption.dart:151`; tests `remote_work_timer_state_test.dart`, `timer_start_closes_session_rests_test.dart` (S-9923/S-9923b: effort B has no finished interval), `widget_test.dart:688` (effort B fresh, no finished interval: unaffected by construction) | none for those fixtures | Done Criteria runs the first two files |
| `S-6113 ... NEW session` in `test/watch_timer_adoption_test.dart` (found at P1) | fixture reuses the effort id and the identical start across two sessions | went red under D-1; fixture made realistic (A-1, resolved by the main session) | A-1 |
| `WatchTimerAdoption` (behaviour via the facade) | `grep -rln "timerAdoption" test` → `watch_timer_adoption_test.dart`, `watch_timer_push_test.dart` (`adoptedInterval()` :457; S-6329 delivers a wrist start 2 ms after a finished interval: refused today too, because no interval is unfinished at that moment and `_applied` blocks the retry after `addEntry`, so unchanged), `watch_timer_adoption_screen_test.dart` | none expected | Done Criteria runs all three |
| Importer duplicate rule (43c D-2) | not touched; `watch_session_importer.dart` keeps its own constant | none | — |
| Docs | `docs/state_management/workout_state.md` (~:237-245 row, 27.8 KB; the row is already stale: it says an effort with no unfinished interval writes nothing, but the grow rule adds one), `docs/watch_session_capture.md` (~:360-380, 36.3 KB); both far under the 52 KB band | rewritten row, one sentence | P2 |

Invariants: layer boundary (state only, no concrete repository); repository parity (Mock + Hive groups); `docs/global_conventions.md` "Timestamps are source data" (the rule compares persisted starts) — PASS by design. No schema, seed or model change.

## UI Standards Impact

None: no screen, widget or copy changes.

## Scenarios

| S-id | Fixture (full text below) | Expect | Fails without the change because |
|---|---|---|---|
| S-12151 | timed [finished S0, notStarted]; remote elapsed S0 | nothing changed | idx1 is started at S0 |
| S-12152 | same; remote paused at S0+30000 | nothing changed | idx1 is written paused at S0 |
| S-12153 | same; remote S0±400, S0+1000, S0+1001, S0+5000 | first three refused, last two adopt idx1 | the first three start idx1 (the last two pass both ways) |
| S-12154 | [notStarted, finished S0, notStarted]; S0 then S0+5000 | S0 refused; S0+5000 starts idx0 | idx0 is started at S0 |
| S-12155 | round [finished S0, notStarted]; S0 then S0+5000 | S0 refused; S0+5000 starts r1 | r1 is started at S0 |
| S-12156 | drill [finished S0, notStarted]; hold S0 | nothing changed | idx1 is started at S0 |
| S-12157 | [finished S0, active P]; S0 | idx1 keeps P | the earlier-start rule rewinds idx1 to S0 |
| S-12158 | S-12151 + open rest after idx0 | rest stays open | the adoption closes the rest |
| S-12159 | [active P]; P-500 | replaced with P-500 | same (pin: passes both ways; guards M6) |
| S-12160 | A [finished S0], B [notStarted]; S0 for B | B starts at S0 | same (pin: guards M9) |
| S-12161 | delete re-indexes / deletes the logged interval | (a) refused, (b) adopts | (a) the not-started interval after the re-indexed log is started at S0 |
| S-12162 | S-12151 twice | both refused | the first call writes |
| S-12163 | round [finished S0]; S0 | no growth | same (pin: grow rule intact) |
| S-12164 | [finished S0]; S0+1001 | grows, idx1 at S0+1001 | same (pin: grow rule intact) |
| S-12171 | graph: wrist pauses its stale copy | [finished, notStarted] | idx1 is written paused at T |
| S-12172 | graph: phone restart + wrist snapshot | [finished, notStarted] | idx1 is started at T |
| S-12173 | graph: redelivery, snapshot, resume | [finished, notStarted] | the first delivery writes |
| S-12174 | graph: wrist starts the next interval for real | idx1 runs on the new start | same (pin: 43b2 D-1 intact) |

Fixture constants (state file): `S0 = DateTime.utc(2026, 11, 5, 9, 0, 0).millisecondsSinceEpoch`; `P = S0 + 180000` (the phone's own next start). "finished at X" = the instance rewritten through the repository as `copyWith(state: finished, startedAtMs: X, finishedAtMs: X + 120000, actualDurationSecs: 120, updatedAtMs: X + 120000)` (rounds: `state: RoundState.finished, startedAtMs: X, finishedAtMs: X + 60000, plannedDurationSecs: 60, actualDurationSecs: 60, completed: true`) then `state.refreshEfforts([effortId])` (the `_startAt` pattern of `test/remote_work_timer_state_test.dart`). Every scenario first asserts its fixture states. "Nothing changed" = `changed == false`, memory list AND `repository.getTimedInstances`/`getRoundInstances` equal to the fixture (state, `startedAtMs`, `pausedAtMs`), `watchRefreshRevision` unchanged, 0 notifications.

### S-12151: stale running copy, next interval not started (the reported bug)
- Fixture: effort `timed` (modality `cardio_endurance`), intervals [idx0 finished at S0, idx1 notStarted (`startedAtMs` 0)].
- Trigger: `adoptRemoteWorkTimer(effort, RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: S0))`.
- Expected outcome: nothing changed; idx1 still notStarted with `startedAtMs` 0; count 2. Fails today: idx1 active at S0.
- Edge case of: none

### S-12152: stale paused copy
- Fixture: as S-12151. Trigger: remote `elapsed` S0, `pausedAtMs: S0 + 30000`, `accumulatedPauseMs: 0`.
- Expected outcome: nothing changed. Fails today: idx1 paused at S0. Edge case of: S-12151

### S-12153: near twins (tolerance edge, one fresh fixture per arm)
- Fixture: as S-12151.
- Trigger / expected: (a) remote S0 + 400 → |400| <= 1000, nothing changed; (b) S0 − 400 → nothing changed; (c) S0 + 1000 → |1000| <= 1000 (inclusive), nothing changed; (d) S0 + 1001 → 1001 > 1000, idx1 active, `startedAtMs` S0 + 1001, `changed` true; (e) S0 + 5000 → idx1 active at S0 + 5000. (a)-(c) fail today; (d), (e) pass today and after.
- Edge case of: S-12151

### S-12154: three intervals, the middle one finished
- Fixture: [idx0 notStarted, idx1 finished at S0, idx2 notStarted] (finish idx1 directly through the repository rewrite).
- Trigger / expected: (a) remote S0 → nothing changed (idx0 and idx2 notStarted). Fails today: idx0 active at S0. (b) remote S0 + 5000 → idx0 active at S0 + 5000, idx2 notStarted (43b2 D-1 first-not-finished intact).
- Edge case of: S-12151

### S-12155: round kind
- Fixture: effort `round` (modality `sports`) with `addRound` to two rounds: [r0 finished at S0, r1 notStarted].
- Trigger / expected: (a) remote `round` S0, `plannedDurationMs: 60000` → nothing changed. Fails today: r1 active. (b) remote S0 + 5000 → r1 active at S0 + 5000, `plannedDurationSecs` 60.
- Edge case of: S-12151

### S-12156: hold kind
- Fixture: effort `drill` (modality `isometric_stretching`) [idx0 finished at S0, idx1 notStarted]. Trigger: remote `hold` S0. Expected: nothing changed. Fails today. Edge case of: S-12151

### S-12157: the phone already started the next interval itself
- Fixture: [idx0 finished at S0, idx1 active at P] (`startTimedEntry(effort, 1)` then rewrite start to P).
- Trigger: remote `elapsed` S0. Expected: nothing changed; idx1 active, `startedAtMs` P. Fails today: idx1 rewound to S0 (earlier start wins).
- Edge case of: S-12151

### S-12158: the rest after the logged interval keeps counting
- Fixture: as S-12151, plus `state.recordRestStart(effort, 1)` (the rest after idx0; assert `restEndMs == null`).
- Trigger: remote `elapsed` S0. Expected: nothing changed; the rest's `restEndMs` still null in memory (`getEntryRests`) and in the repository. Fails today: rest closed.
- Edge case of: S-12151

### S-12159: earlier start wins on an in-progress interval within the tolerance
- Fixture: one interval, idx0 active at P. Trigger: remote `elapsed` P − 500.
- Expected: `changed` true, idx0 active, `startedAtMs` P − 500 (D-4: finished intervals only). Passes today and after.
- Edge case of: none

### S-12160: same start on another slot
- Fixture: two `timed` efforts in one session (add the seeded exercise twice, or seed a second exercise): A [finished at S0], B [notStarted].
- Trigger: remote `elapsed` S0 for B. Expected: B idx0 active at S0; A unchanged. Passes today and after.
- Edge case of: none

### S-12161: deleted / re-indexed interval
- (a) Fixture: [idx0 notStarted, idx1 finished at S0, idx2 notStarted]; `deleteTimedEntry(effort, 0)` → assert [finished at S0, notStarted]. Trigger: remote S0. Expected: nothing changed. Fails today.
- (b) Fixture: [idx0 finished at S0, idx1 notStarted]; `deleteTimedEntry(effort, 0)` → assert [notStarted]. Trigger: remote S0. Expected (D-3): idx0 active at S0. Passes today and after.
- Edge case of: S-12151

### S-12162: redelivery of the same stale timer
- Fixture: as S-12151. Trigger: the S-12151 call twice. Expected: both return false; nothing changed after either. Fails today.
- Edge case of: S-12151

### S-12163: every interval finished, round (no growth)
- Fixture: round effort [r0 finished at S0]. Trigger: remote `round` S0. Expected: count 1, nothing changed. Passes today and after.
- Edge case of: S-12155

### S-12164: growth just outside the tolerance
- Fixture: [idx0 finished at S0]. Trigger: remote `elapsed` S0 + 1001. Expected: count 2, idx1 active at S0 + 1001, `changed` true, revision +1. Passes today and after.
- Edge case of: S-12153

Graph scenarios (`test/watch_timer_adoption_test.dart`, Mock, the file's existing harness: `fixture()` = two notStarted intervals of `sx-run`; `T` = `_wristStart`; `graph.timerPush` NOT bound, so the wrist engine keeps running T, as when the clear never reached it):

### S-12171: the wrist pauses its stale copy
- Fixture: `fixture()`; `wristStartsElapsed(_wristStart)`; deliver; flush → assert idx0 active at T. `phoneState.finishTimedEntry('sx-run', 0)`; `recordRestStart('sx-run', 1)`.
- Trigger: `engine.pauseTimer(kind: WatchTimerKind.elapsed)`; `deliver(lastTimerFrame())`; `graph.timerAdoption.flush()`.
- Expected: states [finished, notStarted], idx1 `startedAtMs` 0, `phoneState.inProgressWorkTimers()` empty, the rest open, `failures` empty. Fails today: idx1 paused at T.
- Edge case of: S-12151

### S-12172: the phone app restarts while the wrist still runs T
- Fixture: as S-12171 up to the finish. `graph.timerAdoption.dispose()`; `graph = await startGraph()`.
- Trigger: `deliver(snapshot())` (the wrist's snapshot carries its running T); flush the new graph's adoption.
- Expected: states [finished, notStarted], idx1 `startedAtMs` 0. Fails today.
- Edge case of: S-12151

### S-12173: redelivery and resume of the stale copy
- Fixture: S-12171 after its trigger. Trigger: deliver the same paused frame again; deliver `snapshot(revision: 9)`; `engine.resumeTimer(kind: WatchTimerKind.elapsed)` and deliver its frame; flush after each.
- Expected: [finished, notStarted] throughout. Fails today (the first delivery already wrote).
- Edge case of: S-12171

### S-12174: the wrist genuinely starts the next interval
- Fixture: as S-12171 up to the finish (no pause). Trigger: `wristStartsElapsed(_now.subtract(const Duration(seconds: 5)))` (35 s after T); deliver; flush.
- Expected: idx1 active, `startedAtMs` = that start. Passes today and after.
- Edge case of: none

## Phases (Iteration 1)

### Phase 0: red tests first (@crew-builder-app)
1. [ ] Create the state test, Mock and Hive groups, plain `test()`, harness copied from `test/remote_work_timer_state_test.dart` (`_PathProviderChannel`, `_openMock`/`_openHive`/`_closeHive`, `_seed`, `_session`, `_startAt`) plus finish-at helpers for timed and round — `test/stale_watch_timer_adoption_test.dart` · header comment mapping S-12151..S-12164
2. [ ] Write S-12151..S-12164 exactly as fixtured above, asserting memory AND stored rows — same file
3. [ ] Add group `S-1217x a stale wrist copy of a logged timer` with S-12171..S-12174; add them to the header's scenario mapping — `test/watch_timer_adoption_test.dart`
4. [ ] Run both and record the red/green table in the evidence file. Expected RED (today's code): S-12151, S-12152, S-12153a-c, S-12154a, S-12155a, S-12156, S-12157, S-12158, S-12161a, S-12162, S-12171, S-12172, S-12173. Expected GREEN: S-12153d/e, S-12154b, S-12155b, S-12159, S-12160, S-12161b, S-12163, S-12164, S-12174. Any mismatch: fix the fixture (not the expectation) or log it in the Assumption Log and stop.
5. [ ] Record the `flutter analyze` issue count baseline in the evidence file.

**Done Criteria** (observed, counts pasted into evidence): `flutter test test/stale_watch_timer_adoption_test.dart` → exactly the expected red set fails, in both groups; `flutter test test/watch_timer_adoption_test.dart --plain-name "S-1217"` → S-12171..S-12173 fail, S-12174 passes; `flutter analyze` count recorded. If the Hive group hangs behind a red Mock group, run `--plain-name "Mock"` and `--plain-name "Hive"` separately (AGENTS.md known hang).
**Predicted Files**: `test/stale_watch_timer_adoption_test.dart` (new), `test/watch_timer_adoption_test.dart`, this plan's Progress, the evidence file.

### Phase 1: the logged-timer rule (@crew-builder-app)
1. [ ] Add one private predicate: the effort holds a finished interval of its kind with `startedAtMs > 0` within `_sameStartToleranceMs` (inclusive) of `remote.startedAtMs` — `lib/state/workout/timer_manager.dart` · near `needsIntervalFor`
2. [ ] `adoptRemoteTimer`: after the pairing check and before `_adoptRemoteRound`/`_adoptRemoteTimed`, return `false` when the predicate holds (D-1); update its doc comment — same file · `TimerManager.adoptRemoteTimer`
3. [ ] `needsIntervalFor`: replace its inline `finishedStarts` match with the predicate; keep `if (anyUnfinished) return false;` for growth (D-2); update its doc comment — same file · `TimerManager.needsIntervalFor`
4. [ ] Run Done Criteria; record red→green table in evidence.

**Done Criteria**: `flutter test test/stale_watch_timer_adoption_test.dart` all green (both groups); `flutter test test/remote_work_timer_state_test.dart test/timer_start_closes_session_rests_test.dart test/watch_timer_adoption_test.dart test/watch_timer_push_test.dart` all green; `flutter test test/watch_timer_adoption_screen_test.dart` green; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` green; `flutter analyze` count not above the P0 baseline; `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty. Never the full suite.
**Predicted Files**: `lib/state/workout/timer_manager.dart` only (about 25 production lines), plan Progress, evidence.

### Phase 2: docs (@crew-docs-keeper)
1. [ ] Rewrite the `adoptRemoteWorkTimer` rule row: the logged-timer rule (D-1, naming `_sameStartToleranceMs`, never its value), the grow rule (a remote with no unfinished interval left adds one, unless already logged), and the verifying tests (`S-12151`..`S-12164`, `S-6105`); the row must no longer contain the Docs delta Old marker and must contain the New marker "a start the phone already logged" on one line — `docs/state_management/workout_state.md` · ~:245
2. [ ] Add one sentence to the adoption paragraph, containing on one line the New marker "matches an interval the phone already logged" (a wrist timer whose start matches an interval the phone already logged is ignored), with `test/watch_timer_adoption_test.dart` `S-12171`..`S-12174` — `docs/watch_session_capture.md` · ~:366-380

**Done Criteria**: `flutter test test/docs_indexing_contract_test.dart` green; both files under 52 KB (state current sizes in evidence).
**Predicted Files**: the two docs above, plan Progress, evidence.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/workout_state.md` | MODIFIED | an effort with no unfinished interval or a wrong pairing writes nothing | a start the phone already logged | S-12151, S-12163, S-12164 |
| `docs/watch_session_capture.md` | ADDED | - | matches an interval the phone already logged | S-12171 |

## Verification (owners)

- **Implementer** — Done Criteria with pasted counts; P0 red observed before P1 exists.
- **crew-prover (mutations, after P1)** — each must turn a named test red; restore after each: M1 drop the D-1 check for the timed path → S-12151; M2 for the round path → S-12155a; M3 `<=` to `<` → S-12153c; M4 tolerance raised to 10000 → S-12153e; M5 check only intervals before the target index → S-12154a; M6 match any state, not only finished → S-12159; M7 one-sided difference (no `abs`) → S-12153b; M8 check placed after the rest closing → S-12158; M9 compare across all session efforts → S-12160; M10 return `true` on refusal → S-12151 (revision); M11 `needsIntervalFor` stops using the predicate (always false on match removed) → S-6105 "ignored", S-12163. Equivalent by construction (name, do not test): the `startedAtMs > 0` arm (a remote start is a wall-clock epoch, never within the tolerance of 0).
- **crew-reviewer** — diff vs Predicted Files; Impact table greps re-run; Mock/Hive parity of stored rows; Assumption Log adjudication.
- **Governor** — full suite once, `flutter analyze` count.

## Owner device checks (owner)

- (owner) Cardio exercise with two intervals. Start interval 1 on the watch; the phone shows it running. Put the watch in aeroplane mode, log interval 1 on the phone, then pause the watch's clock and turn aeroplane mode off: on the phone, interval 2 stays "not started" and the rest after interval 1 keeps counting.
- (owner) The same, but instead of pausing, force-quit and reopen the phone app: interval 2 still "not started".
- (owner) The same, then start interval 2 on the watch: the phone shows interval 2 running from the watch's new start.
- (owner) Log interval 1 on the phone and start interval 2 on the phone; then the watch's old clock is paused: the phone's interval 2 keeps its own time.
- (owner) Repeat the first check with a hold (stretching) and a round (sports).

## Questions

None. D-3 (a deleted logged interval is not remembered) is derived and vetoable before Phase 1.

## Files Affected

`lib/state/workout/timer_manager.dart`; `test/stale_watch_timer_adoption_test.dart` (new); `test/watch_timer_adoption_test.dart`; `docs/state_management/workout_state.md`; `docs/watch_session_capture.md`. Read-only dependents (must stay green): `lib/state/workout/session_core_io.dart`, `lib/state/watch/watch_timer_adoption.dart`, `test/remote_work_timer_state_test.dart`, `test/timer_start_closes_session_rests_test.dart`, `test/watch_timer_push_test.dart`, `test/watch_timer_adoption_screen_test.dart`, `test/widget_test.dart` (fresh effort, unaffected by construction).

## Notes

- Order: P0 → P1 → P2, serial. P2 could run beside P1 (disjoint files) but would document unproven behaviour; keep it serial.
- Intermediate state after P0: the new tests are red by design; do not commit P0 alone.
- Possible overlap: 121a may edit `test/watch_timer_adoption_test.dart` or `test/watch_timer_push_test.dart`; re-read before editing and keep this plan's group self-contained.
- Size: about 25 production lines, about 450 test lines, 3 phases, one track (phone). Within budget.
- Known limit (accepted, same as 43c D-2): an interval logged by typing a duration gets a computed start; a real watch start that happens to land within the tolerance of it would be ignored. Needs two coincidences inside one second.

## Noticed, not planned

- A wrist pause or resume of a timer the phone already adopted never reaches the phone: the same start hits `remote.startedAtMs >= old.startedAtMs` → no write (`timer_manager.dart` ~:371-374). Owner rule O-2 ("pause pauses both") may expect it; worth its own plan.
- `docs/state_management/workout_state.md` and `docs/watch_session_capture.md` never documented the grow rule of commit 31523a49 (P2 fixes the row it touches).
- The importer and `TimerManager` each define their own `_sameStartToleranceMs` (duplicate constant across layers).

## Progress

- [x] P0 red tests (observed 2026-11-05: state file +18 -24 = exactly the 12 expected scenarios in Mock and Hive; graph file +20 -3 = S-12171..S-12173; `flutter analyze` baseline 184 issues on the shared tree)
- [x] P1 logged-timer rule (A-1 resolved): code in place (`timer_manager.dart`, as briefed). New file +42 all green; remote_work_timer_state +36, timer_start_closes_session_rests +12, watch_timer_push +61, watch_timer_adoption_screen +6 ~1 green. (was stopped: existing `S-6113 the same timer for a NEW session is applied again` in `test/watch_timer_adoption_test.dart` went red (see Assumption Log A-1). resolved by main session, see A-1.)
- [x] P2 docs (applied by the lead; plan-lint after clean; docs contract tests +54)
- [x] Mutations: M1-M11 (M7 in two one-sided variants) all killed, in an isolated copy, original restored byte-identical
- [x] Review (crew-reviewer): APPROVE, 4 minors fixed (comment, progress, evidence file); A-1 ratified

## Assumption Log

- A-1 (2026-11-05, found at P1) The plan's Impact table missed `S-6113 ... NEW session` (`test/watch_timer_adoption_test.dart` ~:630-690). Interval rows have no session id and pile up under the effort id (= the wrist slot id) across sessions. That test ends session 1 with an interval finished at T, opens session 2 with the same slot and the wrist then reports the IDENTICAL start T: D-1 reads the old session's finished row as "the phone already logged it" and refuses, so the new session's interval stays notStarted. In real use a new session cannot start at the old session's instant (the fixture is artificial: it reuses the start to prove the adoption memo is per session). Options: (A) change that test so the second session's wrist start differs from the first by more than the tolerance (its memo purpose then needs another way to be shown), (B) scope the rule to the current session's rows (no session link on the instance; model/schema change, out of scope), (C) accept and rewrite the test to keep an identical encoding by moving the old row's start after it is ended. RESOLVED by the main session (technical call): keep the rule; production gives every session its own effort ids, so the fixture is artificial. Option (1) applied: S-6113 `NEW session` now deletes session 1's interval rows through the repository (`deleteTimedInstancesForEffort`) and refreshes the effort when session 1 ends, keeping the identical wrist start; its fixture/final expectations became `[notStarted, notStarted]` -> `[active, notStarted]`. No model or schema change; no other existing test touched. Observed: `watch_timer_adoption_test.dart` +23 all green.

## Feedback

[empty]
