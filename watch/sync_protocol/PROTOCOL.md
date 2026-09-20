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
| `exercise_push` | phone → watch | A catalog exercise the user searched for on the phone, pushed into the live session | `schemas/messages/exercise_push.schema.json` | `fixtures/valid/exercise_push.json` |
| `structure_change` | phone → watch | Add, remove, reorder, swap, correct a logged entry, delete a logged entry | `schemas/messages/structure_change.schema.json` | `fixtures/valid/structure_change.json` |
| `observations_up` | watch → phone | Append-only observations: sets, timed entries, rounds, holds, nutrition quick-logs | `schemas/messages/observations_up.schema.json` | `fixtures/valid/observations_up.json` |
| `session_lifecycle` | either | Session started, exercise advanced, completed, abandoned | `schemas/messages/session_lifecycle.schema.json` | `fixtures/valid/session_lifecycle.json` |
| `session_snapshot` | either | The full live-session state, exchanged on connect, on reconnect, and after a rejection | `schemas/messages/session_snapshot.schema.json` | `fixtures/valid/session_snapshot.json` |
| `timer_state` | either | Rest, round, hold, and elapsed timers as wall-clock timestamps plus pause bookkeeping | `schemas/messages/timer_state.schema.json` | `fixtures/valid/timer_state.json` |

Notes that follow from the schemas:

- The fallback exercise list MUST cover every exercise any synced routine
  references — the watch must never hold a routine it cannot log. The validator
  reports a `semantic_violation` when coverage is missing.
- `fallbackExercises` is catalog reference data: it names exercises, not session
  slots, so its entries carry no `sessionExerciseId`.
- `exercise_push` is itself the structural edit: it carries `insertAtIndex`
  and the slot it creates. The phone MUST NOT follow it with an `add_exercise`
  change for the same slot.
- Every observation event is self-contained. It carries the slot it was logged
  in, the catalog exercise, the kind, the wall-clock timestamps, and the metrics
  the entry needs. The phone never has to ask the watch a follow-up question to
  materialise an entry.
- An observation event carries both `eventId` and `entryId`. `eventId` is the
  delivery key, `entryId` is the entry's identity; the two are equal in
  practice, and either one alone is enough to reject a duplicate.
- A `session_snapshot` payload carries its own `sessionId`, which MUST match the
  envelope's.
- An observation event carries the metrics its entry needs: `reps` and `loadKg`
  for a set, `startedAt` and `endedAt` for timed work, rounds and holds,
  `distanceMeters` for distance-capable work, and `extraLoadKg` for a hold's
  added or assisting load. Distance is entered by hand whenever the watch has no
  fix: GPS is a separate concern and MUST NOT gate an entry.
  `fixtures/valid/observations_up_distance_and_load.json` is the shape in full.

## Authority rules (normative)

1. The watch MUST NOT edit or delete existing records. It appends new
   observations and MAY reflect corrections the phone sends, but it never
   originates a mutation of anything already recorded.
2. The phone MUST be authoritative for session structure: adding, removing,
   reordering, and swapping exercises. Only the phone sends `structure_change`.
3. When a structure change removes the exercise the watch is currently on, the
   watch MUST advance to the next valid exercise: the position stays at the
   same index, which now holds the exercise that followed, or moves to the last
   exercise when the removed one was last. `fixtures/reconciliation/remove_current_exercise.json`
   pins this.
4. The phone MUST accept watch-appended observations. There is no negotiation,
   no approval step, and no "watch data pending" state — an observation the
   watch sent is part of the session.
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
timer state as a whole; kinds it omits are cleared.

## Idempotency and reconciliation (normative)

- Every observation MUST be safe to deliver more than once. Re-applying an
  event whose `eventId` or `entryId` has already been seen MUST NOT create a
  second entry and MUST NOT raise an error.
- On connect and on reconnect, the devices exchange `session_snapshot`. A
  snapshot MUST replace structure, status, position, revision, and timer state.
  Its entries MUST be merged by `entryId` rather than replacing the local set,
  so observations the snapshot's sender has not seen are not lost.
- Between snapshots, incremental messages keep the two sides aligned. A device
  that reconnects MUST resume from the last snapshot it reconciled, then replay
  the observations it accumulated while apart.
- Concurrent edits are resolved by authority, not by last-write-wins: structure
  comes from the phone, entries come from whoever logged them.
- Lifecycle messages are applied in the order received, and the most recent
  status wins. A session reported `started` after an abandon is live again;
  `completed` and `abandoned` are terminal until a later lifecycle message
  says otherwise.
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
| `semantic_violation` | The message is well-formed but violates a rule JSON Schema cannot express — fallback coverage, timer kind mismatch, position out of range, a workout entry without its exercise, a repeated `eventId` |

## Consuming these fixtures

All three clients run the same files. Each MUST run every fixture in
`fixtures/manifest.json`: conforming fixtures MUST validate, non-conforming
fixtures MUST be rejected with the code and reason the manifest states, and
every reconciliation fixture MUST converge on its `expected` state.

- **Phone (Flutter).** `test/sync_protocol_fixtures_test.dart` walks the
  manifest and covers all three. The standing `flutter test` gate runs it, so it
  also runs as part of the pre-release check.
- **watchOS.** The Swift package that owns the watch-side sync client MUST load
  the same JSON from this directory and re-run the conformance and
  reconciliation cases in XCTest.
- **Wear OS.** The Kotlin module MUST do the same in JUnit, using the repository
  copy of `fixtures/manifest.json`.

A client that disagrees with a fixture has found either a bug or a protocol
change. Fix the bug, or change the spec, the schema, and the fixture together in
one pull request — never edit a fixture to match an implementation.

## Version history

| Version | Date | Notes |
|---------|------|-------|
| 1 | 2026-07-13 | First published protocol: seven message families, the authority rules, wall-clock timer state, snapshot reconciliation |
