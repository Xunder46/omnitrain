# Plan 312 — The Wear wrist keeps the phone's exercise list and the picker shows it (series 310-314) — OUTLINE, not yet seeded for building

Status: outline, scouted (2026-11-22: the sheet is summarised under "Scout findings"; seed from it, then split into 312a store + apply + router and 312b picker if the seed passes about 300 lines). Plan 314 (modality start grid) depends on this plan: its modality-first list reads the `recommendedFor` the phone sends here.

## What the review found

The phone builds the wrist's whole exercise list as `exercises_down` batches (`lib/core/utils/watch_reference_sync.dart` 319-369, plan 23e, each exercise carrying a `recommendedFor` list since plan 199). The Apple wrist applies them (`WatchStartPaths.swift` `applyExercisesDown` 566-700, `WatchExerciseBatchResult` 266, `WatchRoutineRecords.swift`, `activeExercisesVersion`, batches of 50, `derivePickerRows` 226 and `pickerRows` 865) and its picker reads that list. The Wear wrist's message router has no case for `exercises_down` (`lib/watch/start/watch_sync_orchestrator.dart` 160-197: it falls to `default: return false`), so the batches are dropped, and its picker only shows `paths.fallbackExercises`, i.e. the exercises of synced routines (`lib/watch/start/watch_exercise_picker.dart` line 52). A Wear user can only add an exercise that belongs to a routine, or one the phone pushes with `exercise_push`.

## Goal (draft)

The Wear wrist stores the phone's exercise batches the way the Apple wrist does (newest version wins, a version is used only once all its batches have arrived, survives a restart) and its picker lists them (alphabetical in the phone's order, recently used and routine exercises as the Apple picker orders them), with the existing "Search on phone" hint kept. No change to the phone.

## Decisions to take when seeding (technical, mine)

- New stored record type for an exercise batch in the Dart store (both `InMemoryWatchSessionStore` and `HiveWatchSessionStore`, tests under Mock AND Hive), the validator already knows `exercises_down` (`watch/sync_protocol/schemas/messages/exercises_down.schema.json`).
- Port `applyExercisesDown` and its rules (version switch, duplicate batch, complete-set rule, prune of superseded versions) and `derivePickerRows`; the existing fallback list stays for the offline-with-nothing-synced case.
- Seed the concurrent-message interleaving test (a batch arriving while a pick is in flight), per the crew rules for handlers frames can reach concurrently.
- Picker UI at 192/227 dp: a long list needs the compact row size; measure with a probe.
- Out of scope: the modality-first ordering (plan 314), the planned workout (plan 313).

## Owner questions

None expected: matches Apple.

## Scout findings (2026-11-22, spot-checked against the files)

- Apple rules, in order (`WatchStartPaths.swift` `applyExercisesDown` ~570-631): validate; a batch older than the active list is dropped; a batch whose `batchCount`/`totalCount` disagree with a stored row of the same version refuses the whole batch; append (idempotent: record id `exb-<catalogVersion>-<batchIndex>`), then re-read AFTER the append (two batches of one version can interleave at the awaits); activate only when the version differs from the active one, is not older, and is complete (every index `0..<batchCount` present and the counts summing to `totalCount`); then prune batches of other versions. Restart: the complete version with the greatest `generatedAt`. The phone sends batches of at most 100 (the Apple record's own comment; the first outline said 50).
- Picker order (`derivePickerRows`): the session's own ladder first, then every addable exercise minus those already on the ladder; the addable list is A-to-Z by lowercase name with the id as the tie-break (`addableExercises`); a malformed slot is skipped.
- Dart touch points for a new record type `exercise_batch`: the `WatchRecord.fromJson` switch (`watch_records.dart` ~192-196), a record class copying `WatchRoutineCatalogRecord` (empty `sessionId`), `WatchStoreContents` + the `readAll` switch in BOTH `hive_watch_session_store.dart` (also the `_allRows` type list ~176-193, which is silently skipped if missed) and `in_memory_watch_session_store.dart`, a prune call (the Dart store interface has none yet), `WatchSessionStartPaths.restore`/a new `applyExercisesDown`, one new `case 'exercises_down'` in `watch_sync_orchestrator.dart` `receive`.
- `WatchCatalogExercise` (`watch_routine_catalog.dart` ~23) has no `recommendedFor`; the batch rows carry it (phone: `watch_reference_sync.dart` 312-313). 312 keeps the field so plan 314 can order by modality.
- Dart tests to extend: `test/watch_session_start_test.dart`, `test/watch_transport_test.dart`, `test/wear_menu_screen_test.dart` (picker, lines ~851-918), `test/wear_start_screen_compact_test.dart` (~150); a Hive+Mock store round trip for the new type is new (no Wear store test names it).
- Scenario to seed (crew rules): two batches of one version arriving across an `await` (the Apple S-3836 interleaving), run through a suspending store.
