# 2026-11-14-172 — The `heal` divergence class: findings

Investigation only. Nothing in `lib/` changed. Evidence is the gateway logs listed in
§8; every number below is copied from them.

Scope: the `heal` bucket of `test/watch_convergence_random_test.dart` — traces whose
only divergence is `!report.healConverged` after `HarnessRunner.heal()` spent its
`healRoundLimit` (= 10) rounds without the pair's `_observableState()` reaching a fixed
point. Plan 158 investigated status/entries/absorbing and left heal unexamined
(`docs/plans/2026-11-14-158-sweep-residue-investigation/…findings.md`, "What could not be
determined"). This run closes that gap.

**Verdict: class (a) — a real shipping bug.** A wrist `session_snapshot` that carries
entries the phone itself logged is staged by the phone's inbox as wrist news and imported
as *new phone sets*, one per exchange. The phone's session therefore gains one set per
snapshot exchange without bound, its projection's newest entry never matches what the
wrist holds, and the two devices answer each other for ever. Heal is not a harness
artifact: the exchange it repeats (`WatchSyncOrchestrator.sync(reconnect: true)` →
`WatchSyncGraph.sync()`) is the app's own connect path. Fix location in §6; not
implemented here.

---

## 1. What this run measured

Four sweeps plus one scratch probe (deleted at hand-off, §7).

| Measurement | Command | Log |
|---|---|---|
| 200 seeds, random traces | `test test/watch_convergence_random_test.dart --plain-name "S-14509 the random seeds" --dart-define=CONVERGENCE_SEEDS=200` | `.work/gateway/test-20261114-215214-26027.log` |
| 2000 seeds, random traces | same, `CONVERGENCE_SEEDS=2000` | `.work/gateway/test-20261114-215237-26224.log` |
| 2000 seeds, contract | `--plain-name "S-14509 every random seed converges" --dart-define=CONVERGENCE_SEEDS=2000` | `.work/gateway/test-20261114-215336-26510.log` (run 1), `.work/gateway/test-20261114-220539-28530.log` (run 2) |
| 2000 seeds, kill sweep | `--plain-name "S-16310" --dart-define=CONVERGENCE_SEEDS=2000` | `.work/gateway/test-20261114-215336-26509.log` |
| Shrink + frame print | `test test/zz_heal_probe_test.dart --dart-define=HEAL_PROBE_SEEDS=15` | `.work/gateway/test-20261114-220456-28388.log` |

The probe imported `Shrinker` from the sweep test, replayed the heal-stall seeds with
`ConvergenceRun.runSeed` / `ConvergenceRun.replayActions`, shrank on
`!report.healConverged` (once with every action allowed, once with synthetic actions
excluded), printed the last heal rounds frame by frame, and then ran the harness's own
round by hand — `clock.advance(31 s)`, `noteClockGrid()`, `drainQueues()`,
`wristOrchestrator.sync(reconnect: true)`, `graph.sync()`, `settle()`, one wrist
`energy_live` — printing both sides' observable state and the phone's repository rows and
inbox rows after each. The lines quoted in §4 and §5 are from that run.

## 2. Question 1 — reproduce, and is it stable?

**200 seeds: no heal stalls.** 197 converge, 3 diverge on status/entries only; "heal never
settles on seeds `[]`". At the sweep's default size the class is not reachable at all.

**2000 seeds, random traces:** 1965 converge, 35 diverge (status 20, entries 6, heal 10);
heal never settles on seeds `[209, 270, 316, 899, 1662]`.

**2000 seeds, contract, two runs.** Run 1: 1933 converge, 31 shipping divergers, 13
heal-only, 23 only after the harness-only re-assert, by class
`{status: 41, entries: 9, heal: 19}`. Run 2: 1932 converge, 32 shipping divergers, 13
heal-only, 23 only after the harness-only re-assert, by class
`{status: 42, entries: 9, heal: 19}`. The heal-only *member list is byte-identical* in the
two runs:

```
[142, 209, 270, 316, 899, 1441, 1479, 1598, 1662, 1893, 1974, 1977, 1985]
```

So the contract sweep is deterministic run to run, and its heal bucket is exactly plan
169's bucket.

**2000 seeds, kill sweep:** 1896 converge, 75 shipping divergers, 11 heal-only
`[70, 253, 395, 535, 750, 766, 900, 924, 1372, 1761, 1833]`, 18 only after the
harness-only re-assert, by class `{status: 51, entries: 5, heal: 13, absorbing: 36}`;
1086 traces carry a phone kill.

**Only 5 of the 13 reproduce in isolation.** Replaying each of the 13 heal-only seeds
alone in a fresh process (the probe):

| Seed | Replay |
|---|---|
| 209, 270, 316, 899, 1662 | **stall** — `healConverged=false`, 10 rounds |
| 142, 1441, 1479, 1598, 1893, 1974, 1977, 1985 | converge — `healConverged=true`, 2 rounds |

Eight of thirteen stall only when earlier seeds ran before them in the same process. That
is plan 158 §1's instability, now measured precisely: the *stable core* of the class is
`[209, 270, 316, 899, 1662]` — the same five the 2000-seed random-trace run names — and
the rest is sweep-order sensitivity, not a separate mechanism. The kill-stall seeds
`[70, 253]` also converge on a fresh replay, so no kill-specific heal trace was available
to shrink (see §7).

## 3. Question 2 — the shrunk traces

All five stable seeds shrink to the same four actions, and the no-synthetic shrink is
identical, so the stall needs nothing the harness invented:

| Seed | Original actions | Shrunk (any action) | Shrunk (no synthetic) |
|---|---|---|---|
| 209 | 36 | 4 | 4 |
| 270 | 11 | 4 | 4 |
| 316 | 38 | 4 | 4 |
| 899 | 22 | 4 | 4 |
| 1662 | 29 | 4 | 4 |

```
1. phone starts a session
2. time advances <N>s      (14, 53, 82, 64, 61)
3. phone logs a set        (or, for 316/899/1662: 3. wrist logs a set, 4. phone logs a set)
4. wrist logs a set
```

One set on each device, in either order, is the whole fixture. Each replay reports
`healConverged=false rounds=10 failures=[the heal did not reach its fixed point]`. The
pair agrees on status, session id, ladder and timers throughout; only the entry sets
differ.

## 4. Question 3 — the last ten frames of a stalled heal

Seed 209, shrunk replay, heal round 10 (16 frames; the ten that carry the loop, verbatim
from the probe log; `entry-effort-1794301200001-0-N` abbreviated as `-N`):

```
wrist→phone null                            delivered   (the routines request)
wrist→phone session_snapshot delivered  entries=[1,10,2,3,4,5,6,7,8,9,w-entry-1]
phone→wrist planned_down delivered
phone→wrist session_snapshot delivered  entries=[10]
wrist→phone session_snapshot delivered  entries=[1,10,2,3,4,5,6,7,8,9,w-entry-1]
phone→wrist null                            delivered   (the snapshot request)
phone→wrist receipt delivered of=(entryIds)
phone→wrist session_snapshot delivered  entries=[11]
phone→wrist receipt delivered of=(entryIds)
phone→wrist session_snapshot delivered  entries=[11]
```

The two lines that matter:

* the wrist's snapshot carries **every** entry, including the phone-minted ones
  (`entry-effort-…-0-1` … `-0-10`);
* the phone's answer carries exactly **one** entry, and its number is one higher every
  round: round 8 answered `-0-8`, round 9 `-0-9`, round 10 `-0-10`, and the second
  snapshot of each round already carries `-0-(N+1)`.

Running the same rounds by hand shows what the number counts. After each round the
phone's repository and its inbox both grow by exactly one entry:

| Hand-run round | Phone rows on the effort | Phone `reps` rows | Inbox rows |
|---|---|---|---|
| 2 | 42 | 14 | 13 |
| 3 | 45 | 15 | 14 |
| (earlier rounds, same trace) | 3 per set | +1 per round | +1 per round |

Three rows per round — `reps`, `weight`, `extra-weight` — is one **set group**
(`LoggedEntryRows.setObservations`). The inbox grows by one row whose id is a
phone-minted entry id (`set:entry-effort-…-0-N`), never a wrist one. So each exchange
writes one extra set into the phone's own session and stages one more inbox row.

## 5. Question 4 — the mechanism, and its class

The loop, step by step, with the code that makes each step true:

1. **The phone holds a set the wrist has not been told about.** Its projection carries it
   as `entry-<sessionExerciseId>-<n>` — `lib/core/sync_protocol/phone_entries.dart`:
   `final entryId = 'entry-$sessionExerciseId-$entryIndex';` and
   `final entryId = 'entry-$sessionExerciseId-${group.number}';` (D-33's id space).
   Entries the wrist's staged rows already claim are dropped from the projection
   (`WatchSessionAdoptionBridge._stampsOf` → `PhoneEntries.project(wristLoggedAtMs: …)`,
   whose doc states the rule: "a group a live watch-inbox row claims by stamp is the
   wrist's own and is **not** projected … Every unclaimed entry is the phone's own"),
   which is why the answer carries only the newest, unclaimed one.
2. **The wrist keeps it and reports it back.** `lib/watch/session/watch_session_engine.dart`
   holds "the watch's own log plus the entries the phone sent" and
   `sessionSnapshot()` sends them all: `'entries': [for (final entry in entries) entry.payload]`.
   Nothing marks a phone-composed entry as not-the-wrist's.
3. **The phone stages the wrist's snapshot entries as wrist news.**
   `lib/state/watch/watch_session_inbox.dart`, `_stageable`:
   ```
   case 'session_snapshot' when envelope['origin'] == 'watch':
     sessionId = payload['sessionId'] as String?;
     entries = payload['entries'];
   ```
   `_isStageable` then checks only that the id is a non-empty string and that the kind's
   required fields are present, and `_entryFor` stamps
   `origin: WatchInboxEntry.originWatch`. An entry the **phone** minted is therefore
   staged as `originWatch`, put-if-absent by `entryId`.
4. **The importer writes it as a new phone set.** `lib/core/services/watch_session_importer.dart`,
   `_createEntry` builds the rows with
   `LoggedEntryRows.setObservations(effortId: effortId, entryIndex: index, …)` for a
   `set` row. The claim rule above suppresses only what the projection *names*; it does
   nothing to the import, so a row the phone already holds under that very entry id is
   written again as a second set (same reps, same load, same stamp). The new group's
   number is one higher, and the echoed inbox row claims the *original* group (the first
   unclaimed one with that stamp), so the duplicate is the one entry left unclaimed — the
   projection mints `entry-<sessionExerciseId>-<n+1>` for it.
5. **Back to step 1.** Exactly one new unclaimed entry exists after every exchange, so the
   exchange is self-sustaining: rows +1 set, inbox +1 row, entry id +1, for ever.

`_observableState()` compares each session's phone and wrist entry-id sets, so the pair
can never reach the fixed point `heal()` waits for. The harness's contribution is only the
repetition: it runs the app's own connect path ten times in a few milliseconds.

**Class (a).** Not (b): every step above is production code on a production path —
`WatchSyncOrchestrator.catchUp` calls `sync(reconnect: true)` on connect and reconnect,
`WatchSessionInbox` is what the running app stages arriving wrist snapshots with, and the
wrist's `sessionSnapshot()` is what the watch sends unasked. The harness adds no synthetic
action (the no-synthetic shrink is identical, §3) and no harness-only re-assert (these are
the `heal stall alone` seeds, not the `harness-only re-assert` ones). Not (c): the state
is not oscillating within a bound — the phone's row count grows monotonically with the
number of exchanges, and the wear is a duplicate set per exchange in the user's own
session.

**User-visible consequence.** Every exchange in which a wrist reports a snapshot while the
phone holds a session that has phone-logged sets adds one duplicate set to the phone's
session: after `n` reconnects the phone's session shows `n` phantom sets with the same
reps and load, its history row count grows the same way, and the phone's mirror, inbox and
repository grow without bound. The convergence test sees the same thing as a permanent
entry-set disagreement.

## 6. Smallest fix location per class

Neither is implemented in this run.

**Class (a) — the one to do. `lib/state/watch/watch_session_inbox.dart`: do not stage an
entry the phone authored.** `_isStageable` (or `_stageable`) gains one predicate: refuse
an entry whose `entryId` is in the phone's id space. `PhoneEntries` mints
`entry-<sessionExerciseId>-<n>` and the wrist mints its own ids (`w-entry-…`, and the
Swift engine's UUIDs), so a wrist snapshot carrying `entry-…` is reporting the phone's own
entry back and there is nothing for the phone to stage. Repository-backed alternative for
the same predicate: resolve the id the way
`WatchSessionImporter._phoneEntry` already does — `entry-<effortId>-<n>` names an existing
phone entry ⇒ skip.

Why this location: it is the earliest point (nothing is written, nothing is imported, the
receipt does not name it), it needs no knowledge of the wrist's engine, and it stops the
loop at the source — with no staged echo there is no new set, so the projection stops
advancing and the next round's `_observableState()` matches.

Second half, because inbox rows are durable (a phone that already staged echoes must
still converge): in `lib/core/services/watch_session_importer.dart`, mark a staged
`set`/`timed`/`round` row applied and write nothing when its `entryId` names a phone entry
that already exists — the same `_phoneEntry` lookup, used as a claim instead of as a rest
target.

**Class (b)/(c), for completeness — not this bug.** Had the class been a harness artifact,
the fix would be in `test/helpers/watch_pair_harness.dart` (`heal()`'s `sync(reconnect:
true)` re-assert and its `energy_live` injection); had it been bounded oscillation, the
fix would be an `_observableState()` comparison that ignores per-round entry ordering. The
frames and the row counts rule both out: the pair does not converge because the phone's
session is changing, not because the harness compares the wrong thing.

**Regression risk of the class (a) fix.** The wrist's own entries still stage
(`w-entry-…`, put-if-absent, imported once), phone corrections and deletions still stage
as `originPhone` (`WatchInboxStagingTransport`, `recordPhoneRating`), and a late wrist
entry still arrives through `observations_up`. What changes is only the case that is
broken today: an entry the phone minted, reflected back by the wrist. Suggested guards:
one import test with a staged row whose id is a phone entry id (no rows written, marked
applied), one inbox test for a wrist snapshot carrying both a phone-minted and a
watch-minted entry (only the latter staged), and one sweep re-run showing the heal bucket
on `[209, 270, 316, 899, 1662]` empty.

## 7. What could not be determined

* **Why eight of the thirteen heal-only seeds need the sweep around them.** Their stall is
  order-sensitive (page §2), and the probe replays them alone, so whatever earlier seeds
  leave behind (an id counter, the harness's clock grid) is still unidentified. Their
  shrunk traces were not obtained; only the five stable ones were.
* **A kill-specific heal trace.** Both kill-stall seeds tried (`70`, `253`) converge on a
  fresh replay, so the 11 kill-sweep heal-only seeds were not shrunk. The mechanism above
  needs no kill, so they are presumed to be the same loop with a different lead-in, but
  that is reasoning, not measurement.
* **Whether the wrist should send phone-composed entries at all.** The fix above is on the
  phone because it also protects against a watch that is already installed and will keep
  echoing. Whether `sessionSnapshot()` should report only watch-minted entries is a
  protocol question (`watch/contract/`), and answering it here would have widened the
  scope; it is worth a decision when the fix is planned.
* **How often a real pair exchanges snapshots.** The loop's rate is bounded by
  `catchUp`/`sync` and by `_endLedgerRepeatWindow`, which this run did not measure; the
  mechanism is per-exchange, so the rate decides severity, not existence.

## 8. Evidence index

| File | Contents |
|---|---|
| `.work/gateway/test-20261114-215214-26027.log` | 200-seed random traces; heal `[]` |
| `.work/gateway/test-20261114-215237-26224.log` | 2000-seed random traces; heal `[209, 270, 316, 899, 1662]` |
| `.work/gateway/test-20261114-215336-26510.log` | 2000-seed contract run 1; 13 heal-only seeds, class counts |
| `.work/gateway/test-20261114-220539-28530.log` | 2000-seed contract run 2; identical 13, one more status seed |
| `.work/gateway/test-20261114-215336-26509.log` | 2000-seed kill sweep; heal-only list, class counts |
| `.work/gateway/test-20261114-220206-27803.log` | probe, seeds 142 + 209, first frame and ledger print |
| `.work/gateway/test-20261114-220228-27960.log` | probe, seeds 142 + 209, row and inbox counts |
| `.work/gateway/test-20261114-220424-28253.log` | probe, 8 seeds; shrink traces for 209, 270, 316, 899 |
| `.work/gateway/test-20261114-220456-28388.log` | probe, 15 seeds; adds 1662, kill seeds, replay stability |

The scratch probe (`test/zz_heal_probe_test.dart`) was deleted with
`gateway.sh delete-scratch` before hand-off; it is not part of the change.
