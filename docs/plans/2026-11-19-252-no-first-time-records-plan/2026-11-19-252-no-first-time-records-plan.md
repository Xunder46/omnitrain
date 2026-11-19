# Plan 252 — No "New PR" for a first-ever exercise, and the strength record says "est. 1RM"

Review item 16 (owner list: "Records are inflated and unlabelled. A first-ever exercise is a 'New PR' toast and 'New best (was 0 kg)', and the figure is an estimated one-rep max shown as a plain weight. Suggested: no record on a first time; label it 'est. 1RM'").
Phone only (the in-session toast and the post-workout summary). No wire, watch, storage or schema change. The wrist's own "New PR" banner is NOT changed here (open item 1).

## Goal and acceptance

- The first time an exercise is ever logged (no earlier finished workout holds a counted set for it, on that axis), nothing is called a record: no "Congrats! New PR" toast while logging, and no "New best ... (was 0)" line on the post-workout summary. Later sets of that same first workout do not fire a toast either (the history still holds nothing).
- From the second workout on nothing changes: a set that strictly beats the standing best (and the session's running best) fires the toast, and the summary lists it.
- The summary line for a strength record says what the number is: `Bench Press: New best est. 1RM 105 kg (was est. 1RM 100 kg)`. The reps-axis line is unchanged: `Push-Up: New best 20 reps (was 18 reps)`.

Acceptance: S-25201..S-25207 green, the "fails without" ones red at the base commit; the existing tests that pinned a first-time record are rewritten to the new rule; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set; Docs delta applied.

## What the user sees

- Do a new exercise for the first time: no trophy toast, nothing in the summary's records. Do it again next week with more: the toast fires, and the summary says `New best est. 1RM 62.5 kg (was est. 1RM 60 kg)`.
- To SEE it: log an exercise you never did (no toast), finish, repeat it heavier in a new workout (toast, summary line).

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25201 | `WorkoutSessionScreen._maybeShowPRToast`: the weight axis fires only when `standingBest > 0 && newE1rm > standingBest`; the reps axis only when `standingReps > 0 && reps > standingReps`. The throttle maps are untouched (they are updated only when a toast fires). | `workout_session_screen.dart:1130-1165` |
| D-25202 | `SessionSummaryService.computePRs`: both passes require `previousBest > 0` before adding a `PRAchievement` (`if (previousBest > 0 && bestE1RM > previousBest)`; `if (previousBest > 0 && bestReps > previousBest)`). | `session_summary_service.dart:262-322` |
| D-25203 | The summary line text moves to a top-level pure function `prLineText(PRAchievement pr, String Function(double kg) formatWeight)` in `session_summary_screen.dart`, annotated `@visibleForTesting`: the reps axis returns `'${pr.exerciseName}: New best ${pr.newBest.toInt()} reps (was ${pr.previousBest.toInt()} reps)'` (unchanged), any other axis returns `'${pr.exerciseName}: New best est. 1RM ${formatWeight(pr.newBest)} (was est. 1RM ${formatWeight(pr.previousBest)})'`. The screen calls it with `_formatWeight`. | `session_summary_screen.dart:1267-1278` |
| D-25204 | The toast copy stays `Congrats! New PR` (it carries no number to label). | `pr_toast.dart:97,137` |

## Scenarios

Fixtures. History: a finished workout `s1` holding exercise `ex-bench` with one `set` effort and a logged set of 100 kg x 5 (best e1RM 116.7, Epley with the app's cap), and a bodyweight exercise `ex-push` with a finished set of 18 reps and no added weight. Existing PR tests already build these fixtures: copy from `test/in_session_pr_toast_test.dart` (the in-session toast, its harness for the logger) and from `test/services_test.dart` (`computePRs`, lines about 400-440 and 700-730).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25201 | `computePRs` for a session whose exercise has NO earlier finished workout (both an `ex-bench` loaded set and an `ex-push` bodyweight set) | the list is empty | the first workout is reported as a record against 0 |
| S-25202 | the same with history s1 and a better set today (loaded 105 kg x 5; bodyweight 20 reps) | one e1RM `PRAchievement` with `previousBest` above 0 and one reps one (control: the rule stays for real records) | control |
| S-25203 | the logger with NO history: log a 100 kg x 5 set, then a 110 kg x 5 set of the same exercise in the same workout | no `PRToast` snackbar either time | a first-ever set fires the toast |
| S-25204 | the logger WITH history s1 and a 110 kg x 5 set | the toast fires once (control) | control |
| S-25205 | the logger with no history on a bodyweight exercise: 12 reps, then 15 reps; and with history (18 reps): 20 reps | no toast for the first two, one toast for the third | a first-ever rep count fires the toast |
| S-25206 | `prLineText` with an e1RM achievement (`metricLabel: 'e1RM'`, previous 100, new 105) and a `formatWeight` of `(kg) => '$kg kg'` | `Bench: New best est. 1RM 105.0 kg (was est. 1RM 100.0 kg)`; and a reps achievement (`metricLabel: 'reps'`, 18 to 20) gives `Push-Up: New best 20 reps (was 18 reps)` | the weight line is unlabelled |
| S-25207 | the summary screen of S-25201's session | no `New best` text on the screen | the first workout shows a record |

Existing tests that pinned the old rule and must change (the lead has listed them after P1 by running the readers): `test/in_session_pr_toast_test.dart` group `S-001: first-ever strength set fires PR toast` (becomes "does not fire"), `test/services_test.dart` lines asserting `previousBest == 0` records, and any other the readers run shows red.

## Input-reality checklist

1. Writers: sets are written by the logger, Edit Session and the wrist importer; the history read (`getAllTimeBestE1RM`, `getAllTimeBestReps`) is the same one the toast, the summary and Stats use. Units: kg stored, shown in the user's unit by `_formatWeight`.
2. Lifecycle: an exercise whose only earlier workout was deleted is first-ever again; a workout finished before this change keeps no stored PR (PRs are computed, not stored), so nothing needs migrating.
3. Settings: the weight unit setting formats the line (S-25206 injects the formatter).
4. Time: the standing best excludes the running workout, so a second set in a first workout is still first-ever (S-25203).
5. Cost: none (no new read).
6. Words: new copy `New best est. 1RM X (was est. 1RM Y)`; the toast copy is unchanged (owner to read).
7. Competition: the wrist banner "New PR" (watch) still treats an exercise missing from its bests frame as a first-ever record: after this change the phone and the wrist disagree for a first-ever exercise (open item 1); the Stats screen's Recent PRs list is not touched (open item 2).

## Phases

1. **P1 builder-app**, scope `lib/features/session/workout_session_screen.dart`, `lib/core/services/session_summary_service.dart`, `lib/features/session/session_summary_screen.dart`: D-25201..D-25203 (exact code in the brief). No full suite.
2. **P2 lead**: run the readers (`in_session_pr_toast_test`, `pr_toast_test`, `services_test`, `state_test`, `progression_rate_test`, `session_summary_*`) and list the red tests.
3. **P3 builder-app** (after P2), scope the listed existing tests plus `test/no_first_time_records_test.dart` (new): rewrite the old-rule tests to the new rule and add S-25201..S-25207.
4. **P4 lead**: full suite, analyze, mutation pass, docs, reviewer.

## Mutation list (lead)

(a) the toast guard `standingBest > 0` removed (S-25203); (b) the reps guard removed (S-25205); (c) `previousBest > 0` removed from the e1RM pass (S-25201); (d) from the reps pass (S-25201); (e) the label removed (S-25206); (f) the label on the reps line (S-25206); (g) `> 0` turned into `>= 0` in the toast guard (S-25203).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/widget_catalog/session_widgets.md` | MODIFIED | fired on a strict `>` against both the standing best and the session's running best. | fired on a strict `>` against both the standing best and the session's running best, and never for an exercise with no earlier finished workout (a first time is not a record, plan 252). | S-25203, S-25205 |
| `docs/session_summary.md` | MODIFIED | The returned list is collapsed to at most one `PRAchievement` per | A first-ever exercise (no earlier finished workout) produces no `PRAchievement`, and the strength line reads `New best est. 1RM X (was est. 1RM Y)` (plan 252). The returned list is collapsed to at most one `PRAchievement` per | S-25201, S-25206 |

Stale-term sweep (lead): `grep -rIn "New best\|was 0\|first-ever" docs` outside plans, history, releases: `docs/stats_best_load_investigation.md` (a dated investigation that quotes the old line; left as history: it is an investigation snapshot) and `docs/state_management/watch_surface_wrist_logging.md` (the wrist rule, unchanged, open item 1).

## As built

Added after the lead's mutation pass and the review: S-25201b and S-25202b (the reps arm of `computePRs`, which no first test covered) and S-25207b (a summary screen with a real record shows the labelled line: the first S-25207 passed vacuously because its session had no record). The plan's S-25204 is covered by the existing toast tests that already have a standing best (`S-002`-style groups in `in_session_pr_toast_test.dart`); S-25205 was written new (no reps-axis group existed in that file).

## Open items

1. (owner) The watch still shows its "New PR" banner for an exercise the frame omits (a first-ever one): the phone no longer calls it a record. Changing the wrist rule is Swift code that cannot be tested on this machine.
2. (owner) The Stats screen's Recent PRs list is not touched.
3. (owner) The in-session toast copy has no number, so it carries no "est. 1RM" label.
