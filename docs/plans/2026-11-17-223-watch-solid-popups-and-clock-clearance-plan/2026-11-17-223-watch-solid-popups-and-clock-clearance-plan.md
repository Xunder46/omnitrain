# Feature: 223 — watch pop-ups are solid, and nothing sits under the clock

> Status: SEEDED by the governor 2026-11-17 (owner asked: "plan 1–5" of the final watch integration review). Not approved for build.
> Next handoff: crew-architect (expand), then the owner
> Binding conventions: `docs/global_conventions.md`, `docs/design_system.md`, `.github/copilot/pr-scope-budget.md`
> Related plans: 171 (Discard Session), 176 (modality grid, 1.4:1 cells), 199 (one exercise list), 201 (menu row colours), 3104B (10 pt section gap)
> Track: watch client only (Swift view code in `watch/watchos/Sources/WatchSessionEngine/` and the host `ios/OmniTrain Watch App/ContentView.swift`). No wire change, no phone change, no engine/state change.
> Base commit: `964dc4c7`

## Goal and acceptance

An integration review on a 40 mm watchOS 26.4 simulator (2026-11-17) found five layout faults, each confirmed by the governor against code and screenshots:

1. **Pop-ups are see-through on watchOS 26.** Sheets wear the system glass, so what is behind bleeds in: the four modality tiles show as coloured blobs behind the exercise picker's rows, and in the "Finish Workout?" question the red Discard Session button glows behind the alert, so the non-destructive Finish looks red. No sheet sets a background (`grep presentationBackground` finds nothing). Sheets: `WatchStartView.swift:267` (exercise picker), `:277` (today's plans); `ContentView.swift:679` (`menuSheet`), `:572` (food), `:579` (diagnostics). Alerts: `WatchMenuView.swift:216` (Finish), `:242` (Discard).
2. **The Start screen scrolls under the clock.** `WatchStartView.body` (`WatchStartView.swift:164`) is a bare `ScrollView` with no `NavigationStack`, so nothing covers the clock: scrolled down, the time sits on the Sync button and the Isometric tile; scrolled back up, the grid rests higher (partly under the clock) than at launch.
3. **Exercise picker rows scroll under the ✕ and the clock, and each row is a capsule inside a rounded box.** `WatchExerciseGroupList` (`WatchExerciseListView.swift:70-125`) is a `List(.plain)` whose rows are `.bordered` / `watchProminent()` buttons, so the list's row platter and the button capsule both draw. The picker sheet has no `NavigationStack`. The same list backs the menu's Add Exercise screen (`WatchMenuView.swift:189`, `WatchAddExerciseList`).
4. **"Resistance" touches both edges of its tile at 40 mm.** `WatchModalityStartGridView` (`WatchStartView.swift:384-393`): the label `Text` has no horizontal padding, `lineLimit(1)`, `minimumScaleFactor(0.8)`.
5. **End Session and Discard Session sit 4 pt apart.** `WatchMenuView.swift:126-128` sit in `VStack(spacing: Self.surfaceInset)`, `surfaceInset = 4.0` (`:57`); `sectionGap = 10.0` (`:62`).

What the owner sees after this plan: every pop-up on the watch is solid black, so nothing behind it shows through; the Finish question no longer looks red; nothing on the Start screen, the exercise picker or Add Exercise draws under the clock or the ✕; each picker row is one shape; the four tile labels have side margins; End Session and Discard Session stand clearly apart.

Acceptance: every scenario fails on the base commit; `swift test` in `watch/watchos` whole target green with observed counts (baseline 1,580 tests, 0 failures, observed 2026-11-17); the watch app target builds for a watchOS simulator (lead, `xcodebuild`); the lead's mutation pass kills every guard; the look itself is an owner check on a 40 mm watchOS 26 simulator or device, offered, not run by default (tests cannot render these views).

## Decision Ledger

| ID | Decision | Where |
|---|---|---|
| D-22301 | Every sheet the watch shows (exercise picker, today's-plans picker, session menu including its pushed Add Exercise screen, nutrition, diagnostics) has a solid black background on watchOS 26 and 10: nothing behind it shows through. One shared modifier applies it (one place decides the colour), applied once per sheet's root content. Technical constraint: the package targets watchOS 9 (`Package.swift:26`, `.watchOS(.v9)`), the app 10.0 (`ios/Runner.xcodeproj/project.pbxproj:694`); any API newer than watchOS 9 sits behind `#available` (precedent: `WatchLoggingView.swift:205`). Architect picks the API and cites the availability. | new modifier in `WatchSessionEngine`; the five sheet sites above |
| D-22302 | The Finish and Discard questions keep their exact words and choices (`WatchMenuCopy.confirmTitle/confirmBody/confirmCancel/confirmFinish`, `discardConfirmTitle/discardConfirmBody/discardConfirmCancel/discardConfirmDiscard`), but nothing behind them shows through. Finish never looks destructive; Discard's confirm stays red/destructive. A system `.alert` cannot be given an opaque background, so the architect picks the mechanism (for example a full-screen confirmation view with the solid background of D-22301, two buttons, Cancel first-reachable). Behaviour is unchanged: Cancel runs nothing; Finish runs `haptics.playFinished()`, `state.finish()`, `onFinish()` (D-3402); Discard runs `state.discard()`, `onDiscard()` with no haptic (D-17104); an End with nothing logged raises the discard question (D-17105). VoiceOver reads the title, the body and both buttons (S-17112). | `WatchMenuView.swift` `finishRow`, `discardRow` |
| D-22303 | On the Start screen, content never draws legibly under the clock: when scrolled, it is covered or faded the system way, and scrolling back to the top returns to the same resting position as at launch. No new title text appears on the Start screen (owner to confirm). | `WatchStartView.body`, or its host branch `ContentView.swift:550` |
| D-22304 | In the exercise picker and Add Exercise, rows never draw under the ✕ or the clock, and each row is ONE shape (no capsule inside a box). Rows the session already holds keep the prominent accent look (`watchProminent()`); the others stay plain/quiet. No new picker title unless the mechanism needs one; if it does, it is raised under Open questions for the owner. Both entry points stay one list (`WatchExerciseGroupList`, D-3105/D-3112, S-3106A). | `WatchExerciseListView.swift` `list`, `rows(of:)`, `leadingButton`; picker sheet `WatchStartView.swift:267` |
| D-22305 | The four modality tile labels have visible side margins at 40 mm, stay on one line, and shrink further rather than wrap. Tile size, ratio (1.4:1, owner call 2026-11-15) and colours unchanged. | `WatchModalityStartGridView.body` (`WatchStartView.swift:384-393`) |
| D-22306 | End Session and Discard Session are separated by at least `Self.sectionGap` (10 pt), Discard stays last; the gaps around the divider (S-3104B) are unchanged. | `WatchMenuView.body` (`:126-128`) |
| D-22307 | No change to engine, state, copy, sync, phone or the logging/rest surfaces (they already sit in a `NavigationStack`, `ContentView.swift:528`, `:648`). The logging screen's own layout is out of scope. | — |
| D-22308 | The solid background is one shared modifier, `solidSheetBackground()`, in a new `WatchSheetBackground.swift`: behind `if #available(watchOS 9.4, *)` it applies `.presentationBackground(.black)` (the API is watchOS 9.4+; the package floor is 9.0, `watch/watchos/Package.swift:26` `.watchOS(.v9)`; availability precedent `WatchSessionEngine/WatchLoggingView.swift:205`), and on the floor it falls back to `.background(Color.black, ignoresSafeAreaEdges: .all)` (watchOS 8+). One place decides the colour. Applied once at the root content of each of the five sheet sites: `WatchExercisePickerView.body` and `WatchPlannedPickerView.body` (the `WatchStartView.swift:267` / `:277` sheet contents), `WatchMenuView.body`, and the food and diagnostics sheet contents (`ios/OmniTrain Watch App/ContentView.swift:572`, `:579`). The menu applies it once per exclusive body branch (menu and confirmation, D-22309). `presentationBackground` colours the sheet's backdrop, so a pushed page (Add Exercise) and the sheet's safe areas wear it too. | new `watch/watchos/Sources/WatchSessionEngine/WatchSheetBackground.swift` · `solidSheetBackground()`; the five sites |
| D-22309 | The Finish and Discard questions are no system `.alert`: while `confirmingFinish` or `confirmingDiscard` is true, `WatchMenuView.body` renders a new private `WatchMenuConfirmationView` instead of the menu's `NavigationStack` — the menu sheet's own content, so the shell's existing closes (`ContentView.swift` `.onChange(of: host.engine.session?.status)` and `.onChange(of: host.rating.isPromptOwed)`) tear it down with the sheet, and it cannot outlive it. The view is a black surface (D-22308's modifier), the title and body `Text`s read `WatchMenuCopy` unchanged, then two buttons in order: Cancel (`.buttonStyle(.bordered)`, runs nothing but the flag flip) first-reachable, then the action — Finish wears `watchProminent()` with no destructive role, Discard is `role: .destructive` with `.buttonStyle(.borderedProminent)` + `.tint(.red)`. Action order unchanged: Finish runs `haptics.playFinished()`, `await state.finish()`, `onFinish()` (D-3402); Discard runs `await state.discard()`, `onDiscard()` with no haptic (D-17104); an End with nothing logged raises the discard question (D-17105, the `finishRow` branch kept). | `WatchMenuView.swift` · `WatchMenuView.body`, `finishRow`, `discardRow`, new `WatchMenuConfirmationView` |
| D-22310 | The Start screen's bare `ScrollView` (`WatchStartView.body`) is wrapped in a `NavigationStack` with no `navigationTitle` (D-22303: no new title text). The change lands in the package view, not the host branch (`ContentView.swift:550-564`). The stack reserves the clock area at the top, so scrolled content is covered the system way and the resting top position is the launch position. | `WatchStartView.swift` · `WatchStartView.body` |
| D-22311 | The picker sheet's content (`WatchExercisePickerView.body`, presented at `WatchStartView.swift:267`) is wrapped in a `NavigationStack` with no `navigationTitle` (Open question: whether it needs a visible title). The Add Exercise screen keeps its push inside the menu's own `NavigationStack` (D-3608) — no new container there. Both still render `WatchExerciseGroupList`; the list's rows gain `.listRowBackground(Color.clear)` in `rows(of:)` and `leadingButton`, so the `List(.plain)` platter is gone and each row is its button's one shape (`listStyle(.plain)` and the button styles — `.bordered` rows, `watchProminent()` leading rows — unchanged). The dismissal contract is untouched: the sheet line keeps `onDismiss: cancelIfNothingPicked` (S-8706). | `WatchStartView.swift` · `WatchExercisePickerView.body`; `WatchExerciseListView.swift` · `list`, `rows(of:)`, `leadingButton` |
| D-22312 | The modality tile label gains side margins: a new constant `static let labelSideInset = 6.0` in `WatchModalityStartGridView`, applied as `.padding(.horizontal, Self.labelSideInset)` between the label `Text` and its `.frame(maxWidth: .infinity, …)`; `minimumScaleFactor` drops `0.8` → `0.6`, so the label shrinks further before it would wrap; `lineLimit(1)`, `cellAspectRatio = 1.4`, colours and `.buttonStyle(.plain)` unchanged. | `WatchStartView.swift` · `WatchModalityStartGridView.body`, new `labelSideInset` |
| D-22313 | End Session and Discard Session get the 10 pt gap by wrapping the two rows together in `VStack(spacing: Self.sectionGap)` inside the menu body — the same value the separators use (D-22306), and every surrounding next-line expectation still holds: the line after `finishRow` is not a `.padding(.top` (S-3104A), the line after `discardRow` is still `}` (S-17101), and the divider/Add-Exercise gaps are untouched (S-3104B). Discard stays last. | `WatchMenuView.swift` · `WatchMenuView.body` |
| D-22314 | (Lead, at P1 brief; amends D-22308/D-22309.) The menu applies `solidSheetBackground()` ONCE, on the body's `Group` that switches between the menu and the two questions, not once per branch. The questions keep the system alert's answer order the owner already knows: the action first (Finish in `watchProminent()`, never destructive; Discard `role: .destructive` with `.buttonStyle(.bordered)`, so its label is red and the file keeps its single `.tint(.red)` on the Discard row, S-20106), then Cancel (`.bordered`), whose only effect is to put the menu back. The questions are two named builders, `finishQuestion` and `discardQuestion`, over one shared layout `WatchMenuConfirmationView`. | `WatchMenuView.swift` · `body`, `finishQuestion`, `discardQuestion` |
| D-22316 | (Lead, review finding 3.) `WatchMenuConfirmationView` spaces with the menu's own tokens: `WatchMenuView.surfaceInset` and `WatchMenuView.sectionGap` become `fileprivate` so the question reads them; S-3104B's menu assertion reads the `fileprivate` line exactly. | `WatchMenuView.swift` |
| D-22315 | (Lead.) `WatchMenuConfirmationView` sits in its own titleless `NavigationStack` so the clock keeps its corner over the question, as D-22310 does for the Start screen. | `WatchMenuView.swift` · `WatchMenuConfirmationView` |

## Input-reality checklist (answered)

1. **Writers.** n/a — the change reads no stored value; it changes how existing views are presented.
2. **Lifecycle.** The menu sheet closes itself when the session ends (`ContentView.swift:599-601`) or a rating is owed (`:606-608`); a custom Finish/Discard confirmation must close with it and never outlive its sheet. A session ended from the phone while the question is up: the sheet closes, the question goes with it (scenario S-22306).
3. **Settings.** The accent (`watchAccent`, `ContentView.swift:616`) is the last modifier so sheets wear the theme; the solid background must not drop the accent from sheet content (S-22303 keeps the accent read).
4. **Time.** n/a.
5. **Cost.** n/a — no reads added.
6. **Words.** No copy changes. Docs that describe the presentation: `docs/state_management/watch_surface_wrist_logging.md:14-18`, `:33-37`; `docs/state_management/watch_surface_wrist.md:234`, `:396-406`; QA docs `docs/watch-app-qa-wrist-logging.md` (50,959 B) and `docs/watch-app-setup-and-qa.md` (54,803 B) are at/over the 80% size band: no new QA step is added to either (A-1).
7. **Competition.** Two questions cannot be up at once: End raises Finish OR Discard (`finishRow` branch on `state.hasWorkToSave`); the Discard row raises Discard only.

## Feature invariants

- No watch sheet or confirmation shows the screen behind it (D-22301, D-22302).
- Finish/Discard behaviour, words and roles are unchanged (D-22302).
- One exercise list serves both entry points (S-3106A, kept).
- The Finish/Discard question lives inside the menu sheet and never outlives it (D-22309, S-22311).

## Scenarios

Source-text guards follow the existing pattern (`menuSource`, `propertyBlock`, `sourceLines` in `WatchMenuTests.swift`; `WatchAccessibilitySourceTests`): each asserts the exact statement (including its brace), not a substring.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22301 | Source of every `.sheet(isPresented:` site in `WatchStartView.swift` (2) and `ContentView.swift` (3 incl. `menuSheet`) | each sheet's root content applies the shared solid-background modifier exactly once; the modifier's body names one colour | no sheet sets a background today |
| S-22302 | Source of `WatchMenuView.swift` | no `.alert(` remains; the Finish and Discard questions are presented with the solid background; Finish's confirm has no `.destructive` role, Discard's has it | both are system `.alert`s today |
| S-22303 | Source of the shared modifier and `ContentView.swift` | `.environment(\.watchAccent, …)` is still the root's last modifier (S-8605 kept) | pin — passes today |
| S-22304 | Behaviour/source of the Finish confirmation | Cancel runs nothing; Finish runs `haptics.playFinished()`, `await state.finish()`, `onFinish()` in that order; Discard runs `await state.discard()`, `onDiscard()` and no haptic; nothing-logged End raises Discard | pin — rewritten from S-17102 / D-3402 guards that read `.alert` today |
| S-22305 | Source of `WatchStartView.body` / its host branch | the Start screen's scroll content sits in the container the architect chose for D-22303, and no title string is added | bare `ScrollView` today |
| S-22306 | Source of the menu sheet and its confirmation | the confirmation is presented from inside the menu sheet's content, so the existing `showingMenu = false` on session end / owed rating closes both | pin of the lifecycle (Input-reality 2) |
| S-22307 | Source of `WatchExerciseGroupList` | rows draw one shape: the list rows clear the platter (or the buttons drop their own capsule — architect's choice), `leadingButton` keeps `watchProminent()` | `.bordered` buttons inside `List(.plain)` platters today |
| S-22308 | Source of the picker sheet and `WatchAddExerciseList` | both sit in a container that keeps rows clear of the ✕ and the clock (D-22304); both still render `WatchExerciseGroupList` | picker sheet has no container today |
| S-22309 | Source of `WatchModalityStartGridView.body` | the label carries horizontal padding (a named constant), `lineLimit(1)` kept, `minimumScaleFactor` lower than 0.8, `cellAspectRatio = 1.4` and colours unchanged | no padding, 0.8 today |
| S-22310 | Source of `WatchMenuView.body` | between `finishRow` and `discardRow` there is `.padding(.top, Self.sectionGap)` (or equal), Discard last; S-3104B gaps unchanged | 4 pt today |
| S-22311 | Source of `WatchMenuView.body` and `ios/OmniTrain Watch App/ContentView.swift` | the confirmation is a body branch of the menu sheet's own content, and the shell's two `onChange` closes are unchanged — no code path presents a question outside the sheet | pin of Input-reality 2 — passes today with `.alert`; the rewrite must not move the question outside the sheet |
| S-22312 | Source of `finishRow`, `discardRow` and `WatchMenuConfirmationView` | no branch sets both `confirmingFinish` and `confirmingDiscard`, and the confirmation view names exactly one question (its title/body come from one call site) — two questions can never be up at once (Input-reality 7) | pin — passes today; guards the rewrite |
| S-22313 | Source of the planned picker sheet after D-22308 | `WatchPlannedPickerView` keeps `navigationTitle(WatchStartSurfaceCopy.plannedPickerTitle)` and its name-only rows; the solid background adds nothing else to its content | pin — guarded by existing `WatchPlannedSurfaceSourceTests.testS8965ThePlannedPickerShowsOnlyNames` |

## Phases

| Phase | Owner | Items (outline) | Write scope | Order |
|---|---|---|---|---|
| P1 | crew-builder-watch | D-22301, D-22302: shared solid-background modifier; apply to the five sheets; Finish/Discard confirmations without `.alert`; rewrite the tests that pin `.alert` (S-17102 family in `WatchMenuTests.swift`, `WatchAccessibilitySourceTests.testS17112…`, the `confirmingFinish/confirmingDiscard` index checks near `WatchMenuTests.swift:1958`, `:2091`); S-22301..S-22304, S-22306 | `watch/watchos/Sources/WatchSessionEngine/**`, `watch/watchos/Tests/**`, `ios/OmniTrain Watch App/ContentView.swift` | first |
| P2 | crew-builder-watch | D-22303..D-22306: Start screen container, picker/Add Exercise container and one-shape rows, tile label margins, menu gap; S-22305, S-22307..S-22310 | same | after P1 (same files) |
| P3 | crew-docs-keeper | Docs delta rows | `docs/**` | after P2 |

Lead after each phase: `swift test` whole target, `xcodebuild` watch target (watchOS 9 package / 10 app availability), mutation pass on the new guards. Owner: look at 40 mm watchOS 26 (and watchOS 10 if available) — offered in the closing report.

## Phase detail

Ordering: **P1 then P2 serially** (both write `WatchStartView.swift` and `WatchMenuView.swift`, same package, one `swift test` at a time — cannot run in parallel). **P3 after P2** (its rows are backed by the S-223xx guards built in P1/P2). No parallel phases.

Every source-text guard follows the existing pattern (`menuSource`, `propertyBlock`, `sourceLines`, `strippingCommentLines` in `WatchMenuTests.swift`, `WatchAccessibilitySourceTests.swift`, `WatchPlannedSurfaceSourceTests.swift`) and asserts the exact statement including its brace, never a substring. Count-based guards count occurrences per sheet body branch (the menu has two exclusive branches, D-22309). The prover proves the new P1/P2 guards red at the base commit `964dc4c7` (prove-red) and kills each by mutating the exact line the guard asserts.

### P1 — crew-builder-watch (D-22301, D-22302)

Write the report FIRST as a skeleton, then fill it item by item.

1. [ ] Add the shared solid-background modifier (`presentationBackground(.black)` behind `if #available(watchOS 9.4, *)`, `.background(Color.black, ignoresSafeAreaEdges: .all)` on the floor) — `watch/watchos/Sources/WatchSessionEngine/WatchSheetBackground.swift` (new) · `solidSheetBackground()`
2. [ ] Apply the modifier to both Start-view sheets — `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` · `WatchExercisePickerView.body`, `WatchPlannedPickerView.body`
3. [ ] Apply the modifier to the menu sheet, once per body branch — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `WatchMenuView.body`
4. [ ] Apply the modifier to the food and diagnostics sheet contents — `ios/OmniTrain Watch App/ContentView.swift` · the two `.sheet(isPresented:)` contents
5. [ ] Replace the two `.alert`s with the in-place confirmation (body branches on the two flags; Cancel no-op; Finish/Discard action order unchanged) — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `WatchMenuView.body`, `finishRow`, `discardRow`, new `WatchMenuConfirmationView`
6. [ ] Rewrite the two guards that read the alert buttons — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · `testS17102TheViewDiscardsOnlyFromTheQuestionsDiscardButton`; `watch/watchos/Tests/WatchSessionEngineTests/WatchAccessibilitySourceTests.swift` · `testS17112TheDiscardRowAndItsConfirmationSpeak`
7. [ ] Move the destructive-role assertion to the confirmation view — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · `testS17101TheDiscardRowIsTheMenusLastRow`
8. [ ] Add the P1 source guards S-22301, S-22302, S-22304, S-22306 (new file) and the S-22303 pin — `watch/watchos/Tests/WatchSessionEngineTests/WatchSheetSoliditySourceTests.swift` (new), `WatchMenuTests.swift` · new tests

- Done Criteria: `gateway.sh swift-test --filter WatchSessionEngineTests` green with observed counts (baseline 1,580 tests, 0 failures, observed 2026-11-17); S-22301, S-22302 and S-22304 proven red at the base commit and green after item 5; `testS17101`, `testS20106`, `testS20111`, `testS17109`, `testS3104A`, `testS3104B`, `testS3106A`, `testS8605`, `testS8706`, `testS8965ThePlanPickerSheetAndItsStateExist` all green untouched.
- Predicted Files: `WatchSheetBackground.swift` (new), `WatchStartView.swift`, `WatchMenuView.swift`, `ios/OmniTrain Watch App/ContentView.swift`, `WatchMenuTests.swift`, `WatchAccessibilitySourceTests.swift`, `WatchSheetSoliditySourceTests.swift` (new), `WatchTimerCueTests.swift` (added after the run, review finding 1).
- Write scope: `"watch/watchos/Sources/WatchSessionEngine/**" "watch/watchos/Tests/**" "ios/OmniTrain Watch App/ContentView.swift"`

### P2 — crew-builder-watch (D-22303, D-22304, D-22305, D-22306)

Write the report FIRST as a skeleton, then fill it item by item. Runs after P1: same package, overlapping files (`WatchStartView.swift`, `WatchMenuView.swift`).

1. [ ] Wrap the Start screen's scroll in a `NavigationStack` with no `navigationTitle` — `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` · `WatchStartView.body`
2. [ ] Wrap the exercise picker sheet's content in a `NavigationStack` with no `navigationTitle` — `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` · `WatchExercisePickerView.body`
3. [ ] Clear the list row platters (`.listRowBackground(Color.clear)` on the row buttons; styles and `listStyle(.plain)` unchanged) — `watch/watchos/Sources/WatchSessionEngine/WatchExerciseListView.swift` · `list`, `rows(of:)`, `leadingButton`
4. [ ] Add the label side margin (`labelSideInset = 6.0`) and lower the scale floor (`minimumScaleFactor(0.6)`) — `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` · `WatchModalityStartGridView.body`
5. [ ] Wrap `finishRow` and `discardRow` together in `VStack(spacing: Self.sectionGap)` — `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `WatchMenuView.body`
6. [ ] Add the S-22305 and S-22309 guards next to the grid's tests — `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSurfaceSourceTests.swift` · new tests
7. [ ] Add the S-22307 and S-22308 guards next to the one-list test — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · new tests
8. [ ] Add the S-22310 guard — `watch/watchos/Tests/WatchSessionEngineTests/WatchMenuTests.swift` · new test

- Done Criteria: `gateway.sh swift-test --filter WatchSessionEngineTests` green with observed counts; S-22305, S-22307, S-22308, S-22309, S-22310 proven red at the P1 commit and green after items 1–5; `testS17603EachCellWearsItsAccentAtTheFixedHeight`, `testS7205`, S-17601, `testS3104A`, `testS3104B`, `testS17101`, `testS20106` all green untouched.
- Predicted Files: `WatchStartView.swift`, `WatchExerciseListView.swift`, `WatchMenuView.swift`, `WatchPlannedSurfaceSourceTests.swift`, `WatchMenuTests.swift`.
- Write scope: `"watch/watchos/Sources/WatchSessionEngine/**" "watch/watchos/Tests/**"`

### P3 — crew-docs-keeper (the Docs delta table's rows, in order)

1. [ ] Apply the seeded row: the logging page's "Finish Workout?" sentence — `docs/state_management/watch_surface_wrist_logging.md` · the sentence at `:14`
2. [ ] Apply the seeded row: the logging page's "Discard session?" sentence — `docs/state_management/watch_surface_wrist_logging.md` · the sentence at `:35`
3. [ ] Apply the seeded row: the wrist page's 44 pt grid sentence — `docs/state_management/watch_surface_wrist.md` · the sentence at `:234`
4. [ ] Apply the seeded ADDED row: `every sheet on the wrist is solid black` — `docs/state_management/watch_surface_wrist.md` · the sheet/one-list section
5. [ ] Apply the seeded ADDED row: `each row is one shape` — `docs/state_management/watch_surface_wrist.md` · the one-list section
6. [ ] Apply the QA row: step 7's prompt sentence — `docs/watch-app-qa-wrist-logging.md` · step 7 (`:65`)
7. [ ] Apply the QA row: step 44's prompt sentence — `docs/watch-app-qa-wrist-logging.md` · step 44 (`:513`)
8. [ ] Apply the QA row: step 45's grid sentence — `docs/watch-app-qa-wrist-logging.md` · step 45 (`:541`)

- Done Criteria: no `swift test` (documentation only); the three touched files stay below the 52,428 B band after the edits (the QA doc is at 50,959 B — the added words are a few dozen bytes; the keeper measures before and after); every behaviour sentence in the changed lines still names an existing test (the seeded rows' backed-by columns and the existing test names in those sentences are kept).
- Predicted Files: `docs/state_management/watch_surface_wrist_logging.md`, `docs/state_management/watch_surface_wrist.md`, `docs/watch-app-qa-wrist-logging.md`.
- Write scope: `"docs/state_management/watch_surface_wrist_logging.md" "docs/state_management/watch_surface_wrist.md" "docs/watch-app-qa-wrist-logging.md"`

## Existing-functionality impact

| Touched surface | What already reads it (the search, run 2026-11-17) | Effect | Guarded by |
|---|---|---|---|
| `WatchMenuView` `finishRow` / `discardRow` `.alert`s | grep `.alert(`, `confirmingFinish`, `confirmingDiscard`, `finishRow`, `discardRow` over `watch/watchos`: source hits only `WatchMenuView.swift:67/72/126/128/207/210/212/216/236/238/242`; tests `WatchMenuTests.swift` ~1636, ~1679, ~1944, ~2040, ~2077 and `WatchAccessibilitySourceTests.swift` ~243 | the alert bodies move into `WatchMenuConfirmationView`; `finishRow`'s rule branch and the two flag writes keep their index order; three guards are rewritten/edited, the rest stay green | S-22302, S-22304, S-22311, S-22312 |
| The five sheet sites | grep `.sheet(isPresented:` over `watch/watchos`: `WatchStartView.swift:267/:277`, `ContentView.swift` food/diagnostics; tests `WatchAccentTests.swift:260`, `WatchCancelEmptyFreeWorkoutTests.swift:191`, `WatchPlannedSurfaceSourceTests.swift:170` | one `solidSheetBackground()` call inside each sheet's root content; the sheet-site lines and the accent's last-modifier position unchanged | S-22301, S-22303, S-22313 |
| `WatchExerciseGroupList` | grep `WatchExerciseGroupList` over `watch/watchos`: `WatchExerciseListView.swift:25`, `WatchStartView.swift:472`, `WatchMenuView.swift:274`; tests `WatchMenuTests.swift:973/:984` | `.listRowBackground(Color.clear)` per row; the shared component, its empty branch and both entry points unchanged | S-22307, S-22308 |
| `WatchStartView.body` (bare `ScrollView`) | grep `WatchModalityStartGridView`: `WatchStartView.swift:168/:352`; tests `WatchNutritionWiringSourceTests.swift:221`, `WatchPlannedSurfaceSourceTests.swift:218` | wrapped in `NavigationStack`; the scroll content, gaps, order and the `.sheet`/`.onChange` modifiers untouched | S-22305 |
| `WatchModalityStartGridView.body` label | `WatchPlannedSurfaceSourceTests.testS17603EachCellWearsItsAccentAtTheFixedHeight` (~245) asserts `.lineLimit(1)`, one `RoundedRectangle`, `.buttonStyle(.plain)`, `cellAspectRatio = 1.4` — and no scale-factor assertion | padding constant + scale floor 0.6; nothing the test asserts changes | S-22309 |
| `WatchMenuView.body` row stack | `testS3104A` (~999), `testS3104B` (~1026), `testS17101` (~1679) next-line expectations (grep `finishRow`, `discardRow`) | the two rows wrapped in `VStack(spacing: Self.sectionGap)`; every next-line expectation still holds | S-22310, D-22313 |

Unaffected, with the search that proves it: grep `minimumScaleFactor(0.8)` over `watch/watchos` hits `WatchRestView.swift:79/95/105` and `WatchLoggingView.swift:316` — the logging/rest surfaces, out of scope (D-22307), untouched. Grep `confirmingFinish|confirmingDiscard|.alert(` over `watch/watchos/Sources` hits only `WatchMenuView.swift` — no engine, state or copy file is touched. Grep `listStyle(.plain)` hits only `WatchExerciseListView.swift:98` — the style itself is kept. `WatchExercisePageFitTests.swift` pins the logging surface (`menuClearance`, notice rows) — untouched, not in any phase's edit list.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/watch_surface_wrist_logging.md` | MODIFIED | `which asks "Finish Workout?" first` | `asks "Finish Workout?" first on a solid screen` | D-22302, S-22302 |
| `docs/state_management/watch_surface_wrist_logging.md` | MODIFIED | `asks "Discard session?"` | `asks, on a solid screen, "Discard session?"` | D-22302, S-22302 |
| `docs/state_management/watch_surface_wrist.md` | MODIFIED | `each a fixed 44 pt high` | `each 1.4 times as wide as it is tall, its label inset from both edges` | D-22305, S-22309 |
| `docs/state_management/watch_surface_wrist.md` | ADDED | - | `every sheet on the wrist is solid black` | D-22301, S-22301 |
| `docs/state_management/watch_surface_wrist.md` | ADDED | - | `each row is one shape` | D-22304, S-22307 |
| `docs/watch-app-qa-wrist-logging.md` | MODIFIED | `prompt reads **Finish Workout?** with the phone's own words` | `a solid screen reads **Finish Workout?** with the phone's own words` | D-22302, S-22302 |
| `docs/watch-app-qa-wrist-logging.md` | MODIFIED | `"Discard session?" with **Cancel** and a red **Discard**` | `"Discard session?" with a red **Discard** and **Cancel**` | D-22302, S-22302 |
| `docs/watch-app-qa-wrist-logging.md` | MODIFIED | `colours, 44 pt tall, and all four fit a 40 mm watch` | `colours, each 1.4 times as wide as it is tall, its label inset from both edges, and all four fit a 40 mm watch` | D-22305, S-22309 |

(Seed: complete from a stale-term sweep — `grep -rIn "44 pt\|alert\|Finish Workout?\|Discard session?\|sheet\|capsule" docs | grep -v "docs/plans\|docs/history\|docs/releases"` limited to watch pages — copying every Old marker from the doc as it is today.)
(Architect 2026-11-17, sweep done: the three `watch-app-qa-wrist-logging.md` rows are the architect's additions; every Old marker was copied from the doc on disk this run. Lead merged the two tables into one so the lint reads every row.)

Sweep result (no row needed): `docs/watch-app-setup-and-qa.md`'s `sheet` hits are the Health permission sheet and its `alert` hit is a haptic-pattern sentence (line 746) — not this change; `docs/state_management/watch_surface_wrist_logging.md`'s `capsule` hits (:135, :157) are the logging step buttons, out of scope (D-22307); `docs/state_management/watch_diagnostics.md:62` "`WatchDiagnosticsView` in a sheet" stays true; `docs/state_management/watch_surface_wrist.md:123` and `:298` describe which sheet runs what, not how it looks — still true. No phone page matched the change's terms.

## Progress

| Phase | State |
|---|---|
| Seed | done (governor, 2026-11-17) |
| Architect | done (crew-architect, 2026-11-17); lead merged the split Docs delta table; plan-lint clean |
| Scope guard | within budget at handoff (227 lines, 3 phases, 13 D, 13 S, watch track only) — 2026-11-17 |
| P1 | done — crew-builder-watch; lead verified 1586/0, watch build OK |
| P2 | done — crew-builder-watch; lead verified 1591/0, watch build OK; mutation pass 24/24 killed |
| P3 | done — crew-docs-keeper; lead joined 4 split markers; plan-lint after clean |
| Review | APPROVE WITH FIXES (0 blocker, 1 major, 3 minor); all four fixed by the lead |

## Assumption Log

- A-1: The two watch QA docs are at or over the 80% size band (50,959 B and 54,803 B of the 52,428 B band), so this plan adds no QA step; the owner's look is recorded here as `(owner)` checks instead.
- A-3: (Lead, at the docs brief.) Three Docs delta New markers were reworded so none contains its own Old marker (plan-lint `after` checks the Old marker is gone): the Discard sentence, and QA steps 7 and 44. QA step 44 now names the answers in the question's order (Discard, then Cancel, D-22314).
- A-4: Owner decision 2026-11-17 on review finding 6 (out of scope here): a lift picked under Cardio keeps the stopwatch; logging follows the modality as plan 206 decided. No change.
- A-2: Scenario ids use the five-digit form `S-223xx`; the literal `S-223` already names a rest-ping contract case (`watch/contract/watch_rest_ping_contract.json:145`, `WatchRestPingTests.swift:252`) and is a different id.

## Owner checks

- (owner) On a 40 mm watch on watchOS 26: open the exercise picker from a tile, open the session menu, tap End Session — nothing behind shows through, and Finish does not look red.
- (owner) Scroll the Start screen and the picker: nothing sits under the clock or the ✕; the grid returns to its launch position.
- (owner) "Resistance" has a margin on both sides; End Session and Discard Session stand clearly apart.

## Existing tests that pin what changes

Every hit from the grep obligations (`.alert(`, `confirmingFinish`, `confirmingDiscard`, `.sheet(isPresented:`, `listStyle(.plain)`, `minimumScaleFactor(0.8)`, `WatchExerciseGroupList`, `WatchModalityStartGridView`, `finishRow`, `discardRow` over `watch/watchos`), with what happens to it:

| Test (file, ~line) | Pins | Expected edit |
|---|---|---|
| `WatchMenuTests.testS17102TheViewDiscardsOnlyFromTheQuestionsDiscardButton` (~1636) | the destructive Discard, Cancel no-op, `Text(WatchMenuCopy.discardConfirmBody)`, `onDiscard()`, no `haptics` — all inside `discardRow`, which holds the `.alert` today | REWRITE (P1 item 6): the button/text assertions move to `WatchMenuConfirmationView`'s body; `occurrences(of: "state.discard()") == 1` still holds (one call site, moved with the button) |
| `WatchAccessibilitySourceTests.testS17112TheDiscardRowAndItsConfirmationSpeak` (~243) | the row reads as its own label; the confirmation's Cancel and destructive Discard are read from their words and roles | REWRITE (P1 item 6): the row-label assertion stays on `discardRow`; the Cancel/destructive/body assertions move to the confirmation view; the no-invented-`.accessibilityLabel` check stays |
| `WatchMenuTests.testS17101TheDiscardRowIsTheMenusLastRow` (~1679) | `role: .destructive` inside `discardRow`'s body; the line after `discardRow` is `}` | EDIT (P1 item 7): the destructive-role assertion moves to the confirmation view; the last-row and `}` expectations stay green with the D-22313 `VStack` wrap |
| `WatchMenuTests.testS17109TheEmptyEndRaisesTheDiscardAlert` (~1944) | index order `state.hasWorkToSave` → `confirmingFinish = true` → `confirmingDiscard = true` in `finishRow` | stays green, no edit (the branch is kept, D-22309) |
| `WatchMenuTests.testS20106TheMenuRowsWearTheirColours` (~2040) | `.watchProminent()` on `finishRow`; `.buttonStyle(.borderedProminent)` + `.tint(.red)` on `discardRow`; one `.tint(.red)` in the file | stays green, no edit (styles unchanged, D-22309) |
| `WatchMenuTests.testS20111TheEndRowRaisesTheFinishQuestionWhenThereIsWorkToSave` (~2077) | the same index order plus "no `hasLoggedEfforts`" | stays green, no edit |
| `WatchMenuTests.testS3104ATheMenuGapSitsAboveAddExercise` (~999) | the line after `finishRow` is not `.padding(.top` | stays green with the `VStack` wrap (the next line is blank), no edit |
| `WatchMenuTests.testS3104BTheSameGapSitsAroundEverySeparator` (~1026) | `sectionGap = 10.0` in both files; divider/Add-Exercise/Sync next-lines | stays green, no edit |
| `WatchMenuTests.testS3106AOneListServesBothEntryPoints` (~967) | `WatchExerciseGroupList` in all three files, no `LazyVStack` | stays green, no edit |
| `WatchMenuTests.testS3617TheMenuAddsFromItsOwnListNotTheStartPicker` (~950) | `WatchMenuView.swift` names neither `WatchExercisePickerView` nor `pickerRows` | stays green, no edit |
| `WatchAccentTests.testS8605TheAccentWrapsTheRootSheetsAndTheRootSetsNoTint` (~260) | the accent `.environment` is after `.menuSheet(` and the last `.sheet(isPresented:`; no root `.tint(` | stays green, no edit (`solidSheetBackground()` uses no `.tint(`; it is added inside the sheet contents, before the accent) |
| `WatchCancelEmptyFreeWorkoutTests.testS8706ThePickerSheetCancelsOnDismissAndTheHostReReads` (~191) | the exact sheet line `.sheet(isPresented: $pickingExercise, onDismiss: cancelIfNothingPicked)` | stays green, no edit (the modifier is added inside the sheet content) |
| `WatchPlannedSurfaceSourceTests.testS8965ThePlanPickerSheetAndItsStateExist` (~170) | exactly one `.sheet(isPresented: $pickingPlan)` | stays green, no edit |
| `WatchPlannedSurfaceSourceTests.testS17603EachCellWearsItsAccentAtTheFixedHeight` (~245) | grid contents incl. `.lineLimit(1)`, one `RoundedRectangle`, `.buttonStyle(.plain)`, `cellAspectRatio = 1.4` | stays green, no edit (no scale-factor assertion) |
| `WatchNutritionWiringSourceTests.testS7205NutritionSitsRightUnderTheStartControls` (~221) | order grid → Nutrition → divider → Sync via `sourceLines` indexes | stays green, no edit |
| `WatchTimerCueTests.testS15107TheMenuFinishesWithTheTapAndNeverOnCancel` (~189) | the alert's empty Cancel line `Button(WatchMenuCopy.confirmCancel, role: .cancel) {}` | EDITED in P1 (found by the whole-target run; review finding 1): now reads the question's Cancel line; the no-haptic pin is unchanged |
| `WatchExercisePageFitTests` (whole file) | the logging surface's `menuClearance`, notice rows, summary line | untouched — logging is out of scope (D-22307); not in any phase's edit list |

## Open questions

1. **Does the exercise picker sheet need a visible title?** D-22311 wraps `WatchExercisePickerView.body` in a `NavigationStack` with no `navigationTitle`, assuming a stack reserves the clock area without one (not verifiable without a watchOS simulator; no picker-title copy exists today — only `WatchMenuCopy.addExerciseTitle` serves the Add list, `WatchMenuView.swift:287`). If the owner's look shows content still reaching the clock, the owner must choose the word (D-22304 leaves the title to them).
2. **Same for the Start screen** (D-22310): `WatchStartView.body` wrapped in a `NavigationStack` with no title; D-22303 says no new title text appears. If the system needs a title to reserve the clock area, that is an owner decision, not the architect's.
3. **`minimumScaleFactor` floor 0.6** (D-22312): chosen as "lower than 0.8"; the owner's look on a 40 mm device decides whether "Resistance" still reads well at that scale. No test can render it.
4. **No transition on the confirmation swap** (D-22309): the body branches switch without an animation modifier; the owner may want the standard watchOS presentation feel. Words, roles, order and behaviour are pinned regardless (S-22302, S-22304).
5. **The system ✕ on the picker sheet**: assumed to remain the sheet's own close and to overlap nothing once the `NavigationStack` reserves the top area; the owner's look decides (D-22304).
6. **`watch_surface_wrist.md` size**: A-1 records the two QA docs' sizes; the wrist page's size was not measured this run (shell restricted to the gateway script). The P3 keeper measures before and after the two ADDED rows (P3 Done Criteria).
7. The seeded S-22301 wording counts the modifier "exactly once" per sheet; the menu sheet applies it once per exclusive body branch (menu, confirmation — D-22309). The P1 guard counts per branch; the seeded entry is kept as written.
