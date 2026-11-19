# Plan 91: code review (Phases 1–2)

Reviewer: code-reviewer (Claude Code), 2026-10-29. Read-only run: no source, test or doc edited.

## Code Review: Critical Issues (documentation only; the code does what the plan asks)

Layers in scope: features (exercise library, calendar, add_food), widgets (buttons), tests, docs
Layers skipped: models, persistence, state, core (no change from this plan; `lib/state/*` belongs to another unit)
Diff vs Predicted Files: conforms. Every changed file is predicted, and no predicted file is left untouched. The other units' files (`docs/session_summary.md`, `docs/state_management/workout_state.md`, `session_summary_screen.dart`, `lib/state/*`, `test/watch_*`) are excluded. The plan-91 hunks in the shared files `screen_widget_test.dart`, `nutrition_test.dart` and `ui_standards_contract_test.dart` touch only plan-91 lines. The allowlist is untouched.

### What the reviewer ran (observed output)

- Full suite: `bash .claude/scripts/macos/with-timeout.sh 900 flutter test` → `03:49 +5870 ~2: All tests passed!`, exit 0 (5870 passed, 2 skipped, 0 failed).
- Done Criteria files for both phases, item 6 readers and `interaction_flow_test.dart`, run together → `00:19 +678: All tests passed!`
- `flutter analyze` → `180 issues found.` (baseline 180, 0 errors; exit 1 because of the existing info notices).
- Invariant grep `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty (exit 1).
- A scratch semantics probe (a temporary file under `test/`, deleted afterwards; `ls` confirms it is gone): it pumped the piece in an `OmniBackHeader` and dumped the semantics nodes. Result is in finding W-1.

### Findings

| Sev | Where | Finding | Fix | Agent |
|---|---|---|---|---|
| CRITICAL (doc false) | `docs/README.md:151` | The tree says `widgets/buttons/  # (empty — reserved)`. That folder now holds `omni_header_add_button.dart`, so this change made the line false. | Name `OmniHeaderAddButton` on that line. | @developer |
| CRITICAL (doc false, pre-existing) | `docs/state_management/nutrition_state.md:181`, `docs/data_models.md:412` | Both say new foods are created from an `AddFoodScreen` "+ New Item tab". No such tab exists: the tabs are Library and Categories, and the create action is the header "+" New Food. These are the surface plan 91 moved. | Drop the "+ New Item tab" wording and point at `test/library_merge_test.dart` `S-12814` / `test/nutrition_test.dart` `S-9161`. | @developer |
| CRITICAL (doc standard §4.2) | `docs/calendar_periods.md:114` | "Returning from the list refreshes the calendar" is a claim about behaviour. The cited tests (`S-9155`, `S-9156`) do not check a refresh. The code does refresh (`calendar_screen.dart:171-173`), but nothing proves it. | Delete the sentence, or add a test (create a period in the list, go back, the banding shows) and point at it. | @developer |
| CRITICAL (doc standard §3.2) | `docs/calendar_periods.md:110-113`; `docs/widget_catalog/layout_and_inputs.md:131-132` | Visual description added to non-design docs: "calendar-span icon", "never labelled Periods", "An `Icons.add` `IconButton` at its default size in `OmniTheme.colors.textDominant`, the back arrow's colour". The plan's item 7/8 wording asked for some of this. | Remove the icon, size and colour prose. Keep the structure (what opens what, which piece) and the test pointers already in place. The visual rule lives in `design_system.md` "Header actions" (exempt). | @developer |
| WARNING | `lib/widgets/buttons/omni_header_add_button.dart:75-77` (same pattern at `lib/features/calendar/calendar_screen.dart:98-100`) | The probe found two button nodes for one button: an outer node, label "New Thing", button, **no tap action**, 48×48; and an inner node, tooltip "New Thing", button, tap. A screen reader gets two focus stops and the first cannot be activated. D-91.2 prescribed the wrapper, copying the Stats header pattern. S-9151's `findsWidgets` cannot see this. | Drop the outer `Semantics` (the `IconButton` tooltip already gives label + button; S-2606 accepts a tooltip), or exclude the child's semantics. Guard: in S-9151 and S-9155, assert exactly one semantics node carries the label/tooltip and that it has the tap action. | @developer |
| WARNING (test gap) | `test/nutrition_test.dart:4357` (S-9166) | Only the zero-inset case is tested. The `+ viewPaddingOf(context).bottom` half, which is the reason for D-91.6 (the last row clears the home indicator), is never exercised. | Add a case with `tester.view.viewPadding = FakeViewPadding(bottom: X)` and assert the padding is 16 + X/dpr. | @developer |
| SUGGEST | `lib/features/nutrition/add_food_screen.dart:667,1734` | The same literal `16` appears twice for the list-end padding (prescribed by D-91.6). | Use one named constant (private or an `OmniTheme` token). | @developer |
| SUGGEST | `test/ui_standards_contract_test.dart` `headerPlusFindings` | Header "+" forms the scan misses beyond the documented helper/variable limit: `'+New'` (no space), a full-width `＋`, `Icons.control_point*`, `CupertinoIcons.add/plus/add_circled`. None exists in `lib/` today. The documented limit is honest and real: the Manage Food Library header itself goes through `_buildHeaderAdd(context)`, so the scan cannot see it. S-9161 and S-12818 guard that screen instead. | Follow-up PR: resolve same-file `_build*(` helpers named inside a header call, and widen the icon and text patterns. Name the remaining gaps in the design doc's "Known limit". | @developer |
| SUGGEST | `test/library_merge_test.dart:269` | The S-12814 title still says "Library CTA … Categories tab shows its own CTA". | Retitle it "header +". | @developer |
| SUGGEST | `docs/global_conventions.md:17` | The "Shared UI pieces" job list does not name the new "header add action" job. The doc is incomplete, not false. | Add the job to the list. | @developer |

### Test gaps
- MISSING: `test/omni_header_add_button_test.dart` and `test/header_standardization_test.dart` do not check the one-semantics-node rule (W-1).
- MISSING: `test/nutrition_test.dart` S-9166 has no non-zero bottom inset case.
- STALE: none (the suite is green).

### Mandatory check 2: documentation falsification
DOC FALSIFICATION: REJECT. `docs/README.md:151`: the buttons folder is "empty — reserved", but it now holds `OmniHeaderAddButton`. Fix: name it.
DOC FALSIFICATION: REJECT (pre-existing). `docs/state_management/nutrition_state.md:181` and `docs/data_models.md:412`: "+ New Item tab", but no such tab exists and create is the header "+". Fix: delete the wording and point at S-12814 / S-9161.
DOC FALSIFICATION: PASS for the claims checked in the 9 touched docs: design_system.md, widget_catalog.md, widget_catalog/layout_and_inputs.md, widget_catalog/nutrition_widgets.md, calendar_periods.md, navigation_and_screens.md, create_new_exercise.md, nutrition.md, my_routines.md. Checked against `lib/`: bottom buttons really remain on the day list, Periodization and My Routines. Exercise Library and Manage Food Library use the piece. Keys `exercise_library_new_button`, `new_food_button`, `new_group_button` and `calendar_training_periods_button` are present. Groups `S-9158 header plus`, `S-9151..S-9153 OmniHeaderAddButton`, `AddFoodScreen — header + (S-9161..S-9166)`, `OmniBackHeader presence – CalendarScreen` and `ExerciseLibraryScreen` exist. Tests S-4102, S-4103, S-4106, S-9154, S-9155, S-9156, S-9161, S-9163, S-12810, S-12814 and S-12815 exist.
DOC FALSIFICATION: PASS for untouched docs that mention the surfaces: navigation_and_screens.md:144, session_widgets.md:644, design_system.md:188/380, nutrition_widgets.md:130 (the New Food form still hosts `OmniBottomCTA`), widget_catalog.md:105.
DOC FALSIFICATION: SCOPE. `calendar_periods.md` and `nutrition_widgets.md` have no §4.1 scope block (pre-existing). Treated as implicated and read.
DOC FALSIFICATION: no conflicts found between docs.

### Documentation standard
DOC STANDARD: REJECT. `docs/calendar_periods.md:114`: class §4.2, a behaviour claim with no test. Fix: remove it, or add a test and a pointer.
DOC STANDARD: REJECT. `docs/calendar_periods.md:110-113` and `docs/widget_catalog/layout_and_inputs.md:131-132`: class 2 (visual: icon, size, colour). Fix: remove.
Borderline, not counted: `nutrition.md:111-114` and `nutrition_widgets.md:253-254` say "read aloud `New Food` / `New Category`". These are labels (§3.2), but they replace label prose that was already there and act as identifiers next to the keys. Owner's call.

### Mandatory check 3: scenario fixture conformance
S-9151..S-9166 and S-9165a all build the fixture the plan enumerates: the adversarial S-9158 set F1–F10 plus the line test, the no-match searches in S-9154/S-9165, the two taps in S-9163, the round trip in S-9164, and reduced motion plus slide-off cancel in S-9153. The only notes are W-1 (S-9151's semantics assertion is too loose) and the S-9166 inset gap. The red claims are plausible:
- Phase 1 reds were taken against stubs. S-9159 was red with exactly 2 findings at `calendar_screen.dart:93` and `exercise_library_screen.dart:117`, matching the plan's ≈ lines.
- Phase 2 showed 7 reds with the failure reasons stated. S-9165 had a mutation (header line removed → red; restored → green).
- S-9157 and S-9162 were green both ways by design (regression guards, stated honestly).

### Impact check
IMPACT: PASS. All 18 rows were re-checked by grep: the key readers, `formBottomCTAClearance` (5 remaining uses in `lib/`, none in the Food Library lists), `_openPeriods`, the bottom buttons that stay, and the header `Icons.add`/`'+'` baseline. No new `Icons.add` or `Text('+')` sits in a header call, and no unlisted reader was found.

### Conventions (`docs/global_conventions.md`)
PASS (5): theme tokens only (`textDominant`, `colorScheme` no longer needed), shared UI pieces, fix what you touch (the calendar's allowlist entry is a permanent user-colour exception; no entry added), reuse the canonical owner, instrument panel (restrained motion, reduced motion respected).
N/A (6): units, card chrome, effort-kind, timestamps, initState notify, rest rule (none of these areas changed).

### Architecture
PASS (9): the piece is pure presentation with local press state only; screens get state by injection with no persistence access; no business logic moved; colours come from the theme; the removed `OutlinedButton` lowers the shape surface; `IconButton` has the default 48×48 target (probe: `Size(48.0, 48.0)`); the key sits on the inner `IconButton`; the press shrink uses a `Listener` outside the gesture arena, so `onPressed` is never delayed; with reduced motion `Transform.scale` is used with no animation. Food Library: the label and key follow `_tabController`; the "+" stays during a no-match search (S-9165); there is no `SafeArea` double padding; under the keyboard the body's `viewPadding` is reduced by the insets, so no extra band. No affordance lost.

### Assumption Log
A-1 RATIFY (owner answers). A-2 RATIFY (red shown before the edits is equivalent proof; the tree is shared). A-3 RATIFY. A-4 RATIFY (the plan's item-8 grep contradicted items 4–5; planner nit).

### Plan 78 D-3 override
Recorded in plan 91 D-91.10, in the evidence file ("Plan 78 override"), and in the renamed test `S-13113 / S-9165a`. The plan-78 file itself is unannotated, which is correct: agents do not edit other plans.

### Scope triage
6 substantive findings, all cheap and mechanical (4 doc edits plus 1 small widget change with its guard, 1 test case), so one round in this PR with no split. Scan widening goes to a follow-up PR plan.

Critical: 4 (all documentation) | Warnings: 2 | Suggestions: 4
→ @developer: fix the README line and the two "+ New Item tab" lines; trim calendar_periods.md / layout_and_inputs.md to structure plus pointers; collapse the double semantics node in the piece and the calendar icon, with a one-node guard test; add the S-9166 inset case.

PIPELINE PAUSED: waiting for the owner's decision.
