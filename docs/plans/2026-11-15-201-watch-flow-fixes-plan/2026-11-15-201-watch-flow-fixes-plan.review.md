# Review: plans 201, 202, 203, 204 · watch-flow-fixes · 7664f126..working tree

Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 2 · minor 0 · tests: Swift package 1548 passed 0 failed; Flutter 7711 passed 4 skipped 0 failed; analyze 181 issues (baseline 181), 0 errors (counts as established by the governor/brief, not re-run)
Diff vs Predicted Files: conforms for the change-set file list; outside it sit the three plan docs (201/202/203, written by the docs phases) and other sessions' uncommitted stats/diagnostics files (`lib/state/…stats…`, `…diagnostics…`, their docs) — the latter are not part of this set and were not reviewed, per the brief.

## Q1 — Plan 201 D-20104: finish() logging at End's instant, throw path, rating.end()

Verdict: OK.
- Per-kind entries are correct at End's instant: timed/elapsed goes through the
  window payload (`WatchLoggingState.swift:1133 log(now:)` → elapsed branch),
  hold/drill through the window payload plus `extraLoadKg`, round/period through
  `roundWindow` (`WatchLoggingState.swift:1320`), which emits the completed
  countdown (start, pause ms, completion instant) when the planned clock ran
  out. `hasRunningEffort` is false for a plain set (no clock), so End never
  fabricates a set entry. `workTimer` (`:688`) is only non-nil under `canLog`
  (`:340`), so `hasRunningEffort` true implies a slot — the "no slot yet" throw
  in `log()` is unreachable from `finish()`.
- Throw path: the only reachable throws from `log()` are
  `engine.appendObservation` failures (`WatchSessionEngine.swift:1881`
  `requireConformant` / store failure). `finish()` uses `try? await
  logging.log()` then `guard hasLoggedEfforts else discard()` — a refused log
  discards with real work in it. That is D-20104's own documented rule ("a log
  the wrist refuses leaves nothing logged, and that is still a discard") and
  matches today's parity (a failed Log then End discards too). Not a finding.
- `rating.end()` still works after the in-finish log: `WatchEffortRating.swift:167`
  computes `isRatingOwed` from the entries *after* the log, so the new effort
  counts; S-20107 asserts status `completed`, which only `rating.end()` →
  `finishSession` produces (`discard()` yields abandoned, `log()` does not end).

## Q2 — Plan 201 D-20101: consumers of nextSlotId / restLabels.next when everything is done

Verdict: OK. Consumers (grep over `watch/watchos/Sources` and
`ios/OmniTrain Watch App`): `WatchLoggingState.leaveRest` (`:594`) — nil means
no move, the rest still ends; `WatchRestView`'s Next button and
accessibilityHint (`:148-156`, `:158`) — the haptic plays on every tap
regardless of the label, unchanged by this diff (pre-existing, not keyed on
nil); and `deriveRestLabels` itself. "Nothing planned next" appears only as
copy constants (`WatchRestLabels.swift:50,180,232`, `WatchLoggingState.swift:637`).
No consumer treats nil / the phrase as "workout over": no auto-finish, no
summary prompt, no end-of-workout haptic exists on that key.

## Q3 — Plan 202: ranInterval swallowing a legitimate phone adoption

Verdict: OK.
- (a) Wrist-started rest (row id without `tms-`) vs phone rest with the same
  start within 1 s: being ignored is the designed answer (D-20201/20203: same
  interval, one adoption). Pause-shape repeats stay adoptable
  (`testS20214ARestThatDiffersOnlyByItsAccumulatedPauseIsAdopted`), resumes stay
  adoptable (`testS20212…`), a later genuine phone rest supersedes
  (`testS20210…`), the tolerance itself is pinned (`testS20211…`).
- (b) Both entry points use the frame's own `sentAt` as the `?? recordedAt`
  fallback: `applyTimerState` (`WatchSessionEngine.swift:1013`, recordedAt:
  sentAt, authoritative: false) and the snapshot path (`:727-735`,
  authoritative: true) agree, so the fallback cannot fuse two different
  intervals beyond the 1000 ms tolerance. A malformed-start frame behaves as
  before the change.
- (c) `ranInterval` filters `held.sessionId == sessionId`, so rows from another
  session in the single `WatchTimerLog` (`:90`) never swallow; the new slot
  scoping is separately pinned (`testS20213…`). The slotless-work-frame edge
  cannot arise from the real phone writer (`watch_timer_push.dart:473`
  `_composeWanted` always sends `sessionExerciseId` for work timers); per
  D-20201 the slot is part of interval identity, so the code matches the plan.

## Q4 — Plan 203/204: phone-echo wristModality; _knownModality on reconcile

Verdict: OK.
- `WatchIncomingRouter.receive` is fed only by the wrist inbound transport
  (`watch_sync_wiring.dart:421`); both engines emit `origin: "watch"` (twin at
  `lib/watch/session/watch_session_engine.dart:286`). `_wristModality` does not
  check origin, but adoption is create-only
  (`watch_session_adoption_bridge.dart:824-825`: `consider` → `_adopt` only
  when `existing == null`; the placeholder branch `:826-850` writes the ladder
  only), and a session the phone holds is never adopted or rewritten
  (`S-20305`). So a phone-echo modality key could only name a session the phone
  does not hold — the session that would be created from a wrist run anyway;
  the phone's own placeholder row keeps the `session_started` row's modality
  (D-20303 accepts that path unchanged; A-3 ratified below).
- `_knownModality` is called only inside `_adopt` (the create path); the
  add-only reconcile of a held session never calls it. Matches D-20303.

## Q5 — Plan 201: weakened "second pick emits nothing" assertion

Verdict: OK. After D-20105 intercepts a held-active session in
`startModalityWorkout` (`WatchStartPaths.swift:7`), the only remaining
`createSession` refusal on that surface is held-ENDED, which now creates a new
session and is pinned by `testS20113AModalityPickOverAnEndedSessionCreatesANewOne`.
The "refused start emits nothing / appends no row" protection still lives at
paths level for `startFreeWorkout` (S-177) and `startFromRoutine` (S-170) in
`WatchSessionStartPathsTests.swift:1037-1100`, untouched by this diff. No
behaviour the old test protected is now unprotected on a path that still
refuses.

## Findings

1. [Major] `docs/state_management/watch_surface_wrist.md:254` — names
   `testS17605ASecondPickReturnsTheHeldSessionAndEmitsNothing`, a test this
   change set renamed to `…AndAddsThePick`; the doc now cites a test that does
   not exist. Fix: one-line reference update. Guard: the docs contract scans
   markers, not test names — the sweep for renamed tests missed this file.
2. [Major] `docs/state_management/watch_surface_wrist_logging.md:302` — names
   `testS9104NothingPlannedCarriesNoSlotId`, renamed in this change set to
   `testS9104TheWholeLadderDoneCyclesToTheFollowingExercise`; the unchanged
   line right below the rewritten rest-labels passage cites the old name.
   Fix: one-line reference update. Guard: same as above.

## Assumption Log rulings

- 201 A-1 (architect skipped the input-reality pass): **ratify** — the seed
  named writers, units and fixtures; every 201 scenario maps to a test present
  in the diff, and the phone-writer check for plan 202 (work timers always
  carry `sessionExerciseId`) confirmed the fixture reality matches the code.
- 202 A-1 (same skip): **ratify** — same grounds.
- 202 A-2 (ghost-hold cause read from code, not device): **ratify** — the QA
  doc now records the on-wrist confirmation procedure (item 48) instead of
  claiming device proof.
- 202 A-3 (phone-side stop of its own timer unasserted): **ratify** — the
  wrist is safe either way (S-20201); phone-side behaviour is out of scope.
- 203 A-1 (architect skip): **ratify**.
- 203 A-2 (wrist-wins over routine Focus needed owner sign-off): **ratify** —
  implemented as the owner decided and pinned by S-20304.
- 203 A-3 (session_started path left unchanged): **ratify** — verified in code:
  the placeholder reconcile writes no modality.
- 204 A-1 (architect skip): **ratify**.
- 204 A-2 (owner-visible only together with 203): **ratify** — both plans land
  in this set.

## Scenario coverage

Plan 201
- S-20101 → `WatchRestLabelsTests.testS20101AfterTheLastExerciseNextGoesBackToTheFirst`
- S-20102 → `WatchRestLabelsTests.testS9104TheWholeLadderDoneCyclesToTheFollowingExercise`
- S-20103 → `WatchRestLabelsTests.testS20103AOneExerciseLadderNeverAnnouncesAMove`
- S-20104 → `WatchRestLabelsTests.testS20104AnUndoneExerciseWinsOverTheCycle`
- S-20105 → `WatchRestNextHoldTests.testS20105TheListStartsOverAfterTheLastExerciseAndKeepsCycling`
- S-20106 → `WatchMenuTests.testS20106TheMenuRowsWearTheirColours`
- S-20107 → `WatchMenuEndRunningEffortTests.testS20107EndWithARunningEffortLogsItThenFinishes`
- S-20108 → `WatchMenuEndRunningEffortTests.testS20108ASetExerciseWithNothingLoggedStillDiscards`
- S-20109 → `WatchMenuEndRunningEffortTests.testS20109AnotherExercisesPhoneClockIsNotThisExercisesRunningEffort`
- S-20110 → `WatchMenuEndRunningEffortTests.testS20110ATimedExerciseWhoseClockWasNeverStartedStillDiscards`
- S-20111 → `WatchMenuTests.testS20111TheEndRowRaisesTheFinishQuestionWhenThereIsWorkToSave`
- S-20112 → `WatchModalityStartTests.testS20112AModalityPickOverAHeldEmptySessionAddsTheExercise`
- S-20113 → `WatchModalityStartTests.testS20113AModalityPickOverAnEndedSessionCreatesANewOne`
- S-20114 → `WatchModalityStartTests.testS20114TheHeldSessionKeepsItsOwnModality`

Plan 202 (all in `WatchTimerReadoptionTests`)
- S-20201 → `testS20201AStoppedHoldIsNotRestartedByALaterFrameNamingTheSameInterval`
- S-20202 → `testS20202ASnapshotNamingTheStoppedHoldDoesNotReopenIt`
- S-20203 → `testS20203ARealSecondIntervalAfterAStopIsAdopted`
- S-20204 → `testS20204AStaleHoldForAnotherExerciseDoesNotMoveTheWrist`
- S-20205 → `testS20205ARestAdoptedTwiceKeepsOneRowAndTheSamePingMemory`
- S-20206 → `testS20206AStopFrameStillStopsTheHold`
- S-20207 (fixtures + replay green) → covered by the whole-package run: Swift
  package 1548 passed 0 failed, Flutter 7711 passed 4 skipped 0 failed
- S-20208 → source guard test in `WatchTimerReadoptionTests`
- S-20209..S-20216 → their same-named tests in `WatchTimerReadoptionTests`
  (incl. S-20211 tolerance, S-20213 slot scoping, S-20214 pause-shape)

Plan 203
- S-20301..S-20305, S-20307 → `test/watch_session_wrist_modality_test.dart`, groups of the same names
- S-20306 → Swift `SyncProtocolFixturesTests` + Dart fixtures suite (both green in the whole runs)

Plan 204
- S-20401 → `WatchSnapshotWristModalityTests.testS20401ASessionWithAModalityNamesItInItsSnapshot`
- S-20402 → `…testS20402AFreeSessionNamesNoModality`
- S-20403 → `…testS20403TheOtherKeysAndTheSchemaAreUnchanged`
- S-20404 → `…testS20404TheWristEchoesTheModalityItWasToldAndKeepsIt`
- S-20405 → `test/watch_snapshot_wrist_modality_send_test.dart` (group `S-20405`)
- S-20406 → `…testS20406TheModalitySurvivesARelaunch`

## Docs delta

Plan 201 — `docs/state_management/watch_surface_wrist_logging.md`
- "Nothing planned next" one-exercise-ladder reword → applied (all named tests verified in the diff)
- ADDED cycle row → applied
- Discard/End colour row → applied (`WatchMenuTests.testS20106…` exists)
- End-logs-running-effort row → applied (`testS20107…` exists)
- ADDED modality-pick-over-started-workout row → applied (testS20112/13/14, testS17605…AndAddsThePick exist)

Plan 202 — `docs/state_management/watch_surface_wrist_logging.md`
- timer-never-restarted reword (interval identity) → applied (named S-20201/02/05/09 tests exist)
- ADDED same-interval row → applied
Plan 202 — `docs/watch-app-qa-wrist-logging.md`
- ADDED item 48 → applied (all named tests exist)
Plan 202 — unnamed edit to list: the jump paragraph's new "an interval the
wrist already stopped (plan 202)" case (true: no row stored, so no jump;
matches S-20204/S-8402 family).

Plan 203 — `docs/watch-app-qa-wrist-logging.md`
- ADDED item 49 → applied (test names verified)
Plan 203 — `docs/watch_session_sync.md`
- ADDED wrist-modality paragraph → applied (S-20301/20304/20302 named, all exist)

Plan 204 — none (per plan).

Stale old terms the keeper did not catch → findings 1 and 2 above.
