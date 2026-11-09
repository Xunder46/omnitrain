# Plan 31: watch QA fixes, round 3 (rest menu, one exercise list, jump that lands, spacing, live heart rate)

> Status: Iteration 1 active — expanded by the planner, 2026-10-13; fix round 1 applied, 2026-10-14. Seeds
> (D-3101…D-3108, S-3101…S-3110, the three-row phase table) are kept exactly as the governor wrote them; the
> planner appended D-3109…D-3116, S-3111…S-3113 and four executable phases, and fix round 1 appended D-3117,
> D-3118 and S-3114 (the review's two blockers: the duplicate scroll id and the interval-less heart-rate read).
> Next handoff: @code-reviewer (Phase 2A)
> Binding conventions: `docs/global_conventions.md`; also `docs/documentation_standard.md` (doc rules),
> `docs/app_philosophy.md` (UX principles), `docs/state_management/watch_surface.md` and
> `docs/state_management/watch_reference_data.md` (the watch surface and its reference data).
> Evidence file for every phase: `docs/plans/2026-10-13-31-watch-qa-fixes-3-plan/2026-10-13-31-watch-qa-fixes-3-plan.evidence.md`.

## Overview

Five owner findings from a real wrist session, all inside the watch app: the live heart-rate readout stops
moving, the session menu cannot be opened from the rest screen, the free session's first-exercise picker does
not look like the menu's Add Exercise list, a letter jump lands off-target (worse the further the letter), and
the extra menu gap sits below Add Exercise instead of above it. Scope is the Swift package `watch/watchos` plus
the app target `ios/OmniTrain Watch App`; nothing on the wire, in the store, on the phone or on Wear changes.
Three of the five are proven by tests in the package; the app target has no test target and cannot be built by
an agent check, so its two edits are held by source scans plus the owner's device checks. Phase 3 is
diagnose-then-fix: the package chain is measured first, and only if it is green does the app-target pull apply.

Base: `.work/2026-10-13-31/base.txt` (0da2a72). Track: watch only (Swift package `watch/watchos` + the app target
`ios/OmniTrain Watch App`). No wire, store, phone or Wear change. Owner QA, 2026-10-13, a real training session.
Earlier rounds: 23a, 23b, 23c, 23e1-23e3 (`docs/plans/2026-10-11-*`).

## Goal and acceptance (what the owner sees)

1. **Heart rate keeps moving.** During a run the number on the logging screen follows the wrist's sensor every few
   seconds, also after the wrist was lowered and raised again. (Owner device check; see Open questions.)
2. **The menu is reachable from the rest screen.** The rest screen has the same list button (top right) as the
   logging screen. It opens the same menu. Jumping to an exercise or adding one from there returns to the REST
   screen, the rest keeps counting, and the rest ends only by Next or by logging/starting the next effort
   (existing behaviour). End Session works from there too.
3. **One exercise list.** The first-exercise picker of a free session (empty session) shows the same A-to-Z list with
   the same letter grid on top as the menu's Add Exercise list: one shared component, two entry points.
4. **Jump to letter lands on that letter.** Tapping any letter puts that letter's first exercise at the top of the
   list with its options visible below it: not at the bottom of the list (T), not on a later letter (W lands on Z).
   Same result for near and far letters. The last letters with few rows show their rows at the bottom.
5. **Menu spacing.** The extra gap sits between the horizontal line and Add Exercise, not between Add Exercise and
   End Session; those two sit at the normal row spacing.

## Decision ledger

- D-3101 (item 5) `WatchMenuView.body` (`watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` ~81-86):
  currently `Divider()`, `addExerciseRow`, `finishRow.padding(.top, 10)`. Remove the `.padding(.top, 10)` from
  `finishRow`; put `.padding(.top, 10)` on `addExerciseRow`. Nothing else in the menu changes.
- D-3102 (item 2) The menu button and sheet move to the root. `ios/OmniTrain Watch App/ContentView.swift`:
  `loggingSurface` (~278) owns the `list.bullet` toolbar item and the `.sheet(isPresented: $showingMenu)` today;
  the `host.logging.isResting` branch (~227) renders a bare `WatchRestView`. After: the rest branch is wrapped in a
  `NavigationStack` with the same toolbar button, and the one `WatchMenuView` sheet is built by one shared helper
  used by both surfaces (no second copy of the `WatchMenuState(...)` construction). The sheet must not vanish
  because a rest ends underneath it (host the sheet where it survives the rest/logging switch, or equivalent); it
  still closes when no session is active (the existing `.onDisappear { showingMenu = false }` intent).
  No change to `WatchRestView`'s Next, ping or timer.
- D-3103 (item 2) Rest is untouched by the menu: `WatchMenuState.jump(to:)` (`WatchMenu.swift` ~249) is gated only
  by `isLocked` (work clocks: elapsed, hold, round), never by a rest; `engine.selectExercise`
  (`WatchSessionEngine.swift` ~325) and `paths.addExerciseToEnd` (`WatchStartPaths.swift` ~610) do not stop any
  timer; `WatchLoggingState.isResting` (~333) stays true; `log()` (~739) and `startWork()` (~414) end the rest.
  This is existing behaviour that the owner's request depends on: pin it with tests (S-3101, S-3102), do not
  change it.
- D-3104 (items 3, 4) A pure grouping function in the package: `deriveExerciseSections(_ exercises:
  [WatchCatalogExercise]) -> [WatchExerciseSection]` (new, next to `deriveAddExerciseLetters` in `WatchMenu.swift`),
  `WatchExerciseSection: Equatable { letter: String; exercises: [WatchCatalogExercise] }`. Keys come from the
  existing `addExerciseLetterKey(of:)` (`WatchMenu.swift` ~80); sections follow the input order, which for the
  list is `addableExercises` (A to Z, `#` first, accented last). The letters of the grid stay
  `deriveAddExerciseLetters` / `WatchMenuState.addExerciseLetters` (threshold 20, unchanged) and must equal the
  section letters in the same order (S-3105).
- D-3105 (items 3, 4) One shared view, new file `watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift`
  (`#if os(watchOS)`), `WatchExerciseLetterList`: takes the sections, the letters, an optional list of leading rows
  (the free picker's in-session rows, shown first, prominent), the empty-text, and an `onPick(exercise)` closure.
  Both `WatchAddExerciseList` (inside `WatchMenuView.swift`) and `WatchExercisePickerView` (`WatchStartView.swift`
  ~188) render it; the two files keep only their own action (menu: `state.addExercise` + `onAdded` + dismiss;
  picker: `paths.selectExercise`, which moves to the exercise when it is on the ladder and appends otherwise).
  `WatchMenu.swift`/`WatchMenuView.swift` must still not name `WatchExercisePickerView` or `pickerRows`
  (`WatchMenuTests.testS3617`, source scan): the shared view takes plain data, so it stays true.
- D-3106 (item 4) Why the jump misses today: `WatchAddExerciseList.body` (`WatchMenuView.swift` ~198-258) puts the
  letter grid and ALL rows in one `LazyVStack` and calls `proxy.scrollTo(letter.firstExerciseId, anchor: .top)`.
  A lazy stack has not measured the rows it has not built, so a far target is placed by an estimate, and the error
  grows with distance. The fix must not depend on estimates of unbuilt rows. Required shape: one section per
  letter in a `List` (`Section` with a header carrying the letter, and `.id(letter)` on the section header), the
  letter button scrolls to that id with `anchor: .top`, no animation. The developer may choose another mechanism
  only if it keeps the two guarantees of item 4 and the evidence says why; both entry points use the same one.
- D-3107 (item 1) Heart rate: the readout is a pure function of the newest stored row
  (`WatchSensorRecorder.readings` -> `engine.newestSensorSamples()`), re-read every second by
  `WatchLoggingModel.poll()`. That chain is tested only with a hand-fed source. Phase 3 is diagnose-then-fix:
  first a package test that feeds a rising sequence of beats through a fake `WatchSensorSource` ->
  `WatchSensorRecorder` -> `WatchLoggingState.heartRateLabel` and a second that does the same through
  `FileWatchSessionStore` (the real store), asserting the label follows each beat. If either is RED, that is the bug:
  fix it in the package. If both are GREEN, the beats stop upstream, in the app target, and D-3108 applies.
- D-3108 (item 1) App-target hardening (cannot be executed by `swift test`; guarded by source scans like
  `WatchSensorSourceSourceTests`, executed by the owner on the wrist). `HealthKitSensorFeed`
  (`ios/OmniTrain Watch App/HealthKitSensorFeed.swift`) today yields a beat only inside
  `workoutBuilder(_:didCollectDataOf:)` (~136). Add a pull: while at least one heart-rate subscription is live, the
  feed also reads `builder.statistics(for: heartRate)?.mostRecentQuantity()` every 3 seconds and when the app
  becomes active, and yields it only when `mostRecentQuantityDateInterval?.end` is newer than the last beat it
  yielded (so a repeated read is never a second row). The builder reaches the feed from `HealthKitWorkoutStore.begin`
  (~101-125, where `collection.delegate = sensorFeed` is set) and is dropped in `end()`. The delegate path stays.
  The pull stops with the last subscription (no timer outlives a session).

### Appended by the planner (the seeds above are unedited)

- D-3109 (item 2, derived from the seed — **supersedes the last clause of S-3102**; see Open questions 1).
  `WatchLoggingState.log()` does not leave the session unrested: it stops the rest running at the logged instant
  (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:740`) and then starts the next one itself
  (`:746` `startFollowOnTimer()`, `:943-945`), so `isResting` (`:332-337`) reads `true` again. The seeded
  clause `isResting == false` is therefore not executable. Ruling, binding on Phase 1: the promise it encodes
  is kept and measured as **"the rest that was running is closed at the logged instant and a new rest row
  runs"**, which S-3111 asserts. `log()` and `startWork()` (`:410-414`) do not change.
- D-3110 (items 3, 4 — fills in D-3104). `WatchExerciseSection`/`deriveExerciseSections(_:)` live in
  `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift`, appended after `deriveAddExerciseLetters` (~110):
  pure, no sorting, one pass over the input grouping by the existing `addExerciseLetterKey(of:)` (`:80`), so the
  concatenation of the sections' exercises equals the input **exactly**, `#` first and accented names last when
  the input is `addableExercises`. The menu exposes it as `WatchMenuState.addExerciseSections` next to
  `addExerciseLetters` (`:274-283`). **One threshold site**: a new
  `deriveExerciseListLetters(_ exercises: [WatchCatalogExercise]) -> [WatchAddExerciseLetter]` in the same file
  returns `exercises.count > WatchMenuCopy.addLetterGridThreshold ? deriveAddExerciseLetters(exercises) : []`,
  and `WatchMenuState.addExerciseLetters` becomes `deriveExerciseListLetters(addableExercises)`, so the literal
  `20` (`WatchMenuCopy.addLetterGridThreshold`, `:134`) keeps exactly one definition and one reader. The shared
  view and the picker both call that helper — never `WatchMenuCopy.addLetterGridThreshold` directly.
- D-3111 (item 3, derived). `WatchStartPaths.pickerRows` (`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift:574-582`)
  passes `fallback: addableExercises` instead of `fallback: fallbackExercises` — one word — so the rows the
  picker offers as available are in **A-to-Z order, the same order the menu's Add Exercise list uses**. The
  ladder's own rows stay first and in ladder order, and the dedup by `exerciseId` (`derivePickerRows`, `:179-201`)
  is untouched. New next to `pickerRows`: `availablePickerExercises: [WatchCatalogExercise]` =
  `addableExercises` minus the exercise ids the ladder holds, in `addableExercises` order, so
  `pickerRows.filter { !$0.isInSession }.map(\.exerciseId) == availablePickerExercises.map(\.exerciseId)` is an
  identity (S-3113) and the picker's grid gate (D-3110) reads the rows it actually offers. The change is a
  re-order of the same data, not a new capability. Two existing tests assert the old order and **must be
  updated, never deleted** (Phase 2A item 6).
- D-3112 (items 3, 4 — the API D-3105 leaves free). `WatchExerciseLetterList` takes plain data:
  `leading: [(slotId: String, exercise: WatchCatalogExercise)]` (empty for the menu), `sections:
  [WatchExerciseSection]`, `letters: [WatchAddExerciseLetter]`, `emptyText: String`,
  `onPickLeading: (String, WatchCatalogExercise) -> Void`, `onPick: (WatchCatalogExercise) -> Void`. It draws
  **one `List`**, one `Section` per entry, `.id(section.letter)` on the letter's `Section` header, the letter
  grid as the list's first row (drawn with a `LazyVGrid`, scrolls with the content, exactly as today),
  `scrollTo(letter, anchor: .top)`, no animation. The leading rows are the picker's in-session rows, drawn first
  and prominent. Its own file `watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift` under
  `#if os(watchOS)`. Two rules bind it: no `LazyVStack` anywhere in it or in either entry point, and **no method
  declared at four-space indentation whose name starts with the append-only verbs** —
  `WatchSessionEngineTests.swift:335-370` rejects `func set|update|clear|remove|write|reset|forget|…` in *every*
  file under `Sources/`, so no `setScroll`/`updateRows`/`clearSelection` helper.
- D-3113 (item 1 — fills in D-3108). The app-target pull is pinned by name: `private let heartRatePullSeconds:
  TimeInterval = 3` and `private var lastHeartRateEnd: Date?` in
  `ios/OmniTrain Watch App/HealthKitSensorFeed.swift`; the pull starts when the first heart-rate subscription is
  taken in `heartRate()` (~94-107) and is cancelled from its `onTermination` when
  `heartRateContinuations.isEmpty` becomes true (so no timer outlives a session); each tick — and each app
  activation — reads `builder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()` and yields it
  through the existing `yieldHeartRate` (~184) **only** when `mostRecentQuantityDateInterval?.end` is strictly
  newer than `lastHeartRateEnd` (a repeated read is never a second row). No `HKAnchoredObjectQuery`, no history
  query, no new dependency, and `workoutBuilder(_:didCollectDataOf:)` (~136) stays as the push path. The store
  gains `func refreshHeartRate()` (`HealthKitWorkoutStore.swift`, `sensorFeed.refreshHeartRate(from: builder)`),
  `WatchAppHost` (in `ContentView.swift`) keeps the store it already constructs (~92) so
  `ContentView`'s existing `.onChange(of: scenePhase)` activation branch (~257-258) can call it next to
  `catchUpOnActivation()`.
- D-3114 (item 2 — the seed's "or equivalent" in D-3102). The one `.sheet(isPresented: $showingMenu)` and the
  one `WatchMenuState(...)` construction (`ContentView.swift:293-295` today) are hoisted out of
  `loggingSurface` (~278-314) into **one** `menuSheet` helper applied to the root `Group` (`:224`), where
  neither the rest↔logging switch nor a rest ending can tear it down. The sheet closes when no session is
  active: `.onChange` on the host's session status clears `showingMenu`, and `.onDisappear { showingMenu =
  false }` (`:314`) goes away because its intent has moved. Each surface keeps its own
  `Image(systemName: "list.bullet")` toolbar button; the rest branch (`:227-233`) is wrapped in its own
  `NavigationStack` for it. Only the *sheet* is shared; the button text is deliberately duplicated (see Open
  questions 3). `WatchRestView`'s Next, ping and timer are untouched.
- D-3115 (all phases — docs). Docs trail code by zero phases: `docs/state_management/watch_surface.md` (the one
  list button and the picker's order sentence, ~432-476 and ~434), `docs/state_management/watch_reference_data.md`
  (`addableExercises` A-to-Z and `addLetterGridThreshold` 20, ~113-117) and `docs/watch-app-setup-and-qa.md`
  (the device steps 10-14 at ~712-790; device-only lines marked **(owner)**). No new doc page, no `docs/README.md`
  change, and every phase that edits an indexed doc runs `test/docs_indexing_contract_test.dart`:
  `docs/state_management/watch_surface.md` is 737 lines and estimated ~56 KB, which is above the 52 KB advisory
  band and below the 64 KiB ceiling, so a phase adds at most ~12 lines to it and, if the contract test reds,
  moves the section to a part page instead of growing it.
- D-3116 (all phases — test naming, so no implementer has to research it). The scenario ids S-3100…S-3117 are
  already taken by earlier plans (`WatchSensorCoordinatorTests.swift:13-25`, `WatchSensorSourceSourceTests.swift:5-18`),
  so the new test methods carry the file's own `A`-suffix idiom and are named exactly:
  `testS3101AJumpDuringARestKeepsTheRestRunning`, `testS3102AAddingAnExerciseDuringARestKeepsTheRestRunning`,
  `testS3103ATheRestScreenCarriesTheMenuButton`, `testS3104ATheMenuGapSitsAboveAddExercise`,
  `testS3105ASectionsFollowTheListAndTheLettersAgree`, `testS3106AOneListServesBothEntryPoints`,
  `testS3107ATheFreePickerOffersTheAvailableExercisesAToZ`, `testS3108ATheLetterGridAppearsOverTwentyRows`,
  `testS3109ATheLabelFollowsEveryBeat`, `testS3110ATheFeedPullsTheNewestBeatWhileAListenerWaits`,
  `testS3111ALogClosesTheRunningRestAndStartsTheNext`,
  `testS3112ATheStoreAndTheHostRefreshTheHeartRateOnActivation`,
  `testS3113AThePickerRowsAndTheAvailableExercisesAgree`. Each touched test file's header gains a
  `// Plan: docs/plans/2026-10-13-31-watch-qa-fixes-3-plan/…` citation block next to the ones already there
  (`WatchSensorSourceSourceTests.swift:7-18` shows the shape). Renumbering to a free block is Open question 2.
- D-3117 (all phases — the scroll id a repeated key's runs carry; fix round 1 of the review). One `ScrollViewReader`
  holds one view per id, but a key opens more than one `Section`: `deriveExerciseSections` groups runs, and a name
  the sort put under a digit sorts before `A` while a `~` name sorts after `Z`, so `#` can open twice (S-3105,
  `testS3908`). The rule is a pure function next to `deriveExerciseSections` in `WatchMenu.swift` —
  `scrollTargetLetters(of:) -> [String]`, the first run of every key, once each, in the sections' own order — and the
  shared list takes its ids from it and from nothing else (`scrollIdsBySection()` consumes that list in order, and a
  run the list did not name renders its header with no `.id`). A tap on a grid entry therefore lands on the first
  run the entry points at. S-3114 pins the rule and the view's use of it.
- D-3118 (all phases — a heart-rate read whose sample end is unknown; fix round 1 of the review). `HKStatistics`
  answers `mostRecentQuantityDateInterval()` as an optional (a builder that has collected nothing, a sample since
  deleted), and `Date()` is not a substitute for a missing end: it would stamp the reading with the moment of the
  read, so the pull's next tick would read the same sample as newer than the mark it just wrote and log a duplicate
  row. The rule: the **pull** path drops the beat (no end to compare, so nothing to gate on), and the **push** path
  yields it ungated through `yieldHeartRate`, because a push is one delivery of one reading and cannot repeat on a
  timer. `yieldHeartRateIfNewer` is the gate a read goes through only when its end instant is known (D-3113, S-3110).

## Scenarios (tests first; each must fail without the change; harness in the named file)

- S-3101 (`WatchMenuTests.swift`, harness `WatchMenuHarness`) With a rest running (`isResting == true`, after a
  logged set), `menu.jump(to:)` another slot returns true, the session's current exercise changes, and
  `logging.isResting` is still true with the same rest timer record. Pins D-3103. (Expected GREEN at base: a guard,
  proven by mutation: making `jump` call `endRest` turns it red.)
- S-3102 (same) With a rest running, `menu.addExercise(x)` returns true, the ladder grows by one at the end, the
  current exercise is unchanged and `isResting` is still true. Then `logging.log()` for the next set ends the rest
  (`isResting == false`, one rest observation emitted). Mutation: `addExerciseToEnd` stops the rest -> red.
- S-3103 (same, source scan of `ios/OmniTrain Watch App/ContentView.swift`, comment lines stripped, like
  `WatchSensorSourceSourceTests.source(_:)`) The `isResting` branch contains a `NavigationStack` and the
  `list.bullet` button; `WatchMenuState(` appears exactly once in the file. Red at base (no button in the rest
  branch; the construction appears once but inside the logging surface only: assert the rest branch text).
- S-3104 (same, source scan of `WatchMenuView.swift`) `finishRow` is not followed by `.padding(.top`; `addExerciseRow`
  is. Red at base (padding is on `finishRow`).
- S-3105 (`WatchMenuTests.swift`) 120 mixed names (digits, symbols, mixed case, one accented, a name with leading
  space): `deriveExerciseSections(menu.addableExercises)` has one section per key, in list order, the concatenation
  of the sections' exercises equals `addableExercises` exactly (nothing dropped or duplicated), the first exercise of
  each section equals `addExerciseLetters[i].firstExerciseId`, and the letters equal `addExerciseLetters.map(\.letter)`.
- S-3106 (`WatchMenuTests.swift`) Both entry points share the component: a source scan finds
  `WatchExerciseLetterList` in `WatchMenuView.swift` and in `WatchStartView.swift`, and finds `LazyVStack` in neither
  (the lazy stack is the cause named in D-3106). Red at base.
- S-3107 (`WatchSessionStartPathsTests.swift`) The free picker's list for an empty session: the available exercises
  the picker offers are `addableExercises` in A-to-Z order (it was the phone's fallback order), and an exercise
  already on the ladder is still offered once, as its in-session row, not again as available.
- S-3108 (`WatchMenuTests.swift`) Threshold unchanged: 20 exercises -> no letters and the shared list shows no grid
  input; 21 -> letters. (Existing S-3902 keeps passing.)
- S-3109 (`WatchSensorRecordingTests.swift`) Feeding 100, 104, 109, 115 through `WatchSensorRecorder` with a fake
  source and a real `WatchSessionEngine` over `FileWatchSessionStore` (temp directory) makes `readings.heartRate`
  and `WatchLoggingState.heartRateLabel` read "100", "104", "109", "115" in turn. (Diagnostic, D-3107: its colour
  at base decides whether D-3108 is the whole fix.)
- S-3110 (`WatchSensorSourceSourceTests.swift`, source scan of `HealthKitSensorFeed.swift`) The feed has a pull that
  reads `mostRecentQuantity`, compares `mostRecentQuantityDateInterval`, and is cancelled when the last heart-rate
  listener goes (`onTermination` removes the id and stops the pull when `heartRateContinuations` is empty); the
  store hands the builder to the feed in `begin` and clears it in `end`. Red at base.

### Appended by the planner

### S-3111: A log closes the rest it was logged into and starts the next
- Fixture: `WatchMenuTests.swift`, class `WatchMenuHarness` (`:105`), store `InMemoryWatchSessionStore`, a
  started session with ladder slots `sx-bench` and `sx-plank`; a `WatchLoggingState(engine:clock:)` built inline
  exactly as `testS1307ARunningRestDoesNotLockTheMenu` (`:547`) builds it; the clock from the file's harness at
  `t0`; the first set logged at `t0` so a rest is running, then the clock advanced to `t0 + 30`.
- Trigger: `logging.log()` once, at `t0 + 30` (the next set).
- Flow: `WatchLoggingState.log()` stops the rest running since `t0`, emits that rest's observation, then
  `startFollowOnTimer()` (`:746`, `:943-945`) starts a rest at `t0 + 30`.
- Expected outcome: the rest that was running is closed at the logged instant (it is no longer the newest timer
  and its duration does not keep growing — the shape `WatchLoggingTimersTests.testS321` already pins; the
  developer copies that test's expected emitted kinds and counts into the evidence file rather than trusting this
  paraphrase), a **new** rest row started at `t0 + 30` is the newest timer, and `isResting` reads `true`. This is
  D-3109's executable form of S-3102's last clause. Mutation: deleting the `startFollowOnTimer()` call, or
  stopping the rest without closing it, turns it red.
- Edge case of: S-3102.

### S-3112: The app target reads the builder on activation as well as on a tick
- Fixture: `WatchSensorSourceSourceTests.swift`; the comment-stripped text of
  `ios/OmniTrain Watch App/HealthKitSensorFeed.swift`, `HealthKitWorkoutStore.swift` and `ContentView.swift`,
  read through that file's own `feedSource()`, `storeSource()` and `viewSource()` helpers (they already blank
  `//`-only lines and trailing comments).
- Trigger: none — a source scan.
- Flow: read the three files and look for the D-3113 tokens.
- Expected outcome: `HealthKitSensorFeed.swift` contains `heartRatePullSeconds`, contains
  `mostRecentQuantityDateInterval`, and cancels the pull at a site where `heartRateContinuations.isEmpty` is
  tested inside an `onTermination`; `HealthKitWorkoutStore.swift` contains `func refreshHeartRate(` and passes
  `builder` to the feed from it; `ContentView.swift` contains `refreshHeartRate(` inside the existing
  scene-phase activation handler (`.onChange(of: scenePhase)`, `:257-258`). Red at base — none of the three
  tokens exists.
- Edge case of: S-3110.

### S-3113: The picker's two lists agree, and its grid gate counts the rows it offers
- Fixture: `WatchSessionStartPathsTests.swift`, harness `WatchStartHarness` (`:61`), the contract read through
  the file's own `startContract()` (`:151`). Three fixture states, all on an empty free session unless stated:
  (a) the contract's own `routines_down` — `fallback.expected` is `[ex-plank, ex-goblet-squat,
  ex-barbell-bench-press, ex-pull-up]` in that order (`watch/contract/watch_start_paths_contract.json:83-88`)
  and the A-to-Z reading of it is `[Barbell Bench Press, Goblet Squat, Plank, Pull-Up]`; (b) a `routines_down`
  built the way the file's existing modified-catalog helper (~`:237-251`) builds one, carrying 21 fallback
  exercises with 21 distinct first letters (`ex-l01`…`ex-l21`, names `Alpha`…`Uniform`), no routines;
  (c) the same 21-exercise catalog with `ex-l01` added to the session through `addExerciseToSession`, leaving 20
  available rows.
- Trigger: read `paths.pickerRows`, `paths.availablePickerExercises` and
  `deriveExerciseListLetters(paths.availablePickerExercises)` after each message has been applied.
- Flow: compare the two lists, then the letters.
- Expected outcome: in all three states `pickerRows.filter { !$0.isInSession }.map(\.exerciseId)` equals
  `availablePickerExercises.map(\.exerciseId)`; in (a) that list reads exactly `[ex-barbell-bench-press,
  ex-goblet-squat, ex-plank, ex-pull-up]`; in (b) the letters are non-empty and start with `"A"`; in (c) the
  letters are empty while `pickerRows` still holds `ex-l01`'s in-session row first. Red at base (no
  `availablePickerExercises`, and (a) reads the phone's fallback order today).
- Edge case of: S-3107.

### S-3114: One key that opens two runs carries one scroll id
- Fixture: `WatchMenuTests.swift`, harness `WatchMenuHarness`, on the file's own `letterCatalogNames` (25 names,
  `Alpha`…`Whiskey`) plus `"3x3 press"` and `"~stretch"`, applied through `harness.applyLetterCatalog`, so the sorted
  list opens `#` twice — the digit name first, the tilde name last — with `A`…`W` between the two runs.
- Trigger: `scrollTargetLetters(of: deriveExerciseSections(harness.menu.addableExercises))`.
- Flow: read the sections, then the letters that carry an id.
- Expected outcome: the fixture really opens two `#` sections of one exercise each (`"3x3 press"` first, `"~stretch"`
  last); the targets hold `#` exactly once; no target repeats; the targets equal `harness.menu.addExerciseLetters`
  mapped to their letters; and each key's letter is taken from its first run — as is the shared view, which the test
  also asserts by reading `WatchExerciseListView.swift` for `scrollTargetLetters(of:`. Red at base: the rule is new
  code, so the proof is a mutation — returning every section's letter reddens four assertions (`#` twice, a repeated
  id, the grid agreement, the first-run rule).
- Edge case of: S-3105.

## Phases (one agent run each; none over 8 items)

| # | Agent | Goal | Code pointers |
|---|---|---|---|
| 1 | developer | Items 5 and 2: menu spacing (D-3101), the rest screen's menu (D-3102), pins S-3101..S-3104 | `WatchMenuView.swift` ~81-86; `ContentView.swift` ~223-316; `WatchMenuTests.swift` |
| 2 | developer | Items 3 and 4: sections function, shared list view, both entry points, S-3105..S-3108 | `WatchMenu.swift` ~85-110, ~269; `WatchMenuView.swift` ~178-259; `WatchStartView.swift` ~188-250; new `WatchExerciseListView.swift` |
| 3 | developer | Item 1: S-3109 first (diagnose), then the package fix if red, then D-3108 + S-3110 | `WatchSensorRecording.swift` ~100-215; `HealthKitSensorFeed.swift` ~48-200; `HealthKitWorkoutStore.swift` ~93-158 |

Docs each phase touches: the page that describes the menu / rest screen / picker (`grep -n "Add Exercise\|rest screen"
docs/state_management/watch_*.md docs/watch-app-setup-and-qa.md docs/rest_tracking.md`), and one owner QA line per
device-only behaviour in `docs/watch-app-setup-and-qa.md` marked **(owner)**.

## Acceptance Criteria (each maps to at least one scenario)

| # | Seeded acceptance | Scenarios | Ledger | Owner check |
|---|---|---|---|---|
| AC-1 | The heart rate keeps moving | S-3109, S-3110, S-3112 | D-3107, D-3108, D-3113 | #1 |
| AC-2 | The menu is reachable from the rest screen | S-3101, S-3102, S-3103, S-3111 | D-3102, D-3103, D-3109, D-3114 | #3 |
| AC-3 | One exercise list, two entry points | S-3105, S-3106, S-3107, S-3108, S-3113 | D-3104, D-3105, D-3110, D-3111, D-3112 | #2 |
| AC-4 | Jump to letter lands on that letter | S-3106 (the mechanism) — the landing itself has no off-device check | D-3106, D-3112 | #2 |
| AC-5 | The menu's extra gap sits above Add Exercise | S-3104 | D-3101 | — |

AC-4 is honest about its limit: `List` + `Section` + `scrollTo(letter, anchor: .top)` is the only mechanism the
package can hold off-device, so S-3106 pins the mechanism (the `LazyVStack` that causes the miss is gone) and
the owner check proves the landing on a 100+ exercise list.

## Existing-Functionality Impact

Each row names the grep that found the readers, the effect, and what guards it.

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `WatchStartPaths.pickerRows` (`:574`) | `WatchStartView.swift:221` (`WatchExercisePickerView`); `WatchConnectivityBridgeTests.swift:845` and `:899` (both assert the fallback order) | the available rows become A-to-Z; the ladder rows keep their order and their once-only offer | S-3107, S-3113, and the two updated tests; `testS108APushIntoAnOpenFreeWorkoutLands` (`:791`) reads no order — the whole `WatchConnectivityBridgeTests` suite is re-run to prove it |
| `WatchMenuCopy.addLetterGridThreshold` (`:134`) / `WatchMenuState.addExerciseLetters` (`:274-283`) | the menu's grid; `WatchMenuTests` letter tests S-3900…S-3908 (`:892-1092`), `testS3611` (`:603`), `testS3615` (`:716`) | one threshold site behind `deriveExerciseListLetters`; same output for the same input | S-3105, S-3108 plus the untouched S-39xx letter tests |
| `WatchMenuState.addableExercises` (`:267`) | S-3611/S-3615 fixtures; the menu's Add Exercise list | unchanged — it is already A-to-Z, and the picker now shows it directly | S-3105, S-3611, S-3615 |
| `ContentView.body` rest branch (`:227-233`) | `WatchRestView` (its own Next/ping/timer, untouched); `WatchSensorSourceSourceTests.testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst` (`:270`) asserts the host's wiring lines in the same file | the branch gains a `NavigationStack` and a toolbar button; the host wiring lines must not move | S-3103 (new) and the existing S-3110 re-run |
| `ContentView.swift` `.sheet` / `WatchMenuState(` (`:293-295`) | the same existing S-3110 scan; the new S-3103 asserts the count is exactly one in the file | the sheet moves to the root `Group`; the construction stays single | S-3103, S-3110 |
| `HealthKitSensorFeed.workoutBuilder(_:didCollectDataOf:)` (`:136`) | app target only; off-device readers are `WatchSensorSourceSourceTests` scans S-3109/S-3110/S-3114/S-3116/S-3311/S-3315 (they assert `WatchSensorSource`, `HKLiveWorkoutBuilderDelegate`, `HKQuantityType(.heartRate)`, `.unavailable`, the `nonisolated` declaration and the negatives `import CoreLocation`, `requestAuthorization`) | a pull is added beside the push path; every asserted token must survive | S-3110, S-3112 plus a full re-run of `WatchSensorSourceSourceTests` |
| `HealthKitWorkoutStore.begin`/`end` (`:93-158`) | `testS3117TheStoreMakesTheBuilderCollectAndHandsItTheFeed` (`:374`, asserts `collection.delegate = sensorFeed` and the builder hand-off) and `testS3312TheStoreTakesTheAdapterAndRegistersOutdoors` (`:521`, asserts `func begin(_ activityType: String, outdoors: Bool)` and `locationType = outdoors ? .outdoor : .unknown`) | a `refreshHeartRate()` is added; `begin`/`end`/the outdoor registration keep their names and their strings | S-3117 and S-3312 stay green |
| `WatchAddExerciseList` (`WatchMenuView.swift:184-259`) | `WatchMenuTests.testS3617` (`:876`) forbids the tokens `WatchExercisePickerView` and `pickerRows` in `WatchMenu.swift`/`WatchMenuView.swift`; `testS1108` (`:860`) forbids `restSeconds`, `plannedDurationMs`, `deleteEntry`, `removeExercise` in the same two files | the wrapper stays plain data and names none of those tokens | S-3617, S-1108, S-3106 |
| every file under `watch/watchos/Sources/` | `WatchSessionEngineTests.swift:335-370` rejects a four-space-indented `func` named with an append-only verb (`set`, `update`, `clear`, `remove`, `write`, `reset`, `forget`, …); `WatchRestIsCountUpTests.sourceFiles()` (`:33`) rejects `restSeconds` and `plannedDurationMs` in every file | the new `WatchExerciseListView.swift` must avoid both | the whole package suite (`swift-test`) |
| `docs/state_management/watch_surface.md` (737 lines, ~56 KB estimated — above the 52 KB band, under the 64 KiB ceiling) | `test/docs_indexing_contract_test.dart` | ≤12 added lines; a section moves to a part page if the test reds | `flutter test test/docs_indexing_contract_test.dart` |
| `docs/state_management/watch_reference_data.md` (210 lines) and `docs/watch-app-setup-and-qa.md` (a record file, not indexed) | the same contract test for the indexed one only | sentence updates and **(owner)** steps | the contract test |
| `watch/contract/watch_start_paths_contract.json`, `watch/sync_protocol/**`, `lib/**`, `docs/README.md` | — | **not touched**; the picker's order change is a view-level re-order, so no fixture, schema or wire change | the diff against Predicted Files |

## Iteration 1 — phases as executable items

The seeded table above is the outline; seeded Phase 2 is split into 2A and 2B so each handoff stays far under 8
items (2A is package data shape, 2B is the watchOS view file). Red tests first, then the change, then the docs.

### Phase 1: the rest screen's menu and the menu's extra gap (seeded Phase 1) (@developer)
1. [x] Write S-3104 `testS3104ATheMenuGapSitsAboveAddExercise` in `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`,
   scanning `WatchMenuView.swift` with comment lines stripped (replicate the three-line helper used by
   `WatchSensorSourceSourceTests.source(_:)`, or host the scan there instead and say so in the Assumption Log;
   the reviewer accepts either, not both): match the lines whose trimmed text is exactly `addExerciseRow` and
   `finishRow` — the declarations read `private var addExerciseRow: some View {`, so an exact match is
   unambiguous — and assert the `addExerciseRow` usage line, not the `finishRow` usage line, carries
   `.padding(.top`. RED at base (`Divider()` `:81`, `addExerciseRow` `:83`, `finishRow` `:85`,
   `.padding(.top, 10)` `:86`). · test `testS3104ATheMenuGapSitsAboveAddExercise`
   - **Done** — red at base (padding on `finishRow`), green after item 6; `prove-red 0da2a72` says RED AT.
2. [x] Write S-3103 `testS3103ATheRestScreenCarriesTheMenuButton` in the same file: the comment-stripped text of
   `ios/OmniTrain Watch App/ContentView.swift` must contain `host.logging.isResting`, and the `NavigationStack`
   and `Image(systemName: "list.bullet")` must both appear after that branch's opening and before the logging
   surface; `WatchMenuState(` must occur exactly once in the file (count occurrences, do not just `contains`).
   RED at base — the rest branch renders `WatchRestView` bare and the button lives only in `loggingSurface`.
   · test `testS3103ATheRestScreenCarriesTheMenuButton`
   - **Done** — red at base (bare `WatchRestView`), green after item 7; host file is `WatchMenuTests.swift` (Assumption Log).
3. [x] Write S-3101 `testS3101AJumpDuringARestKeepsTheRestRunning` in the same file: launch fixture A, log a set
   so a rest runs (`logging.isResting == true`, the newest timer is that rest — copy the inline
   `WatchLoggingState(engine:clock:)` construction from `testS1307ARunningRestDoesNotLockTheMenu` `:547` and the
   assertion shape from `:493`), then `menu.jump(to:)` another slot: returns `true`, the session's current
   exercise index moves, `isResting` is still `true`, and the rest timer's start instant and id are unchanged.
   Expected GREEN at base — a guard (mutation: making `jump` end the rest turns it red).
   · test `testS3101AJumpDuringARestKeepsTheRestRunning`
   - **Done** — green at base; one mutation line in `jump` (`stopTimer(kind: .rest)`) reddens it with 4 failures, restored.
4. [x] Write S-3102 `testS3102AAddingAnExerciseDuringARestKeepsTheRestRunning`: with a rest running,
   `menu.addExercise(...)` (call shape from `testS3611` `:603`) returns `true`, the ladder grew by exactly one
   and the new slot is last, the current exercise index is unchanged, `isResting` is still `true` and the running
   rest is the same record. Mutation: `addExerciseToEnd` (`WatchStartPaths.swift:604-612`) stopping the rest
   turns it red. · test `testS3102AAddingAnExerciseDuringARestKeepsTheRestRunning`
   - **Done** — green at base; the same one-line mutation inside `addExerciseToEnd` reddens it with 2 failures, restored.
5. [x] Write S-3111 `testS3111ALogClosesTheRunningRestAndStartsTheNext`: the corrected second half of S-3102
   (D-3109) — after `logging.log()` the rest that was running is closed at the logged instant and a new rest row
   started at that instant is the newest timer, so `isResting` reads `true` again. Take the exact expected emitted
   kinds and counts from `WatchLoggingTimersTests.testS321` and paste them into the evidence file.
   · test `testS3111ALogClosesTheRunningRestAndStartsTheNext`
   - **Done** — green; kinds `["set","rest","set"]`, one rest, `t0 → t0+30`, `afterEntryId` grown from `testS321`, pasted in the evidence file; mutation (`_ = startFollowOnTimer`) reddens it with 2 failures, restored.
6. [x] D-3101: in `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift`, move `.padding(.top, 10)` from
   the `finishRow` usage (`:86`) to the `addExerciseRow` usage (`:84`); `finishRow` stays bare and `Divider()`
   is untouched. · `WatchMenuView.body` · `addExerciseRow` · `finishRow`
   - **Done** — one line moved; `git-diff --stat` for the file is 2 lines (+1/-1).
7. [x] D-3102/D-3114 in `ios/OmniTrain Watch App/ContentView.swift`: wrap the `host.logging.isResting` branch
   (`:227-233`) in a `NavigationStack` carrying the same top-right `Image(systemName: "list.bullet")` toolbar
   button the logging surface has (`:284-289`) with the same accessibility label; hoist the one
   `.sheet(isPresented: $showingMenu)` + one `WatchMenuState(...)` (`:293-295`) into a single `menuSheet` helper
   applied to the root `Group` (`:224`); drop `.onDisappear { showingMenu = false }` (`:314`) and close the sheet
   instead when no session is active (`.onChange` on `host.logging.isActive`, or the engine's session status —
   record which in the Assumption Log). `WatchRestView`'s props, Next, ping and timer are untouched.
   · `ContentView.body` · `WatchAppHost` · `loggingSurface` · `menuSheet`
   - **Done** — the rest branch is a `NavigationStack` with the same verbatim button; the root `Group` carries the one `menuSheet` helper, which holds the file's only `WatchMenuState(`; `.onDisappear` dropped and the sheet closes on `host.engine.session?.status` and on `host.rating.isPromptOwed` (Assumption Log).
8. [x] Docs: `docs/state_management/watch_surface.md` — the sentence describing where the one list button lives
   now says the rest screen carries the same button and both surfaces open the one sheet (≤6 lines, ~432-476);
   `docs/watch-app-setup-and-qa.md` — append one **(owner)** line after the existing steps 10-14 (~712-790):
   "rest → list button → Add Exercise → pick → back on the rest screen, timer still counting".
   · `docs/state_management/watch_surface.md` · `docs/watch-app-setup-and-qa.md`
   - **Done** — `watch_surface.md` +6 lines; step 10's "extra space above End Session" was made false by D-3101 and says "above Add Exercise" now, and the appended **(owner)** step 15 is in; docs contract test 13/13.

**Done Criteria** (run until green; paste counts into the evidence file):
`.github/copilot/scripts/macos/gateway.sh swift-test` (whole package — names the pass counts of
`WatchMenuTests`), `.github/copilot/scripts/macos/gateway.sh lint` (`flutter analyze`: 0 errors; record the
issue count and compare it with Phase 1's first run, since the repo carries pre-existing info notices), and
`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart` (a doc changed).
The app-target edit is **not** compiled by any agent check (`swift test` builds the package only; the watch app
needs `xcodebuild` on a watchOS simulator, which only the governor runs), so it is held by S-3103 plus the
reviewer reading the diff.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift`,
`ios/OmniTrain Watch App/ContentView.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`,
`docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md` — nothing else.

### Phase 2A: the sections function, the letters gate and the picker's order (seeded Phase 2, part A) (@developer)
1. [x] Write S-3107 `testS3107ATheFreePickerOffersTheAvailableExercisesAToZ` in
   `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`: deliver the contract's own
   `routines_down` to an empty free session (`WatchStartHarness` `:61`, `startContract()` `:151`, the
   `receive(try firstMessage())` / `startFreeWorkout()` shape of `testS002FreeWorkoutStartsEmptyAndAddsAFallbackExercise`
   `:606`), then assert the available rows read exactly `[ex-barbell-bench-press, ex-goblet-squat, ex-plank,
   ex-pull-up]` and that an exercise added to the ladder is offered once as its in-session row and not again as
   available. RED at base (the available rows follow the phone's order `ex-plank, ex-goblet-squat,
   ex-barbell-bench-press, ex-pull-up`, `watch/contract/watch_start_paths_contract.json:83-88`).
   · test `testS3107ATheFreePickerOffersTheAvailableExercisesAToZ`
   - **Done** — red at base through `prove-red 0da2a72` on the two re-pointed bridge tests (the picker's rows
     read the phone's order there) and red under the `fallback:` revert here; the fixture seeds a completed
     session so the wrist's own recents reproduce the contract's `fallback.expected` (Assumption Log).
2. [x] Write S-3113 `testS3113AThePickerRowsAndTheAvailableExercisesAgree` in the same file, on the S-3113
   fixture (three states: the contract catalog, a 21-exercise catalog built like the file's modified-catalog
   helper ~`:237-251` with names `Alpha`…`Uniform`, and that catalog with one exercise on the ladder):
   the order identity between `pickerRows`' non-in-session rows and `availablePickerExercises`, letters
   non-empty and starting with `"A"` at 21 available, empty at 20. RED at base (`availablePickerExercises`
   does not exist). · test `testS3113AThePickerRowsAndTheAvailableExercisesAgree`
   - **Done** — the same revert reddens it at `:2311`; three states pin the identity and the gate (contract
     catalog: no grid; 21 catalog-only rows: grid opening at `A`; 20 after one is added: none).
3. [x] Write S-3105 `testS3105ASectionsFollowTheListAndTheLettersAgree` in `WatchMenuTests.swift`: 120 mixed
   names (digits, symbols, mixed case, one accented, one with a leading space) applied through the harness's
   catalog helper; assert `deriveExerciseSections(menu.addableExercises)` has one section per key in list order,
   its concatenation equals `addableExercises` exactly, each section's first exercise is
   `menu.addExerciseLetters[i].firstExerciseId`, and the section letters equal
   `menu.addExerciseLetters.map(\.letter)`. · test `testS3105ASectionsFollowTheListAndTheLettersAgree`
   - **Done** — red under the mutation `addExerciseLetterKey(of: exercise.exerciseId)` inside
     `deriveExerciseSections` (4 failures; sections lost their keys), restored exact and re-run green; the
     120-name fixture holds every case the scenario enumerates.
4. [x] Write S-3108 `testS3108ATheLetterGridAppearsOverTwentyRows` in the same file: 20 addable exercises → no
   letters and `deriveExerciseListLetters` empty; 21 → letters, and the existing S-3902 test still passes.
   · test `testS3108ATheLetterGridAppearsOverTwentyRows`
   - **Done** — green on the shared gate; red under `>` → `>=` in `deriveExerciseListLetters` (2 failures here)
     together with the untouched `testS3902TheGridNeedsMoreThanTheThreshold`, restored and re-run green.
5. [x] D-3110 in `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift`: add
   `WatchExerciseSection: Equatable { let letter: String; let exercises: [WatchCatalogExercise] }` and
   `deriveExerciseSections(_:) -> [WatchExerciseSection]` after `deriveAddExerciseLetters` (~110, keys through
   `addExerciseLetterKey(of:)` `:80`, pure, no sorting); add
   `deriveExerciseListLetters(_:) -> [WatchAddExerciseLetter]` carrying the single
   `WatchMenuCopy.addLetterGridThreshold` gate; make `WatchMenuState.addExerciseLetters` (`:274-283`) call it and
   add `WatchMenuState.addExerciseSections` beside it.
   · `WatchMenu.swift:deriveExerciseSections` · `deriveExerciseListLetters` · `WatchMenuState.addExerciseLetters`
   · `WatchMenuState.addExerciseSections`
   - **Done** — the three declarations sit after `deriveAddExerciseLetters`; `addExerciseLetters` now calls
     `deriveExerciseListLetters`, whose doc names the one home of `addLetterGridThreshold`; the file's
     `git-diff --stat` is +84 lines (nothing else touched).
6. [x] D-3111 in `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`: `pickerRows` (`:574-582`)
   passes `fallback: addableExercises`; add `availablePickerExercises` beside it (addable minus the ladder's
   exercise ids, addable's order) and leave `derivePickerRows` (`:179-201`) untouched. Then update the two order
   assertions in `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift` — the test at
   ~`:845-897` (its fallback-order slice and its "in its order" comment) and the test at ~`:899-920` — to the
   A-to-Z reading, keeping both names and their offered-once clauses. Update both files' header comments with the
   plan citation (D-3116). · `WatchStartPaths.pickerRows` · `WatchStartPaths.availablePickerExercises` ·
   `testPickerRowsListTheSessionFirstAndNeverTwice` · `testPickerRowsFallBackToTheFallbackListWhileTheSessionIsEmpty`
   - **Done** — `pickerRows` passes `fallback: addableExercises`; `availablePickerExercises` is an explicit
     filter of `addableExercises` by the ladder's ids (Assumption Log), so S-3113 is a real identity; both bridge
     tests read A-to-Z and were RED AT `0da2a72` through `prove-red` (2 failures at `:877`/`:913`), green after.
7. [x] Docs: `docs/state_management/watch_reference_data.md` (~113-117) — the available-row order sentence now
   says the picker offers `addableExercises` A-to-Z (with `#` first, accented last) and that
   `addLetterGridThreshold` 20 gates the picker's grid over the available rows;
   `docs/state_management/watch_surface.md` — the picker's order sentence (~434) matches, ≤6 added lines.
   · `docs/state_management/watch_reference_data.md` · `docs/state_management/watch_surface.md`
   - **Done** — the reference data now says the picker offers `availablePickerExercises`, what
     `deriveExerciseSections` is, and that one gate serves both surfaces (each sentence citing its test); the
     watch surface's picker-order sentence reads A-to-Z in +3 lines; docs contract 13/13.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (whole package:
`WatchMenuTests`, `WatchSessionStartPathsTests`, `WatchConnectivityBridgeTests` and the untouched S-39xx letter
tests all green — the letter tests are the regression guard for the shared threshold); `.github/copilot/scripts/macos/gateway.sh lint`
(0 errors, issue count compared with Phase 1); `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart`.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`,
`docs/state_management/watch_reference_data.md`, `docs/state_management/watch_surface.md` — nothing else.

### Phase 2B: the one shared watchOS list (seeded Phase 2, part B) (@developer)
1. [x] Write S-3106 `testS3106AOneListServesBothEntryPoints` in `WatchMenuTests.swift` (the source-scan shape of
   `testS3617` `:876` and `testS1108` `:860`): `WatchExerciseLetterList` appears in `WatchMenuView.swift` and in
   `WatchStartView.swift`, and `LazyVStack` appears in neither. RED at base.
   · test `testS3106AOneListServesBothEntryPoints`
   - **Done** — RED before any implementation (4 failures: neither entry point named the component, the menu
     still held its `LazyVStack`, and `WatchExerciseListView.swift` did not exist), then red under the mutation
     that put a `LazyVStack` line back into the shared file (`:971` "the shared list places no row by estimate"),
     restored exact and re-run green. `prove-red HEAD` cannot carry this test: the carried file references the
     Phase 1/2A symbols that do not exist at `0da2a72` (Assumption Log).

2. [x] Create `watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift` (`#if os(watchOS)`) with
   `WatchExerciseLetterList` and the D-3112 API: one `List`, a `Section` per section whose header carries the
   letter and `.id(section.letter)`, the letter grid as the list's first row in a `LazyVGrid`, the button
   `scrollTo(letter, anchor: .top)` with no animation, the leading rows first and prominent, `emptyText` when
   there are no sections and no leading rows. No `LazyVStack`; no four-space-indented method named with an
   append-only verb. · `WatchExerciseListView.WatchExerciseLetterList`
   - **Done** — the file is 155 lines: the grid is the `List`'s first row (`.listRowInsets(EdgeInsets())` +
     the wrist inset), then one `Section` of the leading rows drawn `.watchProminent()`, then one `Section` per
     section with `.id(section.letter)` on its header; `.listStyle(.plain)` and no animation (Assumption Log);
     methods are `list`, `leadingButton`, `letterGrid`, none append-only.

3. [x] `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift`: `WatchAddExerciseList.body` (~199-236)
   becomes the shared view with `leading: []`, `sections: state.addExerciseSections`,
   `letters: state.addExerciseLetters`, `emptyText: WatchMenuCopy.addExerciseEmpty`, and
   `onPick: { exercise in … state.addExercise(exercise) … onAdded() … }`; delete the local `letterGrid` (~241-258)
   and the `LazyVStack` machinery it replaces. · `WatchAddExerciseList.body` · `WatchAddExerciseList.letterGrid`
   - **Done** — the body is the shared view plus its `.navigationTitle`, `onPickLeading` is the no-op
     `{ _, _ in }`; the local `letterGrid`, the `LazyVStack` and the now-unused `surfaceInset` are gone
     (`WatchMenuView.swift` −47/+8); `testS3617` and `testS1108` stay green.

4. [x] `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`: `WatchExercisePickerView.body`
   (~220-247) becomes the shared view with `leading:` built from `paths.pickerRows`' in-session rows,
   `sections: deriveExerciseSections(paths.availablePickerExercises)`,
   `letters: deriveExerciseListLetters(paths.availablePickerExercises)`, the existing empty text, and the two
   closures calling `paths.selectExercise` (`.inSession(slotId:exercise:)` and `.available(exercise)`), keeping
   the existing dismissal behaviour. · `WatchExercisePickerView.body`
   - **Done** — `body` is the shared view in a `VStack(spacing: 0)` with the phone hint below it, the empty text
     moved to `static let emptyText` (same words), and `inSessionRows` maps `pickerRows`' in-session rows to
     slot id + exercise; `select(_:)` is unchanged, so the dismissal path is the same one.

5. [x] Docs: `docs/state_management/watch_surface.md` — the Add Exercise/picker entry now says one shared
   component serves both entry points and names `WatchExerciseListView.swift` (≤6 added lines, ~432-476);
   `docs/watch-app-setup-and-qa.md` — the **(owner)** letter-jump line (step 14, ~712-790) names both entry
   points. · `docs/state_management/watch_surface.md` · `docs/watch-app-setup-and-qa.md`
   - **Done** — the watch surface gains a five-line "One list serves both entry points" paragraph naming the
     component and the file and citing S-3106; QA step 14 says the Far letters land because the list measures
     every row, that the Free workout picker draws the same grid, and cites
     `WatchMenuTests.testS3106AOneListServesBothEntryPoints`; docs contract 13/13.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (whole package; this is the phase that
compiles the new view for the first time — a `#if os(watchOS)` error hides from `swift build` on macOS, so also
confirm the file's guard and that the two entry files still compile), `.github/copilot/scripts/macos/gateway.sh lint`
(0 errors, count compared with Phase 1), `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart`.
**Predicted Files**: new `watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift`,
`docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md` — nothing else.

### Phase 3: the live heart rate — diagnose, then fix (seeded Phase 3) (@developer)
1. [x] Write S-3109 `testS3109ATheLabelFollowsEveryBeat` in
   `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift` (fake source `FakeSensorSource`
   `:27`, `eventually` `:107`, a real engine over `FileWatchSessionStore(directory:)` in a temp directory and a
   `WatchLoggingState(engine:clock:sensors:)` as `testS003TheLoggingSurfaceShowsTheLiveHeartRateAndDistance`
   `:255` builds it): beats 100, 104, 109, 115 make `readings.heartRate` and `heartRateLabel` read
   `"100"`, `"104"`, `"109"`, `"115"` in turn. Diagnostic (D-3107) — record its colour in the evidence file.
   · test `testS3109ATheLabelFollowsEveryBeat`
2. [x] Write S-3110 `testS3110ATheFeedPullsTheNewestBeatWhileAListenerWaits` and S-3112
   `testS3112ATheStoreAndTheHostRefreshTheHeartRateOnActivation` in
   `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift`, using that file's own
   `feedSource()`, `storeSource()` and `viewSource()` helpers and its comment-stripping: the D-3113 tokens
   (`heartRatePullSeconds`, `mostRecentQuantityDateInterval`, `onTermination` + `heartRateContinuations.isEmpty`,
   `func refreshHeartRate(`, `builder` handed to the feed, `refreshHeartRate(` in the scene-phase handler).
   RED at base. · test `testS3110ATheFeedPullsTheNewestBeatWhileAListenerWaits` ·
   test `testS3112ATheStoreAndTheHostRefreshTheHeartRateOnActivation`
3. [x] Diagnosis branch (D-3107): if S-3109 (or its `FileWatchSessionStore` twin) is RED, the bug is in the
   package — fix the chain (`WatchSensorRecorder` / `WatchLoggingState`), write the root-cause line in the
   evidence file, and skip items 4-5 (record the skip and why there). If both are GREEN, say so in the evidence
   file and continue — the beats stop upstream. Do not run the same red check a third time.
   · `WatchSensorRecorder` · `WatchLoggingState.poll`
4. [x] D-3108/D-3113 in `ios/OmniTrain Watch App/HealthKitSensorFeed.swift`: add `heartRatePullSeconds = 3` and
   `lastHeartRateEnd`; start the pull when `heartRate()` takes its first subscription (`:94-107`) and cancel it
   in `onTermination` when `heartRateContinuations` (`:62`) becomes empty; each tick and each activation read
   `builder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()` and yield through
   `yieldHeartRate` (`:184`) only when `mostRecentQuantityDateInterval?.end` is strictly newer than
   `lastHeartRateEnd`. The delegate path (`workoutBuilder(_:didCollectDataOf:)`, `:136-165`) stays; no new
   query type, no new dependency. · `HealthKitSensorFeed.heartRate` · `HealthKitSensorFeed.yieldHeartRate` ·
   `HealthKitSensorFeed.forgetHeartRate`
5. [x] D-3113 wiring: in `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` add
   `func refreshHeartRate()` (calling `sensorFeed.refreshHeartRate(from: builder)`) and let the feed see the
   builder handed over in `begin` (`collection.delegate = sensorFeed` `:119`, `builder = collection` `:122`)
   and cleared in `end()` (`:146`); in `ContentView.swift` keep the store `WatchAppHost` already builds (~92) and
   call `refreshHeartRate()` from the existing `.onChange(of: scenePhase)` activation branch (`:257-258`) next to
   `catchUpOnActivation()`. · `HealthKitWorkoutStore.refreshHeartRate` · `HealthKitWorkoutStore.begin` ·
   `HealthKitWorkoutStore.end` · `ContentView.body`
6. [x] Docs: `docs/watch-app-setup-and-qa.md` — refine the **(owner)** heartbeat line ("changes at least every
   ~5 s, also after lowering and raising the wrist; if it freezes, note the last value and after how many
   seconds") and add one line saying the pull reads the newest beat on a tick and on activation;
   `docs/state_management/watch_surface.md` — one line saying the live label follows the sensor while the
   logging screen is up (~432-476, ≤6 added lines). · `docs/watch-app-setup-and-qa.md` ·
   `docs/state_management/watch_surface.md`

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (whole package, and for the app target
`WatchSensorSourceSourceTests` in full — its existing scans are the regression guard for the feed and the store),
`.github/copilot/scripts/macos/gateway.sh lint` (0 errors, count compared with Phase 1),
`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart`.
The app target still cannot be compiled by an agent check — the owner's device check is the only proof of AC-1.
**Predicted Files**: `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchSensorSourceSourceTests.swift`,
`ios/OmniTrain Watch App/HealthKitSensorFeed.swift`, `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`,
`ios/OmniTrain Watch App/ContentView.swift`, `docs/watch-app-setup-and-qa.md`,
`docs/state_management/watch_surface.md` — nothing else.


## Owner checks (device only, cannot be proven by the agents)

- **(owner)** Run outdoors 5 minutes: the heart rate on the logging screen changes at least every ~5 s, also after
  lowering and raising the wrist.
- **(owner)** Letter jump on a 100+ exercise list: A, D, M, T, W, Z each land with their first exercise at the top.
- **(owner)** Rest -> list button -> Add Exercise -> pick -> back on the rest screen, timer still counting.

## Files Affected (whole feature)

`P` = the phase that touches it; entries marked *reads only* must stay unchanged and are named as regression
guards for the reviewer's Impact Check.

| File | Phase | What changes |
|---|---|---|
| `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` | 1, 2B | the gap moves to `addExerciseRow`; `WatchAddExerciseList` renders the shared view |
| `watch/watchos/Sources/WatchSessionEngine/WatchMenu.swift` | 2A | `WatchExerciseSection`, `deriveExerciseSections`, `deriveExerciseListLetters`, `addExerciseSections` |
| `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` | 2A | `pickerRows` passes `addableExercises`; `availablePickerExercises` |
| `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` | 2B | `WatchExercisePickerView` renders the shared view |
| `watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift` | 2B | new: `WatchExerciseLetterList` |
| `ios/OmniTrain Watch App/ContentView.swift` | 1, 3 | the rest branch's `NavigationStack` + button, the hoisted sheet, the activation refresh |
| `ios/OmniTrain Watch App/HealthKitSensorFeed.swift` | 3 | the heart-rate pull |
| `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` | 3 | `refreshHeartRate()`, the builder hand-off |
| `watch/watchos/Tests/…/WatchMenuTests.swift` | 1, 2A, 2B | S-3101…S-3106, S-3108, S-3111 |
| `watch/watchos/Tests/…/WatchSessionStartPathsTests.swift` | 2A | S-3107, S-3113 |
| `watch/watchos/Tests/…/WatchConnectivityBridgeTests.swift` | 2A | two order assertions updated |
| `watch/watchos/Tests/…/WatchSensorRecordingTests.swift` | 3 | S-3109 |
| `watch/watchos/Tests/…/WatchSensorSourceSourceTests.swift` | 3 | S-3110, S-3112 |
| `docs/state_management/watch_surface.md` | 1, 2A, 2B, 3 | the button, the picker's order, the shared component, the live label |
| `docs/state_management/watch_reference_data.md` | 2A | the available-row order and the grid gate |
| `docs/watch-app-setup-and-qa.md` | 1, 2B, 3 | **(owner)** device steps |
| `watch/contract/watch_start_paths_contract.json` | — (reads only) | the fixture S-3107 and the two bridge tests read |
| `WatchSensorCoordinatorTests.swift`, `WatchMenuTests` S-39xx, `WatchSensorSourceSourceTests` S-3109/S-3110/S-3114/S-3116/S-3311/S-3312/S-3315/S-3317/S-3318 | — (reads only) | the regression guards the Impact Check names |

## Notes

**Dependency graph.** Phase 1 and Phase 2A are independent and may run in either order (they touch disjoint
files). Phase 2B needs 2A (`deriveExerciseSections` and `availablePickerExercises` do not exist before it).
Phase 3 is independent of 2A/2B but shares `ios/OmniTrain Watch App/ContentView.swift` with Phase 1, so it runs
after Phase 1 to keep one writer per file per handoff. Alternative ordering, with its trade-off: Phase 3 first
gives the owner the visible heart-rate fix earliest and leaves the two `ContentView.swift` edits as one clean
pair in Phase 1 — at the cost of the menu work (three of the five findings) landing last.

**Predicted intermediate states.** After Phase 1 the rest screen carries the button and the sheet survives a
rest ending under it; nothing in the package changes. After 2A the order and grouping exist in the package but
no view uses them yet — the picker still renders its old `ScrollView`/`VStack` body, and `swift test` is green
with two functions used only by tests (acceptable: S-3105, S-3107 and S-3113 pin them); `testS3617` still passes
because the menu files still name none of its banned tokens. After 2B both entry points render one list, and
Phase 3 changes no package behaviour unless S-3109 is red.

**Deliberate mirroring.** S-3103, S-3104 and S-3106 scan source text the way `WatchSensorSourceSourceTests`
already does for the app target (comment-stripped, token assertions). That file already reads `ContentView.swift`
through `viewSource()`, so hosting S-3103 there instead of in `WatchMenuTests.swift` is admissible — the seed
puts it with S-3101/S-3102, and the developer records the choice, not both, in the Assumption Log.

**Not-touched contract.** No fixture, schema, wire message, phone or Wear file changes; the picker's order
change is a view-level re-order of data the wrist already holds, so `watch/sync_protocol/**`,
`watch/contract/watch_start_paths_contract.json` and `lib/**` stay byte-identical.

## Progress

- [x] Phase 1 — the rest screen's menu and the menu's extra gap (D-3101, D-3102, D-3103, D-3109, D-3114) — **Complete**, 2026-10-13: 8/8 items, 5 new tests (S-3103/S-3104 red at base through `prove-red 0da2a72`, S-3101/S-3102/S-3111 proven by mutation), `swift-test` 564 tests / 0 failures (`WatchMenuTests` 40/0), `docs_indexing_contract_test.dart` 13/13, `lint` 181 pre-existing info notices with no Dart file touched; evidence in `2026-10-13-31-watch-qa-fixes-3-plan.evidence.md`.
- [x] Phase 2A — sections, the letters gate, the picker's order (D-3104, D-3110, D-3111) — **Complete**, 2026-10-13: 7/7 items, 4 new tests (the picker's order RED AT `0da2a72` through `prove-red` on the two re-pointed bridge tests — 2 assertion failures; S-3105, S-3108 and S-3113 proven by mutation), `swift-test` 568 tests / 0 failures (`WatchMenuTests` 5/0 on the letter tests, `WatchSessionStartPathsTests` 2/0, `WatchConnectivityBridgeTests` 2/0), full `test` 4476 passed / 1 skipped, `docs_indexing_contract_test.dart` 13/13, `lint` 181 pre-existing info notices with no Dart file touched; evidence in `2026-10-13-31-watch-qa-fixes-3-plan.evidence.md`.
- [x] Phase 2B — the one shared watchOS list (D-3105, D-3106, D-3112) — **Complete**, 2026-10-13: 5/5 items, 1 new test (S-3106 red before implementation — 4 failures — and red under the mutation that put a `LazyVStack` line back into the shared file, `:971` "the shared list places no row by estimate"; `prove-red HEAD` cannot carry this test — the carried file cites Phase 1/2A symbols that do not exist at `0da2a72`), `swift-test` 569 tests / 0 failures (105 tests / 0 in the two touched suites: `WatchMenuTests` 43, `WatchSessionStartPathsTests` 62), `docs_indexing_contract_test.dart` + `ui_standards_contract_test.dart` 42/42, `lint` 181 → 184 with nothing of this phase touched (the 2 errors and 1 info are in `test/mix_layer_screen_test.dart`, a concurrent run's file), full `test` 4453 passed / 1 skipped / 66 failed — all 66 in that same `mix_layer_screen_test.dart`; no Dart file changed here, so the invariant grep over `lib/state|features|widgets|core` is empty; evidence in `2026-10-13-31-watch-qa-fixes-3-plan.evidence.md`.
- [x] Phase 3 — the live heart rate, diagnose then fix (D-3107, D-3108, D-3113) — **Complete**, 2026-10-14: 6/6 items, 3 new tests. **The diagnosis (D-3107): S-3109A is GREEN at the base commit over both `FileWatchSessionStore` and `InMemoryWatchSessionStore`**, so the package chain carries every beat the source hands it and the beats stop upstream — D-3108 applies and items 4-5 were **not** skipped; the guard still observes something (a mutation of `appendSensorSample`'s dedupe to `$0.kind == kind` reddens it with 18 assertion failures across both stores), so S-3109 is a diagnostic, not a proof. S-3110A and S-3112A are **RED AT `0da2a72`** through `prove-red` (6 tests / 11 assertion failures — 10 on the pull's tokens and the hand-over, 1 for the store's `refreshHeartRate`), and S-3112A is also red under the mutation that drops `host.refreshHeartRate()` from the scene handler (`:901`). `swift-test` 573 tests / 0 failures; `WatchSensorSourceSourceTests` 16/0 in full, its pre-existing scans the regression guard for the feed and the store; `docs_indexing_contract_test.dart` + `ui_standards_contract_test.dart` 42/42; `lint` 182 info with 0 errors and no Dart file touched (181 baseline + 1 from a concurrent run); full `test` 4519 passed / 1 skipped / 0 failed; the invariant grep over `lib/state|features|widgets|core` is empty. The app target still cannot be compiled by an agent check — the owner's device check remains the only proof of AC-1 (Open question 7). Evidence in `2026-10-13-31-watch-qa-fixes-3-plan.evidence.md`.
- [x] Fix round 1 (the closed brief `.work/2026-10-13-31/brief-fix-1.md`: the review's three findings + the app-target compile error) — **Complete**, 2026-10-14: 4/4 items. `HealthKitSensorFeed.swift` calls `mostRecentQuantityDateInterval()` and takes D-3118's reading of a nil interval (pull drops the beat, push yields ungated; no `Date()` fallback); `scrollTargetLetters(of:)` (D-3117) now names the runs that carry a scroll id and the shared list derives its ids from it, pinned by the new `testS3114ARepeatedLetterRunsCarryOneScrollId` (RED under the mutation that returns every section's letter — 4 assertion failures — and GREEN restored; `prove-red HEAD` reports a load error instead, the carried test reading an untracked file, so the mutation is the proof); the picker's "search on the phone" hint is now the shared list's last row (`trailing: AnyView?`), so it scrolls with the content; `docs/watch-app-setup-and-qa.md` step 14 states the picker's real order (grid, in-session rows, letter sections) and `docs/state_management/watch_surface.md` names the id rule (S-3114) and the hint's new row. `swift-test` 574 tests / 0 failures (baseline 573, +1 new), `WatchMenuTests` 44/0 and `WatchSensorSourceSourceTests` 16/0 before it; full `test` 4519 passed / 1 skipped / 0 failed, `test/docs_indexing_contract_test.dart` 13/13 and `test/ui_standards_contract_test.dart` in the same 42/42 run; `lint` 182 info with 0 errors; no Dart file touched; evidence in `2026-10-13-31-watch-qa-fixes-3-plan.evidence.md`.
- [ ] Phase 4 (reserved) — feature consolidation, the residue sweep and the consolidated doc pass; the governor
      adds it after the owner's device checks, or the reviewer opens it as a remediation phase.

## Assumption Log

Phase 1 (developer, 2026-10-13):
1. **S-3103/S-3104's host file — `WatchMenuTests.swift`.** The plan allows either the package's menu tests or
   `WatchSensorSourceSourceTests`, never both; the seed put S-3103 with S-3101/S-3102, so both scans and their
   comment-stripping helper stayed in `WatchMenuTests.swift`.
2. **The sheet-close trigger — the engine's session status.** `WatchLoggingState` has no `isActive` (`canLog` is
   the nearest thing and does not answer the same question), so `.onChange(of: host.engine.session?.status)`
   clears `showingMenu` whenever the status is not `.active`. A second `.onChange(of: host.rating.isPromptOwed)`
   clears it too, because the brief requires the owed question to win over an open sheet.
3. **The rest branch's button is a verbatim duplicate with no accessibility label.** S-3103 requires the branch's
   own text to carry `Image(systemName: "list.bullet")`, and the logging surface's button has no
   `.accessibilityLabel`, so "the same accessibility label" means the same (absent) one.
4. **`docs/watch-app-setup-and-qa.md` step 10 was corrected, not only appended to.** D-3101 makes its "extra
   space above End Session" false; item 8 named only the appended **(owner)** step, and leaving a knowingly false
   device step seemed worse than the one-line correction.

Phase 2A (developer, 2026-10-13):
1. **The wrist's recents are its own sessions, so S-3107's fixture seeds one.** `routines_down` carries no
   recents: `WatchStartPaths.restore()` derives them from the stored sessions (`recentlyUsed`), so the contract's
   `routines_down` alone leaves `fallbackExercises` already A-to-Z (`bench, plank, pull-up`) and S-3107 would be
   green at base. The fixture seeds a completed session whose ladder is `[ex-plank, ex-goblet-squat]`, which
   reproduces the contract's `fallback.expected` order ([plank, goblet-squat, bench, pull-up]); a completed
   session does not block `startFreeWorkout()` (`createSession` holds only an `active` one).
2. **`deriveExerciseSections` groups contiguous runs, not one section per key.** D-3110 makes the concatenation
   of the sections equal the input, so a key that reappears after another opens a second section, while
   `deriveAddExerciseLetters` may skip a repeat (a jump needs one target per key). S-3105's fixture keeps the two
   consistent — no symbol that sorts after `z` — so the untouched S-3908 is unaffected.
3. **S-3113's 21-row fixture is a catalog-only `routines_down`.** Built by the file's own message helper with
   `routines: []` and ids `ex-l01`…`ex-l21`, the shape
   `watch/sync_protocol/fixtures/valid/routines_down_catalog_only.json` pins (the schema allows `minItems: 0`),
   so the wrist's whole list is the catalog's own and the gate is measured on 21 rows, then on 20 once one is
   added to the ladder.
4. **`availablePickerExercises` is an explicit filter, not a read of `pickerRows`.** Deriving it from the rows
   would make S-3113 an identity between a thing and itself; the filter states the rule (the ladder's ids out of
   `addableExercises`, in its order) so the assertion can fail, and it did under the mutation.

Phase 2B (developer, 2026-10-13):
1. **The shared `List` sets `.listStyle(.plain)`.** The brief's safe-API list names the constructs, not the
   style; the watchOS default list style is carousel/paged, which would break a section-per-letter scrolling
   list, so the one style that keeps the `List` a plain scrolling list is set explicitly.
2. **The picker's phone-search hint sits below the list, not inside it.** D-3112's API has no footer slot and
   the hint must not scroll away with the rows, so the picker wraps the shared view in a `VStack(spacing: 0)`
   with the hint after it (the pre-2B body had it as the last row inside the `ScrollView`).
3. **Sections are walked by index, with `.id(section.letter)` on the header.** D-3112 pins the id, and
   `deriveExerciseSections` may open a second run for the same key (S-3105/D-3110), so the `ForEach` iterates
   `sections.indices` — two rows may not share a `ForEach` identity — while the jump keeps targeting the header's
   letter; a repeated key therefore jumps to its first run, which is the run the grid's one entry per key names.
4. **Item 2's "the leading rows first and prominent" loses to its own "the letter grid as the list's first
   row".** The grid is the `List`'s first row as item 2 and D-3112 both say; the leading rows sit directly
   below it, before the letter sections — otherwise the grid would not scroll with the content as D-3112
   requires.
5. **The empty state renders leading-aligned for both entry points.** The shared component holds one shape; the
   menu's list already rendered its empty text leading-aligned, and the picker's was centred, so the picker's
   empty text is now left-aligned too. Same words in both.
6. **S-3106 is proven by mutation rather than `prove-red`.** S-3106 reads `WatchMenuView.swift`, which at
   `0da2a72` has no Phase 1/2A symbols, so the carried test file cannot compile: `prove-red HEAD` would report a
   build failure, not a red assertion. The mutation (`LazyVStack` line inserted into the shared file) reddens
   the assertion the scenario names and nothing else.

Phase 3 (developer, 2026-10-14):
1. **Item 4's `heartRatePullSeconds`, `lastHeartRateEnd` and the tick all live in the feed, and `refreshHeartRate`
   takes the builder it reads.** The brief's one-line shorthand for item 5 ("`refreshHeartRate()` →
   `sensorFeed.refreshHeartRate()`") does not name the builder; item 5's own text in this plan does
   (`sensorFeed.refreshHeartRate(from: builder)`), so the plan's reading wins — the store hands the builder over
   in `begin` and clears it with `nil` in `end()`, exactly as the D-3113 token list asserts.
2. **`ContentView`'s new `healthStore` property is declared after `init`, not with the other properties.**
   `WatchSensorSourceSourceTests.arguments(of: "HealthKitWorkoutStore", in: view)` reads the *first* occurrence in
   the file, and `testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst` asserts on the construction inside
   `init` — a property declaration above `init` made that pre-existing test red at `:301`, so the declaration sits
   below it with a comment naming the test. Any future `HealthKitWorkoutStore`-typed property placed earlier
   re-breaks it.
3. **One immediate read on hand-over, and `lastHeartRateEnd` reset when the builder is cleared.** The plan's tick
   and activation reads both answer "strictly newer than `lastHeartRateEnd`"; a beat collected between the
   collection starting and the first tick would otherwise be dropped, so the hand-over itself reads once, and the
   `nil` hand-over forgets the instant rather than carrying it into the next session.

Fix round 1 (developer, 2026-10-14):
1. **The trailing content is `AnyView?`, not a generic `Trailing: View`.** The brief allows either, and neither is
   compiled by any agent check (all three views are `#if os(watchOS)`, which `swift test` on macOS excludes), so the
   choice went to the construct with no inference risk: one stored `AnyView?` with a `nil` default, built at the
   picker's call site from `paths.phoneReachable`.
2. **The trailing row also renders in the empty state.** The hint is the only thing that tells the user to search on
   the phone, so the empty branch (no rows, no sections — the picker's "nothing synced" case) wraps the empty text
   and the trailing content in one `VStack` instead of dropping the hint. The menu passes nothing, so its empty
   state is unchanged.
3. **`scrollIdsBySection()` walks the sections by index and consumes the rule's letters in order.** The sections
   cannot be keyed by letter (two runs may share one), so the ids come from the rule's output rather than from a
   second copy of it: the letter stays on its first run and a later run renders its header with no `.id`. The view
   therefore cannot drift from S-3114's assertion.
4. **The mutation stands in for `prove-red` in this file, and the restore was checked by reading the file.** The
   carried test reads `WatchExerciseListView.swift`, which is untracked, so at `HEAD` checkouts the test throws a
   file-not-found rather than failing an assertion (`prove-red HEAD` reports exactly that, and the gateway calls it
   a load error): the mutation — `scrollTargetLetters` returning every section's letter — is the proof, four
   assertions red, the original restored exactly and the same run green.

## Feedback

(empty — the owner's or reviewer's findings go here; a non-empty Feedback block is what re-invokes the planner.)

## Open questions

(none from the governor; the planner lists its own here)

Defaults taken — veto any before the handoff that depends on it.

1. **The seeded S-3102 clause `isResting == false` after `log()` contradicts the code.** `WatchLoggingState.log()`
   stops the rest at the logged instant (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:740`)
   and immediately starts the next one (`:746` `startFollowOnTimer()`, `:943-945`), so `isResting` (`:332-337`)
   reads `true` again; `WatchLoggingTimersTests.testS321` already asserts the emitted kinds `["set", "rest",
   "set"]`. The seeded text is kept exactly as written and D-3109/S-3111 carry the executable reading ("the rest
   that was running is closed at the log instant and a new rest row runs"). **Default taken**: measure the closed
   rest + the new rest, not `isResting == false`.
2. **The seeded scenario ids are already in use.** `S-3100`…`S-3117` belong to earlier plans:
   `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorCoordinatorTests.swift:13-25` (S-3100…S-3108,
   S-3111…S-3113, S-3115) and `…/WatchSensorSourceSourceTests.swift:5-18` (S-3109, S-3110, S-3114, S-3116,
   S-3117). The seeded S-3110 also lands in the very file that already holds
   `testS3110TheHostWiresTheSensorsAndRefreshesTheWorkoutFirst` (`:270`), and the seeded S-3109 duplicates
   `testS3109TheFeedIsTheRealSourceAndTheStoreReadsBothTypes` (`:200`) in a different file. **Default taken**:
   keep the seeded ids as the plan's references, name the new methods with the file's own `A`-suffix idiom
   (D-3116) so no two test names collide, and add a `// Plan: …` citation block to each touched test file's
   header (that file's header already carries two). Renumbering the plan to a free block (for example
   S-3200…S-3213) is the cleaner fix and is one edit away if the owner says so.
3. **S-3103's scan forces a duplicated button.** The seeded text requires the *rest branch's own text* to contain
   `NavigationStack` **and** `Image(systemName: "list.bullet")`, so a shared toolbar/sheet modifier holding the
   button cannot satisfy it. **Default taken**: duplicate the button text in both branches (D-3114) and share
   only the sheet, which is what D-3102's "or equivalent" allows. A looser scan (assert the button once and a
   shared modifier used by both surfaces) would need the seeded text changed.
4. **Which rows gate the picker's letter grid.** The menu gates on the rows its list draws; the picker's list
   draws the *available* rows plus a few in-session ones. **Default taken**: gate on the available rows
   (`deriveExerciseListLetters(paths.availablePickerExercises)`, D-3110/D-3111); the only observable difference
   is within one row of the 20 boundary when the ladder already holds exercises (S-3113 (c)).
5. **Two existing bridge tests must change their expectation.** `WatchConnectivityBridgeTests.swift:~845-897` and
   `~899-920` assert the phone's fallback order and go red on D-3111. **Default taken**: update both in place —
   same names, same offered-once clauses, new expected order (`docs/state_management/watch_surface.md` cites
   them by name, so they are not renamed and not deleted).
6. **Doc sizes could not be measured.** A `find`/`wc`/`head` shell attempt is denied by this run's policy, so
   `docs/state_management/watch_surface.md` is 737 lines and only *estimated* at ~56 KB (above the 52 KB advisory
   band, below the 64 KiB hard ceiling). **Default taken**: every phase that edits it runs
   `test/docs_indexing_contract_test.dart` and keeps its additions to ≤12 lines; if that test reds, the section
   moves to a part page rather than growing the file. Governor action: none needed unless the owner wants the
   exact figure recorded in the plan.
7. **No agent check compiles the app target.** `swift test` builds the package only, and the watch app needs
   `xcodebuild` on a watchOS simulator, which only the governor runs. So Phase 1's `ContentView.swift` change and
   Phase 3's feed change are held by source scans, the reviewer's diff read and the owner's device checks.
   **Default taken**: proceed; the governor may run the app build after Phase 1 (a cheap compile-level check that
   would catch a typo in the rest branch) if it wants one before Phase 2B.
8. **How the sheet learns that no session is active.** The seeded D-3102 says the sheet "still closes when no
   session is active" but names no observable. **Default taken**: close it when `host.logging.isActive` turns
   false (equivalently, when the engine's session status leaves `active`), whichever the host already exposes;
   the developer records which in the Assumption Log. This is the one mechanic in Phase 1 the scans do not pin.
