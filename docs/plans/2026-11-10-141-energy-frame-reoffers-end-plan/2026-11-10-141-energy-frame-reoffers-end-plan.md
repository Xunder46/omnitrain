# Plan — 141: the wrist's live energy frames re-offer an end the phone still owes

**Status**: built by the crew 2026-11-10, verified by the lead; uncommitted. Owner device check: QA step 37.
**Base commit**: `b78112ef` (branch `claude_develop`).
**Parent plans**: 128 (the owed-end ledger: the phone re-offers an end when the wrist sends any frame naming the session), 135 (the `energy_live` frame, whose handler returned before the router).

## Overview

Owner (2026-11-10): a session the watch started was finished on the phone, and the watch stayed on its rest timer. The phone already keeps the finish owed (plan 128) and re-sends it when the wrist sends any frame naming the session. A wrist idle on a rest screen sends almost nothing, and the one frame it does send every few seconds, `energy_live`, bypassed the router (plan 135), so it never triggered the re-send.

What the user sees after this plan: a watch that missed the phone's finish hears it at its next energy frame (a few seconds while it is reachable) and goes back to Start by itself.

## Goal and acceptance

Acceptance: S-14101 .. S-14105.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-14101 | `WatchIncomingRouter` extracts the re-offer block into `_reofferOwedEnd(sessionId)` (a pure refactor) and adds `onLiveEnergyFrame(envelope)`: a wrist-origin frame naming a session re-offers that session's owed end, once per window as any wrist frame does | `watch_incoming_router.dart` |
| D-14102 | `createWatchSync`'s `energy_live` branch hands the frame to the holder, then to `router.onLiveEnergyFrame`, and still returns before the push-side flushes | `watch_sync_wiring.dart` |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-14101 | phone ended the wrist's session while away; the wrist sends `energy_live` | exactly one `completed` lifecycle is offered; the wrist engine ends | the early return skipped the router |
| S-14102 | two energy frames in a row | still one offer | n/a: guard of the once-per-window rule |
| S-14103 | an energy frame with origin `phone` | no offer | n/a: guard of the origin check |
| S-14104 | an energy frame naming another session | no offer for the owed session | n/a: guard of the session match |
| S-14105 | the S-14101 frame | the holder still has the kcal | n/a: guard that the holder still receives it |

## Phases

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 | crew-builder-app | router, wiring, `test/watch_session_end_owed_test.dart` | with plan 140 P1 (disjoint) |

## Progress

| Item | Status |
|---|---|
| P1 built, 158 tests passed in the four touched files, analyze 181 | Done |
| docs | Done (lead) |
| device check QA step 37 | Open (owner) |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | The cause of the owner's stuck watch is not proven (no device log); this closes the one code gap found (the energy frame did not trigger the re-offer) | no crash or sync log exists on the watch |
| A-2 | No architect phase and no independent review for this small unit; the lead read the diff and ran the suites | cost discipline |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_surface.md | ADDED | - | `onLiveEnergyFrame` | S-14101 |
| docs/watch-app-setup-and-qa.md | ADDED | - | `One workout across a relaunch` | S-14101 |
