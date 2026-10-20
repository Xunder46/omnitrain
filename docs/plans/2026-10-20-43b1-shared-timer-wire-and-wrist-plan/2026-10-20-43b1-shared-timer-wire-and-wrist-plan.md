# Feature: 43b1 — a running timer says which exercise it belongs to (wire) and the wrist honours it

> Status: BUILT, PROVED, docs written, review pending (P1–P4 done 2026-10-20; mutations killed; evidence in the sibling `.evidence.md`). First of three (43b1 wire + wrist, 43b2 phone receives, 43b3 phone sends); 43b2 and 43b3 need this one. Series outline: `docs/plans/2026-10-19-43-shared-running-timer-plan/`.
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base: e6ff75b0 plus uncommitted plans 41, 42a, 42b, 43a (and another session's plan 44 in the same tree: touch nothing of it). Team: the crew. Architect step skipped (seed carries decisions, scenarios, phases; the lead validates).
> Scout sheets: `.work/crew/2026-10-20-43b-shared-timer/scout-wire.md`, `scout-phone.md` (quotes below read from them).

## Goal and acceptance

Nothing the user sees changes yet. This PR makes the timer on the wire able to say which exercise it is for, and makes the wrist keep and respect that. It is the base the next two PRs use so that a timer started on one device can run on the other for the right exercise.

What the wrist does after this PR: a work timer it starts (cardio interval, hold, round) carries the exercise it was started on; a timer it receives for another exercise does not show as running on the current exercise's logging screen; and when a timer for the same exercise arrives with an EARLIER start than the one the wrist is running, the wrist adopts the earlier start (owner rule: the earlier start wins). Rests are unchanged.

## Owner decisions (2026-10-19, in chat; recorded in the series outline)

- O-1 a timer belongs to the interval where it started (the exercise the starting device was on). O-2 pause pauses both. O-3 the earlier start wins.

## Decision Ledger

- D-1 Contract: `watch/sync_protocol/schemas/envelope.schema.json` `$defs.timer` (`required: kind, state, startedAt`, `additionalProperties: false`, ~:358) gains ONE optional property `sessionExerciseId` (`{"type": "string", "minLength": 1}`); nothing else, no required field, no version change. Both validators apply `additionalProperties: false` from the schema (`SyncProtocolValidator.swift:749`, `message_validator.dart:874`), so the schema edit is what admits the field: the builder confirms they read the schema file and not a hard-coded list; if one does hard-code, change it in the same phase. `timer_state.schema.json` already refers to `$defs.timers`. Rest timers never carry it (D-6). The id is the exercise slot's `sessionExerciseId` (on the phone a slot id equals its effort id).
- D-2 Wrist engine (Swift `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift` `WatchTimerRecord` ~:416, `toTimerJson` ~:476; `WatchSessionEngine.swift` `startTimer` ~:1528, `appendTimer` ~:1677, `adoptTimer` ~:723, `newestTimer` ~:1698): `WatchTimerRecord` gains `sessionExerciseId: String?` (init default nil, `withSequence`, `timerRowFrom`, JSON in/out, store round trip, `toTimerJson` emits it only when set). `startTimer(_ kind, plannedDurationMs:, sessionExerciseId: String? = nil)`; `WatchLoggingState.startWork()` (~:426) passes the current slot's id (`engine.currentExercise?["sessionExerciseId"]`) for the work kinds; the rest start (`startFollowOnTimer`, ~:1000) passes none. Stop rows keep the started row's slot (`timerRowFrom`).
- D-3 (narrowed in P2, 2026-10-20) The wrist hides a timer for another exercise only when that timer CAME FROM A MESSAGE (the phone's; `WatchSessionEngine.isTimerFromMessage`, rows filed under the `tms-` record id prefix): `WatchLoggingState.workTimer` (~:388) returns nil for a message timer whose `sessionExerciseId` is non-nil and differs from the current slot. A timer the wrist started itself keeps running across an exercise jump (existing S-1403 pins that), and a message timer with no slot behaves as today. Known limit: the wire holds one timer per kind, so a newer timer of the same kind for another slot supersedes the wrist's own row in `newestTimer`.
- D-4 (narrowed in P2) Earlier start wins at adoption, WORK KINDS ONLY (`round`, `hold`, `elapsed`; a `rest` is exempt: the phone's newer rest still supersedes the wrist's own, existing S-336): in `adoptTimer` (messages only), when the wrist already holds a NOT-stopped timer of the same kind AND the same `sessionExerciseId` (both nil counts as same) whose `startedAt` is EARLIER than the incoming timer's, ignore an incoming `running`/`paused` row (store nothing); equal or later-held start replaces as today; an incoming `stopped` row always applies; a timer for a different slot is stored beside. Assumption for 43b3: the phone sends the clear of a finished interval before the next interval's start.
- D-5 Dart twin: `lib/watch/session/watch_records.dart` `WatchTimerRecord` (~:402) and `lib/watch/session/watch_session_engine.dart` (`startTimer` ~:1402, `_adoptTimer` ~:737, `_timerRowFrom`, `_senderWroteTimer` ~:733) get the same field, stamping, and the D-4 rule (work kinds only, rest exempt) so the debug twin behaves as the Swift wrist. `lib/watch/logging/watch_logging_state.dart` has no work-clock API (scout): no D-3 twin there. NO reconciliation fixture: the shared `SessionReconciler` (`lib/core/sync_protocol/session_reconciler.dart:135-144`) is the phone mirror's last-write-per-kind fold and stays so; the earlier-start rule on the phone is 43b2's `TimerManager` rule, not the mirror's.
- D-6 `PROTOCOL.md` "Timer state" (~:244) gets the amendment: a timer MAY name the exercise slot it is for (`sessionExerciseId`); a work timer (`round`, `hold`, `elapsed`) a device starts names the slot it was started on; a rest names none; a receiver keeps a timer for another slot and shows it only for that slot; the earlier start wins. Amendment-log row in the file's existing style (date 2026-10-20, additive, no version change).

## Code pointers (current text)

`$defs.timer` ~:358: `"required": ["kind", "state", "startedAt"], "additionalProperties": false, "properties": { "kind": {...}, "state": {...}, "startedAt": {...}, "pausedAt": {...}, "stoppedAt": {...}, "accumulatedPauseMs": {...}, "plannedDurationMs": {...} }`.
`WatchSessionEngine.startTimer(_ kind: String, plannedDurationMs: Int? = nil)` builds `WatchTimerRecord(recordId: newId(), sessionId: requireSession().sessionId, recordedAt: now, kind: kind, startedAt: now, plannedDurationMs: plannedDurationMs)` then `appendTimer`.
`adoptTimer` (~:723-743) builds the record from `timer["kind"]`, `startedAt`, `pausedAt`, `stoppedAt`, `accumulatedPauseMs`, `plannedDurationMs` only.
`WatchLoggingState.startWork()`: `guard canLog, isTimedWork, let kind = workTimerKind, !isWorkRunning else { return }`, then `engine.startTimer(kind, plannedDurationMs: kind == WatchTimerKind.round ? plannedRoundMs : nil)`; `workTimer` is `guard canLog, let kind = workTimerKind, let timer = engine.timerFor(kind), timer.state != WatchTimerState.stopped else { return nil }`.
Fixtures carrying timers (scout Q4): `watch/sync_protocol/fixtures/valid/timer_state.json` (all four kinds at once) and the snapshot/reconciliation fixtures listed there; readers of whole timer payloads: `test/sync_protocol_fixtures_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`, `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolFixturesTests.swift`, `WatchLoggingTimersTests.swift`. Because the new field is optional and added only to NEW fixtures, no existing fixture changes (grep to confirm before writing).

## Core scenarios (ids checked unused: `grep -rE "S-60[0-9]{2}"` returns nothing)

- S-6001 (contract, both stacks) a `timer_state` whose `elapsed` timer carries `sessionExerciseId: "sl-run"` validates; one with `sessionExerciseId: ""` and one with a number are refused; an unknown extra field is still refused. New fixtures `valid/timer_state_with_slot.json`, `invalid/timer_state_slot_empty.json` (manifest entries; `test/sync_protocol_fixtures_test.dart` and `SyncProtocolFixturesTests.swift` read the manifest). Fails without: the schema refuses the field.
- S-6002 (Swift) `WatchLoggingState.startWork()` on a timed slot `sx-run` emits a `timer_state` whose `elapsed` timer names `sessionExerciseId == "sx-run"`; on a hold slot kind `hold`, on a round slot kind `round` (with its planned length); a rest started by the log carries none. Fails without: no slot on the frame.
- S-6003 (Swift) the timer record survives the store round trip (append, relaunch, restore) with its slot, and a record written WITHOUT the field restores with nil (older build).
- S-6004 (Swift) a phone `timer_state` for slot `sx-other` while the wrist is on `sx-run`: `workTimer` is nil and `isWorkRunning` false; after `engine` moves to `sx-other` it is the running timer. A phone timer with NO slot behaves as today (shown for the current slot).
- S-6005 (Swift) the wrist runs `elapsed` for `sx-run` started at T+10 s; a phone `timer_state` for `sx-run` with `startedAt` T (earlier) arrives: the wrist now reports `startedAt == T`; the same with `startedAt` T+20 s (later): the wrist keeps T+10 s and stores nothing; a `stopped` row from the phone with a later start still stops it. Fails without: last write wins.
- S-6006 (Dart twin) the same S-6003 round trip and S-6005 behaviours (work kinds earlier start wins, rest exempt, stopped always applies, another slot stored) in `lib/watch/session/watch_session_engine.dart`, and the engine's `startTimer(kind, sessionExerciseId: ...)` frame carries the slot and validates (`test/watch_logging_timers_test.dart`, `test/watch_session_engine_test.dart`).

## Phases (serial; the lead verifies after each; no builder runs the full suite)

- P1 `crew-builder-watch` — D-1 and S-6001: schema, the two fixtures + manifest, validator check. Scope: `watch/sync_protocol/schemas/envelope.schema.json`, `watch/sync_protocol/fixtures/**`, `test/sync_protocol_fixtures_test.dart`, `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolFixturesTests.swift`, and the two validators only if D-1 shows a hard-coded list.
- P2 `crew-builder-watch` — D-2, D-3, D-4 Swift with S-6002..S-6005 (tests first). Scope: `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift`, `WatchSessionEngine.swift`, `WatchLoggingState.swift`, `WatchLoggingModel.swift` only if needed, `watch/watchos/Tests/WatchSessionEngineTests/WatchTimedWorkTests.swift`, `WatchLoggingTimersTests.swift`. Names in sources avoid the append-only guard's verbs; Done list runs `swift-test --filter WatchSessionEngineTests` and the whole package.
- P3 `crew-builder-watch` — D-5 Dart twin with S-6006. Scope: `lib/watch/session/watch_records.dart`, `lib/watch/session/watch_session_engine.dart`, `test/watch_session_engine_test.dart`, `test/watch_logging_timers_test.dart`.
- P4 `crew-builder-watch` (docs only: PROTOCOL.md is outside the docs keeper's ceiling) `watch/sync_protocol/PROTOCOL.md` D-6, then `crew-docs-keeper` for `docs/state_management/watch_surface.md`, `docs/watch_session_capture.md`, plan evidence. NOT `docs/watch_session_sync.md` (at the size band).
- Then the lead's mutations (slot not stamped, slot hidden check, earlier-start comparison, stop-always-applies), `crew-reviewer`, `xcodebuild` of the watch app target, full `flutter test` and `swift test`.

Size: about 60 Swift + 30 Dart production lines, about 350 test lines, 4 phases, tracks: contract + wrist (a contract change rides with its first consumer): inside the budget.

## Owner checks (owner)

- (owner) None visible yet; the next PRs make it visible. Safe to ship alone: older phones send timers without a slot and the wrist treats them as before.

## Progress

| Phase | What | Result |
|---|---|---|
| P1 | D-1 contract: `$defs.timer` gains optional `sessionExerciseId`; fixtures `valid/timer_state_with_slot.json`, `invalid/timer_state_slot_empty.json`, `invalid/timer_state_slot_number.json`, `invalid/timer_state_slot_unknown_field.json` + manifest; both validators schema-driven, no validator change | done (S-6001 green) |
| P2 | D-2, D-3, D-4 Swift with S-6002..S-6005 (tests first); fix 1: D-3/D-4 narrowed; fix 2: the three existing tests that turned red | done (green; mutations killed) |
| P3 | D-5 Dart twin with S-6006; fix 3: the twin's tests | done (green; mutations killed) |
| P4 | D-6 PROTOCOL.md amendment; docs keeper: `docs/state_management/watch_surface.md`, plan evidence | done (`docs/watch_session_capture.md` checked: no timer content, no update required) |

## Assumption Log

- A-1 The wrist's pause/resume exist in the engine but have no wrist UI (scout Q2): "pause pauses both" therefore means the phone's pause reaches the wrist (43b3) and the wrist shows it paused; no wrist pause control is added.
- A-2 Only `sessionExerciseId` is added, not an interval index: a wrist-started timer is adopted by the phone's first unfinished interval of that exercise (consistent with 43a's fill rule); a phone-started timer on another interval is matched at finish time by its start (43c).
