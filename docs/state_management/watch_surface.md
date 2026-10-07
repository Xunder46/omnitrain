# The Watch Surface — Live Mirroring and Sensors

**Scope.** The watch↔phone live mirroring surface (`lib/state/watch/`,
`lib/watch/start/watch_sync_orchestrator.dart`, `lib/core/sync_protocol/`), the
platform transport it rides on (`lib/core/platform/`), and the watch's own
runtime layer (`lib/watch/`, mirrored file for file by
`watch/watchos/Sources/WatchSessionEngine/`), including the sensor layer and the
summaries computed from its readings. These are service-shaped rather than screen
state; the phone half of session capture is
[Watch Session Capture](../watch_session_capture.md), and the remaining service
and utility classes are in
[Service & Utility Classes](services_and_utils.md).

> Part of [State Management & Services](../state_management.md). See that index
> for the full class list and dependency graph.

---

## Watch ↔ Phone Live Session Mirroring

The watch clients are built from the same protocol and the
same fixtures as the phone; the protocol itself is `watch/sync_protocol/PROTOCOL.md`.

### The two reconcilers, and why there are two

| Codebase | Reconciler |
|----------|-----------|
| Phone (Flutter) | `SyncSessionReconciler` — `lib/core/sync_protocol/session_reconciler.dart`, owned by `LiveSessionMirrorState` |
| Wear OS (Flutter) and watchOS (Swift) | `WatchSessionEngine.applyMessage` / `applyMessage(_:)` — `lib/watch/session/watch_session_engine.dart`, `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` |

There are two because the two ends converge on the same state from different
storage: the phone's session lives in memory and its reconciler is a pure
function over the message stream, while the watch's must survive a kill on an
append-only store. The apply *rules* are the same on both — they are the
fixtures' `expected` blocks, and the contract is that both implementations
converge on them. A cheaper-looking single reconciler would have to be the
intersection of two storage models, which is neither.

Verified by `test/live_mirroring_test.dart` and by watchOS
`WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`, which replay
every reconciliation fixture in `watch/sync_protocol/fixtures/manifest.json`
through both.

### `LiveSessionMirrorState`

**File**: `lib/state/watch/live_session_mirror_state.dart`

The phone's view of a session that a watch is running, or that both are. It is
a `ChangeNotifier` wrapping the reference reconciler: validate the envelope,
apply it, then `notifyListeners()`. Phone-originated messages are applied
locally *before* they go to the transport, because the session the user is
looking at has to be the session the watch is told about.

**A snapshot naming another session is a new workout, not a disagreement.** It
replaces the held session wholesale, entries included, clears
`completedRecord`, and is never answered; re-assertion is for a snapshot of the
held session only (PROTOCOL.md, "Idempotency and reconciliation"). Answering it
would pull the wrist back to a session it had finished, and merging would file
one workout's entries under another. Verified by `test/live_mirroring_test.dart`
(`S-251`); same-session re-assertion by its `S-008` group.

**Session-scoped entries are held.** The mirror keeps every entry of the session
it carries, the wrist's `effort_rating` and `session_end` entries included,
because a snapshot it re-asserts must carry every entry; `sessionScopedKinds`
names that kind set. Verified by `test/watch_session_import_test.dart` (`S-268`),
which pins the entries the mirror holds when a snapshot names another session.

**What this phone asserts is its own session, not this copy.** The ladder a wrist
snapshot is answered with is composed on demand from the session the regular
screen is running — the session-adoption bridge projects `WorkoutState` into
protocol shape, the ladder and the `set` entries the phone logged together. The
wrist's snapshot merge stores the entries it does not already hold beside its
own, so a set the phone logged reaches the wrist at its Sync (D-31, D-33) — and
a set edited on the phone is updated on the wrist at the next push or Sync,
re-stated from the answer while the wrist's stored row is left unrewritten
(D-35).
Its slots are that session's efforts, a slot id is the effort's
own row id, and its revision rises only when the ladder changes, so the wrist's
replace-structure rule accepts a real edit and stays silent on a replay of a
snapshot it already holds. This mirror's own copy answers only when the phone has
no session of its own to speak from: nothing bound, no session running, or a
snapshot naming a session this phone is not in. `projectedSession` is what a
snapshot request is answered with, and `sendState` sends a composed answer; the
same projection is what the automatic push sends when the phone's own session
changes (D-75).
Verified by `test/watch_session_projection_test.dart` (`S-2`, `S-8`, `S-6`,
`S-31 the phone's own sets arrive as entries`,
`S-35 an edit reaches the wrist and a delete is not sent`,
`S-35 a re-statement is append-only and doubles nothing`, and the
revision-rises-only-with-the-ladder case), the wrist-side
`WatchPhoneEntriesTests.testS35AReStatementShowsThePhonesNewValueAndLeavesTheRow`
in `watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift`, and
the two stacks' agreement on a re-stated id in
`test/watch_reconciliation_cross_stack_test.dart`
(`S-35 a held id the phone edited is re-stated on the wrist, not resaved`);
`test/watch_transport_test.dart`'s `S-003` group covers the copy's fallback.

`WatchMirrorTransport` is the phone's half of the transport contract: `send`
and `requestSnapshot`. Per-platform carriers (WatchConnectivity, the Wear OS
data layer) implement it; it is fire-and-forget with retries, and the protocol's
idempotency is what makes at-least-once delivery safe. There is deliberately no
reachability flag on it — a send that cannot be carried yet is the transport's
to buffer, not a decision the session logic should make.

Verified by `test/live_mirroring_test.dart` (`S-008`, `S-010`).

#### The same object is the phone's manage-bridge (item 10)

A live session can be *driven* from the phone, not merely watched, and the
mirror is where every one of those edits originates. Its named operations —
`addExercise`, `removeExercise`, `reorderExercises`, `moveExercise`,
`swapExercise`, `correctEntry`, `deleteEntry`, `pushExercise`,
`completeSession` — apply the change locally, then hand the protocol message to
the transport. They exist so no caller has to know a `structure_change` from an
`exercise_push`: a searched catalog exercise is a push (it carries its own
position), while managing the ladder is a change. Both are the phone's to
originate — the watch never does (PROTOCOL.md, authority rules 1 and 2).
Verified by `test/phone_manage_bridge_test.dart` and
`test/live_mirroring_test.dart`; no phone screen calls them yet, and
`lib/state/watch/live_session_mirror_debug_main.dart` is the only caller of this
object outside tests, through `applyStructureChange`.

`reorderExercises` takes a whole order and `moveExercise` is the one-place case
of it, because the protocol carries the ladder rather than a pair of indices;
the arithmetic therefore belongs to the ladder's owner, not to a screen.

`completedRecord` is the merge point: `completeSession` reports the lifecycle
once, snapshots the converged session, and returns the same record on a second
call, so one session closes as one record however many times Finish is tapped.
The entries in it are the reconciler's — ordered by wall-clock `loggedAt`, so
ordering does not depend on which device logged what.

The phone's *ordinary* finish does not call it: a session ended from the regular
screen writes history, and the end is announced the next time the push runs,
because the push reads that session's own row and finds it ended (D-81). A wrist
that ended its own session still learns at its next sync, when its snapshot of
that session is answered with the session's own `completed` lifecycle; see
[Watch Session Sync](../watch_session_sync.md). Verified by
`test/watch_session_auto_push_test.dart`
(`S-72 finishing on the phone ends the wrist's copy, once`) and
`test/watch_session_finish_test.dart` (`S-5` and both of its `G1` cases).

Two rules the bridge depends on, both already in `PROTOCOL.md`:

- **A phone holding no ladder has no shape to assert.** A snapshot of the held
  session is adopted, not answered, while the phone's own ladder is empty —
  answering with an empty ladder would wipe the wrist's. (A session started on
  the wrist names a session the phone does not hold, so the switch rule above
  adopts it.)
- **A correction is addressed by `entryId`, never by the slot.** What a slot
  holds can change under a logged entry, and history records what happened.

Verified by `test/phone_manage_bridge_test.dart` (structure events against the
protocol's own schemas and against the shape
`watch/sync_protocol/fixtures/valid/structure_change.json` pins; interleaved
observations merging into one ordered record) and by
`test/interaction_flow_test.dart` (`Phone manage-bridge for live sessions`).

### `WatchSessionAutoPush`

**File**: `lib/state/watch/watch_session_auto_push.dart`

The one place a session is pushed from the phone (D-75). It binds the same
`WorkoutState` the screen runs, restarts a trailing window on every notification
and, when the window closes, composes the projection fresh and sends it only if
its encoding differs from the last payload this push sent or baselined — so a
rest-timer tick sends nothing and a burst of changes inside one window is one
frame. Nothing is cached: the newest state is the one that matters. The pending
ends are the sessions the phone itself composed whose end is not decided yet:
each is announced by its own id, once, when its own stored row decides it — an
ended row announces `completed`, a row that is gone announces `abandoned` —
never the phone's current-session pointer, which browsing a past session
repoints. A pending session that still runs is kept while the phone is not on
another live session of its own, so browsing away and finishing it afterwards
still announces its end. It adds no queue, no retry and no user-visible state: a
send the transport cannot carry is dropped and leaves the phone undisturbed.
`bindWorkoutState` is idempotent, `rebaseline()` takes the current session as the
baseline while sending nothing (D-82), and `dispose()` unbinds.

Verified by `test/watch_session_auto_push_test.dart`
(`S-70 the phone's own set is pushed as one snapshot, and the wrist's own set is
not sent back`, `S-71 the push reports the wrist's position, not slot 0`,
`S-72 finishing on the phone ends the wrist's copy, once`,
`S-73 discarding on the phone abandons the wrist's copy, once`,
`S-74 five notifications without a change push nothing`,
`S-75 three changes inside the window are one frame`,
`S-84 opening a past session pushes nothing for the live one`,
`S-85 two finishes and a discard are announced once each, under each session's
own id`, `S-85 the end the wrist itself caused is not announced back at it`,
`S-86 the phone's own push does not end the wrist's live session`,
`S-87 a frame the wrist sends inside the window does not lose the finish it
landed in`, `S-87 a frame the wrist sends inside the window does not lose the
discard it landed in`,
`S-88 browsing a past session and then finishing the live one inside one window
still announces the finish`).

### `WatchSyncOrchestrator`

**Files**: `lib/watch/start/watch_sync_orchestrator.dart`,
`watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`

Routes arriving messages to their owner — reference data to the start paths or
the nutrition state, session state to the engine — and owns the connect
exchange that `PROTOCOL.md`'s "Idempotency and reconciliation" section
specifies. Verified by `test/live_mirroring_test.dart` (`S-009`) and by watchOS
`WatchLiveMirroringTests.testJoiningAsksForASnapshotRatherThanOfferingOne`.

### `WatchNutritionState`

**Files**: `lib/watch/nutrition/watch_nutrition_state.dart`,
`watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift`

The wrist's quick-log: the food list the phone sent down, the food and portion
the user has picked, and the observation confirming them produces. It owns no
storage of its own — the synced list is a `WatchFoodCatalogRecord`, the
wrist's own usage is derived from `WatchSessionEngine.nutritionLog`, and the
log itself goes through `WatchSessionEngine.logNutrition`, so a quick-log is an
observation rather than a parallel pipeline.

A quick-log is the one log on the wrist that needs no session: eating is not a
training event, and `observations_up` requires a `sessionId`, so a log taken
with no workout running carries the day's nutrition-log id
(`WatchNutritionSession`) while one taken mid-session rides that session. It is
not acknowledged by a snapshot: the phone's mirror does not hold a nutrition
session, so the entry never comes back that way, and confirmation comes from
the `receipt` message the phone sends instead. The portion control's detents
and bounds are not the wrist's to choose:
`watch/contract/watch_nutrition_contract.json` carries them and both clients'
suites assert against it.

Verified by `test/watch_nutrition_quick_log_test.dart` (S-001 to S-006) and by
watchOS `WatchNutritionQuickLogTests`.

### The wrist's food list, and why its order is the phone's rule

The watch shows the phone's Foods I Eat list in the phone's order — categories
alphabetically, foods the phone files under nothing last, foods alphabetically
inside each — because the phone owns the catalog and the cut of it the user
eats. That rule lives once, in `lib/core/utils/foods_i_eat_order.dart`, as the
`foodsIEatSections` function the phone's `NutritionScreen` renders; the wrist's
`deriveWatchFoodList` applies the same rule to the synced rows and then lifts
what the wrist itself logged most recently to the front, the same shape
`deriveFallbackExercises` uses for the offline exercise list.

Two implementations rather than one because the inputs differ: the phone has
`Food` and `FoodGroup` rows, the wrist has the protocol's row maps. The values
they must agree on are pinned by `watch/contract/watch_nutrition_contract.json`
— phone order, wrist order after a known log history, and the portion bounds —
which `test/watch_nutrition_quick_log_test.dart` (S-003) and watchOS
`WatchNutritionQuickLogTests.testTheWristDerivesTheContractsOrder` both read.
A change to the ordering on either platform therefore fails the other's suite.

### `WatchReferenceSync`

**File**: `lib/core/utils/watch_reference_sync.dart`

Builds the reference-data messages the phone sends down — `foods_down`,
`routines_down` and `preferences_down` — and nothing else. Building and carrying are separate jobs, so
it hands back an envelope and owns no transport; the foods' order is the phone's
own Foods I Eat order rather than a rule the wrist has to be told, and the energy
per serving comes from `calculateCalories` rather than being derived a second
time. It sits beside `foods_i_eat_order.dart` because it is a pure function over
the phone's models, with no state and no storage.

`buildRoutinesDown` returns **null** rather than an empty message when the phone
holds nothing the wrist could start. `routines_down` requires at least one
routine and at least one fallback exercise, so a phone that sent an empty list
would be sending a message the wrist must reject; a null is the honest answer to
"nothing to sync". It also skips an exercise with no capabilities, because
`sessionExercise` requires a non-empty `capabilities` array — a slot without one
would fail validation before any renderer saw it.

Two mappings in that builder are not mechanical, and both are the phone's
decision rather than the wire's:

- **Effort kind.** The app's `BlockTypes` vocabulary is larger than the wire's
  (`interval` is timed work, `amrap` is rounds, a `note` carries no exercise and
  never reaches here). The mapping is the phone's to make because the phone is
  the one that knows what the user built.
- **Targets.** A routine's targets are per metric *and per set*; the wire's
  `targets` is per effort, so the first set travels and the phone's own screen is
  where the rest stay. Durations are stored in seconds and travel in
  milliseconds; metrics the wire has no key for (RPE, rest, the `extra-weight`
  metric) are not sent, because the schema carries no field for them.

`preferences_down` is its own message rather than a field on `routines_down`
because `buildRoutinesDown` answers null for a phone with no routines, and a
setting riding on it would then never reach the wrist. Its message id follows
its content as well as its `generatedAt`: the wrist keeps the newest copy and a
tie goes to the later-received one, so two different settings stamped in the
same millisecond must not share a delivery key.

Verified by `test/watch_reference_sync_test.dart` (S-003, S-004, S-007, S-253)
and `test/watch_nutrition_quick_log_test.dart` (S-003, for the foods half).

### The watch transport

**Files**: `lib/core/platform/watch_transport.dart`,
`lib/core/platform/watch_connectivity_channel.dart`,
`lib/core/platform/no_watch_transport.dart`,
`lib/core/utils/platform_watch_transport_factory.dart`

One object is both the watch's `WatchSyncTransport` and the phone's
`WatchMirrorTransport`, because they are one radio: `WatchTransport` extends both
and adds `onIncoming`, the single handler every arriving frame is handed to.

**The package boundary is `WatchMessageChannel` and nothing else.**
`watch_connectivity` is imported in exactly one file
(`watch_connectivity_channel.dart`); `WatchConnectivityTransport` is written
against the `WatchMessageChannel` interface, which is what lets a hand-rolled
`MethodChannel` + `WCSession` layer, or a Wear OS data-layer one, replace it
without touching a caller.

**Nothing is queued in the app layer.** A send the radio refuses is reported
through the transport's `onFailure` and dropped; what the peer still owes is
re-sent from storage on the next sync (PROTOCOL.md, "Idempotency and
reconciliation"). The transport is fire-and-forget by design — a queue here would
be a second source of truth about what has been delivered.

**A request is not a message.** PROTOCOL.md says so normatively, and
`WatchTransportRequest` is where that lives: a frame with no `type` is a request
(`routines` or `snapshot`), and a frame with one is a protocol message.
`WatchConnectivityTransport` implements the request calls over that one
vocabulary, so adding a request does not add a wire type.

**Platform choice happens once**, in `createPlatformWatchTransport`: iOS gets
`WatchConnectivityTransport`, and web, desktop, and Android get `null` — Android
until the Wear OS client is built. It reads `defaultTargetPlatform` rather than
`dart:io`'s `Platform`, because this file is compiled for web too, and a failure
to construct answers null rather than refusing to start the app.

Verified by `test/watch_transport_test.dart` (S-001, S-002, S-003, S-006, S-009)
over an in-memory two-ended channel.

#### The wrist's half of the same radio

**Files**: `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift`,
`.../PropertyListFrames.swift`; the real session is
`ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`.

The wrist's transport is written against a seam rather than against
`WatchConnectivity`: `WatchConnectivitySession` is send, report a failure, report
reachability and deliver an arriving frame, and `WatchConnectivityBridge` is the
`WatchSyncTransport` conformance over it. That seam is what lets the whole bridge
run under `swift test` on macOS against a fake session; the only file that
imports `WatchConnectivity` is the app target's, and it supplies the real
session and nothing else.

**A request frame is byte-for-byte the phone's shape and carries no `type`**,
because the presence of `type` is what makes a frame a message rather than a
request. `since` is omitted rather than nulled when the wrist has never synced,
and is formatted by the package's own UTC encoder — three fractional digits,
where Dart's `toIso8601String()` can emit six. The divergence is known and
unread, because the phone ignores `since` today. The three frames are pinned in
`watch/contract/watch_start_paths_contract.json` under `transportRequests`, which
both suites read. Verified by
`WatchConnectivityBridgeTests.testS102FirstSyncAsksForRoutinesWithNoSince`,
`…testS103LaterSyncCarriesSince` and `…testS104SyncWithNoSessionAsksForASnapshot`.

**An outbound frame is checked for plist safety before the radio sees it.** A
`WCSession` message dictionary holds property-list values only, and `NSNull` is
not one — the platform rejects the whole message, so the check refuses the frame
rather than stripping the null, and reports it through the same failure hook a
refused send uses. `Date` becomes the package's UTC string, and `String`, `Bool`,
`NSNumber`, arrays and dictionaries of accepted values pass through **unchanged**
— an `Int` stays an `Int` and a `Double` stays a `Double`, because the protocol's
integer fields are integers and the phone's validator refuses a whole-number
`Double` (witness: `fixtures/invalid/observations_up_steps_as_double.json`). The
refusal costs nothing today because the wrist's wire encoders omit absent
optional fields rather than nulling them; it turns a future regression into a
reported failure instead of a silently dropped message. Verified by
`WatchConnectivityBridgeTests.testS112TheFramesTheWristSendsSurviveThePlistRoundTrip`,
`…testS113AFrameThatCannotBeRepresentedIsReported` and
`…testD5NumbersAreNeverCoerced`.

**Nothing is queued on the wrist either**, for the phone transport's own reason:
a send that fails is reported and dropped, and recovery is the next `sync()`
re-sending from storage. **The bridge itself sends nothing unsolicited** — it
answers a user action or nothing, so a Sync is still the only thing that asks the
phone for an answer. Verified by `WatchConnectivityBridgeTests.testBridgeSendsNothingUntilAsked`
and `…testASendThePlatformRefusesIsReported`.

**Reachability is three-state, and starts unknown.** The wrist says the phone is
unreachable only once the radio has said so; a launch that has asked nothing
says nothing. `WatchPhoneReachability.unknown` is the state a `Bool` cannot
express, which is why the app target's host starts there and moves only when the
bridge reports what the platform observed — the platform's answer is always an
observation, never a "not yet". Verified by
`WatchConnectivityBridgeTests.testS111TheSurfaceSaysUnreachableOnlyAfterObservingIt`.
The sentence lives in the package's `WatchStartSurfaceCopy` rather than the
contract's `startSurface` block; it moves into the contract if the Wear OS client
ever ships a transport.

#### The wrist's start surface, and what an arrival does to it

**A push with no session to land in is read and dropped.** The wrist's start
paths can only grow a session that exists, so an `exercise_push` arriving with
nothing open changes nothing, stores nothing and creates nothing: the engine
returns nil instead of requiring a session, and the message reports itself not
applied. The guard sits *after* the conformance gate on purpose — a frame this
build cannot read is still a refusal, while a readable frame with nowhere to go
is simply nothing to do. Verified by
`WatchConnectivityBridgeTests.testS110APushWithNoLiveSessionChangesNothing` and
`…testS108APushIntoAnOpenFreeWorkoutLands`.

**An arrival is a revision, not a listener.** `WatchSessionStartPaths` is a plain
class that publishes nothing, so the app target's host bumps its own revision on
every frame it routes and hands it to the start surface, which is what re-runs
the picker's body; the rows themselves are derived on every read. Whether a push
that lands while the picker is open appears without the user leaving and
re-entering it is an owner-run check — step 7 of the push-path walkthrough in
[the setup and QA guide](../watch-app-setup-and-qa.md) — not a tested behaviour.
A row is keyed by its own slot id rather than by the exercise, because one
exercise may legitimately hold two slots, and the session's slots come first with
the fallback list minus what the ladder already shows behind them. Verified by
`WatchConnectivityBridgeTests.testPickerRowsListTheSessionFirstAndNeverTwice` and
`…testPickerRowsFallBackToTheFallbackListWhileTheSessionIsEmpty`.

#### The wrist shell's second surface

Once a session is open, the shell's second surface is the package's logging view
for the current exercise: the exercise's own effort kind — a set, a timed hold, a
round or a drill — with the value rows that effort needs, End leading the
toolbar and the exercise picker behind a list button. A logged set starts a rest
countdown of the surface's own length
(`WatchLoggingTimersTests.testS005LoggingASetStartsARestCountdownOfTheSurfaceLength`).

Logged rows leave the wrist as they are logged: the engine's emissions go to
`WatchEmitForwarder` over the connectivity bridge, in emission order, and a
refused frame is reported once and dropped without disturbing the frames behind
it (`WatchEmitForwarderTests.testTheEnginesEmissionsReachTheSinkInOrder`,
`…testEveryRefusedFrameIsReportedOnceAndDropped`). An ended session is no longer
a logging surface
(`WatchLoggingSurfacesTests.testS029AnEndedSessionCannotBeLoggedInto`; on the Dart twin,
`test/watch_logging_surfaces_test.dart`'s `S-52 the wrist's own End closes the logging surface`
and `S-52 a session the phone ended is not a surface to log into`).

The shell builds an append-only file store, `FileWatchSessionStore`, over the
app's Application Support directory (`watch-session/`), so a relaunch brings back
the session, its logged rows, a running rest countdown and any unanswered rating
question; the engine is restored at launch, before the start paths, preferences
and rating. What survives is asserted by the store's two-engine cases
(`watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift`:
`testS44ALoggedSetSurvivesTheProcess`,
`…testS46ACountdownThatWasRunningIsStillRight`,
`…testS47TheOwedRatingQuestionSurvivesTheKill`), and that a commit which suspends
still shows the owed question by
`WatchEffortRatingTests.testS55ASlowCommitStillShowsTheOwedQuestion` and
`…testS55ASlowAnswerNotifiesAfterTheRatingIsRecorded`. Two smaller gaps: the
wrist labels load in kilograms whatever the phone's unit preference says, and a
countdown the phone wrote stops when a Sync arrives while one the wrist started
keeps running, because the phone's answer carries no timers (D-26, D-80; on the
Dart twin, `test/watch_logging_timers_test.dart`'s `S-79 a snapshot leaves the
wrist's countdown running and stops the phone's own`). What a relaunch does not keep is the projection lens:
a re-stated entry holds the phone's new value only until the process ends, and
the stored first value shows again until the next Sync re-states it (D-50,
`WatchFileStoreTests.testD50ARestatedSetShowsItsFirstValueAfterARelaunchUntilTheNextSync`).

### `WatchSyncRequestHandler`

**File**: `lib/state/watch/watch_sync_request_handler.dart`

Answers the frames that are requests rather than protocol messages: `routines`
is answered with `preferences_down` first and always, then with `routines_down`
when the phone holds any, both built through `WatchReferenceSync`; `snapshot`
re-asserts the phone's session. It is separate from `WatchIncomingRouter`
because the two answer different kinds of frame, and merging them would make a
transport detail a protocol one.

**Nothing here answers a request the wrist has not made.** There is no phone-side
schedule and no launch-time push, which is why the preferences ride every
`routines` request: a setting changed on the phone reaches the wrist at the
wrist's next sync. The value is `SettingsState`'s own toggle, never a re-read of
the stored preference. A phone holding no routines sends no `routines_down`,
and one holding no session answers a `snapshot` request with nothing: the wrist
keeps the copy it has, and an empty answer would be a state it never asked for.

Verified by `test/watch_transport_test.dart` (the `S-003` and `S-253` groups).

### `createWatchSync` — the phone's watch graph

**File**: `lib/state/watch/watch_sync_wiring.dart`

The one place the phone's watch graph is built: transport, `WatchSessionInbox`,
`LiveSessionMirrorState` (whose transport stages the phone's corrections in the
inbox), `WatchIncomingRouter` (inbox + mirror + nutrition bridge), and
`WatchSyncRequestHandler` (which reads the wrist-facing settings from
`SettingsState`), with the transport's inbound handler dispatching between the
last two. It resumes any import the phone had not run when it last stopped;
see [Watch Session Capture](../watch_session_capture.md). It returns a
`WatchSyncGraph` — the mirror, the inbox behind `WatchSessionRatings` and
`WatchLateEntryRecovery`, and the adoption bridge — or null when the platform has
no watch, which is what keeps the environment contract intact: a platform without
a wrist builds none of it.

The graph carries a second handle, `WatchLateEntryRecovery`, which is the same
inbox behind a narrower capability: recovering the entries that arrived while an
Edit Session was open, so a Discard does not lose a set the user logged on the
wrist. `main.dart` hands it to `WorkoutState`, which passes it to the session
core's restore. Verified by `test/watch_session_edit_restore_late_entry_test.dart`
(`S-1401` to `S-1410`).

Two construction details are load-bearing:

- The mirror starts from `watchSessionPlaceholder` — a **valid but unheld**
  session id with status `abandoned` and no ladder. The id is not empty because
  every envelope the phone builds carries it and the protocol requires a
  non-empty `sessionId`; the status is `abandoned` so nothing offers a
  session-less phone as live, and the missing ladder means the first real shape
  arrives from the wrist (a session started there) rather than being asserted.

Verified by `test/watch_transport_test.dart` (S-006) for the platform decision
and the null answer, and by its S-001 cases for the placeholder: a phone whose
id the wrist does not hold is a phone whose pushes the wrist ignores, which is
why the id is valid rather than empty.

### `WatchIncomingRouter`

**File**: `lib/state/watch/watch_incoming_router.dart`

The one place a message arriving from a wrist is handed to its owners:
`WatchSessionInbox`, `LiveSessionMirrorState` and `WatchNutritionLogBridge`.
Each is asked about every message, and each answers for itself which messages
are its own — the inbox by entry kind, the mirror by session identity, the day
log by observation kind — so a message that belongs to several is not forced to
pick one, and a caller does not have to know that a quick-log can be session
news and food intake at once. Verified by
`test/watch_nutrition_quick_log_test.dart` (S-002), whose cases cover a
standalone quick-log, a session's own message, and a quick-log taken with a
session running.

The inbox is asked first, so what a wrist session will become in history is
durable before anything else can answer the message; see
[Watch Session Capture](../watch_session_capture.md). Verified by
`test/watch_session_import_test.dart` (`S-261`).

The session the wrist is running is adopted last, after the mirror has answered:
a snapshot the mirror applied is projected into the phone's own session state
(D-2). Both directions of *ending* are answered here too — a wrist
`session_lifecycle` ends the phone's copy through the ordinary finish or discard,
and a snapshot naming a session whose row already has an end is answered with that
session's `completed` lifecycle instead of being adopted back. See
[Watch Session Sync](../watch_session_sync.md). Verified by
`test/watch_session_finish_test.dart` (`S-4`, `S-5`, `G1`, and the wrist's set
merging into the session the phone holds — `a set logged on the watch lands in
the session the phone holds` — and the lifecycle-naming-another-session case).

### `WatchNutritionLogBridge`

**File**: `lib/state/watch/watch_nutrition_log_bridge.dart`

The phone's half of a quick-log: it turns the wrist's `nutrition_quick_log`
events into the phone's own day log through `NutritionState.logConsumedFoodAt`.
A quick-log is filed by the phone's rule, not the bridge's — one row per food
per day means a redelivered message updates the row it made the first time, so
"exactly once" needs no ledger of its own. A food the library no longer holds is
reported rather than guessed at: with no food there are no macros to freeze onto
a row.

It is also the sender of the `receipt` that acknowledges those observations —
including the ones it could not place, since what a receipt asserts is that the
phone holds the observation, not that the day log changed. It answers a message
it refused to read with nothing at all. What the wrist does with the receipt is
`WatchSessionEngine.confirmObservations` — an append of its own, so a relaunch
can still tell what it may drop — and `pruneConfirmed`, which is the only way
the observation box gives rows back. Both are exercised by
`test/watch_nutrition_quick_log_test.dart` ("the phone’s receipt is what lets the
watch drop the row", "a food the phone cannot place is not owed forever") and by
`WatchNutritionQuickLogTests.testThePhonesReceiptIsWhatLetsTheWatchDropTheRow`.

The other half of the same problem is on the mirror: `LiveSessionMirrorState`
ignores any message it consumes whose `sessionId` is not the session it holds
(`session_snapshot` excepted), because a quick-log taken with no workout running
names the day, and filing a meal under a workout is worse than dropping it.

### Invariants

- **Nothing is written twice.** A structure change is keyed by `changeId`, and
every row the watch writes from a message carries an id derived from that
message, so re-delivery is a store-level no-op. Verified by
`test/live_mirroring_test.dart` (`S-007 forced redelivery produces no
duplicates`) and by watchOS
`WatchLiveMirroringTests.testReplayingTheStreamTwiceConvergesIdentically`.
- **The watch store stays append-only.** A phone correction is a *projection*
(`WatchSessionEngine.entries`), not an edit: the stored observation row is never
rewritten. Verified by `test/watch_session_engine_test.dart` (`S-004 append-only
enforcement at the storage API`).
- **An incoming message has one gate.** `SyncProtocolValidator.evaluateOrAccept`
(Dart) and `SyncProtocolValidator.incomingRejections` (Swift) own the version
check and the conformance verdict, including the case of a receiver that carries
no schemas — a receiver that cannot read is not a receiver that should refuse.
Every receiver that takes a message from a peer goes through it: the live
mirror, the nutrition log bridge, the watch session inbox, and each engine's
`_requireConformingIncoming`
/ `requireConformingIncoming`, which differ only in what they do with a
refusal. Verified by `test/sync_protocol_fixtures_test.dart` (`the receiver
gate`), which exercises the shared gate directly, including its no-schema
branch; the per-receiver outcomes are covered by
`test/live_mirroring_test.dart` and `test/watch_session_engine_test.dart`.
- **Outbound is a different question from inbound.** The gate above judges what
a peer sent. What this build is willing to *send* is `requireConformant`, and it
asks `validateEnvelope` directly because the version on an envelope this build
wrote is not in doubt. Every message the app builds goes through one builder,
`phoneEnvelope` (`lib/core/sync_protocol/phone_envelope.dart`), so its producers
cannot spell the envelope's fields differently — `buildFoodsDown`,
`snapshotEnvelope`, the mirror's own messages and `receiptFor`. The QA harness at
`lib/watch/debug/watch_start_debug_main.dart` is the exception: its two seeds are
`const` fixtures standing in for a transport no desktop run has, and a `const`
cannot call a function. Verified by the protocol fixture suites.

## Watch Sensors and the Platform Workout

Both watch clients run the same layer: `lib/watch/sensors/`
and `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` +
`WatchSensorRecording.swift`. The steps sensor and the summaries computed from the
readings (`WatchSensorSummaries.swift`) exist only in the watchOS package:
`lib/watch/` records no steps and computes no summaries.

### Structure

| Concern | Owner |
|---------|-------|
| The OS-level workout registration | `WatchPlatformWorkout`, over a `WatchPlatformWorkoutStore` the app target implements |
| What the device's sensors read | `WatchSensorRecorder`, over a `WatchSensorSource` the app target implements |
| Writing the readings one at a time | `WatchSensorWrites`, inside `WatchSensorRecorder` |
| Starting and stopping both together | `WatchSessionSensors` |
| Whether a session records GPS | `WatchGpsPolicy`, reading the modality's capability profile |
| Modality → platform workout type | `WatchActivityTypes` |
| What is computed from the readings before they may go | `WatchSensorSummaries`, pure functions over stored rows, called by `WatchLoggingState.log` for an entry and by `WatchSessionEngine` for a `session_end` |

`WatchSensorSource` and `WatchPlatformWorkoutStore` are the seam the OS bindings
sit behind, and they are why this layer is testable: `HKWorkoutSession`,
`HKLiveWorkoutBuilder` and `CLLocationManager` exist only in an app target, so
neither `swift test` nor a Dart suite can reach them directly. The
implementations in the tree are the two suites' fakes and the QA harness's own
defaults: `test/watch_sensor_recording_test.dart`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift`, and
`lib/watch/debug/watch_session_debug_surface.dart`, which takes both seams as
constructor parameters and passes a no-permission source and a no-op store when it
is given none. Which app target provides the real bindings, and what that means
for acceptance criterion 2, is recorded in
[the documentation audit](../docs-audit-2026-07-26.md) §8.6.

### Rationale

**Sensor readings are stored rows, not fields.** A heart rate or a distance is
appended to the watch's own store like everything else, and the live readout is
derived from the newest stored row. A value held in memory would be the one thing
on the wrist that a kill loses, and the whole watch design exists to avoid that.

**Sensor rows are dropped with the session, not with a receipt.** Observations
are gated on the phone's receipt because the phone is their destination. A
reading's destination is the session that produced it: once a session is over and
every entry it produced — and, for a session the wrist created, its `session_end`
— has been acknowledged, its raw log has done its job. The distance that reached
the phone is already the logged effort's `distanceMeters` — the protocol's own
field — so no message type was added and the phone holds one source of truth for
how far the user went. A session still running, or one with an entry still
awaiting a receipt, keeps its log, which is what keeps the live readout and the
settled distance across a kill.

**Summaries are computed on the wrist, once, before the readings may go.** The
phone never receives a raw reading, and the wrist prunes its readings once the
phone holds the session, so anything derived from them has to be derived first and
carried by an event the phone already imports. An entry's heart rate, and a timed
entry's steps, are computed when it is logged, over the window the event itself
states; the session's heart rate and each set block's are computed into the
`session_end`, because a set has no window of its own — it carries only the moment
it was logged. Nothing is recomputed afterwards: the stored event is what is re-sent,
so the phone never sees one entry with two sets of values.

**One writer.** Every sensor streams on a task of its own, and because steps are
recorded in every session the user allows it for, at least two streams run at
once. The engine and its store are built for one writer, so the recorder chains
its writes (`WatchSensorWrites`) rather than letting a second always-on sensor
become a second concurrent writer.

**The workout is recovered, not resumed.** A kill cannot be caught, so the next
launch ends whatever the health store still reports as running rather than trying
to adopt it. The session it belonged to is already over as far as the process is
concerned, and its logged entries are in storage either way. Verified by
`test/watch_sensor_recording_test.dart` (`S-005`) and by watchOS
`WatchSensorRecordingTests.testS005TheNextLaunchEndsTheWorkoutTheKillLeftBehind`.

### Invariants

- **GPS activation derives from the modality's capability profile, never from its
name.** A modality added later is handled without touching the policy, and one
that merely sounds like distance work does not wake the radio. Verified by
`test/watch_sensor_recording_test.dart` (`S-008`) and by watchOS
`WatchSensorRecordingTests.testS008TheGpsDecisionFollowsTheCapabilityProfile`.
- **A denied permission or absent hardware never blocks logging.** The
subscription is skipped and nothing else changes; sensor fields are simply
absent. Verified by `S-006` in both sensor suites.
- **Both clients read one vocabulary.** The sample kinds, the modality → workout
type table and the capability profile the GPS decision depends on live in
`watch/contract/watch_sensor_contract.json`, and both suites assert against it, so
a change on one platform fails the other's tests.
- **A reading is stored, never sent.** Sensor rows are written through the same
append entry point as every other row and emit nothing; the measured distance
reaches the phone inside the logged effort. Verified by
`test/watch_sensor_recording_test.dart` (`a reading is stored without being sent
anywhere`) and by watchOS
`WatchSensorRecordingTests.testAReadingIsStoredWithoutBeingSentAnywhere` and
`WatchSensorRecordingTests.testS239AppendingAStepCountEmitsNothing`.
- **The summary fields are the only values derived from readings on the wire,
and none is ever recomputed.** They are the heart-rate, steps, pause and set-block
fields `watch/sync_protocol/PROTOCOL.md` lists under "Session capture"; a re-send
carries the stored event, whatever readings arrived later. Verified by watchOS
`WatchSensorSummaryTests.testS238ALateReadingNeverRewritesWhatWasSent` and
`WatchCaptureContractTests`, which replays
`watch/contract/watch_capture_contract.json` and compares every event.
- **Nothing measured is absent, never zero.** A window with no qualifying reading
gets no pair and no step total, and a reading a summary could not send — below the
protocol's heart-rate minimum, negative, or not a number — is not a reading. A
summary therefore never makes its event unsendable. Verified by watchOS
`WatchSensorSummaryTests.testS235WithTheSensorsDeniedNoEventCarriesASummary` and
`WatchSensorSummaryTests.testAReadingBelowOneBeatPerMinuteIsNotAHeartRate`.
- **Steps change nothing else.** With steps permission refused, every other sensor
behaves exactly as with it granted. Verified by watchOS
`WatchSensorRecordingStepsDeniedTests`, which runs the whole sensor suite again with
steps denied, and `WatchSensorRecordingTests.testS239StepsPermissionChangesNothingButTheStepsRecorded`.
- **Two prunes, both gated on having nothing to lose.** The store's public surface
is exactly `append`, `readAll`, `pruneConfirmed` and `pruneSensorSamples`;
confirmed observations go first, and a session's sensor log goes only after the
session is over, all of its entries are acknowledged and — for a session the
wrist created — its `session_end` is acknowledged, pruned or not. Verified by
`test/watch_session_engine_test.dart` (`S-004 append-only enforcement at the
storage API`) and by watchOS
`WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule` and
the `S-237` cases in `WatchSensorRecordingTests`.
- **A prune that cannot be written replaces nothing, and a pruned row takes its
lens with it.** The file keeps its rows and the cache keeps reading them, with no
staging file left in the store's directory (`WatchFileStoreTests`
`testF2APruneThatCannotBeWrittenPrunesNothing`,
`testG1APruneOfSensorSamplesThatCannotBeWrittenPrunesNothing`,
`testG2AFailedReplaceLeavesNoTemporaryFile`). A pruned row also takes the
correction the phone sent for that id and any deletion marker against it (D-52),
so a re-carried id reads as what was delivered instead of through a lens left
over from a row that is gone
(`WatchSessionEngineTests.testS48APrunedRowTakesItsCorrectionWithIt` and
`…testS48APrunedRowTakesItsDeletionMarkerWithIt`; `test/watch_session_engine_test.dart`
group `S-48 a pruned row takes its lens with it (G3)`).
- **Timers travel as wall-clock timestamps.** A countdown is never sent;
either end derives it, which is what keeps a timer correct through a
suspension or a reconnect. Verified by `test/live_mirroring_test.dart`
(`S-005 the timer's end moment is the same on both devices`).
- **A message a receiver cannot read is refused whole.** Nothing is applied, and
the refuser answers with its own snapshot so the peer converges from real state
instead of from a stream it could not interpret. Verified by
`test/live_mirroring_test.dart` (the two `a message the receiver cannot read`
cases) and by watchOS
`WatchLiveMirroringTests.testAVersionMismatchIsRefusedAndAnsweredWithASnapshot`.

### Vocabulary

- **Snapshot exchange** — the connect/reconnect handshake defined in
`PROTOCOL.md` under "Idempotency and reconciliation".
- **Correction vs. observation** — an observation is an append by whoever logged
it and is never edited; a correction is the phone's edit to an existing entry,
which the watch reflects without rewriting its own history.
- **Reflection** — a watch's copy of session structure or timer state, which it
holds but does not originate. `PROTOCOL.md` authority rules 1 and 2 are what
make the distinction consequential.
- **Session end, set block** — defined in
[Watch Session Capture](../watch_session_capture.md), which owns what the wrist
sends for the import.

---

> **Doc freshness** — Last reconciled against source: 2026-09-20. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
