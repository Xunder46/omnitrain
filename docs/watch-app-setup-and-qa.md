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
- [ ] `Info.plist` and `.entitlements` edits — these are plain XML.
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

**HealthKit you do need**, but only for the sensor path (plan item 11):

- Add the HealthKit capability to the **watch** target. The iOS target already
  has it — `ios/Runner/Runner.entitlements` declares
  `com.apple.developer.healthkit` and is correctly referenced from the build
  settings.
- Add `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` to
  the **watch app's** Info.plist. The iOS strings already exist in
  `ios/Runner/Info.plist:47-50`; write watch-appropriate equivalents.
- Add `WKBackgroundModes` = `workout-processing` to the watch app's Info.plist.
  This is what keeps the app alive with the wrist down during a session — the
  exact behavior `lib/watch/sensors/watch_platform_workout.dart` documents as
  the reason for registering a platform workout at all. Without it the app is
  suspended mid-set and the session dies.

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
  capabilities — and hosts End and the exercise picker. An ended session can no
  longer be logged into
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
always kilograms, so the phone's history and conversions stay correct — and a
Sync while a rest countdown is running stops that countdown and its milestone
haptic, because the phone's answer carries no timers (D-26).

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

**The one-session walkthrough.** The phone and the wrist share one session: sync
is manual, and whichever device holds the session the other is looking at is the
one on screen. Both apps must be foregrounded and reachable for a sync to cross; a
backgrounded app on either end is the usual reason nothing arrives.

**(a) The phone's session reaches the wrist.** Start a Free session on the phone
and add two or three exercises. On the watch, tap **Sync** (the routines action).
The watch's list fills with the phone's exercises, in the phone's order, and the
session on screen is the phone's session.
**(b) A change on the phone arrives on the next sync.** Add an exercise on the
phone. Nothing happens on the watch by itself — tap **Sync** on the watch and the
added exercise appears in its list.
**(c) The wrist's session reaches the phone.** From a fresh state (nothing running
on either device), start **Free workout** on the watch and pick an exercise. Tap
**Sync** on the watch. The phone's home shows it as a session in progress, and
opening it shows the regular session screen with the wrist's exercise.
**(d) Different sessions on both devices: each keeps its own.** With a session
running on the phone, start one on the watch (or the other way round) and sync. The
phone keeps the session it was running and does not adopt the wrist's; the wrist
keeps its own. Nothing is merged, and no history entry is invented.
**(e) Finishing on the phone ends the wrist's session at its next sync.** Finish
the phone's session from the regular session screen. Nothing is sent to the watch
at that moment. Tap **Sync** on the watch: the wrist's session ends, and the phone's
calendar holds exactly one entry for it.
**(f) Finishing on the watch.** Answering the wrist's own End closes the session
on the phone as well, with one history entry and the rating the wrist gave.
**(g) Sets the phone logged reach the wrist at its Sync — (owner), not yet run.**
Log two sets on the phone's regular session screen, in a session that is also on
the watch. With the phone app in the foreground, tap **Sync** on the watch: the
watch's logging screen shows both sets, in the phone's order. The doubling
check: a set logged on the watch earlier is not duplicated by that Sync. Then
edit one of those sets on the phone (change the weight), tap **Sync** on the
watch again: the watch shows the new weight on that same set, not a third set.
Deleting a set on the phone is **not** carried — it stays on the watch.

**The walkthrough** — each step maps to a protocol rule that is already
enforced in code, so a failure points at the transport, not the logic:

1. **The watch says it does not auto-sync.** Before touching anything, confirm
   the wrist shows the label stating there is no automatic sync. Sync is
   user-initiated by design, and the label is what makes that honest rather
   than a bug.
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
4. **Start a session on the phone.** The watch should mirror it: same exercises,
   same order, same current slot. Step *(a)* of the one-session walkthrough is
   this one, and *(b)* is the same session after an edit on the phone.
5. **A session on each device stays where it started.** With the phone's session
   running, start one on the watch and sync: the phone keeps its own and the wrist
   keeps its own (step *(d)* above). No merge, no stray history entry.
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
   it.
10. **Kill the phone app mid-session** and relaunch. The session should restore
   from timestamps, not from a counter — a restored rest timer showing a fresh
   full duration means someone reintroduced remaining-time, which the protocol
   forbids.
11. **Kill the watch app mid-session** and relaunch **(owner)**. Log two sets on
    the wrist, force-quit the watch app with no Sync, then relaunch: the session,
    both sets and the rest countdown are back. Sync: the phone shows the sets
    once.
12. **Quick-log food on the wrist.** It should land on the phone's correct day,
    and a redelivery must not double it.
13. **Sensor path** (after HealthKit is configured): heart rate appears during a
    session; a finished session closes its `HKWorkoutSession`. A workout left
    "in progress" after you force-quit is the specific bug to hunt.
14. **Check Apple Health.** The session should appear there once, not twice.

Steps 15–18 check the session effort rating and all run on the shipped shell.
Steps 19–20 check the heart-rate and step capture and stay with the shipping
plan's Phase 8 (the HealthKit bindings) — see that plan's O-2
(`docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`).

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
17. **The question survives a kill** **(owner)**. End a session on the wrist and
    force-quit the watch app while the question shows. Relaunch: the question
    comes back before anything else, and one answer records one rating. The
    engine restores it from the store that outlives the process
    (`WatchEffortRatingTests.testS215AKillDuringThePromptAsksAgainAndRecordsOneAnswer`);
    the shipped shell builds that store on disk, so this runs on a paired device.
18. **Finishing on either device.** Finish on the phone and sync from the wrist:
    the wrist's session ends and the phone holds one entry (step *(e)* above).
    Finish on the wrist and sync: the phone's copy ends through its ordinary
    finish with the rating the wrist gave (step *(f)* above).
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

### The wrist's own logging (PR 2b)

This walkthrough exercises the wrist logging surface. It has not been run on
hardware yet.

1. **Start a workout on the wrist and pick an exercise.** Tap **Free workout**.
   A Free workout starts with no exercise, so the picker comes up first; pick
   one and the logging screen appears with that exercise's value rows. Dial 3
   reps and tap **Log**: the row is accepted and the rest countdown starts.
2. **The set is on the phone at the moment it is logged.** Phone app in the
   foreground and reachable. Without touching the wrist, the phone's session for
   this wrist session shows the set. The phone must show it before any Sync —
   only an untouched wrist proves the set is handed over as it is logged.
   Nothing is sent on a timer.
3. **End and answer once.** Turn Settings → Effort Rating on, on the phone, and
   sync from the wrist. On the wrist tap **End**; the question appears alone —
   no skip, back or swipe. Answer 4. The phone's calendar holds one entry for
   the session and its Summary shows 4 / 5.
4. **A workout logged with the phone out of reach catches up at the next Sync.**
   Start another wrist workout and log a set with the phone in Airplane Mode.
   Nothing arrives. Turn Airplane Mode off, foreground the phone app and tap
   **Sync** on the wrist: the set lands exactly once.
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

Two known gaps this walkthrough must not be read as failing on: a Sync while a
rest countdown runs stops that countdown (the wrist adopts the answer's empty
timers as authoritative — the reconciliation fixture `timer_cleared.json`,
replayed by `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`),
and the load label is always in kg, whatever unit the phone is set to
(`WatchLoggingTimersTests.testS007APoundPreferenceStepsInPoundsStoredInKilograms`
holds the kilogram payload underneath).

### What "QA passed" means

Levels 1 and 2 green, plus every step at Level 3 on real paired hardware —
steps 15–18 now and steps 19–20 once shipping-plan Phase 8 makes them runnable.
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
