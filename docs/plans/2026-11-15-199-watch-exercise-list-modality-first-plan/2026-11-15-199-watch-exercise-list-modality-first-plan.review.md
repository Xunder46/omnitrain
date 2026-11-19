# Review: 199 watch exercise lists · P1–P4 · b6febc93..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 4 · tests: (lead's run, not re-run here: full Flutter suite 7684 pass / 4 skipped / 0 fail; swift test 1515 / 0 fail)
Diff vs Predicted Files: conforms, outside: `test/watch_transport_test.dart`, `test/watch_sync_changed_only_test.dart` (batch-count updates forced by D-19916; see finding 3). The `docs/plans/2026-11-13-157-*` files in the stat are another session's work, out of this review.

## Findings
1. [Minor] watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift:1253-1295 (`testS19912TheLetterGridAndItsSymbolsAreGone`) — the deleted-symbol walk covers only `Fixtures.sourcesRoot` (`watch/watchos/Sources/WatchSessionEngine`), while scenario S-19912 says the names occur "in no file the watch or the phone compiles"; `ios/OmniTrain Watch App` is never walked. Verified this run that the ios watch app has no occurrences today, so nothing is wrong now — the guard just would not catch a reintroduction there. Fix: extend the walk to the ios watch-app directory (or scope the scenario wording to the watch package). Guard: the same test walking the ios dir.
2. [Minor] WatchMenuTests.swift:1209-1228 and :1232-1249 — the interim P1 tests `testS19907TheAddExerciseListIsOneUntitledGroup` and `testS19909NoModalityIsOneUntitledGroupAndAnEmptyListHasNone` keep "until P3" reasons now that P3 has landed, and the first re-asserts the no-modality rule under S-19907's id while the plan's S-19907 is the Recommended/Other split (asserted by `testS19907TheModalityListSplitsIntoRecommendedThenOther` at :1307). A reader mapping ids to scenarios finds two S-19907 tests with different behaviour. Fix: delete the interim S-19907 test and move its valuable empty-list arm (:1245-1249) into `testS19909NoModalityIsOneUntitledGroupEvenWhenExercisesCarryKeys`. Guard: none needed (coverage-preserving cleanup).
3. [Minor] test/watch_transport_test.dart, test/watch_sync_changed_only_test.dart — both changed (batch-count lists 100→50) although P2b's predicted-files note says "Nothing else may change" and D-19915 explicitly said the transport test stays unchanged. The changes themselves are correct and forced by D-19916; this is a planning gap, not a code error. Fix: none in code; the plan's predicted-file lists should have named them.
4. [Minor] watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift:747-789 — `pendingModalityStart` has exactly two clearers: `cancelIfNothingPicked` on sheet dismiss (WatchStartView.swift:327-331) and `startModalityWorkout` (:788). A phone-pushed session arriving while the tile-picker sheet is open removes WatchStartView from the hierarchy (ios/OmniTrain Watch App/ContentView.swift:539-557 shows it only when no session or an empty session); if SwiftUI does not fire onDismiss on that teardown, the pending tile (e.g. `cardio_endurance`) survives and every Add Exercise during the pushed session ranks by the stale tile, because `listModality` (:762-767) prefers pending over the session modality. Speculative on SwiftUI onDismiss semantics (not determinable from code). Fix: clear `pendingModalityStart` when a session with exercises becomes active (e.g. in the push-apply path). Guard: a WatchSessionStartPathsTests case that begins a modality start, activates a pushed session with exercises, and asserts `listModality` returns the session modality.

Note (not counted, pre-existing plan-176 corner the diff exposes): plan Input-reality item 7 claims "the picker over a session is never a start-mode pick: `startModality == nil`", but over an EMPTY active session the Start surface is still shown, a tile can be tapped, pending gets set, and the pick is refused by the one-session rule (WatchSessionEngine.swift:375-379) — the refusal is safe, the plan's stated claim is too broad. Reword in the plan or add the guard.

## Assumption Log rulings
- Owner defaults (group titles "Recommended"/"Other", letter headers removed, the session modality ranks Add Exercise): RATIFY — implemented and pinned by S-19907/S-19908/S-19911/S-19913 tests.
- The Dart twin view class `WatchCatalogExercise` (lib/watch/start/watch_routine_catalog.dart) gains no `recommendedFor` field (deviation from P2b item 6 / D-19914): RATIFY — checked this run: the record stores `fallbackExercises` as raw maps and re-emits verbatim (lib/watch/session/watch_records.dart:688-768), so the field round-trips through storage; the twin view class is a read view whose `toSlot`/`toJson` intentionally never carry the field (D-19904). The twin's down-message builders were not re-read this run; the lead's green twin tests cover them.
- `structure_change` carries the field implicitly, no dedicated fixture: RATIFY — verified structure_change.schema.json:99 `$ref`s `envelope.schema.json#/$defs/catalogExercise`, so the additive optional field rides it; the fixtures walk covers the shape.
- Suite name for S-19906 assumed as the plan-75 file: RESOLVED — `watch/watchos/Tests/WatchSessionEngineTests/WatchHealthActivityTests.swift`, carrying the four `testS19906*` tests.
- Items left "owner to confirm" (titles shown only when both groups are non-empty; the `WatchExerciseGroupList` rename): ESCALATE to owner — both are implemented and tested; owner sign-off still pending.

## Docs delta
- watch_reference_data.md letter-grid paragraph → grid removed, "has no letter grid" sentence -> applied
- watch-app-qa-wrist-logging.md step 14 letter-jump wording -> applied
- watch_surface_wrist.md "so a letter jump lands on a measured row" -> applied
- watch_reference_data.md `recommendedFor` sections added -> applied
- watch_reference_data.md `deriveExerciseSections` removed -> applied
- watch_reference_data.md `deriveExerciseListLetters` removed -> applied
- watch_surface_wrist.md `WatchExerciseLetterList` → `WatchExerciseGroupList` -> applied
- watch_surface_wrist.md "sections are walked by position" removed -> applied
- watch-app-qa-wrist-logging.md "the grid is its first row, then" removed -> applied
- watch-app-qa-wrist-logging.md "The letters and" removed -> applied
- watch_reference_data.md grouping paragraph added -> applied
- reference_data.md batch size 100 → 50 (batch sentence) -> applied
- reference_data.md batch size 100 → 50 (second sentence) -> applied
No doc edit the table does not name. Every behaviour sentence names a test that exists (checked against the test files in this diff, including `testS19909NoModalityIsOneUntitledGroupEvenWhenExercisesCarryKeys` at WatchMenuTests.swift:1370 and the S-19902 tests inside the `S-3844 the exercise list version` group at watch_reference_sync_test.dart:703-803).

## Scenario coverage
S-19901 -> test/watch_health_activity_test.dart · S-19901 group tests | COVERED
S-19902 -> test/watch_reference_sync_test.dart · three S-19902 tests in the S-3844 group | COVERED
S-19903 -> test/watch_health_activity_test.dart · S-19903 tests | COVERED
S-19904 -> sync_protocol fixture walk, both stacks · valid/exercises_down_recommended_for.json | COVERED
S-19905 -> fixture walk · invalid/exercises_down_unknown_recommended_for.json, invalid/exercises_down_recommended_for_empty.json | COVERED
S-19906 -> WatchHealthActivityTests.swift · 4 testS19906* tests | COVERED
S-19907 -> WatchMenuTests.swift:1307 testS19907TheModalityListSplitsIntoRecommendedThenOther | COVERED
S-19908 -> WatchMenuTests.swift:1348 testS19908OneNonEmptyGroupIsOneUntitledGroup | COVERED
S-19909 -> WatchMenuTests.swift:1370 testS19909NoModalityIsOneUntitledGroupEvenWhenExercisesCarryKeys (empty-list arm at :1245-1249) | COVERED
S-19910 -> WatchSessionStartPathsTests.swift · testS19910ARecentBorrowsTheSyncedListRecommendation | COVERED
S-19911 -> WatchSessionStartPathsTests.swift · testS19911ListModalityFollowsThePendingStartThenTheSession | COVERED
S-19912 -> WatchMenuTests.swift:1253 testS19912TheLetterGridAndItsSymbolsAreGone | COVERED (ios-dir gap: finding 1)
S-19913 -> WatchMenuTests.swift:1461 testS19913BothEntryPointsGroupWithTheRealModality | COVERED
S-19914 -> WatchSessionStartPathsTests.swift · testS19914AStoredRecommendedForFrameGroupsTheList | COVERED
S-19915 -> fixture walk (both stacks) + storage verbatim re-emit; the twin view class carries no field per ratified deviation | COVERED with deviation
S-19916 -> test/watch_sync_request_handler_test.dart · S-19916 stale-version test | COVERED
S-19917 -> WatchMenuTests.swift:1390 testS19917AnUnknownRecommendationIsKeptAndIsOther | COVERED
S-19918 -> WatchMenuTests.swift:1411 testS19918ARepeatedKeyMatchesOnceAndAppearsOnce | COVERED
S-19919 -> WatchMenuTests.swift:1431 testS19919AnEmptyNameKeepsItsInputPositionWithinItsGroup | COVERED
S-19920 -> WatchMenuTests.swift:1490 testS19920TheTitledGroupsAreHeadersAndTheUntitledAddsNone | COVERED
S-19921 -> test/watch_reference_sync_test.dart · S-3858/S-19306 batch tests recomputed for 50 + byte-budget guard retained | COVERED
