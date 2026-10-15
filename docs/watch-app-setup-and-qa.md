# Wearable App — Setup and QA Guide

A hands-on guide for getting OmniTrain onto a wrist. Written for the person at
the keyboard, not for an agent.

> **Companion plan**: `docs/plans/2026-09-21-13-watch-integration-shipping.md`
> covers the code work. This guide covers the parts a human has to do and how to
> tell whether any of it actually works.

---

## 1. Where things actually stand

The wrist logic is finished and tested. The wrist *app* now exists and hosts it.

Verified 2026-10-04:

| | Apple Watch | Wear OS |
|---|---|---|
| Client logic | `watch/watchos/Sources/WatchSessionEngine/` (Swift) | `lib/watch/` (Dart) |
| Tests | `swift test` on a Mac, also run by the pre-release gate; 0 failures required | covered in the Dart suite |
| App shell | `ios/OmniTrain Watch App/` — the start surface, the logging surface, and a radio (§3.6) | **none** — no production `main()` |
| Build target | **exists**; the target links the `WatchSessionEngine` package — building the watch scheme (§5) is the proof | **none** — Gradle has only `:app` |
| Transport | implemented (`lib/core/platform/`) | **none** |
| Wrist store | **append-only file store** — survives a relaunch | — |

The Apple shell is the only thing that hosts a wrist client. The four
`*_debug_main.dart` files are QA harnesses, not the app, and the Wear OS client
still has no host at all.

**Scope**: Apple Watch first. Wear OS is deferred to a separate cloning job
once the Apple path is proven on hardware — see §4.

The phone half is wired: `lib/main.dart` builds the watch graph through
`createWatchSync` — null on a platform with no watch. No phone screen consumes
the mirror yet. Verified by the S-006 tests in `test/watch_transport_test.dart`
(`the production graph is not built where no watch exists`).

**What this means practically**: the first milestone — a watch app shell hosting
the engine — is built and awaiting its first run on a paired simulator (§5,
Level 3). Everything else follows from that.

---

## 2. What only you can do, and what an agent can do

Not all of the "manual" work is actually manual. Split it honestly, or you will
do work an agent could have done.

### An agent can do these (all plain text, all in-repo)

- [x] The Swift `@main` App type and SwiftUI scene for watchOS (§3.6).
- [x] `Info.plist` and `.entitlements` edits — these are plain XML.
  (Landed in plan 19c: `ios/OmniTrainWatchApp-Info.plist`, `ios/OmniTrainWatchApp.entitlements`.)
- [x] The watchOS platform entry in `watch/watchos/Package.swift`.
- [x] The transport Dart interface implementation and the Swift bridge code
  (`lib/core/platform/`; `watch_connectivity` is imported in exactly one file).
- [x] The phone-side wiring: `createWatchSync` bound to the running `WorkoutState`
  through the adoption bridge, and the `routines_down` producer.
  Watch-initiated: the wrist asks, the phone answers
  (`docs/plans/2026-09-21-13-watch-integration-shipping.md`, D-7).

(Deferred with Wear OS: the Dart wrist entry point, the Gradle module strategy,
and the `AndroidManifest.xml` work — all agent-editable when that job starts.)

### Only you can do these

1. **Create the Xcode watchOS target.** `.pbxproj` is plain text, not binary —
   but it is generated, densely cross-referenced by UUID, and hand-editing
   corrupts projects in ways that are painful to unwind. Let Xcode write it.
2. **Apple Developer portal work.** App IDs, capabilities, provisioning
   profiles. Requires authenticated web access.
3. **Code signing.** Team selection, certificate installation.
4. **Physical device pairing.** An Apple Watch paired to an iPhone, both on the
   same Apple ID.
5. **Accepting the health permission prompts** on-device during QA.
6. **Installing the watchOS simulator runtime** — this machine currently has
   only iOS 26.4 (`xcrun simctl list runtimes`). Xcode → Settings → Components.

---

## 3. Apple Watch — creating the app shell

Toolchain on this machine: Xcode 26.4.1, Flutter 3.41.9, Dart 3.11.5, iOS
deployment target 14.0, bundle ID `dev.sasha.omnitrain`.

### 3.1 Install the watchOS runtime first

Xcode → Settings → Components → install a watchOS simulator runtime. Without it
there is no watch simulator to build against, and the target template will still
be created but unbuildable.

Confirm:

```bash
xcrun simctl list runtimes | grep -i watch
```

### 3.2 Add the target

Open the **workspace**, not the project — Flutter's pods live in the workspace:

```bash
open ios/Runner.xcworkspace
```

File → New → Target → watchOS → **App**.

- Product name: `Runner Watch` (or `OmniTrain Watch` — the display name is what
  the user sees on the wrist, set it in the target's Info.plist).
- Interface: SwiftUI. Language: Swift.
- Embed in companion application: **Runner**.
- Uncheck Include Notification Scene / Complication unless you want them now.

Xcode creates the target, sets the bundle identifier, and — importantly — writes
`WKCompanionAppBundleIdentifier` into the watch app's Info.plist.

### 3.3 Verify the bundle-identifier relationship

This is the single most common thing to get wrong, and it fails at install time
with an unhelpful error.

- The watch app's bundle ID **must be prefixed by the iOS app's bundle ID**.
  Xcode's template default is `dev.sasha.omnitrain.watchkitapp`.
- The watch app's `WKCompanionAppBundleIdentifier` must equal exactly
  `dev.sasha.omnitrain`.

Take whatever Xcode generates rather than inventing a suffix; if you change it,
change it in both places.

### 3.4 Capabilities — what you actually need

Two corrections to common assumptions, both worth knowing before you spend time
in the portal:

- **WatchConnectivity needs no entitlement.** `WCSession` works between an iOS
  app and its companion watch app purely on the bundle-ID relationship above.
  There is no "WCSession capability" to add. If messaging fails, the cause is
  pairing, reachability, or the bundle-ID prefix — not a missing entitlement.
- **App Groups are optional.** They give the two apps a shared file container.
  You need them only if you decide the transport should hand off large payloads
  via a shared container rather than `WCSession` file transfer. Skip until the
  transport decision (D-1 in the plan) says otherwise.

**HealthKit you do need**, for the sensor path (plan item 11) and for the workout
that keeps the app alive (plan 19c):

- The HealthKit capability is configured for the **watch** target:
  `ios/OmniTrainWatchApp.entitlements` declares `com.apple.developer.healthkit`
  and the watch configurations name it with `CODE_SIGN_ENTITLEMENTS`. The iOS
  target already had it — `ios/Runner/Runner.entitlements`.
- `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` are
  `INFOPLIST_KEY_*` build settings on the watch target;
  `WKBackgroundModes` = `workout-processing` lives in the watch target's Info.plist
  fragment `ios/OmniTrainWatchApp-Info.plist`. The background mode is what keeps
  the app alive with the wrist down during a session — the exact behavior
  `lib/watch/sensors/watch_platform_workout.dart` documents as the reason for
  registering a platform workout at all. Without it the app is suspended mid-set
  and the session dies.
- **(owner)** Enable the HealthKit capability for `dev.sasha.omnitrain.watchkitapp`
  (team `S3976AA7K8`) in the Apple developer portal so provisioning signs the
  entitlement. A device build fails to sign until then; the simulator build is
  unaffected.

### 3.5 Link the engine

The watch target already links the `WatchSessionEngine` package from `watch/watchos/`.

### 3.6 The entry point and the shell

Written, by Phases 1–4 of the shell-bridge plan:

- `ios/OmniTrain Watch App/OmniTrainApp.swift` — the `@main` App type.
- `ios/OmniTrain Watch App/ContentView.swift` — `WatchAppHost`, which owns the
  store, the engine, the start paths, the phone preferences, the radio, the
  bridge, the outward sink and the orchestrator, plus the three surfaces it
  renders in order: the owed rating question alone, while one is unanswered;
  the logging surface while the session is active and holds at least one
  exercise; and the start surface (`WatchStartView`, in the package, with its
  exercise picker). The logging surface logs the current exercise's own effort —
  a set, a timed hold, a round or a drill, chosen from the exercise's
  capabilities — and hosts the session menu: the ladder's exercises with their
  logged counts to jump to, then Finish. Exercises are added on the phone. An
  ended session can no longer be logged into
  (`WatchLoggingSurfacesTests.testS029AnEndedSessionCannotBeLoggedInto`).
  Logged rows leave through `WatchEmitForwarder` over the connectivity bridge —
  the outward sink wired in this PR;
  `WatchEmitForwarderTests.testTheEnginesEmissionsReachTheSinkInOrder` proves
  they arrive in emission order.
- `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift` — the one file in
  the target that imports `WatchConnectivity`: the real `WCSession` conformance
  behind the package's `WatchConnectivitySession` seam.

The watch `xcodebuild` in §5 is what proves these compile; the S-102 to S-113
tests in
`watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`
are what prove the logic they host.

**What the wrist cannot do yet.** Two gaps: the wrist labels the load it dials
in kilograms even when the phone's saved unit is pounds — the wire value is
always kilograms, so the phone's history and conversions stay correct — and each
device owns only the timer it started, so a Sync stops a countdown the phone
wrote and leaves a wrist-started one running, because the phone's answer carries
no timers (D-26, D-80; `test/watch_logging_timers_test.dart`,
`S-79 a snapshot leaves the wrist's countdown running and stops the phone's own`).
A rest is not one of those timers: it is device-local and has no length, but the
rest itself travels — when it ends (Next, or the next logged set) the wrist emits
a `rest` observation and the phone's importer writes it into the session's
history, so the Session Summary counts it
([Global Conventions](global_conventions.md), "Rest rule: rest is a count-up";
`test/rest_is_count_up_contract_test.dart`;
`test/watch_session_summary_integration_test.dart`, `S-329 the totals`).

---

## 4. Wear OS — deliberately deferred

**Not in scope for this pass.** Apple Watch ships first; Wear OS follows as a
separate cloning job once the Apple path is built, tested and proven on
hardware. Doing them together would mean debugging two unproven transports
against two unproven shells at the same time.

Recorded here so the follow-on job does not have to rediscover it:

- `android/settings.gradle.kts` includes only `:app` — no Wear module.
- No `android.hardware.type.watch` in the manifest.
- No production Dart wrist entry point — only the four debug harnesses.
- `lib/watch/` is already the complete Wear client, and it is contract-tested
  against the Swift client through `watch/contract/*.json`. **The cloning job is
  shell plus transport, not logic** — the hard part is already done and already
  proven to agree with the Apple client.
- The sensor half is Health Connect rather than HealthKit; the modality→activity
  mapping for both already exists in `watch/contract/watch_sensor_contract.json`
  (`WatchActivityType.wear`, the `EXERCISE_TYPE_*` vocabulary).

One thing to preserve while building the Apple path: keep the Dart transport
interfaces platform-neutral, so the Wear implementation slots in later without
reopening the protocol contract.

---

## 5. QA — three levels

Run them in this order. Each level catches a different class of failure, and the
cheap ones catch most of it.

### Level 1 — the suites (seconds, no hardware)

This is the current green baseline. Re-run after every change; any drop is a
regression introduced by your work.

```bash
flutter test
```

Expected: **all passed, no failures.** Read the counts off the run rather than
against a number here.

```bash
cd watch/watchos && swift test
```

Expected: **0 failures.** The count grows with every scenario added, so read it
off the run rather than against a number here. `bash scripts/pre_release_check.sh`
runs this too on a Mac, and a red suite blocks the release; on a host that cannot
build the package it logs a skip instead.

**Neither suite compiles the watch UI.** `swift test` runs on macOS, and every
SwiftUI view in the package sits behind `#if os(watchOS)` — so the views are
skipped entirely. A fully green suite proves nothing about whether they build.
Compile them explicitly:

```bash
cd watch/watchos && xcodebuild -scheme WatchSessionEngine -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)' build
```

Run this alongside the suites. It caught two real compile errors the first time
it was ever run — a ternary between two different `ButtonStyle` types, and a
constant referenced through the wrong type — both of which had sat in green-suite
code for weeks because nothing had ever built them.

Both suites drive the same JSON fixtures in `watch/sync_protocol/fixtures/`, and
the shared contracts in `watch/contract/*.json` are what force the Dart and
Swift wrist clients to agree. A change that makes one client diverge fails the
*other* client's suite — that is the design, and it is why a red Swift suite
after a Dart-only change is meaningful rather than confusing.

### Level 2 — the debug harnesses (minutes, desktop or phone)

Four harnesses run the real implementations against in-memory or scratch
storage. They are the intended way to exercise wrist behavior before any watch
app exists, and none of them can collide with your real app data.

Live session mirroring, both devices real, with a severable link:

```bash
flutter run -t lib/state/watch/live_session_mirror_debug_main.dart --dart-define=LIVE_MIRROR_DEBUG=true
```

Wrist start paths, seeded as a `routines_down` message would:

```bash
flutter run -t lib/watch/debug/watch_start_debug_main.dart --dart-define=WATCH_START_DEBUG=true
```

Session engine against the real Hive store, in its own box prefix:

```bash
flutter run -t lib/watch/debug/watch_session_debug_main.dart --dart-define=WATCH_SESSION_DEBUG=true
```

Wrist logging surfaces, all four effort kinds:

```bash
flutter run -t lib/watch/debug/watch_logging_debug_main.dart --dart-define=WATCH_LOGGING_DEBUG=true
```

The mirroring harness has a loopback carrier you can sever mid-session, and the
start harness has a reachability switch. Those two controls stand in for the
transport, so **use them to test the failure modes now** — offline start,
reconnect-and-catch-up, duplicate delivery — rather than waiting for hardware.

### Level 3 — paired devices (the only level that proves transport)

Everything above passes today with no transport at all. Only this level can
tell you the integration is real.

**Setup**: an Apple Watch paired to an iPhone, both on the same Apple ID, both
unlocked, the phone app installed and launched at least once. Boot the iPhone 17
Pro simulator and the Apple Watch Series 11 (42mm) simulator and pair them, or use
a real pair. Foreground the phone app and the watch app before each sync. On the
phone, create a routine first for the reference-data steps below.

**The one-session walkthrough.** The phone and the wrist share one session:
whatever the phone does to its own session is pushed to the wrist by itself,
and the **Sync** button is what *asks the phone for an answer* — for a session
the wrist started, for a catch-up after being out of reach, and for routines and
the food list. Both apps must be foregrounded and reachable for anything to
cross; a backgrounded app on either end is the usual reason nothing arrives.

**(a) The phone's session reaches the wrist by itself — (owner).** Start a Free
session on the phone and add two or three exercises. With the watch app in the
foreground, the watch's list fills with the phone's exercises, in the phone's
order, without tapping **Sync**, and the session on screen is the phone's
session. The push carries the phone's current place rather than the first slot
(`test/watch_session_auto_push_test.dart`, `S-71 the push reports the wrist's
position, not slot 0`), and a set logged on the phone arrives the same way
(`S-70 the phone's own set is pushed as one snapshot, and the wrist's own set is
not sent back`).
**(b) A change on the phone arrives by itself — (owner).** Add an exercise on the
phone. It appears on the watch without a Sync: a burst of changes inside one push
is a single frame, and a rest tick pushes nothing
(`test/watch_session_auto_push_test.dart`,
`S-75 three changes inside the window are one frame`,
`S-74 five notifications without a change push nothing`).
**(c) The wrist's session reaches the phone by itself — (owner).** From a fresh
state (nothing running on either device), start **Free workout** on the watch and
pick an exercise. It appears on the phone without tapping **Sync**: the wrist
announces its own start with a snapshot the phone adopts as its in-progress
session, and an exercise added afterwards arrives as a second snapshot
(`test/watch_session_engine_test.dart`,
`S-100 a wrist start sends its lifecycle, then its own snapshot`,
`S-101 a wrist-added exercise arrives as a second snapshot with a moved
revision`). The phone's home shows it as a session in progress, and opening it
shows the regular session screen with the wrist's exercise. With the phone back
in reach after being out of range, the wrist catches up on its own
(`WatchConnectivityBridgeTests.testS107TheWristCatchesUpOnAReachabilityEdgeOnce`).
**(d) Two sessions at once: the phone's takes over, and the wrist's ends —
(owner).** With a session running on the phone, start one on the watch (or the
other way round) and sync. The phone holds the session it was running and does
not adopt the wrist's; the wrist's own session *ends*, because the phone sends an
`abandoned` lifecycle naming it ahead of its own state, and the wrist then shows
the phone's session
(`test/watch_session_auto_push_test.dart`,
`S-172 the pass sends abandoned(W) then P's own state, and the wrist's answer is
what converges the pair`; `test/watch_session_projection_test.dart`,
`S-183 case A the abandoned frame the reset carries ends the wrist's session and
takes nothing else`). Nothing is merged and no history entry is invented for the
wrist's session; a session the phone never held is never ended by the phone's own
rule (`S-86 the push ends the wrist's session as a deliberate reset and never as
an end the phone was told about`). A snapshot naming a session the wrist is not
in is still refused silently by the wrist's own rule — that is what a phone that
has not sent the reset meets (`test/watch_session_engine_test.dart`,
`S-77 the wrist refuses a foreign snapshot, silently`). A second start *on the
wrist* opens no second session there: **Free workout** returns the session it
already has and emits nothing, a routine with exercises is refused, and a routine
fills an active empty session in place
(`test/watch_session_start_test.dart`,
`S-177 startFreeWorkout on a live session returns it and emits nothing`,
`S-170 startFromRoutine on a session with exercises is refused too`,
`S-178 a routine fills an active empty session in place`).
**(e) Finishing on the phone ends the wrist's session by itself — (owner).**
Finish the phone's session from the regular session screen. With the watch app
foregrounded the wrist's session ends on its own, without a Sync
(`test/watch_session_auto_push_test.dart`,
`S-72 finishing on the phone ends the wrist's copy, once`), and the phone's
calendar holds exactly one entry for it. Discarding the phone's session abandons
the wrist's copy the same way
(`S-73 discarding on the phone abandons the wrist's copy, once`). A watch the
phone cannot reach at that moment — locked, or apart — is not lost work: the
finish is answered to it at its next sync, when the wrist itself asks
(`test/watch_session_finish_test.dart`,
`S-5 the phone's own finish is reported, and the wrist is answered at its next
sync`).
**(f) Finishing on the watch.** Answering the wrist's own Finish — the menu's
**Finish**, reached from the list button — closes the session on the phone as
well, with one history entry and the rating the wrist gave. A Finish the phone
was not there to hear — the session ended while the pair was apart — is
re-announced by the wrist at its next catch-up, behind whatever the wrist still
owes, and the phone's copy and its session screen end then, with the wrist's
rating (`test/live_mirroring_test.dart`,
`S-216 the catch-up re-announces the wrist's end behind what it owes`;
`test/pr4_session_controls_test.dart`,
`S-213 the end the wrist re-announces at its next catch-up leaves the screen for
one summary carrying the wrist's rating`). The repeat is harmless by design: the
same end travels under its own identity, and the phone reads a second copy as the
end it already holds (`test/live_mirroring_test.dart`,
`S-215 every catch-up repeats the same frame, and the phone stays still`).
**(g) Sets the phone logged reach the wrist by themselves — (owner), not yet
run.** Log two sets on the phone's regular session screen, in a session that is
also on the watch. With the phone app in the foreground, the watch's logging
screen shows both sets, in the phone's order, without tapping **Sync**
(`test/watch_session_auto_push_test.dart`,
`S-70 the phone's own set is pushed as one snapshot, and the wrist's own set is
not sent back`). The doubling check: a set logged on the watch earlier is not
duplicated by the frame. Then edit one of those sets on the phone (change the
weight): an edit is expected to reach the watch at the next push or Sync — if it
does not appear by itself, tap **Sync** and confirm it shows the new weight on
that same set, not a third set, which is what the re-statement is proven to do
(`test/watch_session_projection_test.dart`,
`S-35 an edit reaches the wrist and a delete is announced`). Deleting a set on
the phone is carried: the next push announces the deletion and the set leaves the
watch (`test/watch_session_auto_push_test.dart`,
`S-120 the push names the set the phone dropped, in a frame the wrist applies,
before the snapshot that no longer carries it`). A deletion the push could not
send is not lost: the next push announces it under the id it was minted with
(`test/watch_session_auto_push_test.dart`,
`F7 the next pass announces the deletion the failed one could not, under the
change id it was minted with`), and two deletions of one re-used number are two
distinct frames rather than a repeat (`test/watch_session_auto_push_test.dart`,
`F2 a number the phone re-used and dropped again is announced again, under a
change id the wrist has not applied`). It stays gone after the
watch's app is relaunched (`test/watch_session_engine_test.dart`,
`S-124 the deleted set stays hidden across a restart`), and on the watch itself
after a local stop the watch began and ended on its own
(`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`,
`testF1ALocalTransitionAfterADeleteKeepsTheLens`).

**The walkthrough** — each step maps to a protocol rule that is already
enforced in code, so a failure points at the transport, not the logic:

1. **The button just says Sync.** Before touching anything, confirm the wrist's
   start screen shows a **Sync** button and no line about automatic sync — the
   line that promised the *absence* of automatic sync is gone, because part of it
   is now automatic. Held by `test/watch_session_start_test.dart`
   (`the sync action is offered only when the app can ask`: the button reads
   `Sync` and no "No automatic sync" text renders) and, on the wrist,
   `WatchSessionStartPathsTests.testS082TheStartSurfaceSaysSyncAndCarriesNoAutomaticSyncLabel`.
2. **Reference data arrives when the watch asks for it.** Trigger the sync
   action *on the wrist*. The routine list should populate. Confirm it does
   **not** populate on its own when you merely launch the phone app — an
   automatic refresh here is a defect, not a convenience. The phone side of this
   path exists (`WatchSyncRequestHandler` answers the request; tested by
   `test/watch_transport_test.dart` and `test/watch_reference_sync_test.dart`),
   so a failure here points at pairing or at the radio, not at a missing
   producer.
3. **A routine renders the way the routine defines it.** Start a routine
   containing a Plank on the wrist. It must show the effort kind the routine
   declares, not one the watch re-derived from capabilities. This is the
   specific disagreement that exists in the code today.
4. **Start a session on the phone.** The watch should mirror it by itself: same
   exercises, same order, same current slot. Step *(a)* of the one-session
   walkthrough is this one, and *(b)* is the same session after a change on the
   phone.
5. **Two sessions at once: the phone's takes over.** With the phone's session
   running, start one on the watch and sync: the phone holds the session it
   started, the wrist's own session ends, and the wrist shows the phone's session
   (step *(d)* above).
   Starting again on the wrist while it already runs a session is refused and
   keeps the first (`test/watch_session_start_test.dart`,
   `S-177 startFreeWorkout on a live session returns it and emits nothing`). No
   merge, and no stray history entry for the session that ended.
6. **The wrist's own session becomes the phone's.** From a fresh state, start
   **Free workout** on the watch, pick an exercise and sync: the phone's home shows
   a session in progress and opens it in the regular session screen (step *(c)*
   above).
7. **Try to change structure on the wrist.** You should not be able to. Phone
   owns structure is a MUST in `watch/sync_protocol/PROTOCOL.md`.
8. **Go offline.** Turn on Airplane Mode on the phone mid-session. Keep logging
   on the wrist. Nothing should be lost — wrist storage is append-only.
9. **Come back.** Disable Airplane Mode. Everything logged offline should land
   exactly once. Duplicate delivery is the failure to watch for, and the
   idempotency keys (`eventId`, `entryId`, `changeId`) are what should prevent
   it. Then log a set on the wrist, let the rest run, tap **Next** and sync: the
   phone's session Summary counts that rest, once, beside the rests the phone
   itself recorded (`test/watch_session_summary_integration_test.dart`,
   `S-329 the totals`).
10. **Kill the phone app mid-session** and relaunch. The session should restore
   from timestamps, not from a counter — a restored rest showing a fresh full
   duration means someone reintroduced remaining-time, which the protocol
   forbids: rest is a count-up with no preset length, written down in
   [Global Conventions](global_conventions.md) as "Rest rule: rest is a
   count-up", and `test/rest_is_count_up_contract_test.dart` fails the build if
   anyone adds a rest length or a rest countdown back.
11. **Kill the watch app mid-session** and relaunch **(owner)**. Log two sets on
    the wrist, force-quit the watch app with no Sync, then relaunch: the session,
    both sets and the running rest are back, and the rest screen counts up from
    the restored start rather than from zero
    (`WatchRestSurfaceTests.testS161TheRestElapsedCountsUpAndSurvivesARelaunch`).
    Sync: the phone shows the sets once.
12. **Quick-log food on the wrist.** It should land on the phone's correct day,
    and a redelivery must not double it.
13. **Sensor path** (after HealthKit is configured): heart rate appears during a
    session; a finished session closes its `HKWorkoutSession`. A workout left
    "in progress" after you force-quit is the specific bug to hunt.
14. **Check Apple Health.** The session should appear there once, not twice.

Steps 15–18 check the session effort rating and all run on the shipped shell.
Steps 19–20 check the heart-rate and step capture and stay with the shipping
plan's Phase 8 (the HealthKit bindings) — see that plan's O-2
(`docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`). Steps 21–22 are
the keep-alive checks plan 19c added and need a real watch.

15. **The wrist asks how hard it was.** Turn Settings →
    Effort Rating on, on the phone, then sync from the wrist. Log a set on the
    wrist and end the session there. The wrist asks "How hard was this
    session?" from 1 to 5, and only an answer closes it — no skip, back or
    swipe. Answer 4. After the wrist syncs, the session is in the phone's
    calendar and its Summary shows 4 / 5. Repeat with the phone in Airplane
    Mode while you end and answer: once it reconnects, the rating arrives
    intact.
16. **It asks only when the phone says so.** Turn Effort Rating off on the
    phone and sync from the wrist: ending a session asks nothing, and the
    phone's Summary offers Add rating. A wrist that has never synced does not
    ask either. A session with nothing logged is never asked about.
17. **The question survives a kill** **(owner)**. Finish the session on the wrist
    (the menu's **Finish**, from the list button) and force-quit the watch app
    while the question shows. Relaunch: the question comes back before anything
    else, and one answer records one rating. The engine restores it from the
    store that outlives the process
    (`WatchEffortRatingTests.testS215AKillDuringThePromptAsksAgainAndRecordsOneAnswer`);
    the shipped shell builds that store on disk, so this runs on a paired device.
18. **Finishing on either device.** Finish on the phone: the wrist's session ends
    by itself, without a Sync (`test/watch_session_auto_push_test.dart`,
    `S-72 finishing on the phone ends the wrist's copy, once`), and the phone
    holds one entry (step *(e)* above). Finish on the wrist: the phone's copy ends
    through its ordinary finish with the rating the wrist gave (step *(f)*
    above). Neither finish needs the other device in reach: a wrist that was
    locked or apart when the phone finished is answered at its next sync, when it
    asks (`test/watch_session_finish_test.dart`,
    `S-5 the phone's own finish is reported, and the wrist is answered at its
    next sync`), and a Finish that did not get through is re-announced by the wrist
    at its own next catch-up, which ends the phone's copy and its session screen
    with the wrist's rating (`test/pr4_session_controls_test.dart`,
    `S-213 the end the wrist re-announces at its next catch-up leaves the screen
    for one summary carrying the wrist's rating`).
19. **Heart rate and steps reach the phone** *(needs Phase 8)*. With heart-rate
    and motion permission granted, run a session with a run, three rounds of a
    sports exercise and a block of sets. After sync the phone holds an average
    and maximum heart rate for the session, the run, each round and the set
    block, and a step total for the run only. The phone has no screen for
    these yet: inspect them with a debug build that lists
    `getSensorSummariesForSession`. With heart-rate permission denied the
    session still syncs, with no heart-rate values and no zeros.
20. **Samples arrive in time** *(Phase 8)*. Compare when heart-rate and step
    samples arrive with when each entry is logged. An entry's values are
    computed as it is logged, so a sample that arrives after that is missing
    from them — the shipping plan's Phase 8 item 4 decides whether to wait.
21. **The app stays alive with the wrist down — (owner).** The entitlement, the
    usage strings and the background mode are in the built product and the watch
    app compiles, but nothing has run on a device. Enable the HealthKit
    capability for `dev.sasha.omnitrain.watchkitapp` (team `S3976AA7K8`) in the
    Apple developer portal first: a device build fails to sign until then.
    Install on a real watch, start a session and let the wrist drop mid-session:
    the workout must stay open and the session keep running, rather than
    suspending mid-set.
22. **Declining the permission is not a failure — (owner).** Deny the Health
    permission when the watch asks. Logging, the menu and sync must all keep
    working, and a session still begins and ends on the wrist: a refused begin
    is recorded, never retried while the same session is live
    (`WatchWorkoutCoordinatorTests.testS1505DenialIsNotFailure`).

### The wrist's own logging (PR 2b)

This walkthrough exercises the wrist logging surface, which has not run on
hardware yet.

1. **Start a workout on the wrist and pick an exercise.** Tap **Free workout**.
   A Free workout starts with no exercise, so the picker comes up first; pick
   one and the logging screen appears with that exercise's value rows. Dial 3
   reps and tap **Log**: the row is accepted and the rest screen appears counting
   up, with exactly one control, **Next**
   (`WatchRestSurfaceTests.testS162NextEndsTheRestAtTheTapInstant`).
2. **The set is on the phone at the moment it is logged.** Phone app in the
   foreground and reachable. Without touching the wrist, the phone's session for
   this wrist session shows the set. The phone must show it before any Sync —
   only an untouched wrist proves the set is handed over as it is logged.
   Nothing is sent on a timer.
3. **Finish and answer once.** Turn Settings → Effort Rating on, on the phone, and
   sync from the wrist. On the wrist tap the list button, then **Finish**; the
   question appears alone — no skip, back or swipe. Answer 4. The phone's
   calendar holds one entry for the session and its Summary shows 4 / 5.
4. **A workout logged with the phone out of reach catches up by itself — (owner).**
   Start another wrist workout and log a set with the phone in Airplane Mode.
   Nothing arrives. Turn Airplane Mode off: with the phone back in reach the wrist
   catches up on its own — the set lands exactly once without tapping **Sync**
   (`WatchConnectivityBridgeTests.testS107TheWristCatchesUpOnAReachabilityEdgeOnce`:
   the owed entries leave once, and a second notification while one is in flight
   is dropped). The **Sync** button still fetches routines, preferences and the
   food catalog, and retries by hand.
5. **A band-assisted set logs a negative load** *(owner)*. Pick a set exercise
   with a load. Dial the load down past zero: the crown stops at the wire's floor
   however long you keep turning
   (`WatchLoggingTimersTests.testS061AnAssistedLoadStopsAtTheWireFloor`, and the
   phone's own floor in `watch_logging_stepping_test.dart`). Log the set: the
   phone's session for this wrist session shows the same assisted value, not
   zero, and its summary counts it
   (`WatchLoggingSurfacesTests.testS062AnAssistedLoadIsEmittedWithItsSign`;
   `test/watch_session_import_test.dart`,
   `S-58 a set logged at −20 kg imports at −20 kg and sums −160`), and the next
   set opens at that assisted load rather than resetting to zero
   (`testS063TheNextSetCarriesTheAssist`). A set whose load was never touched
   still claims no load at all (`testS062AnUntouchedLoadDialSendsNoLoadKg`).
   Dialling back up to zero leaves a plain `0.0`, never a `-0.0`
   (`testS064AZeroLoadNeverPrintsASignedZero`).
6. **A timed effort logs one Start-to-Log window** *(owner)*. Pick a timed
   exercise: logging shows one clock readout and one **Start** button, with no
   duration, distance, rounds or length row. Tap **Start** and the readout counts
   up while the button reads **Log**
   (`WatchTimedWorkTests.testS1300TimedWorkIsLoggedAsTheWindowFromStartToLog`);
   log it and the phone's session shows one entry for that window. A round
   exercise picked with the phone's number counts down from it — 40:00 for a
   soccer half
   (`WatchLoggingTimersTests.testS1401TheWristCountsDownFromTheSlotsOwnLength`),
   while one whose slot carries no number keeps the wrist's preset at 3:00
   (`…testS1402ASlotWithNoNumberKeepsTheWristsPreset`). **Finish** still ends the
   session
   (`…testS1311FinishLeavesTheWorkClockRunningAndTakesTheReadout`).

Two known gaps this walkthrough must not be read as failing on: each device owns
only the timer it started, so a Sync stops a countdown the phone wrote and
leaves a wrist-started one running (`test/watch_logging_timers_test.dart`,
`S-79 a snapshot leaves the wrist's countdown running and stops the phone's own`;
the phone-written case is the reconciliation fixture `timer_cleared.json`,
replayed by `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`),
and the load label is always in kg, whatever unit the phone is set to
(`WatchLoggingTimersTests.testS007APoundPreferenceStepsInPoundsStoredInKilograms`
holds the kilogram payload underneath).

### What "QA passed" means

Levels 1 and 2 green, plus every step at Level 3 on real paired hardware —
steps 15–18 now, steps 19–20 once shipping-plan Phase 8 makes them runnable, and
steps 21–22 on a real watch with the HealthKit capability enabled.
Anything less and the integration is still a test-suite reality.

---

## 6. Suggested order

1. Install the watchOS runtime, create the Xcode target, get a blank watch app
   onto the simulator. **Nothing else can be verified until this exists.**
2. Add the watchOS platform to `Package.swift`, link the engine, get the
   existing `WatchStartView` rendering on the wrist with seeded data.
3. Only then build the transport. You will have somewhere to run it and a way
   to see it fail.
4. Wire the phone side (`createWatchSync`, its adoption bridge bound to the
   running `WorkoutState`) and the `routines_down` producer.
5. Run Level 3 on hardware. **This is the gate.** Apple Watch is not done until
   every step passes on a paired device.
6. Only after that: the Wear OS cloning job, as its own plan.

The temptation is to build the transport first because it is the interesting
problem. Resist it — a transport with no app on either end cannot be debugged.
The same logic is why Wear OS waits: clone a proven path, not a hypothesis.
