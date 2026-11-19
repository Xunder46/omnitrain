# Evidence — plan 199 (watch exercise lists, modality-first)

(reserved; the prover fills this after the implementation phases)

## P4 — docs

All 13 rows of the plan's `## Docs delta` were applied to the three docs.
Every new behaviour sentence cites a test read from its test file this run
(2026-11-15); every Old marker was confirmed gone by a grep over `docs/`
outside `docs/plans`.

| Row (doc · change · marker) | Sentence | Test pins read this run |
|---|---|---|
| `watch_reference_data.md` MODIFIED — "has no letter grid" | The Add Exercise list is sorted A to Z and has no letter grid; grid, per-letter headers and symbols removed, pinned gone. | `WatchMenuTests.testS19912TheLetterGridAndItsSymbolsAreGone` (exists), `testS3611TheAddListSortsCaseInsensitivelyByName` (kept) |
| `watch_reference_data.md` REMOVED — "`deriveExerciseSections` reads" | Sentence deleted with the grid sentence; the deleted `testS3105ASectionsFollowTheListAndTheLettersAgree` pin went with it (no match in `watch/watchos/Tests` this run). | — |
| `watch_reference_data.md` REMOVED — "the picker's grid is `deriveExerciseListLetters`" | Grid clause dropped; the row-agreement clause kept with its pin. | `WatchSessionStartPathsTests.testS3113AThePickerRowsAndTheAvailableExercisesAgree` (kept; the deleted `testS3108A…` pin went with the grid clause — no match in the tests) |
| `watch_reference_data.md` ADDED — "recommendedFor" | New subsection "The recommendation rides the list": who computes it, what it rides, how the wrist reads it, why every held version stales once. | `test/watch_health_activity_test.dart` group `S-19901 recommendedFor on the exercise list` (tests `S-19901 the exercise list carries the recommended modalities`, `S-19901 recommendedModalitiesOf, the picker rule as a pure function`, `S-19903 the routine carries it on the fallback exercise, nowhere else`, `S-19903 the session slot never carries the key`); `WatchHealthActivityTests.testS19906…` (4); `WatchSessionStartPathsTests.testS19910ARecentBorrowsTheSyncedListRecommendation`, `testS19914AStoredRecommendedForFrameGroupsTheList`; `test/watch_reference_sync_test.dart` group `S-3844 the exercise list version` (tests `S-19902 a healthActivity-only diff is another version`, `S-19902 a recommendedFor-only diff is another version`); `test/watch_sync_request_handler_test.dart` `S-19916 a version the pre-change phone derived stales the list` |
| `watch_reference_data.md` ADDED — "Recommended group" | New paragraph in "The list the wrist offers offline": the `deriveExerciseGroups` partition, titles only when both non-empty, `listModality`, both entry points. | `WatchMenuTests.testS19907TheModalityListSplitsIntoRecommendedThenOther`, `testS19908OneNonEmptyGroupIsOneUntitledGroup`, `testS19909NoModalityIsOneUntitledGroupEvenWhenExercisesCarryKeys`, `testS19917AnUnknownRecommendationIsKeptAndIsOther`, `testS19918ARepeatedKeyMatchesOnceAndAppearsOnce`, `testS19919AnEmptyNameKeepsItsInputPositionWithinItsGroup`, `testS19920TheTitledGroupsAreHeadersAndTheUntitledAddsNone`, `testS19913BothEntryPointsGroupWithTheRealModality`; `WatchSessionStartPathsTests.testS19911ListModalityFollowsThePendingStartThenTheSession` |
| `watch_reference_data.md` MODIFIED — "in batches of at most 50 exercises, each" | 100 → 50 in "Two messages, two jobs", pin added. | `test/watch_reference_sync_test.dart` group `S-3840..S-3843, S-3845, S-3846 the phone sends the list in batches`, tests `S-3858 the first batch of the seeded catalog stays under the frame budget`, `S-3846 a batch size outside 1..100 is refused` |
| `watch_reference_data.md` MODIFIED — "batches of at most 50," | 100 → 50 in "The phone's sender since 23e2". | same as above |
| `watch_surface_wrist.md` MODIFIED — "Recommended group" | The one-list paragraph now says the list opens with the Recommended group first, headers read as VoiceOver section headers. | `WatchMenuTests.testS3106AOneListServesBothEntryPoints` (kept), `testS19913BothEntryPointsGroupWithTheRealModality`, `testS19920TheTitledGroupsAreHeadersAndTheUntitledAddsNone` |
| `watch_surface_wrist.md` MODIFIED — "render the same `WatchExerciseGroupList`" | Struct name updated; `testS3106A` asserts the new name in its sources (seen this run, `WatchMenuTests.swift:974,985`). | `WatchMenuTests.testS3106AOneListServesBothEntryPoints` |
| `watch_surface_wrist.md` REMOVED — "Within it the sections are walked by position" | Paragraph deleted; `The picker carries no phone hint…` sentence kept. `testS3114A` has no match in the tests this run. | — |
| `watch-app-qa-wrist-logging.md` REMOVED — "Jump to a letter in a long exercise list" | Step 14 replaced in place (number kept, steps 13 and 15 untouched) with `**Recommended exercises first — (owner).**`; the `the grid is its first row, then` and `The letters and` sentences went with the step. | `testS19907…`, `testS19908…`, `testS19909…`, `testS19913…`, `testS19911…`, `testS19912…` |

### Checked and left alone (verified this run)

- `docs/watch-app-setup-and-qa.md:195` — "Add Exercise (which opens an A to Z list of every exercise the phone has sent…)": names no grid, still true. No row needed.
- `docs/state_management/watch_surface_wrist_logging.md:11` — "Add Exercise (an A to Z list of the phone's whole exercise list…)": names no grid, still true. No row needed.
- `docs/state_management/watch_surface.md` — its `exercises_down` batch sentences (:394, :401, :475) state no batch size and no letter grid. No row needed.
- Grep over `docs/` excluding `docs/plans` for letter-grid terms, `WatchExerciseLetterList`, `deriveExerciseSections`, `deriveExerciseListLetters`, `addLetterGridThreshold`, "batches of at most 100", "100 exercises", and version-hash text: no hit outside `docs/plans/` (historical plans, not docs) and the three edited docs. No stale claim found.

