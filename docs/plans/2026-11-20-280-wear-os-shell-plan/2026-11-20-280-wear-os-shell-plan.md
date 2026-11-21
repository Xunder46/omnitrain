# Plan 280 — The Wear OS app: shell, radio and build target

Owner request (2026-11-20): "Apple watch app implementation is complete, but the
android version is behind. Bring the android watch app up to date with the apple
watch." Owner chose the shell-first split, with no watch or emulator available to
verify against.

This is the first PR of that series. It builds the host the Dart wrist client
never had: the Android build target, the production wrist entry point, the shell
that hosts the surfaces, and the phone↔watch radio. Closing the surface gap with
the Apple wrist (the pager, the menu, the rating prompt, the record banner, water,
the summary, diagnostics, accent, live sensors) is later PRs — this PR records
each one so none is lost.

Tracks: the phone app (`lib/core/`, `lib/main.dart` untouched), the wrist client
(`lib/watch/`), and the Android/Wear build. Three tracks is a soft budget signal;
the PR is one shell plus one radio and the plan stays short, so it is not split
further.

## Goal and acceptance

On a Wear OS device (or emulator), the `wear` flavor installs and launches the
wrist app: the start surface lists the routines the phone sent, a session starts
and logs, a rest counts up and ends, and a frame the phone sends is applied — all
over the Wear data layer rather than `WCSession`. The phone app's own watch graph
now runs on Android too, because the factory no longer excludes it.

Acceptance: `flutter build apk --flavor wear -t lib/watch/wear_main.dart` produces
an APK whose manifest declares the watch feature; `flutter build appbundle
--release --flavor phone` still works for the phone; S-28001..S-28035 green;
`flutter analyze` no worse than the 176-issue baseline with 0 errors; no new red
in `flutter test`.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28001 | The wrist app is a **product flavor of the one Flutter project** (`phone` / `wear`), not a second Gradle module and not a second project. The Flutter tool drives flavors (`--flavor`), so `flutter run` and `flutter build` work on a watch unchanged; a second module would be buildable only through raw Gradle. | `flutter_tools/gradle` `getFlutterTarget` reads the target the tool passes; `docs/watch-app-setup-and-qa.md` §4 |
| D-28002 | The wear flavor keeps the **same application id**; its own manifest (`src/wear/AndroidManifest.xml`) carries `android.hardware.type.watch` and it raises `minSdk` to 30. One listing is meant to carry both APKs later; today the wrist APK is installed directly. | Play's watch routing rule; owner's "as a watch app" framing |
| D-28003 | One link plugin, two platforms: `packages/omnitrain_watch_link` gains an Android half over `play-services-wearable`. The Dart API (`WatchLink`, two channels, four event kinds, five calls) does not change, so `WatchConnectivityChannel`, `WatchConnectivityTransport` and the phone's watch graph are platform-blind. | the plugin's own README and `lib/core/platform/watch_connectivity_channel.dart` |
| D-28004 | The factory returns the transport on **iOS and Android** and `null` elsewhere (including web). Android's absence was a placeholder, not a rule. | `platform_watch_transport_factory.dart`, S-006 |
| D-28005 | The request frames move to `lib/core/platform/watch_request_frames.dart`, re-exported by the transport file, so the wrist app builds them without linking the phone's transport. The frame shape is untouched. | `WatchTransportRequest`, PROTOCOL.md "The request is a transport concern" |
| D-28006 | The wrist's radio is `WearWatchTransport`: reachability read from the platform, arrivals handled one at a time in order, and the Swift bridge's durability table (an observation, a lifecycle message, a session start, and a running snapshot wait in the OS queue; a timer, a request and an ended snapshot are dropped). The Apple bridge's newest-copy replacement (plan 69 D-3..D-8) is a later PR. | `WatchConnectivityBridge.swift`, `isDurable` |
| D-28007 | The shell is `WearApp` over injected engine, start paths, nutrition, orchestrator and transport. It owns the surface choice, the launch restore, the inbound routing and the lifecycle catch-up. A stopgap End control finishes a workout until the exercise menu is ported. | `lib/watch/debug/watch_start_debug_main.dart` (the composition it mirrors) |
| D-28008 | Every Flutter build names a flavor, so the release workflow and the pre-release gate were updated. The gate looks for the flavored artifact first and an unflavored one second, so an artifact left by an older build is still inspected rather than skipped (and the gate's existing tests keep their meaning). | `scripts/pre_release_check.sh` §11s/§11r, `.github/workflows/release.yml` |
| D-28009 | Each side advertises its data-layer capability in its flavor's `res/values/wear.xml` (`omnitrain_phone` / `omnitrain_wear`), so a peer that is installed is known before it launches a sync. The names are repeated in the plugin as constants and asserted by a source test. | `CapabilityClient` semantics |
| D-28010 | The live sensors stay out of this PR: the seam (`WatchSensorSource`) exists, but Wear needs the health-services exercise client for live heart rate (Health Connect does not push it), which is its own native piece and unverifiable without a wrist. The shell passes no source, so the wrist behaves as a sensorless one does. | `watch_sensor_recording.dart`, `docs/watch-app-setup-and-qa.md` §4 |
| D-28011 | Test seam: `WearWatchTransport.deliver` is public and is the arrival lane the event channel feeds, because `testWidgets`' fake clock delivers platform stream events only after the test body. The platform stream itself is proved by the transport's own test, which runs with a real event loop. | the failing first attempt at S-28023 |

## Scenarios

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28001 | `createPlatformWatchTransport(platform: android)` with a fake channel | a `WatchConnectivityTransport`, not null | the factory still returns null off iOS (D-28004) |
| S-28010 | the link answers `status` with `reachable: true` | `isPhoneReachable` is true after `start()`; `reachability` and `state` events move it both ways | reachability is cached at construction or ignored (D-28006) |
| S-28011 | `requestRoutines(since:)` and `requestSnapshot()` | the sent frame carries `request` and no `type`; the routines request names the wrist's `since` | the wrist sent a protocol envelope where the phone expects a request |
| S-28012 | a live send of `observations_up` refused with `not_reachable` | `transferUserInfo` is called with the same `messageId`, and no failure is reported | a durable frame is dropped instead of queued (D-28006) |
| S-28013 | a live send of `timer_state` refused the same way | nothing is queued and the failure is reported once | a live-only frame is queued and arrives wrong |
| S-28014 | a frame whose `payload.timers.rest` is null | what leaves carries a stopped timer stamped with the frame's `sentAt` | the wrist sends a null the radio cannot carry |
| S-28015 | two frames pushed back to back, handler awaiting in between | they are handled in arrival order and never overlap | arrivals run concurrently and the engine's state changes out of order |
| S-28016 | the durability table | observation, lifecycle, start and a running snapshot are durable; receipt, energy and water are not | the table diverges from the Swift bridge |
| S-28020 | the shell over an in-memory store, nothing running | the start surface shows | the shell always shows logging |
| S-28021 | an active session | the logging surface shows, and the stopgap End control with it | an active session falls through to the start surface |
| S-28022 | an active session with a running rest | the rest surface shows and End does not | the rest surface is not reached from the engine's timer |
| S-28023 | a `{'request':'snapshot'}` frame delivered through the transport | one `sendMessage` goes out carrying `session_snapshot` | the shell does not answer a snapshot request (D-28007) |
| S-28024 | a `routines_down` frame delivered | nothing is queued for the phone and the shell survives it | an applied frame is echoed back or takes the shell down |
| S-28030 | `android/app/build.gradle.kts` | a `phone` and a `wear` flavor exist, and the wear one raises the floor to Wear OS 3 | the wear target does not exist (D-28001) |
| S-28031 | both manifests | the wear manifest declares the watch feature as required and the main manifest does not | the phone build claims to be a watch app, or the wrist build cannot install on a watch |
| S-28032 | both `wear.xml` files and the plugin | each side declares the other's capability name | neither side can find the other (D-28009) |
| S-28033 | the plugin's pubspec, Gradle and Kotlin | Android is registered, `play-services-wearable` is a dependency, and the five calls and three event kinds are answered | the Android half is missing or partial (D-28003) |
| S-28034 | `lib/watch/wear_main.dart` and the four harnesses | the production entry point builds the real store and the radio; the harnesses stay harnesses | the wear build runs a QA harness |
| S-28035 | the release workflow and the gate | both invoke `flutter build appbundle --release --flavor phone`, and the gate still reads an unflavored artifact | every build fails for a missing flavor, or the gate stops inspecting an older artifact (D-28008) |

## Phases

1. **The radio** — the plugin's Android half, the request-frame split, the factory, and the S-006 test. Done when the Kotlin compiles and S-006 covers both platforms.
2. **The wrist app** — the transport, the shell, the entry point, the flavor, the manifests and the capabilities. Done when the wear APK builds and its manifest carries the watch feature.
3. **The build plumbing** — the release workflow, the gate and its artifact lookups. Done when both invocations name the flavor and the gate's existing artifact tests still pass.
4. **Tests and docs** — the three test files, `docs/wear_os_app.md`, the index entry, and the setup guide's sections 1 and 4. Done when the new suites are green.

## Assumption Log

- The Wear data layer's message limit is the documented 100 KB; frames above it are refused with `send_failed` rather than truncated. The protocol already splits its large messages.
- Android has no `WCSession.isPaired`; a peer that declared the capability counts as paired and one that is also nearby counts as reachable, which is the state a message can actually travel in.
- A queued data item is deleted by whichever side takes it, so `outstandingTransfers` shrinks when the peer receives — the one behavioural difference from the iOS queue.
- The gate's existing artifact tests lay down an unflavored artifact; the flavored path is looked for first and the unflavored path second, so both remain meaningful.

## Progress

- [x] Phase 1 — plugin Android half compiles; factory returns the transport on Android; S-006 covers both platforms.
- [x] Phase 2 — wear APK builds; manifest carries the watch feature; both capabilities in their APKs.
- [x] Phase 3 — release workflow and gate name the phone flavor; gate reads both paths.
- [x] Phase 4 — transport, shell and config suites green (15 + 9 tests); docs written.

## Open items

Later PRs, in the order they matter on a wrist. Sizes are the Apple counterpart's
source, so each is a real piece rather than a tweak.

1. **The exercise menu** (`WatchMenu.swift` and `WatchMenuView.swift`) — the stopgap End control is replaced by it; it also owns jump-to-exercise, Add Exercise and Discard Session. (Corrected 2026-11-21 by plan 281: the Apple menu has no wrist-side remove; removal only arrives from the phone.)
2. **The swipe pager** (`WatchLoggingPagerView.swift`, `WatchPagerModel.swift`) — one exercise per page.
3. **The effort-rating prompt** (`WatchEffortRating.swift`, `WatchEffortRatingView.swift`).
4. **Personal records** (`WatchPersonalBests.swift`, `WatchPersonalRecordBanner.swift`) and the bests frame it reads.
5. **Water** (`WatchWater.swift`) and the routines request's `wantsWater` flag, which the Dart orchestrator's signature does not carry yet.
6. **The workout summary** (`WatchWorkoutSummary.swift`, `WatchWorkoutSummaryView.swift`).
7. **Diagnostics** (`WatchDiagnosticsLog.swift`, `WatchDiagnosticsView.swift`, the send path).
8. **Accent theming** (`WatchAccent.swift`, `WatchAccentStyle.swift`) and the preferences frame that carries the colour.
9. **Live sensors** — a native health-services exercise client for heart rate and a fused-location feed, wired through `WatchSensorSource` (D-28010).
10. **The newest-copy queue replacement** from the Swift bridge (plan 69 D-3..D-8), so only the newest waiting copy of a snapshot or lifecycle is kept.
11. **Distribution** — one Play listing with both APKs, and a background data-layer listener so a frame reaches a wrist whose app is not running.

## Feedback

Review findings are in `2026-11-20-280-wear-os-shell-plan.review.md` beside this
plan; evidence (commands, suite output, APK inspection) is in
`2026-11-20-280-wear-os-shell-plan.evidence.md`.
