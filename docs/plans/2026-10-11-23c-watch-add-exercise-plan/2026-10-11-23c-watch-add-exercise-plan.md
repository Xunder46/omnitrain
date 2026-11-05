# Plan 23c: Add Exercise on the watch, from the phone's whole exercise list

Base: HEAD after 23b. Governor-seeded. Owner QA item 8 (2026-10-11): "a new button Add Exercise above End Session;
it opens a list of all exercises alphabetically; on select it appends the exercise to the end of the list; a back
button too." Owner confirmed: yes to the button in the menu, and the free-workout picker stays as it is.
Plan 20b had removed Add exercise from the menu because the wrist only knows the exercises of the user's routines
and recent sessions (`deriveFallbackExercises`, `WatchStartPaths.swift:114`); the whole list has to reach the wrist.

## Goal and acceptance (what the owner sees)

1. After a Sync, the watch holds every exercise the phone has (custom ones too), even for a user with no routines.
2. The session menu shows **Add Exercise** above **End Session** (End Session keeps its divider). Tapping it opens
   a list titled "Add Exercise", all exercises A to Z (case-insensitive), with the system back button.
3. Tapping an exercise adds it at the END of the session's list and returns to the menu, where the new row is
   last (no count yet). The exercise being logged does not change. The phone's open session shows the new exercise
   (plan 23b already makes the open screen follow the watch). Tapping the same exercise twice adds two slots (a superset).
4. The free-workout start picker keeps its own order (recents first); it now simply has more exercises behind it.
5. Works with the phone out of reach once the list has synced (the list lives on the watch).

## Decision ledger

- D-3601 Wire: widen, do not add a message. `routines_down.payload.fallbackExercises` carries EVERY phone exercise
  that has at least one capability (the `catalogExercise` shape: exerciseId, name, capabilities, optional
  roundDurationSecs; `watch/sync_protocol/schemas/envelope.schema.json:67`), not only the routines' exercises; and
  `routines` may be empty: `routines_down.schema.json:21-24` `"routines": {"type":"array","minItems":1,...}` becomes
  minItems 0. `fallbackExercises` stays minItems 1. The coverage rule (every routine exercise is listed) is unchanged
  (`SyncProtocolValidator.swift:~517 fallbackCoverageRejections`, Dart `message_validator.dart:297`).
  Why not foods-style `exercises_down`: a second message needs its own request, store record, parser on two stacks and a
  PROTOCOL section; the existing message, request and store row already carry this shape.
- D-3602 No protocol version bump: the change relaxes a minimum and widens a list; no legacy handling (single release).
- D-3603 Phone sender: `WatchReferenceSync.buildRoutinesDown` (`lib/core/utils/watch_reference_sync.dart:98`) currently
  returns null when `routines.isEmpty` (line ~132) and builds `fallbackExercises` from `referenced` only (`_fallbackJson`).
  New rule: fallbackExercises = all `repository.getExercises()` with non-empty capabilities (via `_ExerciseResolver.resolve`),
  sorted by name for a stable payload; returns null only when there is no exercise to offer. `generatedAt` handling unchanged.
  The sender of that message (`lib/state/watch/watch_sync_request_handler.dart`, `watch_reference_sync` callers) must
  still be asked on the Sync button only (no new triggers).
- D-3604 Size check: the encoded `routines_down` for the seed catalog (~250 exercises) is measured in a test and recorded in
  the evidence; if the phone's transport has a frame size ceiling (look at `lib/core/utils/platform_watch_transport_factory.dart`
  and the iOS channel), report it as a blocker rather than splitting silently.
- D-3605 Wrist model: add to `WatchSessionStartPaths` (`WatchStartPaths.swift`): `addableExercises` = `fallbackExercises` sorted
  case-insensitively by name (ties by exerciseId) and `addExerciseToEnd(_:)` = `engine.insertExercise(slot, atIndex: nil, moveTo: false)`
  with the slot id from `availableSlotId(for:)` (`:420`). Check `insertExercise`'s `atIndex: nil` means append and `moveTo: false`
  keeps the current exercise; the engine's existing ladder-change announcement (plan 17b) carries the new slot to the phone.
  The menu state `WatchMenuState` (`WatchMenu.swift`) exposes `addableExercises` and `addExercise(_:)`; no new engine path, no new ids
  minted outside `availableSlotId`.
- D-3607 Menu lock: Add Exercise stays available while a work clock runs (it moves nothing); only the exercise rows are inert.
- D-3608 UI: `WatchMenuView` gets an `Add Exercise` button above the divider+End Session; tapping pushes a list inside the menu's own
  `NavigationStack` (`NavigationLink` or `navigationDestination`) with the system back button; a row tap adds, then pops back.
  Empty list text: "No exercises yet. Sync with your phone." Copy lives in `WatchMenuCopy` (testable).
- D-3609 The Wear/Dart client (`lib/watch`) changes only enough to parse `routines: []` (shared fixtures stay green); it gets no menu.
  Plan 20b's docs sentence "Exercises are added on the phone" is replaced.

## Scenarios (tests first; each must fail without the change)

Contract (both stacks run the same fixtures: `watch/sync_protocol/fixtures/`, `test/sync_protocol_fixtures_test.dart`,
`SyncProtocolFixturesTests.swift`):
- S-3601 valid fixture `routines_down_catalog_only.json`: `routines: []`, three exercises in `fallbackExercises` -> valid on Dart and Swift.
- S-3602 invalid fixture: `routines` non-empty naming an exercise absent from `fallbackExercises` -> still rejected (coverage rule).
- S-3603 invalid fixture: `fallbackExercises: []` -> rejected (still minItems 1).
Phone:
- S-3604 `buildRoutinesDown` with no templates and three exercises (one custom, one without capabilities) returns a message whose
  `routines` is `[]` and whose `fallbackExercises` has the two capable exercises, sorted by name, and it passes the validator.
- S-3605 with one routine, `fallbackExercises` still contains every routine exercise AND the other exercises; no duplicates.
- S-3606 with no exercises at all -> null.
- S-3607 the encoded message for the seeded catalog: record its byte length in the test output and assert it is under 200 KB.
Wrist (Swift):
- S-3610 a stored catalog with `routines: []` restores (`WatchSessionStartPaths.restore`) and `addableExercises` lists it.
- S-3611 order: names "apple", "Banana", "cherry", "Apple Pie" -> apple, Apple Pie, Banana, cherry.
- S-3612 `addExerciseToEnd` on a 2-slot session leaves 3 slots, the new one last, `currentExerciseIndex` unchanged.
- S-3613 adding the same exercise twice gives distinct `sessionExerciseId`s (`availableSlotId`).
- S-3614 the engine announces the ladder change (the frame the phone adopts a wrist-added slot from): assert through the
  existing emitted-frame helper that a `session_snapshot` (or the existing equivalent) with the new slot is emitted.
- S-3615 `WatchMenuState.addExercise` works while a work clock runs (`isLocked == true`); jumping still refused.
- S-3616 `WatchMenuCopy.addExerciseLabel == "Add Exercise"`, empty text as in D-3608.

## Phases (serial: C1, C2, C3)

| # | Agent | Scope | Items |
|---|---|---|---|
| C1 | crew-builder-watch | `watch/sync_protocol/**`, `watch/contract/**`, `watch/watchos/**`, `lib/watch/**`, `test/sync_protocol_fixtures_test.dart`, `test/watch_*`, `docs/**` | D-3601/3602 schema + both validators + both parsers accept empty routines, fixtures S-3601..3603, PROTOCOL.md amendment |
| C2 | crew-builder-app | `lib/core/**`, `lib/state/watch/**`, `test/watch_*`, `test/helpers/**`, `docs/**` | D-3603/3604 phone sender, S-3604..3607 |
| C3 | crew-builder-watch | `watch/watchos/**`, `docs/**` | D-3605..3608 model + view, S-3610..3616, QA steps (owner), docs |

## Verification (governor, observed)
swift test, flutter test, flutter analyze (196), xcodebuild watch scheme, mutations (drop the coverage of non-routine exercises;
remove sorting; `moveTo: true`; lock Add while running). (owner) Real devices: Sync, then on the watch Menu > Add Exercise > pick one:
it appears last in the menu and on the phone's open session; the free-workout picker still works.
