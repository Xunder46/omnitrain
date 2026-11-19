# Plan 243 — On the wrist, Next goes on to the following exercise in the list, not the first unlogged one

Owner report, 2026-11-18 (a holds routine of seven exercises, logged on the watch): after two exercises the owner went back to the first, logged it, and Next jumped to the third (the unlogged one) instead of the second; later, from the fourth, Next wrapped round to the third again and the owner logged a hold on the wrong exercise without noticing. The owner's rule: after the last planned set of an exercise Next goes to the exercise that follows it in the list, whether or not that one is logged.

Watch package only (`watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift`). No wire change, no phone change.

## Goal and acceptance

Today `deriveRestLabels` (the rest screen's "Next set: …/Next exercise: …" line and the slot Next opens, `WatchRestLabels.nextSlotId`) stays on the current exercise while its plan has sets left, otherwise searches FORWARD from the current exercise and then from the top for the first exercise that is not done, and only when every exercise is done does it go to the following one (plan 201 D-20101).

After this change: the stay rules are exactly as today; when Next leaves the exercise it goes to the exercise after the current one in the list (the last is followed by the first), done or not. A one-exercise list still has nowhere to go.

Acceptance: S-24301..S-24306 green; the six existing watch tests that pin the old search are rewritten to the new rule (listed under Readers) and green; `swift test` in `watch/watchos` green with observed counts; `flutter analyze` unchanged (no Dart change); Docs delta applied.

## What the user sees

- Rest screen after the last planned set of an exercise: "Next exercise: <the exercise right after it in the list>". If that exercise has sets or holds left, its count is shown ("Bench · Set 3 of 3"); if it is already done its name alone is shown ("Bench"). Tapping Next opens it.
- Going back to the first exercise, logging it and tapping Next opens the second, even though the second is done; from the last exercise Next opens the first.
- Unchanged: an exercise with sets left keeps "Next set: Set 2 of 3" and stays; a planned hold, interval or round stays until its plan is met; a period with no plan keeps its period line; a list of one exercise says "Nothing planned next".
- To SEE it: in a 3-exercise routine log exercise 1 fully, exercise 2 fully, then jump back to exercise 1 from the list, log one set, and read the line above Next: it names exercise 2 (before: exercise 3).

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-24301 | In `deriveRestLabels` the two blocks after the stay rules (`let order = Array((here + 1)..<slots.count) + Array(0..<here)` with `for index in order where !slots[index].isDone`, and the plan 201 D-20101 cycle `if slots.count > 1 { let following = slots[(here + 1) % slots.count] ...`) are replaced by one: with more than one slot, `following = slots[(here + 1) % slots.count]`, line = `following.name` when `following.isDone`, else `following.nextLabel(roundNoun:)`; `nextSlotId = following.slotId`. With one slot: `nothingNext`, no slot id (unchanged). | `WatchRestLabels.swift:deriveRestLabels` |
| D-24302 | The stay rules (`me.plannedEfforts`, planned sets, unplanned set, unplanned round) are not touched. | same function |
| D-24303 | `RestLabelSlot.isDone` stays (it now only picks the name-alone line); `leaveRest(advance:)` and the menu are untouched: they read `nextSlotId`. | `WatchLoggingState.swift:leaveRest` |
| D-24304 | Owner behaviour decision (2026-11-19, "yes, let's do it"): the wrap after the last exercise stays (the last is followed by the first). | owner chat |

## Scenarios

Fixture note: `WatchRestLabelsTests.swift` helpers `slot(_ id:_ name:planned:)` and `entries(_ id:_ count:)` build a set ladder (planned N sets, N entries logged); `restLadder`. A ladder is A "Squat" planned 2, B "Bench" planned 3, C "Row" planned 1, D "Lunge" planned 1 unless stated.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24301 | The owner's first case. Ladder A,B,C; A 2 logged, B 3 logged, C 0 logged; current index 0 (A, its plan met). | `nextSlotId == "B"`, `next == "Next exercise: Bench"` (name alone: B is done). | the base searches forward for the first not-done exercise and names C |
| S-24302 | The owner's second case. Ladder A,B,C,D; A,B logged fully, C not logged, D 1 logged (done); current index 3 (D). | `nextSlotId == "A"`, `next == "Next exercise: Squat"` (wrap to the first, done). | the base names C (the first not-done from the top) |
| S-24303 | Control. Ladder A,B,C,D; all logged except D; current index 2 (C done). | `nextSlotId == "D"`, `next == "Next exercise: Lunge · Set 1 of 1"` (an exercise short of its plan keeps its count). | passes both ways on purpose (mutation: the following exercise always named by its name alone) |
| S-24304 | Control. Ladder A,B; A planned 3 with 1 logged; current index 0. | `nextSlotId == nil`, `next == "Next set: Set 2 of 3"`. | passes both ways on purpose (mutation: the stay rule removed) |
| S-24305 | A partly logged next exercise. Ladder A,B,C; A 2 logged, B 2 of 3 logged, C 0; current index 0. | `nextSlotId == "B"`, `next == "Next exercise: Bench · Set 3 of 3"`. | passes both ways on purpose (mutation: name alone whenever the slot has any entry) |
| S-24306 | Through the engine. A session of three set exercises, all fully logged, current slot B; the rest's Next (`leaveRest(advance:)`, the fixture of `WatchRestAdvanceTests.testS9108TheRestsNextJumpsToTheAnnouncedExercise`). | `advance` is called with C's slot id; with current C it is called with A's. | the base (everything done) already cycles, so the first leg passes; the SECOND fixture, current A with C undone, calls C on the base and B on the new rule: use that as the failing leg |

## Input-reality checklist

1. Writers and units: counts come from the wrist's own entries and the phone's mirrored ones (`engine.entries`, per slot id); the rule reads counts only for the label and `isDone`.
2. Lifecycle: an exercise added or removed during a rest changes the list; the labels are derived on every read, so the following exercise is always the list's current one (a removed current slot clamps `currentIndex` as today).
3. Settings changing while open: none.
4. Time: none.
5. Load cost: O(n) over the ladder, as today (the search loop is removed).
6. Wording: prefixes unchanged ("Next set: " / "Next exercise: "); a done following exercise is named by name alone, as the plan 201 cycle line already did.
7. Slot competition: a phone-logged set during the rest changes counts only; the following exercise does not depend on counts except for the line's words.

## Phases

1. **P1 lead**: the production edit (D-24301), applied before the builder starts.
2. **P2 builder-watch**, scope `watch/watchos/Tests/**`: rewrite the six pinned tests and add S-24301..S-24306 in `WatchRestLabelsTests.swift` / `WatchRestAdvanceTests.swift`. No full suite; `gateway.sh swift-test --filter WatchSessionEngineTests` at the end.
3. **P3 lead**: mutation pass, docs delta (docs keeper), `swift test`, full `flutter test` once.

## Readers

Tests that pin the old search (builder rewrites them, each stating the new expectation): `WatchRestLabelsTests` `testS7603TheForwardSearchWinsThenTheBackwardOne`, `testS7603cAnExerciseWithItsPlanExactlyLoggedIsSkipped`, `testS7604EverythingDoneSaysNothingPlannedNext` (check), `testS9106ATimedEffortAnnouncesTheExerciseAndTheWrapHolds` (check), `testS20104AnUndoneExerciseWinsOverTheCycle`; `WatchRestAdvanceTests`, `WatchRestNextHoldTests`, `WatchPlannedSetsTests`, `WatchModalityKindTests`, `WatchMenuTests` (run; rewrite only a test whose premise is the old search). Other readers of `nextSlotId`: `WatchLoggingState.leaveRest`, the rest view. The Dart twin `lib/watch/logging/watch_rest_screen.dart` does not show these lines (docs say so).

## Mutation list (lead)

(a) back to the not-done search; (b) the wrap `% slots.count` removed (index out of range or no wrap); (c) following named by name alone always (S-24303, S-24305); (d) `nextLabel` always (S-24301); (e) stay rule for planned sets removed (S-24304); (f) the one-slot guard removed.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/watch_surface_wrist_logging.md` | MODIFIED | the next exercise is searched | the next exercise is the one after the current one in the list | S-24301, S-24302 |
| `docs/state_management/watch_surface_wrist_logging.md` | MODIFIED | unfinished exercise ("Next exercise: Barbell Back Squat | following exercise ("Next exercise: Barbell Back Squat | S-24301 |
| `docs/state_management/watch_surface_wrist_logging.md` | MODIFIED | once every exercise is done, Next goes on to the following exercise in turn | Next always goes on to the following exercise in the list, done or not | S-24301, S-24302 |
| `docs/watch_session_sync.md` | MODIFIED | next not-done exercise with its own count | next exercise in list order with its own count | S-24303 |
| `docs/watch-app-setup-and-qa.md` | MODIFIED | it names the first exercise after it that has no | it names the exercise right after it in the list | S-24301 |
| `docs/watch-app-setup-and-qa.md` | REMOVED | hold yet, or, with none after it, the first one from the top that has | - | S-24302 |
| `docs/state_management/watch_surface_wrist_logging.md` | MODIFIED | Next keeps cycling. An undone | Next keeps cycling and never prefers an undone | S-24301 |
| `docs/state_management/watch_surface_wrist_logging.md` | REMOVED | exercise still wins over the cycle | - | S-24301 |
| `docs/state_management/watch_surface_wrist_logging.md` | MODIFIED | testS20104AnUndoneExerciseWinsOverTheCycle | testS20104TheFollowingExerciseWinsOverAnUndoneOneElsewhere | S-24301 |
| `docs/state_management/watch_surface_wrist_logging.md` | MODIFIED | testS7603cAnExerciseWithItsPlanExactlyLoggedIsSkipped | testS7603cTheFollowingExerciseIsNamedWhetherOrNotItIsDone | S-24301 |
| `docs/watch-app-qa-wrist-logging.md` | MODIFIED | testS20104AnUndoneExerciseWinsOverTheCycle | testS20104TheFollowingExerciseWinsOverAnUndoneOneElsewhere | S-24301 |
| `docs/watch-app-qa-wrist-logging.md` | MODIFIED | testS7603cAnExerciseWithItsPlanExactlyLoggedIsSkipped | testS7603cTheFollowingExerciseIsNamedWhetherOrNotItIsDone | S-24301 |

The two sentences at `watch_surface_wrist_logging.md:269-270` ("Next keeps cycling. An undone / exercise still wins over the cycle.") are one sentence the keeper rewrites to say that Next never prefers an undone exercise over the following one; both Old markers must be gone.

Stale-term sweep (`grep -rIn "not-done\|searched forward\|first exercise after it\|unfinished exercise" docs` outside plans/history/releases) hits exactly the four lines above. The keeper also re-reads the plan-201 paragraph around `docs/state_management/watch_surface_wrist_logging.md:262` so the sentence stays grammatical.

## Open items

1. (owner) QA step 41 in `docs/watch-app-setup-and-qa.md` changes: on a watch, log exercises 1 and 2 of a 3-exercise routine, jump back to 1, log, tap Next: it opens 2.
2. After this change nothing sends the user to an unlogged exercise by itself: a user who finishes a routine out of order finds the missed exercise through the list (the pager and menu are unchanged).

## Predicted files

`WatchRestLabels.swift` (-20 +10), `WatchRestLabelsTests.swift` (+150, -60), `WatchRestAdvanceTests.swift` (+40), up to three other watch test files (small edits), three docs.

## Progress

- [x] Seeded
- [x] P1 production edit (lead)
- [x] P2 tests (builder-watch): 4 rewritten, 6 added, swift test 1600 tests 0 failures
- [x] P3 mutation pass (7 of 7 killed), docs (lead-written, plan-lint clean), see `.evidence.md`
- [x] Full `flutter test` 8111 passed, 4 skipped, 0 failed (with plan 244; no Dart change in this plan)
- [ ] (owner) QA step 41 on a watch, Open item 1

## Assumption Log

- 2026-11-19: base commit in `.work/2026-11-19-243/base.txt`. The branch is `claude_develop` (not `develop`); another session's uncommitted files (decimal comma, plan 208, stats gallery test) are outside this plan and are never staged or edited here.
- 2026-11-19: ids S-243xx: none found.

## Feedback

(none yet)
