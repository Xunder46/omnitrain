# Plan 20 — the watch menu: navigate the exercises, add one, finish

> Status: CLOSED — both phases built and committed; independent review round 1 fixed (findings 1, 3, 4, 7); findings 5 and 6 (a doc scope line, an archived plan record) left open on purpose. Seeded Ledger D-1100…D-1108, scenarios S-1100…S-1109; D-1109…D-1114 and S-1110…S-1113 appended.
> Next handoff: governor: commit
> Series: `docs/plans/2026-10-08-18-watch-qa-index.md` row 20 (the planner linked it to this plan; its status flips after Phase 2's governor build). Base: see `.work/watch-20/base.txt`.
> Evidence: `2026-10-09-20-watch-menu-plan.evidence.md` · Review: `2026-10-09-20-watch-menu-plan.review.md` (both beside this file).
> Track: Apple Watch client only (`watch/watchos/`, `ios/OmniTrain Watch App/`) + docs. No wire, phone or Dart change.

## Goal

The logging screen on the wrist carries too much: the exercise, its values, **End** and a list button all share a
40 pt screen. Move everything that is not "log this set" behind **one menu button**. The menu is a screen that
lists the session's exercises so the user can jump between them, and ends with **Add exercise** and **Finish**.
The menu never edits or deletes anything.

## Acceptance criteria

1. The logging screen's toolbar holds exactly one control, the menu button (it replaces today's list button and
   today's **End**). Nothing else on the screen changes.
2. The menu lists one row per exercise in the session's order. Each row shows the exercise name and how many
   efforts are logged on it ("2 logged", none → no count). The exercise the user is on is marked.
3. Tapping a row moves the user to that exercise and closes the menu. Nothing in the menu edits, deletes,
   reorders or re-logs an effort.
4. After the rows: **Add exercise** (opens the picker, listing only exercises not yet in the session; picking one
   adds it, moves the user to it and closes everything) and **Finish** (ends the session exactly as End did:
   same rating prompt rules).
5. The menu is reachable only from the logging screen. The rest screen and the start screen are unchanged
   (D-160: no rest preset, countdown or alarm anywhere near the menu).
6. `swift test` and the watch scheme build stay green; flutter suite unchanged.

### Acceptance criteria → scenarios

| Criterion | Guarded by |
|---|---|
| 1 — one toolbar control, the menu button | D-1100, D-1112; Phase 2 item 2; governor's watch-scheme build (no `swift test` covers a watchOS-only view) |
| 2 — one row per exercise, order, count, current marked | S-1100, S-1101, S-1102, S-1110, S-1111; D-1101, D-1102, D-1109, D-1110, D-1114 |
| 3 — a row jumps and closes; nothing edits/deletes/reorders | S-1103, S-1104; D-1103, D-1106, D-1107 |
| 4 — Add exercise, then Finish with End's rating rules | S-1105, S-1106 (add), S-1107, S-1113 (finish); D-1104, D-1105, D-1112, D-1113 |
| 5 — reachable only from the logging screen; no rest control | S-1108 (D-160); Phase 2 item 5 (start and rest surfaces untouched) |
| 6 — suites and builds green | Phase 1 and Phase 2 Done Criteria |

## Decision Ledger

- **D-1100** The menu is a sheet over the logging screen opened by the toolbar's trailing button; its icon stays
  the existing `list.bullet`. `ContentView.loggingSurface` (`ios/OmniTrain Watch App/ContentView.swift`) loses the
  `.topBarLeading` End item and the direct picker sheet; the trailing item now sets a `showingMenu` state.
- **D-1101** Menu rows are derived, never stored: `deriveMenuRows(sessionExercises:entries:currentIndex:)` in a new
  `WatchMenu.swift`, a pure function like `derivePickerRows` (`WatchStartPaths.swift:179`). Row = `slotId`,
  `name`, `loggedCount`, `isCurrent`. `loggedCount` counts `engine.entries` (the projection with the phone's
  corrections and deletions folded in, `WatchSessionEngine.swift:199`) whose `payload["sessionExerciseId"]` equals the
  slot's `sessionExerciseId`. Order = the session's `exercises` order. A slot without a `sessionExerciseId` or name is
  skipped (same guard as `derivePickerRows`: `WatchCatalogExercise(slot:)`).
- **D-1102** `isCurrent` = the row's index equals `session.currentExerciseIndex` (clamped to the ladder). Exactly
  one row is current when the ladder is non-empty.
- **D-1103** Jumping reuses `WatchSessionEngine.selectExercise(slotId:)` (`WatchSessionEngine.swift:325`) via
  `WatchSessionStartPaths.selectExercise(.inSession…)` — no new engine write. A slot that is gone by the time the tap
  lands changes nothing and the menu closes.
- **D-1104** "Add exercise" opens `WatchExercisePickerView` in an **add-only** mode: a new `addOnly: Bool = false`
  parameter drops `.inSession` rows (they are the menu's rows, not the picker's). Default behaviour (start screen,
  free workout) is unchanged. Picking a row calls `paths.selectExercise` as today (`addExerciseToSession`, which
  moves the user to the new slot).
- **D-1105** "Finish" calls `WatchEffortRatingState.end()` (`WatchEffortRating.swift:148`) — the same code path End
  used, so the owed-rating prompt and `finishSession()` stay one implementation. `WatchEndSessionView` is no longer
  mounted anywhere (governor grep: only `ContentView.swift` uses it, no test names it), so it is removed from
  `WatchEffortRatingView.swift`. Finish has no confirmation, matching End.
- **D-1106** The menu has no rest control, no edit, no delete, no reorder (D-160, D-1101). A scanner-style test
  asserts the menu file names none of `restSeconds`, `plannedDurationMs`, `deleteEntry`, `removeExercise`.
- **D-1107** The menu is read-only over session state except the two actions the user taps (jump, add) and Finish.
  It mints no ids and appends no observation.
- **D-1108** Wire, phone, Dart (`lib/watch/`) and `watch/contract/` are untouched: the Dart Wear client has no
  picker or End parity today (`grep derivePickerRows lib` is empty), so no contract fixture is added.
- **D-1109** `loggedCount` counts only entries whose `kind` is one of `WatchObservationKind.efforts`
  (`WatchRecords.swift:81` — `.set`, `.timed`, `.round`, `.hold`). A rest observation carries the same
  `sessionExerciseId` as the effort it followed (`WatchSessionEngine.swift:1614`), while acceptance criterion 2
  counts *efforts*: a rest is not work in the slot. This refines D-1101's "counts `engine.entries`"; Fixture A
  (no rest) is unchanged. Guarded by S-1110 (mutation: count every kind → S-1100 red).
- **D-1110** `isCurrent` compares the row's **ladder** position — its index in `sessionExercises` — with
  `min(max(currentIndex, 0), sessionExercises.count - 1)`, the clamp `WatchSessionRecord.currentExercise` applies
  (`WatchRecords.swift:239-241`), and never with the row's position in the derived array. A slot the derivation
  skips (D-1101) therefore does not shift the mark. Derived reading of D-1102's "the row's index"; vetoable.
  Guarded by S-1111 and S-1102.
- **D-1111** `WatchMenuState.rows` is derived on every read and never cached, exactly as `pickerRows` is
  (`WatchStartPaths.swift:394-400`), so a frame that lands while the menu is open is in the list the user sees.
  `WatchMenuState` is a plain `final class`, not an `ObservableObject`: the host state's `revision` bump is what
  re-runs the view body, the same rule the picker follows. Guarded by S-1112.
- **D-1112** Finish ends the session through the rating state's `end()` and closes the menu, and the shell needs no
  menu-specific navigation state. With a rating owed, `ContentView.body` renders the prompt alone (`isPromptOwed`
  is tested first); with none owed, the logging branch's `session?.status == active` test fails and the start
  surface takes over. `.onDisappear { showingMenu = false }` stands where today's picker guard does
  (`ContentView.swift:252`), so no sheet survives the surface change. Guarded by S-1113.
- **D-1113** "Add exercise" presents `WatchExercisePickerView(addOnly: true)` as the menu's **own** nested sheet;
  picking a row appends the slot, moves the user to it (the existing `addExerciseToSession`) and dismisses **both**
  presentations, leaving the logging surface on the newly added exercise — acceptance criterion 4's "closes
  everything" is the two dismissals, not a navigation state. The add-only list may be empty; the picker's existing
  empty line is what shows (`WatchStartView.swift:208-213`). Guarded by S-1105 and S-1106.
- **D-1114** The menu's copy is fixed and derived where the suite can hold it: `WatchMenuRow.countLabel` is exactly
  `"\(loggedCount) logged"` when `loggedCount > 0` and `nil` when it is `0` (criterion 2 — never a "0 logged"
  subtitle), the row's title is the slot's `name` verbatim, and the two action labels are the literals
  `"Add exercise"` and `"Finish"`. Guarded by S-1100 for `countLabel`; the action literals are compiled only by the
  governor's watch-scheme build and used by the QA walkthrough step.

## Feature Invariants

- **The menu never writes session structure.** The only session-state changes a menu interaction may cause are the
  ones an existing path already performs: `selectExercise(slotId:)` for a jump and `addExerciseToSession` for an
  add. No new engine write, no id minting, no direct store write (D-1106, D-1107).
- **The rest rule stands.** No rest preset, length, countdown or alarm enters the menu or its rows
  (acceptance criterion 5). The rest surface's only entry point stays logging a set.
- **Corrections win.** Every count reads the engine's corrected projection, never raw stored observations
  (D-1101; `deletedEntryIds`, `entryCorrections`, `replacedEntryIds` at `WatchSessionEngine.swift:199-225`).

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `WatchExercisePickerView.init` gains `addOnly` | `grep -rn WatchExercisePickerView` → `WatchStartView.swift:156` (start sheet), `ios/OmniTrain Watch App/ContentView.swift:245` (logging sheet) | the default keeps both hosts' rows byte-for-byte as today | S-1105; `WatchConnectivityBridgeTests.swift:690`, `:762`, `:803` |
| `derivePickerRows` / `WatchSessionStartPaths.pickerRows` gain the add-only mode | `grep -rn "derivePickerRows\|pickerRows"` → `WatchStartPaths.swift:396` only, plus those three tests; `grep -rn derivePickerRows lib` empty (D-1108) | the existing property is untouched and keeps its three readers; the new mode is additive | S-1105 + the three existing picker tests |
| `WatchEndSessionView` removed | `grep -rn WatchEndSessionView` → `ContentView.swift:234` (the mount, replaced in Phase 2), `docs/watch_session_capture.md:229` (updated in Phase 2), zero test hits | the End *action* survives as the menu's Finish over the same `rating.end()`; no test or view named it | S-1107, S-1113; Phase 2 item 5 |
| `WatchEffortRatingState.end()` gains a new caller | `grep -rn "rating\.end\|canEnd\|isPromptOwed"` → `WatchEffortRatingView.swift:104` (removed), `ContentView.swift:230` | one call site moves; the state, its prompt branches and its tests are otherwise untouched | S-1107, S-1113; `WatchEffortRatingTests` unchanged |
| `WatchSessionEngine.selectExercise(slotId:)` gains a caller | `grep -rn selectExercise` → `WatchStartPaths.swift:406-413`, `lib/watch/session/watch_session_engine.dart` | routed through the existing path; the engine's own tests and the Dart twin are untouched | S-1103, S-1104 |
| `ContentView.loggingSurface` toolbar and sheet | `grep -rn loggingSurface` → `ContentView.swift` only (no test opens it) | one control instead of two; the sheet hosts the menu | D-1100, D-1112; governor's watch-scheme build |
| `docs/state_management/watch_surface.md` (near its 51.2 KB ceiling) | `docs/README.md:87` indexes it; `test/docs_indexing_contract_test.dart` scans it | the second-surface sentence changes, and the picker paragraph's trailing narration is deleted — which is what keeps the file from growing | `gateway.sh test test/docs_indexing_contract_test.dart` |
| the start and rest surfaces | `WatchStartView`, `WatchRestView` and their tests are not edited | unchanged | Phase 2 item 5 |
| the phone, wire and Dart sides | `grep -rn "pickerRows\|deriveMenuRows" lib ios/OmniTrain` → no hits (D-1108) | unchanged | review grep |

## Core scenarios

Fixture A (three-slot ladder, clock-free): slots `s1` "Squat", `s2` "Bench Press", `s3` "Row"; `currentExerciseIndex = 1`;
entries: two on `s1`, zero on `s2`, one on `s3`; one further `s1` entry whose id the phone deleted (`deletedEntryIds`).

- **S-1100** `deriveMenuRows(A)` → `[Squat · 2 · not current, Bench Press · 0 · current, Row · 1 · not current]`.
  Red without the change because the function does not exist. (The deleted `s1` entry is not counted: guards D-1101's
  use of `engine.entries` rather than `engine.observations`.)
- **S-1101** Empty ladder → `[]`; a slot with no name is skipped, the others keep their order.
- **S-1102** `currentExerciseIndex` out of range (7 on a 3-slot ladder) → the last row is current (the engine clamps).
- **S-1103** Jump: from A, tapping "Row" → `engine.session.currentExerciseIndex == 2`, `WatchLoggingState.exerciseName == "Row"`,
  no observation appended, session `revision`/`sequence` otherwise unchanged. Red: no menu jump API.
- **S-1104** Jump to a slot id no longer on the ladder → `nil` result, index unchanged.
- **S-1105** Add-only picker rows: with Fixture A's ladder and a fallback catalog of {Squat, Pull-up, Dip}, the add-only
  rows are `[Pull-up, Dip]` (Squat is on the ladder; "Bench Press"/"Row" are not in the fallback). Default mode still
  returns all three ladder rows first (existing tests pass untouched).
- **S-1106** Picking "Dip" from the add-only list appends slot 4 and moves the index to 3 (existing `addExerciseToSession` behaviour; asserted through the menu path).
- **S-1107** Finish with a rating owed → session `status` becomes finished and `isPromptOwed == true`; without one → finished, no prompt (same assertions as the existing End tests, now via the menu action).
- **S-1108** Negative guard: the menu source mentions none of the D-1106 tokens (mutation: add `deleteEntry` to the file → red).
- **S-1109** Menu rows read the corrected projection: an entry the phone *edited* to another slot id moves its count (mutation: derive from `engine.observations` instead of `engine.entries` → S-1100 red).

### Additional scenarios (planner, appended)

- **S-1110: a rest on a slot is not an effort.** Fixture: Fixture A plus one rest observation — `kind == "rest"`,
  `payload["sessionExerciseId"] == "s1"`, `payload["afterEntryId"] == "e-s1-1"`, stored after `e-s1-1`.
  Trigger: `deriveMenuRows`. Expected: the same three rows as S-1100 (`Squat · 2`, `Bench Press · 0 · current`,
  `Row · 1`) — Squat reads 2, not 3. Mutation: count every entry kind → Squat reads 3 → red. Guards D-1109.
  Edge case of: S-1100.
- **S-1111: a skipped slot does not shift the current mark.** Fixture: a three-slot ladder where slot 1 carries the
  sessionExerciseId but no `exerciseId`/`name` (`[{"sessionExerciseId": "s1"}, {"sessionExerciseId": "s2",
  "exerciseId": "ex-bench", "name": "Bench Press"}, {"sessionExerciseId": "s3", "exerciseId": "ex-row",
  "name": "Row"}]`), `currentExerciseIndex = 2`, no entries. Trigger: `deriveMenuRows`. Expected: two rows,
  `[Bench Press · 0 · not current, Row · 0 · current]` — the mark rides the ladder (D-1110). Mutation: compare the
  row's position in the derived array (1) with the clamped index (2) → no row carries it → red.
  Edge case of: S-1101, S-1102.
- **S-1112: the menu's rows are derived on every read.** Fixture: Fixture A, then a frame that adds slot 4 "Dip"
  to the same session. Trigger: read `state.rows` again from the same `WatchMenuState` instance. Expected: four
  rows, the last `Dip · 0 · not current` (D-1111). Mutation: cache the rows at init → the fourth slot is missing →
  red. Edge case of: S-1100.
- **S-1113: finishing leaves the shell nothing to log into.** Fixture: an active session with one slot and one
  effort entry; a `WatchEffortRatingState` over the same store; preferences asking for the rating. Trigger:
  `await state.finish()`. Expected: `engine.session?.status == .completed`, `rating.isPromptOwed == true`, and the
  logging branch's own test (`engine.session?.status == .active`) false, i.e. the shell falls through to the start
  surface (D-1112). With no rating owed (the same fixture, no `effortRatingPrompt`), finished and `isPromptOwed ==
  false`. Mutation: a menu-local `finished` flag that leaves `showingMenu` set → red. Edge case of: S-1107.

## Phase outline

1. **Phase 1 — menu model and picker mode (developer, Swift package, ≤ 6 items).** `WatchMenu.swift`
   (`WatchMenuRow`, `deriveMenuRows`, a small `WatchMenuState` that reads the engine, exposes `rows`, `jump(to:)`,
   and delegates Finish to the rating state), `WatchExercisePickerView.addOnly`, tests S-1100…S-1109 in a new
   `WatchMenuTests.swift`. Done: `swift-test` green, `prove-red` verdicts, invariant grep clean.
2. **Phase 2 — the wrist surfaces and docs (developer, ≤ 6 items).** `WatchMenuView` (rows, then Add exercise, then
   Finish; `ScrollView`, wrist-scale spacing like `WatchExercisePickerView`), `ContentView.loggingSurface` rewired
   (D-1100), `WatchEndSessionView` removed (D-1105), docs: `docs/state_management/watch_surface.md` (remove
   before adding — near its 51.2 KB ceiling), `docs/watch-app-setup-and-qa.md` walkthrough step, `docs/README.md`
   index row if a doc is added, the QA index row 20. Governor builds the watch scheme with `xcodebuild`.

## Iteration 1

### Phase 1: the menu model and the add-only picker (@developer)

Package-only work (`watch/watchos/`), no surface mounted yet. Six items.

1. [x] Create `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` with the pure model:
       `public struct WatchMenuRow: Equatable` — `slotId: String` (the `sessionExerciseId`), `name: String`,
       `loggedCount: Int`, `isCurrent: Bool`, plus `public var countLabel: String?` returning
       `"\(loggedCount) logged"` when `loggedCount > 0` and `nil` otherwise (D-1114);
       `public func deriveMenuRows(sessionExercises: [[String: Any]], entries: [WatchObservationRecord],
       currentIndex: Int) -> [WatchMenuRow]` — walk `sessionExercises` in order, skip a slot
       `WatchCatalogExercise(slot:)` rejects (`WatchRoutineRecords.swift:41`), and per kept slot count
       `entries.filter { WatchObservationKind.efforts.contains($0.kind) && ($0.payload["sessionExerciseId"] as? String) == slotId }`
       (`WatchRecords.swift:81`, `:325`; D-1101, D-1109), with `isCurrent` =
       `index == min(max(currentIndex, 0), sessionExercises.count - 1)` (D-1110); and
       `public final class WatchMenuState` — `init(engine: WatchSessionEngine, paths: WatchSessionStartPaths,
       rating: WatchEffortRatingState)`, `var rows: [WatchMenuRow]` delegating to `deriveMenuRows` over
       `engine.session?.exercises ?? []`, `engine.entries`, `engine.session?.currentExerciseIndex ?? 0` and
       caching nothing (D-1111), `func jump(to slotId: String) async -> Bool` resolving the row as
       `paths.pickerRows.first { $0.isInSession && $0.id == slotId }` and returning
       `await paths.selectExercise(row) != nil` — the picker row's `id` for an in-session row is exactly the slot's
       `sessionExerciseId` (`WatchStartPaths.swift:145-148`), so the menu's `slotId` finds it; a slot that is gone
       finds nothing and returns `false` (D-1103), and
       `func finish() async` awaiting `rating.end()` (D-1105, D-1112).
       · `WatchMenuRow`, `WatchMenuRow.countLabel`, `deriveMenuRows`, `WatchMenuState.rows`,
       `WatchMenuState.jump(to:)`, `WatchMenuState.finish()`
2. [x] Add the add-only mode to both halves of the picker, additively: in `WatchStartPaths.swift` give
       `derivePickerRows` an `addOnly: Bool = false` parameter that drops the `.inSession` rows
       (`WatchStartPaths.swift:179-230`) and add `public func pickerRows(addOnly: Bool) -> [WatchExercisePickerRow]`
       beside the existing `public var pickerRows` (`:395`) — the property must keep its exact signature, three
       existing assertions read it (`WatchConnectivityBridgeTests.swift:690`, `:762`, `:803`) and S-1105 requires
       them untouched; then in `WatchStartView.swift` add `let addOnly: Bool = false` to `WatchExercisePickerView`
       **before** the trailing `onExerciseAdded` closure and pass it to `paths.pickerRows(addOnly: addOnly)`.
       · `derivePickerRows`, `WatchSessionStartPaths.pickerRows(addOnly:)`, `WatchExercisePickerView.init`
3. [x] Create `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` with its fixture builders — a
       `WatchSessionEngine` + `InMemoryWatchSessionStore` + `WatchSessionStartPaths` + `WatchEffortRatingState`
       harness in the shape of `WatchSessionStartPathsTests.swift`'s `WatchStartHarness` and
       `WatchEffortRatingTests.swift`'s `RatingHarness`; `Fixture A` built by appending
       `store.append(.session(…))` (three slots, `currentExerciseIndex = 1`, `deletedEntryIds == ["e-s1-deleted"]`)
       and four `.observation(…)` rows (two live `set` rows on `s1`, one `set` on `s3`, and a fourth `set` on `s1`
       whose id is in `deletedEntryIds`), then
       `await engine.restore()` — and then the derivation tests: `testS1100MenuRowsCarryNameCountAndCurrent`
       (asserts `loggedCount` **and** `countLabel`/`nil`), `testS1101EmptyLadderAndNamelessSlot`,
       `testS1102OutOfRangeIndexMarksTheLastRow`, `testS1103JumpMovesTheSessionAndLogsNothing` (asserts the
       index, `WatchLoggingState(engine:).exerciseName`, that `engine.entries.count` is unchanged, and that
       `engine.session?.revision`/record sequence are unchanged), `testS1104JumpToAVanishedSlotChangesNothing`.
       · `WatchMenuTests.swift`, `Fixture A`, `testS1100…`, `testS1101…`, `testS1102…`, `testS1103…`, `testS1104…`
4. [x] In the same file add the picker-mode and action tests: `testS1105AddOnlyRowsDropTheLadder` (Fixture A's
       ladder + fallback {Squat, Pull-up, Dip} → `[Pull-up, Dip]` via `paths.pickerRows(addOnly: true)`, and the
       default property still lists all three ladder rows first), `testS1106PickingAnAddOnlyRowAppendsAndMoves`
       (driving the menu's add path — `paths.addExerciseToSession`/`selectExercise(.available(…))` — and asserting
       slot 4 exists with `currentExerciseIndex == 3`), `testS1107FinishEndsAndOwesTheRating`, and
       `testS1113FinishLeavesNothingToLogInto` (both branches of S-1107/S-1113 through
       `await menu.finish()`; use `preferencesDown(effortRatingPrompt:)` from
       `WatchEffortRatingTests.swift` to set the rating branch).
       · `testS1105…`, `testS1106…`, `testS1107…`, `testS1113…`
5. [x] In the same file add the guard and edge tests: `testS1108TheMenuSourceNamesNoRestEditOrDelete` — read
       `WatchMenu.swift`'s text through the same `Fixtures.sourcesRoot` walk the existing scanners use
       (`WatchSessionEngineTests.swift:330-380`, `WatchRestIsCountUpTests.swift:34`) and assert it contains none of
       `restSeconds`, `plannedDurationMs`, `deleteEntry`, `removeExercise`; then
       `testS1109MenuCountsReadTheCorrectedProjection` (a correction that moves an entry to another slot id moves
       that slot's count), `testS1110ARestIsNotACountedEffort`, `testS1111ASkippedSlotDoesNotShiftTheMark`,
       `testS1112MenuRowsAreDerivedOnEveryRead`.
       · `testS1108…`, `testS1109…`, `testS1110…`, `testS1111…`, `testS1112…`
6. [x] Record the evidence: append the `swift-test` pass/fail counts, the `prove-red` verdict, and one line per
       item above to `2026-10-09-20-watch-menu-plan.evidence.md`; fill `## Progress`; log every guess under
       `## Assumption Log` (decision, options, why).

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` — the whole package suite,
counts pasted into the evidence file.
`.github/copilot/scripts/macos/gateway.sh prove-red HEAD swift-test -- watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` — must FAIL on HEAD
(the types do not exist; a green verdict means the test is not exercising the new code), verdict pasted.
`.github/copilot/scripts/macos/gateway.sh git-diff --name-only` must show only the source paths in the Predicted
Files below (the evidence file, this plan's `## Progress` and its `## Assumption Log` are the non-source edits), and
`WatchConnectivityBridgeTests.swift` must not appear (the existing picker assertions are untouched, S-1105).

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` (new) ·
`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` · `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` ·
`watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` (new) · `2026-10-09-20-watch-menu-plan.evidence.md`

### Phase 2: the wrist surfaces and the docs (@developer)

Six items. WatchOS-only view code plus docs; the app target is compiled by the governor.

1. [x] Create `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` — `#if os(watchOS)`-gated like
       `WatchStartView.swift`, `public struct WatchMenuView: View` taking `state: WatchMenuState` plus
       `onClose: () -> Void` and `onFinish: () -> Void`: a `ScrollView` over `state.rows`, one row per
       `WatchMenuRow` (title `row.name`, subtitle `row.countLabel` when non-nil, the current row marked the way
       `WatchExercisePickerView` marks its own — `WatchStartView.swift:188-230`), wrist-scale spacing (4.0) and a
       `NavigationStack` title reading `"Exercises"`. Tapping a row runs
       `Task { if await state.jump(to: row.slotId) { onClose() } }`. · `WatchMenuView`, `WatchMenuView.body`
2. [x] In the same file add the two actions under the rows: an "Add exercise" row that presents
       `WatchExercisePickerView(paths: state.paths, addOnly: true)` as a **nested** sheet inside the menu (D-1113)
       and whose `onExerciseAdded` dismisses both the picker and the menu through `onClose()`, and a "Finish" row
       that calls a `Task { await state.finish(); onFinish() }` (D-1105, D-1112). `WatchMenuState` must therefore
       expose `paths` (and, if the view needs it, `rating`) as `let` properties. The nested picker's presentation
       flag is `WatchMenuView`'s own `@State` — `WatchMenuState` itself stays stateless (D-1111).
       · `WatchMenuView.addExerciseRow`, `WatchMenuView.finishRow`, `WatchMenuState.paths`
3. [x] Rewire `ios/OmniTrain Watch App/ContentView.swift` for D-1100: rename `@State private var pickingExercise = false`
       (`:176`) to `showingMenu = false`; delete the `.topBarLeading` `WatchEndSessionView` item (`:233-235`) so the
       toolbar holds one control — the `list.bullet` button, whose action (`:236-241`) now sets `showingMenu = true`;
       retarget the sheet (`:244-252`) at
       `WatchMenuView(state: WatchMenuState(engine: host.engine, paths: host.paths, rating: host.rating), onClose: { showingMenu = false }, onFinish: { showingMenu = false; host.noteSurfaceChange() })`
       — the finish nudge is what makes the surface switch, exactly as the old picker's `onExerciseAdded` did — and
       update the `.onDisappear` (`:256`) to clear `showingMenu`. The doc comment above `loggingSurface`
       (`:224-229`, "with the picker one tap away and the package's own End on the same screen") becomes the menu.
       · `WatchAppHost.loggingSurface`, `showingMenu`
4. [x] Delete `WatchEndSessionView` from `WatchEffortRatingView.swift` (`:99`; D-1105) and rename it wherever the
       docs name it — `docs/watch_session_capture.md:229` calls it the End control, so that sentence becomes the
       rating prompt (`WatchEffortRatingView`). Nothing else references it (`grep -rn WatchEndSessionView` leaves
       only the docs and this plan). Must land with item 3: item 3 unmounts the view, item 4 deletes it.
       · `WatchEffortRatingView.swift`, `docs/watch_session_capture.md`
5. [x] Docs. `docs/state_management/watch_surface.md` — in the second-surface paragraph (`:431-439`) the sentence
       "End leading the toolbar and the exercise picker behind a list button" becomes the menu (list button →
       rows, Add exercise, Finish); in the picker paragraph (`:415-429`) delete the trailing narration from
       "Whether a push that lands while the picker is open appears…" through "…WhileTheSessionIsEmpty`." — it is
       duplicated by `WatchStartPaths.swift:170-178` and its cited "step 7 of the push-path walkthrough"
       (`docs/watch-app-setup-and-qa.md:479`) is about changing structure on the wrist, not about a push landing
       in the picker, so the claim is stale. Removing it is what keeps the file from growing toward its 51.2 KB
       ceiling. `docs/watch-app-setup-and-qa.md` — the surfaces list (`:174-176`, "hosts End and the exercise
       picker" → the menu) and walkthrough step 3 (`:576`, "tap End" → tap the `list.bullet` button, then
       **Finish**). `docs/plans/2026-10-08-18-watch-qa-index.md` — the planner linked row 20 to this plan; set its
       status to the landing state only once Phase 2's governor build has passed.
       · `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, `docs/plans/2026-10-08-18-watch-qa-index.md`
6. [x] Record the evidence and hand the build over: append the `swift-test` and docs-contract counts, the
       `git-diff --name-only` listing against the Predicted Files below, and one line per item to
       `2026-10-09-20-watch-menu-plan.evidence.md`; fill `## Progress`; log guesses under `## Assumption Log`;
       state in the evidence file that the watch scheme build (`xcodebuild`, watchOS simulator, the
       `OmniTrain Watch App` target) is the governor's step and has not been run by an agent.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` — green (the watchOS-only
views are not compiled into this target, so this catches the model and any shared edit).
`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` — green (the edited docs still pass the
indexing contract; a walkthrough-narration or roadmap phrase introduced in item 5 fails it).
`.github/copilot/scripts/macos/gateway.sh git-diff --name-only` must list only the Predicted Files below (two source
files, four docs and the evidence file; this plan's own `## Progress`/`## Assumption Log` edits are not source either).
Governor-only, recorded in the evidence file: the watch scheme build with `xcodebuild` — the only check that compiles
`WatchMenuView.swift`, `WatchStartView.swift`, `WatchEffortRatingView.swift` and `ContentView.swift`, and the only
one that can prove acceptance criterion 1 (one toolbar control).

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` (new) ·
`watch/watchos/Sources/WatchSessionEngine/WatchEffortRatingView.swift` · `ios/OmniTrain Watch App/ContentView.swift` ·
`docs/state_management/watch_surface.md` · `docs/watch-app-setup-and-qa.md` · `docs/watch_session_capture.md` ·
`docs/plans/2026-10-08-18-watch-qa-index.md` · `2026-10-09-20-watch-menu-plan.evidence.md`

## Files Affected

- `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` — new (Phase 1)
- `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` — new (Phase 2)
- `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` — add-only mode on `derivePickerRows`/`pickerRows` (Phase 1)
- `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` — `WatchExercisePickerView.addOnly` (Phase 1)
- `watch/watchos/Sources/WatchSessionEngine/WatchEffortRatingView.swift` — `WatchEndSessionView` removed (Phase 2)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` — new, S-1100…S-1113 (Phase 1)
- `ios/OmniTrain Watch App/ContentView.swift` — `loggingSurface` (Phase 2)
- `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, `docs/watch_session_capture.md`,
  `docs/plans/2026-10-08-18-watch-qa-index.md` (Phase 2)
- `docs/plans/2026-10-09-20-watch-menu-plan/2026-10-09-20-watch-menu-plan.evidence.md` (both phases)
- Read-only dependents that must stay green untouched: `WatchConnectivityBridgeTests.swift` (`:690`, `:762`, `:803`),
  `WatchEffortRatingTests.swift`, `WatchSessionEngineTests.swift`, `WatchRestIsCountUpTests.swift`.

## Notes

- **Dependency graph**: Phase 1 → Phase 2 only. Phase 2 compiles against Phase 1's types, so the forward order is the
  only one. Within Phase 2, items 3 and 4 are one landing (item 3 stops mounting `WatchEndSessionView`, item 4
  deletes it); between them the repo still builds and its tests pass, with one dead public view.
- **Intermediate state after Phase 1**: `swift-test` green, `WatchMenu.swift` tested in isolation, and the shipped
  wrist unchanged — End still leads the toolbar and the picker is still behind the list button. That state is
  shippable and invisible to a user.
- **No migration, no wire change**: nothing here touches a persisted field, a `WatchStoreContents` row shape, a
  frame, or `watch/contract/` (D-1108). A wrist on the previous build and a phone on any build interoperate exactly
  as before, so there is no legacy-handling step and no regression fixture for a neighbouring surface.
- **Why the watch-scheme build is the governor's**: the view files are `#if os(watchOS)`-gated, so `swift test` on
  macOS never compiles them; acceptance criteria 1 and 4's dismissal behaviour are provable only by `xcodebuild`
  against a watchOS simulator plus the QA walkthrough.
- **The scanner's path rule**: `Fixtures.sourcesRoot` is derived by walking up from `#filePath`
  (`WatchSessionEngineTests.swift:330-380`); `WatchMenu.swift` must live in `Sources/WatchSessionEngine` or S-1108
  silently passes over an empty file set.
- Any new doc page would need a `docs/README.md` index row and must stay under the 64 KiB per-file ceiling
  (`test/docs_indexing_contract_test.dart`); Phase 2 adds no page, so no index row is expected.

## Code pointers

- `ios/OmniTrain Watch App/ContentView.swift` `loggingSurface` (~line 198): toolbar items + `.sheet(isPresented: $pickingExercise)`.
- `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` `WatchExercisePickerView` (~line 180): rows from `paths.pickerRows`; `select(_:)` calls `paths.selectExercise`.
- `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` `derivePickerRows` (179), `pickerRows` (395), `selectExercise` (406).
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` `entries` (199), `selectExercise(slotId:)` (325), `session` (134).
- `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift` `end()` (148), `canEnd` (137); `WatchEffortRatingView.swift` `WatchEndSessionView` (99).
- Tests: `watch/watchos/Tests/WatchSessionEngineTests/` (harness in `WatchConnectivityBridgeTests.swift:690` shows `harness.paths.pickerRows`).

## Open questions

The planner resolved these by default (see the Assumption Log); each is vetoable before the phase that depends on it.

1. **Do the menu's counts include rest observations?** Default: no — `WatchObservationKind.efforts` only (D-1109).
   Fixture A has no rest, so S-1100 is unchanged either way; S-1110 is the discriminating fixture.
2. **Is `isCurrent` the ladder index or the row's position in the derived array?** Default: the ladder index
   (D-1110), which is what "the engine clamps" means. S-1111 is the fixture that tells them apart.
3. **Does the seeded row shape carry the label text?** Default: `WatchMenuRow` gains a derived `countLabel`
   (D-1114) so the copy is testable on macOS; D-1101's four fields are untouched. Veto if the row must stay
   four fields and the copy be asserted only by the governor's build.
4. **Is the menu a plain `final class` or an `ObservableObject`?** Default: plain, reading `revision`, exactly as
   `pickerRows` does (D-1111). Veto if the host should hold the menu as an `@StateObject`.
5. **`docs/state_management/watch_surface.md:423` cites "step 7 of the push-path walkthrough" for an owner check about a
   push landing while the picker is open; step 7 (`docs/watch-app-setup-and-qa.md:479`) is "Try to change structure on the
   wrist".** The citation is stale, and Phase 2 item 5 deletes the sentence rather than correcting it, under the
   file's 51.2 KB ceiling. Veto if the narration should be repaired to point at the real owner check instead.
6. **D-1105 removes `WatchEndSessionView` outright.** Default: delete, since the action survives as Finish.
   Veto if the view should be kept as a deprecated alias.
7. **`docs/plans/2026-10-08-18-watch-qa-index.md` row 20's status wording.** Default: the planner linked the row to this
   plan and set it to `planned — @developer Phase 1`; the implementer flips it to the landing state only after Phase 2's
   governor build has passed.

## Progress

| Phase | Status |
|---|---|
| 1 | Complete |
| 2 | Complete |

Item results (implementers append one line per item: item, what changed, result):

- P1.1 — `WatchMenu.swift` created: `WatchMenuRow` (`slotId`/`name`/`loggedCount`/`isCurrent`, `countLabel` nil at zero), `deriveMenuRows` (skips `WatchCatalogExercise(slot:)` rejects, counts `efforts` on the slot's id, marks the clamped ladder index) and `WatchMenuState` (`rows` derived per read, `jump(to:)` through `paths.pickerRows` + `selectExercise`, `finish()` → `rating.end()`). Result: green, 14/14.
- P1.2 — `derivePickerRows` gained `addOnly: Bool = false` (drops `.inSession`, still fills `onLadder`); `pickerRows(addOnly:)` added beside the untouched `pickerRows` property; `WatchExercisePickerView` gained `addOnly` before the trailing closure and reads `paths.pickerRows(addOnly: addOnly)`. Result: `WatchConnectivityBridgeTests.swift` absent from `git-diff --name-only` — its three assertions are untouched.
- P1.3 — `WatchMenuTests.swift` created with the `WatchMenuHarness`/Fixture A builders in the `WatchStartHarness` shape and S-1100…S-1104. Result: 5 tests green.
- P1.4 — S-1105…S-1107 and S-1113 added (add-only rows, the pick's append-and-move, both branches of Finish). Result: 4 tests green.
- P1.5 — S-1108 (source-token scan through `Fixtures.sourcesRoot`) and S-1109…S-1112 added. Result: 5 tests green.
- P1.6 — evidence appended: `403 tests / 0 failures`, the `prove-red` verdict, the seven mutation verdicts. Result: done.
- P2.1 — `WatchMenuView.swift` created (`#if os(watchOS)`): a `NavigationStack` titled "Exercises" over a `ScrollView` of one `Button` per `WatchMenuRow` — current `.borderedProminent`, the rest `.bordered`, the name with `countLabel` as a `.footnote` line — at wrist-scale 4.0 spacing. Result: `swift-test` green; the file is lexed by the target (`Compiling WatchSessionEngine WatchMenuView.swift`), its body is watchOS-only.
- P2.2 — The same file's `addExerciseRow` (nested `WatchExercisePickerView(paths:rev:, addOnly: true)` sheet; a pick clears the flag and calls `onClose()`) and `finishRow` (`await state.finish()` then `onFinish()`); the sheet flag is the view's own `@State`, so `WatchMenuState` stays stateless. Result: green.
- P2.3 — `ContentView.swift`: `pickingExercise` → `showingMenu`; the `.topBarLeading` `WatchEndSessionView` removed so the toolbar holds the one `list.bullet` button setting `showingMenu = true`; the sheet presents `WatchMenuView(state: WatchMenuState(engine:paths:rating:), revision:, onClose:, onFinish:)` with both closures `{ showingMenu = false; host.noteSurfaceChange() }`; `.onDisappear` clears `showingMenu`; the `loggingSurface` doc comment describes the menu. Result: governor's build is this target's only compile.
- P2.4 — `WatchEndSessionView` deleted from `WatchEffortRatingView.swift` (header retitled "the effort-rating prompt") and `docs/watch_session_capture.md`'s "The prompt and End views" row reduced to "The prompt view" / `WatchEffortRatingView`. Result: `grep -rn WatchEndSessionView` leaves no source or doc-set hit.
- P2.5 — `docs/state_management/watch_surface.md`: the second-surface clause names the list button and the menu (rows, Add exercise, Finish) and the stale "step 7 of the push-path walkthrough" narration is deleted; `docs/watch-app-setup-and-qa.md`: the surfaces list names the menu and walkthrough step 3 taps the list button then **Finish**. Result: docs contract 9/9 green; net −11 lines, `watch_surface.md` shrunk.
- P2.6 — evidence appended (counts, diff listing, the governor-build note); plan filled. Result: done.

## Assumption Log

Planner (ratified into the Ledger, still vetoable — see Open questions): D-1109 counts `efforts` only because a rest
shares its slot's `sessionExerciseId`; D-1110 marks the ladder index, not the derived position; D-1111 caches nothing
and reads `revision`; D-1114 puts `countLabel` on the row so the copy is testable. Executors append below —
decision, options considered, rationale.

- S-1103's "record sequence unchanged" read as the observation entries': a jump reuses `selectExercise`, which appends a
  session row, so the *session* row's sequence does increment. Asserted instead: entry `recordId`s and entry `sequence`s
  unchanged, session `revision` unchanged, ladder count unchanged. The alternative (asserting the session row's sequence)
  would contradict D-1103's reuse of the select path.
- `WatchMenuState` exposes `paths` and `rating` as public `let` (the brief's addition) so Phase 2 can mount the add-only
  picker and the rating prompt without a second injection point. `jump(to:)` kept `@discardableResult` so the view call
  site stays a plain `await menu.jump(to: row.slotId)`; the plan's `Bool` return is unchanged.
- `WatchExercisePickerView`'s new `addOnly` sits **before** the trailing closure with default `false`, so every existing
  call site (and `WatchConnectivityBridgeTests.swift`) compiles unchanged. `paths.pickerRows` was left as a direct
  `derivePickerRows(...)` call — "exact signature" read as signature and behaviour, not as forbidding a shared helper.
- No doc update in Phase 1: the menu and the picker's new mode reach no surface yet; Phase 2 owns
  `docs/navigation_and_screens.md` and the watch docs. Recorded as N/A for this phase, not as an omission.
- Phase 2 item 5's deletion scope: the plan ranged the cut from "Whether a push that lands…" through
  "…WhileTheSessionIsEmpty`", but the brief names only the stale "step 7 of the push-path walkthrough" sentence, and
  the rest of the range is the row-keyed-by-slot-id invariant with its live verified-by citation. Read as the brief
  (delete the narration sentence alone), which still shrinks the file — the alternative would delete verified behaviour.
- `WatchMenuView`'s fixed copy (D-1114) lives in `static let` constants on the view (`title`, `addExerciseLabel`,
  `finishLabel`) rather than inline literals, so the governor's build reads one definition; the values are the plan's
  literals verbatim. The nested picker's sheet hangs off the menu's `NavigationStack` and the add path clears the view's
  own flag before `onClose()`, so both presentations die with the one callback (D-1113).
- `ContentView`'s `onClose` nudges the host (`showingMenu = false; host.noteSurfaceChange()`) on the row-jump path too,
  not only the add path: the picker it replaces nudged on every pick, and a jump moves `currentExerciseIndex` without
  the logging view's own `@Published` firing. Follows the brief's `onClose` wording and keeps the old surface refresh.
- `docs/navigation_and_screens.md` needs no edit: it carries no watch surface row (`grep -n Watch|End` finds only the
  Flutter `StartupFailureScreen`), and Phase 2's Predicted Files do not list it.
- Fix pass (review findings 1/4/7, `brief-fix-1.md`): S-1108 also scans `WatchMenuView.swift`; the watch QA walkthrough's
  wrist-end wording is Finish; and `pickerRows` now delegates to `pickerRows(addOnly: false)` — the earlier bullet above
  about it calling `derivePickerRows` directly is superseded.

## Feedback

[empty — a human move here is what re-invokes the planner]
