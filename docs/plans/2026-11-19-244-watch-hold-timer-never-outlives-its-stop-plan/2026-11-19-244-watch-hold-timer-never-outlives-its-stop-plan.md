# Plan 244 — A hold the phone started counting because the watch started it never keeps counting after the watch stops it

Owner report, 2026-11-18 (a holds routine on the watch, the phone backgrounded): after the owner logged holds on the watch, opening the phone showed a hold running on the fourth exercise for about five minutes. Nothing on the watch was running. The owner logged it on the phone, which synced a 5-minute hold back to the watch, and had to delete it.

The phone's diagnostics log of that workout (23:28-00:02 UTC, 2026-11-18) shows every hold Start on the watch followed by a Log frame, so the watch did its part; the log records frames, not which exercise a timer or entry belonged to, so the exact trigger is not proven. The mechanism that lets any such hold live on is certain from the code: the phone takes a running timer from the wire into an interval of the exercise the wire names, and it treats the wrist's STOP as nothing (`watch_timer_adoption.dart`, rule 2 "A stop is not applied (A-2)"), relying on the wrist's logged entry to fill and finish that same interval (`watch_session_importer.dart:_unfinishedInstanceToFill`, per exercise). If the entry lands on another exercise, arrives for a different interval, or a later phone write puts the interval back (the adoption writes a copy it read before the importer replaced the interval), nothing ever stops the interval, and the wire (one timer per kind) can no longer name it.

Phone only. No wire change, no watch change.

## Goal and acceptance

After this change the phone gives an interval back as soon as the wire stops naming the timer that took it: when the watch's timer of that kind is stopped, gone, or replaced by another exercise's timer, the phone interval that was taken from it and is STILL running or paused returns to "not started" (no start time, no pause time). A finished interval is never touched. When the entry arrives later it fills the first unfinished interval, which is that interval again, so the normal flow is unchanged.

The phone's diagnostics log also says what happened: `timer_adopted` (a watch timer started a phone interval), `timer_released` (the phone gave one back, and whether something was still running), and `entry_placed` (where a watch interval entry landed: filled, appended, already logged, retry).

Acceptance: S-24401..S-24408 and S-24411..S-24418 green, the ones marked "fails without" red at the base commit or killed by the lead's mutation; the existing adoption tests (`watch_timer_adoption_test`, `stale_watch_timer_adoption_test`, `wrist_pause_resume_adoption_test`, `watch_timer_adoption_screen_test`; 130 green before the edit) stay green; `flutter analyze` at baseline, 0 errors; full suite no new red; Docs delta applied.

## What the user sees

- A hold or interval the watch started never keeps running on the phone after the watch stopped it, whatever happened to its entry: the phone shows it as not started again instead of a timer counting for minutes.
- Normal logging looks the same: start on the watch, log on the watch, the phone shows one finished hold with the watch's numbers and no extra interval.
- The Diagnostics copy now carries three more line kinds for a watch workout, so the next report can say which exercise a timer and an entry belonged to.
- To SEE it (phone side): start a session on the watch with a hold exercise, tap Start on the watch so the phone shows the hold running, then tap Log on the watch: one finished hold. For the stale case there is no way to make it happen by hand; it is covered by tests and the owner check below.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-24401 | `TimerManager.releaseRemoteTimer(effortId, effortKind, startedAtMs)` (forwarded by `SessionCore.releaseRemoteWorkTimer(effortId, startedAtMs)` and `WorkoutState.releaseRemoteWorkTimer`): every active or paused interval (timed/drill: `TimedInstance`; round: `RoundInstance`) of the effort whose `startedAtMs` is within 1000 ms of `startedAtMs` (inclusive, the same tolerance as the adoption) is replaced by a copy with `state: notStarted`, `startedAtMs: 0`, `pausedAtMs: null`, `totalPausedDurationMs: 0`, `updatedAtMs: now` and persisted with `updateTimedInstance`/`updateRoundInstance`. A finished interval, an unstarted one, a start outside the tolerance, another effort: untouched. Returns whether anything changed; the core bumps `watchRefreshRevision` and notifies once when it did. | `timer_manager.dart:releaseRemoteTimer`, `session_core_io.dart:releaseRemoteWorkTimer` |
| D-24402 | `WatchTimerAdoption` keeps `_adopted[kind] = (slot, startedAtMs)` for the timer each wire kind last gave an interval to (set only when `adoptRemoteWorkTimer` returned true; cleared when the phone's session changes). At the start of each kind's turn in `_adoptOnce`, if `_adopted[kind]` exists and the wire's timer of that kind does not name the same exercise (not running, or another slot), the entry is removed and `WorkoutState.releaseRemoteWorkTimer(slot, startedAtMs)` runs; only then is the wire's running timer (if any) adopted. The same exercise keeps the claim whatever the start (a pause, a resume, or a later start): a later start of the same exercise is the wrist's next interval, which the adoption's earlier-start rule refuses while the old interval runs, and the phone finishing the old interval must not stop the new clock (`test/watch_timer_push_test.dart` S-6323). The first version of this rule also released on a later start; S-6323 failed in the lead's first full run and the rule was narrowed. | `watch_timer_adoption.dart:_adoptOnce`, `_releaseWhatTheWristLeft` |
| D-24403 | Diagnostics (observation only, never read back): `WatchTimerAdoption` takes an optional `DiagnosticsLog` (passed by `createWatchSync`). `timer_adopted` detail `kind=<wire kind> slot=<slot id> start=<UTC>`; `timer_released` detail `kind=… slot=… start=<UTC> reason=stopped\|replaced reset=<true\|false>`; the importer (`_Pass._noteIntervalPlaced`) notes `entry_placed` for every timed, hold or round wire entry: `kind=<wire kind> effort=<effort id> index=<n> how=filled\|appended\|already_logged\|retry` plus ` start=<UTC>` when the entry carries one. No names or numbers. | `watch_timer_adoption.dart`, `watch_session_importer.dart:_noteIntervalPlaced` |
| D-24404 | Unchanged on purpose: the importer's fill rule (the entry fills the first unfinished interval of ITS exercise), the adoption's earlier-start-wins and logged-interval rules, the phone's own user-started intervals (never recorded in `_adopted`, so never given back), the open exercise screen (see Open items 1). A reset interval has lost its previous target length: the adoption had already set `targetDurationSecs: 0` when it took the interval. | review |
| D-24405 | Owner behaviour decision (2026-11-19, "yes, let's do it"): a stopped hold nobody logged leaves an UNSTARTED interval on the phone, not a finished one, because the stop alone does not say the hold was logged. | owner chat |

## Scenarios

Fixtures. Level A (state level, Mock and Hive groups, template `test/stale_watch_timer_adoption_test.dart`: `_adoptionTests(open:, close:)`, `seedExercise`, `WorkoutState`, `RemoteWorkTimer`): a timed effort `ex-run` with three unstarted intervals unless stated; S0 = `DateTime.utc(2026, 11, 5, 9, 0, 0)` ms. Level B (the full phone graph over a fake radio with a real wrist engine, Mock only, template `test/watch_timer_adoption_test.dart`: `_PhoneRadio`, `createWatchSync`, `fixture()`, `wristStartsElapsed`, `lastTimerFrame`, `_settle`).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24401 | A: `adoptRemoteWorkTimer(effort, RemoteWorkTimer(wireKind: 'elapsed', startedAtMs: S0))` so interval 0 is active; then `releaseRemoteWorkTimer(effort, S0)`. | returns true; interval 0 is `notStarted` with `startedAtMs == 0`, `pausedAtMs == null`; the stored row (read from the repository) is the same; intervals 1-2 unchanged; listeners notified once; `watchRefreshRevision` +1. | the method does not exist |
| S-24402 | A: as S-24401 but the interval is paused (adopt with `pausedAtMs`, `accumulatedPauseMs: 5000`), then release. | `notStarted`, `startedAtMs 0`, `pausedAtMs null`, `totalPausedDurationMs 0`. | same |
| S-24403 | A: interval 0 finished (logged on the phone: `startTimedEntry` then `finishTimedEntry`), release with its start. | returns false; the interval is still finished with its numbers; no notification. | passes both ways on purpose (mutation: the finished check removed) |
| S-24404 | A, tolerance both arms: interval active at S0; release with `S0 + 1000` changes it; a fresh fixture released with `S0 + 1001` changes nothing (still active). | true / false as stated. | passes both ways on purpose (mutations: `<=` to `<`; tolerance dropped) |
| S-24405 | A: a round effort (`effortKind round`, a round active at S0), `wireKind: 'round'`; release. | the round is `notStarted`, `startedAtMs 0`, stored. | same as S-24401 |
| S-24406 | A: two efforts with active intervals of the same start; release for effort 1 only. | effort 2's interval stays active. | passes both ways on purpose (mutation: the effort check dropped) |
| S-24407 | A: an unknown effort id. | returns false, nothing thrown, no notification. | passes both ways on purpose |
| S-24408 | A: two intervals of one effort active at S0 and at S0 + 60 s (the phone started the second itself); release with S0. | only the first is reset; the second stays active. | passes both ways on purpose (mutation: the start match removed) |
| S-24411 | B (the repro): `fixture()` (two unstarted intervals); the wrist starts an `elapsed` timer on the slot, the frame reaches the phone: interval 0 is active. The wrist stops the timer (`engine.stopTimer(kind: elapsed)`), the frame reaches the phone and the pass settles. NO entry frame. | intervals `[notStarted, notStarted]`; interval 0 `startedAtMs == 0`. | the base never applies a stop: interval 0 stays active |
| S-24412 | B: two timed slots in the ladder. The wrist starts an `elapsed` timer for slot A (A's interval 0 active), then, without stopping it, starts another for slot B (`engine.startTimer` replaces the wire's one `elapsed` timer; its frame names B). | A's interval 0 is `notStarted`; B's interval 0 is `active` with the new start. | the base leaves A's interval running forever (the wire can no longer name it) |
| S-24413 | B: the normal flow. Start, the phone adopts (active); the wrist's entry (`observations_up`, the helper of the 43c fill tests) arrives and fills it; THEN the stop frame arrives. | intervals `[finished, notStarted]` with the entry's total; two intervals only; the stop frame changed nothing. | passes both ways on purpose (mutation: release also deletes or resets finished intervals) |
| S-24414 | B: the stop frame arrives BEFORE the entry (the order the radio can deliver): start, adopt (active), stop frame (released: `[notStarted, notStarted]`), THEN the entry arrives. | the entry fills the first unfinished interval: `[finished, notStarted]` with the entry's total, still two intervals, none appended. | passes both ways on purpose (mutation: the release deletes the interval, which would make the entry append a third) |
| S-24415 | B: pause and resume of the same interval (the wrist pauses the timer: same slot, same start, `pausedAt` set; then resumes). | after the pause `[paused, notStarted]`; after the resume `[active, notStarted]`; never `notStarted`. | passes both ways on purpose (mutation: the same-interval check compares `pausedAt` too) |
| S-24416 | B: the phone started interval 0 itself earlier (its start is earlier than the wire timer's, so the adoption refuses the wire timer: the earlier start wins, S-6115); the wrist's timer is then stopped. | the phone's own interval 0 stays active (never given back). | passes both ways on purpose (mutation: `_adopted` set even when the adoption wrote nothing) |
| S-24417 | B: a round slot: the wrist starts a `round` timer (the round active), then stops it with no entry. | the round is `notStarted`. | the base leaves the round running |
| S-24418 | B with a `DiagnosticsLog` (the in-memory storage of `test/diagnostics_log_test.dart`) passed to `createWatchSync`: the S-24411 flow, plus an entry for a second interval. | the log has `timer_adopted ... kind=elapsed slot=sx-run start=<UTC>`, then `timer_released ... reason=stopped reset=true`, and an `entry_placed ... how=filled` (or `appended`) line for the entry; no line contains a name or number. | the base writes none of these kinds |

### Fix round 1 scenarios (tests-only, closing six mutants; S-24421 rewritten after the S-6323 regression)

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24409a/b | A, round effort: release with `_s0 + 1000` / `_s0 + 1001`. | true and reset / false and still active. | passes both ways on purpose (mutation: round tolerance `>=`) |
| S-24419 | B with diagnostics: S-24416's flow (the phone's own earlier interval, the wire timer refused, then stopped). | the phone's interval stays active; no `timer_adopted`, no `timer_released` event. | passes both ways on purpose (mutation: bookkeeping even when nothing was written) |
| S-24420 | B: the same timer frame renamed to a second slot with the SAME start. | slot A's interval given back, slot B's active on that start. | passes both ways on purpose (mutation: the slot arm dropped) |
| S-24421a/b | B: a frame for the same slot with the start +1000 ms (a) or +60 s (b). | the held interval stays active on its start and nothing is taken (S-6323's premise). | S-24421b fails if a later start of the same slot is treated as the end of the claim (the first version of D-24402) |
| S-24422 | B with diagnostics: the wrist moves to a new session while an adopted timer is held. | no `timer_released` after the new session is adopted; its intervals are not started. | passes both ways on purpose (mutation: the memory kept across sessions) |
| S-24423a/b/c | B with diagnostics: `entry_placed` after a fill, after an append (no unfinished interval left), after an already logged interval. | `how=filled`, `how=appended`, `how=already_logged` with `kind=timed`. | passes both ways on purpose (mutation: labels swapped) |

## Input-reality checklist

1. Writers and units: the wire's `startedAt` is ISO UTC at millisecond precision; the instance stores epoch ms; the tolerance is 1000 ms both ways, as the adoption and the importer already use. The release is written only by `WatchTimerAdoption`.
2. Lifecycle: `_adopted` is per phone session (cleared when the session changes) and in memory only, so after an app restart the first pass re-adopts the wire's running timer through the old rules and a timer adopted before the restart is not released later (known limit, Open items 2). A session that ended: `_adoptOnce` already returns when the phone holds no active session.
3. Settings changing while open: none.
4. Time: all comparisons are on instants; a clock skew between watch and phone moves both stamps by the same amount because the phone's interval carries the wire's start, not its own clock.
5. Load cost: one map lookup per wire kind per pass; one repository write per released interval.
6. Wording: none on screen. Diagnostics detail strings are fixed words and UTC instants.
7. Slot competition: the importer's fill picks the first unfinished interval of its exercise; a released interval is unfinished again, so a later entry fills it (S-24414). The phone's own user-started interval is never in `_adopted` (S-24416, S-24408). Concurrency: `_adoptOnce` passes are serialised by `flush()`; the release runs inside a pass, before the adoption of the same kind. The importer and the adoption can still interleave across awaits (the resurrect race in the intro); the release is what closes that case when the stop frame arrives after it.

## Phases

1. **P1 lead (done before the builders)**: production edits D-24401..D-24403 (`timer_manager.dart`, `session_core_io.dart`, `workout_state.dart`, `watch_timer_adoption.dart`, `watch_sync_wiring.dart`, `watch_session_importer.dart`).
2. **P2a builder-app**, scope `test/workout_release_remote_timer_test.dart` (new): S-24401..S-24408, Mock and Hive groups. No full suite.
3. **P2b builder-app**, scope `test/watch_timer_release_test.dart` (new): S-24411..S-24418, Mock. Parallel with P2a (disjoint scopes; neither runs the full suite). No full suite.
4. **P3 lead**: mutation pass, `crew-docs-keeper` (Docs delta), full suite once, `flutter analyze`, reviewer if the lead finds anything unexplained.

## Readers

Readers of the changed symbols (the lead ran the first four before seeding): `test/watch_timer_adoption_test.dart`, `test/stale_watch_timer_adoption_test.dart`, `test/wrist_pause_resume_adoption_test.dart`, `test/watch_timer_adoption_screen_test.dart` (130 green after the production edit). Readers of the importer placement and of the diagnostics vocabulary the builders run: `test/watch_session_import_test.dart`, `test/watch_timed_fill_test.dart`, `test/watch_session_adoption_bridge_test.dart`, `test/diagnostics_wiring_source_test.dart`, `test/diagnostics_log_test.dart`. Constructors of `WatchTimerAdoption`: `watch_sync_wiring.dart` and `test/watch_timer_adoption_screen_test.dart:135` (the new `diagnostics:` parameter is optional).

## Mutation list (lead)

(a) the `_adopted` bookkeeping removed (S-24411, S-24412, S-24417); (b) `_adopted` set even when `adoptRemoteWorkTimer` returned false (S-24416); (c) the same-exercise check without the slot (S-24412, S-24420); (d) any frame ends the claim, the first version of the rule (S-24415, S-24421b, and the existing S-6323); (e) release on `paused` frames too (S-24415); (f) release without the active/paused check, finished intervals reset (S-24413, S-24403); (g) release deletes instead of resetting (S-24414); (h) release matches by effort only, not by start (S-24408); (i) the effort check dropped (S-24406); (j) `_adopted` not cleared on a session change; (k) the diagnostics notes removed (S-24418); (l) the release after the adoption instead of before it (S-24412).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/watch_session_capture.md` | MODIFIED | a wrist stop is not applied — the wrist's logged entry fills and finishes the | a wrist stop gives back a phone interval the wire took and nobody finished, and the wrist's logged entry fills and finishes the | S-24411, S-24413 |
| `docs/state_management/workout_state.md` | ADDED | - | `releaseRemoteWorkTimer(effortId, startedAtMs)` | S-24401, S-24403 |
| `docs/state_management/watch_diagnostics.md` | MODIFIED | Six kinds record what the phone decided about a watch session | Nine kinds record what the phone decided about a watch session | S-24418 |
| `docs/state_management/watch_diagnostics.md` | MODIFIED | while the other five are recorded every time they happen | while the other eight are recorded every time they happen | S-24418 |
| `docs/state_management/watch_diagnostics.md` | ADDED | - | `timer_released`, the phone giving back an interval | S-24418 |

The keeper also adds, in the same paragraph, one sentence each for `timer_adopted` and `entry_placed` (their detail shapes are in D-24403) and cites S-24418. Stale-term sweep (`grep -rIn "stop is not applied\|A stop is not applied\|Six kinds" docs` outside plans/history/releases) hits `watch_session_capture.md:458` and `watch_diagnostics.md` only.

## Open items

1. (owner) An exercise screen that is OPEN on the phone while a release happens keeps showing the interval as running until it is reopened or refreshed: the screen sets its own running flag before it persists a user start, so it cannot treat "not started" as a stale ticker without breaking user starts. Not made here. The owner's case (phone backgrounded, screen reopened on resume) reads the stored state and shows the interval as not started.
2. A timer adopted before an app restart is not released afterwards (`_adopted` is in memory). Not made here; the first pass after a restart treats the wire's running timer under the old rules.
3. (owner) Device check, QA: on a real watch and phone, in a holds routine, tap Start on the watch and, before logging, tap Next/other exercise changes are not possible (the pager locks), so the check is: log three holds in a row on the watch with the phone in the background, open the phone: each exercise shows only its finished holds and nothing is running. Then Settings > Diagnostics > Copy: lines `timer_adopted`, `timer_released` (when something was given back) and `entry_placed` appear for the session.
4. The exact trigger of the owner's stale hold is not proven (the log records no exercise per frame). If it happens again the new lines say whether a Log landed on another exercise (`entry_placed ... effort=<another>`) or an interval was reset by a stop (`timer_released ... reset=true`).

## Predicted files

`timer_manager.dart` (+70, done), `session_core_io.dart` (+25, done), `workout_state.dart` (+8, done), `watch_timer_adoption.dart` (+75, done), `watch_sync_wiring.dart` (+1, done), `watch_session_importer.dart` (+30, done), two new test files (~350 and ~450), three docs.

## Progress

- [x] Seeded
- [x] P1 production edits (lead); existing adoption tests green (130)
- [x] P2a tests (state level): +18 (Mock and Hive)
- [x] P2b tests (full graph): +8, then fix round 1 +14 (six mutants closed)
- [x] P3 mutation pass (27 of 27 killed after one fix round), docs (lead-written), full suite 8111 passed 0 failed; S-6323 regression found and fixed (see Assumption Log)
- [ ] (owner) device checks, Open items 1 and 3

## Assumption Log

- 2026-11-19: base commit in `.work/2026-11-19-244/base.txt` (b94a549a). The branch is `claude_develop`; another session's uncommitted files (decimal comma, plan 208 fuel burned: `fuel_summary.dart`, `stats_progress_service.dart`, `fuel_section.dart`, manifests) are outside this plan and are never staged or edited here.
- 2026-11-19: ids S-244xx: none found.
- 2026-11-19: the lead's first full `flutter test` found `test/watch_timer_push_test.dart` S-6323 red (green on the base commit, checked in an isolated copy with the six production files from `HEAD`): the first rule also gave back an interval when the wire showed a LATER start for the same slot, the adopt then took the new start into the freed interval and the phone's finish of the old one cleared the wrist's new clock. The rule was narrowed to "a stop, or another exercise's timer" (production edit and S-24421b by the lead, 231 timer tests green, mutation pass re-run: 13 of 13 adoption mutants killed). Lesson for the crew: run the readers of the shared stores before the build, not only after (the readers list named four adoption files and missed the push test that pins the same stale-copy premise).
- 2026-11-19: the diagnostics log of 2026-11-18 was read by the lead: 10 Start/Log pairs, 8 exercise changes; it does not show slots, so the trigger stays unproven (Open items 4).

## Feedback

(none yet)
