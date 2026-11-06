# Feature: 125a — contract accepts a routine's Focus; the phone links and labels an imported wrist routine

> Status: DRAFT, Iteration 1 ready. Parent: `2026-11-05-125-wrist-routine-focus-modality-plan.md` (INDEX, read first for evidence and Q1-Q3).
> Next handoff: crew-builder-app (Phase 0: red tests)
> Track: contract (`watch/sync_protocol/`, `watch/contract/`) + phone (`lib/`). No Swift view or engine file. Does NOT touch `lib/state/watch/watch_timer_push.dart` or `watch_sync_wiring.dart` (121a owns them).
> Depends on: plan 122 for the phone-side stamping rule (same rule, D-125-4); if 122 has not landed, 125a still builds (it reads `template.focusModality` itself).
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md` (Versioning policy, Validation profiles), `docs/documentation_standard.md`, `.github/copilot/pr-scope-budget.md`.
> Evidence → `…125a….evidence.md`; review → `…125a….review.md` (beside this file).

## Overview

Two independent gains, one PR because the first is the contract the second's sibling (125b) needs:
1. **Contract.** `routines_down` routines MAY carry `focusModality`. Both validators, the shared contract
   file and the Dart wrist copy accept and keep it. **The phone does not emit it in this PR** (D-125-2).
2. **Importer.** A wrist routine session the phone never adopted (phone away) is saved as the routine it
   was: `intent:'routine'`, `routineTemplateId`, title, and the routine's Focus as `modality` when the
   wrist sent none. Today it is saved as a nameless "Free Training" (INDEX evidence c2).

## Resolved Decisions (Ledger)

- **D-125-1 Wire shape.** `routines_down` `$defs.routine` gains optional `focusModality`:
  `{"type":"string","minLength":1}`, same style as `session_end.modality` (`envelope.schema.json:296`).
  No enum: the schema does not enumerate modalities elsewhere, and the phone has older keys
  (`strength_resistance` …) the wrist table also lists. `required` is unchanged. Omitted when the routine
  has no Focus (never `null`, never `""`).
- **D-125-2 Versioning and back-compat.** Amend v1 additively with a `## Version history` row, same
  grounds as the 40 earlier amendments; no `protocolVersion` bump (the policy bumps for incompatible
  messages, and no existing fixture changes). **Known cost:** the strict profile rejects an unknown field
  (`SyncProtocolValidator.swift:837-841`), so an old watch would drop a whole `routines_down` that carries
  it. Therefore 125a **adds the field to the schema but the phone's `buildRoutinesDown` does not write
  it**; 125b turns the sender on in the same PR that teaches the watch to read it (INDEX Q1). A new watch
  with an old phone just sees no field.
- **D-125-3 Importer routine match.** Extract the slot-id decoder and the template search from
  `WatchSessionAdoptionBridge._routineFor` (`watch_session_adoption_bridge.dart:873-915`) into a small
  core service `WatchRoutineMatcher` (`lib/core/services/watch_routine_matcher.dart`, depends on
  `WorkoutRepository` only). Input: the session's slot ids. Rule unchanged: each id must start with
  `sx-`, effort id = text before the LAST `~`, a template matches when every decoded effort id is one of
  its own efforts; no slots, a malformed id, or no match → null. The bridge calls the matcher and keeps
  its targets lookup (a pure move; behaviour pinned by the existing bridge tests). The importer calls it
  with the slot ids of the rows it is importing (`_Key.sessionExerciseId`, `watch_session_importer.dart:1969`).
- **D-125-4 What the importer writes.** In `_createSession` (`:579-592`), when the matcher returns a
  template: `title = template.name`, `intent = 'routine'`, `routineTemplateId = template.id`, and
  `modality = end.modality ?? template.focusModality` (wrist value wins; copied verbatim; null stays
  null). The same stamp-at-write snapshot rule as 122 D-12202: editing the Focus later never rewrites.
  An existing session (adopted earlier, or imported earlier) is NEVER updated by the importer for these
  fields: this is create-only, so the adoption bridge's row is untouched.
- **D-125-5 No planned rows.** Unlike adoption, the importer does not create `PlannedSession` or planned
  set rows; the session is over, only its identity changes.
- **D-125-6 Dart wrist copy.** `lib/watch/start/watch_routine_catalog.dart` (and `lib/watch/session/watch_records.dart`
  routine row, if routines are stored there) parse and keep an optional `focusModality`; `startFromRoutine`
  in `watch_session_start_paths.dart` is **not** changed here (125b). The Swift `WatchRoutine` parse of the
  new key is also read-only here: it stores the value, `startFromRoutine` still passes `modality: nil`.
  If keeping it in Swift needs more than the one property and one parse line, leave Swift entirely to 125b.
- **D-125-7 Docs.** `PROTOCOL.md` history row; `docs/watch_session_sync.md` (routines_down field list);
  `docs/data_models.md` only if the importer section lists written fields. Size ceiling 64 KiB per doc
  (`test/docs_indexing_contract_test.dart`); if a doc is near it, add to a part page, not the index.

## Scenarios

| ID | Scenario | Expected |
|---|---|---|
| S-12510 | `routines_down` routine with `focusModality:"isometric_stretching"` | valid in the Dart validator and the watchOS suite (new fixture `valid/routines_down_focus_modality.json`, registered in `manifest.json`) |
| S-12511 | `focusModality:""` | invalid, `invalid/routines_down_empty_focus_modality.json`, rejection at `$.payload.routines[0].focusModality` (minLength) |
| S-12512 | `focusModality:null` / wrong type (number) | invalid (type) |
| S-12513 | Existing `routines_down*.json` fixtures (no field) | unchanged and still valid (old phone → new watch) |
| S-12514 | `buildRoutinesDown` for a routine WITH a Focus | message has NO `focusModality` key (pins D-125-2; 125b flips this test) |
| S-12515 | Importer: wrist session, slot ids `sx-<effortId>~<token>` for all efforts of routine R (Focus = X), `end.modality` absent, no row exists | session saved with `intent 'routine'`, `routineTemplateId R`, title R's name, `modality X` |
| S-12516 | Same, `end.modality = 'sports'` | `modality 'sports'` (wrist wins), routine still linked |
| S-12517 | Same, R has no Focus | linked, `modality` null (Free Training label, routine name kept) |
| S-12518 | Routine R deleted on the phone before the import | no match; saved exactly as today (free, no title); no throw |
| S-12519 | Slot ids of a free workout (`sx-<exerciseId>` picks) | no match unless every id equals some template effort id; assert a free workout never links (the real exercise ids are not effort ids) |
| S-12520 | Routine edited after the wrist started (effort ids replaced) | no match, free |
| S-12521 | Round trip: wrist routine, phone adopts mid-session (bridge links R), session ends, importer runs | one session row; importer does not overwrite the adopted row's title/intent/routine/modality (create-only) |
| S-12522 | Existing adoption bridge tests (D-1…D-6 of the plan that added them) | still green after the matcher extraction |
| S-12523 | `lib/` import invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty |

## Phases (each independently green; stop at the first red group)

**Phase 0 — red tests (no production code).** Write S-12510..S-12521 as failing tests: validator fixtures
in the existing conformance walkers (manifest-driven, so fixtures need no new test code); importer tests
as plain `test()` with `MockWorkoutRepository` (seed a template + segment + efforts, feed rows). Show
each red.

**Phase 1 — contract.** Schema, two fixtures, `manifest.json` rows (with `scenarios` notes),
`watch_start_paths_contract.json` only if it enumerates routine keys (check; otherwise untouched),
PROTOCOL history row. Run `flutter test` on the conformance suite; `swift test` in `watch/watchos` is a
governor step (known long-running) — list as owed if not run.

**Phase 2 — matcher + importer.** Extract `WatchRoutineMatcher`; bridge uses it (S-12522 green first),
then importer uses it (S-12515..S-12521 green). Importer loads templates once per import pass, not per
row.

**Phase 3 — wrist copies and docs.** D-125-6 (Dart parse, optional Swift one-liner), D-125-7 docs. Run
`flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`.

**Gate:** targeted suites above + the importer, adoption bridge, validator and contract test files; paste
counts. A bug-fix style test for S-12515 must be shown failing with the importer change stashed.

## Files (predicted, ~250 production lines, within budget)

`watch/sync_protocol/schemas/messages/routines_down.schema.json`, `…/fixtures/valid|invalid/*`,
`…/fixtures/manifest.json`, `watch/sync_protocol/PROTOCOL.md`; `lib/core/services/watch_routine_matcher.dart`
(new), `watch_session_importer.dart`, `lib/state/watch/watch_session_adoption_bridge.dart` (matcher call
only); `lib/watch/start/watch_routine_catalog.dart`; docs; tests under `test/`.

## Noticed, not in scope
- The adoption matcher picks the first template whose efforts include all slot ids; it ignores routine id
  because the wire carries none. Carrying `routineId` on the snapshot would be sturdier but is a bigger
  contract change; not proposed.
- A phone-started routine followed on the wrist has no Focus on the wrist either (snapshots carry no
  modality). Out of scope; 125b's wrist can derive it from the routine list if wanted.
- Plan 122 notes picking "Mixed / Not set" may not clear a routine's Focus; the Focus-only edit must also
  bump `updatedAtMs` for 125b's sync to re-send. Verify in 125b.

## Owner device checks (after 125a alone)
1. Start a routine on the watch with the phone app closed or the phone out of range, finish it, then open
   the phone. The workout should appear on the calendar under the routine's name, and show up in that
   routine's history. If the routine has a Focus, the day shows that Focus's colour and name.
2. Same but delete the routine first: workout still appears as Free Training.
3. Nothing changes on the watch itself in this step.
