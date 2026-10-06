# Review: Stats PR 9a
Status: in progress

## Scope read

Base `c42e526`; diff = the three committed phases `7685094`, `95e9094`, `becb06d` plus the
uncommitted Phase 3B working tree (`git-status`: 7 docs/plan/evidence files + `test/sustained_high_load_test.dart`).
Layers in scope: core (models, services, signals), docs, test. No `lib/data/`, no `lib/state/`,
no `lib/features/`, no `lib/widgets/`, no framework file, no `watch/`.

Suites re-run by the reviewer (gateway `test`, 8 files): `00:21 +188: All tests passed!`.

## Findings

1. **DOC CLAIMS — checked, no finding.**
   Every test name cited in `docs/signals.md`, `docs/stats_screen.md`,
   `docs/constants_reference.md`, `docs/state_management/services_and_utils.md` and
   `docs/training_load.md` resolves to a real test in the named file (read each test file: rule,
   service, screen, `training_load`, `interference`, `modality_mix_shift`, `protein_consistency`,
   `signals_layer`). Every named type/constant/function exists in `lib/`
   (`kSustainedHighLoad*`, `sustainedHighLoad*`, `WeeklyLoad`, `StatsProgressService.weeklyLoads` /
   `startOfWeekSetting` / `computeMixPeriod`, `OmniDateUtils.startOfWeek`). No doc names Cardio
   Efficiency Drift or any unshipped signal; no doc claims a surface that does not exist.
   `docs/signals.md:70-83` states the render rule the brief requires ("when two cautions qualify
   together the framework draws the higher priority first, so Protein Consistency renders above
   Sustained High Load"), and it is proven by the two-caution screen test.
   - **MINOR | docs/stats_screen.md:148 | "The first is the Progression Rate" reads as registry
     order, but the registry's first entry is now Sustained High Load; the sentence is the
     section's own enumeration (pre-existing — the registry order never matched it, and the plan's
     Assumption Log #16 records it) | non-blocking; consider "the first described here" if
     revisited | @developer**

2. **THE RULE — checked, no finding against D-1705…D-1711.**
   Each candidate `m` is tested against its own baseline (`sustainedHighLoadBaseline` at
   `beforeIndex = n - m`, the twelve weeks strictly before it, sum ÷ 12, empty week = 0); the
   streak is the largest qualifying `m` (`best` overwritten in an ascending loop); the floor of 5
   is applied by the composed rule; 110% and 80% boundaries are inclusive; the rated floor of 8 is
   checked per candidate; the history fact reads the winning candidate's own usual and only weeks
   before its first week; the median is the lower one (`(gaps.length - 1) ~/ 2`). All verified by
   reading and by the green S-2402…S-2409 suite.
   - **MINOR | lib/core/models/sustained_high_load.dart:137-138 | the boundary compares
     `loadMinutes * 100 >= usual * kSustainedHighLoadHigherPercent` where `usual = total / 12`
     (a division then a multiply, two roundings), whereas the sibling PR 8 signals cross-multiply
     totals; a one-ulp flip is possible only when an exact-110% week's baseline total is a
     non-dyadic even integer (e.g. total 2402, week load 220.1833…), which real session loads can
     produce but rarely, and the consequence is a caution card shown or hidden at the exact
     boundary | follow-up only (not this PR): expose the baseline sum and compare
     `loadMinutes * 1200 >= total * 110` | @developer**

3. **THE SERVICE READS — checked, no finding.**
   A week's load is `_sessionSplit(...).loadBySection` summed (`stats_progress_service.dart:584-588`),
   the Mix layer's own definition — no second formula. The week containing `now` is excluded
   (`while weekStart < currentWeekStart`). Empty weeks are present (walk fills `0.0`, `false`).
   Weeks advance with `DateTime(y, m, d + 7)` calendar arithmetic, so DST cannot shift a boundary.
   `startOfWeekSetting()` reads `preferred_start_of_week` through the repository and normalizes
   `'sunday'`/`'sun'` → Sunday, else Monday — identical to `SettingsState`
   (`lib/state/settings/settings_state.dart:159-165, 311-317`).

4. **THE ADAPTER — checked, no finding.**
   Reads only `context.now` and `context.progressService`; returns before the Mix read when
   `streak.weekCount < kSustainedHighLoadMinStreakWeeks`; the gate is
   `computeMixPeriod(fromMs: streak.firstWeekStart!, toMs: context.now)` with
   `measure == MixMeasure.load`.
   - **MINOR | lib/core/services/signals/sustained_high_load_signal.dart:4,30,33,37 | the doc
     comments cite D-1707 for the service read, D-1710 for the Mix payload and D-1711 for the gate,
     and D-1715 for the title; the plan's decisions are D-1703, D-1709 and D-1713 | correct the
     comment references | @developer**

5. **SCOPE — checked, no finding.**
   The diff touches only the phases' Predicted Files plus the disclosed
   `test/interference_signal_screen_test.dart`. That edit is a legitimate isolation fix, not
   coverage loss: PR 7b's F-INT history now also satisfies this rule, so the caution-label check is
   scoped to Interference's own card key, and the two post-dismissal quiet-line assertions were
   removed because "a quiet layer" is not a property of Interference — the sole-card behaviour is
   still asserted by `test/signals_layer_screen_test.dart` `S-1709 dismissing removes the card at
   once` (reviewer re-ran that file: green). The two registry guards changed by one list line each;
   `SustainedHighLoadSignal()` is first in `buildSignalRegistry()`; no framework file, no 8a/8b
   file, no `lib/data/`, no `watch/`. `docs/signals.md` is 39,952 bytes, under the 52,428 ceiling.

6. **TESTS CAN FAIL — one minor gap; the gate is covered.**
   Mutation checks 1–9 are recorded in the evidence file with red→green results (boundary,
   median, incomplete week, empty weeks, registry order, Mix gate, priority order, copy wording,
   causal word). The two screen groups that assert absence are confirmed: mutation check 6 flips
   the adapter's `mixShowsLoad` to `true` and `S-2410(b) … the card does not appear and the layer
   is quiet` goes red — the gate is covered.
   - **MINOR | test/training_load_test.dart:548 | `WeeklyLoad (D-1702) sums its sessions and an
     empty week is zero` has no recorded red run or mutation of its own (it post-dates the Phase 1
     red run, which was the rule file) | non-blocking; a one-line mutation (drop the rated flag or
     the sum) would close it | @developer**
   - **MINOR | test/sustained_high_load_signal_screen_test.dart:670-693 | the `the rule abstains`
     groups (`no history at all`, `a history with no higher-load run`) assert absence, so they are
     green before and after the adapter exists and have no recorded mutation; they are not
     gate coverage — mutation check 6 does not touch them | non-blocking | @developer**

## Verdict

No blockers and no majors. The rule matches D-1705…D-1711, the service reads the shared load
definition through the one history walk and the same start-of-week key/normalisation as
`SettingsState`, the adapter reads only through the progress service and gates on the streak's own
Mix period, the diff stays inside the predicted files plus one disclosed and justified test edit,
and every new behaviour has a green test with recorded red/mutation evidence. The four findings are
minor (two non-blocking doc/comment cleanups, two missing per-test mutation records) and none
changes product behaviour. Approved; the minors can ride as follow-ups.

Status: complete
