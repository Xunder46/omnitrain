# Plan — 143: the phone keeps a diagnostics log of the watch link, and Settings copies it

**Status**: seeded by the lead 2026-11-10; not built.
**Base commit**: `3dea8055` (branch `claude_develop`).
**Parent**: the watch overview of 2026-11-10 (recommendation A); sibling of plan 142 (the watch's own log, committed `3dea8055`).

## Overview

Owner (2026-11-10): the watch app restarted mid-session and nothing explained it. Plan 142 gave the watch a log. This plan gives the phone the same kind of record of its side of the watch link, and a button in Settings that copies it, so a device report can carry both ends' timelines. It changes no sync, workout or timer behaviour.

What the user sees: in Settings, in the APPLE WATCH section (which exists only on a phone that can talk to a watch), a second row "Diagnostics", subtitle "N events", with "Copy" on the right. Tapping it copies the whole log as text to the clipboard (a few header lines — app version, platform, number of events — then one line per event, oldest first) and says "Diagnostics copied". Paste it into Notes or a message.

Not in this plan: getting the watch's log onto the phone (a later unit: it needs a file transfer in the native plugin), and logging the phone's own validation refusals (the transport sees every frame arrive; the mirror's refusal is not logged yet).

## Goal and acceptance

Acceptance: S-14301 .. S-14316; `flutter analyze` stays at the baseline (181 issues, 0 errors); every existing test stays green UNCHANGED (the Settings watch-status tests S-6910..S-6914 included).

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-14301 | New `DiagnosticsLog` (`lib/core/services/diagnostics_log.dart`), a Dart twin of the watch's `WatchDiagnosticsLog`: `note(kind, {session, detail, coalesce})`, `noteLaunch()`, `events()`, `shareText(header)`; the same bound (newest 3000, rewritten to 3000 when 3300 lines are reached; a rewrite that fails or a read that finds nothing leaves the file and backs the count off to the capacity), the same 60 s coalescing with an `x<n>` count, detail cut to 120 characters with newlines flattened, UTC ISO-8601 times, every failure swallowed. Storage sits behind a small `DiagnosticsStorage` interface (read lines, append a line, rewrite) with a file implementation (`phone-diagnostics.jsonl` under `<app support>/watch-diagnostics/`) chosen by the same conditional export `startup_failure_diagnostic_writer.dart` uses, and an in-memory stub for web | `lib/core/services/startup_failure_diagnostic_writer*.dart`; plan 142 D-14201 |
| D-14302 | Every collaborator takes `diagnostics: DiagnosticsLog? = null`: null records nothing and changes nothing | plan 142 D-14202 |
| D-14303 | `WatchConnectivityTransport` notes: `frame_sent` (`<type> delivered`, `<type> queued`, `<type> undelivered`, or `<type> failed: <reason>` when the radio threw), `frame_received` (`<type>`, before the handler runs), `frame_handler_failed` (`<type> <reason>`), `reachability` (`reachable`/`unreachable`, in `_reachabilityChanged`), `link_error` (`<reason>` at the other `_report` sites). `energy_live` sent and received is coalesced (`coalesce: 'frame_sent/energy_live'`). A `<reason>` is `PlatformException` code, `timeout` for a `TimeoutException`, else the error's `runtimeType`, never its message | `lib/core/platform/watch_transport.dart` `send` ~:346, `_queue` ~:376, `_dispatch` ~:437, `_handle` ~:446, `_reachabilityChanged` ~:289 |
| D-14304 | `DiagnosticsLifecycleObserver` (`lib/core/services/diagnostics_lifecycle_observer.dart`), a `WidgetsBindingObserver` that notes `app_lifecycle` with the state's name (`resumed`, `inactive`, `hidden`, `paused`, `detached`) for EVERY state; `lib/main.dart` registers it once. `main.dart` also calls `noteLaunch()` right after building the log | `lib/state/watch/watch_resume_sync.dart:40-62` handles only `resumed` |
| D-14305 | `lib/main.dart` `_runStartup` builds the log once before `createWatchSync`, passes it to `createWatchSync(diagnostics:)`, which hands it to `createPlatformWatchTransport(diagnostics:)` and so to the transport, and to `MyApp(diagnostics:)` and on to `SettingsScreen` | `lib/main.dart:370-393`; `lib/state/watch/watch_sync_wiring.dart:223-239`; `lib/core/utils/platform_watch_transport_factory.dart` |
| D-14306 | `SettingsScreen` gets `diagnostics: DiagnosticsLog?`; inside the existing `if (widget.watchLinkState != null)` block, after `_WatchSection`, a `Diagnostics` row (the file's `_SettingsRow` with `onTap`) in its own `OmniSurface`; tapping copies `shareText` to the clipboard (`Clipboard.setData`) and shows a `SnackBar` "Diagnostics copied". The header is `OmniTrain phone diagnostics`, `App <version> (<build>)`, `Platform <iOS/Android>`, `Events <n>`, `Copied <UTC time>` | `lib/features/settings/settings_screen.dart:134-157, 968-1010, 1011` |
| D-14307 | Privacy as plan 142 D-14211: types, session ids, outcomes and short reasons only; never an exercise name, a weight, a food, a typed number, or an error message | owner policy: private data |

## Input-reality checklist

- **Writers and units.** One isolate, so no lock; sync file operations (`writeAsStringSync` append) so two events can never interleave; times are UTC ISO-8601, shown as written.
- **Lifecycle.** A kill mid-append leaves a torn last line, skipped on read, the next append starts on a fresh line. `detached` may never be seen (the system kills a suspended app); the previous run's last recorded state is what `launch`'s `previous=` names.
- **Settings changing while open.** The row's count is read when the screen builds and after a copy; it does not tick live.
- **Time edges.** Events are ordered by append, not by timestamp.
- **Load cost.** One small sync append per frame, `energy_live` coalesced to one line a minute; one rewrite per 300 events beyond the bound; `shareText` reads the file only on a tap.
- **Wording.** "Diagnostics", "N events", "Copy", "Diagnostics copied" (and "Nothing recorded yet" when empty, copy disabled).
- **Slot competition.** One extra row in a section that already exists; nothing moves above it.
- **Readers that wait.** None.

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-14301 | a log notes 3 events; a new log over the same directory | same 3 events, same order | the type does not exist |
| S-14302 | capacity 20, slack 2, 30 notes | newest 20 (`n11`..`n30`) in order; file at most 22 lines; a new log over it reads the same | the type does not exist |
| S-14303 | a file with a good line and a fragment cut mid-record (no newline), then one note | the fragment is skipped, the new event reads back | the type does not exist |
| S-14304 | storage under a path that cannot be created | `note` never throws, `events()` is empty | the type does not exist |
| S-14305 | run 1 notes `app_lifecycle` `paused`; run 2 `noteLaunch()` | `launch` detail `previous=app_lifecycle/paused@<ISO>`; empty file: `previous=none` | the type does not exist |
| S-14306 | 30 coalesced notes over 20 s, one more at +61 s | `... x1`, then `... x30`; another key in the window records on its own | the type does not exist |
| S-14307 | a 300-character detail with a newline at character 10 | stored at most 120 characters, newline gone | the type does not exist |
| S-14308 | `shareText` over 2 events with a 3-line header | the header lines, then `<ISO time> <kind> s:<session> <detail>` per event, oldest first | the type does not exist |
| S-14309 | the transport over the loopback `_Endpoint` (`test/watch_transport_test.dart`): a send that is delivered; a durable frame while unreachable (queued); a non-durable one while unreachable; a channel that throws `StateError('rating 97531')` | `frame_sent` `<type> delivered` / `queued` / `undelivered` / `failed: StateError`, and no `97531` anywhere | no hooks exist |
| S-14310 | 30 `energy_live` frames sent and 30 received over 20 s, then one more each at +61 s | one `frame_sent` and one `frame_received` line per minute (`x1` then `x30`) | no coalescing at the hooks |
| S-14311 | a frame arrives: with a handler; with a handler that throws `StateError('rating 97531')`; with a handler that outlasts the timeout | `frame_received`; `frame_handler_failed` ending `StateError` (no `97531`); `frame_handler_failed` ending `timeout` | no hooks exist |
| S-14312 | the channel reports reachable, then unreachable | `reachability` `reachable`, `reachability` `unreachable` | no hook exists |
| S-14313 | the S-14309 fixtures with a working log, a log over unwritable storage and `diagnostics: null` | the same `WatchDelivery` answers, the same frames at the endpoint and the same handler calls in all three | guard of "observation only" |
| S-14314 | `DiagnosticsLifecycleObserver.didChangeAppLifecycleState` for each `AppLifecycleState` | one `app_lifecycle` event per state, detail the state's name | the observer does not exist |
| S-14315 | Settings with a watch link state and a log of 2 events; the same without a link state; tap the row | the row `Diagnostics` / `2 events` / `Copy` shows only with the link state; tapping puts the share text on the clipboard and shows `Diagnostics copied`; an empty log shows `Nothing recorded yet` and a tap copies nothing | the row does not exist |
| S-14316 | source guards on `lib/main.dart` (exact statements with their brackets) | the log is built, `noteLaunch()` is called, the observer is registered, `diagnostics:` is passed to `createWatchSync` and `MyApp` | the app has no log |

## Phases

| Phase | Agent | Items | Write scope | Parallel |
|---|---|---|---|---|
| P1 | crew-builder-app | the log type, storage interface, io and stub, `shareText`, their tests (S-14301..S-14308) | `lib/core/services/diagnostics_log.dart`, `diagnostics_storage.dart`, `diagnostics_storage_io.dart`, `diagnostics_storage_stub.dart`, `test/diagnostics_log_test.dart` | serial |
| P2 | crew-builder-app | the transport hooks, the lifecycle observer, the wiring, tests (S-14309..S-14314, S-14316) | `lib/core/platform/watch_transport.dart`, `lib/core/utils/platform_watch_transport_factory.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/core/services/diagnostics_lifecycle_observer.dart`, `lib/main.dart`, `lib/app.dart`, `test/diagnostics_watch_transport_test.dart`, `test/diagnostics_lifecycle_test.dart`, `test/diagnostics_wiring_source_test.dart` | after P1 |
| P3 | crew-builder-app | the Settings row and its widget test (S-14315) | `lib/features/settings/settings_screen.dart`, `test/settings_diagnostics_test.dart` | after P2 |

## Progress

| Item | Status |
|---|---|
| seed | Done |
| P1, P2a, P2b, P3 | Done |
| docs, review | Done |
| device check QA step 39 | Open (owner) |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | No architect phase; the lead seeded from two scout sheets and plan 142 | cost discipline |
| A-2 | A "Copy" button (clipboard), not a share sheet: a share sheet needs the `share_plus` package, a native pod and a project-file change; a paste into Notes does the same job | scout: no share package in `pubspec.yaml` |
| A-4 | A `frame_dropped` note (no handler bound) was dropped from the seed: the transport attaches its message listener only after binding the handler, so that branch is unreachable | P2a builder report |
| A-3 | The log also runs on Android builds where there is no watch link: its lifecycle events are recorded, the Settings row shows only with a watch link state | `createPlatformWatchTransport` returns null off iOS; the Wear OS client is a later project |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_diagnostics.md | MODIFIED | `**The phone.** The phone's own log (plan 143)` | `**The phone.** The phone keeps its own log` | S-14301 |
| docs/theme_and_settings.md | MODIFIED | `The APPLE WATCH section is the one read-only status readout` | `Copy diagnostics` | S-14315 |
| docs/watch-app-setup-and-qa.md | ADDED | - | `Copying the phone diagnostics` | S-14315 |
