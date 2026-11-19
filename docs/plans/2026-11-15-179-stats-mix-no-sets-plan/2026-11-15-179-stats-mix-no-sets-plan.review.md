# Review: 2026-11-15-179-stats-mix-no-sets-plan · P1/P2/P3 · c95c4a23..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: not run by reviewer (brief forbids; brief figures: new tests green on Mock and Hive, 27 reader files 609 tests 0 red, mutation 9/9 killed, analyze at baseline 181)
Diff vs Predicted Files: conforms (13 changed files, all inside the plan's Predicted Files; `docs/plans/2026-11-13-157-stats-what-counts-series.md` +4 is the series index the brief says to ignore)

## Findings

1. [Minor] `lib/core/services/stats_progress_service.dart:668-674` — `interferenceSessions` computes its `hasSet` flag inline with the exact predicate the new `_hasSetEffort` (`stats_progress_service.dart:991`) uses (`_sectionForKind(effort.effortKind) == ExerciseSection.resistance`). Today the two cannot disagree: same expression, same `_sectionForKind`, same history index, and neither skips an effort the other sees (the `exerciseId == null` continue at :679 runs after `hasSet = true` is set). The risk is drift only under a future edit: someone changes one predicate (e.g. a new effort kind mapped to Resistance in one walk only) and `InterferenceSession.hasSetEffort` would then disagree with the split's `hasSets` — the interference signal and the Mix bar would contradict each other, and no existing test crosses the two surfaces, so nothing would go red. Fix: extract one predicate (e.g. `bool _effortIsResistance(SegmentEffort e)`) used by both walks, or have the interference loop call `_hasSetEffort` and drop its inline flag. Guard: none exists; a parity test asserting `interferenceSessions().hasSetEffort` and the split's set-lessness agree on a mixed fixture would pin it.

## Answers to the brief's five questions

1. **`hasSet` duplication (Q1)** — Minor, finding 1. Not risky today: both walks are over the same `segmentsOf`/`effortsOf` pairs with the identical `_sectionForKind == resistance` test, so they agree by construction on this code. Only untidy-plus-fragile: the surfaces can drift apart under a future one-sided edit with no test guarding the pair.
2. **`_sessionSplit` readers (Q2)** — OK. All four callers checked in the file: `weeklyLoads` (:614) folds `loadBySection.values` — the sum is unchanged by the rescale, no per-section assumption; `interferenceSessions` (:713) reads only `loadBySection[ExerciseSection.sports] ?? 0.0` — missing key handled; `_mixPayload` (:785) merges via `_addAll` (:1059), which iterates the source map's entries — an absent Resistance key contributes nothing, and `timeSeconds` folds values so the session's total time is unchanged; `sessionTimeBySectionFor` (:946) hands the map to `ActiveEnergyService._estimate` (`lib/core/services/active_energy_service.dart:70`), which sums `_kcal` over the entries present — no Resistance lookup, no division by a Resistance figure. No reader divides by a Resistance figure or assumes a Resistance key exists. (`sessionLoadByModality` divides by the map's own total, which the scaled branch keeps equal to the duration.)
3. **The one-set flip (Q3)** — OK, the plan already names it. Reachable: log a run and a hold, no set (Mix reads Cardio/Isometric 100 by the scaled branch), then add one set exercise before Finish — the set adds no measured time, so the remainder rule returns and the bar flips to e.g. Cardio 75 / Resistance 25 for the 40-min/30-min-run case; adding a second set changes nothing further. The user sees one segment become two with no explanation in the UI (D-6: no wording change). The plan names this exact discontinuity in "What the user sees" (the A2 example: same session with a set reads 67/33) and Open item 3 names the wrist variant (planned-but-unlogged sets keep the remainder until 157d). Not a new finding.
4. **`durationSecs <= 0` in the scaled branch (Q4)** — OK, unreachable. The branch runs only when `totalMeasured > 0` and `totalMeasured <= durationSecs` (`training_load.dart:222-229`): if `durationSecs <= 0` while `totalMeasured > 0`, then `totalMeasured > durationSecs` is true and the overflow branch above it returns first (whole session to the dominant section, or `{}` when dominant is null). For a rolling session the `if (isRolling) return measured;` at :214 returns before either. So inside the scaled branch `durationSecs >= totalMeasured > 0` always holds, and the rescale can never divide by zero or emit a negative value. (`_sessionSplit` computes `durationSecs = (endedAtMs - startedAtMs) / 1000` only when `endedAtMs != null`; a started-after-ended session would be caught by the overflow branch the same way.)
5. **Docs delta staleness (Q5)** — OK. The "its own duration minus the measured sums" sentence is no longer stale: it is now conditioned on "holds a set effort" (`docs/training_load.md:67-69`), and the set-less no-measured case is covered by the next bullet's "A session with no measured time is unchanged" (:70-72) — together the two bullets state exactly what the code does (remainder when sets exist; scaled share when not; remainder-with-zero-measured keeps all Resistance). The `S-13416` line (`docs/session_summary.md:145`, "Free Training with only set work: resistance remainder") stays true: only-set work means measured sums are zero, so the remainder branch still answers all Resistance and the test is untouched by the premise fixes. The new session_summary sentence (:131-135) is accurate for the Free Training branch it sits in. All named test ids exist: S-20001..S-20006 in `test/mix_no_sets_pure_test.dart`, S-20007..S-20011 in `test/mix_no_sets_service_test.dart` (each seen in the file this run). `training_load.md`'s "one remainder rule" sentence (:22) stays true — the remainder branch still exists for set sessions.

## Docs delta

- `docs/training_load.md` MODIFIED ("A non-rolling session that holds a set effort gets its Resistance time as the") -> applied (`docs/training_load.md:67-69`, diff seen)
- `docs/training_load.md` ADDED ("A session with no set effort and some measured time shares its whole duration") -> applied (`docs/training_load.md:70-73`)
- `docs/training_load.md` ADDED (`test/mix_no_sets_pure_test.dart`) -> applied (`docs/training_load.md:88-89`, verified-by)
- `docs/training_load.md` ADDED (`test/mix_no_sets_service_test.dart`) -> applied (`docs/training_load.md:89-90`, verified-by)
- `docs/session_summary.md` ADDED ("session with timed work and no set shares its whole length across the timed") -> applied (`docs/session_summary.md:134-135`, diff seen)
- Doc edits the table does not name: none — the two diffs touch only the rows above.

## Scenario coverage

- S-20001 -> `test/mix_no_sets_pure_test.dart` `S-20001 a run-only session reads Cardio over its whole length` (fails without: asserts `{cardio: 2400.0}`; old rule gives 1800/600)
- S-20002 -> `test/mix_no_sets_pure_test.dart` `S-20002 a hold-only session reads Isometric over its whole length`
- S-20003 -> `test/mix_no_sets_pure_test.dart` `S-20003 two timed modalities split the duration in proportion` (asserts 2250/750 and sum 3000)
- S-20004 -> `test/mix_no_sets_pure_test.dart` `S-20004 a session with sets keeps the remainder rule` (mutation b)
- S-20005 -> `test/mix_no_sets_pure_test.dart` `S-20005 measured time over the duration still goes to the dominant modality before the new rule` (mutation d)
- S-20006 -> `test/mix_no_sets_pure_test.dart` `S-20006 a session with no measured time stays all Resistance` (mutation c)
- S-20007 -> `test/mix_no_sets_service_test.dart` `S-20007 a timed-only session reads cardio 100% and no resistance time` (Mock and Hive via `harnessFactories`; asserts the bar and `sessionTimeBySectionFor` = `{cardio: 2400.0}`; mutations e, f)
- S-20008 -> `test/mix_no_sets_service_test.dart` `S-20008 a drill-only session (3 x 360 s holds) reads isometric 100%`
- S-20009 -> `test/mix_no_sets_service_test.dart` `S-20009 a session holding a set keeps the remainder rule` (real `_hasSetEffort` read; mutations f, g, i)
- S-20010 -> `test/mix_no_sets_service_test.dart` `S-20010 the timed-only session still counts its full 40 minutes of weekly load` (mutation e)
- S-20011 -> `test/mix_no_sets_service_test.dart` `S-20011 a round-only session's Sports load covers the whole hour` (asserts Sports 180.0; old rule reads 120.0)
- No scenario MISSING. Mutation (h) (`_sessionSplit` passes `hasSets: true`) is the service-level twin of (b) and is covered by S-20007/S-20009 going red under it; verdicts per the brief's figures (mutation pass 9/9 killed), not re-run.

## Assumption Log rulings

- Base commit `c95c4a23`, tree holds other plans' work — ratified (the diff stat shows only this plan's scopes plus the series index and `test/stats_gallery_render_test.dart`, both named out of scope by the brief).
- S-20001.. id range chosen after a grep — ratified.
- Option "count only the timed minutes" declined — ratified (owner decision recorded in the Goal).

## Done-criteria spot checks

- All twelve `sessionTimeByModality(` calls in `test/training_load_test.dart` gained `hasSets: true`, assertions untouched (diff seen, 12 additions).
- The five premise fixes add exactly one set effort per named fixture (`mix_layer_service_test.dart` S-1503, `modality_mix_period_service_test.dart` via `_seedWork`, `modality_mix_shift_signal_screen_test.dart` fmix-p3/b0..b4, `active_energy_service_test.dart` s-04/s-14, `active_energy_import_test.dart` a wrist set observation) with no assertion edits (diffs seen).
- The new branch sits between the overflow branch and the remainder, exactly as D-1 specifies (`training_load.dart:222-229`); operand order `entry.value * durationSecs / totalMeasured` as specified.
- `_hasSetEffort` and the `_sessionSplit` argument match D-3's exact code (`stats_progress_service.dart:925, 991-1001`).

