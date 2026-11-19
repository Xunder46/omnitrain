# Plan 158 — sweep residue: real defects or harness artifacts?

Investigation only: no product code was changed. Every conclusion below rests on a
recorded run, a quoted line of code, or both.

Method: the 2000-seed sweep (`test/watch_convergence_random_test.dart`) was run
once end-to-end; then a scratch probe re-ran every diverging seed under the
shipping action set (`kShippingActions`, no `PhoneReassertsLive`), printed each
diverger's class and whether it needed the harness-only action, and shrank the
`absorbing` and `entries` seeds with a local 1-minimal shrinker. Two further
scratch experiments isolated the `entries` id set and the `status` clock pair.
The scratch file was deleted at the end of the run; its two evidence runs are
kept as the gateway logs below.

Evidence logs:

- `.work/gateway/test-20261114-153538-98992.log` — the full 2000-seed sweep.
- `.work/gateway/test-20261114-154141-3080.log` — per-seed classes, traces and shrunk traces.
- `.work/gateway/test-20261114-154357-4086.log` — the same probe, second pass (the seed set moved; see §1).
- `.work/gateway/test-20261114-154720-6190.log`, `.work/gateway/test-20261114-154749-6514.log` —
  the `status` clock experiment, with the lifecycle frames' `at` stamps.

---

## 1. The sweep today, and why its membership is not stable

```
S-14509 contract: 2000 seeds; 1802 converge on every trace; 112 diverge on a
trace the shipping app can perform [...]; 27 on a heal stall alone [...];
59 only after the harness-only re-assert
S-14509 contract: by class {status: 149, entries: 8, heal: 42, absorbing: 3}
```

Plan 151 recorded 116 divergers by class `{status 151, heal 26, absorbing 6,
entries 8}`. Two things changed in the count, and one thing did not:

- **`entries` is exactly the same 8 in both runs**, and it is the one class whose
  reproduction is stable (see §3).
- **`absorbing` fell from 6 to 3 and `heal` rose from 26 to 42.** Neither move is
  a code change: the seed set is not reproducible between runs. The phone mints
  its session ids from the real clock (A-145-02) and, as §5 shows, stamps its
  lifecycle frames from the real clock too, so a run minutes later walks a
  different path through the same seed. The probe run 20 minutes after the sweep
  found `absorbing` on 1524, 1806 and 1866 — none of them absorbing, or even
  diverging, in the sweep's own list — and `entries` on 819, 982, 1061, 1343,
  1347, 1355 and 1583.

Consequence for the rest of this document: a seed number identifies one run, not
a reproducer. The classes are stable; the seeds in them are not.

## 2. `absorbing` (3 seeds) — harness artifact, not reproducible

The probe found `absorbing` on seeds 1524, 1806 and 1866 and recorded the class
from a full run each. Every one of them, replayed through `runSeed` minutes
later, printed `converged on replay`:

```
SEED 1524 converged on replay
SEED 1806 converged on replay
SEED 1866 converged on replay
```

(An earlier probe pass, twenty minutes before this one, named seed 1218 as its
only `absorbing` seed; by this pass 1218 had converged and 1524, 1806 and 1866
were absorbing instead — the same instability §1 describes.) No absorbing trace
could be shrunk, because no absorbing trace survived one replay.

What an `absorbing` violation means is worth stating, because it bounds the
verdict: `HarnessRunner._noteAbsorbingEnd` (`test/helpers/watch_pair_harness.dart`)
fires when a side that reported `completed`/`abandoned` for a session reports
`active` for it again. It is a check on the *pair's* memory of the samples the
clock let it take, so it inherits the same clock asymmetry as `status` (§5); a
session the wrist re-reads as active after the phone's real-clock `abandoned`
landed is exactly the shape that produces it. **Verdict: harness artifact,
subsumed by §5's clock defect.** Nothing here is evidence of a shipping defect.

## 3. `entries` (8 seeds) — harness artifact: check 3 counts the phone's own
annotations as wrist entries

This is the one class that reproduces every time, and its shrunk trace is four
actions (seed 1583; 1061, 982, 1343, 1347 and 1355 shrink to the same shape):

```
SHRUNK 1583
4. wrist starts a Free workout
5. a live frame from the wrist refused (observations_up)
8. wrist logs a set
17. wrist logs a set
SHRUNK FAILURES 1583
session 1: the wrist never held phone-change-del-w-entry-1-1794301231000-1-0,
phone-change-del-w-entry-2-1794301231000-0-0
```

The replay of that four-action trace, with the two entry sets the harness unions
printed out:

```
ENTRIES converged=false failures=[session 1: the wrist never held
  phone-change-del-w-entry-1-1794301231000-1-0,
  phone-change-del-w-entry-2-1794301231000-0-0]
ENTRIES s-w-1 phone={w-entry-2, phone-change-del-w-entry-1-1794301231000-1-0,
  phone-change-del-w-entry-2-1794301231000-0-0, w-entry-1}
ENTRIES s-w-1 wrist={w-entry-1, w-entry-2}
```

The wrist's two entries and the phone's two wrist entries agree exactly. The only
ids the phone holds that the wrist does not are `phone-change-del-w-entry-*` —
and those are not wrist entries at all. They are the phone's **deletion
annotations**:

- `lib/state/watch/watch_session_auto_push.dart` mints one per vanished set,
  `'del-$entryId-${_clock().millisecondsSinceEpoch}-${_deleteSerial++}'` (D-110's
  "a set that vanished is announced"). Its own tests name the shape:
  `test/watch_session_auto_push_test.dart` — `startsWith('del-$doomed-')`,
  `startsWith('del-$_wristEntryId-')`.
- The phone stages every annotation for a wrist session in its inbox under
  `WatchInboxEntry.phoneChangeId(changeId, index)` →
  `'phone-change-$changeId-$index'` (`lib/state/watch/watch_session_inbox.dart`,
  `lib/data/models/models.dart`, where `_phoneChangeIdPrefix = 'phone-change-'`).
  `test/watch_capture_repository_parity_test.dart` names such an id
  (`phone-change-chg-7-1`).

`HarnessRunner._sampleEntries` then unions **every inbox `entryId`** into the
phone's entry set:

```dart
for (final id in harness.sessionIds) {
  final inbox = await harness.repository.getWatchInboxEntriesForSession(id);
  if (inbox.isEmpty) continue;
  _addEntries(phoneEntryIds, id, [
    for (final entry in inbox) entry.entryId,
  ]);
}
```

and `checkConvergence`'s check 3 requires every phone id to be one the wrist
held. A deletion annotation can never be: it is the phone's record *about* a
wrist entry, minted by the phone. **Verdict: harness artifact, in check 3's id
space, in 8 of 8 `entries` seeds** — the check is unsatisfiable whenever the
phone announces a deletion for a wrist session, which is ordinary product
behaviour (`test/watch_session_auto_push_test.dart`).

## 4. `timers` / seed 1814 — could not be reproduced

Seed 1814 was the `timers` seed the series review named. It does not reproduce at
all:

```
SEED 1814 converged on replay
```

The differential-timer check compares the pair's rest timers when both sides
carry one; with 1814 converging on the very next replay, there is no failing
trace to shrink, and this run's 2000-seed sweep produced **no `timers` class at
all** (`by class {status: 149, entries: 8, heal: 42, absorbing: 3}`). **Verdict:
unreproducible in this run; nothing to classify** (consistent with A-146c-16,
which retired the class).

## 5. `status` (149 of 112 divergers) — harness artifact: the pair's ends are
stamped from two different clocks

The four `status` seeds this run shrank (29, 117, 149 and 193) all shrink to the
same four actions, and every one of them fails the same way:

```
SHRUNK 29
4. wrist starts a Free workout
5. link drops
21. phone discards
25. wrist finishes
SHRUNK FAILURES 29
session 1: phone abandoned vs wrist completed
```

(seeds 117 and 149 shrink to the identical shape with the same failure; 193
likewise.) Read the trace: the wrist starts the session, the phone adopts it,
the link drops, the phone discards it, and the wrist finishes it while still
offline. On reconnect the wrist's `completed` reaches the phone and the phone's
`abandoned` reaches the wrist. The wrist keeps `completed` and the phone has no
row, so the check reads `phone abandoned vs wrist completed` forever.

The ruled reason is the end-stamp comparison, and the experiment below shows the
two stamps do not even live in the same calendar. Printing every
`session_lifecycle` frame of that trace with its payload:

```
CLOCK FRAME discard, +3s, finish wristToPhone delivered
  sentAt=2026-11-10T09:00:00.000Z payload={state: started, at: 2026-11-10T09:00:00.000Z}
CLOCK FRAME discard, +3s, finish phoneToWrist queued
  sentAt=2026-11-14T20:47:51.833045Z payload={state: abandoned, at: 2026-11-14T20:47:51.833031Z}
CLOCK FRAME discard, +3s, finish wristToPhone queued
  sentAt=2026-11-10T09:00:03.000Z payload={state: completed, at: 2026-11-10T09:00:03.000Z}
```

The wrist's frames carry the harness's `TestClock` (`2026-11-10T09:00:03Z`, the
run's start plus the 3 s the trace advanced). The phone's `abandoned` carries the
**real wall clock** (`2026-11-14T20:47:51Z`) — about four and a half days
*later* than every stamp on the wrist's side, no matter what the trace does with
`TimeAdvances`.

The wrist then applies D-15403 correctly to a meaningless pair of numbers:

- `lib/core/sync_protocol/end_skew.dart`:
  `bool endsBeforeHeldMsByMoreThanSkew(int incomingMs, int heldMs) => heldMs - incomingMs > kEndSkewToleranceMs;`
  (`kEndSkewToleranceMs = 2000`).
- `lib/state/watch/watch_session_adoption_bridge.dart`, `_routeLifecycleToHeld`,
  held-and-ended branch: `if (atMs != null && endsBeforeHeldMsByMoreThanSkew(atMs, held.endedAtMs!)) { await target.discardCurrentSession(); }`
  — the abandon is only the earlier end if it is earlier by more than 2 s. Four
  days *later* is not, so the finish stands.

The source of the real stamp is a documented wiring decision, not a bug on a
device:

```dart
final mirror = LiveSessionMirrorState(
  ...
  // The graph's clock drives the ledger's `since`, repeat window and 24 h
  // bound only (plan 128 D-1/D-2a); frame stamps keep the mirror's own clock
  // so a graph clock that stands still cannot defeat plan 127's snapshot order.
  ledgerClock: clock,
```

`lib/state/watch/watch_sync_wiring.dart` gives the mirror only `ledgerClock`;
`LiveSessionMirrorState`'s frame clock stays `_clock = clock ?? _utcNow`
(`lib/state/watch/live_session_mirror_state.dart`), and `_utcNow` is the real
clock. On two devices that is right — both sides read the same wall clock. In the
harness it is not: the wrist's side is the injected `TestClock` and the mirror's
is `DateTime.now`. The harness already knows real-clock instants leak into
frames — see the `WatchPairHarness` comment that an instant off the run's
`clockGrid` "came from the phone's real clock and is aliased (D-15204)" — but
`WatchPairHarness.build` passes `clock: clock.call` to `createWatchSync`, which
only reaches `ledgerClock`.

**Verdict: harness artifact — clock incoherence, not a product defect.** The
divergence is manufactured by a ~4½-day gap between the two devices' stamps; the
product's own rule (a finish is never deleted by a discard within
`kEndSkewToleranceMs`, D-15403, proved by
`test/sync_protocol_fixtures_test.dart` S-15405–S-15407 and
`test/watch_session_adoption_bridge_test.dart`) is then applied to numbers the
harness, not the app, produced.

One residual that is *not* an artifact and needs a product decision (not a code
change here): when the phone's discard and the wrist's finish really are within
2 s of each other, D-15403 keeps the finish on the wrist while the phone holds
nothing, so the pair disagrees by design. The convergence check demands agreement
in all cases, which is stricter than the documented rule. A within-skew tie
should probably count as converged for this check, and that is a check (and
perhaps a documented-rule) decision for the owner.

## 6. Smallest fix location per class — locations only, nothing written

| Class | Verdict | Smallest place to fix |
|---|---|---|
| `entries` (8/8) | Harness artifact | `HarnessRunner._sampleEntries` in `test/helpers/watch_pair_harness.dart`: keep the `WatchInboxEntry.phoneChangeId` annotations (`phone-change-*`) out of `phoneEntryIds`, since they are phone-side records about wrist entries, never wrist entries. That single filter makes the four-action replays converge. |
| `status` (149/112) | Harness artifact | The mirror's frame clock has no seam: pass one through `createWatchSync` in `lib/state/watch/watch_sync_wiring.dart` (the `LiveSessionMirrorState(...)` call currently passes `ledgerClock: clock` only) and pin it to the pair's `TestClock` in `WatchPairHarness.build`. Then both sides stamp from one clock and D-15403 is exercised on real orderings. |
| `absorbing` (3) | Harness artifact, unreproducible | No separate fix: same clock incoherence; expected to fall away with the `status` fix. |
| `timers` (0 this run) | Unreproducible | Nothing to fix; seed 1814 converges on replay. |
| `heal` (42) | **Not investigated** | Heal stalls (the heal ran out of `healRoundLimit` rounds without reaching a fixed point) were outside this brief's six questions. They are a distinct class — no check mismatch, no product evidence — and want their own shrink runs. |

No class in this sweep is, on the evidence gathered, a shipping product defect.

## What could not be determined

- **The `heal` class (42 seeds, the second-largest).** Not shrunk, not
  classified. It needs its own run: the shrinker would have to target
  `report.healConverged` rather than a check mismatch.
- **A stable reproducer for `absorbing`.** Every candidate diverged once and
  converged on the next replay, so no shrunk trace exists.
- **Whether a within-2 s discard/finish tie should count as converged.** That is
  a decision about the check and about D-15403, not something the traces can
  settle.
- **`lib/` product behaviour under unequal clocks.** Not investigated by design:
  two real devices share a wall clock, so the scenario the harness manufactures
  does not arise; if the owner wants a device-clock skew tested deliberately, the
  adoption bridge and the wrist engine both compare through `end_skew.dart`, and
  `test/sync_protocol_fixtures_test.dart` is where such a fixture belongs.
