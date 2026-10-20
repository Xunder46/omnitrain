# Watch Session Capture

**Scope.** How a session the watch ran becomes phone history: the watch session
inbox, the import, the source it stores for an imported distance, rating
precedence, tombstones, receipts and history
liveness. It describes the phone half —
`lib/state/watch/watch_session_inbox.dart` (`WatchSessionInbox`,
`WatchInboxStagingTransport`), `lib/core/services/watch_session_importer.dart`
(`WatchSessionImporter`), `lib/core/utils/logged_entry_rows.dart`
(`LoggedEntryRows`) — their wiring in
`lib/state/watch/watch_incoming_router.dart` and
`lib/state/watch/watch_sync_wiring.dart`, the Edit Session restore that brings
back an entry which arrived while the screen was open
(`lib/state/workout/session_core_lifecycle.dart`), the screen that captures the
snapshot that restore reads (`lib/features/session/workout_session_screen.dart`),
and the question the phone's Summary asks about an imported session
(`lib/widgets/session/effort_rating_sheet.dart`), and the timer a wrist starts
running on the phone's own intervals
(`lib/state/watch/watch_timer_adoption.dart`). Which session is whose, and
what ending a session on either device does, is
[Watch Session Sync](watch_session_sync.md). The stored models (`WatchInboxEntry`,
`SensorSummary`) belong to [Data Models](data_models.md); the wire format is
`watch/sync_protocol/PROTOCOL.md` ("Session capture"); the live mirror is in
[The Watch Surface](state_management/watch_surface.md). "The wrist half"
covers what the watchOS package (`watch/watchos/Sources/WatchSessionEngine/`)
sends for the import; its sensors and the summaries computed from them are in
[Watch Sensors and the Platform Workout](state_management/watch_sensors.md).

---

## Structure

| Concern | Owner |
|---|---|
| Staging what a wrist sends: effort entries, the effort rating, the session end and the rests it observed (D-210), from `observations_up` and from a wrist `session_snapshot` | `WatchSessionInbox.receive`, which `WatchIncomingRouter` calls before the mirror and the nutrition bridge |
| Staging the phone's own corrections and deletions of wrist entries | `WatchInboxStagingTransport`, the mirror's transport in `createWatchSync` |
| The phone's own effort rating for a wrist session | `WatchSessionInbox.recordPhoneRating` |
| Asking for the rating, after the fact | The Session Summary's `EffortRatingSheet` — its automatic prompt and its EFFORT row both open it — writing through `WorkoutState.updateSessionFeeling` |
| Turning staged rows into history | `WatchSessionImporter.apply`, a service over `WorkoutRepository` only |
| Keeping the rows the user added to an imported effort | `WatchSessionImporter`, which tells its own rows from the user's by the stamp every imported row carries |
| The measured heart rate and steps, once imported | `SensorSummary` rows, one per target; why they are not `metric-heart-rate` observations is [Data Models](data_models.md)'s |
| The phone's settings the wrist asks by | `WatchSyncRequestHandler`, which answers every wrist sync with `preferences_down` built by `WatchReferenceSync` from `SettingsState` — see [The Watch Surface](state_management/watch_surface.md) |
| The rows one logged entry becomes | `LoggedEntryRows`, shared with the phone's own logging in `SessionCore` |
| Acknowledging what was applied | `WatchSessionInbox`, through the one receipt builder, `WatchNutritionLogBridge.receiptFor` |
| Finishing an import the phone had not run when it stopped | `WatchSessionInbox.resume`, called once by `createWatchSync` |
| Recovering a wrist entry that arrived while an Edit Session was open | `WatchLateEntryRecovery`, the inbox capability `SessionCore.restoreSessionSnapshot` calls on Discard; `createWatchSync` returns it in `WatchSyncGraph` and `lib/main.dart` hands it to `WorkoutState` |
| Keeping history surfaces current | `createWatchSync`'s `onHistoryChanged`, which `lib/main.dart` points at `CalendarState.refresh` |

## Rationale

**Why wrist sessions are imported.** Before the import, a wrist session lived
only in the live mirror's memory: it never reached the calendar, the Session
Summary or Stats, and a phone restart lost it. The effort rating and the heart
rate summaries need an ordinary `TrainingSession` to belong to.

**Why everything is staged before anything is applied.** Staging is
put-if-absent by `entryId`, so the first copy of an entry is the record and a
redelivered or altered copy is ignored. The importer reads only staged rows and
the repository — never a message — so history is a function of what was staged,
not of the order it arrived in or how often. Row values come from the wrist's
own data and from the staging stamps of the phone's annotations, never from the
phone's clock at import time, which is what makes two arrival orders reach
identical rows.

**Why an import waits for the session end.** Only the wrist's `session_end`
says whether a session completed or was abandoned, when it started and ended,
and what it measured over the whole of it. Rows staged before it wait; rows
arriving after it top the imported session up. A session the phone already holds
as its own is the exception: the wrist's effort rows merge into the efforts that
session already has as they arrive, with no end to wait for, and its end then
adds only what the phone's session does not have — its rating, and its
heart-rate summary, an abandoned end included. Verified by
`test/watch_session_merge_test.dart` (`S-9`, `D-19`). A timed, hold or round
entry in that merge fills the first interval the phone has not finished — a
running or paused one included — instead of appending beside it, and appends
only once every interval is finished (`test/watch_timed_fill_test.dart`,
groups `Mock` and `Hive`: `S-5001 a wrist timed entry fills the unfinished
interval`, `S-5002a a running interval is filled`,
`S-5003 every interval finished: the entry appends`).

**Why the rating and the end are observations of their own.** The wrist
re-sends only observations the phone has not acknowledged; it never re-sends a
lifecycle message, and it snapshots only the session that is current. A rating
or an end carried by either would be lost for a session that ended out of the
phone's reach. As observations they are stored on the wrist and re-sent until a
receipt names them, and their ids derive from the session (PROTOCOL.md,
"Session capture"), so a repeat is a store no-op and a session has one of each.

**Where the measurements travel.** Each timed, round and hold entry carries its
own heart rate, and a timed entry its steps; the session's heart rate and each
set block's travel in the `session_end`. Why they are computed on the wrist, and
when, is in [Watch Sensors and the Platform
Workout](state_management/watch_sensors.md).

**Why the rows a user added to an imported effort are never touched.** An
imported session is ordinary history, so the user can add a set to an imported
exercise — and a wrist entry for that exercise can still arrive afterwards: a
late delivery, or a session the phone reopened. The import places entries in
logged order, and the phone places a new entry after the effort's last one, so
both would claim the same position and the later write would replace the
earlier. Every row the import writes carries its entry's logged time as its
creation stamp, which the phone's own edits keep, so the import can tell its
rows from the user's. Once the user has added to an effort, it is theirs to
arrange: nothing in it moves, a late wrist entry goes after its last row, and a
later phone change to a wrist entry reaches only that entry's own rows. An
effort nobody else has added to keeps the logged order, which is what makes the
import independent of arrival order.

**Why applied rows are kept.** An applied staged row is never materialised
again, so it is also the record that history the user deleted — a session, an
effort or one entry — was once there. That is what stops a later sync from
re-creating it. Nothing deletes a staged row. The one exception is an Edit
Session Discard: an entry that arrived while the screen was open is not in the
snapshot the Discard restores, so the restore un-marks exactly that entry and
runs one ordinary import pass to bring it back; the pass re-stamps it applied.

**Why receipts wait for application.** A receipt tells the wrist it may drop an
observation. Sent on arrival, it would let the wrist prune an entry the phone
had not yet made history of; sent at application, a phone that stops in
between still has the staged row and imports it at its next start. An entry the
wrist re-sends after it was applied is acknowledged again, because a re-send
means the earlier receipt never arrived.

**Why the rows come from `LoggedEntryRows`.** An imported set, timed entry,
hold or round must be indistinguishable in shape from one the phone logged —
metric ids, units, the `obs-<effortId>-<entryIndex>-<metricKey>` id pattern and
the companion rows — because every history, summary and Stats reader assumes
the phone's shape. One builder for both writers makes that structural rather
than a copy that could drift.

**Why the repository gained `updateEffort`.** A late entry can precede an
imported one, which changes which effort came first. Re-ranking in place keeps
the effort's rows and any edit the user made to them; deleting and re-creating
it would cascade away both.

**Why corrections are staged by a transport decorator.** The mirror's job is
the live session. Wrapping its transport lets the inbox see exactly what the
wrist is sent, and stage it before the message leaves, without the mirror
knowing history exists.

**Why a phone rating goes through the inbox.** When the phone rates a wrist
session that is not history yet, the rating is staged as the phone's own and wins
at import; once the import has landed it is written to the session directly. One
answer either way, which the import's own tests pin
(`test/watch_session_import_test.dart`,
`the phone’s own rating (D-138, D-139 state half)`).

**Why the phone asks with the Summary's sheet.** One sheet for every phone
surface that asks means the phone never asks a different question from the one
the wrist asks, which the capture contract pins for both.

## Invariants

- **Everything is staged before any other consumer answers.** Verified by
  `test/watch_session_import_test.dart` (`S-261 … every event is staged …`,
  `S-267 … each change is staged before it is sent`, and — at the moment the
  mirror re-asserts its own shape over a session it already holds — `F-5 the
  inbox stages before the mirror can answer …`).
- **The import is idempotent and independent of arrival order.** Verified by
  `test/watch_session_import_test.dart` (`S-262`, `S-263`).
- **Only a completed session with at least one effort entry left after the
  phone's deletions becomes history;** abandoned and empty sessions are consumed
  and acknowledged. Verified by `S-265` and `S-273`.
- **Deleted history stays deleted.** Verified by `S-266`.
- **The phone's rating is final.** At import the phone's own staged rating wins
  over the wrist's; after import a wrist rating applies only while the session
  has none; the phone's own rating after import is written directly. Verified
  by `S-264`, `S-281` and `S-284`.
- **Live corrections and deletions carry into history, and a correction staged
  after the import edits only the metrics it names.** Verified by `S-267`.
- **Imported rows have the shape of the phone's own.** Verified by `S-274`.
- **The import stores the source a timed entry's distance arrived with, or
  `entered` when it arrived with none; a timed entry with no distance gets no
  source.** Verified by `test/distance_source_import_test.dart` (S-876, S-877).
- **A later sync leaves a distance the phone wrote as it is: its value and its
  source.** Verified by `test/distance_source_import_test.dart` (S-878).
- **A wrist entry never lands on, moves, edits or deletes a row the user added
  to an imported effort,** and a pass that stopped half-way finishes the entry it
  had started rather than adding it twice. Verified by
  `test/watch_session_import_test.dart` (the `A-51` group).
- **A summary is what the wrist measured, on its target, and absence is never
  zero.** Verified by `S-261` (`no-sensors`) and `S-269`; the model-level rules
  by `test/watch_capture_repository_parity_test.dart`.
- **An imported session is never written to platform health.** It is created
  already ended, and `endSession` does nothing for an ended session. Verified
  by `S-270`.
- **A change to history refreshes the calendar once; a redelivery refreshes
  nothing.** Verified by `S-271`, and by the `S-284` refresh assertions — the
  phone's own rating of an imported session is such a change, at the state
  layer and through the screen.
- **Hive and Mock hold the same rows after an import.** Verified by
  `test/watch_capture_contract_test.dart` (`S-272`), which imports every case of
  `watch/contract/watch_capture_contract.json` on both and compares them row for
  row.
- **Only the device that ended a session asks how hard it was.** The phone's own
  Finish of a session with something logged asks when the Effort Rating setting
  is on, and only an answer closes the question; a session the wrist completed is
  shown closed and asks nothing, and the wrist's answer is the finished session's
  one rating. Verified by `S-4` and `S-5` in `test/watch_session_finish_test.dart`,
  and — for the phone's own rating — by the `the phone's own rating (D-138, D-139
  state half)` group in `test/watch_session_import_test.dart` (`S-281`, `S-284`).
- **Receipts name only applied entries.** Verified by `S-261` (`receipts are
  sent after the rows exist`) and `S-266` (a late entry is acknowledged and
  dropped).
- **Only wrist effort kinds, the two session-scoped kinds and the rests the wrist
  observed are staged, and only when they carry the fields their kind requires.**
  A nutrition quick-log stays with the nutrition bridge. Verified by the `what the
  inbox stages` group in `test/watch_session_import_test.dart`, and — for a rest —
  by the `the wrist’s rests (D-210)` group there (`S-320`, `S-323`).
- **A wrist entry that arrived while an Edit Session was open survives
  Discard.** The restore un-marks exactly the entries applied after the
  snapshot's watermark and runs one import pass, so the entry returns as the
  wrist sent it while the user's own edits are still discarded; the un-mark is
  durable, so a pass that does not complete leaves the row to the next pass for
  that session — the wrist re-sending it, or the start-up pass for a session
  whose end has not been applied. A snapshot taken with no watermark recovers
  nothing, and a session with no late entry is left untouched. Verified by
  `test/watch_session_edit_restore_late_entry_test.dart` (`S-1401` to `S-1410`,
  `S-1413`, `S-1414`) and the screen's own watermark capture (`S-1415`).

## The wrist half

Only the watchOS package sends what the import consumes; `lib/watch/` sends no
session end, summary or effort rating.

| Concern | Owner |
|---|---|
| The `session_end` of a session the wrist created, whichever path ends it | `WatchSessionEngine`, before the row that records the new status |
| An entry's heart rate, a timed entry's steps and a round's `pausedMs`, at log time | `WatchLoggingState.log`, over `WatchSensorSummaries` |
| The session's and each set block's heart rate | `WatchSessionEngine`, into the `session_end` |
| Re-sending what the phone has not acknowledged | `WatchSessionEngine.pendingObservations`, every session's, in store order |
| The session's ids for its two session-scoped observations | `WatchSessionCapture` |
| The phone's preferences, as the newest `preferences_down` brought them | `WatchPhonePreferences`, fed by `WatchSyncOrchestrator` |
| The End action, whether it owes an effort rating, and the prompt that asks for it | `WatchEffortRatingState` |
| The session's one effort rating | `WatchSessionEngine.recordEffortRating` |
| The prompt view | `WatchEffortRatingView`, which binds to `WatchEffortRatingState` and compiles only for watchOS; where it appears is the app target's to decide |

**Why the wrist sends the end, whoever ended the session.** The import waits for
a `session_end`, and only the wrist holds the readings its summaries come from.
So the wrist appends one for each session it created — at its own End or
abandon, or when the phone's lifecycle message or snapshot ends it — and none for
a session it joined from the phone, which the phone already holds.

**Why the end is stored before the row that ends the session.** A kill between
the two then leaves a session still running with its end already owed, rather
than an ended session with no end — one the phone would never import.

**Why every session's owed observations are re-sent.** A session that ended
while the phone was out of reach is still owed after the next one starts; sending
only the current session's would strand it until the next time it was current,
which is never.

**Why the wrist asks only when its own End ended the session.** On a
live-mirrored session a completion can reach the wrist from the phone; asking
then would be asking about a decision the wrist did not make. Whatever the wrist
sends, a rating the phone holds for the session wins (see "The phone's rating is
final" above).

**Why the wrist's question can close by itself.** The phone may answer first —
the Summary's automatic prompt or its EFFORT row — and when it does, the push
tells the wrist with one `session_snapshot`: the mirror's converged state plus
one `effort_rating` entry under the wrist's own id, `rating-<sessionId>`
(`LiveSessionMirrorState.sendRatingFor`, called from
`WatchSessionAutoPush._pushRating` right after the end is announced, before the
push's ended-session early return). No wire or schema change: the envelope
passes the Dart validator, and the wrist stores the entry under that id — the
record `WatchSessionEngine.hasEffortRating` looks up — so the owed prompt drops
out, `confirm()` records nothing and `recordEffortRating` refuses; the engine
publishes the change and the rating state forwards it on the main queue, so an
open prompt redraws. The phone sends only for an ended session that has a rating
and that the mirror holds, remembers the session id once the send is delivered,
and never when the mirror already holds the wrist's own answer. Limits, stated
not fixed: both devices answering inside the radio latency window leaves the
phone's number standing on the phone (D-138) while the wrist keeps the answer it
recorded; a wrist out of reach keeps its question open until the next phone
notification after it becomes reachable; and a session the phone ended itself,
whose wrist copy is still held, is sent the entry too — the guards ask only that
the phone's row is ended and rated — though the wrist asks nothing for a
completion that came from the phone and does not upload the entry back. Verified
by `test/rating_first_answer_push_test.dart` (the `S-4306`,
`S-4307 the first answer stands and nothing is echoed`, `S-4308` and `S-4309`
groups) and watchOS `WatchEffortRatingTests`
(`testS4310ThePhonesRatingInASnapshotClosesTheOwedQuestion`,
`testS4311ThePhonesRatingIsNotUploadedBackAsAnEffortRating`,
`testS218TheWristNeverChangesARating`,
`testS216ThePhonesLifecycleEndingItOwesNoPrompt`).

**Why the phone's running timer is told to the wrist.** A live session runs both
ways: while the phone holds the session, `WatchTimerPush`
(`lib/state/watch/watch_timer_push.dart`, built in `createWatchSync` as
`WatchSyncGraph.timerPush` and bound in `lib/main.dart` beside the auto push)
listens to the bound `WorkoutState`, debounces, and sends one `timer_state`
frame per pass through `LiveSessionMirrorState.sendTimers` — the in-progress
work interval per wire kind (`elapsed` for a timed effort, `hold` for a drill,
`round`), running or paused, with its start, pause bookkeeping and a round's
planned length, and `sessionExerciseId` naming the effort it belongs to. A kind
the wrist already holds for the same slot, not stopped, with identical fields or
an earlier start is not sent — the wrist's own timer wins — and a skipped kind
is not recorded as delivered, so a later pause on the phone still travels. A
kind no longer in progress is sent as `null` once — a timer the wrist started
and the phone adopted included, while the mirror still holds it (plan 43c) —
and a new interval replacing a delivered one goes out as two frames, the clear
first. Limits, stated not
fixed: the wrist applies a phone timer only for the exercise it is showing and
has no pause control, finishing on the watch stops the phone's timer through
the logged-entry fill, which lands on the interval that started with the entry
(plan 43a, 43c's shared start), a wrist out of reach is served at the
next phone notification, a failed session reload on the phone empties its
timers and sends a clear until the next successful load, and an interval
started with a preset target carries a back-dated start. Verified by
`test/in_progress_work_timers_test.dart` (group
`WorkoutState.inProgressWorkTimers (Mock)`) and
`test/watch_timer_push_test.dart` (the `S-6211` to `S-6217` groups).

**Why a timer the wrist started runs on the phone.** The same `timer_state`
frames are the phone's to receive: `WatchTimerAdoption`
(`lib/state/watch/watch_timer_adoption.dart`, built in `createWatchSync` as
`WatchSyncGraph.timerAdoption` and bound in `lib/main.dart` after `timerPush`)
listens to the live mirror and to the bound `WorkoutState`, and for each work
kind the mirror holds with a non-empty `sessionExerciseId`, not stopped, for
the session the phone is running, hands a `RemoteWorkTimer`
(`lib/state/workout/timer_manager.dart`) to `WorkoutState.adoptRemoteWorkTimer`
(`SessionCore.adoptRemoteWorkTimer` in `session_core_io.dart`, over
`TimerManager.adoptRemoteTimer`). The target is the effort's in-progress
interval if it has one, else its first not-finished interval, in the order
plan 43a's fill uses; a not-started target becomes active — or paused, when the
frame carries a pause stamp — with the wrist's start, pause stamp and
accumulated pause, a round takes the wrist's planned length when the frame
carries one, and the effort's open rests are closed and persisted as a phone
start does. An in-progress target is replaced only when the wrist's start is
earlier; an equal or later start changes nothing. A stopped timer, one for a
slot the phone does not hold, or the wrong kind for the effort is ignored, and
a wrist stop is not applied — the wrist's logged entry fills and finishes the
interval (plan 43a). The write bumps `watchRefreshRevision` once so the open
session screen resyncs: `_adoptRunningTimerState`
(`lib/features/session/workout_session_timer_mixin.dart`, called from
`_resyncExercisesFromState` in `workout_session_screen.dart`) gives an interval
that became active from outside its running flag, its place in the
one-timer-in-progress lock, the per-second ticker, the expiry notification and
the refreshed cached target length. Repeated identical frames are skipped, the
memo resetting when the session changes; there is no echo while the interval
runs — after adoption the phone's instance equals the mirror's timer, so
`WatchTimerPush` sends nothing back until the phone finishes the interval and
the clear in the next paragraph goes out — while a later pause on the phone
still travels. Limits, stated not
fixed: when the session screen is opened after the watch started a round, the
ring shows the running digits but does not sweep and no expiry fires, because
the load path restores an active round as not running — pinned by
`test/round_countdown_screen_test.dart` (`S-4408: at 390x844 with the rest
strip up everything is hittable`, which expects the rest chip on a restored
running round) — while the same screen already open follows the watch; the
wrist has no pause control, so pause travels phone to wrist only; a timer for
another exercise runs on that exercise's interval and shows when the user moves
to it (the phone does not navigate); the wire holds one timer per kind, so
a newer timer of a kind for another exercise supersedes the older one; a timer
the phone refuses because its own interval started later is not retried until
the watch's timer changes. A write from the watch in the middle of an interval
the phone started itself leaves that interval's dialled auto-expiry running (the
screen keeps the target dialled before the start in memory, since the started
instance persists a zero target; `S-6126 a watch-driven resync does not kill the
phone's own dialled expiry` in `test/widget_test.dart`). Verified
by `test/remote_work_timer_state_test.dart` (groups `Mock` and `Hive`,
`S-6101`–`S-6106`), `test/watch_timer_adoption_test.dart` (`S-6111`–`S-6115`)
and `test/watch_timer_adoption_screen_test.dart` (`S-6121 a wrist elapsed timer
starts the open timed interval`, `S-6122 a wrist round timer runs the open
round countdown`, `S-6122 a round the phone had already started with another
length takes the earlier wrist start and its length`, `S-6123 the adopted
interval blocks starting another one`, `S-6124 a wrist timer for another effort
leaves the open one alone`, `S-6125 a wrist elapsed timer that arrives before
the mount still runs`).

**Why finishing on either device logs once.** The live merge aims the wrist's
entry at the interval whose clock started with it: among the effort's
not-finished intervals, the in-progress one whose start is within 1000 ms of
the entry's — the tolerance of a start that crosses the wire as an ISO string,
which a Swift Date round trip can move by a millisecond — else the first
in-progress one, else the first not-finished one (plan 43a's rule), else the
entry appends. Verified by `test/watch_finish_once_test.dart` (groups `Mock`
and `Hive`: `S-6301 the entry fills the interval whose start is its own`,
`S-6304`, `S-6305a`/`S-6305b`,
`S-6306a`/`S-6306b`, `S-6307a`/`S-6307b`). An entry for an interval the
phone already logged — a FINISHED interval of its kind whose start is within
the same 1000 ms and which is not the entry's own instance (an unfinished
instance of the entry's own is finished in place, not mistaken for a
duplicate); the watch out of reach, or the clear not yet arrived — writes nothing: the phone's numbers stand, and a following rest
still lands on the phone's interval (`S-6311 a second report of an interval
the phone logged is ignored` through `S-6316 a rest after a duplicate lands
on the phone's interval`). The mirror image: the phone finishing an interval
the wrist's clock started. `WatchTimerPush` remembered the adopted timer;
when that slot-and-start interval ends it sends one
`{kind: null}` frame while the mirror still holds that exact timer, before any
new timer of the kind; the wrist stops the clock and offers Start. Verified by
`test/watch_timer_push_test.dart` (the `S-6321` to `S-6330` groups and
`S-6341 one interval, no duplicate: the wrist entry lands on the interval the
phone already finished`) and watchOS `WatchTimedWorkTests`
(`testS6331APhoneClearOfTheElapsedTimerMakesTheWristOfferStart` and its
S-6331 siblings). A remote `stopped` timer stays ignored on the phone: the
watch stops a work clock only by Log (the entry arrives and the fill finishes
the interval) or by the phone's own clear, which the watch does not echo — a
stop frame ahead of its entry would end an interval with nothing logged.
Limits, stated not fixed: both devices logging inside the radio latency — the
first entry to reach the phone's data wins, and phone-first the watch's own
list keeps both entries (none retracts one; delete it on the watch),
watch-first the phone's later Log finds the interval finished and does
nothing; a clear names a kind, not a slot, so one arriving after the watch
began its next interval of that kind stops that clock too (the phone sends
one only while its mirror still shows the exact timer); and a watch clock
stopped without a log would leave the phone's running (no such path today).

**Why the wrist decides at End, and stores the decision.** Whether a prompt is
owed depends on the phone's deletions, which only the running process knows, and
a kill before the answer must still ask at the next launch. So End decides once
and stores an owed prompt; the session's rating is what answers it.

**Why the setting is the phone's, and learnt at sync.** The effort-rating setting
lives on the phone (`SettingsState`), and every wrist sync is answered with the
phone's preferences, so the wrist asks as the phone was last set. A wrist that has
never synced does not know the setting, and does not ask.

Invariants:

- **One `session_end` per session the wrist created, appended before the row that
  ends it; none for a session it joined; a reopened session keeps its first.**
  Verified by watchOS `WatchSessionEngineTests` (the `D-120` cases).
- **Every unacknowledged observation of every session is re-sent, in the order
  it was stored.** Verified by watchOS
  `WatchSessionEngineTests.testS240EveryUnacknowledgedObservationOfEverySessionIsResentInStoreOrder`.
- **The wrist emits exactly the events `watch/contract/watch_capture_contract.json`
  expects.** Verified by watchOS `WatchCaptureContractTests`, which replays each
  case's timeline through the wrist and compares every event field for field.
- **A prompt is owed only when the wrist's own End completed a session that has
  at least one effort entry left after the phone's deletions and no rating, and
  the phone's setting as last synced asks for it.** A completion that reaches the
  wrist from the phone never owes one, and a wrist that has never synced does
  not ask. Verified by watchOS `WatchEffortRatingTests` (`S-211` to `S-217`,
  `S-220`).
- **An owed prompt survives a kill.** It is stored at End and answered only by
  the session's rating. Verified by `WatchEffortRatingTests` (`S-215`).
- **One effort rating per session, and the wrist never changes it.** Verified
  by `WatchEffortRatingTests` (`S-218`).
- **The newest preferences apply.** A late older copy never replaces them, and a
  copy stamped the same moment goes to the later-received. Verified by
  `WatchEffortRatingTests` (`S-214`) and
  `WatchSessionStartPathsTests.testTheNewestPreferencesApplyAndALaterCopyWinsATie`.
- **The prompt's only way out is an answer.** Verified by
  `WatchEffortRatingTests.testTheRatingOffersNoWayOutButAnAnswer`, which fails on
  any declaration or button in the rating's state or views named for another way
  out.
- **Both devices ask the same question.** The wrist's copy and scale are held to
  `watch/contract/watch_effort_rating_contract.json` by `WatchEffortRatingTests`
  (`S-211`), and the phone's sheet by
  `test/watch_effort_rating_copy_parity_test.dart` (`S-287`).

## Vocabulary

- **Watch session inbox** — the repository-backed staging area for everything
  the phone knows about a wrist session before it is history
  (`WatchInboxEntry`).
- **Staged row / applied row** — a row is staged when it is first stored, and
  applied once the importer has materialised it, used it (a rating, a
  correction, a deletion) or deliberately discarded it.
- **Tombstone** — an applied row: the record that stops a later sync from
  re-creating history.
- **Phone annotation** — a staged row the phone originates: its own effort
  rating, or a correction or deletion it sent for a wrist entry.
- **Top-up** — applying rows that arrive after a session was imported.
- **Session end** — the `session_end` observation: how and when a session the
  wrist created ended, with the whole session's heart rate and its set blocks'.
  It is the event the phone imports a wrist session by.
- **Effort rating** — the session's answer to "how hard was this session", on
  the scale `watch/contract/watch_effort_rating_contract.json` defines; the
  wrist sends it as the `effort_rating` observation.
- **Owed prompt** — the wrist's stored note that its End owes a session an
  effort rating (`WatchRatingPromptRecord`); the rating answers it.
- **Set block** — every set of one session logged for one `sessionExerciseId`
  and `exerciseId` pair. Its span runs from the effort logged just before its
  first set (or the session's start) to its last set, so interleaved blocks may
  overlap.
- **Session-scoped kind** — `effort_rating` and `session_end`, which describe a
  whole session rather than work logged in it.

---

> **Doc freshness** — Last reconciled against source: 2026-09-27. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree. If you find a claim here that disagrees with `lib/`, `lib/` wins.
