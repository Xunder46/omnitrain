# Feature: 176 — the watch Start screen's modality grid (Free workout replaced)

> Status: DRAFT — owner unavailable; defaults marked **owner to confirm**
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md` (+ `docs/design_system.md` for the wrist rules, `docs/state_management/watch_surface_wrist.md` for the surface this edits, `.github/copilot/pr-scope-budget.md`)
> Related plans: 57 (cancel-empty-free-workout), 129 (Planned button), 168/170 (Health type precedence), 171 (Discard — the same source-scan pattern)

## Overview

The native watchOS Start surface (`WatchStartView`) loses its **Free workout**
button and gains a **2×2 grid of modality buttons at the top**, in the phone's
colours and short labels: **Cardio, Resistance, Sports, Isometric**. Beneath the
grid: the Planned row and the routines, exactly as today. Tapping a cell starts a
session carrying that modality with **no exercises**, then opens the same
exercise picker sheet the Free workout opened; closing that sheet without a pick
cancels the empty session exactly as plan 57 built.

One behavioural seam this plan must settle: **a modality session with no
exercises would open its platform workout immediately** with the modality's
default Health type (`WatchWorkoutLifecycle.action`,
`WatchPlatformWorkout.swift:499-512` + `WatchActivityTypes.forSession`,
`:249-253`), and the type is fixed once opened (S-8808) — so a Cardio start
followed by a Brisk Walk pick would be recorded as a **run**. The Free workout
today opens no workout until an exercise exists. This plan keeps modality starts
consistent with that (D-17603, **owner to confirm**).

The Diagnostics button is being hidden by plan 177: it stays where it is here.

## Resolved Decisions (Ledger)

- **D-17601 (owner decision, 2026-11-15).** The "Free workout" button on the
  watch Start screen is REPLACED by a 2×2 grid of modality buttons at the top,
  in the phone's colours and labels. Beneath the grid: Planned and the routines
  (as today). The owner accepts that on a 40 mm watch the grid pushes the
  routines below the first screen (they scroll; Digital Crown). Plan 177 hides
  the Diagnostics button; this plan does not touch it.
- **D-17602 (the values live in one shared contract; constants, not synced).**
  A new `watch/contract/watch_modality_start_contract.json` carries the four
  rows, in phone home-tile order: `cardio_endurance`/"Cardio"/`#43A047`,
  `resistance_lifting`/"Resistance"/`#5B9BD5`, `sports`/"Sports"/`#E63946`,
  `isometric_stretching`/"Isometric"/`#FFA726`. The hexes are exactly the phone's
  `ModalityColors` constants (`lib/core/constants/modality_colors.dart:9-13`) and
  the labels exactly the phone's home-tile labels
  (`lib/core/constants/home_tiles.dart:67, 75, 94, 67`) — not the long
  `ModalityDisplay.names` ("Cardio / Endurance"), which do not fit a 40 mm cell.
  The watch receives only a theme ACCENT today (`preferences_down`
  `accentColorHex`), so the four colours are **constants in the watch package**
  (`WatchModalityStart.swift`), held to the contract by a Swift test; a Dart
  parity test holds the phone's own tokens to the same contract, so a phone
  token change fails the Dart suite until the contract row moves with it. This
  follows the existing pattern: both suites read `watch/contract/*.json`
  (`WatchAccentTests.swift:9` reads `watch_accent_contract.json`;
  `test/watch_accent_contract_test.dart:37` reads the same file).
- **D-17603 (the workout-open rule — owner to confirm).**
  `WatchWorkoutLifecycle.action` (`WatchPlatformWorkout.swift:499-512`) gains one
  guard: a **wrist-created** session (`source == "watch"`, the engine's own
  marker, `WatchSessionEngine.swift:121`) whose `exercises` are empty returns
  `.none` even when its modality resolves a type — a modality start, like a Free
  workout today, opens its platform workout **when the first exercise is picked**.
  At that moment `WatchActivityTypes.forSession` (`:249-253`) resolves in its
  existing order: a named Health kind on the picked exercise
  (`forNamedHealthKinds`, `:226-238`; plans 168/170) **beats** the modality
  default; a pick that names no kind falls to the modality default
  (`WatchActivityTypes.byModality`, `:62-94`: cardio_endurance → running,
  resistance_lifting → traditionalStrengthTraining, isometric_stretching →
  flexibility, sports → other). So "Cardio start + Brisk Walk pick" records as
  **walking**, not running. Scope guard: the rule is keyed on `source`, so
  **phone-started (followed) sessions and routine sessions are untouched** — they
  open as today (plan 125d; routines always start with their template's
  exercises). Alternative considered and rejected: a uniform empty-session wait
  with no source check — it would change plan 125d's phone-mirror behaviour, a
  regression this plan has no mandate for.
- **D-17604 (the start path).** `WatchSessionStartPaths` gains
  `startModalityWorkout(_ modality: String) async -> WatchSessionRecord` beside
  `startFreeWorkout()` (`WatchStartPaths.swift:727-731`):
  `await engine.createSession(modality: modality)` — a session with that
  modality and **no exercises**; the engine's one-session rule (D-171) already
  refuses a second start by returning the held row. The view then opens the same
  picker sheet (`WatchStartView.swift:256`). The picker is **not filtered** to
  the modality: `WatchCatalogExercise`
  (`WatchRoutineRecords.swift:27-71`) carries no modality field at all — only
  `exerciseId`, `name`, `capabilities`, `roundDurationSecs`, `healthActivity` —
  so filtering would need a protocol/catalog change, which is out of scope. No
  key validation is added: the grid offers only the four contract keys, all
  `byModality` keys.
- **D-17605 (the cell's look, one rule for every size).** The grid is a
  `LazyVGrid` of **two flexible columns**, 4 pt column and row spacing (the
  surface's own `surfaceInset`, `WatchStartView.swift:96`), each cell a
  Button of **fixed height 44** with a one-line `.footnote` semibold label
  (ellipsis) on a fill of the modality's colour, drawn through the existing
  accent machinery: `WatchAccent.worn(hex: cell.hex).color` with `.labelColor`
  text (`WatchAccent.swift:52-61`, the D-3704/D-3705 rule incl. the 3.0
  contrast floor — all four contract hexes clear it and take dark labels;
  the wrist computes this from the hex, the contract carries no flag). Same
  geometry on 40/41/45 mm and 44/49 mm: the flexible columns widen, the height
  and type size do not change — the wrist carries its own values rather than
  scaling a phone token (`docs/design_system.md:11-15`). No Crown binding is
  added; the surface's `ScrollView` scrolls and the Crown follows it, so the
  routines stay reachable below the grid.
- **D-17606 (the Dart twin is unchanged).** `lib/watch/` **does** have a start
  screen — `lib/watch/start/watch_start_screen.dart` (Free workout button at
  `:85` and `:131-134`) — but it is a dev/debug surface (its only app-side caller
  is `lib/watch/debug/watch_start_debug_main.dart:326`) that already does **not**
  mirror the native surface: no Planned button, no Diagnostics, no phone-status
  line, and its paths carry no `cancelEmptyFreeWorkout` twin at all. It keeps
  its Free workout button; `startFreeWorkout()` stays in both paths
  implementations (`WatchStartPaths.swift:727`;
  `lib/watch/start/watch_session_start_paths.dart:211`) and both suites keep
  covering it, so nothing is deleted. The twin's grid parity is not owed.
- **D-17607 (cancel/empty behaviour is unchanged — plan 57).** The picker
  sheet's `onDismiss: cancelIfNothingPicked` (`WatchStartView.swift:256`,
  `:320-324`) calls `paths.cancelEmptyFreeWorkout()`
  (`WatchStartPaths.swift:736-746`), whose guard is modality-agnostic — active
  **and** zero exercises — so a modality-started empty session is cancelled the
  same way; a pick, or a slot the phone pushed while the picker was open, keeps
  it; the host re-reads on `onFreeWorkoutCancelled`
  (`ContentView.swift:549`, plan 57 D-2/D-3). No change to any of it.
- **D-17608 (what the wrist loses).** Removing the button makes a wrist-created
  **no-modality** session unreachable from the Start surface: the wrist can no
  longer start "free training" (a session with no modality). What remains
  reachable: routine starts (a routine without a Focus still starts a
  no-modality session — `WatchRoutineRecords.swift:323-326`), the Planned row,
  and Add Exercise inside any live session. Free training remains a phone
  concept; the phone's mirror and importer are untouched. Accepted by the owner.

## Feature Invariants

- One session at a time: every grid tap goes through `createSession`, so a live
  session is returned unchanged and nothing new is emitted (D-171; the engine
  enforces it, no path adds a guard).
- An empty modality session is a waiting session, like an empty Free workout:
  no platform workout is opened for it, and closing the picker cancels it
  (D-17603, D-17607).
- The workout's Health type is decided once, at open, by the first decidable
  answer: the first pick's named kind, else the session's modality (D-17603,
  S-8808's rule kept).
- A routine picked over a live empty modality session fills it in place and
  **keeps that session's modality** (D-12561, `WatchStartPaths.swift:668-681`) —
  existing behaviour, regression-guarded here.
- The four modality colours/labels exist in exactly one contract file; the
  watch constants and the phone tokens are both held to it (D-17602).

## Requirements

- R-1: the Start surface's first content is a 2×2 modality grid in phone order
  (Cardio, Resistance, Sports, Isometric), wearing the contract's colours and
  short labels (D-17601, D-17602, D-17605).
- R-2: tapping a cell starts a session with that modality and no exercises and
  opens the exercise picker; the picker is unfiltered (D-17604).
- R-3: closing the picker without a pick cancels the empty modality session and
  the host re-reads (D-17607).
- R-4: a wrist-created empty modality session opens no platform workout; the
  first pick opens it, typed by the pick's named kind, else the modality default
  (D-17603 — owner to confirm).
- R-5: the Free workout button and its view helper are gone from the native
  surface; `startFreeWorkout()` stays in the paths and both suites (D-17606,
  D-17608).
- R-6: Planned and the routines keep their current order and styles beneath the
  grid; the Diagnostics button is untouched (plan 177 owns it).
- R-7: the wrist surface doc and the wrist QA script describe the grid
  (Phase 4).

## Acceptance Criteria (each maps to ≥ 1 scenario)

- AC-1 the grid is the surface's first content, 2×2, contract values, VoiceOver
  labels (S-17601, S-17602, S-17603).
- AC-2 a modality tap starts the right session and opens the picker; a second
  start is refused by the engine (S-17604, S-17605).
- AC-3 the cancel story is plan 57's, unchanged, for modality starts
  (S-17606).
- AC-4 the workout-open rule holds and the Brisk Walk case records as walking
  (S-17607, S-17608, S-17609 — owner to confirm).
- AC-5 routine starts and phone-started sessions are unchanged (S-17610,
  S-17611).
- AC-6 the Free workout button is gone; no routines yet still reads sensibly
  (S-17612, S-17613).
- AC-7 the docs say the grid (S-17614, Phase 4).

## Existing-Functionality Impact

| Touched surface | What already reads it (grep / test) | Effect | Guarded by |
|---|---|---|---|
| `WatchStartView.body`'s top block | `WatchPlannedSurfaceSourceTests.testS8965ThePlannedButtonComesBeforeTheRoutineList` (planned above the empty-routines branch and the routine `ForEach` — both still true with the grid above) | grid inserted **above** the planned block (`WatchStartView.swift:161`); the doc's "first thing on the surface" wording for Planned is corrected | S-17601, S-17610 |
| `Button("Free workout")` + view helper `startFreeWorkout()` | `WatchStartView.swift:192-195` (button), `:286-288` (helper); tests that call the **paths** method (`WatchSessionStartPathsTests.swift`, plan 57's list at l.666-792) | button + helper removed; the paths method stays; paths tests rerun unchanged | S-17612 |
| Picker sheet + `cancelIfNothingPicked` | `WatchCancelEmptyFreeWorkoutTests` (S-8701..S-8706), `WatchStartView.swift:256, 320-324` | unchanged; now also serves modality starts | S-17606 |
| `engine.createSession(modality:exercises:)` | `WatchSessionEngine.swift:362-403`; D-171 refusal; the phone's importer consumes an abandoned empty session (`lib/core/services/watch_session_importer.dart:156`, plan 57 D-1) | no engine change; one more caller shape (modality non-nil, exercises empty) | S-17604, S-17606 |
| `WatchWorkoutLifecycle.action` | `WatchWorkoutCoordinatorTests` (incl. `:304-314`), `WatchFitnessFollowsSessionTests` (S-89-1/S-89-2), `WatchOneWorkoutPerSessionTests`, plan 82 review (`WatchPlatformWorkout.swift:376-389` read) | one new guard on the `.start` branch; every existing case (routine sessions, followed sessions, Free workouts) keeps its answer — proven by the new S-17610/S-17611 regressions | S-17607, S-17610, S-17611 |
| `startFromRoutine`'s fill-in-place rule | `WatchSessionStartPathsTests` (S-178/D-177), `test/watch_session_start_test.dart` S-170/S-171/S-177/S-178 groups | unchanged; new arm: the empty session held is now a modality session — keeps its modality (D-12561) | S-17610 |
| GPS at workout open | `WatchGpsPolicy.isRequired(session)` read in `WatchPlatformWorkout.start` (`:421-425`); `WatchGpsByExerciseTests` | unchanged: the policy reads the session at open time, which now is the first pick's moment for modality starts | S-17608 |
| `lib/watch/` twin | `test/watch_session_start_test.dart` (`WatchStartScreen` widget tests, `:1376-1502`), `lib/watch/debug/watch_start_debug_main.dart:326` | no change in this plan (D-17606) | S-17612 (paths half) |
| `watch_sensors.md:118` ("a session with no modality — every Free workout and…") | the sentence stays true: no-modality sessions still exist (routine-without-Focus, phone free training, the twin); checked, **no edit** | none | D-17608 |
| Stale mentions of "Free workout" taps in `docs/watch-app-setup-and-qa.md` (l.371, 399, 502, 629, 657, 670, 705, 755) | historical owner steps for earlier features | **not rewritten here** (the brief names only the wrist QA doc); listed as residue under Notes | S-17614 |

Standing invariants this could break, from `docs/global_conventions.md` and the
watch plans: D-171 one-session-at-a-time (S-17604), D-12561 the fill-in-place
modality rule (S-17610), plan 57's cancel guard (S-17606), S-8808 the type is
fixed at open (S-17608/S-17609 — the rule exists *because* of it). Every
"unaffected" row above carries its grep or cited test.

## UI Standards Impact

- `docs/design_system.md:11-15`: wrist layout geometry is out of the doc's
  scope; the surface carries its own values (`surfaceInset = 4.0`,
  `WatchStartView.swift:96`), and this plan adds the grid with the surface's
  own values (D-17605), no new exception.
- Colour: the cells reuse the accent machinery (`WatchAccent.worn(hex:)` +
  `.labelColor`, D-3704/D-3705) rather than introducing a new colour rule; the
  values come from the shared contract (D-17602). Colour is never the only
  differentiator: every cell carries its label text
  (`docs/design_system.md`, Accessibility 3).
- `test/ui_standards_contract_test.dart` covers `lib/` minus `lib/watch/` — it
  does **not** govern the watchOS views; the binding guards are the watch
  source-scan suites (`WatchPlannedSurfaceSourceTests.swift` pattern) and the
  shared contract tests (both stacks).
- VoiceOver: each cell exposes "Start Cardio workout" and its siblings
  (`docs/design_system.md`, Accessibility 4).

## Scenarios

### S-17601: the grid is the surface's first content, and Planned stays above the routines
- Fixture: the source text of `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`, comment lines stripped (`WatchPlannedSurfaceSourceTests.engineSource(_:)` pattern).
- Trigger: the source scans run in the suite.
- Flow: the grid's use stands **before** the `if !startablePlans.isEmpty` block (`:161`), which stands before the routine `ForEach` — the existing S-8965 assertions still hold.
- Expected outcome: the scan fails while the grid is missing or sits anywhere but the top; the planned-before-routines order is unchanged.
- Edge case of: none (new surface).

### S-17602: the grid wears exactly the contract's values, on both stacks
- Fixture: `watch/contract/watch_modality_start_contract.json` — four rows `{key, label, hex}` in phone order; Swift constants `WatchModalityStart.cells` (`WatchModalityStart.swift`); the phone's `ModalityColors` and `HomeTiles`.
- Trigger: the Swift contract test and the Dart parity test run.
- Flow: each suite reads the JSON from the repo root (the `Fixtures.swift` contract-loader pattern, e.g. the accent loader at `:104-108`).
- Expected outcome: the Swift cells equal the contract rows key-for-key, label-for-label, hex-for-hex, in order; the Dart test asserts `ModalityColors` hexes and the four `HomeTiles` labels equal the same rows — a phone token change without a contract move fails the Dart suite (D-17602).
- Edge case of: none.

### S-17603: the cell's look and its VoiceOver label
- Fixture: the source text of `WatchStartView.swift` (the grid block) and `WatchModalityStart.swift`'s copy.
- Trigger: the source scans.
- Flow: each cell draws `WatchAccent.worn(hex:).color` with `.labelColor` text; the label is the contract's short word, one line; the accessibility label is `WatchModalityStart.startSentence(label)` = "Start <Label> workout".
- Expected outcome: the scans hold the accent reuse (no raw `Color(hex:)` invention in the view), the fixed cell height, and the four accessibility sentences; a cell with no accessibility label fails the scan.
- Edge case of: S-17601.

### S-17604: a modality tap starts a modality session with no exercises, and only one
- Fixture: `WatchStartHarness` (internal in `WatchSessionStartPathsTests.swift`, ~l.66; members `engine`, `paths`, `store`; launch and first-message receipt as `testS002FreeWorkoutStartsEmptyAndAddsAFallbackExercise` does) — no new harness.
- Trigger: `await harness.paths.startModalityWorkout("cardio_endurance")`.
- Flow: `engine.createSession(modality: "cardio_endurance")` under the mutex.
- Expected outcome: the record is `active`, `modality == "cardio_endurance"`, `exercises.isEmpty`, `source == "watch"`, and a `session_lifecycle` `started` frame plus a snapshot are emitted; a second `startModalityWorkout` (any modality) returns the **held** row unchanged and emits nothing (D-171).
- Edge case of: none.

### S-17605: the picker is unfiltered, and a pick keeps the session's modality
- Fixture: the S-17604 session; the harness's `paths.fallbackExercises` including a distance exercise that names a Health kind (e.g. "Brisk Walk" with `healthActivity == "walking"`, the plan 168 fixture shape) and one that names none.
- Trigger: `paths.pickerRows` / `availablePickerExercises` with the empty modality session live; then `selectExercise(.available(walk))`.
- Flow: the picker's rows are `addableExercises` — the same A-to-Z list the menu shows (D-3111); no modality filter exists to apply (D-17604).
- Expected outcome: the offered rows are the full fallback list, not a modality subset; the pick appends a slot, moves the user to it, and `session.modality` stays `cardio_endurance`.
- Edge case of: S-17604.

### S-17606: closing the picker without a pick cancels the empty modality session
- Fixture: the S-17604 session, plus arms: (a) a session holding a pick, (b) one holding a pushed slot (`engine.insertExercise(slot, moveTo: false)`), (c) a `finishSession()`-ended session, (d) no session.
- Trigger: `paths.cancelEmptyFreeWorkout()` in each arm.
- Flow: plan 57's guard (`WatchStartPaths.swift:736-746`) — active **and** zero exercises.
- Expected outcome: the modality session with no exercises is abandoned (status `abandoned`, cancel returns `true`) and the next start of any kind is free; every arm returns `false` and leaves the session as it was.
- Edge case of: S-17604, S-17605.

### S-17607: a wrist-created empty modality session opens no platform workout (owner to confirm)
- Fixture: `WatchWorkoutCoordinatorTests`' shape — a coordinator over a store; `WatchSessionRecord(source: "watch", modality: "cardio_endurance", status: active, exercises: [])`.
- Trigger: `coordinator.refresh(record)`.
- Flow: `WatchWorkoutLifecycle.action` — the new D-17603 guard answers `.none` although `forSession` would resolve `running`.
- Expected outcome: no `.start`, `platform.running` stays nil, nothing is registered with Health; a Free-workout record (nil modality, empty) answers `.none` exactly as before (regression in the same test).
- Edge case of: none.

### S-17608: the first pick opens the workout, typed by the pick (owner to confirm)
- Fixture: the S-17607 coordinator; two sessions — one whose first slot carries `healthActivity: "walking"`, one whose slot names no kind, both `modality: "cardio_endurance"`, `source: "watch"`.
- Trigger: `refresh` with the exercises present.
- Flow: `forSession` → `forNamedHealthKinds` first (`:226-238`), else `forModality` (`:62-94`).
- Expected outcome: both answer `.start`; the platform `start(_:)` returns `walking` for the named pick and `running` (the modality default) for the unnamed one; a second exercise added later never retypes the opened workout (S-8808 kept).
- Edge case of: S-17607.

### S-17609: Cardio start + Brisk Walk pick records as walking, not running (owner to confirm)
- Fixture: end-to-end on the harness: `startModalityWorkout("cardio_endurance")`, then `selectExercise(.available(walk))`; the coordinator's refresh observes the session through the host's revision bump (the wiring plan 82's review documents).
- Trigger: the pick, then the workout open.
- Flow: D-17603's wait, then S-17608's resolution.
- Expected outcome: the Health workout is opened with the `walking` type; the user-visible statement of S-17607+S-17608 in one chain.
- Edge case of: S-17608.

### S-17610: routine starts are unchanged, including over a live empty modality session
- Fixture: the harness with a synced routine (the contract's `routineSession` shape) and, in one arm, a live empty `cardio_endurance` session; in another, no session.
- Trigger: `paths.startFromRoutine(routineId)` in both arms.
- Expected outcome: with no session held, the routine's slots become the session and the workout opens **at once** (the session has exercises — the D-17603 guard does not apply); over the live empty modality session, the routine fills it in place (same session id, D-177/S-178) and the session **keeps `cardio_endurance`** (D-12561).
- Edge case of: S-17604.

### S-17611: followed (phone-started) sessions are unchanged (owner to confirm)
- Fixture: `WatchSessionRecord(source: "phone", modality: "cardio_endurance", status: active, exercises: [])` — a plan 125d mirror.
- Trigger: `coordinator.refresh(record)`.
- Flow: the D-17603 guard is keyed on `source == "watch"`; a followed session skips it.
- Expected outcome: the workout opens immediately with the modality's type, exactly as today — the phone-mirror behaviour plans 125b/125d pinned is untouched.
- Edge case of: S-17607.

### S-17612: the Free workout button is gone from the native surface; the paths stay
- Fixture: the source text of `WatchStartView.swift` (comment lines stripped) and the paths tests.
- Trigger: the scans and the paths suite.
- Flow: no `Free workout` literal and no view `startFreeWorkout()` helper in the view; `WatchSessionStartPaths.startFreeWorkout` (`WatchStartPaths.swift:727`) remains, with its tests green.
- Expected outcome: the scan fails while either the button or the helper survives; the paths method's tests pass unchanged (D-17606, D-17608).
- Edge case of: S-17601.

### S-17613: no routines yet — the grid is still first and the sentence sits beneath
- Fixture: the source text of `WatchStartView.swift`; the harness with no synced routines.
- Trigger: the scans; a harness read of `paths.routines.isEmpty`.
- Expected outcome: the grid block stands above the `if paths.routines.isEmpty` branch; the "No routines yet. Sync with your phone to get them." sentence and the Sync flow are unchanged; the grid works with the phone off (everything it needs is local — the paths read local storage, `WatchStartPaths.swift:9-19`).
- Edge case of: S-17601.

### S-17614: the docs say the grid
- Fixture: `docs/state_management/watch_surface_wrist.md` (the start-surface section, `:207-360`) and `docs/watch-app-qa-wrist-logging.md` (the numbered steps; 44 today).
- Trigger: Phase 4's edits.
- Flow: the wrist doc gains a grid paragraph (order, colours' source, tap behaviour, the workout-open rule, the unchanged cancel story) and its Planned paragraph's "first thing on the surface" wording is corrected; the QA doc gains **step 45** (device checks) and rewords the "Tap Free workout" taps in steps 1, 20 and 22 to a modality tap.
- Expected outcome: both docs updated inside their size bands (`watch_surface_wrist.md` ~22.9 KB, `watch-app-qa-wrist-logging.md` ~500 lines — both well under the 52 KB split band; the 64 KiB ceiling is enforced by `test/docs_indexing_contract_test.dart`).
- Edge case of: none.

## Iteration 1

### Phase 1: the contract, the watch constants and the parity tests (@developer)
1. [x] Create the shared contract — `watch/contract/watch_modality_start_contract.json` · top-level: `description`, `gridOrder` (the four `{key, label, hex}` rows of D-17602, in phone home-tile order: `cardio_endurance`/"Cardio"/`#43A047`, `resistance_lifting`/"Resistance"/`#5B9BD5`, `sports`/"Sports"/`#E63946`, `isometric_stretching`/"Isometric"/`#FFA726`), and `startSurfaceSentence` pattern note ("Start <Label> workout"). No flag for label darkness — the wrist computes it from the hex, as the accent contract does (D-17602, D-17605)
2. [x] Add the watch constants — `watch/watchos/Sources/WatchSessionEngine/WatchModalityStart.swift` · new `WatchModalityStart` enum: `struct Cell { key, label, hex }`, `static let cells: [Cell]` (the four, in contract order), `static func startSentence(for label: String) -> String` = `"Start \(label) workout"`. Platform-independent, so `swift test` compiles it (D-17602)
3. [x] Add the Swift parity test — `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartContractTests.swift` · reads the contract from the repo root (`Fixtures.swift`'s contract-loader pattern, accent loader at `:104-108`): asserts `WatchModalityStart.cells` equals `gridOrder` row-for-row (key, label, hex, order) and each hex parses as `#RRGGBB` (D-17602)
4. [x] Add the Dart parity test — `test/watch_modality_start_contract_test.dart` · reads the same JSON: asserts `ModalityColors.byModality`'s four entries (`lib/core/constants/modality_colors.dart:14-19`) equal the contract hexes and the four `HomeTiles` labels (`lib/core/constants/home_tiles.dart:67, 75, 94, 67`) equal the contract labels, in `HomeTiles.all` order — a phone token change without a contract move fails here (D-17602). Plain `test()`, no Hive, no `testWidgets`

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (full; the Swift test is red — it does not compile — before item 2, green after) and `.github/copilot/scripts/macos/gateway.sh test` (full `flutter test`; the Dart parity test is red before the contract exists, green after). Paste the pass/fail counts in the evidence file.
**Predicted Files**: `watch/contract/watch_modality_start_contract.json`, `watch/watchos/Sources/WatchSessionEngine/WatchModalityStart.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartContractTests.swift`, `test/watch_modality_start_contract_test.dart`. Nothing else.
**Phase 1 verification notes (Conductor, date):** —

### Phase 2: the start path, the workout-open rule and the behaviour tests (@developer) — after Phase 1
1. [x] Add the start path — `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` · `WatchSessionStartPaths.startModalityWorkout(_ modality: String) async -> WatchSessionRecord`, beside `startFreeWorkout()` (`:727-731`): `await engine.createSession(modality: modality)`; no guard, no throw (D-17604)
2. [ ] Add the workout-open guard — `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` · `WatchWorkoutLifecycle.action` (`:499-512`): inside the active branch, before answering `.start`, `if session.source == "watch", session.exercises.isEmpty { return .none }` — the engine's own wrist-source marker (`WatchSessionEngine.swift:121`), the literal spelled with a comment naming D-17603 and D-171. **Owner to confirm**
3. [x] Red→green path tests — `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartTests.swift` · new file on `WatchStartHarness`: S-17604 (start, modality, empty, one-session refusal, the `started` frame + snapshot emitted), S-17605 (picker rows unfiltered; the pick keeps the modality), S-17606's four arms (cancel; pick; pushed slot; ended; no session)
4. [ ] Lifecycle tests — `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutCoordinatorTests.swift` · new cases beside the existing ones: S-17607 (watch-sourced empty modality session → `.none`; the Free-workout record still `.none`; a routine record still `.start`), S-17608 (first pick opens: named kind wins, unnamed falls to the modality default), S-17611 (a `source: "phone"` empty modality session still `.start`) — **owner to confirm** on the rule itself, the tests pin it either way
5. [x] Regression — `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift` · the S-17610 arm is added: a routine picked over a live empty `cardio_endurance` session keeps that session's modality and session id (D-12561); rerun the file's `startFreeWorkout` tests (plan 57's list, l.666-792) unchanged

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (full package) green; the red→green table for items 3–4 lands in `2026-11-15-176-watch-modality-start-grid-plan.evidence.md`.
**Amendment note:** item 2 (the D-17603 guard) and item 4 (its coordinator cases) are dropped by D-17608/D-17609 and stay unticked; item 1's shape is superseded — Path 3 ships as `startModalityWorkout(_:with:)` (see Progress).
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutCoordinatorTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`. Nothing else.
**Phase 2 verification notes (Conductor, date):** —

### Phase 3: the grid view and the source-scan guards (@developer) — after Phase 2
1. [ ] Add the grid — `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` · new `private struct WatchModalityStartGridView: View`: `LazyVGrid(columns: [GridItem(.flexible(), spacing: Self.surfaceInset), GridItem(.flexible())], spacing: Self.surfaceInset)` over `WatchModalityStart.cells`; each cell a `Button` of fixed height 44, label one-line `.footnote` semibold, background `WatchAccent.worn(hex: cell.hex).color`, foreground the same accent's `.labelColor` (D-17605)
2. [ ] Wire the tap — `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` · `WatchModalityStartGridView` takes `onPick: (String) -> Void`; `WatchStartView.body` places the grid **above** the `if !startablePlans.isEmpty` block (`:161`) and passes a `startModality(_:)` helper: `Task { _ = await paths.startModalityWorkout(key); pickingExercise = true }` — the same shape `startFreeWorkout()` (`:286-288`) has today; the sheet, its `onDismiss` and `onSessionStarted` are untouched (D-17604, D-17607)
3. [ ] Remove the Free workout surface — `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` · delete the `Button("Free workout")` block (`:192-195`) and the view's private `startFreeWorkout()` helper (`:286-288`); the paths method stays (D-17608). The Diagnostics button (`:249`) is **not** touched — plan 177 owns it
4. [ ] VoiceOver — `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` · each cell `.accessibilityLabel(WatchModalityStart.startSentence(for: cell.label))` ("Start Cardio workout", "Start Resistance workout", "Start Sports workout", "Start Isometric workout") (D-17605)
5. [ ] Source-scan guards — `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSurfaceSourceTests.swift` · new tests: S-17601 (the grid's use before the `if !startablePlans.isEmpty` line; the S-8965 order tests rerun unchanged), S-17603 (the accent reuse, the fixed height, the four accessibility sentences), S-17612 (no `Free workout` literal and no view `startFreeWorkout()` helper), S-17613 (the grid above the `paths.routines.isEmpty` branch)
6. [ ] Copy guard — `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartContractTests.swift` · extend with the S-17603 copy half: `startSentence(for:)` output for all four labels, exactly the contract's words

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (full) green; **Governor action after this phase**: compile-check the app target — `xcodebuild -target "OmniTrain Watch App" -sdk watchsimulator` (the view is compiled only into the watch target, `swift test` never sees it; `ContentView.swift` needs **no change** — the host's start-screen branch, the sheet wiring and `onFreeWorkoutCancelled: { host.noteSurfaceChange() }` at `ContentView.swift:546-558` already serve the grid).
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSurfaceSourceTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartContractTests.swift`. Nothing else — in particular **not** `ios/OmniTrain Watch App/ContentView.swift`.
**Phase 3 verification notes (Conductor, date):** —

### Phase 4: docs and the QA step (@developer) — after Phase 3
1. [ ] The start-surface section — `docs/state_management/watch_surface_wrist.md` · "The wrist's start surface, and what an arrival does to it": a new grid paragraph at its top (order, contract source, tap → session+picker, the unfiltered picker, the workout-open rule of D-17603 with its owner-to-confirm mark, what the wrist lost — D-17608); correct the Planned paragraph's "first thing on the surface" wording (`:207-243`); extend the plan-57 cancel paragraph (`:247-256`) to say modality starts cancel the same way; name the new test files; keep the page inside the 64 KiB ceiling (`test/docs_indexing_contract_test.dart`)
2. [ ] QA step 45 — `docs/watch-app-qa-wrist-logging.md` · the next numbered step after 44 (`:510`): on a real watch — the grid's four cells in the phone's colours and labels; VoiceOver reads "Start Cardio workout" etc.; tap Cardio: the picker opens unfiltered; close it without picking: back on Start, nothing in Fitness; pick Brisk Walk under a Cardio start: the workout opens as **walking**, not running (D-17603's owner check); Crown-scroll to the routines on a 40 mm watch
3. [ ] Reword the stale taps — `docs/watch-app-qa-wrist-logging.md` · steps 1 (`:10-11`), 20 (`:220`) and 22 (`:275`): replace "Tap **Free workout**" with the modality tap the step's check needs; every other Free-workout sentence that describes the *picker* or the *paths* stays true
4. [ ] Size check — `test/docs_indexing_contract_test.dart` rides in the full suite; confirm both docs sit under the 52 KB band at edit time (both are far under it at planning)

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test` (full `flutter test` — the docs indexing contract and the Dart parity test ride in it) green.
**Predicted Files**: `docs/state_management/watch_surface_wrist.md`, `docs/watch-app-qa-wrist-logging.md`. Nothing else.
**Phase 4 verification notes (Conductor, date):** —

## Files Affected (whole feature)

- `watch/contract/watch_modality_start_contract.json` — Phase 1 (new)
- `watch/watchos/Sources/WatchSessionEngine/WatchModalityStart.swift` — Phase 1 (new)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartContractTests.swift` — Phases 1, 3 (new)
- `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` — Phase 2
- `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` — Phase 2
- `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartTests.swift` — Phase 2 (new)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutCoordinatorTests.swift` — Phase 2
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift` — Phase 2
- `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` — Phase 3
- `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSurfaceSourceTests.swift` — Phase 3
- `docs/state_management/watch_surface_wrist.md`, `docs/watch-app-qa-wrist-logging.md` — Phase 4
- Dependents that only read a touched surface and change nothing:
  `ios/OmniTrain Watch App/ContentView.swift` (the host wiring already serves
  the grid; compile-checked, not edited), `WatchSessionEngine.swift`
  (`createSession` gains a caller shape, no change), the Dart twin
  `lib/watch/` (D-17606), the phone (`lib/` untouched except the new parity
  test), the phone's importer (an abandoned empty modality session is consumed
  without history, plan 57 D-1).

## Notes

- Phase graph: 1 → 2 → 3 → 4, strictly ordered: the constants (1) feed the
  paths' test fixtures and the grid (3); the view (3) needs the paths method
  (2); the docs (4) name what 1–3 built. No reordering offered: each phase's
  tests fail without its predecessor.
- Intermediate states: after Phase 2 the surface still shows the Free workout
  button (the paths method exists, unused); after Phase 3 the button is gone.
  Both are shippable checkpoints.
- **Owner-confirm list** (none blocks implementation): D-17603 whole (the
  workout-open rule and its `source == "watch"` keying — the Brisk Walk case is
  its user-visible test); D-17605's cell height (44) and label size
  (`.footnote` semibold); D-17606 (the Dart twin keeps its Free workout
  button).
- Residue, deliberately not this plan's: `docs/watch-app-setup-and-qa.md`'s
  eight "Free workout" taps (l.371–755) describe historical owner steps whose
  *paths* still exist; sweep them when the owner asks.
- Legacy handling: none. No stored representation, migration, seed, or SQLite
  contract change; no new frame type (the grid emits the frames any start
  emits), so the replay/soak suites and `watch/sync_protocol/` are untouched.
- QA note for the executor: `swift test` compiles only the package; the view is
  proven by source scans plus the governor's `xcodebuild` compile check and the
  owner's device check (the plan 168/171 pattern). No `testWidgets` anywhere in
  this plan.

## Progress

- [x] Phase 1 (@developer): contract, constants, parity tests — **Complete**. 5 Swift tests + 4 Dart tests green; a mutated contract hex turns both red (evidence: Phase 1).
- [x] Phase 2 (@developer): start path, workout-open rule, behaviour tests — **Complete (amended)**. Path 3 is now `pendingModalityStart` / `beginModalityStart(_:)` / `cancelModalityStart()` / `startModalityWorkout(_:with:)` (D-17608/D-17609); `WatchModalityStartTests` 11 green, S-17610's two pins green at their new call sites, package at 1509 tests. Item 2 (the D-17603 guard) and item 4 (its coordinator cases) are dropped by the amendment, not implemented; the earlier Blocked note is superseded.
- [x] Phase 3 (@developer): grid view, source-scan guards — **Complete**. `WatchModalityStartGridView` above the plan, `startModality(_:)`, the `Free workout` button and the view's helper gone, the picker's start mode; 9 new source guards (15 in `WatchPlannedSurfaceSourceTests`) proven RED AT HEAD (10 failures) then green.
- [x] Phase 4 (@developer): docs and the QA step — **Complete**. The wrist doc's grid paragraph, its Planned wording and its cancel paragraph; QA steps 1, 14, 20, 29, 38, 43 reworded and step 45 added. `flutter test`: 7673 passed, 0 failed, 4 skipped.
- [ ] **Unpredicted dependent, for re-plan** — `WatchNutritionWiringSourceTests.testS7205NutritionSitsRightUnderFreeWorkout` (plan 72) fails: it pins `Button("Free workout")` in `WatchStartView.swift`, which D-17608 and S-17612 remove. Package: 1509 tests, 1 failure. Re-basing another plan's test is not this run's edit.

## Open Items

- D-17603 as written (`session.source == "watch", session.exercises.isEmpty` → `.none`) suppresses the workout open for **every** wrist-started session, because `createSession(modality:)` defaults `source: "watch"` and the whole existing open-test fleet builds sessions that way — 14 tests in `WatchWorkoutCoordinatorTests`, `WatchFitnessFollowsSessionTests`, `WatchContinueRecoveredWorkoutTests`, `WatchWorkoutAdoptBeforeRestoreTests`, `WatchOpenFailureTests`, `WatchMenuTests`. **Closed by the amendment**: D-17608 drops the rule; nothing is created until the pick, so a session with no exercises never exists on the wrist.
- So the rule needs a **discriminator narrower than `source`** — e.g. `session.exercises.isEmpty && session.modality != nil`, or a record field naming the grid as the start's origin (a model change, which the plan's Notes exclude) — or those 14 tests need re-basing. Either is a re-plan, not an execution edit. **Closed by the amendment.**
- Phases 3 and 4 are otherwise independent of the rule and can be executed in a fresh session once it is settled. **Done this run.**
- **Re-plan needed (new):** `WatchNutritionWiringSourceTests.testS7205NutritionSitsRightUnderFreeWorkout` (plan 72) anchors the Nutrition button's position on `Button("Free workout")` in `WatchStartView.swift`. D-17608, S-17612 and Phase 3 item 3 delete that button, so the pin is now false and the class is red. Re-basing it means either re-anchoring S-7205 on the grid (the surface's first start control) or dropping its Free-workout clause; both edit a test outside this plan's Predicted Files.

## Assumption Log

- **Phase 1 was not written red-first.** Every new symbol is uncompilable at HEAD, so the red run could only be a build failure; proved instead by mutating a contract hex (`#43A047`→`#43A048`): Swift `testS17602TheCellsAreTheContractsRowsInOrder` red, Dart `S-17602 every row wears the phone's own ModalityColors hex` red, both green again after the exact restore.
- **Phase 2 stopped rather than absorbing item 2.** Options were: re-base 14 existing tests outside the Predicted Files, weaken the rule, or stop. Chosen: roll the guard back, keep the suite green, mark the phase Blocked (scope) — the plan's own protocol and its "Owner to confirm" mark on D-17603. The governor then superseded it with D-17608/D-17609.
- **A grid tap while a session is already live still opens the picker.** Options: dim the grid while `engine.session` is active, or leave it and let the paths refuse. Chosen: leave it — the pick goes through `startModalityWorkout(_:with:)` → `createSession`, whose D-171 refusal hands the held row back and emits nothing, which `testS17605ASecondPickReturnsTheHeldSessionAndEmitsNothing` pins. Dimming would need a rule the plan does not have.
- **The modality start mints its own slot id.** `availableSlotId(for:)` is private and reads `engine.session`, which is nil before the pick creates the session, so Path 3 uses `exercise.slotId(token: sessionToken(from: newId()))` — the same `sx-<exerciseId>~<token>` shape routine starts produce. The alternative (making `availableSlotId` internal) widens a private surface for one caller.
- **The cell's corner radius is spelled 8.0.** No wrist token covers a grid cell: the radius tokens in the design system are the phone's `OmniTheme` values, and the wrist's routine buttons carry their own style. 8.0 matches the neighbouring bordered buttons at text size.
- **`routineNotice` is not cleared by a modality tap.** S-9004's pin counts exactly three `routineNotice = nil` sites (plan 72/129), and the documented rule is "cleared on the next start of any routine" — a modality tap is not one. The extra clearing line was removed rather than re-basing that test; this is why `WatchPhoneProblemWiringSourceTests` stays green.
- **Phase 4's stale-tap list was off by line.** The "Tap Free workout" taps sat in steps 1, 14 (the picker comparison), 20, 29, 38 and 43, not "1, 20 and 22"; step 22 never named the button. All six were reworded to the modality tap their check needs.

## Feedback

Phase 2 item 2 could not be implemented as planned. `WatchWorkoutLifecycle.action`'s D-17603 guard, keyed on `session.source == "watch"` with empty exercises, is true of every session the existing suite starts through `WatchSessionEngine.createSession(modality:)` — that call defaults to `source: "watch"` with `exercises: []`, and `WatchWorkoutLifecycle` is consulted on the open path for all of them. Implementing it as specified left the full suite at 14 failures across five test files, none of them in the phase's Predicted Files. The guard has been reverted exactly (`git diff` on `WatchPlatformWorkout.swift` is empty); the rest of Phase 2 is landed and green (full package: 1495 tests, 0 failures). Re-plan the rule's discriminator before Phase 3.

## Governor amendment (2026-11-15): pick first, then create (supersedes D-17603, D-17604 and D-17607)

Phase 2 item 2's rule (D-17603: a wrist-created session with no exercises waits to open its workout) could not be implemented without re-basing 14 existing tests, because `createSession` defaults to `source: "watch"` with no exercises in many fixtures. The rule is dropped, and with it the empty-session design:

- **D-17608** Tapping a modality cell creates NOTHING. It presents the exercise picker in a start mode that remembers the tapped modality. Cancelling (closing the picker without choosing) leaves no session behind: nothing is stored, nothing is sent to the phone, no abandoned empty session. Choosing an exercise creates ONE session, with that modality AND that exercise as its first slot, through the existing creation path that routine starts use (`engine.createSession(modality:exercises:)`), and moves to it. The platform workout then opens by the unchanged lifecycle rule (a session with exercises opens at once) and is typed by plans 168/170: the exercise's named Health kind beats the modality default (a Cardio start with Brisk Walk saves as walking), the modality default applies when the exercise names none. The type is fixed at that moment, exactly as for a routine start.
- **D-17609** `WatchSessionStartPaths.startModalityWorkout(_:)` (the empty-session form added in Phase 2) is replaced by `startModalityWorkout(_ modality:, with exercise:)`; the picker gets a start-mode parameter (the tapped modality) whose selection calls it instead of `selectExercise`. `startFreeWorkout()` and `cancelEmptyFreeWorkout()` stay in the paths type (the Dart twin's dev start screen and existing tests still use them) but the Start view no longer calls them.
- **Scenarios changed:** S-17604 (tap opens the picker, creates no session), S-17605 (pick creates one session with modality + exercise, active, one platform workout typed by the exercise's kind or the modality default), S-17606 (cancel creates nothing: assert the store holds no new session row and no frame was emitted), S-17607/S-17608/S-17611 (the "first pick opens the workout" arms) are replaced by S-17607 (Cardio + Brisk Walk -> walking; Cardio + an exercise with no kind -> running; Resistance -> traditionalStrengthTraining; Isometric -> flexibility; Sports + unmapped -> other) and S-17608 (the picker in start mode lists the same exercises as the Free workout picker did). S-17610 (routine start unchanged) and the phone-mirror pin stay as written. The contract, constants and parity tests of Phase 1 are unchanged.
- Owner-visible behaviour: unchanged from the owner's decision (grid buttons; tap, choose an exercise, log). Marked "owner to confirm" only for the cancel behaviour (nothing created).
