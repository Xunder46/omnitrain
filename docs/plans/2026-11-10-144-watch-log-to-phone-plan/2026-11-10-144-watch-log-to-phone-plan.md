# Plan — 144: the watch sends its diagnostics log to the phone, and Copy gives both timelines

**Status**: seeded by the lead 2026-11-10; not built.
**Base commit**: `eee2179a` (branch `claude_develop`).
**Parents**: plans 142 (the watch's log) and 143 (the phone's log and the Settings Copy row).

## Overview

Owner (2026-11-10): a device report should carry both devices' timelines without screenshots of a tiny watch screen. This plan lets the watch send its whole log to the phone on request, and makes the phone's Copy row paste both logs together, merged by time.

What the user sees:
- On the watch, the Diagnostics screen has a "Send to phone" button at the bottom. After a tap it says "Sent. The phone has it when it next wakes." (or "Install the OmniTrain app on the phone." / "Phone link not ready." / "Could not send.").
- On the phone, Settings → APPLE WATCH → Diagnostics reads "N events · watch log M events" once a watch log has arrived. Copy puts both logs on the clipboard in one block, oldest first, each line tagged `[phone]` or `[watch]`, with a header line "Watch log received HH:mm" (or "Watch log not received").

It is user-initiated and separate from the sync: it uses the system's file transfer, never the sync frames, so it cannot change what syncs.

## Goal and acceptance

Acceptance: S-14401 .. S-14407; the watch app builds (`xcodebuild`); the iOS runner builds with the plugin change (`flutter build ios --debug --no-codesign`); `flutter analyze` stays at 181 (0 errors); all existing tests stay green UNCHANGED. Not provable on a simulator (it does not deliver watch-to-phone transfers): QA step 40 is an owner device check.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-14401 | `WatchDiagnosticsLog.snapshotFile(into:)` (package): under the log's lock, copies the log file to `<directory>/watch-diagnostics-<UTC yyyyMMdd'T'HHmmss'Z'>.jsonl` (default the temp directory) and returns its URL, or nil when the log holds no event or the copy fails | plan 142 D-14201 |
| D-14402 | `WatchDiagnosticsSendOutcome` (package enum: `sent`, `phoneAppMissing`, `notReady`, `failed`) with a plain `message` each; `WatchDiagnosticsView(log:onSend:)` gets `onSend: ((URL) -> WatchDiagnosticsSendOutcome)? = nil` and, when set, a last bordered button "Send to phone" that snapshots the log, calls `onSend`, and shows the outcome's message under it (nothing to send: "Nothing to send.") | `WatchDiagnosticsView.swift` |
| D-14403 | App target: `OmniTrainWatchConnectivity.sendDiagnostics(_:)` answers `.notReady` unless `WCSession.isSupported()` and the session is `.activated`, `.phoneAppMissing` unless `isCompanionAppInstalled`, else `transferFile(url, metadata: ["kind": "diagnostics_log"])` and `.sent`; `WatchAppHost` keeps the radio and exposes `sendDiagnostics(_:)`; `ContentView` passes `onSend:` to the view | `OmniTrainWatchConnectivity.swift`, `ContentView.swift` |
| D-14404 | Plugin `OmniTrainWatchLinkPlugin`: `session(_:didReceive file: WCSessionFile)` handles only `metadata["kind"] == "diagnostics_log"`: copies the file synchronously (the system deletes it when the callback returns) to `<Application Support>/watch-diagnostics/watch-received.jsonl`, replacing the previous one, and notes it with `NSLog`; it emits nothing to Dart | `packages/omnitrain_watch_link/ios/Classes/OmniTrainWatchLinkPlugin.swift:248-262` |
| D-14405 | `DiagnosticsLog` gets `attachWatchReceived(storage, receivedAt)` (called by `main.dart` right after the existing construction statement, which stays as it is), a `watchEvents()` (the events of that storage, same line shape) and `shareTextWithWatch({header})`: with no attached storage it returns exactly `shareText(header: header)`; with one attached it returns the header, `Watch log received <UTC time>` (or `Watch log not received` when it holds no event, `Watch log received (time unknown)` when the time is null), `Times are each device's own clock` (only when the watch log holds events), then both logs' events merged by time (phone first on ties, then in stored order), each line `<UTC time> [phone|watch] <kind>[ s:<session>][ <detail>]`. `shareText` is unchanged | `lib/core/services/diagnostics_log.dart` |
| D-14406 | `diagnostics_storage_default*.dart` gain `openWatchReceivedStorage()` answering a `WatchReceivedSource` (storage plus a `receivedAt` function; io: `FileDiagnosticsStorage` on `watch-received.jsonl` in the same directory with the file's modification time, and the same 2-second timeout fallback as the phone log; stub: in-memory, empty, `receivedAt` null); `lib/main.dart` attaches it; the Settings row's subtitle reads `N events` plus ` · watch log M events` when `watchEvents()` is not empty, and Copy uses `shareTextWithWatch` | `lib/main.dart`, `lib/features/settings/settings_screen.dart` `_DiagnosticsRow` |
| D-14407 | Privacy as plans 142 and 143: the log holds types, session ids, outcomes and short reasons only, so sending it moves no workout content | plans 142/143 D-14211, D-14307 |

## Input-reality checklist

- **Writers and units.** The watch's snapshot is taken under the log's lock, so a note arriving mid-copy is either in or out, never torn; the phone writes `watch-received.jsonl` once per received file, replacing the previous one atomically (write to a temp name, then replace).
- **Lifecycle.** A transfer outlives the watch app (the system delivers it when the phone next runs); the phone may receive it while backgrounded: the plugin callback copies at once. A newer transfer replaces the older file. A file the system could not copy leaves the previous file in place.
- **Settings changing while open.** The row's counts are read when the screen builds and after a copy.
- **Time edges.** Both logs are UTC; their clocks are two devices' clocks (a skew of seconds is possible): the merge says so in the header line `Times are each device's own clock`.
- **Load cost.** One file of at most ~360 KB per send; read only on a Copy tap or when the Settings row builds (count only, once).
- **Wording.** "Send to phone", "Sent. The phone has it when it next wakes.", "Install the OmniTrain app on the phone.", "Phone link not ready.", "Could not send.", "Nothing to send."; phone: "N events · watch log M events", "Watch log received <time>", "Watch log not received".
- **Slot competition.** One extra button at the bottom of the watch's Diagnostics screen (it is already the last thing on a scrolling screen); no new phone row.
- **Readers that wait.** None: no spinner, timeout or retry reads the transfer.

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-14401 | a log with 3 events; `snapshotFile(into: <temp dir>)`; then an empty log; then an unwritable target | the snapshot file's lines equal the log's file lines and its name matches `watch-diagnostics-<15-char UTC stamp>.jsonl`; empty log: nil; unwritable target: nil | the function does not exist |
| S-14402 | each `WatchDiagnosticsSendOutcome` | the four messages in the plan's Wording row, exactly | the enum does not exist |
| S-14403 | source guards (exact statements with their braces) in `OmniTrainWatchConnectivity.swift`, `ContentView.swift`, `WatchDiagnosticsView.swift` | `isCompanionAppInstalled`, the `.activated` check, `transferFile(url, metadata: ["kind": "diagnostics_log"])`, `onSend: { url in host.sendDiagnostics(url) }`, the button's `Text("Send to phone")` | the app target cannot send |
| S-14404 | source guards on the plugin file (read by a Dart test) | `didReceive file: WCSessionFile`, the `kind` check, the destination `watch-received.jsonl`, the copy happens before the method returns (no `Task`/`async` around it), the old file replaced | the plugin ignores files |
| S-14405 | a phone log of 2 events and a watch-received log of 2 interleaved events (times 06:00:00, :01, :02, :03), `watchReceivedAt` 06:05:00Z | `shareTextWithWatch(header)` = header lines, `Watch log received 2026-07-13T06:05:00Z`, `Times are each device's own clock`, then the 4 events in time order tagged `[phone]`/`[watch]`; equal times: phone first; a `watchReceived` storage that is empty: `Watch log not received`, then the phone events tagged `[phone]`; no `watchReceived` at all: exactly `shareText` | the method does not exist |
| S-14406 | Settings with a log whose `watchReceived` holds 3 events, and with none | subtitle `2 events · watch log 3 events`, and `2 events`; Copy puts the merged text on the clipboard | the row ignores the watch log |
| S-14407 | `openWatchReceivedStorage()` io over a temp directory file, and the stub | io: reads what a test wrote to the file; stub: reads empty | the function does not exist |

## Phases

| Phase | Agent | Items | Write scope | Parallel |
|---|---|---|---|---|
| P1 | crew-builder-watch | snapshot file, outcome enum, the view's button, the app target's send, tests (S-14401..S-14403) | `watch/watchos/Sources/WatchSessionEngine/WatchDiagnosticsLog.swift`, `WatchDiagnosticsSendOutcome.swift` (new), `WatchDiagnosticsView.swift`, `ios/OmniTrain Watch App/*.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchDiagnosticsSendTests.swift`, and the one-line update of `WatchDiagnosticsSourceTests.swift` (its guard for the sheet's opening) | with P3 |
| P3 | crew-builder-app | merged share text, storage, main, Settings row and tests (S-14405..S-14407) | `lib/core/services/diagnostics_log.dart`, `diagnostics_storage*.dart`, `lib/main.dart`, `lib/features/settings/settings_screen.dart`, new `test/diagnostics_merged_text_test.dart`, `test/settings_diagnostics_watch_log_test.dart` | with P1 |
| P2 | crew-builder-watch | the plugin's file receive and its Dart source-guard test (S-14404) | `packages/omnitrain_watch_link/ios/Classes/OmniTrainWatchLinkPlugin.swift`, `test/diagnostics_file_receive_source_test.dart` | after P1 (the writer cap is 2) |

## Progress

| Item | Status |
|---|---|
| seed | Done |
| P1, P2, P3 | Done |
| docs, review | Done |
| device check QA step 40 | Open (owner) |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | `WCSession.transferFile` and `session(_:didReceive file:)` behave as Apple documents (the file is queued, delivered when both apps run, deleted by the system after the callback returns); the simulator does not deliver them, so only a device settles it | simulator limit noted in the crew rules |
| A-2 | No architect phase | cost discipline, as plans 140-143 |
| A-3 | The watch log reaches the phone only when the owner taps Send; nothing is sent automatically | observation-only principle, owner policy on data |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_diagnostics.md | MODIFIED | `Not yet: the phone's own` | `Send to phone` | S-14401 |
| docs/watch-app-setup-and-qa.md | ADDED | - | `Sending the watch log to the phone` | S-14403 |
