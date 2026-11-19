# Evidence — plan 142: the watch keeps a diagnostics log

Docs-keeper run 2026-11-10: every fact the docs now claim, and the test (exact name, read in the file this run)
that guards it. All four test files live in `watch/watchos/Tests/WatchSessionEngineTests/`.

| Fact (as documented) | Backed by |
|---|---|
| JSONL `watch-diagnostics.jsonl` in `Application Support/watch-diagnostics/`, one line per event `{at, kind, session?, detail?}` (UTC ISO-8601), one lock for all writers, newest `capacity` events kept (rewritten at `capacity + slack`), detail cut to `detailLimit` characters, newlines flattened, failures swallowed (`note` never throws) | `WatchDiagnosticsLogTests`: `testS14201ThreeEventsSurviveANewLogOverTheSameDirectory`, `testS14202ThirtyNotesCompactedToTheNewestTwenty`, `testS14204ADirectoryThatCannotBeCreatedNeitherThrowsNorTraps`, `testS14215ALongDetailIsCutToOneTwentyCharactersWithoutANewline` |
| A kill mid-append leaves a torn last line that reads skip; the next append starts on a fresh line | `WatchDiagnosticsLogTests.testS14203ATornLastLineIsSkippedAndTheNextAppendStartsAFreshLine` |
| A `coalesce` key records at most once per `coalesceWindow` (60 s), detail ends `x<n>`; `energy_live` is the one chatty type (its send lines) | `WatchDiagnosticsLogTests.testS14214ACoalescedKeyRecordsOncePerWindowAndCountsWhatItHeld`, `WatchDiagnosticsHooksTests.testS14207LiveEnergyLiveIsCoalescedToOneLineAMinute` (a failed `energy_live` is never coalesced: `testS14207AFailedEnergyLiveIsNotCoalesced`) |
| `noteLaunch()` records `launch` with `previous=<kind>[/<detail>]@<UTC time>`, or `previous=none` | `WatchDiagnosticsLogTests.testS14205NoteLaunchNamesThePreviousRunAndNoneWhenEmpty` |
| The bridge notes `frame_sent` (`<type> live`/`queued`/`failed: <error>`) and `frame_not_sent`; a frame the radio cannot carry is `frame_not_sent` | `WatchDiagnosticsHooksTests.testS14206SendOutcomesAreRecordedFrameSent` |
| The bridge notes `frame_received` (type, session) and `frame_handler_failed` when the handler throws | `WatchDiagnosticsHooksTests.testS14208ADeliveredFrameIsRecordedAndItsHandlerFailureToo` |
| The engine notes `frame_rejected` once for an incoming frame its validator refuses, engine state unchanged; an own frame refused at the emit side is `frame_not_sent` | `WatchDiagnosticsHooksTests.testS14209ARefusedIncomingFrameIsRecordedFrameRejectedOnce`, `testS14209ARefusedOwnFrameIsRecordedFrameNotSent` |
| The platform workout notes `workout_begin`, `workout_end` (`saving`/`discarded`), `workout_adopted`, `workout_recovered` (type + outcome) | `WatchDiagnosticsHooksTests.testS14210ThePlatformWorkoutRecordsItsLife` |
| The log is built once in `WatchAppHost.init` and handed to the radio halves, the engine and the platform workout; the launch, `recovery_relaunch`, every scene phase, reachability and link-problem are noted in the app target; the radio notes `frame_send_refused` | `WatchDiagnosticsSourceTests`: `testS14213TheHostBuildsTheLogOnceAndHandsItOn`, `testS14213TheAppNotesTheRecoveryRelaunch`, `testS14213TheHostNotesReachabilityLinkProblemAndScene`, `testS14213TheRadioNotesTheLateRefusal` |
| `nil` diagnostics (or an unwritable directory) changes nothing about sends, reports or engine state | `WatchDiagnosticsHooksTests.testS14211TheHooksChangeNothingAboutWhatHappens` |
| The Start screen's Diagnostics button opens the sheet with `WatchDiagnosticsView(log: host.diagnostics)` | `WatchDiagnosticsSourceTests.testS14213TheStartScreenOpensTheDiagnosticsSurface` |
| The summary: "Started HH:mm — restarted by the system" when a `recovery_relaunch` follows the latest `launch`; "Before that: last seen … at HH:mm" (background → "in the background", active → "on screen", other kinds → the kind); "First run recorded." when nothing earlier; newest 40 lines, newest first, `HH:mm:ss <kind> <detail> s:<session prefix 4>` | `WatchDiagnosticsSummaryTests`: `testS14212ARestartedRunNamesTheBackgroundSceneFromThePreviousRun`, `testS14212ThePhrasesFollowTheKindAndDetailOfThePreviousRun`, `testS14212AFirstLaunchAloneSaysStartedAndFirstRunRecorded`, `testS14212SixtyEventsGiveTheNewestFortyLinesNewestFirst`, `testS14212ALineNamesTimeKindDetailAndSessionPrefix`, `testS14212NoLaunchMeansNoStartRecordedYet` |

Not unit-guarded (source-read this run): the "dimmed" phrase for a `scene` event with detail `inactive`
(`WatchDiagnosticsSummary.swift`, the `phrase` switch) and the received-side coalescing of `energy_live`
(`WatchConnectivityBridge.deliver`, `coalesce: "frame_received/…"`); no test asserts either.
