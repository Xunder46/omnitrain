# Data Models — watch capture and session energy (part page)

Part of [Data Models](data_models.md): the watch capture models and the session energy model, split out to keep each page under the indexing ceiling. Section order and wording are unchanged.

## Watch Capture Models

Covers `SensorSummary` and `WatchInboxEntry` in `lib/data/models/models.dart`,
stored through the watch-capture methods of `WorkoutRepository` (see
[DB Integration](db_integration.md#watch-capture-storage)). Decisions D-131 and
D-132 of `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`.

### SensorSummary

A heart-rate and step summary the wrist measured over one window of a wrist
session. It attaches to exactly one target, named by its scope: the
`TrainingSession` itself, a set block (`SegmentEffort`), a timed or hold entry
(`TimedInstance`), or a round (`RoundInstance`). Every summary also names the
session it belongs to, whatever its scope. The scope vocabulary is
`SensorSummary.scopes`.

Why it is its own model:
- **Not `metric-heart-rate` observations.** A summary is an average and
  maximum pair plus steps. An `EffortObservation` holds one value per metric
  per entry and cannot address a session or a `RoundInstance`. Summaries are
  measured, never entered, so they must never be read or edited as a manual
  metric; `metric-heart-rate` stays seeded and unused.
- **Not new columns on its targets.** `TrainingSession`, `TimedInstance` and
  `RoundInstance` rows are rebuilt field by field in several places (for
  example `endSession` and `updateSessionFeeling`), where a new field would be
  silently dropped.

Invariants:
- **Refused at construction.** The constructor throws `ArgumentError` for an
  unknown scope, a session summary aimed at another session, a heart-rate pair
  that is not both-or-neither, a zero average or one above the maximum,
  negative steps, steps outside a `timed_instance`, no measured value at all, a
  reversed window, or a source other than the watch. A missing reading is
  absence, never zero. Verified by `test/watch_capture_repository_parity_test.dart`
  (`D-131 refuses a zero heart rate, …`), against both repositories.
- **One per target, never rewritten.** The id derives from scope and target
  (`SensorSummary.idFor`) and `createSensorSummary` is put-if-absent
  (`D-131 stores put-if-absent by scope and target: …`).
- **Deleted with its target.** A repository delete removes the summaries of
  every row it deletes, and `deleteSession` removes all of the session's
  (the `D-131 delete… removes …` tests).

### WatchInboxEntry

One thing the phone learned about a wrist session before it became history:
a wrist event (origin `watch`), or one of the phone's own annotations on that
session (origin `phone`): its rating, and the live corrections and deletions
it sent for a wrist entry. The kind vocabularies are
`WatchInboxEntry.watchKinds` and `WatchInboxEntry.phoneKinds`. The phone mints
its annotation ids with `phoneRatingId` and `phoneChangeId`, so each is
staged at most once.

Why it exists: the wrist delivers a session's observations, rating and end in
any order, possibly more than once, and possibly across a phone restart.
Staging each on arrival lets the import into history be idempotent,
independent of arrival order, and durable.

Invariants:
- **Put-if-absent by entry id.** The first copy is the record; a redelivered
  or altered copy never replaces it (`D-132 stages put-if-absent: …`).
- **Applied once, never deleted, with one exception.** A row keeps its first
  applied stamp (`D-132 marks rows applied in one batch; …`). Applied rows are
  the tombstones that keep history the user deleted from being re-created, so
  no history delete cascades into the inbox
  (`D-132 the inbox survives deleteSession: …`). The exception is a Discard
  that has to recover an entry which arrived while the Edit Session screen was
  open: the stamp is unset on exactly that entry, so the next import pass
  re-materialises it. The repository half is `clearWatchInboxApplied`
  (`test/watch_capture_repository_parity_test.dart`, `S-1412`); the Discard is
  `test/watch_session_edit_restore_late_entry_test.dart` (S-1401).
- **The payload is frozen.** The event is held as its JSON encoding; the map a
  caller reads is a fresh copy, and a payload that is not a JSON object is
  refused (`D-132 a staged payload is JSON, …`).
- **Kind follows origin.** A phone kind with origin `watch`, a wrist kind with
  origin `phone`, a kind outside both vocabularies, or a phone id not minted by
  the helpers is refused (`D-132 WatchInboxEntry refuses a kind outside …`).

---

## Session Energy Model

`SessionEnergy` (`lib/data/models/models.dart`) is the active energy, above
resting, that one stored session burned. One row per session, keyed by
`sessionId`: `activeKcal` (double, unrounded), `source` (`estimated` or
`measured`), `bodyWeightKg` (double ?); an estimate stores the body weight it
used, required finite and above 0, a `measured` row carries none. The
constructor refuses a source outside the two, negative or non-finite kcal, a
`measured` row with a weight and an `estimated` row without one. Not a
`SensorSummary`: a summary is put-if-absent per target and needs a heart rate
or steps. A measured row is written by the watch importer from the end's
`activeEnergyKcal`. Storage: [DB Integration](db_integration.md#session-energy-storage).
Verified by `test/session_energy_repository_test.dart` (group
`D-13401 SessionEnergy refuses what the contract refuses`).

---
