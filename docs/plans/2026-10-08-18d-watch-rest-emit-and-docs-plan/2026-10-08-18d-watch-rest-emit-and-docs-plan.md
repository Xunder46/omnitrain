# Feature: the watch emits its rests, and the totals and docs follow (18d)

> Status: Iteration 1 active — written by the planner from plan 18c's seeded Phase 1B and Phase 3 (moved here by the
> governor's scope split of 2026-10-08). No phase has started.
> Next handoff: @developer (Phase 1).
> Depends on **18c committed first** (the wire and the phone's writer):
> `docs/plans/2026-10-08-18c-watch-rest-to-phone-plan/2026-10-08-18c-watch-rest-to-phone-plan.md`. A wrist built from
> this plan must not send a rest to a phone that does not have 18c: the phone would never stage or receipt the row
> (`WatchInboxEntry.watchKinds`, `docs/plans/2026-10-08-18c-watch-rest-to-phone-plan/…plan.md` D-214), so the wrist
> would re-offer the same frame forever.
> Binding conventions: `docs/global_conventions.md`; plus `docs/rest_tracking.md` (`## The Wrist's Rest`),
> `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`,
> `docs/documentation_standard.md`, `docs/app_philosophy.md`, and 18b's D-160…D-169
> (`docs/plans/2026-10-08-18b-watch-rest-count-up-plan/…plan.md`).
> Evidence: `…-plan.evidence.md` (baselines, red→green, pasted counts) · Review: `…-plan.review.md`.
> **Transpose note (18c's A-6).** Plan 18c keeps one-line "→ moved to plan 18d" markers for the entries below and
> reproduces none of them; this file holds them **in full, under their original ids**, with 18c's D-214…D-218 and D-222
> staying there and cited by id. Ids are never renumbered and never reused.

## Overview

18b made the wrist's rest a count-up with its own screen and Next; 18c made the phone **able to receive** a rest (the
wire kind, the staging field contract, the importer's writer) while **no client sends one yet**. This plan is the sender
half plus the docs that must follow it.

**What the user sees after this plan.** A set logged on the watch, a rest that ends at **Next**, at **the next set**, or
when **the workout ends**, then afterwards on the phone: the session holds a rest between those two sets, with the same
start and end the watch showed, and the session's Rest stat counts it exactly like a rest the phone itself counted.
Nothing changes on the watch screen, no rest is ever sent for a window of no length, and a spot where the phone logged
the set itself keeps the phone's own rest untouched.

**What ships here.** Phase 1: the wrist emits one `observations_up` `rest` event per completed rest — Swift client, the
Dart twin, and the finish-path stop that **does not exist at the base commit** (18c's V-1). Phase 2: the totals and views
are asserted against the shipped phone surfaces (no production change expected — `computeSessionRestTimeMs` already sums
whatever rests exist) and the four documents that still claim a wrist rest cannot travel are made true, plus the 17a
annotation and this series' index rows.

**Out of scope** (D-218, which stays 18c's): editing, pausing or deleting a rest on either device, showing wrist rests on
the watch, any rest length, rests in a routine, the phone sending its rests to the watch.

### Acceptance criteria

Numbered as 18c's own list so the split stays traceable; the parenthetical says which of 18c's criteria this is.

1. **(18c criterion 1, wrist half)** The wrist emits one `rest` observation per completed rest, in the Swift client and
   in the Dart twin, carrying D-166's fields; never for a rest whose `endedAt <= startedAt`; a rest still running when
   the workout ends is emitted with the workout's end instant — which means the finish path first has to **stop** it
   (S-320 wrist half, S-321, S-322, S-323 wrist half, S-331…S-336, S-339).
2. **(18c criterion 4)** `SessionSummaryService.computeSessionRestTimeMs` totals an imported wrist rest, and the phone's
   session views read it where they read any rest, with no new screen and no new widget (S-329, S-340).
3. **(18c criterion 6)** Docs are true where they claim what travels: the sync doc's and watch-surface doc's "what
   travels" lists, `docs/rest_tracking.md`'s `## The Wrist's Rest`, the QA guide's device-local sentence, 17a's D-80/S-79
   annotated per 18b D-165, and the 18 series index row for 18c and 18d (S-341).
4. **(18c criterion 7)** Baselines hold or rise: flutter `+4181 ~1`, swift `376 / 0`, analyze `196 / 0`. The governor runs
   `xcodebuild "OmniTrain Watch App"` (only the governor; no agent builds the watch app).
5. The rest rule (18b D-160/D-164) is untouched by every edit here: the event carries a start and an end and no planned
   length, and `test/rest_is_count_up_contract_test.dart` — which scans `watch/sync_protocol/schemas` too — stays green.

## Requirements

Numbered as 18c's own list; R-1/R-4/R-6 moved here with their text, R-7 is this plan's addition for V-1.

- **R-1 (moved from 18c)** The wrist emits one `rest` observation per completed rest, from the one place every wrist-side
  ending goes through, with the fields of D-166/D-220, identically in the Swift client and the Dart twin (S-320, S-332,
  S-335).
- **R-4 (moved from 18c)** An imported rest renders and totals exactly like a phone-counted rest of the same window
  (S-329, S-340).
- **R-6 (moved from 18c)** Docs are true where they claim what travels, 17a D-80/S-79 is annotated, and the 18 index
  gains its row (S-341).
- **R-7 (new, V-1)** A rest still running when the workout ends is stopped at the session's end instant and emitted once
  (S-322, S-331): at the base commit `finishSession`/`abandonSession` stop no timer at all, so the rest would run
  forever and nothing would be emitted. D-211 pre-authorises the addition; D-223 pins where it goes and at which
  instant.

## Verification of the moved facts (planner, read at the base commit)

18c's V-1…V-5 stand and are not re-derived. What this plan's executor needs, with the symbol that decides it:

- **V-1 — the finish path stops nothing.** `WatchSessionEngine.transitionTo` (`WatchSessionEngine.swift:1071`) calls only
  `captureSessionEnd` (`:1381`) and then appends the terminal row; nothing calls `stopTimer` (`:1569`). The Dart twin is
  the same (`_transitionTo`, `lib/watch/session/watch_session_engine.dart:1148`, from `finishSession` `:341` /
  `abandonSession` `:347`). **Added here** per R-7/D-223, before the terminal row is written.
- **V-2 — the `afterEntryId` lookup is positional** (D-221): the newest effort observation of the session whose **store
  `sequence`** is lower than the pre-stop rest timer row's. Every row carries `sequence` (`WatchObservationRecord`,
  `WatchRecords.swift:318`; Dart the same) and the store assigns it on append, so the comparison needs no array index.
- **V-3 — the effort event already carries what the rest event needs.** `WatchLoggingState.log()` builds
  `entryId = eventId = id`, `kind`, `loggedAt`, `sessionExerciseId` and `exerciseId` (`WatchLoggingState.swift:563-589`;
  Dart `watch_logging_state.dart:607-629`) and ends a running rest at **this log's instant** before appending the new
  entry — which is exactly why the positional lookup returns the *previous* entry (S-321). The rest event's
  `afterEntryId` is that observation's `entryId`, and D-224 takes its exercise fields from the same row.
- **V-4 — the emission path is the existing one.** `appendObservation` (public `:1167`, private `:1225`; Dart `:1236`/
  `:1288`) stores the row first, emits second, and skips the emit when the `recordId` is already stored; `eventId`
  becomes `recordId` and `messageId = "msg-<recordId>"` (`:1776`, Dart `:1680`). Reusing a timer row's `recordId`
  directly would therefore mint the *same* `messageId` its `timer_state` frame used, which is why D-223 derives the
  event id instead.
- **V-5 — the twin has no `session_end` observation, and no `efforts` list either.** Dart `WatchObservationKind.all` is
  `[set, timed, round, hold, nutrition_quick_log]` (`lib/watch/session/watch_records.dart:58,68`) while Swift's `all` also
  carries `effort_rating` and `session_end` (`WatchRecords.swift:70-75`); Dart has no counterpart to
  `WatchObservationKind.efforts` (`WatchRecords.swift:76`) at all (grep `efforts` in `lib/watch/session/` finds only an
  unrelated comment at `:644`), so Phase 1 adds it beside `all` before D-221's lookup can use it. The finish-path
  emission must not depend on `session_end`: the rest event is an observation of its own and the session end travels as a
  lifecycle frame (`captureSessionEnd` / `emitLifecycle`), already true in both stacks.
- **V-6 — both stacks guard the kind list.** `WatchNutritionQuickLogTests.testTheKindsTheWristCanEmitAreAClosedSet`
  (`watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionQuickLogTests.swift:583`) and
  `test/watch_nutrition_quick_log_test.dart:1338` (`the kinds the wrist can emit are a closed set`) compare
  `WatchObservationKind.all` to a literal list, so adding `rest` turns both red until each names it — the guard that
  makes the new kind deliberate rather than incidental.

## Resolved Decisions (Ledger)

18c keeps one-line markers for D-211/D-212/D-213/D-219/D-220/D-221; their full text lives here under the same ids, as
D-210 said it would. D-210, D-214…D-218 and D-222 stay in
`docs/plans/2026-10-08-18c-watch-rest-to-phone-plan/…plan.md` and bind here by reference. D-166/D-167/D-169 (18b) and
D-160/D-161/D-164 (18b, the rest rule) are cited, never restated.

**D-210 — Pinned designs stand.** *(held by 18c, full text there)* — 18b's D-166 (the `rest` observation: `eventId`,
`sessionExerciseId`, `exerciseId`, `startedAt`, `endedAt`, `afterEntryId`; emitted when the rest ends;
`endedAt <= startedAt` not emitted; a rest running at the workout's end is emitted with that end instant; no new message
type; `$defs.event` oneOf gains the value; no version bump) and D-167 (`EntryRest` with
`entryIndex = index of afterEntryId's entry + 1`, `id = 'rest-<effortId>-<entryIndex>'`, `restStartMs = startedAt`,
`restEndMs = endedAt`, never paused, first write wins, a rest is never placed, re-stated, re-indexed or deleted with its
set, an `afterEntryId` that resolves to nothing is dropped) are implemented as written.

**D-211 — Where the wrist records the rest.** At the one place every ending goes through: the engine's rest-timer stop
(`WatchSessionEngine.stopTimer(kind:)`, `WatchSessionEngine.swift:1569`; Dart twin `lib/watch/session/watch_session_engine.dart`
`stopTimer`, `:1441`), not in the view and not in `WatchLoggingState.endRest()` alone — `endRest` (`WatchLoggingState.swift:271`),
`log()`'s "a rest can never outlive the entry that follows it" (`:589`), a phone-sent stop and the session finish all end
a rest, and a path that bypasses the engine would silently lose it. The planner verifies that `finishSession` /
`abandonSession` (`WatchSessionEngine.swift:340,349`) stop a running rest at the session's end instant; if they do not,
the phase adds that, and says so. Emission uses the existing `appendObservation` (`:1225`), so retry, ordering and
delivery-owed (19b) apply unchanged.

**D-212 — Idempotency.** `eventId` is derived from the rest timer row's `recordId` (stable across a re-send), so a
re-delivery is the same event; the phone's `EntryRest.id` (D-167) is the second guard. A rest that ends twice (a stop of
an already stopped timer) emits once. *(The exact derivation is D-224.)*

**D-213 — `afterEntryId` is the set the rest follows.** The `entryId` of the last observation the wrist logged on that
exercise before the rest started — the entry whose log started the rest. The planner pins the exact lookup (the rest
timer row is started by `startFollowOnTimer`, `WatchLoggingState.swift` after `appendObservation`); a rest with no such
entry (a rest started by another route) is not emitted. *(The exact lookup is D-221.)*

**D-219 — exactly one emission site, and only a wrist-side ending fires it.** The emission lives in the engine's rest
stop (D-211) and nowhere else. The endings that reach it are exactly the three a wrist-side actor causes: the explicit
stop (`WatchLoggingState.endRest()` `WatchLoggingState.swift:271`, Dart `watch_logging_state.dart:197` — the rest
screen's Next), `log()`'s pre-entry stop (`:589`, Dart `:629`), and the finish path (D-223). A stop **the phone** sent
does not: `stopTimerFromMessage` (Swift `:752`, Dart `_stopTimerFromMessage` `watch_session_engine.dart:768`) — reached
from `adoptTimers` (`:683`, Dart `_adoptTimers` `:667`), `applyTimerState` (`:658`) and both sides' message handling —
records the timer state and returns **without emitting**, because the phone authored that ending and returning its own
rest to it would double-count (D-216 at the wrist). Consequence: a phone-initiated stop produces no frame at all, so
the wrist cannot be the source of a duplicate (S-333).

**D-220 — what the emitted event carries, and how it travels.** The event is D-166's shape, built from the stopped rest
timer row plus the session: `kind: "rest"`; `sessionExerciseId` and `exerciseId` from the rest timer row's own exercise
instance (the row 18b already writes from the timer); `startedAt` = the row's timer start; `endedAt` = the ending instant
the caller passed in (D-223), never a second clock read; `afterEntryId` = D-221's answer. It travels as an ordinary
`observations_up` event through the existing `appendObservation` (Swift `:1167`/`:1225`, Dart `:1236`/`:1288`:
stored first, emitted second; a stored `recordId` suppresses a second emit) and the existing retry/ack machinery — no new
message type, no hand-built frame, no version bump. Nothing is emitted when `endedAt <= startedAt`, and nothing is
emitted when D-221 has no answer; in both cases the stop itself still happens and the timer row is still appended (the
rest is over either way — only its travel is skipped).

**D-221 — the `afterEntryId` lookup, stated exactly.** Positional, against the store's own row order, because the rest
timer row carries no slot: the `recordId` of the **newest effort observation of the same session whose stored row
precedes the pre-stop rest timer row's** (`sequence` is assigned on append — `WatchObservationRecord`,
`WatchRecords.swift:318`; Dart the same), skipping timer rows and every non-effort record. Effort kinds are the closed
set `WatchObservationKind.efforts` = `set`, `timed`, `round`, `hold` (`WatchRecords.swift:76`; **added to the twin in
Phase 1 — it has none today**, V-5) — `nutrition_quick_log`, `effort_rating` and `session_end` are never an answer. The stored row supplies the id only: the
emitted `afterEntryId` is that row's `entryId` (the id the phone's importer resolves, D-215). No effort observation
precedes the rest row → nothing is emitted (S-334). The rule is positional on purpose, so a rest the wrist **adopted**
from the phone still emits when the wrist ends it (S-336), and it survives a relaunch because it reads the store, not
memory (S-339).

**D-223 — every wrist-side ending is stopped at an instant the caller already has, including the finish path (V-1).**
Three sites, one rule:

1. **The explicit stop** (Next, and any other caller of `endRest()`): the clock, as today.
2. **`log()`'s pre-entry stop** (`WatchLoggingState.swift:589`, Dart `:629`): the log's own instant — the same `loggedAt`
   that frame carries. At the base commit this site calls `endRest()` and lets the engine read a second clock value; the
   two differ by microseconds and the emitted window must be the one the rest screen showed and the frame reports.
3. **The finish path (the addition V-1 names).** `transitionTo` (Swift `:1071`, Dart `_transitionTo` `:1148`) stops a
   running rest **before** it builds the terminal row — it copies `session.exercises` into the new row, so a stop after it
   would land on a session that is already over — at the session's end instant (the instant `finishSession` `:340` /
   `abandonSession` `:349` is ending at; Dart `:341`/`:347`). `captureSessionEnd` (`:1381`) and `sessionEndEvent`
   (`:1404`) are untouched, and the twin needs no `session_end` observation: the end still travels as a lifecycle frame
   (V-5).

Mechanically: `stopTimer` gains an optional instant (`kind:rest, at: Date? = nil` Swift; `{String? kind, DateTime? now}`
Dart) which defaults to the clock, `endRest()` gains the same optional parameter and passes it through, and the emission's
`endedAt` is always that instant. A `replaySessionEnd` (`:1145`) — a replayed lifecycle frame — re-emits nothing: the
rest row is already stopped, so `stopTimer`'s early guard returns before the emission (S-332's rule).

**D-224 — the emitted event's identity is derived, so it cannot collide with the same row's timer frame.** *(refines
D-212; it does not supersede it.)* `stopTimer` appends the row through `appendTimer` (`:1574`), which emits a
`timer_state` frame whose id is `messageId(for: row.recordId)` = `"msg-<recordId>"` (`:1776`, Dart `:1680`). Reusing that
`recordId` as the observation's `eventId` would give the rest event the *same* `messageId` as the `timer_state` frame from
the same row — one receipt would then cover both, and the delivery-owed machinery could suppress the observation. So the
event's `eventId` is `<row.recordId>-rest`: derived from the row (D-212 — stable across a re-send, because the row's id
is), distinct from the timer frame's, and identical on every re-send. `recordId` and `messageId` follow from it as
always. A second stop of the same rest reaches `stopTimer`'s `guard` (`activeTimer`/`state != stopped`) and neither
appends nor emits (S-332).

**D-222 and D-214…D-218 (held by 18c).** The wire's rest event and the entry shape (D-222), the staged kind (D-214), the
importer's `_applyRests` (D-215), the phone's authority (D-216), the amendment row (D-217) and the out-of-scope list
(D-218) are 18c's and are implemented there; this plan's Phase 2 asserts against the surfaces they produce and edits the
docs they invalidate. No entry here re-decides any of them.

## Feature Invariants

Only the invariants this feature can plausibly break; project-wide rules stay in `docs/global_conventions.md`.

- **The two engines stay twin-shaped.** Anything the Swift engine emits the Dart engine emits too, with the same kind,
  the same fields and the same ordering relative to the entry that follows (S-335). A field that exists in one and not
  the other is a defect, not a twin difference.
- **Only a wrist-side ending speaks.** D-219's rule is an invariant, not a nicety: a phone-sent stop emits nothing.
  A frame whose ending the phone caused is a double count waiting to happen (S-333).
- **The rest rule.** The event still carries a start and an end and no planned length: no `restSeconds`,
  `restDurationMs`, `restLengthMs`, `defaultRest*` or `kRest*` identifier, no "rest countdown"/"rest remaining" wording,
  no `startTimer(WatchTimerKind.rest, plannedDurationMs:)`. `test/rest_is_count_up_contract_test.dart` scans
  `watch/sync_protocol/schemas` too, so nothing added here escapes it (criterion 5).
- **The kind list is closed and deliberate.** `WatchObservationKind.all` is pinned by a test in each stack (V-6); `rest`
  joins `all` and never joins `efforts`.
- **A rest never outlives the entry that follows it, and never outlives the workout.** `log()`'s pre-entry stop stays
  before the new entry is appended, and the finish path stops before the terminal row is built (D-223).
- **Emitted state is stored state.** An emission never writes a row the store does not have: the observation is appended
  through `appendObservation`, never synthesised at send time.

## Existing-Functionality Impact

Each row: the wrist surface this feature touches → what already reads it (the grep that found it) → what the change does
to it → the guard. `grep -n "stopTimer\|appendObservation\|WatchObservationKind\|efforts\|finishSession\|abandonSession\|transitionTo\|storedObservations\|_observations\|getEntryRests\|computeSessionRestTimeMs"` over
`watch/watchos/Sources/`, `watch/watchos/Tests/`, `lib/` and `test/` produced these readers. The phone-side rows
(`_effortKinds`, `_requiredFields`, `createEntryRest`, the wire, the SQL contract) stay in 18c's table and are not
re-litigated.

| Touched surface | What already reads it | Effect | Guarded by |
|---|---|---|---|
| `WatchObservationKind` `all` (`WatchRecords.swift:71-75`) and its Dart twin (`lib/watch/session/watch_records.dart:68`) | `WatchNutritionQuickLogTests.testTheKindsTheWristCanEmitAreAClosedSet` (`…/WatchNutritionQuickLogTests.swift:583`), `test/watch_nutrition_quick_log_test.dart:1338` — both assert the literal list | adding `rest` turns both red until each names it; that is the guard that makes a new wire kind deliberate. The twin's `all` has no `effort_rating`/`session_end` (V-5) and gains only `rest` | S-320 (wrist) |
| `WatchObservationKind.efforts` (`WatchRecords.swift:76`) | `WatchSensorSummaries.swift:277`, `WatchEffortRating.swift:162` | unchanged: it is the set D-221 reads, and a rest in it would move the effort debt and the sensor summary | S-334 (negative), D-221 |
| `stopTimer(kind:)` (Swift `:1569`, Dart `:1441`) | `WatchLoggingState.endRest` (Swift `:271`, Dart `:197`), `log`'s pre-entry stop (`:589`/`:629`), both stacks' screens | it now emits (D-211/D-220) and takes an optional instant (D-223); a second call on a stopped timer returns at the `guard` and emits nothing | S-332, S-320 (wrist) |
| `stopTimerFromMessage` (Swift `:752`, Dart `:768`) | `applyTimerState` (`:658`), `adoptTimers` (`:683`, Dart `:667`) | unchanged on purpose: no emission site (D-219), so a phone-sent stop is silent | S-333 |
| `transitionTo` (Swift `:1071`, Dart `_transitionTo` `:1148`) | `finishSession` (`:340`/`:341`), `abandonSession` (`:349`/`:347`), `replaySessionEnd` (`:1145`) | it now stops a running rest **before** the terminal row, and that stop emits (D-223); a replayed lifecycle frame re-emits nothing | S-322, S-331 |
| `appendObservation` (public Swift `:1167`, private `:1225`, Dart `:1236`/`:1288`) | `log`, `logNutrition` (`:1189`), `pendingObservations` (`:1346`/`:1358`), `pruneConfirmed` | the rest rides the existing store-then-emit path, so retry, ack and delivery-owed are unchanged; the public entry point calls `requireSession()` (`:1810`), which is why the finish-path stop runs while the session is still current | S-339, S-324 (wrist) |
| `storedObservations` (Swift) / `_observations` + `_emittedMessageIds` (Dart `:93`, `:1314`) | the store-check in `appendObservation`, the newest-routine-style scans | D-221's lookup reads the stored order (`sequence`); no writer changes it, and nothing new is stored for a rest that is not emitted | S-334, S-339 |
| `messageId(for:)` (Swift `:1776`, Dart `:1680`) + `appendTimer` (Swift `:1574`, Dart `:1474`) | the timer frame's own id, deliveries owed | D-224's derived `eventId` is what keeps the rest observation's id distinct from the `timer_state` frame of the same row | S-320 (wrist), S-332 |
| `computeSessionRestTimeMs` (`session_summary_service.dart:17`) | `session_summary_screen.dart` `_restTimeMs`, the summary tests; 18c's impact table row names it too | **no code change**: an imported rest is a closed `EntryRest` inside the session window, so it merges and sums like any other. Asserted, never edited | S-329 |
| `getEntryRests` readers (`workout_session_screen.dart:331`, `:678`, `:770`; `workout_session_list_view.dart:607`) | the session screen's rest pings (`workout_session_global_timer.dart:45,81`, which filter `restEndMs == null`), the closed-rest key lookup, the set-logged state at `:678` | no code change expected: an imported rest is **closed**, so it never pings; at `entryIndex + 1` it makes the watch-logged set read as logged, which is what the wrist showed. Asserted in Phase 2 | S-340 |
| The four docs that assert a wrist rest cannot travel (five claims) | `docs/watch_session_sync.md:588` (device-local rest bullet) and `:373-380` ("What does not sync"), `docs/rest_tracking.md:240-241`, `docs/watch-app-setup-and-qa.md:199-200`, `docs/state_management/watch_surface.md:290-292` and `:432-439` | each is stale the moment Phase 1 ships; Phase 2 narrows each to the ownership half (the *timer* stays device-local) and asserts the travel | S-341 |
| `docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/…plan.md` D-80 (`:83`), S-79 (`:348`), Open question 1 (`:855`) | a reader looking for why the wrist's rest was display-only | annotated per 18b D-165 (display half superseded; ownership half stands) | S-341 |
| `docs/plans/2026-10-08-18-watch-qa-index.md` (rows and the dependency bullet) | whoever picks up the next 18-series plan | gains the 18d row and completes 18c's placeholder; the order acquires "18c before 18d" | S-341 |

## Scenarios

Stable ids; numbering continues this series and is not reused. "Red without the change" = the thing named does not exist
or does not do this at the base commit. Every fixture is enumerated, including the adversarial populations. Scenarios
whose id carries "(18c)" are 18c's halves of a shared scenario and are not asserted here; the ids are restated because
both plans' tests name them.

### S-320 (wrist half): the happy path, emitted on the real engine
- **Fixture:** a live session `s1` with exactly one exercise instance `se1` (`exerciseId 'e1'`), no stored observations,
  no stored timers; an injected clock whose values are `T0`, `T0`, `T0+70s`.
- **Trigger:** log set A at `T0`; tap **Next** at `T0+70s`.
- **Flow:** `log()` appends set A (`entryId`/`eventId` `entry-1`, `sequence` 1) and `startFollowOnTimer` starts a rest;
  `endRest()` → `stopTimer(kind: rest)` appends the stopped row and emits.
- **Expected outcome:** exactly one new observation: `kind 'rest'`, `afterEntryId` = `entry-1`,
  `startedAt` = `T0`, `endedAt` = `T0+70s` (70 s apart), `sessionExerciseId` = `se1`, `exerciseId` = `'e1'`,
  `eventId` = `<rest row recordId>-rest` (D-224), `messageId` = `msg-<eventId>`; the store holds it and
  `pendingObservations` reports it exactly once. Identical in Swift and Dart.
- **Red:** `WatchObservationKind` has no `rest` and `stopTimer` emits nothing — and in the Dart twin
  `WatchObservationKind.all` is a five-kind list, so D-224's kind has to be added deliberately (V-6).
- **Edge case of:** none.

### S-321 (18c holds the phone half): a rest ended by the next set
- **Fixture:** session `s1` with `se1`/`'e1'`; clock `T0`, `T0`, `T0+45s`, `T0+45s`.
- **Trigger:** set A logged at `T0`; set B logged at `T0+45s` **without** Next.
- **Flow:** `log()`'s pre-entry stop (`WatchLoggingState.swift:589`) ends the rest at this log's instant, **before** B is
  appended; then B is appended and starts its own follow-on rest.
- **Expected outcome:** exactly one rest observation: `afterEntryId` = A's `entryId`, `startedAt` = `T0`,
  `endedAt` = `T0+45s` = B's `loggedAt`, not a second clock read; B's observation has a **higher** `sequence` than the
  rest's; R2's timer row exists (B's rest) but has no observation yet. Phone side: one `EntryRest` at index 1 and none at
  index 2 (18c, D-215).
- **Red:** the ending instant would come from a second clock read and the two frames would disagree.
- **Edge case of:** S-320.

### S-322 (18c needs it for the total): a rest running when the workout ends
- **Fixture:** session `s1`, set A logged at `T0`, rest running; clock `T0`, `T0`, `T0+30s`.
- **Trigger:** **End** (`finishSession`).
- **Expected outcome:** the rest is stopped at `T0+30s` and emitted with `endedAt` = `T0+30s`; the terminal session row
  is appended **after** it (so the session still carries `se1`'s rows); one rest observation,
  `afterEntryId` = A. A later `replaySessionEnd` adds nothing.
- **Red:** `transitionTo` stops no timer, so the rest runs on forever and nothing is emitted (V-1).
- **Edge case of:** S-331.

### S-323 (18c holds the phone half): zero length is never sent
- **Fixture:** session `s1` with `se1`, no stored observations; an injected clock returning the **same** value for the
  rest's start and its stop (`T0`), so `endedAt == startedAt`.
- **Trigger:** log A at `T0`; **Next** at `T0`.
- **Expected outcome:** the timer row is appended (stopped), and **no** observation is emitted: after the stop,
  `pendingObservations` contains no `rest`, the store gained no rest row, and the message id index has no entry for it.
  (`endedAt < startedAt` cannot come from a monotonic clock; the `==` case is the wrist's.) The phone additionally drops
  such a row if an older peer staged it (18c, D-222/S-323).
- **Red:** nothing guards the window today — the emission itself is new.
- **Edge case of:** S-320.

### S-324 (18c holds the phone half): one emission per rest
- **Fixture:** as S-320, after the first stop.
- **Trigger:** `stopTimer(kind: rest)` a second time (the same call the rest screen makes on a stale tap).
- **Expected outcome:** exactly one rest observation, one `eventId`, one stored row; the second call returns at the
  `guard` (`activeTimer` nil or the rest already `stopped`) and appends nothing; `pendingObservations` is unchanged.
  A re-delivery of that same `messageId` is the same event (D-212) and the phone writes one `EntryRest` (18c).
- **Red:** n/a for the emission, but this is the structural guard against a second emission.
- **Edge case of:** S-320.

### S-329: the totals (one fixture, both surfaces)
- **Fixture:** two sessions with the **same** window `[T0, T0+3600s]`:
  (i) **imported** — set A at `entryIndex 0` logged at `T0`, one imported `EntryRest` at `entryIndex 1` with
  `restStartMs = T0+10s`, `restEndMs = T0+80s` (written through 18c's importer);
  (ii) **phone-counted control** — the same set and one `EntryRest` at `entryIndex 1` with the same window, written by
  `TimerManager.recordRestStart`/`recordRestEnd` at `T0+10s`/`T0+80s`.
- **Trigger:** `computeSessionRestTimeMs(sessionId)` and the summary screen's Rest stat for each.
- **Expected outcome:** `70 000` for both (arithmetic: `80s − 10s = 70 s`, one interval, both ends inside the window, no
  merge with anything), and the summary's Rest stat renders the same for both. The imported rest adds no entry, no
  segment and no opened/closed rest elsewhere.
- **Red:** at 18d's base this is green (18c wrote the writer) — it is an acceptance test for the shipped surfaces. Its
  red proof is the commit 18c was built on (`prove-red <that ref> test test/watch_session_summary_integration_test.dart`,
  where the fixture's imported rest cannot be written); the implementer records the ref it used in the evidence file.
- **Edge case of:** none.

### S-331: the finish path ends a rest
- **Fixture:** session `s1`, set A at `T0`, rest running; clock `T0`, `T0`, `T0+30s`; a file-store snapshot taken before
  the End.
- **Trigger:** `finishSession`; then rebuild the engine from the file store.
- **Expected outcome:** the rest timer row is appended with `stoppedAt = T0+30s` (state `stopped`), the session's terminal
  row keeps `se1`'s rows, and the rebuilt engine reports **no** active rest (the restored state has no running rest) —
  the rest did not survive the workout. One rest observation, as S-322.
- **Red:** V-1 (nothing stops it).
- **Edge case of:** S-322.

### S-332: Next emits once; a second stop is silent
- **Fixture:** session `s1` with `se1`, set A at `T0`, rest running; clock `T0`, `T0`, `T0+70s`, `T0+70s`.
- **Trigger:** Next at `T0+70s`; then the same stop again.
- **Expected outcome:** exactly one observation, one `eventId`, one `messageId`, one store row; the second call emits
  nothing and the observation count is unchanged.
- **Red:** the emission is new; this is the structural guard for D-212's second half.
- **Edge case of:** S-320.

### S-333: a phone-sent stop emits nothing
- **Fixture:** session `s1` with set A logged **on the wrist** at `T0` (so an effort observation exists), plus a rest the
  wrist **adopted** from the phone: a `timer_state` snapshot at `T0+5s` naming the rest active; clock `T0`, `T0`, `T0+5s`,
  `T0+20s`.
- **Trigger:** the phone's snapshot delivering the stop at `T0+20s` (`stopTimerFromMessage`, Swift `:752`/Dart `:768`).
- **Expected outcome:** **zero** rest observations before and after the message; the timer row is appended with
  `stoppedAt = T0+20s`; `pendingObservations` has no `rest`. The phone's own `EntryRest` remains the only row for that
  spot (18c, D-216).
- **Red:** at the base nothing emits, so the red here is the inverse defect — this test is the structural guard that keeps
  a future `stopTimerFromMessage` from emitting (D-219).
- **Edge case of:** S-320.

### S-334: nothing to hang the rest on
- **Fixture:** session `s1`; **no** stored effort observation at all; a rest started by a route other than a logged entry
  — the phone's `timer_state` snapshot at `T0+5s` starts a rest (`applyTimerState`); clock `T0+5s`, `T0+5s`, `T0+40s`.
- **Trigger:** Next at `T0+40s`.
- **Expected outcome:** the rest is stopped and its timer row appended, but **no** observation is emitted (D-221 has no
  answer): `pendingObservations` has no `rest`, and no entry and no effort is invented. `WatchObservationKind.efforts`
  does not contain `rest` (negative assertion).
- **Red:** the emission is new; the guard is the "no answer → silent" branch of D-221.
- **Edge case of:** S-320.

### S-335: the two stacks agree
- **Fixture:** one scripted session driven through the same five steps with an injected clock in **both** engines
  (`WatchSessionEngine` and `lib/watch/session/watch_session_engine.dart`): log A at `T0`; log B at `T0+45s`;
  log C at `T0+60s`; **Next** at `T0+90s`; **End** at `T0+120s`.
- **Trigger:** the scripted run.
- **Expected outcome:** identical observation sequences. Arithmetic: A's log starts R1 at `T0`; B's log ends R1 at
  `T0+45s` (45 s, after A) and starts R2; C's log ends R2 at `T0+60s` (15 s, after B) and starts R3; Next ends R3 at
  `T0+90s` (30 s, after C); End finds no running rest, so **no** fourth rest. Three rests:
  `(T0 → T0+45s, after A)`, `(T0+45s → T0+60s, after B)`, `(T0+60s → T0+90s, after C)` — same kinds, same windows and
  same `afterEntryId`s in both stacks, and the same interleaving (`rest(R1) < B < rest(R2) < C < rest(R3)` by
  `sequence`).
- **Red:** no emission exists in either stack.
- **Edge case of:** S-320, S-321.

### S-336: an adopted rest the wrist ends still emits
- **Fixture:** session `s1` with set A logged **on the wrist** at `T0` (an effort observation exists); the phone sends a
  `timer_state` snapshot at `T0+10s` naming a rest active, started at `T0+8s`; clock `T0`, `T0`, `T0+10s`, `T0+40s`.
- **Trigger:** Next at `T0+40s`.
- **Expected outcome:** one rest observation, `afterEntryId` = A's `entryId` (D-221 is positional, so it does not care who
  started the rest), `startedAt` = `T0+8s` (the adopted row's own start), `endedAt` = `T0+40s`. The phone later drops it
  if it holds its own rest for that slot (18c, D-216) — the wrist still emits; that asymmetry is D-219's point.
- **Red:** the emission is new.
- **Edge case of:** S-320, S-333.

### S-339: the lookup survives a relaunch
- **Fixture:** the file-store path: log A at `T0` (rest starts); tear the engine down; rebuild a fresh engine over the
  **same** file store before the rest ends; clock `T0`, `T0`, `T0+40s`.
- **Trigger:** Next at `T0+40s` in the new process.
- **Expected outcome:** one rest observation with `afterEntryId` = A's `entryId` (read from the store, not from memory —
  D-221) and `startedAt` = `T0` (the persisted timer row's start), `endedAt` = `T0+40s`.
- **Red:** the emission is new; the guard is that the lookup is store-based.
- **Edge case of:** S-321.

### S-340: the phone shows and totals it where it shows any rest
- **Fixture:** a **Mock-first** phone (`MockWorkoutRepository`) holding session `s1` over `[T0, T0+3600s]`: set A at
  `entryIndex 0` logged at `T0`, one imported `EntryRest` at `entryIndex 1` with `restStartMs = T0+10s`,
  `restEndMs = T0+80s`; no other rest anywhere; the session is the most recent one.
- **Trigger:** open the session screen, then the summary screen, then return to the session list.
- **Flow:** `workout_session_screen._isSetLogged` (`:678`) asks for a rest at `entryIndex + 1`;
  `_scheduleActiveRestNotifications` (`:331`) and `WorkoutSessionGlobalTimer` (`:45`, `:81`) ask for the most recent
  **open** rest.
- **Expected outcome:** the Rest stat reads 1 m 10 s; the imported rest never pings and is not treated as open
  (`_getMostRecentOpenRestKey` finds none); set A reads as **logged**; the session renders in the list with no new widget
  and no crash.
- **Red:** the imported row cannot exist before 18c; this is the acceptance test for the shipped surfaces (same red proof
  as S-329).
- **Edge case of:** S-329.

### S-341: the docs stop claiming a wrist rest cannot travel
- **Fixture:** the repository after Phase 2, with the five claims at `docs/rest_tracking.md:240-241`,
  `docs/watch-app-setup-and-qa.md:199-200`, `docs/watch_session_sync.md:373-380` and `:588`,
  `docs/state_management/watch_surface.md:290-292` and `:432-439`.
- **Trigger:** the residue grep and the two contract tests.
- **Expected outcome:** (a) `rest_tracking.md` no longer says the wrist's rest does not reach the phone's history;
  (b) `watch-app-setup-and-qa.md` keeps the timer-ownership sentence and drops "never appears in the phone's history",
  and gains the device check (log a set on the wrist, rest, Next, look at the phone's session Rest stat);
  (c) `watch_session_sync.md`'s "What does not sync" and the device-local bullet read the same narrowed claim (the
  *timer* is device-local; a completed rest travels); (d) `watch_surface.md` says a **taken** rest travels while the
  **routine** still carries none, with the file no larger than it was (`test/docs_indexing_contract_test.dart` green and
  the net size change recorded in the evidence file); (e) 17a's D-80 (`:83`) carries 18b D-165's annotation and S-79
  (`:348`) is marked; (f) `docs/plans/2026-10-08-18-watch-qa-index.md` holds the 18c and 18d rows and the order
  "18c before 18d". Grep proof: `grep -rn "does not yet reach\|never travels to the phone\|never appears in the phone's history" docs/`
  returns historical plan files only (`docs/plans/…17a…`, `docs/plans/…18b…`), no live guide.
- **Red:** those claims are in the tree today and are false the moment Phase 1 ships.
- **Edge case of:** none.

## Iteration 1

Both phases land in **one PR** (the split was into plan 18d, not into two PRs): the wrist cannot emit into a phone that
has not shipped 18c, and the docs are false from the moment Phase 1 lands. Phase 1 must run with 18c merged
(`git log` should show 18c's commits on the branch).

### Phase 1: the wrist emits it — Swift, the Dart twin, and the finish-path stop (@developer)

1. [ ] Add the kind: `rest` to the Swift enum and to `all`, never to `efforts` — `WatchRecords.swift` ·
       `WatchObservationKind` (`:50-77`); update the guard that pins the set — `WatchNutritionQuickLogTests.swift` ·
       `testTheKindsTheWristCanEmitAreAClosedSet` (`:583`).
2. [ ] The same in the twin, with the twin's own `all` (no `effort_rating`/`session_end`, V-5), and add the missing
       `efforts` list beside it (= `set`, `timed`, `round`, `hold`, mirroring `WatchRecords.swift:76`) so item 6 has
       something to read — `lib/watch/session/watch_records.dart` · `WatchObservationKind` (`:58-68`); update
       `test/watch_nutrition_quick_log_test.dart` · `the kinds the wrist can emit are a closed set` (`:1338`).
3. [ ] Emit from the engine's rest stop, at that one site (D-211/D-219/D-220/D-224): after the stopped row is appended,
       when the stopped kind is `rest`, build the event from the row + `D-221`'s answer, with `eventId` =
       `<row.recordId>-rest`, and emit through the **private** appender — `WatchSessionEngine.swift` · `stopTimer(kind:)`
       (`:1569`, `appendTimer` `:1574`, private `appendObservation` `:1225`, `messageId(for:)` `:1776`). Twin:
       `lib/watch/session/watch_session_engine.dart` · `stopTimer` (`:1441`, `_appendTimer` `:1474`, `_appendObservation`
       `:1288`, `_messageIdFor` `:1680`).
4. [ ] Thread the ending instant (D-223): `stopTimer` gains an optional instant that defaults to the clock, `endRest()`
       passes it through, and `log()` passes the `loggedAt` it already computed so the pre-entry stop's window equals the
       frame's — `WatchLoggingState.swift` · `endRest` (`:271`) and `log(now:)` (`:589`); twin
       `lib/watch/logging/watch_logging_state.dart` · `endRest` (`:197`) and `log` (`:629`).
5. [ ] Add the finish-path stop (V-1, R-7): stop a running rest at the session's end instant **before** the terminal row
       is built (it copies `session.exercises`), capturing the session id first so the appender's `requireSession()`
       cannot fire — `WatchSessionEngine.swift` · `transitionTo` (`:1071`; callers `finishSession` `:340` /
       `abandonSession` `:349`; `replaySessionEnd` `:1145` must stay a silent replay). Twin:
       `watch_session_engine.dart` · `_transitionTo` (`:1148`, callers `:341`/`:347`).
6. [ ] Implement D-221's lookup once per stack, reading the store's `sequence` order and `WatchObservationKind.efforts`,
       returning nil when there is no preceding effort row (S-334) — `WatchSessionEngine.swift` · a private
       `restFollowOnEntryId(forRestRow:)` (reads `storedObservations`); twin `watch_session_engine.dart` ·
       `_restFollowOnEntryId` (reads `_observations`, `:93`).
7. [ ] Swift tests, red first (paste the failing names in `…-plan.evidence.md`, then green): S-320, S-322, S-332, S-333,
       S-334, S-336 in `WatchSessionEngineTests.swift`; S-321 in `WatchLoggingTimersTests.swift`; S-332/S-336 through the
       surface in `WatchRestSurfaceTests.swift`; S-331's post-rebuild state (no rest survives the workout, the count-up
       still holds) in `WatchRestIsCountUpTests.swift`; S-339 in `WatchFileStoreTests.swift`.
8. [ ] Dart tests, red first: S-320, S-322, S-332, S-333, S-334, S-336 in `test/watch_session_engine_test.dart`; S-322/
       S-331 in `test/watch_session_finish_test.dart`; S-332/S-336 through the surface in `test/watch_rest_surface_test.dart`;
       S-321 in `test/watch_logging_timers_test.dart`; the rest row + emission in
       `test/watch_session_rest_timer_append_test.dart`; S-335's scripted five-step fixture (three rests, the arithmetic
       in S-335) in `test/watch_reconciliation_cross_stack_test.dart`, with the same expectation asserted in Swift's
       `WatchSessionEngineTests.swift`.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (analyze stays at 196 pre-existing
notices, 0 errors) · `.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_finish_test.dart test/watch_rest_surface_test.dart test/watch_logging_timers_test.dart test/watch_session_rest_timer_append_test.dart test/watch_nutrition_quick_log_test.dart test/watch_reconciliation_cross_stack_test.dart`
(flutter baseline `+4181 ~1`; every file green, no skips) · `.github/copilot/scripts/macos/gateway.sh swift-test`
(baseline `376 / 0`; the new tests included, 0 failures) · red proof:
`.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_session_engine_test.dart -- lib/watch/session/watch_records.dart lib/watch/session/watch_session_engine.dart lib/watch/logging/watch_logging_state.dart`
fails at the base commit (the emission, the `rest` kind and `efforts` do not exist there) — record its output in the
evidence file (`prove-red` takes files, not directories). The Swift side has no `prove-red` gate in the gateway, so its
red proof is item 7's pasted failing-test list.

**Predicted Files** (nothing else):
`watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchRestSurfaceTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchRestIsCountUpTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionQuickLogTests.swift`,
`lib/watch/session/watch_records.dart`, `lib/watch/session/watch_session_engine.dart`,
`lib/watch/logging/watch_logging_state.dart`, `test/watch_session_engine_test.dart`,
`test/watch_session_finish_test.dart`, `test/watch_rest_surface_test.dart`, `test/watch_logging_timers_test.dart`,
`test/watch_session_rest_timer_append_test.dart`, `test/watch_nutrition_quick_log_test.dart`,
`test/watch_reconciliation_cross_stack_test.dart`, and this plan's `…-plan.evidence.md`.

### Phase 2: the totals, the views, and the docs (@developer)

1. [ ] S-329: assert the totals against both fixtures of the scenario (the imported row and the phone-counted control,
       both 70 s) — `test/watch_session_summary_integration_test.dart` · a new `computeSessionRestTimeMs` group
       (`lib/core/services/session_summary_service.dart` · `computeSessionRestTimeMs` stays unchanged; if it needs an
       edit, log it in the Assumption Log and stop).
2. [ ] S-340 (Mock-first, no Hive harness): an imported **closed** rest draws no overlay and never pings, and the
       watch-logged set reads as logged through the rest at `entryIndex + 1` — `test/unified_rest_overlay_test.dart`
       (the overlay) and `test/watch_rest_ping_test.dart` (the ping);
       `lib/features/workout/workout_session_screen.dart` · `_isSetLogged` (`:678`), `_scheduleActiveRestNotifications`
       (`:331`) and `lib/features/workout/workout_session_global_timer.dart` · `_getMostRecentOpenRestKey` (`:81`) stay
       unchanged.
3. [ ] `docs/watch_session_sync.md`: narrow "What does not sync" (`:373-380`) and the device-local rest bullet (`:588`) to
       the claim that survives — the **timer** is device-local, a completed rest travels as a `rest` observation — and
       name the two tests that prove it · replace text rather than appending a section, and record the before/after size in
       the evidence file (net must not grow).
4. [ ] `docs/state_management/watch_surface.md`: delete the "the wire has no key for it" half at `:290-292` and extend the
       second-surface paragraph (`:432-439`) by the one clause that a taken rest's end travels; the file sits in its 52 KB
       band, so the net size must not grow — if the net is positive, delete superseded countdown-era wording in the same
       edit and record the before/after size in the evidence file · `test/docs_indexing_contract_test.dart` stays green.
5. [ ] `docs/rest_tracking.md` · `## The Wrist's Rest` (`:228-241`): replace the "device-local, does not yet reach the
       phone's history" claim with the shipped path (rest → `rest` observation → 18c's importer → `EntryRest`), keeping
       18b's count-up rule text untouched.
6. [ ] `docs/watch-app-setup-and-qa.md` (`:194-201`): keep the timer-ownership sentence, drop "never appears in the
       phone's history", and add the QA step (log a set on the wrist, rest, Next, then read the phone's session Rest
       stat) · replace text, do not append a section, and record the before/after size in the evidence file (net must not
       grow).
7. [ ] Annotate the superseded design and index the pair: `docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/…plan.md` ·
       D-80 (`:83`), S-79 (`:348`) and Open question 1 (`:855`) annotated per 18b D-165 (display half superseded,
       ownership half stands); `docs/plans/2026-10-08-18-watch-qa-index.md` · the 18c row (complete the placeholder),
       a new 18d row, and the order bullet gains "18c before 18d".
8. [ ] S-341's residue sweep, pasted into `…-plan.evidence.md`: `grep -rn "does not yet reach\|never travels to the phone\|never appears in the phone's history" docs/`
       returns historical plan files only; `grep -rn "restSeconds\|restDurationMs\|restLengthMs" watch/sync_protocol/schemas lib/ watch/watchos/Sources/`
       returns nothing outside the routine's prescription fields; `test/rest_is_count_up_contract_test.dart` and
       `test/docs_indexing_contract_test.dart` green; the before/after size of the three banded docs, the suite counts and
       the `xcodebuild` note recorded.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` · `.github/copilot/scripts/macos/gateway.sh test test/watch_session_summary_integration_test.dart test/unified_rest_overlay_test.dart test/watch_rest_ping_test.dart test/rest_is_count_up_contract_test.dart test/docs_indexing_contract_test.dart test/watch_session_import_test.dart`
· **the full suite** `.github/copilot/scripts/macos/gateway.sh test` (flutter baseline `+4181 ~1`, 0 failures — this phase
ends the PR) · `.github/copilot/scripts/macos/gateway.sh swift-test` (`376 / 0` baseline plus Phase 1's additions) · the
governor runs `xcodebuild "OmniTrain Watch App"` for a watchOS simulator (no agent builds the watch app) · the two
`prove-red` rows for the acceptance tests: `.github/copilot/scripts/macos/gateway.sh prove-red <the commit 18c was built on> test test/watch_session_summary_integration_test.dart -- lib/watch/session/watch_records.dart lib/watch/session/watch_session_engine.dart lib/watch/logging/watch_logging_state.dart`
and the same for `test/unified_rest_overlay_test.dart`, both of which must fail there because 18c's writer — the `rest`
kind, its staging and the importer — is absent at that ref, so the fixture cannot even be built.

**Predicted Files** (nothing else): `test/watch_session_summary_integration_test.dart`,
`test/unified_rest_overlay_test.dart`, `test/watch_rest_ping_test.dart`, `docs/watch_session_sync.md`,
`docs/state_management/watch_surface.md`, `docs/rest_tracking.md`, `docs/watch-app-setup-and-qa.md`,
`docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/2026-10-06-17a-watch-auto-sync-pr1-plan.md`,
`docs/plans/2026-10-08-18-watch-qa-index.md`, and this plan's `…-plan.evidence.md`.

## Files Affected

- Swift wrist: `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`,
  `WatchSessionEngine.swift`, `WatchLoggingState.swift`.
- Swift tests: `watch/watchos/Tests/WatchSessionEngineTests/` — `WatchSessionEngineTests.swift`,
  `WatchLoggingTimersTests.swift`, `WatchRestSurfaceTests.swift`, `WatchRestIsCountUpTests.swift`,
  `WatchFileStoreTests.swift`, `WatchNutritionQuickLogTests.swift`.
- Dart twin: `lib/watch/session/watch_records.dart`, `lib/watch/session/watch_session_engine.dart`,
  `lib/watch/logging/watch_logging_state.dart`.
- Dart tests: `test/watch_session_engine_test.dart`, `test/watch_session_finish_test.dart`,
  `test/watch_rest_surface_test.dart`, `test/watch_logging_timers_test.dart`,
  `test/watch_session_rest_timer_append_test.dart`, `test/watch_nutrition_quick_log_test.dart`,
  `test/watch_reconciliation_cross_stack_test.dart`, `test/watch_session_summary_integration_test.dart`,
  `test/unified_rest_overlay_test.dart`, `test/watch_rest_ping_test.dart`.
- Docs: `docs/rest_tracking.md`, `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`,
  `docs/watch-app-setup-and-qa.md`, `docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/…plan.md`,
  `docs/plans/2026-10-08-18-watch-qa-index.md`.
- **Dependents that only read a touched surface** (no edit expected; named because the Impact Check named them):
  `lib/features/workout/workout_session_screen.dart`, `lib/features/workout/workout_session_global_timer.dart`,
  `lib/core/services/session_summary_service.dart`, `lib/state/workout/timer_manager.dart`,
  `watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift`,
  `watch/watchos/Sources/WatchSessionEngine/WatchSensorSummaries.swift`,
  `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift`.

## Notes

- **Phase dependency graph.** 18c (wire + phone) → Phase 1 (the wrist emits) → Phase 2 (totals, views, docs). Inside
  Phase 1, items 1–2 (the kind) precede 3 (the emission), 3 precedes 4–6, and 7–8 only make sense after 3–6. Phase 2's
  items 1–2 are assert-only and could run before Phase 1 on a hand-written fixture — cheaper as written, because they
  share Phase 1's fixtures. Re-ordering Phase 2's docs (items 3–7) ahead of Phase 1 would make the docs claim travel the
  build cannot do; do not.
- **Intermediate states.** After Phase 1 and before Phase 2 the code is right and four documents are wrong; that is why
  both phases are one PR. A wrist built from Phase 1 alone must not pair with a phone that lacks 18c: the inbox would
  never settle the row (`_isStageable`), so the wrist would keep re-offering the frame (18c's D-214 impact row).
- **A rest that is not emitted still ends.** S-323 and S-334 skip only the travel: `stopTimer` appends the stopped timer
  row either way, so the count-up screen's state and the NEXT set's follow-on behaviour are unchanged.
- **No repository, no schema, no model change.** The rest travels as a wire event the wrist already knows how to send and
  the phone already knows how to write (18c); `scripts/sqlite_schema.sql`/`scripts/sqlite_seed.sql` and
  `lib/data/models/models.dart` are untouched, so `test/db_seed_test.dart` is unaffected.
- **Scope (for `.github/copilot/pr-scope-budget.md`).** Two phases, one PR; the track touched is the watch client (Swift
  + the Dart twin); the phone app and the sync contract are **asserted**, not edited (18c edited them). Scenarios: 11
  asserted here, 4 restated as 18c's halves (S-320/S-323/S-324 phone sides, and S-321's phone write).
- **`xcodebuild` is the governor's.** No agent runs it; the plan's Done Criteria name it so the governor knows what is
  still owed before merge.
- **File-list supersets.** 18c's "Moved to plan 18d" list is a superset of what this plan edits in one direction and a
  subset in the other: it names `test/watch_rest_to_phone_view_test.dart` (a new file), which this plan does not create —
  the same guard runs in the two existing Mock-first files named in Phase 2's item 2 (A-6) — and it omits
  `WatchLoggingState.swift`, `WatchLoggingTimersTests.swift`, `test/watch_session_finish_test.dart`,
  `test/unified_rest_overlay_test.dart` and `test/watch_rest_ping_test.dart`, all of which this plan edits. Predicted
  Files is the binding list; 18c's list is a marker, not a contract.

## Progress

- [x] **Planner** — read the brief, 18c's trimmed plan and evidence, the seed, and the wrist/engine/phone sources;
      wrote this plan from 18c's moved Phase 1B and Phase 3. Baselines confirmed on read: flutter `+4181 ~1`,
      swift `376 / 0`, analyze `196 / 0`; `xcodebuild` governor-run.
- [x] **Phase 1** (@developer) — **Complete** (both halves). Items 1 and 3–7 (Swift) and items 2 and 8 (the Dart twin) are
      done; `swift-test` 389 executed / 0 failures, the ten Dart files green (`+232`, 0 failures), `lint` back at 196 / 0
      after removing the six imports this half's own change made redundant. Footprint: part A 9 files, plus fix round 1's
      contract and four Swift test files; part B 12 files, 1090 changed lines. Mutation tables (Swift M1/M4/M5/M7–M11
      killed, M2/M3/M6 survived; Dart M12–M16 killed), the `prove-red` verdict and every count: `…-plan.evidence.md`.
  - [x] Fix round 1 (part A) — the nine pre-existing reds were all legitimate expectation updates (the contract's
        `expectedEvents` and `receiptedEntryIds`, the forwarder's 7-frame list, S-237's ack list, S-163's entry count); no
        production defect. Contract: the three rest events with their windows, slots and `afterEntryId`s.
  - [x] Item 1 — `WatchObservationKind.rest` and `all`; `WatchNutritionQuickLogTests` names it. Guard: M7.
  - [x] Item 3 — the emission at the one rest-stop site, stored then emitted. Guard: M1.
  - [x] Item 4 — `stopTimer(kind:at:)`, `endRest(at:)`, `log` passes its own `loggedAt`. Guard: S-321.
  - [x] Item 5 — the finish-path stop, before the terminal row. Guard: S-322.
  - [x] Item 6 — `restFollowOnEntryId` over `storedObservations` × `efforts`. Guard: S-334 (M3 survived, see Feedback).
  - [x] Item 7 — 13 Swift tests green; the 8 pre-existing cases went red and fix round 1 closed them (`swift-test` 389
        executed, 0 failures; see Feedback).
  - [x] Item 2 (part B) — `WatchObservationKind.rest` joins the twin's own `all` (no `effort_rating`/`session_end`) and the
        twin gains the missing `efforts` list; `test/watch_nutrition_quick_log_test.dart`'s closed-set guard names both.
        Guard: M16.
  - [x] Item 8 (part B) — the Dart tests: S-320/S-322/S-332/S-333/S-334/S-336 in `test/watch_session_engine_test.dart`,
        S-322/S-331 in `test/watch_session_finish_test.dart`, S-332/S-336 through the surface in
        `test/watch_rest_surface_test.dart`, S-321 in `test/watch_logging_timers_test.dart`, the rest row + emission in
        `test/watch_session_rest_timer_append_test.dart`, S-335's five-step fixture in
        `test/watch_reconciliation_cross_stack_test.dart`. Ten files, `+232`, 0 failures; the three S-261 reds handed over
        by fix round 1 are closed by `_rowsExist`'s new `rest` branch. Guards: M12–M16.
  - [x] Part B's unplanned fix — `HiveWatchSessionStore._nextSequence` handed every row the same `sequence` (the `??=`
        cached the stored maximum and `highest + 1` never advanced it), so `_newestTimer` read a stale row after a
        relaunch; `++_lastSequence` with a `-1` sentinel fixes it. Outside Predicted Files; both test files that construct
        the store are in the green set. Guard: M15.
- [ ] **Phase 2** (@developer) — totals, views, docs: not started. Counts to paste: `lint`, the six targeted suites, the
      **full** suite, `swift-test`, the residue greps, the two doc sizes, the 18c-base `prove-red` row.

## Assumption Log

(Executors append: decision made, options considered, choice + why. The Conductor marks each RATIFIED — promoted to a
D-x — or REVERT with a remediation item.)

- **A-1 (planner) — transposed into plan 18d under the original ids (18c's A-6).** Options: renumber into 18d's sequence,
  or keep the ids and put the full text where the owning phases are. Chose the latter: 18c's phases still cite
  D-211/D-212/D-213/D-219/D-220/D-221 by number, and 18c's own markers point here; renumbering would make two live plans
  disagree about the same rule.
- **A-2 (planner) — what Phase 1 must add that 18c called out as absent.** V-1 is a divergence, not a decision: the
  finish path stops no timer at the base commit, and D-211 says the phase that finds that adds the stop. Pinned where
  and at which instant as D-223, and the id collision with the row's own `timer_state` frame as D-224, because both are
  choices two implementers could make differently with different wire output. Both are vetoable (Open questions 1).
- **A-3 (planner) — "the phone's rest rows" (18c criterion 4) means the summary stat plus the session screen's readers,
  not a new history widget.** Options: add a rest row widget to the history list, or assert the existing readers. Chose
  assert: no rest row exists in the history today (`workout_session_list_view.dart:607` is a comment, not a reader), and
  inventing a widget would grow this PR past its scope. S-340 asserts the stat, the overlay/ping silence and the
  logged-set state instead.
- **A-4 (planner) — the doc set is the five claims the grep found, plus the 18b D-165 annotations.** Options: the three
  docs the seeded Phase 3 named, or every doc carrying the stale claim. Chose the grep's answer —
  `rest_tracking.md:240-241` and `watch-app-setup-and-qa.md:199-200` repeat the claim outside the two seeded docs, and
  S-341's residue sweep is what proves they are all gone.
- **A-5 (planner) — S-329/S-340 are acceptance tests, not red-first tests.** 18c wrote the writer, so at 18d's base they
  are green. Their red proof is therefore a `prove-red` run against the commit 18c was built on, recorded in the evidence
  file; the implementer records the exact ref it used.
- **A-6 (planner) — the view guard reuses two existing Mock-first test files instead of 18c's named new file.** Options:
  create `test/watch_rest_to_phone_view_test.dart` as 18c's moved list says, or extend
  `test/unified_rest_overlay_test.dart` and `test/watch_rest_ping_test.dart`, which already pump a session screen and a
  repository with rests. Chose the existing files: fewer new harnesses, the same assertions (S-340). If the reviewer
  prefers 18c's name, that is a rename, not a behaviour change.
- **A-7 (planner) — the twin needs an `efforts` list, and both `prove-red` rows name files.** Two corrections from the
  final verification read: Dart has no `WatchObservationKind.efforts` (grep finds only a comment at
  `lib/watch/session/watch_records.dart:644`), so Phase 1 adds it beside `all`; and the gateway's `prove-red` takes
  source files after `--` (18a's review table, 18b's A-2), not a bare test path. Both are recorded in the evidence file.
- **A-8 (developer) — the finish-path stop is at `transitionTo`'s `now`, before `captureSessionEnd`.** D-223 leaves the
  instant to the caller; the terminal row must carry the latest instant, so the rest's `endedAt` cannot be later than it.
  Chosen: stop first, at the same `now`. Guarded by S-322.
- **A-9 (developer) — the rest row is stored before it is emitted, and a failed append is swallowed (`try?`).** Chosen to
  match `appendObservation`'s existing call sites: an emission that cannot reach the wire must not break the timer stop,
  and the stored row is what the next set's lookup reads (S-339).
- **A-10 (developer) — item 7's tests are split by surface, not by scenario.** The engine-facing half of S-332/S-336 sits
  in `WatchSessionEngineTests.swift`; the surface-facing half in `WatchRestSurfaceTests.swift`, beside S-163. Chosen so a
  reader finds a scenario's guard where its subject lives; the alternative (one new file per scenario) adds harnesses.
- **A-11 (developer) — S-322 asserts the *event* sequence, not the frame list.** `emittedKinds` filters to
  `observations_up` and flattens each frame's `events`, so `["set", "rest", "session_end"]` shows the rest sitting between
  the set it followed and the end that closed it, while the `timer_state` frame goes uncounted. Chosen over clearing the
  harness, which would have made the assertion order-blind. Guarded by M1 (removing the finish-path call).
- **A-12 (developer) — M2, M3 and M6 are recorded as surviving, not chased.** Each guards a state the wire validator or
  the emission order already makes unreachable, so the fixture cannot tell the mutant apart without a new adversarial
  fixture the plan does not name. Options were to invent one (unplanned scope) or record it (chosen; evidence file).
  Open item 3 asks the planner to decide.
- **A-13 (developer, fix round 1) — the shared contract gains the rest events, rather than the F-CAP tests being taught
  to expect them.** Options: edit the five Swift replay tests' expectations, or make
  `watch/contract/watch_capture_contract.json` carry the events the wrist now emits. Chose the contract: the F-CAP tests
  replay it, and the phone half reads the same file — the conformance test confirms the phone really receipts the three
  ids. Its `expectedEvents` and `receiptedEntryIds` gain `rec-13-rest`, `rec-15-rest`, `rec-17-rest`, and each case's
  `derivation` names them.
- **A-14 (developer, fix round 1) — all nine reds were expectation updates, so no production code moved.** Options:
  treat any of them as a defect (e.g. stop emitting the rest, or keep it out of `engine.entries`), or accept the new row
  as the intended output. Chose accept: D-210/D-211/D-219 make the rest a stored, emitted observation, and M9 shows the
  emission is exactly what the rest-stop contract needs. `WatchSessionEngine.swift` is byte-identical to what the run
  above left.
- **A-15 (developer, fix round 1) — the three Dart S-261 reds are handed to part B, not fixed here.** The contract change
  reaches `test/watch_session_import_test.dart`, whose `_rowsExist` helper has no `rest` branch (Dart scope, and the brief
  forbids it here). Part B adds the branch and renames the three tests, which now feed twelve envelopes in `full`.
- **A-16 (developer, part B) — the Hive store's append counter is fixed rather than the S-331 rebuild guard dropped.**
  `HiveWatchSessionStore._nextSequence` returned the same sequence for every row (`??=` cached the stored maximum and
  `highest + 1` never wrote it back), so a relaunch read a stale timer row and S-331's rebuild half was red for a reason
  the emission does not cause. Options: keep the rebuild guard but assert observation counts only (weaker — it would not
  catch a stale `_newestTimer`), or fix the counter (chosen). The file is outside Predicted Files and Dart-only — the
  Swift twin's `WatchFileStoreTests` S-339 is green — so it needs the governor's ratification; the two test files that
  construct the store are both in part B's green set, and nothing else reads the changed ordering.
- **A-17 (developer, part B) — `prove-red` cannot prove new Dart guards; the mutation table is part B's red proof.**
  Options: report the plan's `prove-red` invocation as the red proof (it returns GREEN AT, because it runs the base tree's
  copy of the test file), or mutate the five new behaviours (chosen). M12–M16, each restored exactly and re-run green, are
  the verdicts; the raw `GREEN AT` line is pasted in the evidence file with the reason.
- **A-18 (developer, part B) — S-322/S-331's Dart tests sit in `test/watch_session_finish_test.dart` over the in-memory
  store, not Hive.** Item 8 names that file, and the finish path is the engine's own state machine; the Hive relaunch
  shape (S-339's twin) is the engine file's `S-331` group, whose Hive harness is seeded in `setUp`. Chosen so no
  `testWidgets`/FakeAsync hazard enters the finish file and the two aspects stay separately guarded.
- **A-19 (developer, part B) — the six `wire_timestamps.dart` imports this half made redundant were removed.** Adding the
  `watch_records.dart` import to six test files made the direct import unnecessary (the record file exports
  `utcIso`/`parseUtcIso`/`parseOptionalUtcIso`), which took `lint` from 196 to 202. Options: leave the notices and explain
  them, or remove the imports (chosen: the phase's Done Criteria hold analyze at 196). No test's behaviour changed — the
  ten-file run is `+232` before and after.
- **A-20 (developer, part B) — S-163's `engine.entries` expectation moved 3 → 5 in `test/watch_rest_surface_test.dart`.**
  Options: leave it red (it is an existing guard) or match part A's identical Swift change, which already carries the
  reason "three sets, plus the two rests their logs ended (D-219)". Chose match: `entries` projects every stored
  observation in both stacks, so the Dart twin must read the same. Ratified by A-14; not a weakened guard.
- **A-21 (developer, part B) — the Dart implementation was written before its tests, so the red evidence is mutation-based.**
  The implementer rule is to write tests early; this half was implemented first (the emission is the twin of part A's,
  which the plan spells out at code level) and the guards were then proved by M12–M16 rather than by a working-tree red
  run. Recorded so the reviewer weighs the evidence as it is: killed mutants, not a red-then-green transcript.

## Feedback

**Phase 1, Swift half — Blocked (scope).** *(Superseded by fix round 1 below: the eight reds were legitimate expectation
updates and are closed; the contract change moved the red to Dart.)* One cause, one class of reader: the rest observation
is now a stored row and a
sent frame, so every fixture that *enumerates* a session's observations, entries or emitted frames sees one more of them.
Eight pre-existing tests in five files went red; three of those files are outside Predicted Files. Only one was predicted
(`WatchEmitForwarderTests`). `swift-test` 389 executed, 120 assertions failing across those 8 cases:

- `WatchCaptureContractTests` — 5 F-CAP replay tests: the event list gains `rec-13-rest`, `rec-15-rest`, `rec-17-rest`,
  every later index is then compared with the wrong contract event, and prompt-off counts 11 events, not 8. Reproduced in
  isolation: `swift-test --filter WatchCaptureContractTests` → `Executed 5 tests, with 112 failures`.
- `WatchEmitForwarderTests.testTheEnginesEmissionsReachTheSinkInOrder` — 7 frames, not 6; frame 5 is the new
  `observations_up` (the predicted red).
- `WatchSensorRecordingTests.testS237TheLogIsReleasedOnlyOnceTheSessionEndIsAcknowledged` — its ack list never names the
  rest ids, so no reading is released (`"0" != "20"`). Reproduced in isolation:
  `swift-test --filter WatchSensorRecordingTests` → `Executed 38 tests, with 2 failures`.
- `WatchRestSurfaceTests.testS163LoggingEndsARunningRestFirst` — `engine.entries` counts the two stopped rest rows beside
  the three sets (`"5" != "3"` at `:127`); deterministic.

All eight are deterministic; none is an ordering artefact of the full suite.

Readers the Existing-Functionality Impact table does not list: `engine.entries` (`WatchSessionEngine.swift:199`), the
snapshot's `"entries"` (`:248`), and `WatchLoggingState.observations` (`:347`, whose `sessionExerciseId` filter a rest
matches because it copies the field). Not edited: other features' tests, and the plan did not predict them.

**Fix round 1 (part A) — the eight Swift reds are closed; the contract change moved the red to Dart.** All eight were
legitimate expectation updates (the contract's `expectedEvents`/`receiptedEntryIds`, the forwarder's 7-frame list, S-237's
ack list, S-163's entry count) and no production code moved; `swift-test` is 389 / 0. Because the contract now carries
the three rest events, `test/watch_session_import_test.dart`'s three S-261 tests go red — the full suite is
`+4202 ~1 -3` against the `+4205 ~1` baseline — and the cause is that test's own `_rowsExist` helper, which has no `rest`
branch. Dart is part B's; `…-plan.evidence.md` has the diagnosis and the minimal fix.

**Part B — the Dart half is Complete; fix round 1's three Dart reds are closed.** `_rowsExist` gained the `rest` branch
(the effort's `EntryRest` at `entryIndex` = the index of `afterEventId`'s set among the set entries, its window compared
with `startedAt`/`endedAt`) and the three S-261 names now say "twelve envelopes", which is what `full` feeds. The ten files
the brief names are green: `+232`, 0 failures. Three readers outside the run's own files could have moved and did not:
`test/live_mirroring_test.dart`, `test/watch_logging_surfaces_test.dart`, `test/sync_protocol_fixtures_test.dart` →
`+181`, 0 failures. `lint` 196 / 0, `swift-test` 389 / 0. One unplanned, required change outside Predicted Files:
`HiveWatchSessionStore._nextSequence` gave every row the same `sequence`, so the planned S-331 rebuild guard was red for a
reason the emission does not cause (A-16; guard M15).

Open items for the planner (max 5 lines):

1. Add the four reader rows above to Existing-Functionality Impact, and the five red test files to Predicted Files.
2. Decide whether a rest belongs in `engine.entries` at all — S-163 and the F-CAP replays read it as the wrist's *entry*
   list, so a rest row there may be a design answer, not a test that needs updating.
3. Decide the three surviving mutants: M2 (zero-length rest — the validator already rejects it), M3 (no after-entry), M6
   (an entry that lands mid-rest). Each needs either a fixture the plan names or an explicit "defence in depth, untestable
   here" note in the plan.
4. `prove-red HEAD swift-test` cannot prove Swift guards (the new enum member is absent at HEAD → compile error). The plan
   should name the mutation route as the Swift proof, as this run did.
5. **Done in part B.** The three S-261 reds are closed: a `rest` branch in `test/watch_session_import_test.dart`'s
   `_rowsExist` (the row is `getEntryRests(effortId)` at the index of `afterEntryId` among the set entries) and the three
   test names' envelope count, which is twelve in `full`, not nine.
6. **Ratify or revert A-16:** `HiveWatchSessionStore._nextSequence` had to be fixed for the planned S-331 rebuild guard to
   pass; the file is outside Predicted Files, so it needs the governor's decision (and a Predicted Files row if kept).
7. **`prove-red` cannot prove new Dart guards** (it runs the base tree's copy of the test file): the plan's Phase 1
   red-proof row should name the mutation route for Dart as it already does for Swift.

## Open questions

Nobody can answer during this run, so each carries the default this plan proceeds on.

1. **D-211…D-213 and D-219…D-221 now live in plan 18d in full, under their original ids** (18c keeps markers). Default:
   proceed. If the governor prefers the text in 18c, it is a move, not a rewrite — the ids must not change.
2. **D-223 (the three stop sites and their instants) and D-224 (the `eventId` derivation, `<row.recordId>-rest`) are
   planner additions**, not seeded. They pin what R-7/V-1 leaves open. Default: adopt them. Vetoing D-224 would let the
   rest observation share the `timer_state` frame's `messageId`, which can suppress its delivery.
3. **The wrist's rest does not update an already-open live phone screen** (18c's writer is repository-only for a session
   the phone holds; D-167(d) names `createEntryRest` as the only writer). Default: out of scope; S-340 loads the session
   and asserts the surfaces. If live liveness is wanted, it is a separate plan, not a phase here.
4. **No new phone widget and no rest row in the history list** (A-3). Default: as written.
5. **The doc set includes `docs/rest_tracking.md` and `docs/watch-app-setup-and-qa.md`** beyond the two docs the seeded
   Phase 3 named (A-4). Default: as written; S-341's grep is the guard.
6. **Both phases ship in one PR**, and Phase 1 requires 18c merged. Default: as written. A split that merges Phase 1
   alone would leave four documents false.
