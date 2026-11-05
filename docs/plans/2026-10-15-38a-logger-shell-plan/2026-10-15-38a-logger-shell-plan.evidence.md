# Evidence — 38a Phase D (docs keeper)

Date: 2026-10-15. Scope: `docs/modality_based_exercise_ui.md`,
`docs/widget_catalog/session_widgets.md`, `docs/design_system.md`, this file.

| doc | section | what changed | claim verified against (file:line) |
|---|---|---|---|
| `docs/modality_based_exercise_ui.md` | Component Hierarchy | "Set Progress Indicator" / "Set Dots (visual progress)" replaced by `SetSegmentBar`, `LoggedValuesLine`, `SetCountStepper` | `lib/widgets/session/set_segment_bar.dart:22`, `logged_values_line.dart:24`, `set_count_stepper.dart:16` |
| `docs/modality_based_exercise_ui.md` | Key Design Principles 4 (Haptic + Visual Feedback) | "Completed set dots fill in" → "Logged segments of the set bar fill in (`SetSegmentBar`)" | `lib/widgets/session/set_segment_bar.dart:100-110` (logged fill `scheme.primary`) |
| `docs/modality_based_exercise_ui.md` | 6. Set Navigation and Control | New intro paragraph (bar block: segments, count text, logged line; stepper below the controls) with test citations | `lib/features/session/workout_session_detail_view.dart:760-813` (`_buildSetBar`), `lib/features/session/workout_session_list_view.dart:825-849` (detail Column order) |
| `docs/modality_based_exercise_ui.md` | 6. Set Navigation and Control | New **Lock Rule (live sessions)**: logged set read-only live, `LOGGED` centre control kept, edit mode never locked | `workout_session_detail_view.dart:226-229` (`isLoggedNow = !widget.editMode && _isSetLogged`), `:233,:242` (`isReadOnly: isLoggedNow`), `:112,:124,:154` (weight-adjustment `isReadOnly`), `:910` (`'LOGGED'`) |
| `docs/modality_based_exercise_ui.md` | 6. Set Navigation and Control | New **Auto-Advance Rule**: focus to first unlogged set after the focused one, else next exercise, else stays | `lib/features/session/workout_session_screen.dart:797-807` (`_nextUnloggedSetAfter`), `:981-999` (advance block in `_logSet`) |
| `docs/modality_based_exercise_ui.md` | 6. Set Navigation and Control | "Delete / Remove Rule" replaced by **Stepper Remove Rule**: `−` removes the last unlogged set (last set when all logged), same confirmations, `+` up to the 12-entry cap | `workout_session_screen.dart:1404-1421` (`_deleteLastUnloggedSet`), `:1311-1402` (`_deleteSetAt`, `Delete logged $setLabel?` / `Remove Exercise?`), `lib/widgets/session/set_count_stepper.dart:88-91` (`Max ${WorkoutConstants.maxEntriesPerEffort} entries`) |
| `docs/modality_based_exercise_ui.md` | Set Skip vs Delete | Dot wording replaced: segment stays unlogged on skip; `−` removes the last unlogged set, not the focused one; one-set effort shows the trash-can and `Remove exercise` tooltip | `workout_session_screen.dart:1408-1417` (target pick), `set_count_stepper.dart:83-87` (`removeIsExercise` icon/tooltip), `test/logger_shell_screen_test.dart:836` (S-4233) |
| `docs/modality_based_exercise_ui.md` | Code Organization | Actions list updated (`_logSet, _addSet, _deleteSetAt, _deleteLastUnloggedSet`); Timer Management corrected to `_toggleEffortTimer` (mixin); Helpers dropped `_formatValue`; inline editor gesture corrected to `_onNumberTap` (tap-only, no drag path) | `workout_session_screen.dart:1195,1311,1404,1494,1509`; `workout_session_timer_mixin.dart:428`; `lib/widgets/session/inline_metric_editor.dart:90,114` |
| `docs/modality_based_exercise_ui.md` | Footer | Document Version 1.5 → 1.6; Last Updated → October 15, 2026 | — |
| `docs/widget_catalog/session_widgets.md` | Session Metric Widgets | Three new entries: `SetSegmentBar`, `LoggedValuesLine` (+ `loggedValuesText`), `SetCountStepper` — path, props, keys, behaviour, verified-by | `set_segment_bar.dart`, `logged_values_line.dart`, `set_count_stepper.dart` (read in full); `test/set_shell_widgets_test.dart:30,141,175,204`; `test/logger_shell_screen_test.dart:128,297,463,528,615,776` |
| `docs/design_system.md` | Shared pieces and rules per job | Two table rows: "Set progress bar" → `SetSegmentBar`; "Add/remove entry stepper" → `SetCountStepper` | `lib/widgets/session/set_segment_bar.dart`, `lib/widgets/session/set_count_stepper.dart` |
| `docs/design_system.md` | Shared pieces and rules per job (text after the table) | One sentence per new piece: use the piece, not a copy. Bar rule cites S-4223; stepper rule marked `unguarded` (no scan counts hand-built entry steppers — checked `test/ui_standards_contract_test.dart`: no `SetSegmentBar`/`SetCountStepper` match) | `test/logger_shell_screen_test.dart:514-519` (`S-4223: the dot builders are gone from the session detail view`) |

## Removed-name sweep (`_buildSetProgress`, `_buildSetIndicator`, `Set Dots`, `set dots`, `_skippedSets`)

In scope: `docs/modality_based_exercise_ui.md` had the only in-scope mentions
(`Set Dots` :51, `set dots` :75, plus the "Set Progress Indicator" hierarchy
line); all fixed above. `docs/widget_catalog/session_widgets.md` and
`docs/design_system.md` had none.

### Outside my scope

- `docs/stats_best_load_investigation.md:430` — names `_skippedSets` (field no longer exists; `workout_session_screen.dart` has no such field).
- Historical plan records under `docs/plans/` (kept as written history, not live docs): `timed-emphasis-redesign-plan.md`, `session-set-management-relocation-plan.md`, `workout-state-and-screen-refactor-plan.md`, `testflight-ui-fixes-plan.md`, `routine-exercise-detail-ui-parity-plan.md`, `data-tracking-fixes-plan.md`, `resistance-active-screen-emphasis-redesign-plan.md`, `rest-timer-lock-nav-and-stop-on-start-plan.md`, `session-detail-set-count-plan.md`, `exercise-detail-emphasis-tier-rebalance-plan.md`, `docs-standard-audit-2026-07-30.md`, and plan `2026-10-15-38a-logger-shell-plan.md` itself — all name the removed builders/field.

## Contract test

`flutter test test/docs_indexing_contract_test.dart` via the gateway — final
run, all green:

```
00:00 +12: Docs indexing contract no design doc carries a unit value or a percentage
00:00 +13: All tests passed!
```

Two earlier runs failed on the value scan ("no design doc carries a unit value
or a percentage"): my new catalog entries quoted dp measurements in prose
(7 findings, then 1). Fixed by naming the role instead of the number; the last
finding was the literal test name `tooltips, 48 dp targets and both callbacks
fire`, which the scan cannot skip (it only skips fences and `S-` ids), so the
citation names the group exactly and paraphrases that one test name. The test
file itself is outside this brief's write scope.

## File sizes

The contract test's own size checks pass: "no documentation file exceeds the
indexing ceiling" and "no documentation file is within the warning band of the
ceiling" (both green above), so every edited doc is under the 64 KiB hard
limit and clear of the warning band — well under the 52 KB working limit. (The
`wc -c` shell command is not in this agent's allowed set.)
