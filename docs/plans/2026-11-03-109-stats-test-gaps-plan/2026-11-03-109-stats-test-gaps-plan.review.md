# Review: 109-stats-test-gaps · P1-P4 · 5c882e75..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 1 · tests: not run (brief: no full suite; targeted suites green, `flutter analyze` at the baseline 181)
Diff vs Predicted Files: conforms — `test/consistency_test.dart`, `test/consistency_signal_test.dart`, `test/weight_trend_screen_test.dart`, `docs/signals_registered.md`; the only dirty `lib/` file is `lib/core/services/stats_progress_service.dart` (another session's DST work, declared out of scope in the plan).

## Findings

1. [Minor] `docs/plans/...-plan.md` D-18303 and the S-18307 fixture column — the plan says the layout test "passes no `signals` so the real registry runs", but `test/weight_trend_screen_test.dart:322` passes `signals: [_StackSignal()]`. The deviation is justified (with this sparse seed the real registry produces no card, so `signals_locked_hint` — rendered only when `cards.isNotEmpty && lockedRatedWeeks != null`, `signals_layer.dart:139` — would never appear and T4's "under the Signals hint" could not be pinned), and the brief endorses it; but neither D-18303 nor the Assumption Log records it, so the plan no longer describes the code. Fix: one Assumption Log entry (or an amended D-18303) naming the stub and the reason. Guard: none (plan text).

## Answers to the brief's questions

1. **Yes, and no wrong-reason pass.** Verified against `lib/core/models/consistency.dart` arithmetic: Monday A = 4 last-week (Mar 9, 11, 13, 15; Mar 16 00:00 excluded by `!day.isBefore(currentWeekStart)`), 8 weeks (first day Jan 20 → Monday week start Jan 19, 56 days), 20 total; C puts Mar 8 23:59 in the window but not the last week (21 total). Sunday A = 4/8/18, C = 4/8/19, D (A's sessions read as Monday) = 4/8/19 — A vs D pins the setting. The history floor reads only the earliest day (Jan 20 in every fixture), so the added boundary sessions cannot influence `weeks`; `lastWeekSessions`, `weeks` and `totalSessions` are all asserted, so a session landing in the wrong bucket fails a number. M1 is killed by A (lastWeek 3 → null), M1b by C (lastWeek 5).
2. **Yes.** Both new groups sit inside the `for (final factory in harnessFactories)` loop (Mock and Hive), each with its own `setUp` (`harness.open()` + `_clearSessions`) and `tearDown` (`harness.close()`), so no sessions leak between tests. `_seed` builds unique ids from the epoch ms (plus suffixes for the future sessions).
3. **Fair reading, weak-but-not-vacuous bottom edge.** The stub has `needsRatedWeeks = false` (so it is evaluated while the gate is unmet), returns a card (→ `signal_card_stack-1`), and `waitingFor` returns a line (→ `signals_waiting_0`); with the gate unmet `lockedRatedWeeks` is non-null, so `signals_locked_hint` renders — exactly the "hint + waiting lines + card" stack T4 names. The real registry cannot produce that stack with one session, two weigh-ins and one food row, so the stub is the only way to pin it. The final `getBottomLeft(...).dy <= 844` after a clamped full scroll is nearly always true once the block is found (at max scroll the last block's bottom sits at the viewport bottom), so it is a reachability check, not an overflow check; the overflow guard is the two `takeException()` assertions, which the lead proved have teeth (RenderFlex overflowed at 150 dp). Acceptable as pinned.
4. **Yes, clause by clause.** All cited groups exist verbatim: `S-18301 a session at midnight belongs to its own Monday week` and `S-18302 ... Sunday week` (`test/consistency_test.dart:277,322`), `S-18303 the Training Gap history floor follows Start of Week` (:367), `S-18304 a session dated after now changes neither rule` (:431), `S-18305 the Training Gap signal follows Start of Week` and `S-18306 a session dated after now changes neither card` (`test/consistency_signal_test.dart:183,225`), and the retained `S-17807 the training gap` › `five completed weeks of history is too little` (:186,226). The sentences are true: the midnight/23:59 sentence matches S-18301/S-18302's assertions; "the same sessions can pass under one start and fall short under the other" matches S-18303 (Monday: card, Sunday: null); "a completed session dated after today changes neither card" matches S-18304/S-18306 (identical observation strings, which the pre-existing S-17809 tests pin for the no-future fixtures).

   Docs delta:
   - docs/signals_registered.md ADDED (midnight/23:59 sentence, Consistency bullet) -> applied
   - docs/signals_registered.md MODIFIED (Training Gap history-floor bullet) -> applied
   - docs/signals_registered.md ADDED ("Sessions after today" bullet) -> applied
   - Doc edits the table does not name: the `S-18302` citation inside row 1's sentence, the `S-18305` citation inside row 2, the `S-18306` citation inside row 3's bullet — all applied.
5. **Survivors.**
   - M4 (`completedSessionStarts` drops `startedAtMs <= nowMs`, `stats_progress_service.dart:161`) survives **all new tests**: the rule's own `.where((day) => !day.isAfter(today))` masks it in both signals. The plan's S-18306 row credits "M3, M4"; only M3 is killed by the new tests — M4 rests on the pre-existing S-18103 service test (plan 107), as the plan's mutation list itself notes.
   - `trainingGap`'s `if (gap <= longest) return null` → `<`: no fixture has the current gap equal to the longest previous gap, so it survives all tests.
   - Constant-boundary mutants with no fixture on the boundary: `gap < kTrainingGapMinDays` → `<=` (no 5-day-gap fixture), `inWindow.length < kTrainingGapMinSessionDays` → `<=` (no exactly-4-session-day fixture), `lastWeek < kConsistencyMinWeekSessions` → `<=` (no fixture with lastWeek 3 and a passing average — S-18301 B's 3 sessions fail on the average condition instead). The history-floor boundary (`kConsistencyMinHistoryWeeks`, exactly 6) **is** pinned by S-18303's Monday case.

## Assumption Log rulings
- T5 needs no change (cardio-section fixture in `test/hold_progress_test.dart:139`): **ratified** — the test exists and its comment states only the section filter rejects it.
- Tests-only, no prover, the lead's mutations stand in (D-18305): **ratified** — consistent with the brief's mutation results; no production change in the diff.

## Scenario coverage
S-18301 -> test/consistency_test.dart · group `S-18301 a session at midnight belongs to its own Monday week` (3 tests)
S-18302 -> test/consistency_test.dart · group `S-18302 a session at midnight belongs to its own Sunday week` (4 tests)
S-18303 -> test/consistency_test.dart · group `S-18303 the Training Gap history floor follows Start of Week` (3 tests)
S-18304 -> test/consistency_test.dart · group `S-18304 a session dated after now changes neither rule` (2 tests)
S-18305 -> test/consistency_signal_test.dart · group `S-18305 the Training Gap signal follows Start of Week — <harness>` (2 tests × Mock + Hive)
S-18306 -> test/consistency_signal_test.dart · group `S-18306 a session dated after now changes neither card — <harness>` (2 tests × Mock + Hive)
S-18307 -> test/weight_trend_screen_test.dart · group `S-18307 the Weight block under the Signals lines at a phone width — <harness>` (1 testWidgets × Mock + Hive)
T5 -> no change, covered by the existing `test/hold_progress_test.dart` · `a hold-metric row in another section is ignored` (per plan and Assumption Log)
S-18103 -> pre-existing (plan 107), untouched by this diff

## Resolution (lead, 2026-11-03)

Finding 1 (Minor): the S-18307 stub deviation is recorded in the plan's Assumption Log. Survivors in the answer to question 5: `gap <= longest` and `gap < kTrainingGapMinDays` are killed by existing S-17807 tests (mutated and observed red); `inWindow.length < kTrainingGapMinSessionDays` and `lastWeek < kConsistencyMinWeekSessions` were real survivors, closed in fix round 3 (observed red under mutation, green after). M4 stays covered by S-18103 (plan 107).
