# Plan 23a: watch QA fixes, pack 1 (wrist-only changes)

Base: d668924 on `claude_develop`. Governor-seeded, no architect run (the changes are small and
specific). Owner QA of 2026-10-11 produced 8 items plus one question; this pack covers the ones that
need no wire change. Packs 23b (item 8, full exercise list: contract change) and 23c (item 2, wrist
cardio entries not reaching the phone: investigation first) are separate plans.

## Goal and acceptance (what the owner sees on the wrist)

1. The session menu's last button reads **End Session** (was "Finish").
2. Tapping it asks first: title **Finish Workout?**, text "This action will save and close the workout
   session.", buttons **Cancel** and **Finish** (the phone's own sibling dialog, `workout_session_finish.dart`).
   Cancel changes nothing; Finish ends the session exactly as before (then the effort-rating question).
3. The rest screen says it is rest: a **Rest** caption above the clock (it only showed the exercise name).
4. A hold's companion row is labelled **Load** (was "Extra load", truncated on screen). Wire field
   `extraLoadKg` is unchanged. Same label in the Dart wrist client.
5. A sports period (round kind) shows a **period length** row with minus/plus before Start; its start
   value is the slot's `roundDurationSecs` (the phone's number) else 3:00. Stepping changes the length the
   countdown starts from. Once Start is tapped the row disappears and only the countdown and Log remain;
   the length cannot change while a period runs. The chosen length carries to the next period of the
   same slot, not to other slots. Minimum 1 second.
6. Alignment: every list row on the menu is left-aligned (title and "N logged" on one leading edge, a long
   name wraps leftwards, no row centred); the logging, rest and menu screens share one inset; the header
   (name, bpm) does not collide with the system clock/menu button. Detail in Phase 2.

Not in this pack: Add exercise (23b), the phone sync bug (23c), rest after timed/hold/round efforts
(owner question open: rest starts only after a set, by design of plan 18b).

## Decision ledger

- D-3401 Copy lives in testable package values, not in views (views compile only for watchOS): add
  `WatchMenuCopy` (finishLabel "End Session", confirmTitle, confirmBody, confirmCancel, confirmFinish)
  and `WatchRestSurfaceCopy.restCaption = "Rest"`. `WatchMenuView.finishLabel` currently
  `WatchMenuView.swift:33`; keep a single source (remove the old constant, update users).
- D-3402 Confirmation is a SwiftUI `.alert`/`confirmationDialog` in `WatchMenuView`; `state.finish()`
  runs only on the Finish button. No new engine path; the rating state's `end()` is untouched.
- D-3403 Label: `WatchLoggingState.label(for:)` `extraWeight` -> "Load" (`WatchLoggingState.swift:592`),
  Dart twin `lib/watch/logging/watch_logging_state.dart:531`.
- D-3404 Round length: `metricKeysByKind[round]` (`WatchLoggingState.swift:184`) becomes
  `[roundDuration]` but the field is listed by `fields` only while `!isWorkRunning`. The dialled value
  (`dialled[roundDuration]`, cleared by `dialled.removeAll()` after a log) must survive across logs of
  the same slot: keep a separate `[slotId: Int]` override map read by `plannedRoundMs`
  (`WatchLoggingState.swift:218`) before the slot's number and the preset. `initialValue(roundDuration)`
  returns the planned length in seconds when no timer runs. `startWork()` already passes
  `plannedRoundMs` to the timer (`:394`); that is what the countdown uses.
- D-3405 Step size: the existing `secondsPerDetent` of `WatchMetricStepping` (shared with hold
  duration, contract-tested): do not change it. Clamp: `roundDuration` floor becomes 1 s
  (`WatchMetricStepping.clamp`, `:120`) in Swift and its Dart twin if one exists.
- D-3406 The Dart wrist client (`lib/watch`) mirrors D-3403 only. It stays behind on the rest of the
  18b-21b behaviour (documented divergence); do not widen it.
- D-3407 No protocol/schema change in this pack.

## Scenarios (write these tests first; each must fail without the change)

- S-3401 `WatchMenuCopy.finishLabel == "End Session"`; the confirm copy equals the phone's strings.
- S-3402 `WatchMenuState.finish()` is unchanged: ending through it still yields the owed rating prompt
  (existing WatchMenuTests keep passing).
- S-3403 A drill slot's field with key `extraWeight` has `label == "Load"`.
- S-3404 A round slot with `roundDurationSecs: 2400` shows one field `roundDuration` value 2400; with no
  number, 180.
- S-3405 Stepping that field by +3 detents moves it by 3 x `secondsPerDetent`; `startWork()` then starts a
  timer whose `plannedDurationMs` is that value x 1000 (read from the engine timer row).
- S-3406 While the round timer runs, `fields` is empty (no row to change); after Log, the next period's
  field starts at the value used for the previous period, and a different slot starts from its own
  number.
- S-3407 A round field cannot go below 1 s.
- S-3408 A set slot and a timed slot still show exactly the fields they showed before (no `roundDuration`).
- S-3409 `WatchRestSurfaceCopy.restCaption == "Rest"`.

## Phases (serial: one Swift package)

| # | Owner agent | Scope | Items |
|---|---|---|---|
| 1 | crew-builder-watch | `watch/watchos/**`, `lib/watch/logging/**`, `test/**` | D-3401, D-3403, D-3404, D-3405, D-3406 and tests S-3401..S-3409 |
| 2 | crew-builder-watch | `watch/watchos/Sources/**` views, docs | views for 1-6 of the goal, docs |

Phase 2 views: `WatchMenuView` (label, confirmation, row alignment), `WatchRestView` (caption),
`WatchLoggingView` (period row appears through `fields`; spacing/inset; header must not overlap the
system clock: header top padding, `.lineLimit(1)`, `.truncationMode(.tail)`). Docs: `docs/state_management/watch_surface.md`
(stay under its size ceiling: remove before adding), `docs/watch-app-setup-and-qa.md` QA steps for the
confirmation, the Rest caption, the period length row; the QA index.

## Verification (governor, observed)

`swift test --package-path watch/watchos` (baseline 496/0), `flutter test` (+4240 ~1), `flutter analyze`
(196), xcodebuild watch scheme, invariant grep, mutations: revert the label; remove the override map;
let the field show while the timer runs; skip the clamp. (owner) On a real watch: the confirmation
prompt, the Rest caption, set a sports period to 1:00 and watch it count down from there.
