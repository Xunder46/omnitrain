# Watch ↔ Phone Sync Protocol — v1

Two watch clients on two stacks (native watchOS, Flutter Wear OS) speak to one
phone. This document is the language they share. It is platform-neutral,
transport-neutral, and enforced by fixtures rather than by convention: every
statement here that a client could get wrong has a machine-readable fixture
next to it, and the fixtures are the contract.

**Protocol version: 1.** Every message carries it. See
[Versioning policy](#versioning-policy-normative).

What this document is not: it defines no transport (WatchConnectivity, Wear OS
Data Layer, and anything that replaces them are out of scope), no UI, and no
cloud sync. It defines payloads, authority, and convergence.

## Layout

| Path | Contents |
|------|----------|
| `schemas/envelope.schema.json` | Envelope fields plus the payload fragments shared by more than one message type |
| `schemas/messages/` | One JSON Schema per message type |
| `fixtures/manifest.json` | Register of every fixture in this tree: valid, invalid, and scenario |
| `fixtures/valid/` | Conforming messages, at least one per type |
| `fixtures/invalid/` | One or more non-conforming messages per type, each with the reason it must be rejected |
| `fixtures/reconciliation/` | Scenario fixtures: replayable snapshots with event streams, covering reconciliation, duplicate delivery, structure-change application, snapshot merge, timer clearing, slot identity, lifecycle ordering, and version mismatch. `fixtures/manifest.json` is the complete register |

Schema dialect: the subset of JSON Schema 2020-12 the protocol actually uses —
`type`, `const`, `enum`, `required`, `properties`, `additionalProperties`,
`items`, `minItems`, `minLength`, `minimum`, `maximum`, `pattern`, `allOf`,
`oneOf`, and `$ref`. A `$ref` target is either `#/…` inside the current
document or `<document>.schema.json#/…` relative to `schemas/`.

`integer` means an integer on the wire, not a number without a fraction: a
whole-number double such as `3200.0` is refused wherever `integer` is declared,
because the two validators must agree on the bytes rather than on the value —
`fixtures/invalid/observations_up_steps_as_double.json` is the register's
witness, and its `expectedReasonContains` is the wording contract.

The Dart validator that consumes these files lives at
`lib/core/sync_protocol/message_validator.dart` and is pure Dart: the caller
supplies the decoded schema documents, which is what keeps file access out of
the app bundle. The reference implementation of the apply rules below lives at
`lib/core/sync_protocol/session_reconciler.dart`; `test/sync_protocol_fixtures_test.dart`
runs every fixture through both.

## Envelope

Every message is an object with these fields, and nothing else
(`additionalProperties: false` — see [Validation profiles](#validation-profiles)):

| Field | Type | Notes |
|-------|------|-------|
| `protocolVersion` | integer ≥ 1 | Required |
| `messageId` | non-empty string | Required. Identifies the message, not the data in it |
| `sessionId` | non-empty string | Required for every session-scoped message |
| `type` | one of the message types below | Required |
| `origin` | `"watch"` or `"phone"` | Required |
| `sentAt` | UTC timestamp | Required |
| `payload` | object | Required. Shape depends on `type` |

A timestamp is an ISO-8601 UTC instant, `YYYY-MM-DDTHH:MM:SS(.sss)Z`. Local
counters are never part of a message.

## Message families

| Type | Direction | Purpose | Schema | Fixture |
|------|-----------|---------|--------|---------|
| `routines_down` | phone → watch | The user's routines (routine → segments → efforts → per-metric targets) plus the fallback exercise list | `schemas/messages/routines_down.schema.json` | `fixtures/valid/routines_down.json` |
| `foods_down` | phone → watch | The user's Foods I Eat list — the foods the wrist may quick-log — plus the categories that order it | `schemas/messages/foods_down.schema.json` | `fixtures/valid/foods_down.json` |
| `preferences_down` | phone → watch | The phone's settings the wrist honours: today, whether a session ended on the wrist asks for the session effort rating | `schemas/messages/preferences_down.schema.json` | `fixtures/valid/preferences_down.json` |
| `exercise_push` | phone → watch | A catalog exercise the user searched for on the phone, pushed into the live session | `schemas/messages/exercise_push.schema.json` | `fixtures/valid/exercise_push.json` |
| `structure_change` | phone → watch | Add, remove, reorder, swap, correct a logged entry, delete a logged entry | `schemas/messages/structure_change.schema.json` | `fixtures/valid/structure_change.json` |
| `observations_up` | watch → phone | Append-only observations: sets, timed entries, rounds, holds, nutrition quick-logs, the session effort rating, and the session end | `schemas/messages/observations_up.schema.json` | `fixtures/valid/observations_up.json` |
| `receipt` | phone → watch | The observations the phone has taken responsibility for — what lets the watch drop an observation it sent | `schemas/messages/receipt.schema.json` | `fixtures/valid/receipt.json` |
| `session_lifecycle` | either | Session started, exercise advanced, completed, abandoned | `schemas/messages/session_lifecycle.schema.json` | `fixtures/valid/session_lifecycle.json` |
| `session_snapshot` | either | The full live-session state, exchanged on connect, on reconnect, and after a rejection | `schemas/messages/session_snapshot.schema.json` | `fixtures/valid/session_snapshot.json` |
| `timer_state` | either | Rest, round, hold, and elapsed timers as wall-clock timestamps plus pause bookkeeping | `schemas/messages/timer_state.schema.json` | `fixtures/valid/timer_state.json` |

Notes that follow from the schemas:

- The fallback exercise list MUST cover every exercise any synced routine
  references — the watch must never hold a routine it cannot log. The validator
  reports a `semantic_violation` when coverage is missing.
- `fallbackExercises` is catalog reference data: it names exercises, not session
  slots, so its entries carry no `sessionExerciseId`.
- `foods_down` is reference data too, and the wrist owns none of it: a food the
  user creates, edits or deletes on the phone reaches the watch only in the next
  `foods_down`, and the watch that quick-logs a food never edits the catalog. A
  food's `categoryId` is the phone's own grouping, already resolved to the
  categories the message carries; `null` means the phone groups it under
  Uncategorized.
- `preferences_down` carries the phone's settings the wrist honours. It is
  reference data about the user, not a session, so it names no session. The
  phone MUST answer every wrist sync request with one — even when it holds no
  routines, and before any `routines_down` — so a setting changed on the phone
  reaches the wrist at the wrist's next sync. The wrist keeps the newest: the
  copy with the latest `generatedAt` applies, a tie goes to the copy received
  later, and an older copy that arrives late MUST NOT replace a newer one. A
  wrist that has never received one does not ask for an effort rating
  (`watch/contract/watch_effort_rating_contract.json`).
- `exercise_push` is itself the structural edit: it carries `insertAtIndex`
  and the slot it creates. The phone MUST NOT follow it with an `add_exercise`
  change for the same slot.
- Every observation event is self-contained. An effort event carries the slot
  it was logged in, the catalog exercise, the kind, the wall-clock timestamps,
  and the metrics the entry needs. A *session-scoped* event — `effort_rating` or
  `session_end` — describes the whole session, so it names no slot and no
  exercise (see [Session capture](#session-capture-normative)). The phone never
  has to ask the watch a follow-up question to materialise an entry.
- An observation event carries both `eventId` and `entryId`. `eventId` is the
  delivery key, `entryId` is the entry's identity; the two are equal in
  practice, and either one alone is enough to reject a duplicate.
- A `receipt` names the `entryId`s the phone holds. It is deliberately
  session-free: a nutrition quick-log taken with no workout running names a
  session the phone does not hold, so `session_snapshot` never carries it back,
  and without a receipt the watch would re-send it on every connect and could
  never prune the row. A receipt asserts that the phone has the observation, not
  that anything changed — a food the phone's library no longer carries is
  acknowledged too. A snapshot also confirms the `entryId`s it carries, so a
  receipt is what acknowledges an entry no snapshot carries, and the two are the
  whole of it: an entry neither message names stays owed.
  This was the first message type added after v1 was published, and it is
  additive in the sense that matters here: the two clients ship from this
  repository in one release, so a receiver that predates the type cannot be in
  the field. The session-capture amendment (see
  [Version history](#version-history)) is additive on the same grounds.
- A `session_snapshot` payload carries its own `sessionId`, which MUST match the
  envelope's.
- An observation event carries the metrics its entry needs: `reps` and `loadKg`
  for a set, `startedAt` and `endedAt` for timed work, rounds and holds,
  `distanceMeters` for distance-capable work, and `extraLoadKg` for a hold's
  added or assisting load. Distance is entered by hand whenever the watch has no
  fix: GPS is a separate concern and MUST NOT gate an entry.
  `fixtures/valid/observations_up_distance_and_load.json` is the shape in full.
- A set's `loadKg` MAY be negative down to -200 kg: a band or partner assists
  the lift, so the logged resistance is below bodyweight. The same floor applies
  to a routine target and to a correction, and a value below -200 kg MUST be
  rejected as invalid, never clamped into range. The floor is the bound the
  phone's set editor already enforces.
  `fixtures/valid/observations_up_band_assist.json` is that shape.

## Authority rules (normative)

1. The watch MUST NOT edit or delete existing records. It appends new
   observations and MAY reflect corrections the phone sends, but it never
   originates a mutation of anything already recorded. The phone holds the
   session's records too, and MAY add entries it logged, which arrive in its
   `session_snapshot`.
2. The phone MUST be authoritative for session structure: adding, removing,
   reordering, and swapping exercises. Only the phone sends `structure_change`.
3. When a structure change removes the exercise the watch is currently on, the
   watch MUST advance to the next valid exercise: the position stays at the
   same index, which now holds the exercise that followed, or moves to the last
   exercise when the removed one was last. `fixtures/reconciliation/remove_current_exercise.json`
   pins this.
4. The phone MUST accept watch-appended observations. There is no negotiation,
   no approval step, and no "watch data pending" state — an observation the
   watch sent is part of the session. An `effort_rating` is accepted the same
   way, with one limit: a rating the phone already holds for the session is the
   user's own answer on the phone, and a wrist rating MUST NOT replace it,
   however it arrives.
5. Removing an exercise MUST NOT remove the entries already logged against it,
   and swapping an exercise MUST NOT rewrite the exerciseId on existing
   entries. History records what happened.
6. A structure change is identified by `changeId`. A receiver MUST apply a given
   `changeId` at most once, so re-delivery cannot duplicate an edit.

## Exercise identity (normative)

A live session is an ordered list of exercise *slots*. A slot carries two
identifiers, and they answer different questions:

| Field | Identifies | Lifetime |
|-------|-----------|----------|
| `sessionExerciseId` | The slot — where in the session this exercise sits | The life of the session. Stable across reorder, preserved across swap |
| `exerciseId` | Which catalog exercise the slot holds | Changes when the slot is swapped |

- Every `sessionExerciseId` MUST be unique within a session. The same
  `exerciseId` MAY appear in more than one slot — a routine that benches in two
  segments produces exactly that — so `exerciseId` MUST NOT be used to address a
  slot. The validator reports a `semantic_violation` when slot ids repeat.
- Structure operations (`remove_exercise`, `reorder_exercises`,
  `swap_exercise`) MUST address the session by `sessionExerciseId`. Only
  `add_exercise` and `exercise_push` introduce a slot, and the phone MUST choose
  its id.
- An operation that introduces a slot — `exercise_push` or `add_exercise` —
  whose `sessionExerciseId` is already present MUST be ignored. That is what
  makes a re-delivered push harmless; replacing what a slot holds is
  `swap_exercise`'s job, and MUST NOT be attempted by re-adding the slot.
- `swap_exercise` MUST preserve the slot's `sessionExerciseId`. It replaces what
  the slot holds and nothing else, so the watch's position does not move and an
  entry logged against the slot still points at it.
- A logged entry MUST record both the slot it was logged in
  (`sessionExerciseId`) and the catalog exercise it recorded (`exerciseId`).
  Neither is rewritten by a later structure change: history records what
  happened, not what the slot holds now.
- Removing a slot MUST NOT touch the entries logged against it.
- A slot MAY carry the `effortKind` its routine declared, and a slot that does
  MUST be rendered with it. This is the one field a receiver does not derive:
  the routine is the user's own plan, and re-deriving the kind from the
  exercise's capabilities would render the effort as something the plan never
  asked for (a Plank carries `time` and `hold`, which the capability rule reads
  as a hold, while the routine that declares it `timed` is what the user set
  up). A slot with no `effortKind` — a free workout, or an exercise pushed into
  a live session — is resolved from its capabilities, which is the rule
  `watch/contract/watch_start_paths_contract.json` (`effortKindParity`) pins for
  both clients.

## Timer state (normative)

Timers MUST be exchanged as wall-clock timestamps plus pause accounting:
`startedAt`, optionally `pausedAt` and `stoppedAt`, `accumulatedPauseMs`, and
optionally the planned duration. A remaining-time field MUST NOT be sent, and
MUST NOT appear in any fixture that carries state: the receiver derives
remaining time from `startedAt`, `accumulatedPauseMs`, and its own clock, which
is what keeps a timer correct across backgrounding, reconnect, and clock drift
between devices.

A `timer_state` message is authoritative for every timer kind it names. A kind
carrying `null` clears that timer. A `session_snapshot` is authoritative for
timer state as a whole; kinds it omits are cleared, except a kind whose newest
row the snapshot's sender did not write — a snapshot speaks for the countdowns
it started, and MUST NOT stop one the receiver started itself. A kind carrying
`null` in a snapshot is cleared even so. Verified by
`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`
(`testS79ASnapshotLeavesTheWristsCountdownRunningAndStopsThePhones`,
`testS79AKindNamedNullIsStillCleared`) and, for the Dart twin, by
`test/watch_logging_timers_test.dart` (`S-79 a snapshot leaves the wrist's
countdown running and stops the phone's own`, `S-79 a kind named null is still
cleared`).

## Session capture (normative)

A wrist that ends a session reports two session-scoped events and the
summaries it computed from its own sensor readings. Raw readings never travel:
the fields below are the only values derived from them that appear on the wire.

- **`effort_rating`** carries `rating`, an integer on the scale
  `watch/contract/watch_effort_rating_contract.json` defines. A wrist appends at
  most one per session, with `entryId` and `eventId` both `rating-<sessionId>`,
  and never edits one. The phone's own rating for the session is final
  (authority rule 4).
- **`session_end`** carries the session's `startedAt` and `endedAt`, its
  `status` (`completed` or `abandoned`), its `modality` when it has one, and the
  session's heart-rate summary. A wrist appends exactly one for each session it
  created — `entryId` and `eventId` both `end-<sessionId>` — at the session's
  first transition to completed or abandoned, whichever device caused it. A
  session reopened and ended again gets no second one, and a session the wrist
  joined from the phone gets none. `endedAt` is the wrist's clock when the
  wrist ended the session, the payload's `at` when a `session_lifecycle` from
  the phone did, and the envelope's `sentAt` when a `session_snapshot` from the
  phone did.
- **Phone-logged entries.** The phone logs sets too, and mints their ids itself:
  `entry-<sessionExerciseId>-<n>`, where `n` is the entry's ordinal among the
  sets logged in that slot, with `eventId` equal to `entryId` as it is on the
  wrist. A phone id names the same entry on every projection, and cannot collide
  with the UUIDs a wrist mints.
- **Summary fields.** Each travels only on the kinds in the table; anywhere
  else it is a `semantic_violation`, in an `observations_up` event and in a
  `session_snapshot` entry alike. A value is absent when nothing was measured,
  never zero: the heart-rate fields have a minimum of 1, so a zero-filled
  summary cannot be sent. An event is never re-sent with different values.

| Field | Carried by | Meaning |
|-------|-----------|---------|
| `avgHeartRateBpm`, `maxHeartRateBpm` | `timed`, `round`, `hold`, `session_end` | Mean and maximum heart rate over the entry's active window — pauses excluded — or, on `session_end`, over the whole session. The two travel together, and the average never exceeds the maximum |
| `steps` | `timed` | Steps inside the window, from the wrist's step counter. A measured zero is sent |
| `distanceSource` | `timed`, with `distanceMeters` | Where the distance came from: `gps`, `entered` or `estimated` |
| `pausedMs` | `round` | The round's accumulated pause, which its active window excludes. Never longer than the window |
| `setBlockHeartRates` | `session_end` | One heart-rate pair per *set block* — the sets logged for one `sessionExerciseId` and `exerciseId` pair — with the span it covers. Each block appears once |
| `rating` | `effort_rating` | The session effort rating |
| `status`, `modality` | `session_end` | How the session ended, and its modality |

`fixtures/valid/observations_up_session_capture.json` is the shape in full, and
`watch/contract/watch_capture_contract.json` is one session end to end: the
events a wrist emits and what the phone holds after importing them.

A phone-side change to a distance is never sent to the watch: a `correct_entry`
correction carries no distance
(`fixtures/invalid/structure_change_correction_distance.json`).

## Idempotency and reconciliation (normative)

- Every observation MUST be safe to deliver more than once. Re-applying an
  event whose `eventId` or `entryId` has already been seen MUST NOT create a
  second entry and MUST NOT raise an error.
- On connect and on reconnect, the devices exchange `session_snapshot`. A
  snapshot MUST replace structure, status, position, revision, and timer state.
  When it names the session the receiver holds, its entries MUST be merged by
  `entryId` rather than replacing the local set, so observations the
  snapshot's sender has not seen are not lost; an `entryId` the receiver already
  holds MUST NOT be stored a second time.
- A `session_snapshot`'s `entries` are the entries its sender logged: a receiver
  MUST NOT add them back under a second `entryId`, and MUST NOT read a snapshot
  as a claim about entries its sender did not log. Entries are ordered by
  `loggedAt`, then by `entryId` where two share an instant.
  `fixtures/valid/session_snapshot_with_entries.json` is the shape, and
  `fixtures/reconciliation/phone_entries_merge.json` pins the merge.
- A snapshot naming an `entryId` the receiver already holds MUST be read as its
  sender's current values for that entry: the receiver MUST re-state the entry
  from the snapshot's payload — the correction the sender made is what it shows
  — and MUST NOT store a second row or rewrite the record it already holds.
  Only the watch re-states: for an id it holds it takes the values the phone's
  snapshot carries for it. A phone that receives a watch snapshot keeps the
  values it already holds for an id — its model does not re-state, because the
  watch does not edit existing records (authority rule 1) — and the phone's
  answer carries the watch's own values for the watch's own entries, so a
  re-statement of one is a no-op. Verified by the wrist-side tests in
  `watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift`
  (`testS35AReStatementShowsThePhonesNewValueAndLeavesTheRow`,
  `testASecondEditWinsOverTheFirst`), by the phone-side half of the two stacks'
  agreement in `test/watch_reconciliation_cross_stack_test.dart` (`S-35 a held id
  the phone edited is re-stated on the wrist, not resaved`: the wrist shows the
  new value, the phone its own), and, for the Dart twin,
  `test/watch_session_projection_test.dart`
  (`S-35 a re-statement is append-only and doubles nothing`,
  `S-35 a second edit wins over the first`).
- A snapshot that names a session other than the one the receiver holds is not
  a merge. It MUST replace the held session wholesale — structure, status,
  position, revision, timers, and entries — so entries never merge across
  sessions. The receiver adopts it and MUST NOT answer it: re-assertion (below)
  is for a snapshot of the session the receiver holds.
  `fixtures/reconciliation/session_switch.json` pins it.
- The one exception to that replacement is the wrist mid-workout: a snapshot
  naming another session MUST be refused whole while the wrist holds an
  `active` session of its own with a non-empty ladder — nothing applied, no row
  written, nothing emitted, and no session end captured for the session the
  snapshot names. What the user is in the middle of is not interrupted by a
  frame that is not about it. A wrist holding nothing, holding a session that
  has already ended (`completed` or `abandoned`), or holding a session whose
  ladder is empty adopts the snapshot as above. Verified by
  `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`
  (`testS77AForeignSnapshotChangesNothingAndSaysNothing`,
  `testS77ARefusedSnapshotDoesNotEndASessionTheWristCreatedEarlier`), with the
  counter-cases `testS77TheSameSnapshotAppliesOnceTheWristHasFinished` and
  `testS77AWristWithAnEmptyLadderReservesNothing`, and, for the Dart twin, by
  `test/watch_session_engine_test.dart` (`S-77 a snapshot for another session
  changes nothing and says nothing`, `S-77 counter-case the same snapshot
  applies once the wrist has finished`, `S-77 counter-case a wrist with an
  empty ladder reserves nothing`).
- Session-scoped frames name the session they are about. A receiver MUST
  refuse a `session_lifecycle`, `timer_state`, `structure_change` or
  `exercise_push` whose `sessionId` is not the id of the session it holds —
  nothing applied, no row written, no answer sent — because a frame about
  another session is not news about this one. Verified by
  `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`
  (`testS78ALifecycleForAnotherSessionConcernsNobodyHere`,
  `testS78AnAdvancedPositionForAnotherSessionMovesNothing`,
  `testS78AStructureChangeForAnotherSessionWritesNoRow`,
  `testS78AnExercisePushForAnotherSessionLandsNowhere`,
  `testS78TimerStateForAnotherSessionAdoptsNoTimer`) and, for the Dart twin, by
  `test/watch_session_engine_test.dart` (`S-78 a lifecycle for another session
  concerns nobody here`, `S-78 an advanced position for another session moves
  nothing`, `S-78 timer state for another session adopts no timer`,
  `S-78 a structure change for another session writes no row`,
  `S-78 an exercise push for another session lands nowhere`).
- Between snapshots, incremental messages keep the two sides aligned. A device
  that reconnects MUST resume from the last snapshot it reconciled, then replay
  the observations it accumulated while apart.
- On sync, a wrist MUST re-send every observation the phone has not
  acknowledged, for every session it stores — not only the current one — in the
  order it stored them. A session that ended while the wrist was out of reach is
  still owed to the phone after the next one starts.
- A device MAY ask its peer for a snapshot at any time — joining a session that
  is already running, or resuming after a reconnect. The request is a transport
  concern and carries no message of its own; the answer MUST be a
  `session_snapshot`. A device with no session to report answers nothing: an
  empty session is not a state, and a device that has logged nothing is not
  the authority on anything.
  Verified by `test/live_mirroring_test.dart` (`S-006 joining an in-progress
  phone session from the watch`, `S-009 a sessionless watch answers a snapshot
  request with nothing`) and by watchOS
  `WatchLiveMirroringTests.testASnapshotRequestIsAnsweredOnce` and
  `WatchLiveMirroringTests.testASessionlessWatchAnswersNothing`.
- The phone MAY send a `session_snapshot` of the session it is in without being
  asked, so a change the user makes on the phone reaches the wrist on its own
  rather than at the wrist's next sync. Such a frame carries the position the
  receiver last reported, never the sender's own first slot, so a wrist on its
  third exercise is not moved back to its first. Verified by
  `test/watch_session_auto_push_test.dart` (`S-71 the push reports the wrist's
  position, not slot 0`) and by `test/watch_session_projection_test.dart`
  (`S-76 the answer carries the position the wrist is on`).
- A push MUST NOT re-send a payload equal to the one it last sent: a state that
  notifies without changing anything the peer can see MUST NOT produce a frame,
  and a burst of changes inside one window MUST be composed into one. The
  comparison is over the payload's encoding, so a `revision` that does not move
  is not a reason to speak and one that moves is not a reason to stay silent.
  Verified by `test/watch_session_auto_push_test.dart` (`S-74 five
  notifications without a change push nothing`, `S-75 three changes inside the
  window are one frame`, `S-75 the trailing window closes by itself`).
- A frame the phone applied from the wrist MUST NOT be pushed back: applying a
  peer's frame re-composes the payload and stores it as the last-sent one
  without sending, so a push is never a reply to the wrist's own news. Verified
  by `test/watch_session_auto_push_test.dart` (`S-80 the wrist's own set and
  its snapshot are not answered with a push`).
- A push the transport cannot carry is dropped: the failure is reported and the
  push MUST NOT queue it, retry it, or hold any user-visible state for it.
  Catching up is the peers' own reconciliation, not a queue. Verified by
  `test/watch_session_auto_push_test.dart` (`S-83 a failed send is reported
  once, changes nothing, and is not retried`).
- A push re-delivered MUST change nothing: it is an ordinary snapshot or
  lifecycle, so re-applying one MUST NOT write a second row, a second entry, or
  a second end. Verified by `test/watch_session_auto_push_test.dart` (`S-81 the
  same snapshot twice writes nothing new on the wrist`, `S-81 the same
  lifecycle twice ends the wrist's copy once`, `S-81 the same observation twice
  leaves the phone unchanged and pushes nothing`).
- A snapshot MUST NOT be answered with a snapshot that says the same thing:
  agreeing peers stay silent, or two connected devices would answer each other
  for ever. This is the phone's rule to apply, and it applies to the phone
  alone: structure is the phone's to own (authority rule 2), so when a watch
  snapshot of the session the phone holds reports a different shape, the phone
  answers with the shape it held, and a watch never answers a snapshot at all —
  its ladder is the phone's reflection, and a watch that re-asserted one would
  be originating structure.
  Entries are not part of this comparison: they merge by `entryId`, so an entry
  one side lacks is a convergence in progress rather than a disagreement.
  Verified by `test/live_mirroring_test.dart` (`S-008 a snapshot the phone
  disagrees with is answered with its own`) and by watchOS
  `WatchLiveMirroringTests.testPendingObservationsSurviveARelaunchAndClearOnTheSnapshotsReceipt`.
- Concurrent edits are resolved by authority, not by last-write-wins: structure
  comes from the phone, entries come from whoever logged them.
- Lifecycle messages are applied in the order received, and the most recent
  status wins. A session reported `started` after an abandon is live again;
  `completed` and `abandoned` are terminal until a later lifecycle message
  says otherwise.
- The phone MUST report its own finish. A session the phone has ended (its
  record carries an end) MUST be announced with `completed`, and one the phone
  discarded (its record is gone) with `abandoned`, once each. What is announced
  is the session the two devices share, read from that session's own record:
  a past session the user opens on the phone MUST NOT be read as the shared one
  ending, and MUST NOT be announced. Verified by
  `test/watch_session_auto_push_test.dart` (`S-72 finishing on the phone ends
  the wrist's copy, once`, `S-73 discarding on the phone abandons the wrist's
  copy, once`, `S-84 opening a past session pushes nothing for the live one`)
  and by `test/watch_session_finish_test.dart` (`S-5 the phone's own finish is
  reported, and the wrist is answered at its next sync`).
- `revision` increases by one per applied structure change, so two clients can
  tell at a glance whether they are looking at the same session shape.
- Applying the same event stream twice MUST produce the same end state as
  applying it once. `fixtures/reconciliation/duplicate_delivery.json` and
  `fixtures/reconciliation/snapshot_then_events.json` pin both halves of this.

## Versioning policy (normative)

- Every message MUST carry the protocol version it was written against.
- A receiver MUST NOT interpret a message that advertises a different version —
  older or newer. It MUST reject the message, MUST NOT apply it, and MUST
  answer with a `session_snapshot` so the peer converges from authoritative
  state instead of from a stream it cannot read.
- After a version mismatch the pair stays in snapshot-only exchange until both
  devices advertise the same version. A device that cannot read the other's
  snapshot MUST suspend sync and surface an upgrade prompt; it MUST NOT resume
  incremental sync.
- Version 1 is the only version defined today. Adding a version means adding
  schemas, fixtures, and a `## Version history` entry here; it never means
  editing a fixture that v1 clients already ship.

`fixtures/reconciliation/version_mismatch.json` carries both directions of the
mismatch (watch older, watch newer) with the decision each must produce.

## Validation profiles

- **Conformance (this repository, both watch clients).** Strict: unknown fields
  are rejected, every required field must be present, and every valid fixture
  must parse. This is what `additionalProperties: false` is for — it turns a
  typo and a stray remaining-time field into a build failure.
- **Cross-version reading.** Lenient: ignore fields the reader does not know,
  require the fields it does, and never guess at a field it cannot interpret.
  This profile exists only so a peer one version away can still read a
  `session_snapshot`; it is not an invitation to skip the conformance profile.

## Rejection codes

A rejection carries a stable machine-readable `code`, the `path` inside the
message, and a human-readable reason. Clients MUST switch on the code, never on
the reason text.

| Code | Meaning |
|------|---------|
| `unsupported_protocol_version` | The message advertises a version this receiver does not speak. The payload was not read |
| `unknown_message_type` | `type` is missing, not a string, or not a defined message family |
| `missing_schema` | The receiver has no schema document for a known type |
| `unresolvable_reference` | A `$ref` in the schema could not be resolved — a defect in the schema set, not in the message |
| `missing_required_field` | A field the schema requires is absent |
| `unexpected_field` | A field the schema does not define is present (this is how a remaining-time field is caught) |
| `invalid_type` | The value is not the type the schema requires |
| `invalid_enum_value` | The value is not one of the allowed values |
| `invalid_const_value` | The value is not the single value a message type pins (e.g. `type`, `origin`) |
| `constraint_violation` | A bound was broken: `minItems`, `minLength`, `minimum`, `maximum`, or `pattern` |
| `no_matching_variant` | The value matches none (or more than one) of the allowed shapes in a `oneOf` |
| `semantic_violation` | The message is well-formed but violates a rule JSON Schema cannot express — fallback coverage, timer kind mismatch, position out of range, a workout entry without its exercise, a repeated `eventId`, a summary field on a kind that does not carry it |

## Consuming these fixtures

All three clients run the same files. Each MUST run every fixture in
`fixtures/manifest.json`: conforming fixtures MUST validate, non-conforming
fixtures MUST be rejected with the code and reason the manifest states, and
every reconciliation fixture MUST converge on its `expected` state.

- **Phone (Flutter).** `test/sync_protocol_fixtures_test.dart` walks the
  manifest and covers all three. `test/live_mirroring_test.dart` replays the
  same register through the phone's live mirror
  (`lib/state/watch/live_session_mirror_state.dart`) and through the Wear OS
  watch engine, which is what keeps "the phone's half" and "the watch's half"
  of the apply rules from drifting apart. The standing `flutter test` gate runs
  both, so they also run as part of the pre-release check.
- **watchOS.** The Swift package that owns the watch-side sync client MUST load
  the same JSON from this directory and re-run the conformance and
  reconciliation cases in XCTest: `SyncProtocolFixturesTests.swift` for
  conformance, `WatchLiveMirroringTests.swift` for the watch engine's half of
  the reconciliation.
- **Wear OS.** The Kotlin module MUST do the same in JUnit, using the repository
  copy of `fixtures/manifest.json`.

A client that disagrees with a fixture has found either a bug or a protocol
change. Fix the bug, or change the spec, the schema, and the fixture together in
one pull request — never edit a fixture to match an implementation.

## Version history

| Version | Date | Notes |
|---------|------|-------|
| 1 | 2026-07-13 | First published protocol: seven message families, the authority rules, wall-clock timer state, snapshot reconciliation |
| 1 (amended) | 2026-09-25 | Session capture: the `preferences_down` message; the `effort_rating` and `session_end` event kinds; the heart-rate, steps, pause and set-block summary fields; the session-switch rule; the resend rule. Additive, as the `receipt` addition was: both clients ship from this repository in one release, v1 is unreleased, and no receiver that predates the change exists. No existing fixture changed |
| 1 (amended) | 2026-09-27 | Session capture: the `distanceSource` summary field on a `timed` entry that also carries `distanceMeters`. Additive for the same reason as the 2026-09-25 amendment; optional in this release, PR 3c makes it required when the watch sends it. No existing fixture changed |
| 1 (amended) | 2026-10-05 | Phone-logged entries: authority rule 1 states that the phone MAY add entries it logged, which arrive in its `session_snapshot`; a snapshot's `entries` are the sender's own and are ordered by `loggedAt` then `entryId`; entries merge by `entryId`, and an `entryId` a receiver already holds is not stored a second time; the id a phone mints for a set it logged is `entry-<sessionExerciseId>-<n>` with `eventId` equal to it. The wire shape does not change — `session_snapshot` already requires `entries` and envelope already carries every metric a set needs — so no schema and no version change. Additive for the same reason as the 2026-09-25 amendment; no existing fixture changed. `fixtures/valid/session_snapshot_with_entries.json` is the shape and `fixtures/reconciliation/phone_entries_merge.json` pins the merge |
| 1 (amended) | 2026-10-06 | Entries a snapshot re-carries: an `entryId` the receiver already holds is re-stated from the snapshot's payload — the receiver shows the sender's current values, stores no second row, and leaves the record it holds unrewritten. Only the watch re-states, taking for an id it holds the values the snapshot carries; a phone keeps the values it already holds, and the answer carries the watch's own values for the watch's own entries, so a re-statement of one is a no-op. The wire shape does not change — no schema and no version change — and no existing fixture changed: the re-statement is pinned by the wrist-side tests `watch/watchos/Tests/WatchSessionEngineTests/WatchPhoneEntriesTests.swift` (`testS35AReStatementShowsThePhonesNewValueAndLeavesTheRow`, `testASecondEditWinsOverTheFirst`) and the Dart twin's `test/watch_session_projection_test.dart` (`S-35 a re-statement is append-only and doubles nothing`). Additive for the same reason as the 2026-09-25 amendment |
| 1 (amended) | 2026-10-06 | A band-assisted set: a `loadKg` MAY be negative down to -200 kg — a band or partner assist, a load below bodyweight — on an entry, a routine target and a correction alike. A value below -200 kg MUST be rejected as invalid, not clamped into range. The floor is the bound the phone's set editor already enforces, so the wire refuses no set the phone can produce. No new field, no schema shape change beyond the widened minimum, and no version change: only what is accepted widens, so nothing a v1 client accepted becomes invalid. No existing fixture changed. `fixtures/valid/observations_up_band_assist.json`, `fixtures/valid/session_snapshot_band_assist.json`, `fixtures/valid/structure_change_band_assist.json` and `fixtures/valid/routines_down_band_assist.json` are the shapes and `fixtures/invalid/observations_up_load_below_floor.json` is the refusal, pinned by `test/sync_protocol_fixtures_test.dart` (`S-58 an assisted set on the observations wire`, `S-59 the band-assisted set travels with its sign`, `S-65/S-66 one floor for a correction and a target`) and by `test/watch_reconciliation_cross_stack_test.dart` (`S-67 a re-stated assist is neither duplicated nor zeroed`) |
| 1 (amended) | 2026-10-06 | The wrist's session-acceptance rules: a `session_snapshot` naming another session is refused whole while the wrist holds an `active` session of its own with a non-empty ladder — nothing applied, no row written, nothing emitted, and no session end captured for the session it names — while a wrist holding nothing, holding a session that has already ended, or holding one whose ladder is empty adopts it as before; `session_lifecycle`, `timer_state`, `structure_change` and `exercise_push` are refused when their `sessionId` is not the id of the session the receiver holds; and a snapshot stops only the timer kinds its own sender wrote, so a countdown the receiver started keeps running, while a kind the snapshot carries as `null` is still cleared and a kind it carries running is still adopted. No new field, no schema change, no version change — no existing fixture changed — and the rules are pinned by `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift` (`testS77AForeignSnapshotChangesNothingAndSaysNothing`, `testS77ARefusedSnapshotDoesNotEndASessionTheWristCreatedEarlier`, `testS78ALifecycleForAnotherSessionConcernsNobodyHere`, `testS78AnAdvancedPositionForAnotherSessionMovesNothing`, `testS78AStructureChangeForAnotherSessionWritesNoRow`, `testS78AnExercisePushForAnotherSessionLandsNowhere`, `testS78TimerStateForAnotherSessionAdoptsNoTimer`), by `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift` (`testS79ASnapshotLeavesTheWristsCountdownRunningAndStopsThePhones`, `testS79AKindNamedNullIsStillCleared`), and by the Dart twin's `test/watch_session_engine_test.dart` (`S-77 a snapshot for another session changes nothing and says nothing`, `S-78 a lifecycle for another session concerns nobody here`) and `test/watch_logging_timers_test.dart` (`S-79 a snapshot leaves the wrist's countdown running and stops the phone's own`). Additive for the same reason as the 2026-09-25 amendment |
| 1 (amended) | 2026-10-06 | The phone's own push: the phone MAY send a `session_snapshot` of the session it is in without being asked, carrying the position the receiver last reported rather than its own first slot; a payload equal to the one last sent is not re-sent, a burst of changes inside one window composes into one frame, a frame the phone applied from the wrist is re-baselined rather than answered, a push the transport cannot carry is dropped rather than queued, and a push re-delivered changes nothing. The phone also MUST report its own finish — `completed` for a session it ended, `abandoned` for one it discarded — read from that session's own record, so a past session the user opens is not the shared one ending. No new field, no schema change, no version change, and no existing fixture changed. Pinned by `test/watch_session_auto_push_test.dart` (`S-70 the phone's own set is pushed as one snapshot, and the wrist's own set is not sent back`, `S-71 the push reports the wrist's position, not slot 0`, `S-72 finishing on the phone ends the wrist's copy, once`, `S-73 discarding on the phone abandons the wrist's copy, once`, `S-74 five notifications without a change push nothing`, `S-75 three changes inside the window are one frame`, `S-75 the trailing window closes by itself`, `S-80 the wrist's own set and its snapshot are not answered with a push`, `S-81 the same snapshot twice writes nothing new on the wrist`, `S-81 the same lifecycle twice ends the wrist's copy once`, `S-81 the same observation twice leaves the phone unchanged and pushes nothing`, `S-83 a failed send is reported once, changes nothing, and is not retried`, `S-84 opening a past session pushes nothing for the live one`), by `test/watch_session_projection_test.dart` (`S-76 the answer carries the position the wrist is on`) and by `test/watch_session_finish_test.dart` (`S-5 the phone's own finish is reported, and the wrist is answered at its next sync`). Additive for the same reason as the 2026-09-25 amendment |
