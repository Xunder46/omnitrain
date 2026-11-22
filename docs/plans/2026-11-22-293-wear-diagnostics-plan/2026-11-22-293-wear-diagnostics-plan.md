# Plan 293 — The Wear wrist keeps a diagnostics log and shows it in debug builds (plan 280 open item 7)

The Apple wrist keeps a diagnostics log (plan 142: launches, scene phases, reachability, every sync frame with its outcome) and shows it on a Diagnostics screen from the Start screen; plan 177 hid the entry point from release builds while the log keeps recording; plan 144 sends the log to the phone as a file. The phone already has the Dart twin of the log (`lib/core/services/diagnostics_log.dart`, plan 143: same line shape, bound, coalescing and cut, so the two logs read together) and the entry rule (`lib/core/constants/diagnostics_entry.dart`). This plan gives the Wear wrist the same log by reusing that class and the same rule, and a screen that reads it. It is a debugging tool: nothing leaves the device unless the owner copies it (plan 142 D-14211: no payload value is ever logged). Wrist only (`lib/watch/` and the two existing core files read, not changed); no wire, phone, schema or Swift change. Base commit: `.work/2026-11-22-293-wear-diagnostics/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On a Wear watch the app records one line for: each launch (naming the last thing the previous run recorded), each app lifecycle change (`scene` active, inactive, background), each change of the phone's reachability, each frame it sends (`frame_sent` with `live` or `queued`; `frame_not_sent` with the error's type when the radio refuses it), each frame it receives (`frame_received`) and a handler that fails (`frame_handler_failed`). In debug and profile builds (and in release while `kHideDiagnosticsInRelease` is false) the Start screen shows a `Diagnostics` button that opens a screen with the plain sentences (`Started 09:12`, `Before that: last seen on screen at 09:10`, or `First run recorded.`; `No start recorded yet.`) and the newest 40 lines, newest first. Send-to-phone is not built (the platform plugin has no file transfer).

Acceptance: S-29301..S-29322 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the Wear files no new red; Docs delta applied.

## Feature invariants

- Observation only: nothing reads the log to decide anything, every call swallows its own failure (`DiagnosticsLog` guarantees it), and a collaborator holding null records nothing: a shell or transport built without a log behaves exactly as before.
- No payload value, id or body is ever written: a line carries the frame's type, the session id the frame names, an outcome word and an error's type.
- The log records in every build; only the entry point is gated.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29301 | The Wear wrist reuses the phone's `DiagnosticsLog` (storage: `openDefaultDiagnosticsStorage()`), not a second class: one rule for the bound (3000 lines, 300 slack), the torn line, the coalescing window and the cut (120 characters). | `diagnostics_log.dart` 31-60; plan 143 D-14301 |
| D-29302 | `WearWatchTransport` takes an optional `DiagnosticsLog? diagnostics`. `send` records `frame_sent` `<name> live` after the radio accepts a frame, `frame_sent` `<name> queued` when a durable frame went to the OS queue, and `frame_not_sent` `<name> <error type>` when neither worked; `_deliver` records `frame_received` `<name>` before the handler and `frame_handler_failed` `<name> <error type>` when it throws. `<name>` is the frame's `type`, else its request name, else `unknown`; each line names the frame's `sessionId` when it has one. | Apple `WatchConnectivityBridge.swift` 213-246, 395-410 |
| D-29303 | `WearApp` takes an optional `DiagnosticsLog? diagnostics`: `didChangeAppLifecycleState` records `scene` with `active` (resumed), `inactive` or `background` (paused, hidden, detached); the shell records `reachability` `reachable`/`unreachable` when the transport's answer differs from the last one it noted (checked at boot and on every tick). | Apple `ContentView.swift` 280, 590 |
| D-29304 | New pure type `WatchDiagnosticsSummary` (`lib/watch/diagnostics/watch_diagnostics_summary.dart`): `headline` (plain sentences) and `lines` (the newest 40, newest first, `HH:mm:ss kind detail s:<first 4 of the session>`), built from a log's events in the device's local time; the scene details read `in the background`, `on screen`, `dimmed` in the headline; a `recovery_relaunch` after the last launch adds ` — restarted by the system`. | `WatchDiagnosticsSummary.swift` |
| D-29305 | New screen `WatchDiagnosticsScreen(log:)` (`lib/watch/diagnostics/watch_diagnostics_screen.dart`): reads the log once when it opens, shows the headline sentences, a divider and the lines in a small monospace, in one scrolling list. | `WatchDiagnosticsView.swift` |
| D-29306 | `WatchStartScreen` takes an optional `onOpenDiagnostics`; with it a `Diagnostics` utility button sits under `Log food`. The shell passes it only when it holds a log and `kDiagnosticsEntryVisible` is true (the phone's rule, plan 177), and pushes the screen through its own navigator. | plan 177 D-17701..D-17703; `watch_start_screen.dart` 86-92 |
| D-29307 | `wear_main.dart` opens the default storage, builds one `DiagnosticsLog`, calls `noteLaunch()` before anything else records, and gives it to the transport and the shell. | `lib/main.dart` 383 |
| D-29308 | Not in scope: sending the log to the phone (plan 144: needs a file-transfer call in the `omnitrain_watch_link` Android half); recording workout, sensor or recovery events (the Wear wrist has no platform workout yet). | plan 144 |

## Input-reality checklist

1. **Writers.** The log: the shell (lifecycle, reachability), the transport (frames) and `main` (launch). Readers: the screen, once per open.
2. **Units.** None.
3. **Lifecycle.** Cold launch (a launch line naming the previous run's last line); resume/background cycles (scene lines); reachability flapping (one line per change, never per tick); a frame arriving before the shell is up (the transport records it when delivered).
4. **Settings changing while open.** None.
5. **Time.** The log's own clock; the summary formats in local time; a coalesced event is recorded at most once a minute (the log's rule).
6. **Load.** One synchronous append per event (the storage swallows failures); the screen reads the file once when it opens.
7. **Wording.** `Diagnostics`, `Started HH:mm`, `Before that: last seen <phrase> at HH:mm`, `First run recorded.`, `No start recorded yet.` as the Apple wrist says them. Stale wording: `docs/wear_os_app.md` lists the diagnostics view among the Apple-only items (the Docs delta); the shell header comment names it as not hosted (fixed in P1).
8. **Slot competition.** One more utility button on the Start screen, only in debug and profile builds; the screen is a scrolling list that cannot overflow.

## Scenarios

Summary (`test/wear_diagnostics_summary_test.dart`, new, plain `test()`):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29301 | no events | headline `No start recorded yet.`; no lines | the empty case differs |
| S-29302 | one `launch` event | headline `Started HH:mm` and `First run recorded.` (the time in local time) | the first-run sentence is missing |
| S-29303 | events: `scene background`, then `launch` | `Before that: last seen in the background at HH:mm`; the other phrases: `scene active` -> `on screen`, `scene inactive` -> `dimmed`, anything else -> its kind | the phrases are wrong |
| S-29304 | a `recovery_relaunch` after the last launch | the first sentence ends ` — restarted by the system`; one before the last launch does not | the restart note is missing or misplaced |
| S-29305 | 45 events | 40 lines, newest first; the oldest five are absent | the limit or the order is wrong |
| S-29306 | one event with a detail and a session id of six characters; one without | `HH:mm:ss kind detail s:abcd`; `HH:mm:ss kind` | the line format differs |
| S-29307 | two launches | the headline reads from the LAST launch | the first launch is used |

Transport (`test/wear_diagnostics_transport_test.dart`, new; the channel mocks of `wear_watch_transport_test.dart`, an in-memory log with a fixed clock):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29310 | a live send of an `observations_up` frame naming a session | one `frame_sent`, detail `observations_up live`, the session id | nothing is recorded |
| S-29311 | a durable frame the live send refuses | `frame_sent` `<name> queued`; and when the queue refuses too, `frame_not_sent` `<name> <error type>` | the queued and failed outcomes are missing |
| S-29312 | a non-durable frame refused | `frame_not_sent` with the error's type, and no payload value anywhere in the log text | a refusal is silent, or a value leaks |
| S-29313 | a request frame (`{request: 'routines'}`) sent | the name is `routines`; a frame with neither type nor request is `unknown` | the name rule is wrong |
| S-29314 | an inbound frame delivered | `frame_received` with its name, before the handler runs | arrivals are not recorded |
| S-29315 | a handler that throws | `frame_handler_failed` with the error's type; the lane still delivers the next frame | a failure is silent |
| S-29316 | a transport built with no log | every path works and nothing throws | a null log crashes |

Shell (`test/wear_diagnostics_shell_test.dart`, new; in-memory store, Mock-first, explicit pumps):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29317 | the shell with a log; the lifecycle moves resumed -> inactive -> paused -> resumed | `scene` lines `inactive`, `background`, `active` (in that order) | the lifecycle is not recorded |
| S-29318 | the radio's answer flips unreachable -> reachable -> reachable -> unreachable over several ticks | exactly three `reachability` lines (the first answer at boot, then each change), never one per tick | per-tick or missing lines |
| S-29319 | the Start screen with a log vs without | with: a `Diagnostics` button; without: none | the button is missing, or shown with no log |
| S-29320 | tap `Diagnostics` | the screen opens through the shell's navigator and shows the headline and the lines | the entry does not open it |
| S-29321 | the screen at 192x192 and 227x227 dp with 40+ lines | no overflow; scrolls | it overflows |
| S-29322 | `wear_main.dart` (a source scan) | one `DiagnosticsLog(storage: await openDefaultDiagnosticsStorage())`, `noteLaunch()` once, `diagnostics: diagnostics` twice (transport and shell) | the entry point does not wire it |

Guard families the lead proves by mutation: each frame outcome and its name rule, the order of the received line before the handler, the error's type and the absence of payload values, the lifecycle mapping, the reachability change rule, the summary's phrases, limit, order and last-launch rule, the button's gate, the screen's open, the entry wiring.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — summary, screen, transport, shell, start screen, entry point** (`crew-builder-watch`; scope `lib/watch/diagnostics/watch_diagnostics_summary.dart` (new), `lib/watch/diagnostics/watch_diagnostics_screen.dart` (new), `lib/watch/app/wear_watch_transport.dart`, `lib/watch/app/wear_app.dart`, `lib/watch/start/watch_start_screen.dart`, `lib/watch/wear_main.dart`). Exact code in the brief. About 260 lines.
2. **P2 — tests** (lead): the three new files.
3. **P3 — docs** (lead).
4. **Lead:** analyze, readers, mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | ## The diagnostics log | S-29310 |
| docs/wear_os_app.md | ADDED | - | `test/wear_diagnostics_summary_test.dart` | S-29301 |
| docs/wear_os_app.md | ADDED | - | 13. (owner) on a Wear watch in a debug or profile build | S-29320 |

The Apple-only list loses "the diagnostics view," (hand edit). Plan 280's open item 7 is a plan record ("built by plan 293; send-to-phone not built").

## Assumption Log

- `DiagnosticsLog.events()` returns the stored events oldest first, each a `DiagnosticsEvent` (`at`, `kind`, `session`, `detail`).
- `openDefaultDiagnosticsStorage()` resolves a file in the app's documents directory on Android (`diagnostics_storage_default_io.dart`) and the in-memory storage on the web.
- `kDiagnosticsEntryVisible` is true in `flutter test` (a debug build), so the shell tests see the button; the gate's truth table is the phone's own test (`diagnosticsEntryVisibleFor`).

## Progress

- [x] P1 production (crew builder)
- [x] P2 tests (lead; S-29301..S-29322)
- [x] P3 docs (lead)
- [x] Verify and prove (analyze 174; 265 Wear tests, one pre-existing red; 30 of 31 mutants killed, one equivalent)
- [ ] (owner) check 13 in `docs/wear_os_app.md` on a watch
