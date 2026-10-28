# Series 87: New PR banner on the watch

> Status: 87a CLOSED 2026-10-27 (reviewed APPROVE, committed `d0189d6d`); 87b BUILT 2026-10-27, awaiting review; 87c proposed, not planned. 87b was planned on its turn against the code as it was then (`.github/copilot/pr-scope-budget.md`, "Over budget at planning time"), and 87b's own plan carries the decisions, scenarios and evidence.

## What the owner asked for, and decided (2026-10-26)

"Add the New PR message on the watch." The phone already shows "Congrats! New PR" when a logged strength set beats the user's best for that exercise (`docs/plans/in-session-pr-toast-plan.md`). The wrist shows nothing today and has no history to compare against.

Owner decisions (answers in chat, 2026-10-26):

1. **Look.** A short "New PR" banner with a trophy over the exercise screen for about 4 s, plus a distinct tap on the wrist, replacing the normal "logged" tap for that log. It never blocks Log, the rest timer or Next.
2. **No data, no message.** A wrist that has never received the phone's bests announces nothing. With bests held, an exercise the phone has no history for counts as a first-ever PR, as on the phone.
3. **One banner per device.** A set logged on the wrist gets the wrist banner; a set logged on the phone keeps the phone's toast. A phone-run workout mirrored to the wrist does not fire a wrist banner for phone-logged sets.

## Shared decisions

- PR definition is the phone's, unchanged: Epley estimated one-rep-max for sets with load, rep count for bodyweight sets, strict "greater than", `set` efforts only, completed sessions only (`StatsProgressService.epley1RM`, `getAllTimeBestE1RM`, `getAllTimeBestReps`).
- Data path: new `bests_down` message, phone → watch, kilograms on the wire, sent with every routines request (87a D-2, D-4).
- Nothing about PRs is persisted as events; bests are reference data on the wrist like the food list.

## The PRs

| PR | Order | Scope | Depends on | Track | Status |
|---|---|---|---|---|---|
| 87a | 1 | `bests_down` contract (schema, fixtures, PROTOCOL.md, both validators) and the phone builder and sender. Not visible to the owner. Safe to land alone: a wrist that does not know the type ignores it. | none | contract + phone | done (`d0189d6d`) |
| 87b | 2 | Wrist: store the newest frame, detect a PR when a set is logged on the wrist (running best per session so equal and repeated sets do not re-fire), banner, distinct tap, VoiceOver announcement, Sync-spinner handling, QA step, docs. Landed as one PR: the decision/lock/fold core was small enough that splitting it would have added a review round for no reduction in risk. | 87a | watch (Swift) | built, awaiting review |
| 87c | 3 | Close the two limits 87b stated rather than fixed: fold the phone's mirrored sets in during a live workout (no relaunch), and give the wrist's own-best memory a persistence or prune-order guarantee so a repeat cannot be lost before the phone's next frame. Extend the QA walkthrough with a phone-logged-set case. | 87b | watch (Swift) | proposed, not planned |

## The owner's questions, answered

Asked 2026-10-26 and answered inside 87b, so nothing here blocks review.

- **How old may the wrist's copy of the bests be before it stops announcing?** No age limit. A frame stays the wrist's truth until the next one replaces it; a wrist that has never received one stays silent (87b D-3, `WatchPersonalBestsTests.testS87b2AWristThatNeverReceivedAFrameSaysNothing`). 87a's default held.
- **A wrist set the phone has not folded in yet — how does it dedup?** The wrist folds its own logged sets into the comparison for the rest of its session (87b D-15), so an equal set never announces twice; the phone's frame remains the truth it compares against. A phone-logged set only counts after the watch app restarts — the one limit 87c would close.
- **Bodyweight sets with added or assisted weight.** The wrist reads the reps axis whenever `loadKg` is not above zero, which is exactly what the phone's toast does for a negative weight (87b open question (a), `WatchPersonalBestsTests.testS87b16AnAssistedSetWinsOnTheRepsAxis`).
