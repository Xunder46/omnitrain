# The Watch Surface — Live Mirroring

**Scope.** The watch↔phone live mirroring surface (`lib/state/watch/`,
`lib/watch/start/watch_sync_orchestrator.dart`, `lib/core/sync_protocol/`,
`lib/core/utils/watch_reference_sync.dart`), the
platform transport it rides on (`lib/core/platform/`), and the watch's own
runtime layer (`lib/watch/`, mirrored file for file by
`watch/watchos/Sources/WatchSessionEngine/`). These are service-shaped rather than screen
state; the phone half of session capture is
[Watch Session Capture](../watch_session_capture.md), and the remaining service
and utility classes are in
[Service & Utility Classes](services_and_utils.md).

> Part of [State Management & Services](../state_management.md). See that index
> for the full class list and dependency graph.

The watch's sensor layer and the platform workout — `WatchPlatformWorkout`,
`WatchSensorRecorder`, `WatchSessionSensors`, `WatchSensorCoordinator`,
`WatchGpsPolicy`, `WatchActivityTypes`, `HealthKitSensorFeed` and the summaries —
are in [The Watch Sensors and the Platform Workout](watch_sensors.md).

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
changes (D-75). `sendRatingFor` sends that same converged state with one
`effort_rating` entry appended under the wrist's own id, `rating-<sessionId>`,
for the phone that answered the effort question first (plan 42b).
`holdsEffortRating` reports whether the held entries already contain one — the
echo guard that keeps the wrist's own answer from being sent back. Verified by
`test/rating_first_answer_push_test.dart` (the `S-4306` and `S-4307` groups).
Verified by `test/watch_session_projection_test.dart` (`S-2`, `S-8`, `S-6`,
`S-31 the phone's own sets arrive as entries`,
`S-35 an edit reaches the wrist and a delete is announced`,
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
data layer) implement it; the protocol's idempotency is what makes at-least-once
delivery safe.

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
originate — the watch never does — and so is the reset that ends a wrist session
the phone is not in: an `abandoned` lifecycle naming that session, sent ahead of
the phone's own state (PROTOCOL.md, authority rules 1 and 2; D-170).
Verified by `test/phone_manage_bridge_test.dart` and
`test/live_mirroring_test.dart`; no phone screen calls them yet, and
`lib/state/watch/live_session_mirror_debug_main.dart` is the only caller of this
object outside tests, through `applyStructureChange`. The reset itself by
`test/watch_session_auto_push_test.dart`
(`S-172 the pass sends abandoned(W) then P's own state, and the wrist's answer is
what converges the pair`).

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
rest tick sends nothing and a burst of changes inside one window is one
frame. Nothing is cached: the newest state is the one that matters. The pending
ends are the sessions the phone itself composed whose end is not decided yet:
each is announced by its own id, once, when its own stored row decides it — an
ended row announces `completed`, a row that is gone announces `abandoned` —
never the phone's current-session pointer, which browsing a past session
repoints. A pending session that still runs is kept while the phone is not on
another live session of its own, so browsing away and finishing it afterwards
still announces its end. It adds no queue, no retry and no user-visible state.
`bindWorkoutState` is idempotent, `rebaseline()` takes the current session as the
baseline while sending nothing (D-82), and `dispose()` unbinds. Since plan 64,
`rebaseline()` is skipped when `WatchSessionAutoPush.hasUnsentChange()` was true
before the frame — the phone's composed session differs from the last baseline,
which covers an edit logged inside the 250 ms debounce window and a state an
earlier undelivered push still owed — so the edit is not baselined away as
already sent, and the `push.flush()` that follows the frame sends it. One more step
runs in the same pass, right after the end is announced and before the
ended-session early return: when the phone's current session is ended and rated
but the mirror holds no `effort_rating` entry, `_pushRating` tells the wrist the
phone's answer through `LiveSessionMirrorState.sendRatingFor` — once per session
id, and only a delivered send is remembered, so an undelivered frame is offered
again at the next notification (plan 42b). Verified by
`test/rating_first_answer_push_test.dart` (the `S-4306` to `S-4309` groups).

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
`S-86 the push ends the wrist's session as a deliberate reset and never as an
end the phone was told about`,
`S-87 a frame the wrist sends inside the window does not lose the finish it
landed in`, `S-87 a frame the wrist sends inside the window does not lose the
discard it landed in`,
`S-88 browsing a past session and then finishing the live one inside one window
still announces the finish`, group `S-200 a frame the radio did not carry stays
owed`, `S-200 the baseline does not advance on an undelivered send, so the same
state is offered again when the radio comes back`, group `S-205 a frame from the
wrist re-offers what is owed, never itself`, `S-205 (S-209) the wrist's own set
arrives while a deletion is owed: the owed state is re-offered after it (plan
64), and the wrist's own row is still not echoed`, group `S-9400 an edit the
phone has not pushed survives a wrist frame` (`S-9401 the phone's own set,
logged before the wrist's frame, rides the snapshot sent after the frame is
handled`, `S-9405 a push the radio did not carry is offered again once the
wrist's frame proves the link`).

`WatchTimerPush` (`lib/state/watch/watch_timer_push.dart`) is the timer
sibling of the auto push: the same bound `WorkoutState`, trailing debounce and
one-drain shape, but each pass composes the session's in-progress work timers
and the phone's open rest — read through `WorkoutState.inProgressRest()`
(`TimerManager.inProgressRest`, the newest open `EntryRest` across the
efforts) — and sends only what the wrist does not already hold, as one
`timer_state` frame through `LiveSessionMirrorState.sendTimers` — the wrist's
earlier start wins for the work kinds, a finished interval is cleared once, and
a replacement clears first. The rest travels as a `rest` timer with no slot and
no planned length (a rest is a count-up and belongs to no slot), running or
paused with its pause bookkeeping, and a rest the phone no longer holds open
goes out as `{rest: null}`; a wrist rest started within 2000 ms of the phone's
is the same rest and is not echoed back, while one outside that tolerance is a
different rest and is sent. Built in
`createWatchSync` and returned as `WatchSyncGraph.timerPush`. Its own trigger
is a change of the bound `WorkoutState`; the inbound-frame handler that flushes
the auto push flushes the timer push too, under the same reset gate (54 D-1,
`lib/state/watch/watch_sync_wiring.dart`), so a wrist out of reach is served at
the next frame the wrist sends, not only at the next phone state change. That
flush is clears only (`WatchTimerPush.flushClears()`): it re-offers the
`{kind: null}` frames the wrist is owed and withholds a start, so a timer the
wrist has already ended is not restarted, while an ordinary `flush()` that
joins or follows a clears-only drain still gets its full pass. Verified by
`test/watch_timer_push_test.dart` (the `S-6211` to `S-6217` groups; the rest,
`S-7301` to `S-7310`; the inbound-frame re-offer, groups `S-8406 the end of the
effort reaches the wrist at the next conversation`, `S-8407 a reset-answered
frame flushes no timers` and `S-8408 an ordinary flush is not starved by a
clears-only drain`).

`WatchTimerAdoption` (`lib/state/watch/watch_timer_adoption.dart`) is the
receiving sibling: built in `createWatchSync` as `WatchSyncGraph.timerAdoption`,
it listens to the mirror and the bound `WorkoutState` and hands each wrist
timer to `WorkoutState.adoptRemoteWorkTimer`; the open screen's
`_adoptRunningTimerState` then runs it. Verified by
`test/watch_timer_adoption_test.dart` and
`test/watch_timer_adoption_screen_test.dart` (`S-6111` to `S-6125`
tests).

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

`select` starts a food at its own starting amount: the `defaultServings` of the
wrist's newest `engine.nutritionLog` observation for that food when the log's
`loggedAt` is later than the held catalog's `generatedAt`, and the catalog's
value otherwise — compared on every read rather than stored beside the list, so
a relaunch keeps it and a list the phone generated after the log wins
(`WatchNutritionFreshnessTests.testS8302ALogBecomesTheFoodsStartingAmount`,
`…testS8303ANewerListWinsAndAnOlderOneDoesNotRevertALog`,
`…testS8304ARelaunchKeepsTheDerivedStartingAmount`,
`…testS8306ALogOlderThanTheCatalogKeepsTheCatalogsAmount`,
`…testS8315ASelectionClampsTheListedAmount`). `deselect()` clears the selection,
puts the portion back to `minServings` and drops the confirmation, so the next
food opens at its own amount
(`…testS8301LeavingAFoodClearsItAndTheNextOneOpensAtItsOwnAmount`,
`…testS8313DeselectingNothingChangesNothing`); a list that no longer carries the
selected food clears it the same way
(`…testS8314ANewerListThatDropsTheSelectedFoodClearsTheSelection`).
`onFoodsChanged` is called at the end of `restore()`, on a `foods_down` that was
applied and on no other — a dropped, refused or unreadable one stays quiet —
and after a log that becomes a new starting amount
(`…testS8305FoodChangesAreAnnouncedOnlyWhenTheListChanges`); the model holding
it is the host's one, so the observer survives a body pass
(`WatchNutritionWiringSourceTests.testS8311TheHostOwnsTheOneNutritionModel`,
`…testS8318TheMenuPushesTheHostsNutritionModel`).

Verified by `test/watch_nutrition_quick_log_test.dart` (S-001 to S-006) and by
watchOS `WatchNutritionQuickLogTests` and `WatchNutritionFreshnessTests`.

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

`buildRoutinesDown` always answers a message, even for a phone holding no
routine and no exercise the wrist could log: the answer is then `routines: []`
with `fallbackExercises: []` (`test/watch_reference_sync_test.dart`, group
`S-3840..S-3843, S-3845, S-3846 the phone sends the list in batches`, test
`S-3840 no templates: a message with both lists empty`), so a wrist whose user
deleted the last routine is told the list is empty rather than left with the
old one. An exercise with no capabilities cannot be rendered — `sessionExercise`
requires a non-empty `capabilities` array — so it is left out rather than sent.
`fallbackExercises` is the exercises the routines use, and nothing more
(`S-3841 the fallback list is the exercises the routines use`): the whole
catalog travels as `exercises_down` batches instead (23e2), which is where the
wrist gets the exercises no routine mentions.

Two mappings in that builder are not mechanical, and both are the phone's
decision rather than the wire's:

- **Effort kind.** The app's `BlockTypes` vocabulary is larger than the wire's
  (`interval` is timed work, `amrap` is rounds, a `note` carries no exercise and
  never reaches here). The mapping is the phone's to make because the phone is
  the one that knows what the user built.
- **Targets.** A routine's targets are per metric *and per set*; the wire's
  `targets` is per effort, so the first set travels and the phone's own screen is
  where the rest stay. Durations are stored in seconds and travel in
  milliseconds; RPE and the `extra-weight` metric have no wire key.

`preferences_down` is its own message rather than a field on `routines_down`
because the two answer different questions: the preferences travel on every
`routines` request, while `routines_down` carries the routines and the
exercises they use. Its message id follows
its content as well as its `generatedAt`: the wrist keeps the newest copy and a
tie goes to the later-received one, so two different settings stamped in the
same millisecond must not share a delivery key.

Verified by `test/watch_reference_sync_test.dart` (S-003, S-004, S-007, S-253,
S-3840..S-3846) and `test/watch_nutrition_quick_log_test.dart` (S-003, for the
foods half).

### The watch transport

**Files**: `lib/core/platform/watch_transport.dart`,
`lib/core/platform/watch_connectivity_channel.dart`,
`lib/core/platform/no_watch_transport.dart`,
`lib/core/utils/platform_watch_transport_factory.dart`

One object is both the watch's `WatchSyncTransport` and the phone's
`WatchMirrorTransport`, because they are one radio: `WatchTransport` extends both
and adds `onIncoming`, the single handler every arriving frame is handed to.

**The package boundary is `WatchMessageChannel` and nothing else.**
`omnitrain_watch_link` is imported in exactly one file
(`watch_connectivity_channel.dart`); `WatchConnectivityTransport` is written
against the `WatchMessageChannel` interface, which is what lets a hand-rolled
`MethodChannel` + `WCSession` layer, or a Wear OS data-layer one, replace it
without touching a caller.

**Nothing is queued in the app layer.** A queue here would be a second source of
truth about what has been delivered (PROTOCOL.md, "Idempotency and
reconciliation").

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

Verified by `test/watch_transport_test.dart` (S-001, S-002, S-003, S-006, S-009;
group `S-206 a send answers whether the frame was handed over`,
`S-206 a reachable counterpart means delivered, and the radio carried the frame`,
`S-206 an unreachable counterpart is undelivered, unsent and unreported`,
`S-206 a send reads reachability again rather than trusting the last answer`,
`S-206 a radio that refuses the frame is undelivered and reported once`,
`S-218 a transport that cannot carry a frame is undelivered and quiet`) over an
in-memory two-ended channel.

**Frames are handled one at a time, and a stale snapshot is ignored.**
`WatchConnectivityTransport._dispatch` chains each incoming frame after the
previous frame's handling and counts the frame as heard on arrival; a handler
that does not finish within its handler timeout is reported and given up on, so
later frames are not stuck behind it. On the mirror,
`LiveSessionMirrorState.isStaleSnapshot` answers a `session_snapshot` whose
`sentAt` is earlier than the newest snapshot stamp the mirror has applied — one
stamp across all workouts — with `MirrorOutcome.ignored`: nothing applied,
nothing notified; an equal or later stamp applies, and an unreadable `sentAt` is
not stale, while the inbox still stages the entries of a stale snapshot.
Verified by `test/watch_message_order_test.dart` (`S-9301`..`S-9307`).

The wrist's half of this area — the Swift bridge over the same radio, the wrist's start surface and the wrist's logging surface (the Crown and the per-exercise dialled numbers included) — has its own page: [The Watch Surface — the Wrist's Half](watch_surface_wrist.md).

### The phone's link: the plugin, the channel, the queue and the status

**Files**: `packages/omnitrain_watch_link/` (a local path dependency, iOS
only), `lib/core/platform/watch_connectivity_channel.dart`,
`lib/core/platform/watch_link_info.dart`,
`lib/state/watch/watch_link_state.dart`

The radio under `WatchConnectivityTransport` is the local plugin
`packages/omnitrain_watch_link`, which replaced the `watch_connectivity`
dependency. Its Dart API is `WatchLink`: `status()`; `sendMessage`, which
completes on the watch's reply and fails with a `WatchLinkException` —
`not_supported`, `not_activated`, `not_reachable`, `send_failed`, or `timeout`
when no reply arrives within the call's `timeout`; `transferUserInfo`, which
answers `queued` or `already_queued` by the frame's `messageId`; and one
broadcast `events` stream of the sealed `WatchLinkEvent` kinds
(`WatchLinkMessage`, `WatchLinkUserInfo`, `WatchLinkReachability`,
`WatchLinkStateChanged`). The native half (`OmniTrainWatchLinkPlugin.swift`)
is one `WCSession` delegate that buffers events until Dart listens (bounded by
its `bufferCap`, oldest dropped past it), answers every incoming message so
the sender's send completes, and emits state and reachability; the buffer and
the reply are verified on the paired simulators (plan 47d), not by a unit
test. Verified by `test/watch_link_package_test.dart` (groups `S-6801` to
`S-6805`).

The app's seam is `WatchConnectivityChannel(link:)`, the implementer of the
seven-member `WatchMessageChannel` (`isPaired`, `isReachable`, `messages` —
message and userInfo frames merged into one stream — `send`, `queue`,
`reachability`, `info`); `WatchLinkInfo` is the core value type, so no plugin
type escapes the channel. Verified by
`test/watch_connectivity_channel_test.dart` (group `S-6816 the channel over
the plugin`).

**A frame owed for good can be queued, not only delivered.** `WatchDelivery`
gained `queued` — handed to the OS queue; it arrives when the devices meet —
and `WatchConnectivityTransport.isDurable` is true exactly for `receipt`: a
durable frame the radio cannot reach or refuses is queued instead of
reported, while every other frame stays live-only and is re-offered at its
next trigger. Verified by `test/watch_transport_test.dart` (group `S-6810-6815
the transport over a link that queues`).

**The listener order is load-bearing.** `onIncoming` attaches the message and
the reachability listener together, because listening is what makes the
native side flush its buffer: the message listener must attach first or in
the same turn. Verified by `test/watch_transport_test.dart` (group `S-6817
the transport attaches its listeners when it starts receiving`).

`WatchLinkState` (`lib/state/watch/watch_link_state.dart`) is the status
Settings shows: a `ChangeNotifier` over `WatchLinkSource` — implemented by
the transport — whose `phase` is `connected`, `notReachable`, `notPaired` or
`appNotInstalled`, whose `lastSyncedLabel` says when the phone last heard a
frame, and which persists that instant under the repository key
`watch_last_heard_ms` at most once per `persistEvery`. Verified by
`test/watch_link_state_test.dart` (groups `S-6901` to `S-6905`).

### `WatchSyncRequestHandler`

**File**: `lib/state/watch/watch_sync_request_handler.dart`

Answers the frames that are requests rather than protocol messages: `routines`
is answered with `preferences_down` first and always, then with `routines_down`,
then with the food list as `foods_down` — only when the phone holds foods (the
schema requires at least one, so a phone with none sends no foods frame and the
wrist keeps the list it has) — then with the exercise list as `exercises_down`
batches — unless the request
names the version of the list the phone would send, in which case the batches
are omitted and only the preferences and the routines travel. The foods sit
before that early return, so a wrist that already holds the exercise list still
receives them, and a refused foods frame does not stop the batches (the next
sync re-sends). The handler takes the library as a required `foodLibrary`
(`FoodLibraryState`). All of it is built
through `WatchReferenceSync`; `snapshot` re-asserts the phone's session. It is
separate from `WatchIncomingRouter`
because the two answer different kinds of frame, and merging them would make a
transport detail a protocol one.

**Nothing here answers a request the wrist has not made.** There is no phone-side
schedule and no launch-time push, which is why the preferences ride every
`routines` request: a setting changed on the phone reaches the wrist at the
wrist's next sync. The value is `SettingsState`'s own toggle, never a re-read of
the stored preference, and the accent travels the same way: the handler reads
the theme that state holds (`appTheme`) and sends that theme's primary as
`accentColorHex`, so a theme changed on the phone needs no watch update to be
worn. A phone holding no routine sends a `routines_down` with both lists empty,
and one holding no session answers a `snapshot` request with nothing: the wrist
keeps the copy it has, and an empty answer would be a state it never asked for.

Verified by `test/watch_transport_test.dart` (the `S-003` and `S-253` groups)
and `test/watch_sync_request_handler_test.dart` (S-3850..S-3854; the foods,
group `S-7101…S-7105 the phone sends the food list with the routines`).

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

The held merge also fills intervals (plan 43a): a wrist `timed`, `hold` or
`round` entry lands in the first interval of the effort the phone has not
finished — a running or paused one included — replacing that instance and the
rows paired with it by position, stamped with the wrist's `loggedAt` so the
projection never sends it back, and opening no rest; when every interval is
finished, or in a history import, it appends as before. Verified by
`test/watch_timed_fill_test.dart` (groups `Mock` and `Hive`:
`S-5001 a wrist timed entry fills the unfinished interval`,
`S-5002a a running interval is filled`,
`S-5002b a paused interval is filled`,
`S-5003 every interval finished: the entry appends`,
`S-5007b the filled interval is the wrist's own`). The open session screen
drops the timer UI state of an interval whose persisted instance the merge
finished (`_dropFinishedTimerState` in
`lib/features/session/workout_session_timer_mixin.dart`, called from
`_resyncExercisesFromState`), so the phone's own running timer for a filled
interval stops. Verified by `test/watch_timed_fill_screen_test.dart`
(`S-5008 a watch interval fills the open timed effort and the phone's running
timer stops`, `S-5009 the same for a round effort`).

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
- **A deletion is announced, and it lands before the snapshot that drops the
row.** The push names the dropped entry first — a `delete_entry` frame the wrist
applies — and only then sends the snapshot without it, so it leaves the wrist as
a deliberate removal, never a disagreement to reconcile (D-113, D-115). Each
deletion carries an id of its own (D-110), so a re-used number dropped again is
announced again, not read as a repeat, and an announcement the transport could
not carry is owed: the next push sends it under the id it was minted with
(`test/watch_session_auto_push_test.dart`,
`F2 a number the phone re-used and dropped again is announced again, under a
change id the wrist has not applied` and
`F7 the next pass announces the deletion the failed one could not, under the
change id it was minted with`). Verified by
`test/watch_session_auto_push_test.dart`
(`S-120 the push names the set the phone dropped, in a frame the wrist applies,
before the snapshot that no longer carries it`,
`S-144 a non-set entry the wrist logged leaves under the wrist's own id, and one
the phone logged under the id the phone minted`); the wrist's half — a delete for
an unheld id is refused, a repeat a no-op — by
`WatchSessionEngineTests.testS126AForeignDeleteIsRefusedAndARepeatIsANoOp`.
- **The ledger is memory-only; the lens is the durable half.** The correction and
the id it replaced live only in the running engine, so a relaunch reads the held
rows plus the session's lens, never the corrections: an edit is re-delivered, not
remembered (D-50). The lens goes the other way: a hidden entry cannot be
re-derived from its rows, so every session row written
after a deletion carries it, including one the wrist writes when it stops or
transitions
(`WatchSessionEngineTests.testF1ALocalTransitionAfterADeleteKeepsTheLens`), and
the entry stays hidden across a relaunch (`test/watch_session_engine_test.dart`,
`S-124 the deleted set stays hidden across a restart` and `S-124 the lens rides
on the rows written after it`; `WatchFileStoreTests.testS124TheLensSurvivesAStoreReopen`)
and on the phone as well (`test/watch_session_projection_test.dart`, `S-35 a
re-statement of a deleted id stays deleted`).
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

---

> **Doc freshness** — Last reconciled against source: 2026-10-08. This page is one part of [State Management & Services](../state_management.md); see that index for the full class list. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
