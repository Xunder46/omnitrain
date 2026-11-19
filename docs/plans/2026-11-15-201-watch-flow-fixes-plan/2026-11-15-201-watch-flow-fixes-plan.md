# Feature: 201 — watch flow fixes: the list restarts after the last set, red Discard, End logs a running effort, a modality pick over a started workout

> Status: SEEDED by the governor 2026-11-15; the architect expands it. Defaults marked **owner to confirm**.
> Next handoff: crew-architect
> Binding conventions: `docs/global_conventions.md`, `docs/design_system.md` (wrist rules), `docs/state_management/watch_surface_wrist_logging.md`, `.github/copilot/pr-scope-budget.md`
> Related plans: 149 (rest labels), 171 (Discard Session, D-17101..D-17111), 176 (modality grid), 79 (rest Next opens the announced exercise)
> Track: watch client only (`watch/watchos/`, `ios/OmniTrain Watch App/`). No wire change, no phone change.

## Goal and acceptance

Four owner-visible fixes, from the owner's wrist session of 2026-11-15 and an independent review of the same day:

1. **After the last exercise's last set is logged, the list starts over.** Today the rest screen's Next, with every planned set of
   every exercise done, says "Nothing planned next" and goes nowhere. Owner: "restart the list, go back to the first one, then
   allow logging to switch again". After this change Next goes on to the following exercise in turn (the last one is followed
   by the first), whether or not that exercise is already done; the user can keep logging extra sets there and Next keeps
   cycling.
2. **Colours on the session menu.** Owner: "Discard button should be red and end session should be theme primary color".
   End Session is a filled button in the watch's theme colour; Discard Session is a filled red button.
3. **End Session while an effort clock is running and nothing is logged** (a 30-minute walk where Log was never pressed). Today
   it asks "Discard session?" and the only way to keep the walk is to know to press Log first. Owner choice: **End Session logs
   the running effort first, then finishes.** (Chosen 2026-11-15.)
4. **A modality button pressed over an already-started workout.** Start a workout on the phone, tap Cardio on the watch and pick an
   exercise: today the pick is silently dropped and the Start screen stays. After this change the exercise is added to the
   running workout and the logging screen opens on it, like the old Free workout did.

Acceptance: the four behaviours above, each held by a test that fails on the old code; `swift test` in `watch/watchos` green
with observed counts; the watch target compiles (`xcodebuild`, lead); the invariant greps and the docs contracts green.

## Decision Ledger

| ID | Decision | Where |
|---|---|---|
| D-20101 | **The "next" search cycles instead of ending.** In `deriveRestLabels`, when the stay-branches do not apply and the forward-then-wrap search finds no undone slot AND the ladder holds more than one slot, the target is the slot after the current one in a circle: `slots[(here + 1) % slots.count]`; `next` is `"\(movePrefix)\(slot.name)"` (name only; no "Set k of n", because every slot is done and an extra set reads as its own last number on the logger) and `nextSlotId` is its id. A one-slot ladder keeps "Nothing planned next" and a nil `nextSlotId` (Next ends the rest and the same exercise logs another set). No other branch changes: an undone slot still wins over the circle, a planned slot with sets left still stays (D-14903/D-14904). | `WatchRestLabels.swift` (`deriveRestLabels`, the loop at the end) |
| D-20102 | **The pager does not wrap** (`WatchPagerModel.neighbourIndex`) and is not touched: the owner's complaint is the rest screen's Next. | — |
| D-20103 | **Colours.** `finishRow` uses `.watchProminent()` (the accent fill, `WatchAccentStyle.swift`); `discardRow` uses `.buttonStyle(.borderedProminent)` and `.tint(.red)`. The alert buttons and their `role: .destructive` are unchanged. No other row's style changes. | `WatchMenuView.swift` (`finishRow`, `discardRow`) |
| D-20104 | **End logs a running effort.** `WatchMenuState` gains an optional `logging: WatchLoggingState?` (init parameter with default `nil`; `ContentView.menuState` passes `host.logging`). New `hasRunningEffort`: `logging?.workTimer != nil` (that property already requires `canLog` and hides another slot's message-started clock). New `hasWorkToSave`: `hasLoggedEfforts \|\| hasRunningEffort`. `finishRow` branches on `hasWorkToSave` (finish confirmation) instead of `hasLoggedEfforts`. `finish()`: when `hasRunningEffort`, first `try? await logging.log()` (stores the entry, stops the clock, starts the follow-on rest, which the terminal write stops), then if `hasLoggedEfforts` is still false (the log was refused) `discard()`, otherwise `await rating.end()`. `hasLoggedEfforts` keeps its meaning. A set-kind exercise has no clock, so its behaviour is unchanged. | `WatchMenu.swift`, `WatchMenuView.swift`, `ios/OmniTrain Watch App/ContentView.swift:623` |
| D-20105 | **A modality pick over a held, active session adds the exercise.** In `startModalityWorkout(_:with:)`: after `pendingModalityStart = nil`, when `engine.session?.status == WatchSessionStatus.active`, return `await addExerciseToSession(exercise)` (the same call Add Exercise makes: `insertExercise(..., moveTo: true)`). The held session's modality is NOT changed (D-12591/D-12592: the phone's value is stamped on first hearing only; no mid-workout location prompt). With no held session, or an ended one, today's `createSession` path runs unchanged. | `WatchStartPaths.swift:789` |
| D-20106 | **Words.** No new strings: the cycle line reuses `WatchRestLabelCopy.nextExercisePrefix` ("Next exercise: "); the finish confirmation is the existing "Finish Workout?". | — |

## Input-reality checklist (answered)

1. **Writers.** n/a for storage: nothing new is stored. D-20104's logged entry is written by the existing `WatchLoggingState.log(now:)` (the clock's window, the user's own kind), the same entry Log makes.
2. **Lifecycle.** Rolling/imported/edited sessions are phone concepts. On the wrist: a held session with exercises and a running clock (D-20104); a held empty session (D-20105); a one-slot ladder (D-20101); an ended session (D-20105 falls through to the old path).
3. **Settings.** Accent colour changes while the menu is open: `.watchProminent()` reads the worn accent at render (`WatchAccentStyle.swift`), as the current-exercise row already does. Rest-ping seconds: not read here.
4. **Time.** D-20104 logs at the wrist's clock at the instant End is confirmed (`log(now:)` default clock). No date logic.
5. **Cost.** `deriveRestLabels` runs on every read of `restLabels` (O(slots)); the circle adds one index computation. `finish()` adds one `log()`.
6. **Words.** Grep of the old wording is in the Docs delta. The `"Nothing planned next"` copy stays (one-slot ladder, no-exercise); the wrist QA doc gets two steps.
7. **Competition.** The circle vs the undone search: an undone slot always wins (S-20104). End-with-running-effort vs the menu lock: `isLocked` disables jump rows, never End/Discard (D-17103 stays).

## Feature invariants

- An undone exercise is always announced before the circle is used (D-20101, S-20104).
- A one-exercise ladder never announces a move (D-20101, S-20103).
- `hasLoggedEfforts` keeps its D-17105 meaning (saved efforts only); the new property is separate (D-20104).
- A discard still owes no rating and never logs (S-17102..S-17111 stay green).
- New Swift function names avoid the append-only guard's verbs (update, delete, remove, replace, edit, overwrite, write, clear, purge, wipe, reset, drop, truncate, erase, forget, modify, mutate, destroy, set); SwiftUI targets watchOS 9 only (crew rules (r), (ac), (an)).

## Existing-functionality impact

| Touched surface | What reads it (search to be re-run by the architect) | Effect | Guarded by |
|---|---|---|---|
| `deriveRestLabels` nothing-left branch | `WatchRestLabelsTests` S-9104 (`:795-808`, three slots all done → today nil target), S-14945 (`:715-739`, one slot → stays), `WatchRestNextHoldTests.swift:208` (four holds all logged once → today nil), `WatchLoggingState.restLabels` (`:629`), `WatchRestView` Next, `ContentView` `advance:` | S-9104 and the NextHold ending are rewritten to the cycle; S-14945's one-slot case is unchanged | S-20101..S-20105 |
| `finishRow` / `discardRow` source scans | `WatchMenuTests` ~1606-1643 (S-17101 order, destructive/cancel), ~1831-1906 (S-17109 branch scan on `state.hasLoggedEfforts`), `WatchAccessibilitySourceTests` ~251-263 (discardRow lines) | Scans updated to the new exact statements | S-20106, S-20111 |
| `WatchMenuState.init` | `ContentView.swift:623` only (`grep -rn "WatchMenuState(" watch ios` run 2026-11-15) plus `WatchMenuTests` harness builds | New parameter has a default, so existing constructions compile; the harness passes the logging state for the new tests | S-20107..S-20109 |
| `startModalityWorkout` | `WatchStartView.swift:490` (the picker's `select`), `WatchModalityStartTests` S-17605 (`:226-235`, a held session answers) | The S-17605 held-session test is revisited: a held ACTIVE session now receives the exercise instead of ignoring it | S-20112, S-20113 |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-20101 | `deriveRestLabels` over three set slots A (planned 2), B (planned 3), C (planned 1), every slot's planned sets logged, current index 2 (C, the last) | `nextSlotId == "A"`, `next == "Next exercise: A"` | today returns "Nothing planned next" and nil |
| S-20102 | Same ladder, current index 0 | `nextSlotId == "B"` (the circle goes to the following slot, not to the first) | today nil |
| S-20103 | One slot, planned 3, three logged | `nextSlotId` nil, `next == "Nothing planned next"` (pin; S-14945) | passes today — the guard the change must not break |
| S-20104 | A done, B NOT done, C done, current C | `nextSlotId == "B"` (the undone slot wins over the circle) | passes today — pins the priority |
| S-20105 | Engine ladder of four exercises each holding its one planned hold (`holdLadder()` in `WatchRestNextHoldTests`), current D, everything logged once; `leaveRest(advance: jump)` | the session moves to A; a hold logged there makes A hold two entries and B, C, D one each; Next from A then announces B | today the session stays on D |
| S-20106 | Source guard on `WatchMenuView.swift` | `finishRow` contains the exact statement `.watchProminent()` after its `Button(Self.finishLabel) {` block closes; `discardRow` contains the exact statements `.buttonStyle(.borderedProminent)` and `.tint(.red)`; no other `.tint(.red)` in the file | both rows are `.bordered` |
| S-20107 | Harness: a timed exercise (timed effort kind, no plan), the work clock started, nothing logged; `menu.hasRunningEffort == true`, `menu.hasLoggedEfforts == false`; `menu.finish()` | exactly one `timed` entry stored with the clock's window, session status `completed`, NOT `abandoned`; the rating state's end ran | today `finish()` discards the session |
| S-20108 | A set-kind exercise, nothing logged | `hasRunningEffort == false`; `finish()` discards (S-17109 pin) | passes today — pin |
| S-20109 | The only running clock is a phone message's clock for ANOTHER slot (hidden by `workTimer`) | `hasRunningEffort == false`; `finish()` discards | passes today — pin |
| S-20110 | A timed slot whose clock was never started (`isAwaitingStart`) | `hasRunningEffort == false`; `finish()` discards | passes today — pin |
| S-20111 | Source guard on `WatchMenuView.finishRow`: the exact line `if state.hasWorkToSave {` and `confirmingFinish = true`, and the exact line `confirmingDiscard = true` in its else branch | as stated | it reads `hasLoggedEfforts` |
| S-20112 | Paths harness: a held ACTIVE session with no exercises (started as the phone starts one); `beginModalityStart("cardio_endurance")`; `startModalityWorkout("cardio_endurance", with: Running)` | the returned row has the held `sessionId`, exactly one exercise (Running), `currentExerciseIndex 0`, `pendingModalityStart == nil`; the engine still holds one session | today the held row comes back with no exercise |
| S-20113 | The held session already ended (`completed`); same call | a NEW session is created with the modality and the exercise (the S-17605 path) | passes today — pin |
| S-20114 | S-20112's session has modality nil | the modality stays nil after the pick | n/a today — pins D-12591 |

## Phases (outline for the architect to expand; at most 8 items each)

**P1 — rest cycle and modality pick (owner: crew-builder-watch; write scope `watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift`, `WatchStartPaths.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchRestLabelsTests.swift`, `WatchRestNextHoldTests.swift`, `WatchModalityStartTests.swift`; serial).**
Items: D-20101 in `deriveRestLabels`; rewrite S-9104 and the NextHold ending; add S-20101..S-20105; D-20105 in `startModalityWorkout`; revisit S-17605; add S-20112..S-20114. Done list includes `swift test --filter WatchRestLabelsTests`, `--filter WatchRestNextHoldTests`, `--filter WatchModalityStartTests`, `--filter WatchSessionEngineTests` (the append-only guard).

**P2 — menu colours and End (owner: crew-builder-watch; scope `WatchMenu.swift`, `WatchMenuView.swift`, `ios/OmniTrain Watch App/ContentView.swift`, `WatchMenuTests.swift`, `WatchAccessibilitySourceTests.swift`; serial after P1).**
Items: D-20103 colours; D-20104 `hasRunningEffort`/`hasWorkToSave`/`finish()` and the `ContentView` argument; update the S-17101/S-17109 scans; add S-20106..S-20111. The lead builds the watch target with `xcodebuild` afterwards.

**P3 — docs (owner: crew-docs-keeper; scope the three docs below; after P1 and P2).** Execute the Docs delta.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_surface_wrist_logging.md | MODIFIED | `"Nothing planned next". The line's word is the rule` | `only a one-exercise ladder says "Nothing planned next"` | S-20101, S-20103 |
| docs/state_management/watch_surface_wrist_logging.md | MODIFIED | `"Next set: Period n" and "Nothing planned next"), and the rest screen's Next` | `a one-exercise "Nothing planned next"` | S-20103 |
| docs/state_management/watch_surface_wrist_logging.md | ADDED | - | `once every exercise is done, Next goes on to the following exercise in turn` | S-20101, S-20102, S-20105 |
| docs/state_management/watch_surface_wrist_logging.md | MODIFIED | `Finish, the phone's own words), and last Discard Session (plan 171);` | `Discard Session in red, End Session in the theme colour` | S-20106 |
| docs/state_management/watch_surface_wrist_logging.md | MODIFIED | `question instead, so nothing empty is saved to Health. Verified by` | `an End while an effort clock runs logs that effort first` | S-20107 |
| docs/state_management/watch_surface_wrist_logging.md | ADDED | - | `a modality button pressed over a started workout adds its exercise to it` | S-20112 |
| docs/watch-app-qa-wrist-logging.md | ADDED | - | `**The list restarts after the last set — (owner, plan 201).**` | S-20101 |
| docs/watch-app-qa-wrist-logging.md | ADDED | - | `**End Session keeps a running effort and the buttons wear their colours — (owner, plan 201).**` | S-20107 |

Stale-term sweep run 2026-11-15 (`grep -rIn "Nothing planned next\|nothingNext" lib test watch ios docs`): code hits are the copy and tests listed above; doc hits are the two rows. `Discard Session`/`End Session` appear in `docs/watch-app-setup-and-qa.md` (lines 197, 426, 561, 747) as plain descriptions of the buttons; none claims their colour or that End discards a running effort — the architect re-reads them and adds a row if one does.

## Open questions

- (owner to confirm) D-20101: the cycle announces the exercise by name only ("Next exercise: Bench"), never "Set 4 of 3". Say so if a set number is wanted.
- (owner to confirm) D-20103: Discard is a filled red button (system red, white label); End Session is the filled accent button, same weight as the current-exercise row.

## Progress

- [x] Seeded by the governor 2026-11-15 (scout sheets 1 and 3 read; base commit in `.work/2026-11-15-201/base.txt`).
- [x] P1 rest cycle and modality pick
- [x] P2 menu colours and End
- [x] P3 docs
- [x] Prove, review, report

## Assumption Log

| # | Assumption | Source | Status |
|---|---|---|---|
| A-1 | The architect step is skipped: the seed already names files, symbols, fixtures and phases, so the lead briefs builders from it directly. | lead, cost discipline | open |
| A-2 | Owner answers 2026-11-15: End Session logs a running effort first (D-20104); batches A and B now, C after. | owner | confirmed |
| A-3 | The Dart twin (`lib/watch`) has no rest-label or menu code (`grep -rn deriveRestLabels lib` empty), so no twin change. | lead grep | confirmed |
