# Plan 304 — The Wear wrist sends its diagnostics log to the phone (plan 280 leftover; the Apple wrist's plan 144)

The Wear Diagnostics screen (plan 293) only shows the log on the wrist. The Apple wrist has a "Send to phone" button that hands the phone its log, and the phone's Settings Copy row then pastes both timelines merged (plans 143/144). The phone's Dart half (merge, Settings row, `watch-received.jsonl` reader) is platform-blind and already exists. What is missing on Wear is the carrier: the plugin has no way to move bytes that are not a sync frame. Base commit: `1cc390ff`. Analyze baseline: 174 issues, 0 errors. Kotlin is lead-written (the crew cannot write under `android/`), and the gateway hangs for builders on this PC, so the lead builds and proves this unit and says so in the evidence file.

## Goal and acceptance

On a Wear watch, `Diagnostics` shows a last button `Send to phone`. A tap sends the whole log; the screen then says one of: `Sent. The phone has it when it next wakes.`, `Install the OmniTrain app on the phone.`, `Phone link not ready.`, `Could not send.`, `Nothing to send.` On an Android phone, the file lands at `<app support>/watch-diagnostics/watch-received.jsonl` (the path the existing reader opens), so Settings reads `N events · watch log M events` and Copy merges both logs, with no phone-side Dart change. The sync is untouched: the send never uses a sync frame.

Acceptance: S-30401..S-30408 green, each guard red without its change; `flutter analyze` at most 174 issues, 0 errors; the Wear and phone debug APKs build; Docs delta applied. Not provable without a pair: owner check 21.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-30401 | Carrier: ONE data item at `/omnitrain/diagnostics/watch-log` carrying the log text as an `Asset` (a data item's own payload is capped near 100 KB; an asset is not) plus `role` and `sentAt` (millis, so a second send is a change even when the text is equal). The data layer queues it until the phone is next in range: the same "when it next wakes" meaning as Apple's `transferFile`. Not `ChannelClient`: it needs both ends live. | Wear data layer; Apple plan 144 D-14403 |
| D-30402 | Plugin method `sendDiagnostics({text})` (watch role only; a phone answers `not_supported`): `not_supported` when Play services is missing, `phone_app_missing` when no peer declares the phone capability, `send_failed` when the put fails, else `null` (sent). A put replaces the previous item at the same path. | plugin pattern |
| D-30403 | Receive (phone role): `takeQueuedItem` (shared by the change event and the start-up read of plan 295) recognises the diagnostics path first: ignores an item whose `role` is its own, reads the asset through `getFdForAsset` on a background executor, writes `<filesDir>/watch-diagnostics/watch-received.jsonl.part` then renames it over `watch-received.jsonl` (the previous file stays when anything fails), then deletes the data item. `filesDir` is what `getApplicationSupportDirectory()` returns on Android. Nothing is emitted to Dart. | plan 144 D-14404/D-14406 |
| D-30404 | Dart `WatchLink.sendDiagnostics(String text)`: invokes the method; `PlatformException` becomes `WatchLinkException`; a missing method (the iOS plugin has none) becomes `not_supported`. | `watch_link.dart` |
| D-30405 | `DiagnosticsLog.rawText()` returns the stored text as is (what a send carries). `WatchDiagnosticsSendOutcome` (Dart enum: `sent`, `phoneAppMissing`, `notReady`, `failed`, `nothingToSend`) with the Apple wording. `WearWatchTransport.sendDiagnostics(text)` maps empty text to `nothingToSend`, `not_supported` to `notReady`, `phone_app_missing` to `phoneAppMissing`, anything else to `failed`, and records one `diagnostics_send` line (outcome word only) in the log. | Apple `WatchDiagnosticsSendOutcome.swift` |
| D-30406 | `WatchDiagnosticsScreen(log:, onSend:)`: with `onSend` set, a last 40 dp button `Send to phone` that disables while a send runs and shows the outcome's message under it. `WearApp` passes `() => transport.sendDiagnostics(log.rawText())`. | `wear_app.dart` `_openDiagnostics` |
| D-30407 | Privacy as plans 142/293: the log holds names, ids, outcome words and error types, never a payload value, so the file moves no workout content. Sent only when the user taps; never automatic. | plan 144 D-14407 |
| D-30408 | Not in scope: a wrist-side receipt (the phone never answers), a phone-side "received" refresh while Settings is open (the row reads at build, as on Apple), a send from the phone. | |

## Input-reality checklist

- **Writers/units.** The wrist's log is appended synchronously; the text is read once at the tap, so a line arriving mid-send is in or out, never torn. One item at one path: the newest send replaces an older one the phone never took.
- **Lifecycle.** The item outlives the wrist app (queued by the data layer). The phone may be closed: the start-up read takes it at next launch; the change event takes it live. The file is written to a temp name then renamed: a kill mid-write leaves the previous file.
- **Size.** At most ~3300 lines of about 120-200 bytes: under 700 KB, one asset.
- **Time.** Both logs are UTC on two clocks; the phone's merge already says so.
- **Wording.** The five outcome sentences above, exact.
- **Slot competition.** One extra button at the end of a scrolling screen: no overflow at 192/227 dp.
- **Readers that wait.** The button disables until the call completes; Dart guards the call with a 10 s timeout that reports `failed`.

## Scenarios

| ID | Fixture | Expect |
|---|---|---|
| S-30401 | channel mock: `sendDiagnostics` call; then PlatformException `phone_app_missing`; then MissingPluginException | args `{text: ...}` exact; `WatchLinkException` carries the code; missing method gives `not_supported` |
| S-30402 | `DiagnosticsLog.rawText()` with 3 events, and none | the stored lines exactly; empty string |
| S-30403 | transport `sendDiagnostics` over the channel mock | empty text: `nothingToSend`, no call; success: `sent`; `not_supported`: `notReady`; `phone_app_missing`: `phoneAppMissing`; `send_failed`/other/timeout: `failed`; each non-empty case leaves one `diagnostics_send <outcome>` line and no log text |
| S-30404 | outcome enum | the five messages, exactly |
| S-30405 | screen at 192/227 dp with 60 lines, `onSend` returning each outcome | button present and below the lines; tap shows the message; button disabled while pending; no overflow; without `onSend` no button |
| S-30406 | shell: `WearApp` with a log opens Diagnostics and taps Send | the transport call carries the log's raw text |
| S-30407 | Kotlin source guards: method registered, watch-only, error codes, asset put with `role`/`sentAt`, path constant | text present, in order |
| S-30408 | Kotlin source guards: `takeQueuedItem` handles the path first, role check, background executor, temp-then-rename, asset closed, item deleted after a good write only | text present, in order |

Mutation pass by the lead on every guard family (outcome mapping, empty rule, button disable, wiring, Kotlin guards).

## Phases

Single phase by the lead (Kotlin plugin, Dart link, log text, transport, screen, shell wiring, tests, docs).

## Docs delta

`docs/wear_os_app.md`: the diagnostics log paragraph (remove "Not built: sending the log", describe the send) and owner check 21. `.claude/crew.md` is the owner's file: not touched.

## Progress

| Item | Status |
|---|---|
| seed | Done |
| build, tests, mutation (34/35, 1 equivalent), docs | Done (evidence file) |
| commit | Done |
| device check owner check 21 | Open (owner) |
