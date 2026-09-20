# Feature: Watch↔Phone Sync Protocol Specification

> **Tier 2 — Watch foundation. Launch-critical path. Gates all watch code.**
> Covers both watch platforms: native watchOS and Flutter Wear OS.
> Last reconciled against source: 2026-07-13.

## Overview

Two watch clients on two stacks (native watchOS, Flutter Wear OS) must
speak exactly one language with the phone. This item produces a
platform-neutral specification for that language plus machine-readable
conformance fixtures, kept in the repository as living documentation,
that every client (native watchOS app, Flutter Wear OS app, Flutter
phone app) validates against. The protocol encodes the product's
authority rules as normative statements — the watch appends and never
edits, the phone owns session structure, all timers are wall-clock
timestamps with pause bookkeeping — so the rule is not tribal knowledge
across three codebases. Defining the language once and fixture-testing
it before any watch UI exists is what keeps the two watch apps from
drifting apart behaviourally.

## Requirements

### Message families

- **Routines-down**: delivering the user's routines (full template chain
  — routine → segments → efforts → per-metric targets) and the fallback
  exercise list (recent exercises plus every exercise referenced by
  synced routines) to the watch proactively.
- **Exercise-push**: the phone pushing a catalog exercise into a live
  watch session (user searched on the phone).
- **Structure-and-corrections-down**: phone-originated changes to a live
  session — add, remove, reorder, swap, and corrections to logged
  entries — streamed to the watch for display.
- **Observations-up**: an append-only event stream of everything the
  watch logs — sets, timed entries, rounds, holds, nutrition
  quick-log entries — where each event is self-contained and
  idempotent, safe to deliver more than once.
- **Session lifecycle**: session started (on either device), exercise
  advanced, session completed or abandoned.
- **Live-state reconciliation**: a full session snapshot exchanged on
  connect and reconnect so both devices converge after any period
  apart; between snapshots, incremental events keep them aligned.
- **Timer state**: all timers (rest, round, hold, elapsed) exchanged as
  wall-clock timestamps plus pause bookkeeping, never as
  remaining-time countdowns.
- **Protocol versioning**: every message carries a protocol version; the
  spec defines behaviour when versions differ.

### Authority rules (normative)

- The watch only appends new records; it never edits or deletes
  existing data. It may display corrected state originating from the
  phone but never originates a mutation.
- The phone is authoritative for session structure (add / remove /
  reorder / swap).
- If a structure change removes the exercise the watch is currently on,
  the watch advances to the next valid exercise.
- Watch-appended observations are always accepted by the phone.

### Conformance fixtures

- Example payloads for every message type, valid and invalid, with each
  invalid fixture stating its rejection reason.
- A reconciliation fixture (snapshot + event stream) whose replay
  produces the expected converged state.
- A duplicate-delivery fixture demonstrating idempotency.
- A version-mismatch fixture with defined expected behaviour.

### Out of scope

- Any transport implementation (WatchConnectivity, Wear OS Data Layer).
- Any UI.
- Cloud sync of any kind.

## Acceptance Criteria

- [ ] Every message type has a defined schema, at least one valid
      fixture, and at least one invalid fixture with the rejection
      reason stated.
- [ ] The spec contains explicit normative statements for the
      authority rules and the append-only guarantee.
- [ ] No fixture representing timer state contains a remaining-time
      field — timestamps and pause accounting only.
- [ ] Replaying the same observations-up fixture stream twice against
      the reconciliation rules yields an identical end state
      (idempotency demonstrated in fixtures).
- [ ] A version-mismatch fixture exists with defined expected
      behaviour.
- [ ] The fixtures live in the repository as machine-readable files
      (JSON or equivalent) and are consumed by phone, watchOS, and
      Wear OS test suites.
- [ ] The protocol document is reviewable in plain prose with links to
      fixtures.

## Scenarios

### S-001: Routines-down schema and fixtures
- Trigger: Engineer reads the routines-down message definition.
- Precondition: A routine with at least one segment, one effort, and
  per-metric targets exists.
- Flow: Validate the routine template chain → routine payload
  → full effort targets.
- Expected outcome: Valid fixture parses; invalid fixture (missing
  `routineId`) is rejected with the stated reason.
- Edge case of: none

### S-002: Observations-up event is self-contained and idempotent
- Trigger: An observation event is delivered twice.
- Precondition: Valid observations-up fixture (set effort with reps +
  load).
- Flow: Apply once → apply again → compare end state.
- Expected outcome: End state is identical to a single apply. No
  duplicate entries; no error on duplicate delivery.
- Edge case of: S-004

### S-003: Timer state carries timestamps, not remaining time
- Trigger: Engineer reads the rest-timer, round-timer, hold-timer, and
  elapsed-timer message definitions.
- Precondition: All four timer message types have fixtures.
- Flow: Inspect each fixture for the presence of remaining-time
  fields.
- Expected outcome: Only wall-clock timestamps and pause accounting
  fields are present. Validator test asserts no
  `remainingSeconds` / `remainingMs` style field exists in any timer
  fixture.
- Edge case of: none

### S-004: Reconciliation converges after snapshot + divergent events
- Trigger: Watch logs five entries while disconnected; reconnect
  triggers a snapshot-and-replay.
- Precondition: Snapshot fixture + observations-up event stream
  fixture covering the same five entries plus an interleaved
  phone-originated structure change.
- Flow: Apply snapshot → apply each event in order → verify end state.
- Expected outcome: End state matches the expected fixture. Watch
  entries are present. Phone-originated structure change is reflected.
  No duplication; no loss.
- Edge case of: none

### S-005: Phone removes the watch's current exercise
- Trigger: Phone sends a structure-change event removing the exercise
  the watch is currently on.
- Precondition: Live session fixture with at least three exercises;
  watch is positioned on exercise index 1.
- Flow: Apply remove event → watch advances to the next valid
  exercise (index 2 if 1 was removed, otherwise index 1).
- Expected outcome: Watch position reflects the next valid exercise;
  no crash; running timers elsewhere in the session are unaffected.
- Edge case of: S-004

### S-006: Version mismatch behaviour
- Trigger: Watch sends a message with an older protocol version.
- Precondition: Version-mismatch fixture includes both versions and a
  negotiated policy.
- Flow: Receiver reads version → applies policy.
- Expected outcome: Behaviour is documented in the spec (e.g.
  reject-and-resync, accept-and-warn, fall back to snapshot-only).
  Expected end state is part of the fixture.
- Edge case of: none

### S-007: Authority rules are stated normatively
- Trigger: Reviewer reads the spec.
- Precondition: Spec document exists with the authority section.
- Flow: Look for the append-only rule, the structure-ownership rule,
  the next-valid-exercise rule, and the always-accept-watch-events
  rule.
- Expected outcome: Each rule appears in a normative form (MUST /
  MUST NOT / SHOULD), not a descriptive paragraph.
- Edge case of: none

## Iteration 1

### DB Changes

None. This is a specification and fixtures deliverable, not code that
persists data. The fixtures live in the repository as JSON (or
equivalent machine-readable format) under
`watch/sync_protocol/fixtures/`. No schema migration.

### Backend Changes

- Author `watch/sync_protocol/PROTOCOL.md` — the prose specification.
- Author `watch/sync_protocol/fixtures/` — JSON fixtures for every
  message type, valid + invalid.
- Author `watch/sync_protocol/schemas/` — JSON Schema (or equivalent)
  definitions per message type, referenced by tests.
- Add a Dart-side validator (in the Flutter repo) that loads the
  fixtures, asserts each valid fixture parses, asserts each invalid
  fixture is rejected for the stated reason. This becomes the gate the
  phone, watchOS, and Wear OS test suites wire into.
- Add a version-mismatch fixture with documented expected behaviour.

> The watchOS-native validator is owned by the watch item 6 pipeline;
> this item only delivers the spec, the fixtures, and the Dart
> validator. The watchOS-native validator must consume the same JSON
> fixtures so that "the spec is the contract" holds across all three
> codebases.

### Frontend Changes

None. This item produces documentation and fixtures; no UI.

### Implementation Steps

1. Define the message families and their schemas (JSON Schema or
   equivalent). Pin to a v1 protocol version.
2. Encode the authority rules in normative prose.
3. Author one valid fixture per message family and at least one
   invalid fixture per message family, each with a stated rejection
   reason.
4. Author reconciliation, duplicate-delivery, and version-mismatch
   fixtures.
5. Implement the Dart validator that loads fixtures and asserts
   pass / fail / rejection reasons.
6. Verify the validator by running it in CI.
7. Document how the watchOS-native and Wear OS clients consume the
   same fixtures (this is enforced in their respective items).

## Unit Tests Required

- `test/sync_protocol_fixtures_test.dart` — every valid fixture parses
  through the schema validator.
- `test/sync_protocol_fixtures_test.dart` — every invalid fixture is
  rejected by the validator for its documented reason.
- `test/sync_protocol_fixtures_test.dart` — reconciliation test driven
  purely by fixtures: snapshot + event stream → expected end state.
- `test/sync_protocol_fixtures_test.dart` — duplicate-delivery test:
  applying the same observations-up fixture twice yields an identical
  end state.
- `test/sync_protocol_fixtures_test.dart` — version-mismatch fixture
  produces the documented end state under the documented policy.
- `test/sync_protocol_fixtures_test.dart` — timer-state validator
  asserts no remaining-time field appears in any timer fixture.
- These fixture tests become shared gatekeepers — items 6–12 must
  wire the same fixtures into their own suites.

## Progress

- [x] TDD: tests authored, red run recorded. `flutter test
      test/sync_protocol_fixtures_test.dart` failed to compile
      (`Undefined name 'SyncProtocolValidator'`) before the validator
      existed; once it landed, the invalid-fixture assertion for
      `timer_state_remaining_seconds` stayed red until `oneOf` branch
      failures were surfaced instead of collapsing into
      `no_matching_variant`. Red run recorded 2026-09-20. A
      mutation check (forcing the current-exercise fallback index to 0)
      turned S-005 red and nothing else, proving the scenario test is
      load-bearing.
- [x] Phase 1 — Data Layer (N/A — fixtures only)
- [x] Phase 2 — Logic & UI. Validator (`lib/core/sync_protocol/message_validator.dart`),
      reference reconciler (`lib/core/sync_protocol/session_reconciler.dart`),
      8 schema documents, 26 fixtures + manifest, `watch/sync_protocol/PROTOCOL.md`.
      CI gate is the standing `flutter test` run (`scripts/pre_release_check.sh`
      §12–13); no separate workflow was added — test-running CI is not
      a Developer-owned artefact. No watchOS/Wear OS validator in this
      item, per plan (`item 6` owns it).
- [x] Review pass (2026-09-20, addressing code review). Added session-level
      exercise identity: a slot (`sessionExerciseId`) addresses an exercise
      for the life of the session, so the same catalog exercise may occupy
      two slots — matching how the app models a session (efforts per
      segment, `lib/state/workout/session_core_entry.dart`). Broadened
      coverage to 34 conformance cases over 26 fixtures (7 valid, 10 invalid,
      9 reconciliation): every structure-change kind, the timer-clear path, the
      snapshot-merge path, the repeated-exercise case, and a duplicate-slot
      invalid fixture. Every reconciliation fixture is now replayed as a gate.
      The four behavioural guards — swap preserving the slot id, snapshot
      merging entries, timer clearing, and slot uniqueness — were
      mutation-checked, each caught by exactly the fixture written for it.
      Lifecycle coverage is partial: `abandoned` and the position clamp are
      load-bearing, while `started` and `completed` are unobservable in
      `reconciliation/lifecycle_transitions.json` (pruning either leaves the
      suite green) — see the code-review finding.
- [x] Review pass 2 (2026-09-20, addressing code review). Added the
      slot-introduction guard: a re-delivered `exercise_push` or `add_exercise`
      naming a slot that already exists is now ignored, so slot ids stay unique
      across incremental messages and `_reorderExercises` cannot silently drop
      one (fixture `reconciliation/duplicate_slot_add.json`). Split lifecycle
      coverage into per-status fixtures (`lifecycle_started.json`,
      `lifecycle_completed.json`) so all four states are observable; all eight
      guards now fail the suite when pruned, verified by mutation. 36
      conformance cases over 29 fixtures (7 valid, 10 invalid, 12
      reconciliation). Spec gains the duplicate-slot rule and the
      lifecycle-ordering rule, and the S-007 assertions read the spec with
      whitespace collapsed so rewrapping prose is not mistaken for a protocol
      change.
- [ ] Phase 3 — Code Review
- [ ] Release-ready (gates all watch code)

## Feedback

_(empty — fold contents into a new `## Iteration N` block if blocked.)_

### Phase 0 Complete ✓

### Phase 2 Complete ✓

Implementation done. All Phase 0 tests green. Ready for Code Reviewer.
