# Review: 105-consistency · P1, P2a, P2b, P2c, P3 · base..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 2 · minor 0 · tests: 6282 passed / 1 failed (the plan's known flaky red, `routine_save_removes_deleted_rows_test.dart` S-R3) / 2 skipped
Diff vs Predicted Files: outside: `test/modality_mix_shift_signal_screen_test.dart` (finding 2), `docs/README.md` (sanctioned, see Docs delta), `lib/core/services/stats_progress_service.dart` + `test/stats_dst_day_arithmetic_test.dart` (the brief's unrelated dirty files, ignored)

## Findings

1. [Major] `test/consistency_test.dart:207` (`S-17806 at least three sessions last week`) — the floor of 3 (`kConsistencyMinWeekSessions`) is not isolated: `_fixtureLow` has lastWeek 2, total 9, weeks 8, and the average boundary also rejects it (2*8 = 16 < 9+8 = 17), so deleting the floor check would fail no test in the repo. The plan's S-17806 row claims the fixture "fails without the change because the floor of 3 sessions", which it does not establish (the test's own name, "two sessions against an average of about one", overstates: the average is 1.125 and 2 < 2.125). A user would see nothing go wrong today; the risk is a future edit to the boundary silently lowering the floor to 2. Fix: add one fixture where only the floor rejects — lastWeek 2 with a low total (e.g. 2 in W1, 1 in W4, 1 in W7: total 4, weeks 8, 2*8 = 16 ≥ 4+8 = 12) asserting null. Guard: a new test in `consistency_test.dart` that fails if `lastWeek < kConsistencyMinWeekSessions` is removed.
2. [Major] `test/modality_mix_shift_signal_screen_test.dart:626` — an unlisted reader of the changed surface `buildSignalRegistry()`: its structural guard pinned the exact registry id list, and the plan's D-17805 names only `interference_test.dart` and `signals_service_test.dart` as the tests that pin the registry change. The file is now updated in the tree (`seven` → `nine`, `training-gap` first, `consistency` after `progression-rate`) and passes, but no phase's write scope named it; had it been missed the full suite would be red. Fix: none in code (the edit is correct and required); record the third registry-pinning test in D-17805 or the phase table so the next registry change finds it. Guard: already exists (the guard itself).

## Answers to the brief's questions

**Q1 — unlisted production behaviour: none.** `consistency.dart`, `session_history.dart`, both signal files, `signal_registry.dart`, `signal.dart`, `signals_service.dart` and `stats_screen.dart` match the plan's "Exact production code" line for line (constants, thresholds, registry order, `startOfWeek` default `'monday'`, both service methods, both screen call sites). The only other lib change is the other session's `stats_progress_service.dart` (ignored per the brief).

**Q2 — the rules walked:**
- First session inside the running week: `history = 0` → both rules null. Correct.
- First session on the first day of the oldest week: `firstWeekStart` is that day; `history` is exact; the window `[currentWeekStart − 7·weeks, currentWeekStart)` includes that week's sessions. Correct.
- A session dated in the future: `consistency` skips every day `!day.isBefore(currentWeekStart)` (all future days are), and it never touches `_completedHistoryWeeks` (which reads the earliest day); `trainingGap` drops days after today. No wrong count, no wrong week.
- Several sessions on one day: `consistency` counts each (plan item 4); `trainingGap` dedupes to one day. Correct.
- History exactly 6 completed weeks: speaks, `weeks = 6`; exactly 8: `weeks = 8`; more: capped at 8. Correct.
- Sunday start: the setting flows through context → both rules; S-17802 discriminates (the M3 mutant makes the same fixture non-null). Correct.
- A clock change inside the window: `_daysApart` re-reads both dates as UTC; `OmniDateUtils.startOfWeek` builds from calendar components (`date_utils.dart:95`). No 23/25-hour week.
- `now` at 00:00 and at 23:59: both rules read only the local date of `now`; identical results.
- The average includes the last week (S-17801's 2.5 includes the 4), and the copy states the span ("over the last 8 weeks") — that is what the plan fixed, so the copy is accurate to the plan; "your usual" is the 8-week mean including the week being praised.
No input found that gives a wrong count, a wrong week, or a card where the plan says none.

**Q3 — cards together:** `resolveSignals` (`lib/core/models/signals.dart:196`) takes `[cautions.first, positives.first]` when both kinds survive, else the top two of one kind. Training Gap (25) is the lowest caution, so any other qualifying caution displaces it; Consistency (50) sits below Progression Rate (100), so Progression Rate keeps the positive slot. With Training Gap + one other caution and no positive, both render (top two of a kind); with two higher cautions, Training Gap drops. Behaves as the plan says.
Existing screen fixtures: no real card can appear. Tests that inject through the `signals:` seam pass stubs; `pumpStats`'s default is an empty list; the tests that build `StatsScreen` without `signals:` (e.g. `screen_widget_test.dart:3154`) seed sessions at most ~30 days back (`header_standardization_test.dart:2274`), which spans at most 5 completed weeks — below the 6-week history floor both signals require. The suite is green.

**Q4 — assertions satisfied for the wrong reason:** the boundary tests hold on both sides (S-17805: 24 speaks, 25 null; S-17807: 5 fires / 4 null; equals-longest null / strictly-longer fires). S-17802 is not luck (the M3 mutant flips it). S-17803 is a real M4 discriminator. The one wrong-reason case is finding 1 (the floor of 3). A redundancy, not a finding: the `fewer than four session days in the window` fixture is also rejected by the longest-gap rule, but the 4-day floor is isolated by the `no session in the last 56 days` test (without the floor, longest = 0 and the 63-day gap would fire).
Docs: every sentence checked against the code; every cited test name exists verbatim (`the structural guards` › `the caution order holds and the registry is ordered by it` at `interference_test.dart:1077`, `S-17503 which registered signals need rated weeks` at `signals_service_test.dart:367`, all `consistency_test.dart` groups and subtests, `S-17811`/`S-17812` groups, `the registry lists the cautions in strictly ascending priority` at `sustained_high_load_test.dart:271`). The Protein Consistency citation swap away from `modality_mix_shift_signal_screen_test.dart` was necessary and is correct — the old cited test name ("the seven shipped signals") no longer exists.

**Q5 — user-visible text:** none outside the plan. `stats_screen.dart` only passes `startOfWeek`; no existing card's copy changed (no other `lib/` file is touched); neither new card has a suggestion line (`SignalCard` built without one; both adapter tests assert `suggestion` isNull).

## Assumption Log rulings
- Independent-review guards (completed weeks only, 6-week history floor, 5-day gap floor, 3-session floor, dismissal instead of a rest exemption, Consistency below Progression Rate): **ratified** — all present as coded.
- Owner rule (`OmniDateUtils.startOfWeek(date, startOfWeek: 'monday'|'sunday')` is the existing helper): **ratified** — `date_utils.dart:95`, already used by the Mix layer.
- Lead's names and copy defaults (`training-gap`, `Training gap`, no suggestion line): **ratified** — as coded and pinned.

## Docs delta
- docs/signals.md "Six cautions" → "Seven cautions ... Training Gap (`kTrainingGapPriority`)" -> applied
- docs/signals.md priority list gains Training Gap first -> applied
- docs/signals.md "The registered positive is Progression" → "The registered positives are Progression ... and Consistency" -> applied
- docs/signals.md "The seven registered signals" → "The nine registered signals" -> applied
- docs/signals.md ADDED `startOfWeek` pass-through sentence -> applied
- docs/signals_registered.md scope "seven" → "nine" -> applied
- docs/signals_registered.md ADDED `consistency({required sessionStarts` section -> applied
- docs/signals_registered.md ADDED `trainingGap({required sessionStarts` section -> applied
- docs/stats_screen.md "lists seven" → "lists nine" -> applied
- docs/stats_screen.md ADDED "The eighth is the Consistency" -> applied
- docs/stats_screen.md ADDED "The ninth is the Training Gap" -> applied
- docs/theme_and_settings.md "calendar display (`Start of Week`)" → "calendar display and the weeks the Consistency signal counts" -> applied
- Unnamed by the table: `docs/README.md:74` — the index row for `signals_registered.md` ("The seven registered signals" → "The nine registered signals", names added). True and necessary (the keeper's stale-term sweep); sanctioned by the plan's keeper mandate.

## Scenario coverage
S-17801 -> test/consistency_test.dart · `S-17801 consistency, a Monday week` › `four sessions last week against 20 in eight weeks` (+ the observation string in `consistency_signal_test.dart`)
S-17802 -> test/consistency_test.dart · `S-17802 the week ends on the day the setting says`
S-17803 -> test/consistency_test.dart · `S-17803 the running week is never counted`
S-17804 -> test/consistency_test.dart · `S-17804 six completed weeks of history` (both subtests)
S-17805 -> test/consistency_test.dart · `S-17805 exactly one above the average is enough` (both sides)
S-17806 -> test/consistency_test.dart · `S-17806 at least three sessions last week` | floor not isolated (finding 1)
S-17807 -> test/consistency_test.dart · `S-17807 the training gap` (nine subtests)
S-17808 -> test/consistency_test.dart · `S-17808 the copy` (both sentences, plural and singular)
S-17809 -> test/consistency_signal_test.dart · `S-17809 the signals on real sessions — Mock` and `— Hive`
S-17810 -> test/interference_test.dart · `the structural guards` › `the caution order holds and the registry is ordered by it`; test/signals_service_test.dart · `S-17503 which registered signals need rated weeks`; test/modality_mix_shift_signal_screen_test.dart · `the registry` › `lists exactly the nine shipped signals, in order`
S-17811 -> test/signals_service_test.dart · `S-17811 the start of week reaches the signals` (both methods, default and given)
S-17812 -> test/signals_layer_screen_test.dart · `S-17812 the Start of Week setting reaches the signals` (both methods, default and Sunday)
