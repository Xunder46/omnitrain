# 109 — Close the test gaps the Stats analysis found (tests only)

Status: SEEDED by the lead 2026-11-03 (no architect run: tests only; fixtures derived with a throwaway script).
Base commit: `.work/2026-11-03-109-stats-test-gaps/base.txt` (5c882e75). Track: phone only (`test/`, `docs/`). NO `lib/` change.
Unrelated dirty files, never touch: `lib/core/services/stats_progress_service.dart` (another session's DST hunks) and `test/stats_dst_day_arithmetic_test.dart`.
Series: Stats screen analysis 2026-11-03, PR 3 of 4 (section 3, untested behaviours). Owner: "Yes, plan PR 3"; committing is pre-approved when verified (`commit-ok.txt`).
Out of scope: any production change (if a new test shows a real bug, the unit stops and reports), the other analysis items, docs D2-D4, wording W2/W3/W4.

## Goal and acceptance

Nothing changes for a user. After this PR the suite pins six behaviours that were true but unguarded:

1. **T1** A session at local midnight on the first day of the last completed week counts in that week; one at 23:59 the day before counts in the week before; one at midnight on the first day of the running week is not counted. For Monday weeks and for Sunday weeks (Consistency).
2. **T2** The Training Gap's history floor follows Start of Week: the same sessions give a card under a Monday start and none under a Sunday start (a first session on a Sunday opens a new Sunday week but belongs to the previous Monday week). Pinned at the rule and at the signal on Mock and Hive.
3. **T3** A completed session dated after today changes neither card (rule and signal).
4. **T4** The Weight block stays laid out and reachable under the Signals hint and waiting lines at 390x844 with 1.3 text scale (no overflow).
5. **T5** The Hold Progress section filter has its own fixture. Finding: it already has one (`a hold-metric row in another section is ignored`, cardio section, both figures holds, so only the section filter rejects it); the analysis's resistance fixture is the redundant one. No test change; the lead proves it by mutation (M5).
6. The service-level future-session pin already exists (S-18103, plan 107).

## Decision Ledger

| Id | Decision | Where |
|---|---|---|
| D-18301 | Boundary and floor tests for the pure rules go in `test/consistency_test.dart`, with the file's own `_d`/`_now` helpers and a new `_at(month, day, hour, minute)` helper; `now` stays Wednesday 2026-03-18 12:00 local | `consistency_test.dart` |
| D-18302 | The signal-level pins (T2, T3) go in `test/consistency_signal_test.dart` inside its `for (final factory in harnessFactories)` loop (Mock AND Hive); they use its `_seed`, `_clearSessions` and `_context(repo, startOfWeek: ...)` | `consistency_signal_test.dart` |
| D-18303 | The layout pin (T4) goes in `test/weight_trend_screen_test.dart` (its seeds and harness loop), passes no `signals` so the real registry runs (the gate is unmet with one unrated session, so the locked line, its hint and real waiting lines render), and runs on both harnesses (it only reads) | `weight_trend_screen_test.dart` |
| D-18304 | Scenario ids S-18301..S-18307 (grep: free) | all |
| D-18305 | Proof: the lead's mutations M1-M6 on `lib/`; no prover (new tests do not exist at the base). A mutation that survives gets a closed tests-only fix brief | Assumption Log |
| D-18306 | The docs sentences are written by the lead (three small edits in `docs/signals_registered.md`, which has room: 48 KB) | Docs delta |

## Scenarios (fixtures derived with a throwaway script mirroring the rule)

`now` = Wed 2026-03-18 12:00. Monday weeks: running week starts Mon Mar 16, last week Mar 9-15. Sunday weeks: running week starts Sun Mar 15, last week Sun Mar 8 - Sat Mar 14.
`_at(m, d, h, mi)` = `DateTime(2026, m, d, h, mi)`. Base sets: **baseM** = the 16 noon sessions Jan 20, 21, 22, 23, 27, 29, Feb 3, 5, 10, 12, 17, 19, 24, 26, Mar 3, 5. **baseS** = the 14 noon sessions Jan 20, 22, 27, 29, Feb 3, 5, 10, 12, 17, 19, 24, 26, Mar 3, 5.

| Id | Fixture | Expect | Fails without the guard because |
|---|---|---|---|
| S-18301 | Monday. A: baseM + Mar 9 00:00, Mar 11 12:00, Mar 13 12:00, Mar 15 23:59, Mar 16 00:00. B: the same without the Mar 9 00:00 session. C: baseM + Mar 8 23:59, Mar 10, 11, 13 (12:00), Mar 15 23:59 | A: `lastWeekSessions` 4, `weeks` 8, `totalSessions` 20 (the Mar 16 00:00 session is the running week). B: null. C: `lastWeekSessions` 4, `totalSessions` 21 (the Mar 8 23:59 session is in the week before) | a boundary shifted one way drops Mar 9 00:00 (A fails or B passes by accident), the other way counts Mar 8 23:59 (C's 4 becomes 5) |
| S-18302 | Sunday. A: baseS + Mar 8 00:00, Mar 10 12:00, Mar 12 12:00, Mar 14 23:59, Mar 15 00:00. B: A without Mar 8 00:00. C: baseS + Mar 7 23:59, Mar 10, 11, 12 (12:00), Mar 14 23:59. D: fixture A read as Monday | A: 4 / 8 / 18. B: null. C: 4 / 8 / 19. D: 4 / 8 / 19 (not 18: the same sessions give another total under the other setting) | the same boundary under the Sunday week; D catches a rule that ignores the setting |
| S-18303 | Training Gap rule. Eleven session days every 3 days from Sun Feb 8 (Feb 8, 11, 14, ... Mar 10), noon; `now` = Mar 18 | Monday: a result, `days` 8, `longestBefore` 3. Sunday: null (five completed Sunday weeks of history). A second set of eleven days every 3 days from Sun Feb 1 (Feb 1, 4, ... Mar 3): both settings give a result (`days` 15, `longestBefore` 3) | the floor counted on the wrong week start (M2) |
| S-18304 | Rule level. Fixture G (`consistency_test.dart`) plus session days Mar 19, Mar 20 (after `now`) for the gap; fixture A plus Mar 19, 20, 21 for Consistency | the gap result equals fixture G's (`days` 6, `longestBefore` 3); the Consistency result equals fixture A's (4 / 8 / 20) | the future day filter in `trainingGap` (M3) |
| S-18305 | Signal level, Mock and Hive. The 11 sessions of S-18303 (Sunday-start set) seeded as completed noon sessions; `TrainingGapSignal.evaluate` with `_context(repo)` and with `_context(repo, startOfWeek: 'sunday')` | Monday: a card with `No session in 8 days, longer than any gap in your last 8 weeks (the longest was 3 days).`; Sunday: null | the signal passes `monday` to the rule whatever the setting (M2) |
| S-18306 | Signal level, Mock and Hive. Fixture G plus a completed session on Mar 20 12:00 (after `now`): Training Gap card text equals the no-future card; fixture A plus completed sessions Mar 19-21: the Consistency card equals the no-future card | cards identical | the future filter in the rule and in `completedSessionStarts` (M3, M4) |
| S-18307 | Weight block layout, Mock and Hive. One completed session 3 days ago, weights 80.8 kg 27 days ago and 80.2 kg today, one food row (as `two weigh-ins 27 days apart` seeds); Stats pumped at 390x844 with text scale 1.3, the real signal registry | no exception; `signals_locked` and its hint and at least one `signals_waiting_*` line are on screen; after `scrollUntilVisible` the `weight_trend` block is found, its line reads `80.2 kg, −0.6 kg over 4 weeks`, and its bottom edge is inside the 844 dp viewport | the stack overflows or the Weight row is unreachable at a phone width (no mutation: a layout guard; the lead checks it also fails when the viewport is narrowed to 200 dp wide in a throwaway probe) |

## Phases

| Phase | Agent | Write scope | Items | Order |
|---|---|---|---|---|
| P1 | crew-builder-app | `test/consistency_test.dart` | S-18301..S-18304 | parallel with P2, P3 |
| P2 | crew-builder-app | `test/consistency_signal_test.dart` | S-18305, S-18306 | parallel with P1, P3 |
| P3 | crew-builder-app | `test/weight_trend_screen_test.dart` | S-18307 | parallel with P1, P2 |
| P4 | the lead | `docs/signals_registered.md` | the Docs delta rows | after P1-P3 |
| P5 | crew-reviewer | the plan's `.review.md` | five narrow questions | after P4 |

Done criteria: touched test files green with real counts (each builder runs its own file only); `flutter analyze` not above 181; full `flutter test` green apart from the known flaky red (S-R3); invariant grep clean; `docs_indexing_contract_test.dart` green; `plan-lint.py after` clean.
Mutations (lead, one at a time): M1 `consistency.dart` `if (!day.isBefore(lastWeekStart)) lastWeek++;` to `if (day.isAfter(lastWeekStart)) lastWeek++;`; M1b the same line to `!day.isBefore(lastWeekStart.subtract(const Duration(days: 1)))`;
M2 `training_gap_signal.dart` `startOfWeek: context.startOfWeek,` to `startOfWeek: 'monday',`; M2b `consistency.dart` inside `trainingGap` the `_completedHistoryWeeks(days, currentWeekStart, startOfWeek)` argument `startOfWeek` to `'monday'`;
M3 `consistency.dart` drop `.where((day) => !day.isAfter(today))` in `trainingGap`; M4 `stats_progress_service.dart` `completedSessionStarts` drop `&&\n            session.startedAtMs <= nowMs` (already killed by S-18103; re-run to confirm);
M5 `hold_progress.dart` drop `if (section.section != ExerciseSection.isometric) continue;` (T5).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/signals_registered.md | ADDED | - | `S-18301 a session at midnight belongs to its own | S-18301 |
| docs/signals_registered.md | MODIFIED | `startOfWeek` setting. Verified by `test/consistency_test.dart` (`S-17807 the | `S-18303 the Training Gap history floor follows Start of Week`) and | S-18303 |
| docs/signals_registered.md | ADDED | - | group `S-18304 a | S-18304 |

The sentences: the completed-weeks bullet also cites the Monday and Sunday midnight-boundary groups (S-18301, S-18302); the Training Gap history-floor bullet cites S-18303 (rule) and S-18305 (signal); a one-sentence addition to the Consistency/Training Gap definitions says a session dated after today changes neither card (S-18304, S-18306).

## Progress

- [x] P1 rule tests
- [x] P2 signal tests
- [x] P3 Weight layout test
- [x] P4 docs sentences
- [x] P5 review
- [x] lead: verify, mutations, full suite

## Assumption Log

- 2026-11-03 lead: T5 needs no change: `test/hold_progress_test.dart` already holds `a hold-metric row in another section is ignored` (cardio section, both figures are holds), which only the section filter rejects. The analysis's resistance fixture is redundant; the lead proves the filter by mutation M5.
- 2026-11-03 lead: tests-only; no prover (the new scenarios do not exist at the base); the lead's mutations stand in (D-18305).
- 2026-11-03 lead: S-18307 deviates from D-18303. The real registry shows no card while the gate is unmet with this seed, so `signals_locked_hint` (rendered only with a card) would never appear; the test passes a stub signal (`_StackSignal`: speaks without rated weeks, one waiting line) to build the tallest real stack: card + hint + waiting line + Weight block. It scrolls to the end and asserts the block's line and bottom edge; the overflow guard is `takeException()`, which fails at a 150 dp width (probe, removed).
- 2026-11-03 lead: results. Mutations M1, M1b, M2, M2b, M3, M4, M5 and four boundary mutants (`gap <= longest`, `gap < MinDays`, `inWindow.length < MinSessionDays`, `lastWeek < MinWeekSessions`) each failed a test; three needed closed fix rounds (round 1: S-18307 premise; round 2: a Saturday-first-session fixture for M2b; round 3: exactly-four-session-days and exactly-three-sessions-last-week for the last two boundary mutants). M4 is killed by S-18103 (plan 107), not by this unit's tests: the rule's own future-day filter masks it at signal level. The review's claim that `gap <= longest` and `gap < MinDays` survive was wrong (existing S-17807 tests kill them); its other two survivors were real and are closed by round 3.
