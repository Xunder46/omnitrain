# Evidence — Stats PR 8h (housekeeping)

Plan: `2026-10-03-08h-stats-pr8h-housekeeping-plan.md`. Review findings go in
`2026-10-03-08h-stats-pr8h-housekeeping-plan.review.md`.

Executors write here, never into the plan: baselines, suite summaries, red→green tables, mutation pairs,
the measured doc sizes. Append a dated section per run; never rewrite an earlier one.

## Opening measurement

| Command | Result |
|---|---|
| `flutter analyze` | |
| `flutter test` | |

If 8a or 8b has merged before this run, state that here and use the re-measured numbers as the baseline
for every Done Criteria comparison below. The pre-8a `develop` (`2b6e8e5`) numbers were
`196 issues found.` (0 errors) and `+3635 ~1: All tests passed!`.

## Phase 1 — the two derivations, their guards, and the plan-file bookkeeping

### Red runs (guards written before the derivations)

| Suite | Command | Output |
|---|---|---|
| `test/interference_test.dart` — S-2301's stripped-source scan | | |
| `test/modality_mix_shift_test.dart` — S-2302's stripped-source scan | | |

### Green runs

| Suite | Command | Output |
|---|---|---|
| _not run yet_ | | |

### Byte-identity check (the rendered strings must not move)

| Assertion | Suite | Before | After |
|---|---|---|---|
| `endsWith('Sports load is up 30% over the last 3 weeks.')` | `test/interference_test.dart` | pass | |
| `'is up 38% over the last 3 weeks.'` | `test/interference_test.dart` | pass | |
| `'over the last 3 weeks.'` | `test/interference_signal_screen_test.dart` | pass | |
| `'… over the last 4 weeks, down from its usual …'` (six assertions) | `test/modality_mix_shift_test.dart` | pass | |
| `'Isometric is 3% of your load over the last 4 weeks, down from'` | `test/modality_mix_shift_signal_screen_test.dart` | pass | |

All six rows must pass **unmodified**. A changed expectation is a defect in the derivation.

### Mutation pairs (each applied, observed, restored, re-run green)

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (a) | `lib/core/models/interference.dart` | restore the `3 weeks` literal | S-2301's scan | | |
| (b) | `lib/core/models/interference.dart` | `kInterferenceSportsLoadWindowDays ~/ 7` → `~/ 14` | `test/interference_test.dart`'s `over the last 3 weeks.` assertion | | |
| (c) | `lib/core/models/modality_mix_shift.dart` | restore the `4 weeks` literal | S-2302's scan | | |

### Plan-file edits (S-2303)

| File | Line changed | Before | After |
|---|---|---|---|
| `docs/plans/2026-10-03-07-stats-pr7-index.md` | status line | `READY (planner) — neither half started.` | |
| `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/…md` | status line | `READY (planner) — not started.` | |
| `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/…md` | status line | `READY (planner) — not started.` | |
| `docs/plans/2026-10-03-06b-stats-pr6b-progression-rate-plan/…md` | status line | `READY (planner) — not started; blocked on 6a` | |
| 7a / 7b open questions answered by the owner on 2026-10-03 | rows marked answered | | |
| open questions the brief records no answer for | rows left untouched (count) | | |

### Doc sizes (H-3 / D-1605 — measured only, nothing edited)

64 KiB = 65,536 bytes; `test/docs_indexing_contract_test.dart` warns past 80% (52,429 bytes).

| Doc | Bytes | % of ceiling |
|---|---|---|
| _not run yet — every file in `docs/`_ | | |

### Full-suite summary (Phase 1)

```
<paste `flutter test`'s summary line>
```

## Plan size, measured

| Measure | Predicted | Measured |
|---|---|---|
| Plan lines | 236 | |
| Ledger decisions | 5 | |
| Scenarios | 3 | |
| Production lines changed | ~8 | |
| Files deleted | 0 | |
