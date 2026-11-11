# The Watch Diagnostics Log

**Scope.** The watch's own event log (`WatchDiagnosticsLog`, plan 142) and the Diagnostics screen on the wrist that reads it.
Observation only: nothing in the sync, the workout or the timers depends on it.

> Part of [State Management & Services](../state_management.md). See that index for the full class list and dependency graph.

---

**The log.** `WatchDiagnosticsLog` (`watch/watchos/Sources/WatchSessionEngine/WatchDiagnosticsLog.swift`) is one
JSONL file, `watch-diagnostics.jsonl`, in the app's `Application Support/watch-diagnostics/` directory: one line
per event, `{at, kind, session?, detail?}`, the time UTC ISO-8601. One lock serialises every writer; the newest
`capacity` events are kept, the file rewritten down to that bound once it reaches `capacity + slack` lines; a
detail is cut to `detailLimit` characters with newlines flattened; every failure is swallowed, so `note` never
throws. A kill mid-append leaves a torn last line that a read skips, and the next append starts on a fresh line.
Verified by `WatchDiagnosticsLogTests` (`watch/watchos/Tests/WatchSessionEngineTests/`):
`testS14201ThreeEventsSurviveANewLogOverTheSameDirectory`, `testS14202ThirtyNotesCompactedToTheNewestTwenty`,
`testS14203ATornLastLineIsSkippedAndTheNextAppendStartsAFreshLine`,
`testS14204ADirectoryThatCannotBeCreatedNeitherThrowsNorTraps`,
`testS14215ALongDetailIsCutToOneTwentyCharactersWithoutANewline`.

**The chatty exception.** An event noted with a `coalesce` key is recorded at most once per `coalesceWindow`
seconds, its detail then ending `x<n>` for the events it stands for; the live calorie frame `energy_live` is the
one chatty type, so a long workout cannot push the interesting events out of the log. Verified by
`WatchDiagnosticsLogTests.testS14214ACoalescedKeyRecordsOncePerWindowAndCountsWhatItHeld` and
`WatchDiagnosticsHooksTests.testS14207LiveEnergyLiveIsCoalescedToOneLineAMinute`.

**What is recorded.** The kinds, and who notes them: `launch` (`noteLaunch()`, carrying
`previous=<kind>[/<detail>]@<UTC time>` — the last event the previous run recorded — or `previous=none`);
`recovery_relaunch` when the system relaunches the app to recover a workout
(`WatchAppDelegate.handleActiveWorkoutRecovery`); `scene` (`active`, `inactive` or `background`, every phase),
`reachability` (`reachable`/`unreachable`) and `link_problem` (`true`/`false`) from the app host; `frame_sent`
(`<type> live`, `<type> queued`, `<type> failed: <error>`), `frame_not_sent`, `frame_received` (`<type>`) and
`frame_handler_failed` from the bridge (and `frame_not_sent` from the engine when the validator refuses a frame the
engine itself built); `frame_send_refused` when the radio refuses a live send after the call
returned, durable frames then queued; `frame_rejected` when the engine must refuse an incoming frame this build
cannot read; `workout_begin`, `workout_end` (`saving`/`discarded`), `workout_adopted` and `workout_recovered`
from the platform workout. Verified by `WatchDiagnosticsHooksTests`
(`testS14206SendOutcomesAreRecordedFrameSent`,
`testS14208ADeliveredFrameIsRecordedAndItsHandlerFailureToo`,
`testS14209ARefusedIncomingFrameIsRecordedFrameRejectedOnce`, `testS14209ARefusedOwnFrameIsRecordedFrameNotSent`,
`testS14210ThePlatformWorkoutRecordsItsLife`), by `WatchDiagnosticsSourceTests`
(`testS14213TheAppNotesTheRecoveryRelaunch`, `testS14213TheHostNotesReachabilityLinkProblemAndScene`,
`testS14213TheRadioNotesTheLateRefusal`) and by `WatchDiagnosticsLogTests`
(`testS14205NoteLaunchNamesThePreviousRunAndNoneWhenEmpty`).

**Wiring.** The log is built once in `WatchAppHost.init` (`ios/OmniTrain Watch App/ContentView.swift`) and handed
to `OmniTrainWatchConnectivity`, `WatchConnectivityBridge`, `WatchSessionEngine` and `WatchPlatformWorkout` as a
trailing optional `diagnostics:` parameter; `nil` records nothing and changes nothing. Verified by
`WatchDiagnosticsSourceTests.testS14213TheHostBuildsTheLogOnceAndHandsItOn` and
`WatchDiagnosticsHooksTests.testS14211TheHooksChangeNothingAboutWhatHappens`.

**The screen.** The Start screen's last button, "Diagnostics" (`WatchStartView`'s `onOpenDiagnostics`), opens
`WatchDiagnosticsView` in a sheet. `WatchDiagnosticsSummary` builds two plain sentences — "Started 21:04 —
restarted by the system" when a `recovery_relaunch` follows the latest `launch`, and "Before that: last seen in
the background at 20:52" (an active scene reads "on screen", an inactive one "dimmed", any other kind reads as
itself; "First run recorded." when nothing earlier is stored) — and the newest
`WatchDiagnosticsSummary.lineLimit` events, newest first, as `HH:mm:ss <kind> <detail> s:<first four characters
of the session id>`. Verified by `WatchDiagnosticsSummaryTests`
(`testS14212ARestartedRunNamesTheBackgroundSceneFromThePreviousRun`,
`testS14212ThePhrasesFollowTheKindAndDetailOfThePreviousRun`,
`testS14212SixtyEventsGiveTheNewestFortyLinesNewestFirst`, `testS14212ALineNamesTimeKindDetailAndSessionPrefix`)
and `WatchDiagnosticsSourceTests.testS14213TheStartScreenOpensTheDiagnosticsSurface`.

**What it cannot do.** Say why the system closed the app: watchOS gives an app no crash hook, MetricKit is not in
the watchOS SDK, and the watch app has no crash reporter (Sentry's own documentation says its Apple SDK does not
detect crashes on watchOS). What the log shows instead is the
last recorded phase before the gap and how the app started again.

**Privacy.** Events carry types, session ids, outcomes and error text (cut to `detailLimit` characters) — never
an exercise name, a weight, a food or a number the user typed (plan 142, D-14211). A refused frame is recorded by its
rejection's code and path only, because the validator's message can quote the offending value; a handler that
fails is recorded the same way for a refusal, and by error domain and code for any other error. Compacting the log
(once per `slack` events) rereads and rewrites the file under the same lock; a rewrite that fails, or a read that
finds nothing, leaves the file untouched and tries again after `slack` more events.

**The phone.** The phone's own log (plan 143) and the way this wrist log reaches the phone are separate, later
plans; until then the wrist's log is read on the wrist.
