# Code review 1 (17b)

Range reviewed: `git diff a45dd49..HEAD` (plan commit → HEAD); pipeline files under `.claude/` and
`.github/` ignored per the brief.

Layers in scope: `lib/state/watch`, `lib/state/workout`, `lib/app.dart`, `lib/main.dart`,
`lib/watch/session`, `watch/watchos/Sources/WatchSessionEngine`, `watch/watchos/Tests`,
`watch/sync_protocol/PROTOCOL.md`, `docs/`, `ios/OmniTrain Watch App/ContentView.swift`.
Layers skipped: `lib/data/**` (no changes), `lib/features/**` (no changes), `lib/widgets/**` (no changes).

Findings were appended as they were found.

Reviewed from: the plan (D-90…D-103, AC-1…AC-11, S-100…S-115, Predicted Files, Impact table, A-1…A-23),
`<plan>.evidence.md` (per-phase counts, red-first records, mutation tables) and the diff read one file at
a time through the gateway. Every doc-cited test name was resolved by grep; every count below was
produced in this run.

## Verdict

One blocking item: a new sentence in `docs/watch_session_sync.md` asserts behaviour the code does not
have (F2). Everything else the brief asks about is sound: both device-side guards hold, every guard is
red at its base or proven by a named mutation, and the suites are green.

## Findings

F1 | minor | plan:223 | The Phase-1 "Red without the change because" note for the Dart engine S-104 is
false — that test passes at the base commit (it asserts silence), as `.evidence.md:23` and A-13 record
and as my `prove-red` run confirms at `e88a491` | Reword to "passes vacuously at the base; red only under
mutation (e′)/(b)" | @planner.

F2 | major | docs/watch_session_sync.md:181-182 | "it re-sends what the phone has not acknowledged and
asks for the phone's state" is untrue of the case the sentence sits in: `WatchSyncOrchestrator.catchUp`
runs `sync` only while the wrist holds a session, and `sync` then sends the wrist's own snapshot
(`answerSnapshotRequest`) — `requestSnapshot()` is the *no-session* branch, which the gate excludes
| Delete the clause (the wrist sends its own state and asks only when it holds none), keeping the pointer
to `WatchConnectivityBridgeTests.testS107…`/`testS108…` | @developer.

F3 | minor | lib/state/watch/watch_session_adoption_bridge.dart:444-446 | AC-5 ("a stale wrist snapshot
cannot re-add a slot the phone removed") holds only while the phone holds that session continuously: the
ever-seen set is dropped as soon as the phone holds another session, and it is memory-only, so a
switch-away-and-return or an app relaunch re-opens the resurrection window. The plan discloses the 250 ms
window (plan:54) but not this one (plan:288 designs the clearing) | State the boundary in the plan/AC-5,
or plan the durable slot ledger as a follow-up — not this PR | @planner.

F4 | minor | lib/state/workout/session_core_entry.dart:77 | A failed `appendSessionSlots` write is
swallowed into the state's error channel and never reaches the graph's `onFailure`, unlike the adoption
write, which reports and rethrows; the slot is marked ever-seen before the write, so a failed append is
not retried in this run | Route the failure to the hook, or say in the doc comment that the write failure
is a UI-level error | @developer.

F5 | minor | watch/watchos/Sources/WatchSessionEngine/WatchEmitForwarder.swift (`bounded`) | Each frame
starts a sleeper `Task` that is never cancelled when the send wins — one suspended task per frame for the
process lifetime; no correctness effect (`SendRace.claim()` keeps one continuation) | Cancel the sleeper
when the send completes | @developer.

F6 | minor | watch/sync_protocol/PROTOCOL.md:384-396; docs/watch_session_sync.md:351-362 | The class "a
frame the wrist applied from the phone emits nothing" names only the `exercise_push` test, while its
`structure_change` and snapshot halves are pinned by the S-104 tests at `WatchSessionEngineTests.swift:1348`
/`:1394` (mutation-proven per `.evidence.md` (e)/(f)) | Name all three | @developer.

F7 | minor | docs/watch_session_sync.md:225-229 | D-102 as written says a wrist holding an active session
refuses a phone snapshot for another session; the code also requires a non-empty ladder (the PROTOCOL
amendment row states it correctly) | Add the ladder condition, or point at the test | @developer.

F8 | minor | lib/state/watch/watch_session_auto_push.dart:137-155 | A pass that times out is reported, and
the abandoned pass may later report again on its own failure — two `onFailure` calls for one pass; no
state effect (the baseline is stored before the send, D-83) | Note it, or guard the second report
| @developer.

## The brief's eight questions

1. **Which session / can an id be overwritten.** No. The wrist refuses a snapshot naming another session
   whole (D-102), and the phone writes a row only where it has none (`existing == null`); every other path
   loads or appends. Adopting again loads the existing row and never rewrites its ladder (D-2), so a
   converged snapshot cannot re-assert the phone's structure. Pinned by the S-77A/S-78 Swift tests and by
   S-106/S-115, all present and passing.
2. **Wrist announcements and the revision.** Start emits `session_lifecycle` then its own snapshot; a
   wrist-originated add emits a second snapshot with the revision moved; a push, a structure change and a
   snapshot applied from the phone emit nothing. The wrist's `revision` is overwritten by the revision a
   phone snapshot carries (a snapshot is authoritative for revision, PROTOCOL.md:288), so the counter is
   not monotone across a phone answer; nothing in either codebase compares revisions to make a decision,
   so there is no ping-pong — the disagreement is with the summary at PROTOCOL.md:466-467, not with
   behaviour.
3. **`WatchSyncGraph.sync()` and the placeholder.** The production path composes from the phone's own
   session and sends that, or nothing when the phone holds none (S-109 case B) — never the placeholder.
   The one remaining `sendSnapshot()` on a production path is the request handler's fallback when a
   projection is unavailable and the mirror's ladder is non-empty
   (`lib/state/watch/watch_sync_request_handler.dart:101-110`), which is pre-existing and guarded; the
   placeholder is now only the mirror's initial state and the debug mains.
4. **`WatchEmitForwarder.bounded` and `catchUp`.** `bounded` bounds one frame and is drained by the queue;
   `catchUp` carries both gates (`reachable` **and** `engine.session != nil`) and the NSLock test-and-set
   with no suspension between check and set, so it is one sync per reachability edge and a dropped trigger
   while one is in flight (S-107, S-108). See F5 for the sleeper task.
5. **The phone's resume trigger.** `WatchResumeSync` is mounted only when the graph's callback exists;
   it observes `AppLifecycleState.resumed` (one call per reported resume, nothing on any other state) and
   registers in `initState` and removes in `dispose`. A cold start may report one `resumed`; that is one
   extra catch-up, recorded as A-17. `lib/app.dart` mounts it around the shell, so a watch-less build
   mounts no observer (existing app-shell tests pass no callback and are unaffected).
6. **Test vacuity.** No vacuous guard found. `prove-red a45dd49 test` over the three Phase-1 files is RED
   for assertion reasons (S-102/S-103/S-110/S-111 plus the renamed pre-existing test, e.g. the append
   assertion `Expected ['sl-1','sl-2','sl-3'] Actual ['sl-1','sl-2']`), and
   `prove-red e88a491 test test/watch_session_engine_test.dart` is RED at S-003:452, S-100:1337 and
   S-101:1364 — assertions, not a load error. The tests that assert *silence* (S-103's ever-seen half,
   S-104, S-105, S-106) are green at the base by construction and are proven by the named mutations in
   `.evidence.md` (b), (d), (e′), (f) — each shown red, then restored. No `testWidgets` real-delay trap in
   the new files: the whole suite finished in 97 s with no hang.
7. **Docs and PROTOCOL truth.** Every cited test name resolves (checked by grep, both stacks, including
   the renamed `…AnExercisePushFromThePhoneIsNeverAnnouncedBack` form). Two prose defects: F2 (false) and
   F7 (incomplete), plus the narrow pointer in F6. PROTOCOL's new rule and its amendment row match the
   implementation.
8. **Plan hygiene.** Progress is complete for all five phases; A-1…A-23 record the deviations (A-11/A-14
   sensor frame counts, A-22 the shell edit with `xcodebuild` left to the governor, A-23
   `WatchLiveMirroringTests.swift` predicted but untouched because S-107/S-108 live in
   `WatchConnectivityBridgeTests.swift`); Feedback is empty and the Open questions carry defaults. One
   falsity: F1.

## Checks

- TEST RUN `gateway test` (full): **4030 passed, 1 skipped, 0 failed** (exit 0) — matches the plan's final
  count; baseline 4013 (+17). Log `test-20261007-025535-63106.log`.
- SWIFT TEST `gateway swift-test` (full): **Executed 325 tests, with 0 failures** (exit 0) — matches;
  baseline 322 (+3). Log `swift-test-20261007-025822-68092.log`.
- PROVE-RED: `a45dd49 test` (the three Phase-1 files) RED, assertion failures only;
  `e88a491 test test/watch_session_engine_test.dart` RED at S-003/S-100/S-101.
- DIFF vs Predicted Files: conforms, with the two deviations disclosed as A-22/A-23; the extra new test
  files are the sensor-recording and resume-sync files the phases themselves added.
- LAYER RULES: state depends on `WorkoutRepository` only, screens take state by constructor, no
  platform-specific import in shared code, neither repository implementation was touched and the invariant
  grep (`hive_workout_repository` outside `lib/data`) stays clean.
- DOC FALSIFICATION: one document made false by the change — `docs/watch_session_sync.md:181-182`, F2.
  The other documents the changed files fall inside (`watch_surface.md`, `watch-app-setup-and-qa.md`,
  `PROTOCOL.md`, the watch entries of `docs/README.md`) assert nothing the change altered; their cited
  symbols and tests resolve.
- DOC STANDARD `docs/documentation_standard.md`: no prohibited class added — the new prose is invariant
  plus test pointer throughout. One note for the standard's owner, not a rejection: the Level-3 QA steps
  this change edits keep that document's pre-existing numbered-procedure style (§3.1), and the edited steps
  now carry test pointers, which is the conformant part.
- IMPACT: every row of the plan's Existing-Functionality Impact table was re-read against the code and its
  greps hold; a grep of the touched surfaces for further readers found only the debug mains
  (`live_session_mirror_debug_main.dart`, `watch_start_debug_main.dart`) and no shipping reader the table
  misses.
- CONVENTIONS: PASS on the applicable `docs/global_conventions.md` rules (repository-only state access,
  injected dependencies, named constants, no formatter run over a tree); N/A grouped — the rules about
  models/serialization, the SQL schema artifact, and theme tokens, none of which this range touches.

## Required before merge

1. F2 — one clause in `docs/watch_session_sync.md`. No structural guard is needed for prose; the fix is a
   deletion plus the existing test pointers.

## Recommended as a follow-up plan, not this PR

- F3's durable ever-seen ledger, with the switch/relaunch scenario as its guard.
- F1, F4, F5, F6 and F8 as cheap mechanical fixes if the owner wants them here; none is blocking.

