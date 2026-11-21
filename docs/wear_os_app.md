# The Wear OS App

**Scope.** The Android wrist app: its build target, the shell that hosts the
wrist surfaces, and the radio that carries frames between the two devices. The
client it hosts is the shared Dart wrist code in `lib/watch/` — the same engine,
storage and surfaces the watchOS package mirrors — so this page is about the
shell, the transport and the Android build, not about what the wrist logs. What
a wrist session becomes on the phone is
[Watch Session Capture](watch_session_capture.md); which session is whose across
the two devices is [Watch Session Sync](watch_session_sync.md); the models the
wrist stores are in [Data Models — watch](data_models_watch.md); the hands-on
guide to installing and exercising either wrist is
[Wearable App — Setup and QA](watch-app-setup-and-qa.md). The Apple shell and the
Swift client are described in
[State Management — the Wrist's Half](state_management/watch_surface_wrist.md).

## Two devices, one project

The phone app and the wrist app are the same Flutter project. What separates
them is an Android product flavor and a Dart entry point:

| | Phone | Wear OS |
|---|---|---|
| Flavor | `phone` | `wear` |
| Entry point | `lib/main.dart` | `lib/watch/wear_main.dart` |
| Manifest | `android/app/src/main/AndroidManifest.xml` | the same, merged with `android/app/src/wear/AndroidManifest.xml` |
| Advertised capability | `omnitrain_phone` | `omnitrain_wear` |
| Minimum SDK | 26 | 30 |
| It has, the other does not | the whole app | the watch feature in its manifest |

Both flavors keep the application id `dev.sasha.omnitrain`, so one Play listing
is meant to carry both and the watch feature is what routes one of them to a
watch. Today the wrist APK is built and installed directly.

```
flutter build apk --release --flavor wear -t lib/watch/wear_main.dart
flutter build appbundle --release --flavor phone
```

Every Flutter build has to name a flavor now, including the release workflow and
the pre-release gate (`scripts/pre_release_check.sh`), which look for the
flavored artifact first and an unflavored one second so an artifact left by an
older build is still inspected.

## The radio

`packages/omnitrain_watch_link/` is one plugin over two platforms:
`WCSession` on iOS, the Wear data layer on Android. The Dart side
(`WatchLink`, two channels) is the same for both, so every layer above it —
`WatchConnectivityChannel`, `WatchConnectivityTransport` and the phone's watch
graph — is platform-blind.

The Android half runs on **both** devices, because both apps compile it. It
learns which role it is playing from the device's own feature set, and it looks
for the peer by the other side's capability. The two capabilities are declared
in each flavor's `res/values/wear.xml`, so a peer that is installed is known
before it ever launches a sync.

The five calls mirror the watchOS plugin: `status`, `sendMessage`,
`transferUserInfo`, `outstandingTransfers`, `cancelTransfers`. The four event
kinds are the same: `message`, `userInfo`, `reachability`, `state`.

Where the two platforms differ is the queue. watchOS has `transferUserInfo` and
`outstandingUserInfoTransfers`; Android has the data layer, so a queued frame
becomes one data item under its own `messageId`, carried when the two devices
next meet. One rule follows from that and is worth knowing when reading the
transport's queue tests: a data item is deleted by whichever side takes it, so
the sender's list of outstanding frames shrinks when the peer receives one, not
only when the sender withdraws it.

A frame is serialized as JSON on Android rather than carried as a property list,
with explicit nulls preserved, because the protocol uses a null to clear a
timer.

## The shell

`WearApp` (`lib/watch/app/wear_app.dart`) is what the wrist launches. It is
handed an engine, the start paths, the nutrition state, the orchestrator and the
transport — everything injected, which is what lets a desktop test build it over
an in-memory store and a fake link.

It decides one thing: which surface is on screen. A running session shows the
logging surface; a running rest shows the rest surface; anything else shows the
start surface. Nutrition is pushed over the top, so the platform's own back
gesture returns to the session. While a session runs, one rebuild a second keeps
countdowns and the rest clock moving; with nothing running there is nothing to
tick.

The shell owns three things besides layout:

- **The launch sequence.** Restore the engine, the start paths and the nutrition
  state from the wrist's own storage, then start the radio and catch up.
- **Inbound frames.** A request frame asking for the wrist's state is answered
  with the wrist's snapshot; every other frame goes to `WatchSyncOrchestrator`,
  which routes it to the roster catalogue, the food list, or the engine. Frames
  are handled one at a time in arrival order.
- **The app's own lifecycle.** A resumed app catches the wrist up when the phone
  is reachable.

`WearWatchTransport` (`lib/watch/app/wear_watch_transport.dart`) is the wrist's
radio over the link package. Reachability is the platform's answer, re-read
rather than cached; a durable frame — a logged observation, a lifecycle message,
a session start, or the snapshot of a workout still running — is handed to the
OS queue when the radio refuses it, and anything else is reported and dropped
for the next sync to re-send. Its durability table is the same one the Swift
`WatchConnectivityBridge` uses.

The wrist stores everything in its own Hive directory (`omnitrain_watch`), so a
watch never shares a box with anything else on the device.

## What the wrist shows

The start surface (synced routines, free training, the quick-log entry, a manual
sync), the logging surface (one effort, its values, one Log), the rest surface
(the elapsed rest and one Next), and the nutrition quick-log. A stopgap End
control under the logging surface finishes the workout; it stands in for the
Apple wrist's exercise menu until that menu is ported.

The Apple wrist hosts more: the swipe pager between exercises, the exercise
menu, the effort-rating prompt, the personal-record banner, the water bar, the
workout summary, the diagnostics view, spoken timer cues and the accent
theming. None of those is on the Wear wrist; the plan that built this shell
records each one, and the sizes they are (the Apple client is roughly twice the
Dart client), in
[the plan](plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md).

Live sensors are the same story. `WatchSensorSource` is the seam a platform
satisfies; on Wear OS the live feed is the health-services exercise client
rather than HealthKit, and the shell passes no source yet, so the wrist logs
without heart rate and distance exactly as it would on a device with no sensor.

## How it is verified without a watch

- `test/wear_watch_transport_test.dart` — reachability, the request frames, the
  durable queue, the non-durable drop, the radio-safe rewrite, arrival order,
  and the durability table.
- `test/wear_app_test.dart` — the shell's choice of surface and the two ways it
  handles an arriving frame, over an in-memory store.
- `test/wear_os_config_test.dart` — the flavors, the watch feature, the two
  capabilities, the plugin's Android registration and its five calls, the
  production entry point, and the two release invocations.
- `flutter build apk --flavor wear -t lib/watch/wear_main.dart` — the build
  target itself.
- `test/watch_transport_test.dart` — the phone's side, including the platform
  choice that now includes Android.

What none of those can prove is that the two devices pair and carry a frame.
That is the paired-device level of
[Wearable App — Setup and QA](watch-app-setup-and-qa.md), and it needs a watch.

> **Doc freshness** — Derived from `lib/watch/`, `android/app/` and
> `packages/omnitrain_watch_link/` on 2026-11-20. If a claim here disagrees with
> the source, the source wins.
