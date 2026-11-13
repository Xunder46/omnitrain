# Evidence — 146c: an earlier discard wins (146 PR 3)

Baselines, suite outputs, red→green tables and footprints live here; implementers write here, not into
the plan.

## Baselines (measured at planning, 2026-11-12)

- Plan 146's final soak (2000 seeds): **1777 converge, 146 diverging** on a shipping trace,
  `{status: 166, absorbing: 21, heal: 32, entries: 11, timers: 2}`
  (`.work/gateway/test-20261112-000556-15213.log`, recorded in plan 146's evidence `## Phase 5.Z`).
- Sweep contract: `knownClasses` = `{status, absorbing, entries, timers, heal}`; `shippingRatchet` =
  `(kSeedCount * 18 / 200).ceil()` (18 measured on seeds 1..200 in Phase 5.Z) —
  `test/watch_convergence_random_test.dart` :171-204.
- `flutter analyze`: **181 issues**, the repo baseline.
- Full suite at plan 146's close: **+7441 ~2: All tests passed!** (5m24s;
  `.work/gateway/test-20261112-000733-15770.log`).
- A-146-15's interim lives in two files: `lib/watch/session/watch_session_engine.dart`
  (`_applyLifecycle`, the completed-beats-abandoned skip ~766-776) and
  `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`
  (`applyLifecycleExclusive`, the same skip ~826-833). The phone's reconciler
  (`lib/core/sync_protocol/session_reconciler.dart`, `_incomingEndWins` :226-241) already resolves
  earlier-instant-first with the D-14601 tie-break and has no interim — verified by read, no change
  planned.

## Phase outputs

*(filled in by the implementing agent at the end of its own phase: command, result, red→green table,
footprint)*

| Phase | Check | Command | Result |
|---|---|---|---|
| | | | |

## Governor actions

*(recorded by the planner when the work needs something its tools deny)*
