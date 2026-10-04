# Evidence — Stats PR 8h (housekeeping)

Plan: `2026-10-03-08h-stats-pr8h-housekeeping-plan.md`. Review findings go in
`2026-10-03-08h-stats-pr8h-housekeeping-plan.review.md`.

Executors write here, never into the plan: baselines, suite summaries, red→green tables, mutation pairs,
the measured doc sizes. Append a dated section per run; never rewrite an earlier one.

## Opening measurement

| Command | Result |
|---|---|
| `flutter analyze` | `196 issues found.` (ran in 2.9s), 0 errors |
| `flutter test` | `+3635 ~1: All tests passed!` |

Run 2026-10-03 on `develop` at `2b6e8e5`; 8a and 8b had **not** merged, so the Done Criteria below are
compared against these numbers, and they match the pre-8a numbers recorded in the plan exactly. The final
run in this phase is `+3637 ~1` — the same suite plus this phase's two new guards.

## Phase 1 — the two derivations, their guards, and the plan-file bookkeeping

### Red runs (guards written before the derivations)

Run 2026-10-03, before either derivation existed:

`.github/copilot/scripts/macos/gateway.sh test test/interference_test.dart test/modality_mix_shift_test.dart`

| Suite | Test | Observed |
|---|---|---|
| `test/modality_mix_shift_test.dart` — S-2302's stripped-source scan | `the structural guards the Mix period is derived from its constant` | FAIL — `Expected: false / Actual: <true>` at `test/modality_mix_shift_test.dart 434:7`, reason "the Mix period must be derived from kModalityMixShiftPeriodDays, not written as a literal" |
| `test/interference_test.dart` — S-2301's stripped-source scan | `the structural guards the sports-load window is derived from its constant` | FAIL — `Expected: false / Actual: <true>` at `test/interference_test.dart 1229:7`, reason "the sports-load span must be derived from kInterferenceSportsLoadWindowDays, not written as a literal" |

Summary line: `00:00 +52 -2: Some tests failed.` Both failures are the new scans; every pre-existing test passed.

### Green runs

Run 2026-10-03, after both derivations:

`.github/copilot/scripts/macos/gateway.sh test test/interference_test.dart test/modality_mix_shift_test.dart test/interference_signal_screen_test.dart test/modality_mix_shift_signal_screen_test.dart test/progression_rate_test.dart test/progression_samples_service_test.dart test/signals_layer_screen_test.dart`

| Suite | Command | Output |
|---|---|---|
| `test/interference_test.dart` — S-2301's scan | (in the 7-suite command above) | PASS |
| `test/modality_mix_shift_test.dart` — S-2302's scan | (in the 7-suite command above) | PASS |
| All 7 suites | the command above | `00:04 +146: All tests passed!` (exit 0) |

### Byte-identity check (the rendered strings must not move)

Every assertion below ran **unmodified** in the green run above; none was edited.

| Assertion | Suite | Before | After |
|---|---|---|---|
| `endsWith('Sports load is up 30% over the last 3 weeks.')` | `test/interference_test.dart` | pass | pass (unmodified) |
| `'is up 38% over the last 3 weeks.'` | `test/interference_test.dart` | pass | pass (unmodified) |
| `'over the last 3 weeks.'` | `test/interference_signal_screen_test.dart` | pass | pass (unmodified) |
| `'… over the last 4 weeks, down from its usual …'` (six assertions) | `test/modality_mix_shift_test.dart` | pass | pass (unmodified) |
| `'Isometric is 3% of your load over the last 4 weeks, down from'` | `test/modality_mix_shift_signal_screen_test.dart` | pass | pass (unmodified) |

All six rows pass **unmodified**. A changed expectation would be a defect in the derivation.

### Mutation pairs (each applied, observed, restored, re-run green)

The exact line to restore after each mutation, recorded before editing:

- (a)/(b) `lib/core/models/interference.dart`: `      '${kInterferenceSportsLoadWindowDays ~/ 7} weeks.',`
- (c) `lib/core/models/modality_mix_shift.dart`: `    'last ${kModalityMixShiftPeriodDays ~/ 7} weeks, down from its usual '`

| # | File | Mutation | Test that must fail | Observed | Restored |
|---|---|---|---|---|---|
| (a) | `lib/core/models/interference.dart` | restore the `3 weeks` literal | S-2301's scan | FAIL — `Expected: false / Actual: <true>` at `test/interference_test.dart 1229:7`; `+34 -1: Some tests failed.` | yes — re-run `+35: All tests passed!` |
| (b) | `lib/core/models/interference.dart` | `kInterferenceSportsLoadWindowDays ~/ 7` → `~/ 14` | `test/interference_test.dart`'s `over the last 3 weeks.` assertion | FAIL — S-2001 exact copy (`... over the last 1 weeks.` at 536:7) and S-2007(a) `endsWith` (`... over the last 1 weeks.` at 767:7); `+32 -3: Some tests failed.` | yes — re-run (with (c)'s restore) `+54: All tests passed!` |
| (c) | `lib/core/models/modality_mix_shift.dart` | restore the `4 weeks` literal | S-2302's scan | FAIL — `Expected: false / Actual: <true>` at `test/modality_mix_shift_test.dart 434:7`; `+18 -1: Some tests failed.` | yes — re-run (with (b)'s restore) `+54: All tests passed!` |

No step ended with a mutation applied: the final combined run of both suites is `00:00 +54: All tests passed!`.

### Plan-file edits (S-2303)

| File | Line changed | Before | After |
|---|---|---|---|
| `docs/plans/2026-10-03-07-stats-pr7-index.md` | status line | `READY (planner) — neither half started.` | `DONE — 7a shipped as \`b3b91fa\`, 7b shipped as \`2b6e8e5\`.` |
| `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/…md` | status line | `READY (planner) — not started.` | `DONE — shipped as \`b3b91fa\`.` |
| `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/…md` | status line | `READY (planner) — not started.` | `DONE — shipped as \`2b6e8e5\`.` |
| `docs/plans/2026-10-03-06b-stats-pr6b-progression-rate-plan/…md` | status line | `READY (planner) — not started; blocked on 6a` | `DONE` |
| 7a / 7b open questions answered by the owner on 2026-10-03 | 7a **O-1**, **O-2**; 7b **O-1**, **O-5** — status cell only | `Defaulted — **owner to confirm**; vetoable` | 7a O-1/O-2 → `**Answered 2026-10-03: owner kept the shipped wording**`; 7b O-1/O-5 → `**Answered 2026-10-03: owner confirmed the default**` |
| open questions the brief records no answer for | rows left untouched (count) | — | 6 rows unchanged — 7a O-3, O-4, O-5 and 7b O-2, O-3, O-4. 6b has no Open questions table at all, so no row could be marked (the plan's A-2). |

Nothing else in any of the four files moved: the four diffs are one status line each, plus four
open-question status cells in 7a and 7b. No Ledger, scenario, Progress or Next-handoff line changed.

### Doc sizes (H-3 / D-1605 — measured only, nothing edited)

64 KiB = 65,536 bytes; `test/docs_indexing_contract_test.dart` warns past 80% (52,429 bytes).
Measured 2026-10-03 by `dart:io` `lengthSync()` over every `docs/**/*.md` (see the plan's A-3). Nothing
was edited; this is a measurement only.

| Doc | Bytes | % of ceiling |
|---|---|---|
| `docs/README.md` | 20069 | 30.6% |
| `docs/app_philosophy.md` | 8217 | 12.5% |
| `docs/calendar_periods.md` | 10179 | 15.5% |
| `docs/constants_reference.md` | 18993 | 29.0% |
| `docs/create_new_exercise.md` | 4003 | 6.1% |
| `docs/data_models.md` | 39424 | 60.2% |
| `docs/db_integration.md` | 37326 | 57.0% |
| `docs/design_system.md` | 27825 | 42.5% |
| `docs/distance_source.md` | 10287 | 15.7% |
| `docs/docs-audit-2026-07-26.md` | 15772 | 24.1% |
| `docs/documentation_standard.md` | 11313 | 17.3% |
| `docs/exercise_info_and_notes.md` | 5183 | 7.9% |
| `docs/exercise_ranking.md` | 4338 | 6.6% |
| `docs/future-work.md` | 2615 | 4.0% |
| `docs/global_conventions.md` | 4174 | 6.4% |
| `docs/history/feedback-pack-baseline-2026-07-27.md` | 7596 | 11.6% |
| `docs/history/route-migration-audit.md` | 14598 | 22.3% |
| `docs/memories/category-unification.md` | 2215 | 3.4% |
| `docs/modality_based_exercise_ui.md` | 22076 | 33.7% |
| `docs/modality_tracking.md` | 21690 | 33.1% |
| `docs/my_routines.md` | 20505 | 31.3% |
| `docs/navigation_and_screens.md` | 25191 | 38.4% |
| `docs/navigation_contract.md` | 5567 | 8.5% |
| `docs/nutrition.md` | 14320 | 21.9% |
| `docs/plans/2026-07-13-01-pr1-crash-reporting-plan.md` | 16743 | 25.5% |
| `docs/plans/2026-07-13-02-pr2a-seeded-demo-programs-plan.md` | 9704 | 14.8% |
| `docs/plans/2026-07-13-03-pr2b-descriptive-log-analytics-plan.md` | 31360 | 47.9% |
| `docs/plans/2026-07-13-04-pr3-platform-health-integration-plan.md` | 21791 | 33.3% |
| `docs/plans/2026-07-13-05-pr4-watch-phone-sync-protocol-plan.md` | 14243 | 21.7% |
| `docs/plans/2026-07-13-06-a1-watch-session-engine-plan.md` | 12582 | 19.2% |
| `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md` | 15103 | 23.0% |
| `docs/plans/2026-07-13-08-b-watch-session-start-paths-plan.md` | 16503 | 25.2% |
| `docs/plans/2026-07-13-09-c1-live-session-mirroring-plan.md` | 13774 | 21.0% |
| `docs/plans/2026-07-13-10-c2-phone-manage-bridge-live-sessions-plan.md` | 13486 | 20.6% |
| `docs/plans/2026-07-13-11-d-watch-sensor-recording-plan.md` | 21574 | 32.9% |
| `docs/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md` | 50272 | 76.7% |
| `docs/plans/2026-07-27-01-pr1-feedback-pack-documentation-refresh-plan.md` | 2328 | 3.6% |
| `docs/plans/2026-07-27-02-pr2-launch-quality-hotfix-plan.md` | 15526 | 23.7% |
| `docs/plans/2026-07-27-03-pr3-isolated-ui-corrections-plan.md` | 9110 | 13.9% |
| `docs/plans/2026-07-27-04-pr4-session-screen-controls-plan.md` | 10199 | 15.6% |
| `docs/plans/2026-07-27-05-pr5-routine-unsaved-changes-guard-plan.md` | 12812 | 19.5% |
| `docs/plans/2026-07-27-06-pr6-routine-session-entry-navigation-plan.md` | 54015 | 82.4% |
| `docs/plans/2026-07-27-07-pr7-exercise-details-view-plan.md` | 6367 | 9.7% |
| `docs/plans/2026-07-27-08-pr8-exercise-library-plan.md` | 8788 | 13.4% |
| `docs/plans/2026-08-07-catalog-150-to-166-plan.md` | 35937 | 54.8% |
| `docs/plans/2026-08-07-track-bundled-food-photos-plan.md` | 14840 | 22.6% |
| `docs/plans/2026-08-08-catalog-delivery-validation-suite-plan.md` | 18022 | 27.5% |
| `docs/plans/2026-08-08-edit-food-shipped-photo-plan.md` | 14711 | 22.4% |
| `docs/plans/2026-08-08-food-edit-orphan-category-plan.md` | 19190 | 29.3% |
| `docs/plans/2026-08-08-retire-alcohol-catalog-rows-plan.md` | 20063 | 30.6% |
| `docs/plans/2026-08-10-catalog-validation-followups-plan.md` | 11731 | 17.9% |
| `docs/plans/2026-08-11-13-hit-full-body-routine-plan.md` | 31481 | 48.0% |
| `docs/plans/2026-08-13-theme-contrast-remediation-plan.md` | 47557 | 72.6% |
| `docs/plans/2026-08-16-rest-timer-timed-overlap-bug-plan.md` | 29056 | 44.3% |
| `docs/plans/2026-09-21-13-watch-integration-shipping.md` | 73349 | 111.9% |
| `docs/plans/2026-09-24-01-stats-pr1-effort-rating-plan.md` | 57713 | 88.1% |
| `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` | 88320 | 134.8% |
| `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.evidence.md` | 11682 | 17.8% |
| `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md` | 300522 | 458.6% |
| `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.review.md` | 11563 | 17.6% |
| `docs/plans/2026-09-26-03-stats-pr3-distance-series-index.md` | 6486 | 9.9% |
| `docs/plans/2026-09-26-03a-stats-pr3a-phone-distance-plan.evidence.md` | 27853 | 42.5% |
| `docs/plans/2026-09-26-03a-stats-pr3a-phone-distance-plan.md` | 43787 | 66.8% |
| `docs/plans/2026-09-26-03a-stats-pr3a-phone-distance-plan.review.md` | 17458 | 26.6% |
| `docs/plans/2026-09-27-03a2-stats-pr3a2-entry-identity-plan.evidence.md` | 23004 | 35.1% |
| `docs/plans/2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md` | 37796 | 57.7% |
| `docs/plans/2026-09-27-03a2-stats-pr3a2-entry-identity-plan.review.md` | 18827 | 28.7% |
| `docs/plans/2026-09-27-03b-stats-pr3b-distance-source-import-plan.evidence.md` | 28330 | 43.2% |
| `docs/plans/2026-09-27-03b-stats-pr3b-distance-source-import-plan.md` | 37341 | 57.0% |
| `docs/plans/2026-09-27-03b-stats-pr3b-distance-source-import-plan.review.md` | 25489 | 38.9% |
| `docs/plans/2026-09-30-04-stats-pr4-index.md` | 23736 | 36.2% |
| `docs/plans/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.evidence.md` | 38404 | 58.6% |
| `docs/plans/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.md` | 59923 | 91.4% |
| `docs/plans/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.review.md` | 17710 | 27.0% |
| `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.evidence.md` | 26319 | 40.2% |
| `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.md` | 53153 | 81.1% |
| `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.review.md` | 12902 | 19.7% |
| `docs/plans/2026-10-01-04b2-stats-pr4b2-instruments-list-plan/2026-10-01-04b2-stats-pr4b2-instruments-list-plan.evidence.md` | 26047 | 39.7% |
| `docs/plans/2026-10-01-04b2-stats-pr4b2-instruments-list-plan/2026-10-01-04b2-stats-pr4b2-instruments-list-plan.md` | 49878 | 76.1% |
| `docs/plans/2026-10-01-04b2-stats-pr4b2-instruments-list-plan/2026-10-01-04b2-stats-pr4b2-instruments-list-plan.review.md` | 11825 | 18.0% |
| `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/2026-10-01-04b3-stats-pr4b3-fuel-row-plan.evidence.md` | 39513 | 60.3% |
| `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/2026-10-01-04b3-stats-pr4b3-fuel-row-plan.md` | 60560 | 92.4% |
| `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/2026-10-01-04b3-stats-pr4b3-fuel-row-plan.review.md` | 16625 | 25.4% |
| `docs/plans/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.evidence.md` | 24963 | 38.1% |
| `docs/plans/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.md` | 58529 | 89.3% |
| `docs/plans/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.review.md` | 17139 | 26.2% |
| `docs/plans/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.evidence.md` | 30874 | 47.1% |
| `docs/plans/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.md` | 52854 | 80.6% |
| `docs/plans/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.review.md` | 23672 | 36.1% |
| `docs/plans/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.evidence.md` | 44969 | 68.6% |
| `docs/plans/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.md` | 57368 | 87.5% |
| `docs/plans/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan/2026-10-02-03a3-stats-pr3a3-phone-cleanup-plan.review.md` | 10240 | 15.6% |
| `docs/plans/2026-10-02-03d-stats-pr3d-late-watch-entry-plan/2026-10-02-03d-stats-pr3d-late-watch-entry-plan.evidence.md` | 36653 | 55.9% |
| `docs/plans/2026-10-02-03d-stats-pr3d-late-watch-entry-plan/2026-10-02-03d-stats-pr3d-late-watch-entry-plan.md` | 49728 | 75.9% |
| `docs/plans/2026-10-02-03d-stats-pr3d-late-watch-entry-plan/2026-10-02-03d-stats-pr3d-late-watch-entry-plan.review.md` | 12513 | 19.1% |
| `docs/plans/2026-10-02-05-stats-pr5-index.md` | 7009 | 10.7% |
| `docs/plans/2026-10-02-05a-stats-pr5a-mix-data-plan/2026-10-02-05a-stats-pr5a-mix-data-plan.evidence.md` | 32073 | 48.9% |
| `docs/plans/2026-10-02-05a-stats-pr5a-mix-data-plan/2026-10-02-05a-stats-pr5a-mix-data-plan.md` | 48053 | 73.3% |
| `docs/plans/2026-10-02-05a-stats-pr5a-mix-data-plan/2026-10-02-05a-stats-pr5a-mix-data-plan.review.md` | 3890 | 5.9% |
| `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/2026-10-02-05b-stats-pr5b-mix-screen-plan.evidence.md` | 37671 | 57.5% |
| `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/2026-10-02-05b-stats-pr5b-mix-screen-plan.md` | 48286 | 73.7% |
| `docs/plans/2026-10-02-05b-stats-pr5b-mix-screen-plan/2026-10-02-05b-stats-pr5b-mix-screen-plan.review.md` | 12976 | 19.8% |
| `docs/plans/2026-10-03-05c-stats-pr5c-housekeeping-plan/2026-10-03-05c-stats-pr5c-housekeeping-plan.evidence.md` | 9682 | 14.8% |
| `docs/plans/2026-10-03-05c-stats-pr5c-housekeeping-plan/2026-10-03-05c-stats-pr5c-housekeeping-plan.md` | 34321 | 52.4% |
| `docs/plans/2026-10-03-06-stats-pr6-index.md` | 6339 | 9.7% |
| `docs/plans/2026-10-03-06a-stats-pr6a-signals-framework-plan/2026-10-03-06a-stats-pr6a-signals-framework-plan.evidence.md` | 26959 | 41.1% |
| `docs/plans/2026-10-03-06a-stats-pr6a-signals-framework-plan/2026-10-03-06a-stats-pr6a-signals-framework-plan.md` | 46451 | 70.9% |
| `docs/plans/2026-10-03-06a-stats-pr6a-signals-framework-plan/2026-10-03-06a-stats-pr6a-signals-framework-plan.review.md` | 5257 | 8.0% |
| `docs/plans/2026-10-03-06b-stats-pr6b-progression-rate-plan/2026-10-03-06b-stats-pr6b-progression-rate-plan.evidence.md` | 18268 | 27.9% |
| `docs/plans/2026-10-03-06b-stats-pr6b-progression-rate-plan/2026-10-03-06b-stats-pr6b-progression-rate-plan.md` | 39046 | 59.6% |
| `docs/plans/2026-10-03-07-stats-pr7-index.md` | 7300 | 11.1% |
| `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.evidence.md` | 26753 | 40.8% |
| `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.md` | 42120 | 64.3% |
| `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.review.md` | 12858 | 19.6% |
| `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.evidence.md` | 26488 | 40.4% |
| `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.md` | 50920 | 77.7% |
| `docs/plans/2026-10-03-07b-stats-pr7b-interference-plan/2026-10-03-07b-stats-pr7b-interference-plan.review.md` | 6429 | 9.8% |
| `docs/plans/2026-10-03-08-stats-pr8-index.md` | 6578 | 10.0% |
| `docs/plans/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.evidence.md` | 4683 | 7.1% |
| `docs/plans/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.md` | 38783 | 59.2% |
| `docs/plans/2026-10-03-08b-stats-pr8b-protein-consistency-plan/2026-10-03-08b-stats-pr8b-protein-consistency-plan.evidence.md` | 6153 | 9.4% |
| `docs/plans/2026-10-03-08b-stats-pr8b-protein-consistency-plan/2026-10-03-08b-stats-pr8b-protein-consistency-plan.md` | 47671 | 72.7% |
| `docs/plans/2026-10-03-08h-stats-pr8h-housekeeping-plan/2026-10-03-08h-stats-pr8h-housekeeping-plan.evidence.md` | 7100 | 10.8% |
| `docs/plans/2026-10-03-08h-stats-pr8h-housekeeping-plan/2026-10-03-08h-stats-pr8h-housekeeping-plan.md` | 17047 | 26.0% |
| `docs/plans/active-session-persistence-plan.md` | 17311 | 26.4% |
| `docs/plans/add-exercise-modality-bug-plan.md` | 2922 | 4.5% |
| `docs/plans/add-food-screen-bottom-cta-plan.md` | 11151 | 17.0% |
| `docs/plans/add-planned-session-theme-plan.md` | 6841 | 10.4% |
| `docs/plans/android-timer-alert-sounds-fix-plan.md` | 10237 | 15.6% |
| `docs/plans/avatar-crop-step-plan.md` | 16336 | 24.9% |
| `docs/plans/bilateral-logging-guidance-plan.md` | 7316 | 11.2% |
| `docs/plans/block-add-exercise-header-plan.md` | 5239 | 8.0% |
| `docs/plans/boxing-rest-timer-reset-bug-plan.md` | 13685 | 20.9% |
| `docs/plans/boxing-rounds-sports-summary-plan.md` | 4106 | 6.3% |
| `docs/plans/bundled-food-photographs-plan.md` | 35568 | 54.3% |
| `docs/plans/calendar-duplicate-session-plan.md` | 4175 | 6.4% |
| `docs/plans/calendar-month-grid-height-cap-plan.md` | 30047 | 45.8% |
| `docs/plans/calendar-monthly-stats-plan.md` | 10078 | 15.4% |
| `docs/plans/calendar-periods-plan.md` | 35674 | 54.4% |
| `docs/plans/calendar-session-theme-plan.md` | 3818 | 5.8% |
| `docs/plans/calendar-summary-screen-bugs-plan.md` | 9636 | 14.7% |
| `docs/plans/catalog-refresh-plan.md` | 12875 | 19.6% |
| `docs/plans/centralized-route-system-plan.md` | 21100 | 32.2% |
| `docs/plans/clone-block-numeric-values-plan.md` | 3413 | 5.2% |
| `docs/plans/coach-mark-icon-positioning-plan.md` | 3627 | 5.5% |
| `docs/plans/confirmation-dialog-consolidation-plan.md` | 65074 | 99.3% |
| `docs/plans/crash-reporting-ios-destination-plan.md` | 13734 | 21.0% |
| `docs/plans/crash-reporting-rate-limit-plan.md` | 37088 | 56.6% |
| `docs/plans/crash-reporting-three-defects-plan.md` | 28094 | 42.9% |
| `docs/plans/crash-reporting-upload-destination-plan.md` | 13025 | 19.9% |
| `docs/plans/crash-reporting-version-identity-plan.md` | 7082 | 10.8% |
| `docs/plans/crown-control-tap-to-edit-plan.md` | 24537 | 37.4% |
| `docs/plans/daily-nutrition-macro-chart-plan.md` | 85384 | 130.3% |
| `docs/plans/data-migration-versioning-plan.md` | 15190 | 23.2% |
| `docs/plans/data-tracking-fixes-plan.md` | 9017 | 13.8% |
| `docs/plans/day-session-list-bottom-cta-plan.md` | 8885 | 13.6% |
| `docs/plans/disable-feeling-survey-setting-plan.md` | 2647 | 4.0% |
| `docs/plans/distance-unit-preference-plan.md` | 15900 | 24.3% |
| `docs/plans/doc-reconciliation-plan.md` | 20781 | 31.7% |
| `docs/plans/docs-standard-audit-2026-07-30.md` | 58261 | 88.9% |
| `docs/plans/edit-historical-session-timed-iso-sports-plan.md` | 42336 | 64.6% |
| `docs/plans/edit-session-duration-plan.md` | 6103 | 9.3% |
| `docs/plans/emphasis-tier-color-contract-plan.md` | 29121 | 44.4% |
| `docs/plans/exercise-detail-coach-marks-plan.md` | 8663 | 13.2% |
| `docs/plans/exercise-detail-emphasis-tier-rebalance-plan.md` | 21580 | 32.9% |
| `docs/plans/exercise-details-tracking-vs-movement-classification-plan.md` | 15590 | 23.8% |
| `docs/plans/exercise-info-notes-plan.md` | 3530 | 5.4% |
| `docs/plans/exercise-library-info-icon-removal-plan.md` | 21528 | 32.8% |
| `docs/plans/exercise-picker-auto-open-plan.md` | 8527 | 13.0% |
| `docs/plans/exercise-picker-page-plan.md` | 24323 | 37.1% |
| `docs/plans/exercise-row-density-fix-plan.md` | 8814 | 13.4% |
| `docs/plans/exercise-set-last-value-plan.md` | 11958 | 18.2% |
| `docs/plans/failing-tests-fix-plan.md` | 5426 | 8.3% |
| `docs/plans/finish-session-stops-timers-plan.md` | 12741 | 19.4% |
| `docs/plans/first-unlogged-set-landing-plan.md` | 6716 | 10.2% |
| `docs/plans/fix-failing-unit-tests-plan.md` | 4562 | 7.0% |
| `docs/plans/food-catalog-150-expansion-plan.md` | 40932 | 62.5% |
| `docs/plans/food-catalog-load-plan.md` | 7795 | 11.9% |
| `docs/plans/food-catalog-nutrition-corrections-plan.md` | 8908 | 13.6% |
| `docs/plans/food-category-unification-plan.md` | 6924 | 10.6% |
| `docs/plans/food-default-categories-seed-plan.md` | 8245 | 12.6% |
| `docs/plans/food-durable-identity-plan.md` | 4836 | 7.4% |
| `docs/plans/food-form-decimals-and-autofocus-plan.md` | 11481 | 17.5% |
| `docs/plans/food-last-amount-plan.md` | 12343 | 18.8% |
| `docs/plans/food-library-browse-view-plan.md` | 16595 | 25.3% |
| `docs/plans/food-library-edit-image-plan.md` | 52995 | 80.9% |
| `docs/plans/food-library-edit-propagate-all-fields-plan.md` | 8190 | 12.5% |
| `docs/plans/food-library-multiplier-ux-plan.md` | 23671 | 36.1% |
| `docs/plans/food-library-plan.md` | 26579 | 40.6% |
| `docs/plans/food-library-row-layout-plan.md` | 4413 | 6.7% |
| `docs/plans/food-log-thumbnail-contrast-plan.md` | 2998 | 4.6% |
| `docs/plans/food-serving-unit-normalization-plan.md` | 9130 | 13.9% |
| `docs/plans/foods-i-eat-thumbnail-toggle-plan.md` | 26164 | 39.9% |
| `docs/plans/free-rolling-session-add-exercise-plan.md` | 6488 | 9.9% |
| `docs/plans/fuzzy-exercise-search-plan.md` | 12250 | 18.7% |
| `docs/plans/gradient-window-layer-plan.md` | 19636 | 30.0% |
| `docs/plans/green-themes-bakeoff-plan.md` | 18050 | 27.5% |
| `docs/plans/header-standardization-plan.md` | 15944 | 24.3% |
| `docs/plans/height-preview-plan.md` | 2541 | 3.9% |
| `docs/plans/height-unit-preference-plan.md` | 21555 | 32.9% |
| `docs/plans/home-header-rework-plan.md` | 35742 | 54.5% |
| `docs/plans/home-logo-hub-open-plan.md` | 3032 | 4.6% |
| `docs/plans/home-logo-press-affordance-plan.md` | 7444 | 11.4% |
| `docs/plans/home-logo-restyle-circle-menu-plan.md` | 3704 | 5.7% |
| `docs/plans/home-main-tile-shadow-parity-plan.md` | 987 | 1.5% |
| `docs/plans/home-nutrition-no-target-show-percentages-plan.md` | 13379 | 20.4% |
| `docs/plans/home-nutrition-strip-plan.md` | 45549 | 69.5% |
| `docs/plans/home-screen-short-viewport-plan.md` | 8741 | 13.3% |
| `docs/plans/home-tile-fixes-plan.md` | 15677 | 23.9% |
| `docs/plans/home-tile-responsive-artwork-plan.md` | 10779 | 16.4% |
| `docs/plans/home-tile-row-separation-plan.md` | 3294 | 5.0% |
| `docs/plans/home-tile-tier-restyle-plan.md` | 9763 | 14.9% |
| `docs/plans/hub-bottom-sheet-single-step-open-plan.md` | 8450 | 12.9% |
| `docs/plans/hub-sheet-content-anchor-top-plan.md` | 13362 | 20.4% |
| `docs/plans/hub-sheet-gap-and-logo-clip-plan.md` | 14930 | 22.8% |
| `docs/plans/hub-sheet-navigation-plan.md` | 8597 | 13.1% |
| `docs/plans/hygiene-sweep-plan.md` | 7067 | 10.8% |
| `docs/plans/image-persistence-fix-plan.md` | 49417 | 75.4% |
| `docs/plans/image-persistence-relocation-fix-plan.md` | 25622 | 39.1% |
| `docs/plans/in-session-pr-toast-plan.md` | 51348 | 78.4% |
| `docs/plans/ios-release-infrastructure-plan.md` | 3288 | 5.0% |
| `docs/plans/keyboard-dismissal-and-capitalization-plan.md` | 40915 | 62.4% |
| `docs/plans/large-screen-capped-column-plan.md` | 13639 | 20.8% |
| `docs/plans/manage-food-library-ux-plan.md` | 29431 | 44.9% |
| `docs/plans/measurement-history-chart-readability-plan.md` | 12225 | 18.7% |
| `docs/plans/measurement-history-chart-sheet-plan.md` | 18520 | 28.3% |
| `docs/plans/minimum-supported-viewport-plan.md` | 4058 | 6.2% |
| `docs/plans/modality-aware-create-exercise-plan.md` | 20714 | 31.6% |
| `docs/plans/modality-color-consolidation-plan.md` | 7588 | 11.6% |
| `docs/plans/nav-example-in-agent-instructions-plan.md` | 6272 | 9.6% |
| `docs/plans/navigation-contract-enforcement-plan.md` | 11000 | 16.8% |
| `docs/plans/nutrition-data-audit-plan.md` | 21019 | 32.1% |
| `docs/plans/nutrition-day-isolation-groups-search-plan.md` | 24201 | 36.9% |
| `docs/plans/nutrition-food-library-add-plan.md` | 28233 | 43.1% |
| `docs/plans/nutrition-foods-i-eat-empty-state-plan.md` | 7084 | 10.8% |
| `docs/plans/nutrition-log-from-library-plan.md` | 32623 | 49.8% |
| `docs/plans/nutrition-page-calories-ring-plan.md` | 27420 | 41.8% |
| `docs/plans/nutrition-page-primer-plan.md` | 16879 | 25.8% |
| `docs/plans/nutrition-targets-daily-plan.md` | 26028 | 39.7% |
| `docs/plans/nutrition-targets-live-readout-plan.md` | 14199 | 21.7% |
| `docs/plans/nutrition-targets-plan.md` | 5358 | 8.2% |
| `docs/plans/nutrition-terminology-unification-plan.md` | 30492 | 46.5% |
| `docs/plans/onboarding-plan.md` | 11417 | 17.4% |
| `docs/plans/period-current-badge-text-plan.md` | 4615 | 7.0% |
| `docs/plans/period-list-ux-plan.md` | 5203 | 7.9% |
| `docs/plans/pr-celebration-throttle-plan.md` | 5749 | 8.8% |
| `docs/plans/preflight-ux-improvements-plan.md` | 17906 | 27.3% |
| `docs/plans/primary-bottom-cta-anchor-width-plan.md` | 19365 | 29.5% |
| `docs/plans/profile-cleanup-plan.md` | 15325 | 23.4% |
| `docs/plans/profile-identity-horizontal-header-plan.md` | 44818 | 68.4% |
| `docs/plans/profile-lean-mass-caption-fix-plan.md` | 11604 | 17.7% |
| `docs/plans/profile-screen-plan.md` | 34214 | 52.2% |
| `docs/plans/remove-app-launch-resume-modal-plan.md` | 6234 | 9.5% |
| `docs/plans/remove-auto-finish-prompt-plan.md` | 7920 | 12.1% |
| `docs/plans/remove-general-modality-plan.md` | 4568 | 7.0% |
| `docs/plans/resistance-active-screen-emphasis-redesign-plan.md` | 13917 | 21.2% |
| `docs/plans/resistance-framework-extra-weight-visibility-plan.md` | 4025 | 6.1% |
| `docs/plans/resistance-rest-timer-bug-plan.md` | 5985 | 9.1% |
| `docs/plans/rest-timer-cross-exercise-and-list-view-plan.md` | 5441 | 8.3% |
| `docs/plans/rest-timer-docked-strip-plan.md` | 23045 | 35.2% |
| `docs/plans/rest-timer-local-notifications-plan.md` | 44246 | 67.5% |
| `docs/plans/rest-timer-lock-nav-and-stop-on-start-plan.md` | 5760 | 8.8% |
| `docs/plans/retire-martial-arts-category-plan.md` | 16640 | 25.4% |
| `docs/plans/retire-sqlite-runtime-plan.md` | 14623 | 22.3% |
| `docs/plans/rolling-session-calendar-duration-fix-plan.md` | 6554 | 10.0% |
| `docs/plans/rolling-session-hide-duration-rest-plan.md` | 4128 | 6.3% |
| `docs/plans/rolling-session-summary-hide-time-stats-plan.md` | 4826 | 7.4% |
| `docs/plans/round-auto-expiry-active-round-lock-plan.md` | 7102 | 10.8% |
| `docs/plans/routine-add-sets-bug-plan.md` | 15629 | 23.8% |
| `docs/plans/routine-builder-no-duration-target-plan.md` | 7150 | 10.9% |
| `docs/plans/routine-exercise-detail-ui-parity-plan.md` | 8239 | 12.6% |
| `docs/plans/routine-focus-modality-inheritance-plan.md` | 13885 | 21.2% |
| `docs/plans/routine-modality-picker-plan.md` | 4516 | 6.9% |
| `docs/plans/routine-rest-menu-and-session-detail-icons-plan.md` | 7739 | 11.8% |
| `docs/plans/routines-bottom-cta-plan.md` | 8420 | 12.8% |
| `docs/plans/screen-transition-animation-plan.md` | 6242 | 9.5% |
| `docs/plans/session-blocks-plan.md` | 70910 | 108.2% |
| `docs/plans/session-detail-set-count-plan.md` | 6227 | 9.5% |
| `docs/plans/session-detail-spacing-plan.md` | 7785 | 11.9% |
| `docs/plans/session-details-execution-order-plan.md` | 12993 | 19.8% |
| `docs/plans/session-exercise-capabilities-plan.md` | 11688 | 17.8% |
| `docs/plans/session-feeling-extended-tracking-plan.md` | 12252 | 18.7% |
| `docs/plans/session-horizontal-set-swipe-transition-plan.md` | 5043 | 7.7% |
| `docs/plans/session-persistence-fix-plan.md` | 8164 | 12.5% |
| `docs/plans/session-scroll-bottom-padding-plan.md` | 3881 | 5.9% |
| `docs/plans/session-set-management-relocation-plan.md` | 11408 | 17.4% |
| `docs/plans/session-summary-completed-rounds-only-copilot-prompts.md` | 4661 | 7.1% |
| `docs/plans/session-summary-group-chips-plan.md` | 9197 | 14.0% |
| `docs/plans/session-summary-open-calendar-plan.md` | 5384 | 8.2% |
| `docs/plans/session-summary-redesign-plan.md` | 9262 | 14.1% |
| `docs/plans/session-summary-rest-and-sports-time-plan.md` | 4305 | 6.6% |
| `docs/plans/session-summary-time-fix-plan.md` | 8809 | 13.4% |
| `docs/plans/session-summary-top-stats-card-plan.md` | 4383 | 6.7% |
| `docs/plans/session-toolbar-rework-plan.md` | 15726 | 24.0% |
| `docs/plans/settings-account-removal-plan.md` | 12003 | 18.3% |
| `docs/plans/settings-version-row-plan.md` | 8672 | 13.2% |
| `docs/plans/shared-bottom-cta-plan.md` | 8329 | 12.7% |
| `docs/plans/sports-screen-redesign-plan.md` | 15313 | 23.4% |
| `docs/plans/startup-failure-screen-plan.md` | 10419 | 15.9% |
| `docs/plans/stats-feeling-chart-width-consistency-plan.md` | 6097 | 9.3% |
| `docs/plans/stats-feeling-color-dry-fix-plan.md` | 7416 | 11.3% |
| `docs/plans/stats-feeling-trend-color-visibility-plan.md` | 8570 | 13.1% |
| `docs/plans/stats-feeling-trend-plan.md` | 28528 | 43.5% |
| `docs/plans/stats-nutrition-trend-card-plan.md` | 13689 | 20.9% |
| `docs/plans/stats-rest-time-chart-plan.md` | 15259 | 23.3% |
| `docs/plans/stats-screen-plan.md` | 8708 | 13.3% |
| `docs/plans/stats-screen-progress-rework-plan.md` | 41656 | 63.6% |
| `docs/plans/stats-screen-remediation-plan.md` | 55917 | 85.3% |
| `docs/plans/stats-scrollable-trend-charts-plan.md` | 9516 | 14.5% |
| `docs/plans/stats-summary-fix-pack-plan.md` | 42334 | 64.6% |
| `docs/plans/stats-window-scoped-selection-plan.md` | 20314 | 31.0% |
| `docs/plans/summary-pr-parity-plan.md` | 19585 | 29.9% |
| `docs/plans/tap-to-edit-metric-modal-plan.md` | 28870 | 44.1% |
| `docs/plans/tap-to-edit-unification-plan.md` | 17985 | 27.4% |
| `docs/plans/testflight-ui-fixes-plan.md` | 6177 | 9.4% |
| `docs/plans/theme-support-plan.md` | 11719 | 17.9% |
| `docs/plans/theme-system-overhaul-plan.md` | 10620 | 16.2% |
| `docs/plans/timed-emphasis-redesign-plan.md` | 16316 | 24.9% |
| `docs/plans/timed-extra-weight-plan.md` | 15141 | 23.1% |
| `docs/plans/timer-alerts-sound-system-plan.md` | 21910 | 33.4% |
| `docs/plans/timer-start-on-exercise-select-plan.md` | 3714 | 5.7% |
| `docs/plans/train-screen-non-scrolling-layout-plan.md` | 13583 | 20.7% |
| `docs/plans/typography-control-styling-plan.md` | 22946 | 35.0% |
| `docs/plans/typography-text-scale-audit-plan.md` | 27743 | 42.3% |
| `docs/plans/unfinished-session-modal-set-count-plan.md` | 5374 | 8.2% |
| `docs/plans/unified-card-and-header-plan.md` | 146342 | 223.3% |
| `docs/plans/unified-rest-overlay-rule-plan.md` | 13535 | 20.7% |
| `docs/plans/unify-chart-scrolling-popup-plan.md` | 42329 | 64.6% |
| `docs/plans/unsaved-changes-popup-plan.md` | 3865 | 5.9% |
| `docs/plans/value-entry-select-on-focus-plan.md` | 18392 | 28.1% |
| `docs/plans/volume-double-conversion-bug-plan.md` | 24258 | 37.0% |
| `docs/plans/water-tracker-plan.md` | 29747 | 45.4% |
| `docs/plans/weight-increment-defaults-plan.md` | 3430 | 5.2% |
| `docs/plans/whey-protein-to-proteins-plan.md` | 6878 | 10.5% |
| `docs/plans/workout-state-and-screen-refactor-plan.md` | 43543 | 66.4% |
| `docs/profile_and_measurements.md` | 14671 | 22.4% |
| `docs/records_and_trends.md` | 6162 | 9.4% |
| `docs/releases/2026-05-plan-review.md` | 4524 | 6.9% |
| `docs/releases/2026-06-27-pr-surface-verification.md` | 9718 | 14.8% |
| `docs/releases/ios-testflight.md` | 7034 | 10.7% |
| `docs/rest_tracking.md` | 13450 | 20.5% |
| `docs/rolling_sessions.md` | 5750 | 8.8% |
| `docs/session_summary.md` | 15998 | 24.4% |
| `docs/signals.md` | 21753 | 33.2% |
| `docs/state_management.md` | 9175 | 14.0% |
| `docs/state_management/app_state.md` | 9971 | 15.2% |
| `docs/state_management/nutrition_state.md` | 21985 | 33.5% |
| `docs/state_management/services_and_utils.md` | 24103 | 36.8% |
| `docs/state_management/watch_surface.md` | 32008 | 48.8% |
| `docs/state_management/workout_state.md` | 19066 | 29.1% |
| `docs/stats_best_load_investigation.md` | 35084 | 53.5% |
| `docs/stats_screen.md` | 28131 | 42.9% |
| `docs/theme_and_settings.md` | 7318 | 11.2% |
| `docs/training_load.md` | 10313 | 15.7% |
| `docs/watch-app-setup-and-qa.md` | 19114 | 29.2% |
| `docs/watch_session_capture.md` | 20999 | 32.0% |
| `docs/widget_catalog.md` | 13989 | 21.3% |
| `docs/widget_catalog/feature_primitives.md` | 6100 | 9.3% |
| `docs/widget_catalog/home_screen.md` | 8140 | 12.4% |
| `docs/widget_catalog/layout_and_inputs.md` | 10250 | 15.6% |
| `docs/widget_catalog/nutrition_widgets.md` | 13255 | 20.2% |
| `docs/widget_catalog/session_widgets.md` | 14268 | 21.8% |

**362 files, 7,229,112 bytes.** 18 files are at or past the 80% warning band (52,429 bytes) and 6 are past
the ceiling itself (65,536 bytes) — all six are old `docs/plans/` files:
`unified-card-and-header-plan.md` (146,342 / 223.3%), `2026-09-25-02-stats-pr2-watch-capture-plan.md`
(300,522 / 458.6%), `2026-09-24-stats-redesign-modality-lens-prompt-pack.md` (88,320 / 134.8%),
`daily-nutrition-macro-chart-plan.md` (85,384 / 130.3%), `2026-09-21-13-watch-integration-shipping.md`
(73,349 / 111.9%) and `session-blocks-plan.md` (70,910 / 108.2%). This PR adds none of them and removes
none — the numbers are a baseline for 8a and 8b. The evidence file's own row is its size immediately
before this table was written, which is the one number in the table that is not its post-run size.

### Full-suite summary (Phase 1)

```
01:33 +3637 ~1: All tests passed!
```

`flutter analyze` after the phase: `196 issues found.` (ran in 2.9s) — identical to the opening
measurement, so the two guards and the two derivations add no new lint finding.

### Done Criteria test list (re-run after the last evidence edit)

```
00:01 +78: All tests passed!
```

`test/interference_test.dart test/modality_mix_shift_test.dart test/interference_signal_screen_test.dart
test/modality_mix_shift_signal_screen_test.dart test/docs_indexing_contract_test.dart` — re-run last, so
the `docs/` ceiling check covers this file and the plan after every edit this phase made to them.

## Plan size, measured

| Measure | Predicted | Measured |
|---|---|---|
| Plan lines | 236 | 251 |
| Ledger decisions | 5 | 5 (`D-1601` … `D-1605`) |
| Scenarios | 3 | 3 (`S-2301` … `S-2303`) |
| Production lines changed | ~8 | 3 added / 2 removed in 2 files under `lib/core/models/` (one interpolation each); the guards add 59 lines across the two suites |
| Files deleted | 0 | 0 |
| Evidence file growth | — | +407 lines (this run) |
