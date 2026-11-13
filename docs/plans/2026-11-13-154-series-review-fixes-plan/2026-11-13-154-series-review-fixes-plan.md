# Plan 154 — fixes for the series review's first four major findings

Source: `docs/plans/2026-11-13-153-series-review/2026-11-13-153-series-review.review.md`, majors 1-4.
Owner said "Fix 1-4 now" on 2026-11-13. Findings 5-9 are NOT in this plan.

## Scope

- **A** (finding 1) — `EntryClaim` state behind a lock; no lost wakeup.
- **B** (finding 2) — a wrist `completed` that reaches a phone still holding an open workout ends it at the wrist's own end instant, not the arrival instant.
- **C** (finding 3) — skew tolerance on the earlier-discard rule, identical on the phone bridge, the Dart wrist twin and the Swift engine.
- **D** (finding 4) — the Health re-write cannot lose the workout when the write fails, and the delete is as narrow as the platform allows.

## Decisions

- **D-15401** `EntryClaim` takes an `NSLock` around `finished`/`waiters`; `wait()` registers or returns under the lock, `finish()` drains under the lock and resumes outside it (S-15401, S-15402).
- **D-15402** `_routeLifecycleToHeld` passes the lifecycle's `at` (fallback: none, as today) to `endSession(atMs:)` for an open held session; `endSession` already honours `atMs` (plan 146). `writeToHealth: false` stays (S-15403, S-15404).
- **D-15403** Skew tolerance `kEndSkewToleranceMs = 2000`. Two end instants within the tolerance of each other count as the SAME instant for D-14601/D-14630: the tie-break applies (completed wins, then the smaller messageId). A discard wins by being earlier only when it is earlier by MORE than the tolerance. Symmetric, so the phone and the wrist reach the same answer from the same two stamps. Applies to the phone bridge, the Dart wrist engine (snapshot and lifecycle paths) and the Swift engine (snapshot and lifecycle paths); documented in `watch/sync_protocol/PROTOCOL.md` and the reconciliation fixture notes (S-15405..S-15408).
- **D-15404** `HealthSyncService.rewriteWorkout`: if the new write fails (false or throws) after the delete, write the previous span again (`startedAtMs`..`previousEndedAtMs`, same draft) before returning; the delete is narrowed to a workout the platform can identify as the ledger's (by id if the platform interface exposes one; if it needs native plugin code, STOP and report, keep the window delete and say so) (S-15409, S-15410).

## Scenarios

- **S-15401** Two tasks wait on a claim while a third finishes it, many repetitions, under TSan: every waiter resumes, no report.
- **S-15402** A `wait()` that starts after `finish()` returns at once.
- **S-15403** Phone holds an open workout; wrist `completed` with `at` = T-10 min arrives now: the phone's end is T-10 min, not now.
- **S-15404** A `completed` with no `at` ends at the arrival instant as today.
- **S-15405** Discard 1 s before the phone's end: the finished workout stays (phone), and the wrist engine (both) ends on the same status.
- **S-15406** Discard 3 s before: the finished workout is deleted, as D-14630.
- **S-15407** Discard exactly 2 s before: the finished workout stays (tolerance is inclusive of 2 s).
- **S-15408** Dart twin and Swift engine agree on S-15405..S-15407 and the replay corpus still matches 16/16.
- **S-15409** Re-write where the new write fails: the previous span is written back, the ledger unchanged.
- **S-15410** Re-write where the delete is refused: nothing else is called (as today).

## Phases

1. A + B (small, independent). 2. C. 3. D. 4. Docs, sweep and soak counts, full suites.

## Progress

| Phase | Item | Status |
|---|---|---|
| 1 | A: `EntryClaim` behind an `NSLock` (S-15401, S-15402) | Complete — TSan red at HEAD, green after |
| 1 | B: wrist `completed` ends the phone at the wrist's `at` (S-15403, S-15404) | Complete — red at HEAD, green after |
| 2 | C: 2 s skew tolerance on the earlier-end rule | Complete — red at HEAD on all four fronts, green after |
| 3 | D: Health re-write restores the previous span | Complete — S-15409 red at HEAD on both failure paths, green after |
| 4 | Docs, sweep and soak counts | Complete — full suite 7509 passed / 0 failed, Swift 1419 / 0, lint at the HEAD baseline, sweep 10 of 200 |

## Assumption Log

- A-154-01 S-15403's wrist end is `_adoptedAt + 10 min`: the adopted row starts at the phone's
  clock (`_adoptedAt`), so a wrist end before that would be clamped by D-153 and prove nothing.
- A-154-02 D-15404's id-scoped delete is not reachable from Dart: `HealthPlatformService.deleteWorkouts(start, end)`
  is the only delete API and resolving a workout id needs native plugin code, which D-15404 says to report
  rather than write. The window delete stays; the restore closes the data loss. Reported to the governor.

