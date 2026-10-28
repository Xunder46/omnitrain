# Series 87: New PR banner on the watch

> Status: PLANNING 2026-10-26. This index plus the full plan of 87a. 87b is planned when its turn comes, against the code as it is then (`.github/copilot/pr-scope-budget.md`, "Over budget at planning time").

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

| PR | Order | Scope | Depends on | Track |
|---|---|---|---|---|
| 87a | 1 | `bests_down` contract (schema, fixtures, PROTOCOL.md, both validators) and the phone builder and sender. Not visible to the owner. Safe to land alone: a wrist that does not know the type ignores it. | none | contract + phone |
| 87b | 2 | Wrist: store the newest frame, detect a PR when a set is logged on the wrist (running best per session so equal and repeated sets do not re-fire), banner, distinct tap, VoiceOver announcement, Sync-spinner handling, QA step, docs. Split into 87b1 (store + detection, pure and tested) and 87b2 (banner + haptic + wiring) if the plan passes budget. | 87a | watch (Swift) |

## Open for the owner (do not block 87a)

- How old may the wrist's copy of the bests be before it stops announcing PRs? Today's rule: never-received only (87a D-8).
- A set the wrist logged but the phone has not yet taken into its history is not in the phone's bests: until the next sync the same wrist may announce a PR for an equal set. 87b decides how the wrist folds its own completed sets in (87b plan, Open questions).
- Bodyweight exercises with added or assisted weight (the wrist's extra-weight row): which axis they use must match the phone's toast exactly; 87b verifies against `workout_session_screen.dart:1042 _maybeShowPRToast`.
