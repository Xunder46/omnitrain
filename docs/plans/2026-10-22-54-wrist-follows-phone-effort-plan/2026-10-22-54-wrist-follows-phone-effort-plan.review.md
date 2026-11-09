# Review: plan 54 — the watch follows the phone's effort; the lock releases

Reviewer: code-reviewer (2026-10-23). Base: `a5ef2efe2a39874857c560fb2e62f5808814ddcc`.

## Findings

1. **major** | plan file, Decision Ledger D-1 (and Phase 1 item 2, Impact row "WatchTimerPush.flush()", root-cause §1) | D-1 as written says `await timerPush.flush()` and "Nothing else in `WatchTimerPush` changes", but the shipped build is `timerPush.flushClears()` plus a clears-only mode in `WatchTimerPush` (+15 lines) — the plan text is now false against its own code | annotate D-1 in place (or add D-1a) naming `flushClears()`, the clears-only mode and `_fullAgain`, citing S-6322/S-6323/S-6324/S-7305 and S-8408; the Assumption Log entry alone does not bind a reader of D-1 | @governor (plan edit).
2. **major** | `watch/sync_protocol/PROTOCOL.md:314` | names `testS6004APhoneTimerForAnotherSlotIsNotTheWristsWorkClock`, which the 2B split removed — a doc naming a test that no longer exists | replace with the two shipped names | @governor (outside this plan's Predicted Files; the builder deferred it correctly, but it must not survive the merge).
3. **major** | `watch/sync_protocol/PROTOCOL.md:696` (amendment 1 register) | "the watch hides a timer that came from a message for another slot" no longer describes shipped behavior for a slot the session holds — the wrist now follows it (D-2) | add a pointer to the follow rule (`docs/state_management/watch_surface_wrist.md`, S-8401) or an amendment note; the wire contract itself is unchanged, so no schema edit | @governor.
4. **minor** | `WatchSessionEngine.swift:737-740` (`applyTimerState`) | the jump is performed without re-checking the session is still active: a lifecycle frame landing between `adoptTimers` and `selectExercise` could move a just-finished session's position and emit `exercise_advanced` (D-6's gate is checked only at collect time) | re-check `current?.status == .active` before performing the jump, or accept and document the window | @developer.
5. **minor** | `watch_timer_push.dart:157-176` (`_flush`) | when a clears-only flush joins a running FULL drain whose pass then fails its send, the follow-up pass is downgraded to clears-only and withholds the start the full flush owed until the next phone-state trigger (pre-54 the follow-up pass was always full) | either force `_fullAgain` for the pass after a failed full pass, or document the window in the `_flush` doc comment | @developer.

## Brief checks

**(a) `_flush`/`flushClears`/`_fullAgain` join cases** — walked all four:
- *Full first, then clears joins*: the follow-up pass is clears-only. A clears-only pass can never send a start: `clears` entries are only ever `null` values and `next.clear()` runs before any send (`watch_timer_push.dart:331`). The start is withheld only in the failed-full-pass window of finding 5.
- *Clears first, then full joins*: `_fullAgain` is set, so the pass after the running clears-only pass is full and sends the start — proven by S-8408 (red before the per-request fix, green after).
- *Clears joins a clears drain*: follow-up stays clears-only; nothing but clears is owed by either caller. Correct.
- *A drain with three joiners*: `onlyClears` is computed from `_fullAgain` at each pass boundary, so a full joiner before a boundary upgrades the next pass and a later clears joiner never downgrades a pass a full joiner asked for. Correct.
No clears-only pass can send a start in any case; the only start-withholding window is finding 5.

**(b) The engine jump** — `selectExercise` is never reached while the mutex is held: `applyMessage` (`:475`) is not mutex-wrapped, `applyTimerState` runs outside it, and `applySnapshot` performs the jump only after `mutex.exclusive` returns (`:517-521`); `adoptTimers`' only in-mutex caller (`applySnapshotExclusive:590`) only collects. If the jump's `selectExercise` returns nil (the slot vanished between collect and perform), it changes nothing and emits nothing — safe degradation, and `selectExercise` re-validates against `current` so the collect-time check cannot go stale silently. A duplicate (replayed) frame with the same `messageId` derives the same `recordId`, so `adoptTimer` early-returns with an empty `TimerAdoption` — it never jumps again. A re-send under a new `messageId` is a new frame by the ledger's own identity rule (pre-existing semantics, not introduced here).

**(c) The reworked S-6004** — the S-1403 hiding rule is still protected: the unheld-slot fixture asserts `workTimer` is nil and nothing is emitted for a message-borne timer whose slot the ladder does not hold, and the "only a message-borne timer is hidden" half is untouched. The held-slot half is now the jump behavior, asserted by the new companion test. Correct split.

**(d) Lock rule and pager** — untouched: no diff in `WatchMenu.swift` or `WatchPagerModel.swift`; S-8404 and S-8414 assert the unchanged rules (lock on any running work timer, cleared by the clear frame; derived pager index; refused landing).

**(e) Clears-only vs D-1** — the builder's reasoning is confirmed against the existing push tests: S-6322/S-6323/S-6324/S-7305 assert that when the wrist has already logged, begun a newer interval, or stopped its own rest, no start is sent for that kind — a full flush on the wrist's inbound frame would recompose the phone's still-running timer and re-offer it as a start, restarting a clock the wrist ended. Clears-only is the right trigger shape, and S-8408 proves an ordinary flush is not starved. **The plan text must be corrected** (finding 1).

## Docs (4d)

Implicated: the three edited docs (checked against post-change code — every named file, test and group exists; every behavioral claim matches the shipped code) and `watch/sync_protocol/PROTOCOL.md` (no scope declaration → implicated; findings 2 and 3). `rest_tracking.md:314` and `watch_surface_wrist.md:444` mention `WatchTimerPush` without a trigger claim — not falsified.

## Standards

No widget, layout or copy change; no allowlist entry added, no ratchet raised (`ui_standards_contract_test.dart` 29 passed, per evidence and the full suite). N/A as a group.

Critical: 0 | Major: 3 | Minor: 2
