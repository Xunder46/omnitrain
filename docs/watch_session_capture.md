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
and the phone's own question after
it finishes a wrist session (`lib/features/session/live_session_screen.dart`,
`lib/widgets/session/effort_rating_sheet.dart`). The stored models (`WatchInboxEntry`,
`SensorSummary`) belong to [Data Models](data_models.md); the wire format is
`watch/sync_protocol/PROTOCOL.md` ("Session capture"); the live mirror is in
[Services & Utilities](state_management/services_and_utils.md). "The wrist half"
covers what the watchOS package (`watch/watchos/Sources/WatchSessionEngine/`)
sends for the import; its sensors and the summaries computed from them are in
[Services & Utilities](state_management/services_and_utils.md) ("Watch Sensors
and the Platform Workout").

---

## Structure

| Concern | Owner |
|---|---|
| Staging what a wrist sends: effort entries, the effort rating and the session end, from `observations_up` and from a wrist `session_snapshot` | `WatchSessionInbox.receive`, which `WatchIncomingRouter` calls before the mirror and the nutrition bridge |
| Staging the phone's own corrections and deletions of wrist entries | `WatchInboxStagingTransport`, the mirror's transport in `createWatchSync` |
| The phone's own effort rating for a wrist session | `WatchSessionInbox.recordPhoneRating` |
| Asking for it after the phone's own Finish | `LiveSessionScreen`, through `EffortRatingSheet` — the Session Summary's sheet — and `WatchSessionRatings`, the one inbox capability a screen receives; `createWatchSync` returns it in `WatchSyncGraph`, and `MyApp` and `HomeScreen` thread it beside the mirror |
| Turning staged rows into history | `WatchSessionImporter.apply`, a service over `WorkoutRepository` only |
| Keeping the rows the user added to an imported effort | `WatchSessionImporter`, which tells its own rows from the user's by the stamp every imported row carries |
| The measured heart rate and steps, once imported | `SensorSummary` rows, one per target; why they are not `metric-heart-rate` observations is [Data Models](data_models.md)'s |
| The phone's settings the wrist asks by | `WatchSyncRequestHandler`, which answers every wrist sync with `preferences_down` built by `WatchReferenceSync` from `SettingsState` — see [Services & Utilities](state_management/services_and_utils.md) |
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
arriving after it top the imported session up.

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
when, is [Services & Utilities](state_management/services_and_utils.md)'s
("Watch Sensors and the Platform Workout").

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

**Why the phone's answer goes through the inbox.** When the phone finishes a
wrist session, that session is not history yet: it becomes history when the
wrist's `session_end` arrives, at the wrist's next sync. So the answer is
staged as the phone's own rating and wins at import, or is written to the
session directly if the import has already landed. A screen is handed only
`WatchSessionRatings`, so recording a rating is all it can do to the inbox.

**Why the phone asks with the Summary's sheet.** One sheet for every phone
surface that asks means the phone never asks a different question from the
one the wrist asks, which the capture contract pins for both.

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
- **Only the device that ended a live-mirrored session asks how hard it was.**
  The phone's own Finish of a running session with something logged asks when
  the Effort Rating setting is on, and only an answer closes the question; a
  session the wrist completed is shown closed and asks nothing. Verified by
  `test/live_session_effort_rating_test.dart` (`S-281` to `S-284`, `A-62`).
- **Receipts name only applied entries.** Verified by `S-261` (`receipts are
  sent after the rows exist`) and `S-266` (a late entry is acknowledged and
  dropped).
- **Only wrist effort kinds and the two session-scoped kinds are staged, and
  only when they carry the fields their kind requires.** A nutrition quick-log
  stays with the nutrition bridge. Verified by the `what the inbox stages`
  group in `test/watch_session_import_test.dart`.
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
| The prompt and End views | `WatchEffortRatingView` and `WatchEndSessionView`, which bind to `WatchEffortRatingState` and compile only for watchOS; where they appear is the app target's to decide |

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
