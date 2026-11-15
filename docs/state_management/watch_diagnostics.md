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
cannot read; `workout_begin`, `workout_end` (`saving`/`discarded`), `workout_adopted` and
`workout_recovered` from the platform workout; `workout_end` with the detail `discarded_held <name>`
when a second begin ends the session the store still held, and `workout_saved <name>` /
`workout_save_failed <name>` around its `finishWorkout()`, from the app target's
`HealthKitWorkoutStore` — so a walk that never reached Health says so, and a begin that discards a
held session names the type it dropped. Verified by `WatchDiagnosticsHooksTests`
(`testS14206SendOutcomesAreRecordedFrameSent`,
`testS14208ADeliveredFrameIsRecordedAndItsHandlerFailureToo`,
`testS14209ARefusedIncomingFrameIsRecordedFrameRejectedOnce`, `testS14209ARefusedOwnFrameIsRecordedFrameNotSent`,
`testS14210ThePlatformWorkoutRecordsItsLife`), by `WatchDiagnosticsSourceTests`
(`testS14213TheAppNotesTheRecoveryRelaunch`, `testS14213TheHostNotesReachabilityLinkProblemAndScene`,
`testS14213TheRadioNotesTheLateRefusal`), by
`WatchWorkoutStoreSourceTests.testS16809TheStoreNotesTheSaveOutcomeAndTheHeldDiscard` (plan 168
D-16804) and by `WatchDiagnosticsLogTests`
(`testS14205NoteLaunchNamesThePreviousRunAndNoneWhenEmpty`).

**Wiring.** The log is built once in `WatchAppHost.init` (`ios/OmniTrain Watch App/ContentView.swift`) and handed
to `OmniTrainWatchConnectivity`, `WatchConnectivityBridge`, `WatchSessionEngine`, `WatchPlatformWorkout` and
`HealthKitWorkoutStore` as a
trailing optional `diagnostics:` parameter; `nil` records nothing and changes nothing. Verified by
`WatchDiagnosticsSourceTests.testS14213TheHostBuildsTheLogOnceAndHandsItOn`,
`WatchWorkoutStoreSourceTests.testS16809TheStoreNotesTheSaveOutcomeAndTheHeldDiscard` and
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

**Entry point visibility.** The Diagnostics button and the phone's Diagnostics row are debugging
tools, so neither ships to users (plan 177, D-17702/D-17703): both show in debug and profile builds and
are hidden in a release build, while the logs keep recording either way (D-17701) — only the way in is
gated. On the wrist the gate is `DiagnosticsEntryPoint.isVisible`
(`ios/OmniTrain Watch App/DiagnosticsEntryPoint.swift`), which `ContentView` reads when it passes
`onOpenDiagnostics`: a release build passes nil and `WatchStartView` leaves the button off. The watch
app target's Profile configuration defines `PROFILE` (`ios/Runner.xcodeproj/project.pbxproj`), and no
committed configuration defines `OMNITRAIN_DIAGNOSTICS`. On the phone the gate is the one constant
`kDiagnosticsEntryVisible` (`lib/core/constants/diagnostics_entry.dart`), read by `lib/main.dart` when
it builds `MyApp`: a release build passes null and Settings shows no row. The owner can bring either
entry back in a release build — `--dart-define=OMNITRAIN_DIAGNOSTICS=true` on the phone,
`OMNITRAIN_DIAGNOSTICS` in the watch app target's Active Compilation Conditions (Release) or
`OMNITRAIN_DIAGNOSTICS=1` in the scheme's run action on the watch. Verified by
`WatchDiagnosticsSourceTests.testS17704TheEntryPointIsGatedThroughTheAppTargetGate`,
`testS17705TheWatchBuildConfigurationsCarryTheRightConditions`,
`testS17707HidingTheEntryNeverStopsTheRecording`, `test/diagnostics_entry_test.dart` (S-17701,
S-17706), `test/diagnostics_wiring_source_test.dart` (S-17702) and `test/settings_diagnostics_test.dart`
(S-17703).

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

**The phone.** The phone keeps its own log of its side of the link (plan 143): `DiagnosticsLog`
(`lib/core/services/diagnostics_log.dart`), the Dart twin of the wrist's, with the same line shape (`{at, kind,
session?, detail?}`, UTC times), the same bound (newest 3000, rewritten when 3300 lines are reached; a failed
rewrite or an empty read leaves the file and backs off), the same 60 s coalescing for `energy_live` and the same
120-character cut. It lives in `phone-diagnostics.jsonl` under the app support directory (memory only on web, and for a run in which the directory cannot be resolved within two seconds) and
is built once in `lib/main.dart`, which notes `launch` (with `previous=`) and registers
`DiagnosticsLifecycleObserver` (`app_lifecycle`, every state). `WatchConnectivityTransport` notes `frame_sent`
(`<type> delivered`, `queued`, `undelivered` or `failed: <reason>`), `frame_received`, `frame_handler_failed` and
`link_error`, and `reachability`; a reason is the platform error's code, `timeout`, or the error's type name, never
its message. Settings, in the APPLE WATCH section, has a `Diagnostics` row with `Copy`: it puts the header (app,
platform, event count) and the events, oldest first, on the clipboard. Verified by `test/diagnostics_log_test.dart`,
`test/diagnostics_watch_transport_test.dart`, `test/diagnostics_lifecycle_test.dart`,
`test/diagnostics_wiring_source_test.dart`, `test/settings_diagnostics_test.dart`,
`test/watch_session_adoption_bridge_test.dart` and `test/watch_session_import_test.dart`. Not yet recorded: the
phone's own validation refusals.

**The phone's decisions.** Six kinds record what the phone decided about a watch session, each naming the session
and nothing that varies but fixed words and UTC instants (plan 174, D-17402): `adoption_decision`, the bridge's
verdict on a snapshot — `adopted status=active start=<UTC>`, `skipped reason=held_session held=<session id>` (the
phone already holds another session, D-10) or `skipped reason=already_history`; `session_row_created`, a row the
phone wrote itself — `path=snapshot|started|import start=<UTC> end=<UTC|none>`; `session_start_corrected`, a start
moved to the wrist's own (`from=<UTC> to=<UTC> path=merge|import`, plan 167 D-16705); `end_clamped`, an end cut to
this phone's clock plus five minutes (`from=<UTC> to=<UTC> who=lifecycle|import`, plan 164's bound — this line, not
the bound's own prose, is the phone's record of a cut); `end_applied`, an end the session now holds
(`who=catchup|end_session|import instant=<UTC|none> status=<the row's status>`); and `discard_applied`, a wrist
discard (`who=held|finished`). Only `adoption_decision` is deduplicated, per session and detail, in memory
(D-17404): a snapshot resent fifty times is one line, because a decision the phone repeats is not a new decision,
while the other five are recorded every time they happen. Instants are this phone's clock; nothing recorded here is
a name, a weight or a number the owner typed, which is the privacy rule above. Verified by
`test/watch_session_adoption_bridge_test.dart` group `plan 174 the log records what the bridge decided`
(`S-17401 a fresh adoption notes its decision and the row it wrote`,
`S-17402 a refused adoption is noted once, not fifty times`,
`S-17403 a snapshot of a session already in history is noted once`,
`S-17412 a burst of repeats leaves one line per decision`,
`S-17404 the row a start report opens is noted with the wrist's start`,
`S-17407 a claimed end beyond the bound is noted as clamped`,
`S-17409 an applied end is noted with who and its instant`,
`S-17409b a later end on a finished row is noted as a catch-up`,
`S-17409c a completed frame with no instant is noted as none`,
`S-17410 an applied discard is noted with who it was`,
`S-17410b a discard earlier than the phone’s finish is noted as such`) and by
`test/watch_session_import_test.dart` group `import diagnostics notes`
(`S-17405 an imported history row is noted with both stamps`,
`S-17406 A a merge’s start correction is noted`, `S-17406 B an import’s start correction is noted`,
`S-17408 an import clamps a future end and notes it`, `S-17408 b the catch-up bound is noted too`,
`S-17409 an applied import end names who and the instant`).

**Send to phone (plan 144).** The wrist's log reaches the phone only when the owner asks. The Diagnostics screen's
last button, "Send to phone", copies the log file (`WatchDiagnosticsLog.snapshotFile`, a file named
`watch-diagnostics-<UTC stamp>.jsonl` in the temp directory) and hands it to the system's file transfer
(`OmniTrainWatchConnectivity.sendDiagnostics`: `transferFile` with metadata `kind = diagnostics_log`), never through
the sync frames, so it cannot change what syncs. The screen then says "Sent. The phone has it when it next wakes.",
"Install the OmniTrain app on the phone.", "Phone link not ready." or "Nothing to send."
(`WatchDiagnosticsSendOutcome`; its `failed` case, "Could not send.", is defined but no path produces it today: the
radio does not observe a transfer that fails after it was queued). On the phone, the plugin's `session(_:didReceive file:)`
(`packages/omnitrain_watch_link/ios/Classes/OmniTrainWatchLinkPlugin.swift`) keeps only a file with that metadata,
copies it before the callback returns (the system deletes it afterwards) to
`<app support>/watch-diagnostics/watch-received.jsonl`, replacing the previous one, and emits nothing to Dart.
`DiagnosticsLog.attachWatchReceived` (called by `main.dart`) points the phone's log at that file;
`shareTextWithWatch` then returns the header, `Watch log received <time>` (the file's modification time) or `Watch
log not received`, `Times are each device's own clock`, and both logs' events merged by time, each line tagged
`[phone]` or `[watch]`. Settings' Diagnostics row reads `N events · watch log M events` and Copy uses that text.
Verified by `WatchDiagnosticsSendTests` (`watch/watchos/Tests/WatchSessionEngineTests/`),
`test/diagnostics_merged_text_test.dart`, `test/settings_diagnostics_watch_log_test.dart`,
`test/diagnostics_received_storage_test.dart` and `test/diagnostics_file_receive_source_test.dart`; the transfer
itself needs a real watch and phone (QA step 40).
