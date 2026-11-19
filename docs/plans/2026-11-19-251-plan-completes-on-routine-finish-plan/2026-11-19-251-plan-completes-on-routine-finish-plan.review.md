# Review: plan 251 · P1-P3 · 6b1cd237..working tree

Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: not re-run — brief states the governor already ran the full suite (plan-251 tests 22/22 pass, `flutter analyze` at baseline 178 issues / 0 errors, `test/state_test.dart` passes). Per the brief I did not run the full `flutter test`.
Diff vs Predicted Files: outside — `test/food_catalog_load_test.dart` (1 line, unattributed). `macos/Flutter/GeneratedPluginRegistrant.swift` carries only a line-ending warning, no content change (not a finding). The plan file itself is expected.

1. [Major] `test/food_catalog_load_test.dart:270` — a change outside the plan's Predicted Files: `expect(withSkin.fat, greaterThan(byId['chicken_thigh']!.fat))` replaces `...!.fat!`. Unrelated to plan 251 (food catalog), unattributed in the plan, so a maintainer cannot tell which change owns it. Failure scenario: this branch's review approves a behavioural change the plan never describes. Fix: attribute it in the plan (lead's analyze fix) or move it to its own change. Guard: none needed — a scope-attribution fix.

2. [Minor] `lib/state/calendar/calendar_state.dart:306,265` — the plan's cost line (Input-reality item 5, "one `getPlannedSessions` read at Finish") is not what the code does: `completePlanFor` reads all plans, then `completePlannedSession` reads them again before the write (plus `_loadMonth`'s reads after the write). Impact is one extra read per routine finish; no user-visible failure. Fix: correct the plan line (or pass the already-read list into `completePlannedSession`; not worth the churn).

3. [Minor] Open item 3 is declared but untested: starting plan B of two same-day same-routine plans from the day list now leaves BOTH plans completed and linked to the one workout (the hook completes A at Finish, `onSessionSaved` completes B at summary open). New behaviour this change introduces, owned as an open item — no test covers the double-completion. Fix (once the owner decides): a fixture with two plans + the day-list `onSessionSaved` callback asserting both outcomes.

## What I verified (per question)

Q1 callers of `endSession(`: `workout_session_finish.dart:114` (live Finish), `session_summary_screen.dart:448` (`_finishAndSaveSession`, guarded by `!_isHistoricalView` at :444), `watch_session_adoption_bridge.dart:984` (the wrist's end, `writeToHealth: false`), `workout_state.dart:275` (facade). No false link: a historical session never re-ends (`_notifySessionSaved` returns early for historical at :163, summary `_finishAndSaveSession` skips `endSession` for historical, edit mode blocks finish at `workout_session_screen.dart:352`); discard routes through `discardUnfinishedSession`→`discardCurrentSession` (delete + `clearSession`, `session_core_lifecycle.dart:307-343`), never `endSession`; a session whose persistence threw returns from the catch before the hook (`session_core_lifecycle.dart:140-143`); an already-ended session returns at :21-22, so the hook cannot double-fire; the day comes from `startedAtMs` (S-25108 covers midnight crossing). The hook also fires on the wrist's own end — plan 251's stated intent (input-reality item 7); the bridge's own `_linkPlanAtEnd` then no-ops on the plan the hook completed (it re-checks `isCompleted`/`linkedSessionId`, `watch_session_adoption_bridge.dart:1023-1025`).

Q2 ordering: `onLifecycle` awaits the phone's `endSession` (hook runs inside) before `_linkPlanAtEnd` (:908-909), and the day-list `onSessionSaved` fires when the summary opens, after Finish — the hook is always first. The tapped plan always ends up linked (the hook never deletes or rewrites the tapped plan; `completePlannedSession` re-links it idempotently). One plan cannot link to two sessions: `completePlanFor` filters out plans with a non-null `linkedSessionId` and early-returns when any plan is already linked to this session. No stale overwrite: `completePlannedSession` rebuilds the whole row from a fresh read (`calendar_state.dart:265-289`), so the second write re-derives every field — it only bumps `updatedAtMs`.

Q3 re-entrancy / month reload: `completePlanFor`'s whole call sits in its own try/catch inside `endSession` (`session_core_lifecycle.dart:99-107`), so a throw from `getPlannedSessions`, `completePlannedSession` or `_loadMonth` never reaches `endSession`'s caller (S-25107 exercises the shield). `_loadMonth` reloads the `CalendarState`'s displayed month and notifies its own listeners — at Finish the calendar sits in the back stack, so the user sees fresh data on return; no re-entrant call back into the hook.

Q4 assertions are behavioural, not presence: S-25102 (Nov 17/19 untouched) kills a removed day check; S-25103 (other-routine plan and free plan untouched, plus a no-routine workout) kills a removed routine check; S-25108 (started 23:50 Nov 18, ended 00:20 Nov 19) kills taking the day from the end time; S-25105 (B written first, A linked by `createdAtMs`) kills write-order choice; S-25111 (a plan already linked to the session, plus an unstarted sibling) — stronger than S-25106 — kills the removed already-linked guard; S-25109/S-25110 kill taking a linked-but-unstarted and a completed-but-unlinked plan. No assertion would still pass if the hook linked ANY routine's plan, or the wrong day.

Q5 docs: the `docs/calendar_periods.md` delta row is applied (sentence at :73 ties to `test/plan_completes_on_routine_finish_test.dart` S-25101..S-25111 — all present in the file) and the CalendarState responsibilities bullet at :229 names `completePlanFor`/`onSessionEnded`, both of which exist. The retained "originating `PlannedSession`" sentence stays true (it describes the unchanged day-list path). Stale-term sweep outside plans/history/releases: no sentence claims plans complete only when started from the day list or the watch; `docs/state_management/app_state.md`'s CalendarState section makes no claim this change falsifies.

## Assumption Log rulings

The plan carries no separate Assumption Log; its Open items rule as follows.

1. Free-training plans not matched by a matching free workout — ratify (D-25104; S-25103 asserts the free plan stays untouched).
2. The plan completes at Finish (stored), not at start; a discarded workout never completes — ratify (consistent with the day-list path; discard verified above not to call `endSession`).
3. Two same-day same-routine plans + a day-list/watch start → both completed for one workout — escalate to the owner: a product decision, declared but untested (finding 3).

## Scenario coverage

S-25101 → `test/plan_completes_on_routine_finish_test.dart` · "S-25101 finishing the routine workout completes its unstarted plan for today and links it" (Mock + Hive)
S-25102 → same file · "S-25102 plans for other days are untouched"
S-25103 → same file · "S-25103 another routine plan and a free plan stay untouched, also after a workout with no routine"
S-25104 → same file · "S-25104 an already completed plan is never taken again"
S-25105 → same file · "S-25105 two unstarted plans for the routine today: the one created first is linked"
S-25106 → same file · "S-25106 a second endSession writes the plan nothing more"
S-25107 → same file · "S-25107 a failing plan completion never fails the Finish"
S-25108 → same file · "S-25108 a workout started 23:50 and ended 00:20 completes the plan of the day it started"
Beyond the plan: S-25109 (linked-but-unstarted plan not taken), S-25110 (completed-but-unlinked plan not taken), S-25111 (a session a plan is already linked to changes nothing) — all present, all Mock + Hive.

## Docs delta

`docs/calendar_periods.md` MODIFIED (new sentence at :73, new responsibilities bullet at :229) -> applied. Note: the responsibilities bullet at :229 is a doc edit the table does not name (correct content, verified against `calendar_state.dart:303-329`).

## Lead dispositions

1. Major `test/food_catalog_load_test.dart:270`: not this plan's change; the file was already modified before the unit started (the owner's) and stays unstaged.
2. Minor (cost line said one read, the code reads twice when a plan matches): the plan's checklist item 5 corrected; no code change.
3. Minor (open item 3, two same-routine same-day plans started from the day list complete both, untested): left as the declared open item for the owner; no test until the owner decides.
