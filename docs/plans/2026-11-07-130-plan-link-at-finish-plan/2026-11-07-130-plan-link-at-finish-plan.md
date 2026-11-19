# Plan — 130: a plan the wrist starts is marked done when the workout finishes, as on the phone

**Status**: seeded by the lead (2026-11-07); one build run, lead-reviewed.
**Next handoff**: `crew-builder-app` (production text given exactly; tests and one doc sentence are the run).
**Binding conventions**: `docs/global_conventions.md`.
**Track**: the watch → phone session contract (`lib/state/watch` + its tests), one track.
**Evidence path**: `docs/plans/2026-11-07-130-plan-link-at-finish-plan/2026-11-07-130-plan-link-at-finish-plan.evidence.md`
**Base commit**: see `.work/2026-11-07-130/base.txt` (branch `claude_develop`, tree carries the uncommitted plan 128 F1 work).
**Slug**: `2026-11-07-130-plan-link-at-finish`.

## Overview

On the phone, a planned workout stays planned until the workout is finished and saved; a discarded workout leaves the
plan planned (`day_session_list_screen.dart` links it only from `onSessionSaved`). Plan 129 made the wrist different: the
wrist's `session_started` report linked the plan the moment the wrist started it (D-8977 / D-8973), so a wrist start
followed by a discard burned the plan — it stopped being offered and pointed at a session that no longer exists.

Owner answer (2026-11-07): follow the way the phone already works. The report now only **hands over** which plan the
wrist started; the plan is marked done (completed + linked to the session) when the wrist **finishes** that session
(its `completed` lifecycle). A discard (`abandoned`) leaves the plan planned.

## Goal and acceptance

A wrist start of a plan opens the session row as before and changes nothing on the plan. The plan becomes completed and
linked to the wrist's session id only when that session's wrist `session_lifecycle` of state `completed` arrives, and only
if the session row still exists and the plan is still unstarted. `abandoned` forgets the plan. Acceptance: S-13030 to
S-13038.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13030 | Reverses plan 129 D-8977's link-at-start: `WatchSessionAdoptionBridge.onSessionStarted` keeps its gate and row-opening but no longer calls `_onPlanStarted`; it records `sessionId → plannedSessionId` in `_plansAwaitingEnd` | owner answer 2026-11-07; `day_session_list_screen.dart:304` links on save only |
| D-13031 | The link runs from `onLifecycle`, after the existing routing, on a wrist-origin `completed` lifecycle, independent of whether the phone holds the session (the phone may have ended it first, or never held it) | `onLifecycle` returns early on held mismatch today, which would skip a session the phone does not hold |
| D-13032 | `abandoned` removes the remembered plan; no link is ever written for it | S-13032 |
| D-13033 | Gates at link time: the plan still exists, `!isCompleted`, `linkedSessionId == null`, and the session row still exists in the repository; otherwise nothing is written | plan 129 D-8972 idempotency kept; S-13035, S-13036 |
| D-13034 | The remembered map is in memory only. A phone restart between the wrist's start and finish forgets the plan, which stays planned (the safe side: the same as a discard). Recorded limit, no persistence | no model field holds a plan id for a session (`grep plannedSessionId lib/data/models` has none) |
| D-13035 | `main.dart` wiring (`onPlanStarted: calendarState.completePlannedSession`) is unchanged; the callback keeps its name | minimal edit |
| D-13036 | The wrist-side planned list is unchanged: a plan stays in the wrist's list until the phone has linked it and the next sync arrives; a second start of the same plan before that opens a session and links nothing (gate D-13033) | the wrist refuses a second start while a session is live (plan 129 owner answer) |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13030 | A `session_started` report (origin watch, session `w-1`, plan `p-today`, routine `tpl-push`) through the whole router, Mock and Hive | the row `w-1` opens; the plan is not completed and has no `linkedSessionId`; the recorder is never called | the old code links at the report, so the plan is completed at once |
| S-13031 | The same report, then a wrist-origin `session_lifecycle` `completed` for `w-1`, Mock and Hive | the plan is completed with `linkedSessionId == 'w-1'`, read back from a new repository; the recorder is called once with (`p-today`, `w-1`) | the old code linked at the report, the recorder is called at the report not at the lifecycle |
| S-13032 | The report, then a wrist `abandoned` lifecycle, then a wrist `completed` lifecycle for the same session | the plan stays planned and unlinked at both steps; the recorder is never called | the old code linked at the report |
| S-13033 | The report, then `completed` delivered twice | the recorder is called once; the plan reads back linked once | a naive link-on-every-completed (no forgetting) would call twice |
| S-13034 | A free start report (no plan) then `completed`; and a `completed` for a session no report named | nothing is linked; no failure is recorded | an unguarded link would throw on a missing plan id |
| S-13035 | The report, then the plan is completed and linked elsewhere (a different session id), then `completed` for `w-1` | the plan keeps its first link; the recorder is not called | without the link-time gate the second link overwrites the first |
| S-13036 | The report, then the phone discards the session row (`deleteSession`), then `completed` for `w-1` | no link; the plan stays planned | without the row-exists gate the plan is linked to a session that does not exist |
| S-13037 | The report, then a `completed` lifecycle whose `origin` is `phone` | nothing is linked | without the origin guard a phone-origin frame links a plan |
| S-13038 | The report, the phone holds and has already ended `w-1` itself (G1), then the wrist's `completed` | the plan is linked (the session finished); the phone's session is not ended a second time | an implementation that links only inside the held-session branch skips this |

## Phases

| Phase | Owner | Scope | Items |
|---|---|---|---|
| P1 | `crew-builder-app` | `lib/state/watch/watch_session_adoption_bridge.dart`, `test/watch_session_import_test.dart`, `test/watch_session_adoption_bridge_test.dart`, `docs/watch_session_sync.md` | 1 apply the exact production text in the brief; 2 turn the existing tests that pin link-at-report (S-8963, S-8971, S-8964, S-8972 groups) to the new rule; 3 add S-13030 to S-13038 each as its own test (Mock and Hive where stored); 4 the one docs sentence |

Lead after P1: mutation pass (link at report restored; no origin guard; no row-exists gate; no link-time plan gate; abandoned
not forgotten; link only inside the held branch), the full suite, `flutter analyze` count 181, the invariant grep, the
ui/docs contract tests, PROTOCOL.md's two sentences.

## Progress

- [x] P1 build (run 20261107-165332-crew-builder-app, 10 m 7 s)
- [x] Lead: mutations (8 mutants; 3 survived, closed by two lead-written tests), full suite, analyze, grep, contract tests
- [x] Lead: PROTOCOL.md sentences

## Assumption Log

- D-13034 (in-memory only) is a recorded limit. If the owner wants the link to survive a phone restart, the wrist's
  `completed` lifecycle would have to carry `plannedSessionId` (a wrist and schema change), a separate unit.
- Found while reading, not fixed here: a report-opened row that never receives a snapshot and then meets `abandoned` is
  not held by the phone, so `onLifecycle` returns before discarding it and the empty row stays in the calendar. Not
  introduced by this plan; to be checked by the lead.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/watch_session_sync.md` | MODIFIED | and links the plan it names when that plan is unstarted, idempotently | and remembers the plan it names, linking it only when the wrist finishes that session | D-13030, S-13031 |
| `watch/sync_protocol/PROTOCOL.md` | MODIFIED | name the tapped plan, which the phone links; the link is idempotent, so a | name the tapped plan, which the phone links when the wrist finishes that session (a discarded session leaves the plan planned) | D-13030, S-13031 |
