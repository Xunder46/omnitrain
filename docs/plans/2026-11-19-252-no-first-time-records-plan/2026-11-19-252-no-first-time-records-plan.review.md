# Review: plan 252 (no record for a first-ever exercise, "est. 1RM" label) · P1–P4 · 31436d3f..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: not run this run (brief forbids the full `flutter test`; lead-reported: PR tests 106 pass, analyze baseline 178 / 0 errors, 8 mutants killed)
Diff vs Predicted Files: outside: `test/food_catalog_load_test.dart` (see Finding 2)

## Findings
1. [Major] `test/no_first_time_records_test.dart:94` — S-25207 is the only summary-screen test in the diff and its session produces no record, so `expect(find.textContaining('New best'), findsNothing)` (line 185) passes vacuously if the screen's record rendering breaks or if `session_summary_screen.dart:1509` reverts to the old inline unlabelled expression instead of calling `prLineText` (with no record in the fixture there is no line either way). Mutants (e)/(f) are killed only at the `prLineText` unit level (S-25206); no wiring mutant has a prove-red verdict in the brief — unproven. A user would see the unlabelled `New best 105.0 kg (was 100.0 kg)` line again with every PR test green. Fix: one widget test whose session beats an earlier lower best, asserting the rendered line contains `est. 1RM`. Guard: summary screen of a real record shows the labelled line.
2. [Minor] `test/food_catalog_load_test.dart:270` — outside the plan's Predicted Files and unexplained: `byId['chicken_thigh']!.fat!` became `byId['chicken_thigh']!.fat`. `fat` is non-nullable (`lib/core/models/food_draft.dart:28`), so behaviour is identical; plausibly a dead-null-aware lint fix for the analyze baseline. The plan does not say why the file changed. Fix: governor/lead records the edit in the plan (or reverts it if the baseline holds without it).

## Assumption Log rulings
No Assumption Log section exists in the plan; nothing to rule on. Rulings on the plan's stated leftovers:
- `docs/stats_best_load_investigation.md` (quotes the old unlabelled line, :175, :284-291) — RATIFIED: the file carries a frozen-history banner ("where it disagrees with `lib/`, `lib/` wins").
- `docs/state_management/watch_surface_wrist_logging.md:392-399` ("the rule is the phone's toast, mirrored"; absent exercise is a first-ever record) — RATIFIED as stale-but-owned: the wrist rule is plan Open item 1 (Swift, untestable here); the mirroring sentence is now only half true and should be reworded when item 1 lands.
- NOT changed on purpose (wrist banner, Stats Recent PRs, toast copy) — confirmed by code below; open items 1-3 stand.

## Brief questions
1. Surfaces still treating `previousBest == 0` as a record: (a) the Stats screen's Recent PRs — `stats_progress_service.dart:415-441` (`computeProgressData`'s PR loops start at `bestSoFar = 0`, so the first positive day is a `StatsPR`; rendered by `lib/features/stats/widgets/recent_pr_list.dart`): first-ever day is listed, documented open item 2. (b) the wrist: `getAllTimeBests` (`stats_progress_service.dart:2564`) sends only bests above 0 and the wrist treats an absent exercise as first-ever (`watch_surface_wrist_logging.md:399`; builder caller `watch_sync_request_handler.dart:337`, `watch_reference_sync.dart:783`), documented open item 1. No in-session "PR" chip exists in `lib` (searched `PRAchievement`, `New PR`). Phone/wrist disagreement beyond the wrist banner: none undocumented — but phone-internal: toast/summary now say "not a record" while the same phone's Stats Recent PRs lists the first-ever day (documented open item 2, not a finding).
2. `StatsProgressService.getAllTimeBestE1RM` (`stats_progress_service.dart:2452`) has no try/catch: a repository read failure throws out of the call, it never returns 0 on error. The same read (and the same uncaught path through `_maybeShowPRToast`, awaited from `_logSet` at `workout_session_screen.dart:1026`) existed before the change, so the hypothesised "history but failed read silently loses its toast" does not arise from this diff — error behaviour is unchanged (the throw aborts `_logSet` before and after alike).
3. Tiny-but-real previous best (e.g. a logged 0.5 kg set): `> 0` fires a genuine record against it — per the plan that is correct from the second workout on; no defect. A bodyweight exercise whose only earlier workout logged 0 reps: `getAllTimeBestReps` only counts `reps > best` over weight-0 sets, so a 0-rep set never raises the best and the exercise stays first-ever on the reps axis — matches the plan's "no counted set" definition.
4. All new/rewritten assertions are behavioural: S-25201/S-25201b `expect(prs, isEmpty)`, S-25203/S-25205a `findsNothing` on `Congrats! New PR`, S-25207 `findsNothing` on `New best` — each fails if a first-ever set fired or was listed. No assertion passes in those cases. The one gap is the wiring in Finding 1 (passes when the screen never renders any record line).
5. Doc sentences: `docs/widget_catalog/session_widgets.md:557` and `docs/session_summary.md:441` match the code (`previousBest > 0 &&` guards at `session_summary_service.dart:276,317`; `prLineText` at `session_summary_screen.dart:1509-1514`), and every named test/ID exists (`S-25203`, `S-25205`, `S-25201`, `S-25206` in the named files). No other current doc sentence outside `docs/plans`, the frozen-history file and the wrist doc (open item 1) is now false.

## Docs delta
`docs/widget_catalog/session_widgets.md` MODIFIED -> applied (line 557; names existing tests)
`docs/session_summary.md` MODIFIED -> applied (line 441; names existing `prLineText`/S-25201/S-25206)
Doc edit the table does not name: none in the diff.

## Scenario coverage
S-25201 -> `test/services_test.dart` · "S-25201 an exercise with no previous best is not a PR" (+ "S-25201b" reps arm)
S-25202 -> `test/services_test.dart` · "S-25202 a better set over a lower prior best..." (+ "S-25202b" reps arm)
S-25203 -> `test/in_session_pr_toast_test.dart` · "S-25203 (was S-001a): no prior history → the first logged set fires NO toast"
S-25204 -> `test/in_session_pr_toast_test.dart` · group "S-002: a set beating the prior best fires the toast" (control; S-008a and S-010a reseeded with a lower prior best)
S-25205 -> `test/in_session_pr_toast_test.dart` · "S-25205a" (no history, no toast) + "S-25205b" (prior 18 reps, one toast)
S-25206 -> `test/no_first_time_records_test.dart` · "S-25206 prLineText labels a strength record est. 1RM..."
S-25207 -> `test/no_first_time_records_test.dart` · "S-25207 the summary of a first-ever workout shows no New best line" (vacuous-pass risk: Finding 1)

## Verified facts this run
- Lib diff matches D-25201 (`workout_session_screen.dart:1142,1161`), D-25202 (`session_summary_service.dart:276,317`), D-25203 (`session_summary_screen.dart:1509-1514`, `@visibleForTesting` top-level function); toast copy untouched (`pr_toast.dart:97,137`).
- Test helpers named by the new tests exist: `_seedCompletedSetSession`/`_freshRepo` (`in_session_pr_toast_test.dart:36,44`), `pumpLiveSessionScreen` (`:1441`), `_appTheme` copy is faithful to `session_summary_effort_row_test.dart:31-46`; `PRAchievement.metricLabel` exists (`session_summary.dart:116`); `SessionSummaryScreen` params at `:68-75`.
- No allowlist entry added, no ratchet raised, no raw UI piece introduced (diff touches no widget construction).

## Lead dispositions

1. Major (S-25207 passed vacuously, the screen wiring untested): FIXED. S-25207b shows a real record on the summary screen and asserts the labelled line; the wiring mutant (the screen reverting to the unlabelled text) is killed.
2. Minor `test/food_catalog_load_test.dart:270`: not this plan's change; already modified before the unit started (the owner's), left unstaged.
