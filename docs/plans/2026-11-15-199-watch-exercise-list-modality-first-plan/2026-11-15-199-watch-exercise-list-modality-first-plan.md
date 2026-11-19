# Feature: 199 — watch exercise lists: no letter strip, the chosen modality's exercises first

> Status: SEEDED by the governor 2026-11-15; the architect expands it. Defaults marked **owner to confirm**.
> Next handoff: crew-architect
> Binding conventions: `docs/global_conventions.md`, `docs/design_system.md` (wrist rules), `docs/state_management/watch_surface_wrist.md`, `docs/state_management/watch_reference_data.md`, `watch/sync_protocol/PROTOCOL.md`, `.github/copilot/pr-scope-budget.md`
> Related plans: 23e1–23e3 (the letter grid being removed), 3 / D-3110 / D-3117 / D-3851 / D-3852 (its decisions), 176 (the modality tiles whose tap opens the picker), 170 (`healthActivity`, the field this one copies), 107–110 (phone Recommended section)

## Goal and acceptance

Two owner decisions, 2026-11-15, after seeing the watch Start screen on a wrist:

1. **Remove the jump-to-letter grid** from the watch's exercise lists — the picker that opens from a
   modality tile (or over a running session) and the session menu's **Add Exercise** list. Owner:
   "too much friction with too little return; it takes a lot of space, always sits on top and may be
   confusing". Both lists become one plain scrolling list.
2. **Recommend by modality.** After tapping Cardio / Resistance / Sports / Isometric the list shows the
   exercises that suit that modality first, alphabetically, then every other exercise alphabetically
   below them. Owner: "recommended by modality first, alphabetically, then the rest alphabetically
   below it".

What a user sees afterwards:

- Tap **Cardio** → the list opens with a small **Recommended** header, Brisk Walk / Running / Rowing …
  (A to Z), then an **Other** header and everything else A to Z. No letter squares at the top.
- Tap **Resistance** → the same, with the lifting exercises first.
- A modality in which nothing is recommended (or every exercise is) shows one plain A-to-Z list, no headers.
- A Free-workout style session with no modality (a plan's own start, the phone's free session) shows one
  plain A-to-Z list. **Add Exercise** in the menu of a running session ranks by that session's modality.
- The per-letter section headers (A, B, C …) are gone with the grid (they were the grid's jump anchors).

Acceptance: the grid and every symbol that only served it are deleted; the phone sends each exercise's
recommended modalities on the wire; the wrist orders by them; an already-synced watch picks the new field
up at its next Sync without anything else changing; Swift (`swift test` in `watch/watchos`), Flutter
(full suite), the sync-protocol fixtures on both stacks, the docs contracts and the watch-target compile
are green with observed counts.

## Decision Ledger

| ID | Decision | Where |
|---|---|---|
| D-19901 | **Owner (2026-11-15): the letter grid is removed from BOTH lists.** Deleted with it: `WatchAddExerciseLetter`, `addExerciseLetterKey(of:)`, `deriveAddExerciseLetters`, `scrollTargetLetters(of:)`, `deriveExerciseListLetters`, `WatchMenuCopy.addLetterGridThreshold`, `WatchMenuCopy.addLetterJumpLabel`, `WatchMenuState.addExerciseLetters`, the `letters:` parameter and `letterGrid(_:)`/`ScrollViewReader` in the list view, and the tests that pin them. | `WatchMenu.swift`, `WatchExerciseListView.swift`, `WatchMenuView.swift`, `WatchStartView.swift` |
| D-19902 | **Per-letter section headers are removed too (owner to confirm).** Their only job beyond the grid was a visual break; on a 40 mm wrist a header per letter adds ~26 rows to a long list. The list is made of at most two **groups** (D-19905). `WatchExerciseSection(letter:)` becomes `WatchExerciseGroup(title:)`. | `WatchMenu.swift` |
| D-19903 | **"Recommended" is the phone's own rule, computed on the phone.** The phone's exercise picker already splits Recommended / Other with `ModalityConfig.isRecommended` (score ≥ `RECOMMENDED_SCORE_THRESHOLD` 50, from capabilities + the discipline's category: `lib/core/constants/modality_config.dart:332`, used by `exercise_picker_screen.dart`). The watch must not re-implement that scoring: the phone computes, per exercise, the list of the four primary modalities (`Modality.primaryHomeTiles`) for which it is recommended and sends it. So the wrist's "Recommended" and the phone's "Recommended" are the same set by construction. | `lib/core/utils/watch_reference_sync.dart` |
| D-19904 | **Wire: an additive optional `recommendedFor` on `catalogExercise`** — an array of 1–4 strings (`minItems` 1, `maxItems` 4; the validators' dialect has no `uniqueItems`, so the phone simply sends each key once), enum `cardio_endurance`, `resistance_lifting`, `isometric_stretching`, `sports`; omitted when the exercise is recommended for none. `catalogExercise` is closed, so `envelope.schema.json#/$defs/catalogExercise` declares it; it rides `exercises_down` batches and `routines_down.fallbackExercises` (both reference `catalogExercise`); the routine `effort` and the session `sessionExercise` slot do NOT carry it. No version change, no new message family — only what is accepted widens (same pattern as `healthActivity`, plan 75/170). PROTOCOL.md gets an amendment row dated 2026-11-15. | `watch/sync_protocol/schemas/envelope.schema.json`, `PROTOCOL.md`, fixtures, `manifest.json` |
| D-19905 | **Wrist grouping rule.** A pure function over the already-A-to-Z list (`addableExercises`, which sorts by lowercased name, id tiebreak): with a modality `m`, a stable partition into **Recommended** (`recommendedFor` contains `m`) then **Other**, each keeping the A-to-Z order; titles `Recommended` / `Other` (the phone's own words) shown ONLY when both groups are non-empty; one non-empty group, or no modality, is one group with `title == nil`. Unknown keys in `recommendedFor` are kept but never match. | `WatchMenu.swift` (`deriveExerciseGroups`) |
| D-19906 | **Which modality ranks the list (owner to confirm).** The picker opened from a tile: the tile's modality (`WatchSessionStartPaths.pendingModalityStart`). The picker or **Add Exercise** opened over a running session: that session's `modality` (`WatchSessionRecord.modality`, `WatchRecords.swift:211`). No modality → one plain A–Z list. One accessor, `listModality`, serves both. | `WatchStartPaths.swift`, `WatchMenu.swift` |
| D-19907 | **An exercise's own recommendation comes from the synced entry.** `deriveFallbackExercises` keeps the FIRST mention of an id and puts the wrist's recents first, and a recent (stored before this change, or from a slot) carries no `recommendedFor`. The grouping reads `recommendedFor` from the synced list (`activeExercises` + `catalogFallback`) by exercise id, falling back to the entry's own value; a recent the sync does not know is Other. | `WatchStartPaths.swift` (`syncedFallback`, `fallbackExercises`) |
| D-19908 | **An already-synced watch must receive the field.** `WatchReferenceSync.exercisesVersionOf` hashes only `id|name|capabilities|roundDurationSecs`, so a catalog change that touches nothing else keeps the version and the phone then sends NO batches to a wrist that names it (`watch_sync_request_handler.dart:381`). The canonical text gains `healthActivity` and `recommendedFor` (comma-joined, empty when absent) so every wrist re-fetches once at its next Sync. This also fixes the same latent gap for `healthActivity` (plans 75/170), which never reached a wrist that already held the old version. The version string format (`v1-<count>-<h1><h2>`) is unchanged; its value changes for every list, and the pinned vectors are recomputed. | `lib/core/utils/watch_reference_sync.dart:377` |
| D-19909 | **An older phone / an old stored catalog = no recommendation.** `recommendedFor` absent parses to `[]`; every exercise is then Other and, with one non-empty group, the list is one plain A–Z list. Nothing breaks and nothing is hidden. | `WatchRoutineRecords.swift` |
| D-19910 | **The Dart watch twin only round-trips the field.** `lib/watch/session/watch_records.dart`/`lib/watch/start/*` parse and re-emit `recommendedFor` (so a closed-schema round trip keeps it) but do not group: the twin is a developer harness and has no letter grid to remove. | `lib/watch/**` |
| D-19911 | **Only the wrist's list changes.** The phone's own exercise picker, the phone's ranking and the routine/effort wire shapes are untouched. | — |
| D-19912 | **The list view keeps its file name.** `WatchExerciseListView.swift` is one of the eight files the accessibility ratchet names (`WatchAccessibilitySourceTests.swift:306-333`); only the struct renames (`WatchExerciseLetterList` → `WatchExerciseGroupList`). The S-3106A source guard that asserts the struct name in three files and forbids `LazyVStack` is updated to the new name. | `WatchExerciseListView.swift`, `WatchMenuTests.swift` |
| D-19913 | **`structure_change` rides the same widening.** `structure_change.schema.json:99` also `$ref`s `$defs/catalogExercise`; the optional field therefore flows there too, harmlessly (additive, optional, and no structure_change fixture carries catalog exercises today). No extra fixture is added for it. | `watch/sync_protocol/schemas/messages/structure_change.schema.json` |
| D-19914 | **The twin's round trip is already verbatim.** `WatchRoutineCatalogRecord` (`lib/watch/session/watch_records.dart:690-758`) stores `fallbackExercises` as raw JSON maps, so `recommendedFor` survives storage unchanged; the twin's view class `WatchCatalogExercise.fromJson` (`lib/watch/start/watch_routine_catalog.dart:30`) gains the field only for parse/re-emit parity. The twin has no exercise-batch record (`WatchRecord.fromJson`'s switch has no `exerciseBatch` case) — `exercises_down` is not stored by the twin. | `lib/watch/start/watch_routine_catalog.dart`, `lib/watch/session/watch_records.dart` |
| D-19915 | **The contract's sample version value is not recomputed.** `watch/contract/watch_start_paths_contract.json:352` pins `routinesExercises.exercisesVersion = 'v1-2-004dbda823a1b308'` as an opaque sample of the request frame (the wrist transport test reads the value, never re-types it); only the derivation pins change (S-19902, D-19908). | `watch/contract/watch_start_paths_contract.json` |
| D-19916 | **Lead, found in P2b: the exercise batches shrink to 50 per batch (default), up from 100.** With `recommendedFor` on every discipline-linked exercise, the real seeded catalog's first `exercises_down` batch measured 18813 bytes, over the 16000-byte frame budget the existing guards S-3858 and S-19306 hold. The budget is not raised; `buildExercisesDown`'s default `batchSize` becomes 50 (the validated range stays 1..100, the schema's per-batch maximum is unchanged, the catalog version does not depend on batch size, the wrist merges any batch count). | `lib/core/utils/watch_reference_sync.dart` |
| D-19917 | **Review finding 4: a session that holds exercises ranks by its own modality; the pending tile wins only over no session or an empty one** (`listModality`). Guards a tile left pending by a picker whose dismissal never fired when a phone-pushed session arrived. | `WatchStartPaths.swift` |

## Input-reality checklist (answered)

1. **Writers.** `recommendedFor` is written only by `WatchReferenceSync._catalogExerciseJson` from `ModalityConfig.isRecommended` over `getExerciseCapabilities(id)` and the discipline's `categoryId` (`getDisciplines()`); custom exercises have a discipline too, or none (no category → score from capabilities only). The wrist stores it verbatim in `exb-<catalogVersion>-<n>` records and in the routines catalog's `fallbackExercises`; recents are stored by the wrist and carry none (D-19907).
2. **Lifecycle.** An exercise created or edited on the phone changes capabilities/discipline → its `recommendedFor` and the version change → next Sync re-sends (D-19908). A deleted exercise leaves the list. A stored catalog from before this change parses to `[]` (D-19909).
3. **Settings.** None changes the answer. (Units, accent: no.) The session's modality can be absent (Free) → plain list.
4. **Time.** n/a — no dates.
5. **Cost.** The phone scores each exercise against 4 modalities once per `buildExercisesDown`/`buildRoutinesDown` (pure arithmetic over data already read; the resolver reads disciplines ONCE per message, as it reads exercises once). The wrist partitions a list of a few hundred names per body read: O(n).
6. **Words.** Grep of the old wording is in the Docs delta. New strings: `Recommended`, `Other` (the phone's own). VoiceOver: group titles are section headers; the removed "Jump to <letter>" label disappears with the grid.
7. **Competition.** Recents-first vs synced recommendation (D-19907); the tile's modality vs a running session's (the picker over a session is a start-mode pick only while the Start surface is shown, i.e. over no session or an EMPTY one, where the engine's one-session rule refuses the pick; a session that holds exercises always ranks by its own modality, so a stale pending tile cannot outlive it — D-19917, S-19922).

## Feature invariants

- The A-to-Z order is owned by `addableExercises` alone: `deriveExerciseGroups` never re-sorts, each group preserves the input order, and the concatenation of the groups is the input list exactly once (D-19905, S-19907).
- Titles appear only when both groups are non-empty; one non-empty group or no modality is exactly one group with `title == nil` (D-19905, S-19908/S-19909).
- The wire change is additive-optional: no existing field moves, no message family and no version format change; an absent `recommendedFor` parses to `[]` on every reader (D-19904/D-19909, S-19906).
- The routine `effort` shape and the `sessionExercise` slot never carry `recommendedFor` (D-19904, S-19903).
- The watch never scores: it only compares stored strings against the modality the list was opened with (D-19903, D-19905).
- New Swift function names avoid the append-only guard's banned verbs (`WatchSessionEngineTests` "S-004 append-only enforcement"); SwiftUI targets watchOS 9 only (one-parameter `.onChange`) — crew-playbook rules (r)/(an).
- The list view keeps its file name `WatchExerciseListView.swift` (D-19912), and `WatchExercisePickerView`'s `select` body and `cancelIfNothingPicked` guard are untouched (source guards `WatchPlannedSurfaceSourceTests.swift:334-337`).

## Existing-functionality impact

| Touched surface | What already reads it (search run) | Effect | Guarded by |
|---|---|---|---|
| The letter/section symbols of D-19901 in `WatchMenu.swift` | The two call sites only: `WatchMenuView.swift:267-270` (`WatchAddExerciseList`) and `WatchStartView.swift:462-465` (`WatchExercisePickerView`); grep of `addExerciseLetters\|deriveExerciseListLetters\|deriveExerciseSections\|WatchExerciseSection\|scrollTargetLetters` over `watch/watchos/Sources` + `ios/OmniTrain Watch App` returned no other reader | Deleted/renamed together with their call sites | S-19912, S-19913 |
| `WatchExerciseLetterList` (`WatchExerciseListView.swift`) | `WatchMenuTests` S-3900–S-3908 (letters), S-3105A/S-3108A/S-3114A (sections/grid/scroll id), S-3106A (the name asserted in three files, `!LazyVStack`); `WatchSessionStartPathsTests.testS3113A` (~l.2389-2462) calls `deriveExerciseListLetters` three times | Struct renamed, grid and letters gone; the listed tests rewritten in P1 | S-19912, S-19913 |
| The accessibility ratchet, `WatchAccessibilitySourceTests.swift:306-333` | Names `WatchExerciseListView.swift` among the eight files that must carry `.accessibility` | Unaffected: the file name is kept (D-19912) | D-19912 |
| The version-hash derivation pins | `test/watch_reference_sync_test.dart:736` (`'v1-2-004dbda823a1b308'`) and `:741` (`'v1-2-6a71268979e6d5bd'`) — recomputed in P2b; `test/watch_transport_test.dart:1755` (a `const` round-tripped through `exercisesVersionOf`) and `watch/contract/watch_start_paths_contract.json:352` (a sample request frame) hold the same text opaquely — unchanged (D-19915) | Only the derivation pins are recomputed | S-19902, S-19916 |
| The version skip, `lib/state/watch/watch_sync_request_handler.dart:379-390` (`if (exercisesVersion == version) return;`) | Every wrist that synced before this change holds a now-impossible version | The whole list travels once at the next Sync | S-19916 (D-19908) |
| `structure_change.schema.json:99` | `$ref`s `$defs/catalogExercise` like the exercises_down/routines_down sites | The optional field rides it | D-19913, S-19904 |
| The Dart twin | `WatchCatalogExercise.fromJson` (`lib/watch/start/watch_routine_catalog.dart:30`, three fields today), raw-map storage in `WatchRoutineCatalogRecord` (`lib/watch/session/watch_records.dart:690-758`), no `exerciseBatch` case in `WatchRecord.fromJson`'s switch (`:201-215`) | Parse/re-emit only; storage is already verbatim | S-19915 (D-19914) |
| The replay corpus, `watch/sync_protocol/fixtures/replay/` (19 files) | Grep for `exercises_down\|fallbackExercises\|catalogExercise` in `replay/`: no matches | Untouched; the lead regenerates it only if the corpus tests go red on the version hash | D-19908 |
| `lib/watch/sensors/watch_platform_workout.dart` (reads `exercise['healthActivity']` from slot maps) | Slots do not gain `recommendedFor` (D-19904) | Unaffected | D-19911 |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-19901 | Phone: repository with `Running` (discipline in `category-cardio`, capabilities time+distance), `Bench Press` (`category-resistance`, reps+sets+load), `Mystery` (no discipline, capability reps only). `buildExercisesDown` | Running's wire object has `recommendedFor == ['cardio_endurance']`, Bench Press `['resistance_lifting']`, Mystery has NO `recommendedFor` key. Expected values hand-derived from `ModalityConfig.calculateRelevanceScore` (Running/cardio = 40 + 30 = 70; Bench/resistance = 40 + 30 = 70; Mystery/resistance = 10, nothing ≥ 50); the builder re-derives them with a throwaway test. | the field does not exist today |
| S-19902 | Phone: two catalogs identical except one exercise's `recommendedFor`; then two identical except one `healthActivity` | `exercisesVersionOf` differs in each pair; the same catalog in another order has the same version. | the hash ignores both fields today |
| S-19903 | Phone: `buildRoutinesDown` for a routine naming Running: `fallbackExercises` entries carry `recommendedFor`; the routine `effort` and `sessionExercise` shapes do not. | as stated | only `exercises_down` could carry it; the closed effort schema would refuse it |
| S-19904 | Contract: `fixtures/valid/exercises_down_recommended_for.json` (all four keys on one exercise, one key on another) conforms on Dart and Swift. | as stated | the closed `catalogExercise` refuses an undeclared field |
| S-19905 | Contract: `fixtures/invalid/exercises_down_unknown_recommended_for.json` (`"curling"`) and `…_recommended_for_empty.json` (`[]`) are refused on both stacks with the stated codes. | as stated | no schema rule exists to refuse them |
| S-19906 | Wrist: `WatchCatalogExercise(json:)` reads `recommendedFor`; `toJson()` round-trips it; absent | `[]` and `toJson()` omits the key; `toSlot` never emits it. | the model has no such field |
| S-19907 | Wrist grouping, modality `cardio_endurance`, A-to-Z input `[Arm Curl(res), Bike(card), Climb(card), Dips(res), Zumba(card)]` | groups `Recommended: [Bike, Climb, Zumba]`, `Other: [Arm Curl, Dips]`; concatenated = the input set, each exercise once. | today's sections are per-letter |
| S-19908 | One non-empty group: all recommended | one group, `title == nil`; none recommended → one group, `title == nil`. | headers would show on a one-group list |
| S-19909 | No modality (`nil`) | one group, `title == nil`, input order untouched. | n/a today — pins the Free case |
| S-19910 | Paths: a recent (no `recommendedFor`, stored before this change) whose id the synced list marks recommended for `sports` appears under Recommended for `sports`; a recent unknown to the sync is Other. | as stated | `deriveFallbackExercises` keeps the recent's own (empty) value |
| S-19911 | Paths: `beginModalityStart("sports")` | `listModality == "sports"`; after `cancelModalityStart()` and with a running session whose modality is `resistance_lifting` → `"resistance_lifting"`; a session with no modality → `nil`. | no accessor |
| S-19912 | Source guard: `WatchExerciseListView.swift` has no `LazyVGrid`, no `letterGrid`, no `ScrollViewReader`, no `scrollTo`; the symbols of D-19901 occur nowhere in `watch/watchos/Sources` or `ios/OmniTrain Watch App` | Each assert is the exact statement incl. brace/`Text(...)`, never a substring such as `if let`. | the grid is there |
| S-19913 | Source guard: the list renders a `Section` per group with `header:` only when `group.title != nil`, and both entry points (`WatchExercisePickerView`, `WatchAddExerciseList`) pass `groups:` computed with `listModality`. | as stated | headers are letters |
| S-19914 | Integration: an `exercises_down` frame (the S-19904 fixture shape) stored through the wrist's real apply path | `availablePickerExercises` grouped for its modality shows the recommended exercises first. | needs the field end to end |
| S-19915 | Dart twin: `WatchCatalogExercise` round-trips `recommendedFor` and the Dart validator accepts S-19904 / refuses S-19905 (`test/sync_protocol_fixtures_test.dart` walks the same manifest). | as stated | twin drops/refuses the field |
| S-19916 | `test/watch_sync_request_handler_test.dart`, the S-3854 pattern: a wrist answers `exercisesVersion` with the value the pre-change phone sent for the same catalog | With the new canonical text that value matches nothing, so the batches travel again and `sentVersion != held`; a wrist naming the freshly built version still gets no batch | the version skip matches today's text, which D-19908 changes |
| S-19917 | Wrist grouping, `recommendedFor: ['curling']` on one exercise | The key is kept in the model and matches no modality; the exercise is Other | an enum alone would refuse it; kept-but-unmatched is D-19905's rule |
| S-19918 | Wrist grouping, `recommendedFor: ['sports','sports']` | The exercise matches once and appears exactly once in the concatenated list | the wire has no `uniqueItems` (D-19904) |
| S-19919 | Wrist grouping, an exercise whose name is empty (the S-3907 fixture's case) | It keeps its A-to-Z position (the `#` run's place sorts last under plain-lowercase) and lands in its group | the group test must not special-case empty names |
| S-19920 | The grouped list exposes each titled group as a section header to VoiceOver; the untitled single group adds no header row (source/view assert on `WatchExerciseListView.swift`) | as stated | today's headers are letters |
| S-19921 | The real seeded catalog through `buildExercisesDown`: every batch is under 16000 bytes and holds at most 50 exercises; the batch count is `ceil(totalCount / 50)` | as stated | with 100 per batch the first batch is 18813 bytes once `recommendedFor` is on the wire (D-19916) |
| S-19922 | Paths: `beginModalityStart("sports")`, then a session that holds an exercise with modality `resistance_lifting`; `listModality` | `resistance_lifting`; with an empty session and the pending tile it is still `sports` | a pending tile beats the session's modality today (D-19906 as built) |

## Phases (outline; the architect expands, ≤ 8 items each)

- **P1 — remove the grid and the letter sections** · `crew-builder-watch` · scope `watch/watchos/**` · D-19901/2, S-19912. Replace `WatchExerciseSection` with `WatchExerciseGroup(title: String?, exercises:)` and `deriveExerciseGroups(_:modality:)`; until P3 supplies `recommendedFor` the function returns one untitled group. Delete the symbols of D-19901 and their tests; adjust every test that built sections/letters. Serial first with P2a (disjoint scopes → parallel).
- **P2a — contract** · `crew-builder-watch` · scope `watch/sync_protocol/**` · D-19904, S-19904/5. Schema, fixtures + `manifest.json` (rule bh), PROTOCOL.md amendment row. Parallel with P1.
- **P2b — phone sender** · `crew-builder-app` · scope `lib/**`, `test/**` · D-19903/8/10, S-19901–03/15. After P2a. The resolver reads `getDisciplines()` once; `_SyncedExercise` gains `recommendedFor`; the version hash text; the Dart validator if it hand-codes the shape; the Dart twin records.
- **P3 — wrist consumes** · `crew-builder-watch` · scope `watch/watchos/**`, `ios/OmniTrain Watch App/**` · D-19905–7/9, S-19906–11/13/14. After P1 and P2a. Rule (an): watchOS 9 SwiftUI only; rule (r): no banned verbs in NEW Swift function names.
- **P4 — docs** · `crew-docs-keeper` (+ the lead's one-file PROTOCOL run) · the Docs delta table.
- Then prove, review, fix rounds. Replay corpus: the lead regenerates it only if the Swift/Dart corpus tests go red on the version hash (D-19908).

## Phases (expanded)

Next handoff: P1 and P2a can start in parallel (disjoint write scopes). P2b waits for P2a; P3 waits for P1 and P2a; P2b and P3 may then run in parallel. P4 last. Gateway spellings used below are the ones earlier plans ran (`gateway.sh list` shows the checks; a check the gateway does not offer is reported, not improvised).

### P1 — remove the grid and the letter sections (first; parallel with P2a)

- Owner: `crew-builder-watch`. Write scope: `watch/watchos/**`. Deps: none. Write the report FIRST as a skeleton (`.work/crew/2026-11-15-199/watch-p1-report.md`), one status line per item, filled as items land.
- Items:
  1. [ ] Write the P1 report skeleton with one status line per item — `.work/crew/2026-11-15-199/watch-p1-report.md` · (report)
  2. [ ] Red tests first: rewrite S-3105A/S-3108A/S-3114A to the group shape (S-19907/8/9 fixtures; one untitled group until P3) and add the S-19912 source-guard test (no letter symbols anywhere in Sources) — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · `letterCatalogNames`, `applyLetterCatalog`
  3. [ ] Replace `WatchExerciseSection` with `WatchExerciseGroup(title: String?, exercises:)` and add `deriveExerciseGroups(_:modality:)` returning one untitled group for now — `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` · `WatchMenuState`
  4. [ ] Delete `WatchAddExerciseLetter`, `addExerciseLetterKey(of:)`, `deriveAddExerciseLetters`, `scrollTargetLetters(of:)`, `deriveExerciseListLetters`, `WatchMenuCopy.addLetterGridThreshold`, `WatchMenuCopy.addLetterJumpLabel`, `WatchMenuState.addExerciseLetters` — `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` · `WatchMenuCopy`
  5. [ ] Rename the struct `WatchExerciseLetterList` → `WatchExerciseGroupList` (the file name stays, D-19912); drop the `letters:` parameter, `letterGrid(_:)`, `ScrollViewReader`/`scrollTo`; render one `Section(header:)` per titled group — `watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift` · `WatchExerciseGroupList`
  6. [ ] Update both call sites to pass `groups:` computed with modality `nil` for now — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift:267-270` · `WatchAddExerciseList`; `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift:462-465` · `WatchExercisePickerView`
  7. [ ] Update the S-3106A source guard to the new struct name in the three files and keep its `!LazyVStack` assert; delete the letter tests S-3900–S-3908 — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · `testS3106AOneListServesBothEntryPoints`
  8. [ ] Remove the three `deriveExerciseListLetters` assertions from `testS3113A` and keep its row-agreement asserts — `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift` · `testS3113AThePickerRowsAndTheAvailableExercisesAgree`
- Done criteria:
  - `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter WatchMenuTests` → 0 failures
  - `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter WatchSessionStartPathsTests` → 0 failures
  - `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter WatchSessionEngineTests` → 0 failures (whole target: the append-only guard, the ratchet, `WatchPlannedSurfaceSourceTests`)
- Predicted files: `WatchMenu.swift`, `WatchExerciseListView.swift`, `WatchMenuView.swift`, `WatchStartView.swift`, `WatchMenuTests.swift`, `WatchSessionStartPathsTests.swift` (all under `watch/watchos/`), plus the report under `.work/crew/2026-11-15-199/`. Nothing else may change.

### P2a — contract (parallel with P1; disjoint scope)

- Owner: `crew-builder-watch`. Write scope: `watch/sync_protocol/**`. Deps: none. Write the report FIRST as a skeleton (`.work/crew/2026-11-15-199/contract-p2a-report.md`).
- Items:
  1. [ ] Write the P2a report skeleton — `.work/crew/2026-11-15-199/contract-p2a-report.md` · (report)
  2. [ ] Declare the optional property `recommendedFor` on `$defs.catalogExercise` (array, `minItems` 1, `maxItems` 4, the four-key enum beside `$defs/healthActivity`) — `watch/sync_protocol/schemas/envelope.schema.json` · `$defs/catalogExercise`
  3. [ ] Valid fixture: one exercise carrying all four keys, another exactly one — `watch/sync_protocol/fixtures/valid/exercises_down_recommended_for.json`; register it in `watch/sync_protocol/fixtures/manifest.json`
  4. [ ] Invalid fixtures with their expected codes: `exercises_down_unknown_recommended_for.json` (`"curling"`) and `exercises_down_recommended_for_empty.json` (`[]`) — `watch/sync_protocol/fixtures/invalid/`; register both in `manifest.json`
  5. [ ] PROTOCOL.md amendment row dated 2026-11-15 at the end of the version-history table (the plan-170 `healthActivity` row's shape) — `watch/sync_protocol/PROTOCOL.md` · `## Version history`
- Done criteria:
  - the gateway's Dart fixture walk (`flutter test test/sync_protocol_fixtures_test.dart`, run through the gateway's flutter check; the spelling `gateway.sh list` shows) → 0 failures, including the "lists every fixture file on disk, exactly once" test
  - `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter SyncProtocolFixturesTests` → 0 failures
- Predicted files: `envelope.schema.json`, the three new fixtures, `manifest.json`, `PROTOCOL.md`. Nothing else may change.

### P2b — phone sender (after P2a)

- Owner: `crew-builder-app`. Write scope: `lib/**`, `test/**`. Deps: P2a (the schema is the contract both sides code against). Write the report FIRST as a skeleton (`.work/crew/2026-11-15-199/phone-p2b-report.md`).
- Items:
  1. [ ] Write the P2b report skeleton — `.work/crew/2026-11-15-199/phone-p2b-report.md` · (report)
  2. [ ] `_SyncedExercise` gains `recommendedFor`; `_ExerciseResolver` reads `getDisciplines()` once and maps discipline → `categoryId`; per exercise, per `Modality.primaryHomeTiles` modality, score with `ModalityConfig.isRecommended` (capabilities + category) and keep the passing keys in `Modality.primaryHomeTiles` order — `lib/core/utils/watch_reference_sync.dart` · `_ExerciseResolver`
  3. [ ] `_catalogExerciseJson` writes `recommendedFor` (each key once, omitted when empty); `_fallbackJson` inherits it — `lib/core/utils/watch_reference_sync.dart` · `_catalogExerciseJson`
  4. [ ] `exercisesVersionOf` canonical text gains `healthActivity` and `recommendedFor` (comma-joined, empty when absent), field order pinned by the new S-19902 derivation test; format `v1-<count>-<h1><h2>` unchanged — `lib/core/utils/watch_reference_sync.dart` · `exercisesVersionOf`
  5. [ ] Recompute the pinned vectors (`'v1-2-004dbda823a1b308'`, `'v1-2-6a71268979e6d5bd'`) with a throwaway derivation and add the S-19902 assertions (a `recommendedFor`-only diff and a `healthActivity`-only diff each change the version) — `test/watch_reference_sync_test.dart` · S-3844 group
  6. [ ] Twin round trip: `WatchCatalogExercise.fromJson`/`toJson` parse and re-emit `recommendedFor`, no grouping — `lib/watch/start/watch_routine_catalog.dart` · `WatchCatalogExercise`; asserted in `test/watch_health_activity_test.dart` · S-10514 group (S-19915)
  7. [ ] S-19901/S-19903: builder output carries the field on `exercises_down` items and `routines_down.fallbackExercises`, not on the routine `effort` or `sessionExercise` shapes — `test/watch_health_activity_test.dart` · S-10513/S-10514 groups
  8. [ ] S-19916 in the S-3854 pattern — `test/watch_sync_request_handler_test.dart` · S-3854 group
- Done criteria (each through the gateway's flutter check):
  - `test/watch_reference_sync_test.dart` → 0 failures
  - `test/watch_health_activity_test.dart` → 0 failures
  - `test/watch_sync_request_handler_test.dart` → 0 failures
  - `test/watch_transport_test.dart` → 0 failures (its const is opaque, D-19915)
  - `test/sync_protocol_fixtures_test.dart` → 0 failures
- Predicted files: `lib/core/utils/watch_reference_sync.dart`, `lib/watch/start/watch_routine_catalog.dart`, `test/watch_reference_sync_test.dart`, `test/watch_health_activity_test.dart`, `test/watch_sync_request_handler_test.dart`. Nothing else may change.
- Note: the Dart validator is schema-driven (no hand-coded `catalogExercise` key list, `lib/core/sync_protocol/message_validator.dart:84-85`), so the outline's "the Dart validator if it hand-codes the shape" resolves to no change.

### P3 — wrist consumes (after P1 and P2a)

- Owner: `crew-builder-watch`. Write scope: `watch/watchos/**`, `ios/OmniTrain Watch App/**`. Deps: P1 (the group types), P2a (the wire shape). Rules (an)/(r) apply. Write the report FIRST as a skeleton (`.work/crew/2026-11-15-199/watch-p3-report.md`).
- Items:
  1. [ ] Write the P3 report skeleton — `.work/crew/2026-11-15-199/watch-p3-report.md` · (report)
  2. [ ] Red tests first, S-19906: `WatchCatalogExercise(json:)` reads `recommendedFor`, `toJson` round-trips it, absent → `[]` and the key omitted, `toSlot` never emits it — the suite that today covers `WatchCatalogExercise`'s json round-trip (plan 75/170's contract tests; if the file is not named `WatchHealthActivityContractTests.swift`, use that one) · `WatchCatalogExercise.init(json:)`
  3. [ ] Group tests S-19907/S-19908/S-19909/S-19917/S-19918/S-19919, the `applyLetterCatalog` harness extended to name each exercise's `recommendedFor` — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · `deriveExerciseGroups`
  4. [ ] `listModality` (D-19906) and the per-id recommendation lookup over `activeExercises` + `catalogFallback` (D-19907), falling back to the entry's own value; S-19910/S-19911 tests — `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` · `syncedFallback`, `availablePickerExercises`; `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`
  5. [ ] Feed the real modality at both entry points: the picker from a tile (`paths.pendingModalityStart`) and Add Exercise over a session (the session's `WatchSessionRecord.modality`) — `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift:462-465` · `WatchExercisePickerView`; `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift:267-270` · `WatchAddExerciseList`
  6. [ ] S-19914: store the S-19904 fixture shape through `applyExercisesDown` (`WatchStartPaths.swift:568`) and group `availablePickerExercises` for its modality — `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`
  7. [ ] S-19920: the titled groups are section headers, the untitled group adds none — `watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift` · `WatchExerciseGroupList` (asserted in `WatchMenuTests.swift`)
- Done criteria:
  - `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter WatchMenuTests` → 0 failures
  - `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter WatchSessionStartPathsTests` → 0 failures
  - `.github/copilot/scripts/macos/gateway.sh swift-test -- --filter WatchSessionEngineTests` → 0 failures
- Predicted files: `WatchStartPaths.swift`, `WatchMenuView.swift`, `WatchStartView.swift`, `WatchMenu.swift` (if the lookup lives beside `deriveExerciseGroups`), `WatchMenuTests.swift`, `WatchSessionStartPathsTests.swift`, the plan-75 contract-test file. Nothing else may change.

### P4 — docs (last)

- Owner: `crew-docs-keeper`. Write scope: `docs/**` excluding `docs/plans`, `docs/history`, `docs/releases`. Deps: P1–P3 (writes what the code now does). Write the report FIRST as a skeleton (`.work/crew/2026-11-15-199/docs-p4-report.md`).
- Items (the Docs delta table's rows, grouped per doc):
  1. [ ] `docs/state_management/watch_reference_data.md`: the seeded MODIFIED row (the whole grid sentence, its `testS3908`/`testS3900`/`testS3902`/`testS3905` pins included, becomes the no-letter-grid sentence) plus the REMOVED rows below; the sort sentence (`testS3611…`) and the batch/version paragraphs stay
  2. [ ] `docs/state_management/watch_reference_data.md`: the seeded ADDED row — the paragraph naming who writes `recommendedFor`, how the wrist reads it and why every held version stales once (D-19903/4/7/8/9)
  3. [ ] `docs/state_management/watch_surface_wrist.md`: the seeded MODIFIED row (`so a letter jump lands on a measured row` → the Recommended-group sentence), the MODIFIED row for `render the same \`WatchExerciseLetterList\`` → the new struct name, and the REMOVED row for the "Within it the sections are walked by position" paragraph (`testS3114A…`, D-3117); the row at ~225 stays true
  4. [ ] `docs/watch-app-qa-wrist-logging.md`: the seeded REMOVED row (step 14, `Jump to a letter in a long exercise list`) and its remaining sentences (`the grid is its first row, then`, `The letters and` with the `testS3900…`–`testS3905…` pins) go with the step; step 13 stays
  5. [ ] Verify no row needed: `docs/watch-app-setup-and-qa.md:195` and `docs/state_management/watch_surface_wrist_logging.md:11` name no letter grid — record the check in the docs report
  6. [ ] Write the docs report: rows applied, the verified-still-true sentences, any doc the sweep missed — `.work/crew/2026-11-15-199/docs-p4-report.md`
- Done criteria:
  - the repo's docs test (seen referenced in plan 76's Done list as `flutter test test/docs_indexing_contract_test.dart`; verify the file exists before relying) → 0 failures
  - every behaviour sentence added names an existing test; every touched file stays below 52 KB
- Predicted files: the three docs above plus the docs report under `.work/crew/2026-11-15-199/`. Nothing else may change.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/watch_reference_data.md` | MODIFIED | also carries the letter grid it | has no letter grid | D-19901 |
| `docs/watch-app-qa-wrist-logging.md` | REMOVED | Jump to a letter in a long exercise list | - | D-19901 |
| `docs/state_management/watch_surface_wrist.md` | MODIFIED | so a letter jump lands on a measured row | Recommended group | D-19905 |
| `docs/state_management/watch_reference_data.md` | ADDED | - | recommendedFor | D-19904 |
| `docs/state_management/watch_reference_data.md` | REMOVED | `deriveExerciseSections` reads | - | D-19901 |
| `docs/state_management/watch_reference_data.md` | REMOVED | the picker's grid is `deriveExerciseListLetters` | - | D-19901 |
| `docs/state_management/watch_surface_wrist.md` | MODIFIED | render the same `WatchExerciseLetterList` | render the same `WatchExerciseGroupList` | D-19901, D-19912 |
| `docs/state_management/watch_surface_wrist.md` | REMOVED | Within it the sections are walked by position | - | D-19902 |
| `docs/watch-app-qa-wrist-logging.md` | REMOVED | the grid is its first row, then | - | D-19901 |
| `docs/watch-app-qa-wrist-logging.md` | REMOVED | The letters and | - | D-19901 |
| `docs/state_management/watch_reference_data.md` | ADDED | - | partitions the already-A-to-Z list into a | D-19905 |
| `docs/state_management/watch_reference_data.md` | MODIFIED | in batches of at most 100 exercises, each | in batches of at most 50 exercises, each | D-19916 |
| `docs/state_management/watch_reference_data.md` | MODIFIED | batches of at most 100, | batches of at most 50, | D-19916 |

(Sweep completed. Checked and left alone: `watch_surface_wrist.md` ~225 (`availablePickerExercises —
addableExercises, the menu's own A to Z list` — still true), `watch_surface_wrist_logging.md:11` and
`docs/watch-app-setup-and-qa.md:195` (name no grid — still true), the QA step 13 sentence (`the full
list is there, custom exercises included, A to Z` — still true), `watch_sensors.md`/`watch_session_capture.md`/
`watch_surface.md` healthActivity and exercises_down sentences (unaffected). The seeded note expected a
version-hash sentence in `watch_reference_data.md`; the sweep found none outside `docs/plans` — no row
invented.)

## Progress

| Item | Status |
|---|---|
| P1.1 report skeleton | pending |
| P1.2 red tests (groups + S-19912 guard) | pending |
| P1.3 `WatchExerciseGroup` + `deriveExerciseGroups` | pending |
| P1.4 delete the letter symbols | pending |
| P1.5 rename the list view | pending |
| P1.6 call sites pass `groups:` | pending |
| P1.7 S-3106A guard + delete S-3900–S-3908 | pending |
| P1.8 `testS3113A` letter asserts out | pending |
| P2a.1 report skeleton | pending |
| P2a.2 `$defs.catalogExercise` field | pending |
| P2a.3 valid fixture + manifest | pending |
| P2a.4 invalid fixtures + manifest | pending |
| P2a.5 PROTOCOL.md amendment row | pending |
| P2b.1 report skeleton | pending |
| P2b.2 resolver computes `recommendedFor` | pending |
| P2b.3 `_catalogExerciseJson` writes it | pending |
| P2b.4 `exercisesVersionOf` text | pending |
| P2b.5 recomputed vectors + S-19902 | pending |
| P2b.6 twin round trip | pending |
| P2b.7 S-19901/S-19903 shapes | pending |
| P2b.8 S-19916 handler test | pending |
| P3.1 report skeleton | pending |
| P3.2 S-19906 red tests | pending |
| P3.3 group tests | pending |
| P3.4 `listModality` + lookup + S-19910/11 | pending |
| P3.5 entry points feed the modality | pending |
| P3.6 S-19914 integration | pending |
| P3.7 S-19920 headers | pending |
| P4.1 reference_data grid rows | pending |
| P4.2 reference_data added rows | pending |
| P4.3 surface_wrist rows | pending |
| P4.4 QA doc rows | pending |
| P4.5 verified-no-row checks | pending |
| P4.6 docs report | pending |

## Assumption Log

- Owner defaults: headers read `Recommended` / `Other` and show only when both groups exist; letter headers removed (D-19902); a running session's own modality ranks Add Exercise (D-19906). **owner to confirm**.
- The phone's "Recommended" rule is reused as is, including its imperfections (e.g. an exercise with no discipline is judged on capabilities alone).
- The struct rename `WatchExerciseLetterList` → `WatchExerciseGroupList` (D-19912) is the architect's choice; the owner has not named it. **owner to confirm**.
- Lead deviation from P2b item 6 / D-19914: the Dart twin's `WatchCatalogExercise` view class (`lib/watch/start/watch_routine_catalog.dart`) is NOT changed — it already drops `healthActivity` and `roundDurationSecs`, and its store keeps the phone's raw JSON, so the field round-trips; S-19915 is the manifest walk of the valid/invalid fixtures.
- `structure_change` carries the field implicitly (D-19913) without a dedicated fixture. **owner to confirm**.
- The suite for S-19906 is assumed to be plan 75/170's `WatchCatalogExercise` contract-test file; its exact name was not verified this run — P3 item 2 resolves it.

## Feedback

(none yet)
