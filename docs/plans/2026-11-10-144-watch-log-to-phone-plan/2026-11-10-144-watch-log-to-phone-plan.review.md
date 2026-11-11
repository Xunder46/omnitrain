# Review: plan 144 watch-log-to-phone · P1,P2,P3 · eee2179a..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 4 · tests: flutter test 7355 passed / 18 failed / 2 skipped
Diff vs Predicted Files: conforms; outside: `.claude/crew.md` (lead playbook note, not a builder file),
`watch/watchos/Tests/WatchSessionEngineTests/WatchDiagnosticsSourceTests.swift` (finding 3).

## Findings

1. [Minor] docs/watch-app-setup-and-qa.md:843 — QA step 40 says the pasted header says
   "Watch log received HH:mm", but the code writes the full UTC ISO stamp
   (`Watch log received 2026-07-13T06:05:00Z`, `DiagnosticsLog._iso`, seconds precision —
   lib/core/services/diagnostics_log.dart:227). A maintainer comparing the paste with the step sees a
   full ISO time, not HH:mm. Fix: one line in step 40 — "Watch log received <UTC time>" (D-14405's own
   wording). Guard: none needed (doc-only).
2. [Minor] ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift:187-194 —
   `WatchDiagnosticsSendOutcome.failed` ("Could not send.") is unreachable: no caller returns it and no
   `session(_:didFinishFileTransfer:error:)` is observed anywhere in the radio (grep this run found
   only `transferFile` at :193), yet docs/state_management/watch_diagnostics.md's "Send to phone"
   lists it among the words the screen can show. A user whose queued transfer later fails sees
   "Sent." and no further message. Per D-14403 the code matches the plan, so the smallest fix is one
   doc line: name `failed` as a defined outcome no path produces today. (Observing transfer errors
   would be a new feature — not proposed.)
3. [Minor] watch/watchos/Tests/WatchSessionEngineTests/WatchDiagnosticsSourceTests.swift:129 —
   outside every write scope in the plan's Phases table (P1 names only the new
   `WatchDiagnosticsSendTests.swift`). The change is forced by D-14403: the S-14213 guard's expected
   string must match the new `onSend:` call or the existing Swift suite goes red, and acceptance
   requires it green. The plan should have listed the file; no code change needed.
4. [Minor] watch/watchos/Sources/WatchSessionEngine/WatchDiagnosticsLog.swift:117-121 — two Sends in
   the same second produce the same stamped name (`watch-diagnostics-<stamp>.jsonl`), and the second
   atomic write replaces the first snapshot's bytes. If the system has not yet read the first queued
   file (A-1: the simulator cannot settle when `transferFile` reads it), the first transfer would
   deliver the second log's content — in practice the same log, newer, and the user must tap twice
   within one second. Also: the app never deletes a snapshot file, so one file per Send accumulates
   in the temp directory until the system purges it (each at most the log's capacity, a few hundred
   KB); deleting it immediately would risk the transfer reading it late. No change proposed; settle
   the `transferFile` read timing on the owner device (QA step 40).

## No other findings

Q1 Sync untouched — OK. The diff adds only: `sendDiagnostics` (frame-path file never touched), the
radio kept in `WatchAppHost` (`self.radio = session` — the bridge already held the session; the extra
strong reference changes no lifetime or activation behaviour), and the sheet's `onSend:` wiring.
No frame path, engine, bridge, ledger or timer line is modified; `transferFile` calls no delegate
method; the plugin's new `session(_:didReceive file:)` runs beside the existing message/userInfo
handlers and guards out everything not tagged `diagnostics_log` before any filesystem access.

Q2 Watch side — OK beyond finding 4. `snapshotFile` takes the log's lock; `readAll()` does not
re-lock (checked: it is a plain file read), so no deadlock; the empty-log guard answers nil; an
unreadable target answers nil and leaves the log untouched (S-14401 tests all three). The view's
button is inside `if let onSend {`, "Nothing to send." on a nil snapshot, the outcome's message under
the button; Package.swift declares `.watchOS(.v9)` and the view uses only API available there
(`.bordered`, `foregroundStyle`, `Divider`).

Q3 Plugin — OK. The copy is synchronous inside the callback (no `Task`/`async`/`DispatchQueue` —
the source guard test forbids exactly those), staged as `watch-received.jsonl.incoming` (stale staged
file removed first), then `replaceItemAt` on an existing destination (same volume, consumes the
staged file; on failure the previous received file stays and the next receive cleans the staged
one) or `moveItem` on a first receive; `.applicationSupportDirectory` is created with
`create: true` and the subdirectory with intermediates; a non-diagnostics file returns at the guard
with zero side effects. Two files close together arrive on the session's serial delegate queue, so
the fixed staged name cannot race (same A-1 family; the real device check settles it).

Q4 Phone Dart — OK. The merge comparator is a total order (time, then source `phone`<`watch`, then
stored index), so Dart's unstable `List.sort` cannot reorder ties (tested with equal times and two
same-time watch lines in stored order). A torn last line is skipped (`_decodeAll` drops unparsable
lines; `FileDiagnosticsStorage.read` decodes with `allowMalformed: true`; tested). The row reads the
watch log once per State (late field) and once after a Copy — a full watch log is at most `capacity`
(3000) events, a synchronous main-isolate decode of a few hundred KB, exactly the plan's Load-cost
row. `attachWatchReceived` writes two non-final fields once at startup (`main.dart` right after the
existing construction, before `noteLaunch`) on the single main isolate before any UI reads.
`openWatchReceivedStorage` mirrors the phone log's 2-second `getApplicationSupportDirectory` timeout:
on timeout or failure it answers in-memory empty storage with `receivedAt` null, so the subtitle
stays as before and Copy says "Watch log not received".

Q5 Claims — finding 1 and 2 above; every other sentence in
docs/state_management/watch_diagnostics.md "Send to phone" was checked against the code this run and
is true: snapshotFile's name and temp location, the radio's guards and metadata `kind`,
the four produced outcomes' words, the plugin's destination and replace-before-return, `main.dart`
calling `attachWatchReceived`, `shareTextWithWatch`'s header/time/merged-tagged shape, the row's
"N events · watch log M events", and every named test exists (listed in Scenario coverage).

## Test run

`.github/copilot/scripts/macos/gateway.sh test` (full `flutter test`, once, this run):
**+7355 ~2 -18 — Some tests failed.** All 18 failures are `TimeoutException after 0:00:30` in
`test/pre_release_gate_upload_destination_test.dart` (8), `pre_release_gate_notification_and_build_test.dart` (3),
`pre_release_gate_ios_artifact_test.dart` (7) — artifact-inspection gate tests that need built
IPA/AAB artifacts; the diff touches none of those files or any build script. No plan-144 test file
appears among the failures.

## Scenario coverage

S-14401 → WatchDiagnosticsSendTests · testS14401TheSnapshotCarriesTheLogLinesUnderTheStampedName,
testS14401AnEmptyLogSnapshotsNothing, testS14401ATargetThatCannotBeCreatedAnswersNil
S-14402 → WatchDiagnosticsSendTests · testS14402TheFourOutcomesSayTheWordsTheScreenShows
S-14403 → WatchDiagnosticsSendTests · testS14403TheRadioSendsTheFileThroughTheSystemsTransfer,
testS14403TheHostWiresTheScreenToTheRadio, testS14403TheScreenOffersTheSend
S-14404 → test/diagnostics_file_receive_source_test.dart · the plugin keeps the diagnostics log file
S-14405 → test/diagnostics_merged_text_test.dart · 6 tests (interleave, equal times, empty watch log,
no attach = shareText, null receivedAt, torn line)
S-14406 → test/settings_diagnostics_watch_log_test.dart · 5 tests (counts, singular, no watch log,
Copy to clipboard, empty phone log with watch log)
S-14407 → test/diagnostics_received_storage_test.dart · 3 tests (modified(), file round-trip, stub)

## Resolution (lead, 2026-11-11)

1. Fixed: QA step 40 now says `Watch log received <UTC time>`.
2. Fixed in the doc: `failed` is a defined outcome no path produces today.
3. Plan table now names the one-line update of `WatchDiagnosticsSourceTests.swift`.
4. Accepted: two Sends within the same second would share a snapshot name, and the temp snapshots accumulate until the system purges them; whether `transferFile` reads the file late is settled on a device (QA step 40, A-1).

Verified: whole Swift suite 1346 tests, 0 failures; watch app `xcodebuild` BUILD SUCCEEDED; the plugin method type-checks against the iOS SDK (the iOS runner itself was not built here); `flutter test` +7373 ~2 all passed on the final run (two earlier full runs showed 7 and 4 unrelated failures in `pre_release_gate_*` and `logger_feedback_controls_test`, which pass alone and on rerun: load-dependent flakes); `flutter analyze` 181 (baseline); mutation pass: 13 mutants, all killed.
