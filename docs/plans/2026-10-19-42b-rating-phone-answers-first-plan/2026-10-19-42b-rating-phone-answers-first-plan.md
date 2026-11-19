# Feature: 42b — the phone answers the effort question first: the watch's question closes and cannot be answered late

> Status: BUILT, PROVED, docs written, review pending (2026-10-19).
> Next handoff: P1 (`crew-builder-watch`, tests first)
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base commit: e6ff75b0 + 42a. Team: the crew. Split by the scope guard from the original 5-phase, two-track seed; the phone half is `docs/plans/2026-10-19-42a-rating-wrist-answers-first-plan/`.
> Scout sheets: `.work/crew/2026-10-19-42-rating-first-answer-wins/scout-phone.md`, `scout-wire.md`.

## Goal and acceptance

A workout finished on the watch asks the effort question on both devices. When the PHONE is answered first, the watch's question closes by itself within moments and can no longer be answered; the first answer stands everywhere.

| What the user does | Now | After 42b |
|---|---|---|
| Finishes on the watch, answers on the phone first | the watch's question stays open; its late answer is ignored by the phone but shows on the watch | the watch's question closes by itself; nothing to answer |
| Phone answered while the watch is out of reach | same | the watch's question closes as soon as the phone can reach it (the frame is re-offered at the next phone notification) |
| Finishes on the phone | only the phone asks | unchanged |

## Decision Ledger

- D-1 NO wire or schema change. The phone tells the wrist with a `session_snapshot` whose `entries` carry one `effort_rating` entry with `entryId` = `eventId` = `rating-<sessionId>` (the wrist's own id, `WatchSessionCapture.effortRatingId`, `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift:88-91`), `rating` 1..5 and `loggedAt`. Evidence: both validators already accept `effort_rating` in a snapshot (`SyncProtocolValidator.swift:66-72,85`; `lib/core/sync_protocol/message_validator.dart:122-143`); the schema has no origin rule on `entryId` (`watch/sync_protocol/schemas/envelope.schema.json:197-215`); the wrist stores a snapshot entry under its own `entryId` as the observation `recordId` (`WatchSessionEngine.storeSnapshotEntry` ~806-830), which is exactly what `hasEffortRating` looks up (`WatchSessionEngine.swift:1468-1493`); `applySnapshot` applies at any status of the same session (~492-515).
- D-2 The wrist closes by itself with no Swift logic change expected: `WatchEffortRatingState.owedSessionIds` filters out sessions where `engine.hasEffortRating` (`WatchEffortRating.swift:186-190`), `confirm()` returns nil when nothing is owed (`:262-275`), and `recordEffortRating` refuses when `rating-<sessionId>` is known (`WatchSessionEngine.swift:1476-1491`). P1 PROVES this with tests and fixes only what they show missing (most likely: `WatchEffortRatingState.objectWillChange` is not sent when a snapshot lands, so an open prompt would not redraw; see S-4310). More than about 15 changed Swift lines means it is a separate plan.
- D-3 Phone → wrist send, in `WatchSessionAutoPush` (`lib/state/watch/watch_session_auto_push.dart`). Its listener stays bound after the end (`_onChanged` ~427-439) but `_pushOnce` returns right after `_announceEnd` (~286-288) and composes nothing for an ended session (`projectSession` needs `hasActiveSession`, `watch_session_adoption_bridge.dart:233`). A NEW step runs BEFORE that return: when `target.currentSession` is ended (`endedAtMs != null`) with `sessionFeeling != null`, the mirror holds that same session id, and the mirror's `entries` hold no `effort_rating` entry, send the mirror's converged state plus the one rating entry through a NEW `LiveSessionMirrorState.sendRatingFor(sessionId, rating)` (`lib/state/watch/live_session_mirror_state.dart`, building on `sendState` ~350 and `snapshotEnvelope` ~319). Remembered per session id once DELIVERED (`WatchDelivery.delivered`); an undelivered frame is offered again at the next notification. Never sent when the mirror already holds a rating entry: that is the wrist's own answer (the mirror folds `effort_rating` as a session-scoped kind, `sessionScopedKinds` ~151), so the wrist's answer is never echoed back.
- D-4 Limits, stated not fixed: (a) both answered inside the radio latency window: the phone's number stands (D-138); (b) a phone-ended session whose wrist copy is still held also receives the entry; the wrist asks nothing for it, so it is harmless (S-4311 checks it is not sent back up as a new rating).
- D-5 `watch/sync_protocol/PROTOCOL.md` amendment (docs phase; the file is ~80 KB and not under the 64 KiB docs cap: add lines, do not restate): the phone may carry the session's `effort_rating` entry, id `rating-<sessionId>`, in a snapshot; authority rule 4 is why the phone's number is final.

## Code pointers (current text)

`watch_session_auto_push.dart:286-288`: `final ended = await _announceEnd(composedId);` then `if (composed == null || composedId == null) return;` — the new step goes before the `return`.

`WatchEffortRating.swift:186-190`:
```swift
    public var owedSessionIds: [String] {
        prompts
            .filter { !engine.hasEffortRating($0.sessionId) }
            .sorted { $0.sequence > $1.sequence }
            .map(\.sessionId)
    }
```
`WatchSessionEngine.swift:1476-1491`: `recordEffortRating` computes `let id = WatchSessionCapture.effortRatingId(sessionId)`, `guard !knowsObservation(id) else { return nil }`, then `appendObservation([... "entryId": id, "eventId": id, "kind": WatchObservationKind.effortRating, "loggedAt": ..., "rating": rating], sessionId:)`; `knowsObservation` is `acknowledgedObservationIds.contains(recordId) || storedObservations.contains { $0.recordId == recordId }` (`:1489-1493`).

## Core scenarios (ids checked unused: `grep -rE "S-43[0-9]{2}"` returns nothing; 42a uses S-4301..S-4305)

Harness: `test/watch_session_auto_push_test.dart` (S-85/S-87 harness) for the push; Swift tests in `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift`.

- S-4306 The wrist ended `s-w1`; the phone ended its copy and the mirror holds `s-w1` as completed with no rating entry. The user answers 3 on the phone's sheet. Expect exactly one `session_snapshot` sent whose `entries` contain `{kind: 'effort_rating', entryId: 'rating-s-w1', eventId: 'rating-s-w1', rating: 3, loggedAt: <iso>}`, and the envelope passes the Dart validator (`message_validator.dart`). Fails without: nothing is sent.
- S-4307 After S-4306 another notification sends nothing more; and a mirror that already holds the wrist's `effort_rating` entry (the wrist answered first) sends nothing even when the phone's row is also rated. Fails without: one rating frame per notification, or an echo of the wrist's own answer.
- S-4308 The first send answers not-delivered: the next notification sends again; once delivered, it stops. Fails without: a lost frame is never re-offered.
- S-4309 Negatives: a session still ACTIVE with a rating, and an ended session with NO rating, send no rating frame; a mirror holding a different session id than the phone's current session sends none. Fails without: a missing guard sends a frame for a session the wrist is not asking about.
- S-4310 (Swift) The wrist owes the prompt for `s1` (End with one effort entry, preferences ask). A `session_snapshot` for `s1` carrying an `effort_rating` entry `rating-s1` rating 3 is applied. Expect `isPromptOwed == false`, `owedSessionIds` empty, `canConfirm == false`, `try await confirm()` returns nil and appends nothing, and `objectWillChange` fired so the open prompt redraws. Fails without: a state that does not publish on a snapshot leaves the prompt on screen (fix only what this test shows).
- S-4311 (Swift) The same entry is NOT uploaded back: after S-4310 the pending-upload list holds no new unacknowledged `rating-s1` observation; if it does, the phone's `_topUpRating` ignores it (the row keeps the phone's number). The builder reports which and pins it.

## Readers of what this seed touches

- Whole-payload comparisons of snapshots (none should change: the new frame is a new send): `test/watch_session_auto_push_test.dart`, `test/live_mirroring_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_capture_contract_conformance_test.dart`.
- Swift: `WatchEffortRatingTests.swift`, `WatchSessionEngineTests.swift`, `WatchCaptureContractTests.swift`. Append-only source guard: new Swift names avoid update/delete/remove/replace/edit/overwrite/write/clear/purge/wipe/reset/drop/truncate/erase/forget/modify/mutate/destroy/set; the Done list includes `swift test --filter WatchSessionEngineTests`.

## Phases (serial)

- P1 `crew-builder-watch` — D-2 with S-4310 and S-4311: tests first, a source fix only if red for the stated reason. Scope: `watch/watchos/Sources/WatchSessionEngine/WatchEffortRating.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift`.
- P2 `crew-builder-app` — D-3 with S-4306..S-4309. Scope: `lib/state/watch/watch_session_auto_push.dart`, `lib/state/watch/live_session_mirror_state.dart`, new `test/rating_first_answer_push_test.dart`.
- P3 `crew-docs-keeper` — `watch/sync_protocol/PROTOCOL.md` (D-5), `docs/watch_session_sync.md` (add at most ~1 KB), `docs/watch_session_capture.md`, plan evidence.
- Then `crew-prover`, `crew-reviewer`, owner device checks.

Size: about 60 production lines (Dart) plus at most 15 Swift, about 250 test lines, 3 phases, two tracks (phone sync, wrist tests) with no contract change: inside the budget (one soft signal).

## Owner checks (owner)

- (owner) Finish a session on the watch with the effort question on; answer on the phone first: the watch's question closes by itself within a few seconds.
- (owner) Answer on the phone with the watch off the wrist/out of reach, then bring it back: its question closes once it reconnects.

## Progress

| Phase | What | Result |
|---|---|---|
| P1 | `crew-builder-watch` — D-2 proved by S-4310/S-4311; the fix they showed: `WatchSessionEngine` is now an `ObservableObject` sending `objectWillChange` at the end of `applySnapshot`, forwarded by `WatchEffortRatingState` on the main queue | done — `swift test` 610 tests, 0 failures; watch app target BUILD SUCCEEDED (evidence file) |
| P2 | `crew-builder-app` — D-3: `WatchSessionAutoPush._pushRating` before the ended-session early return, `LiveSessionMirrorState.sendRatingFor` / `holdsEffortRating`; doc-block move into `watch_session_capture.md`'s wrist half | done — S-4306…S-4309 in `test/rating_first_answer_push_test.dart`; full `flutter test` all passed; `flutter analyze` 181 before and after (evidence file) |
| — | fix 2 tests | done per the lead's handoff (2026-10-19); the two test names were not recorded in the handoff and are not re-verified here |
| P3 | `crew-docs-keeper` — `docs/watch_session_capture.md`, `docs/state_management/watch_surface.md`, plan evidence | done 2026-10-19; `watch/sync_protocol/PROTOCOL.md` amendment pending, separate run; `docs/watch_session_sync.md` and `docs/session_summary.md` deliberately untouched (42a already documents them; the sync doc sits under the indexing warning band) |

## Assumption Log

- A-1 The wrist closes through the snapshot path with no Swift logic (D-2); if S-4310 is red the fix is part of P1.
