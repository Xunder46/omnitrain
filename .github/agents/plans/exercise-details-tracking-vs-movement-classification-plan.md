# Feature: Exercise Details — Separate Tracking Methods from Movement Properties

## Overview
The exercise details screen (and its sibling, the library detail surface, which
reuses the same `ExerciseDetailViewBody`) lists every capability recorded
against an exercise under a single `Tracking Methods` heading. That heading
currently leaks non-tracking attributes: `bilateral` describes how the
movement is performed (one limb at a time), not how the exercise is measured,
so showing it under "Tracking Methods" tells the user they can "track by
bilateral" — which is meaningless. Because the heading is generated from the
full capability set without filtering, other exercises will surface other
non-tracking attributes in the same place. This plan classifies every
existing capability, splits movement properties into their own heading, and
hides the heading entirely when its group is empty.

## Requirements
- Classify every capability in `lib/core/constants/capability.dart` into
  exactly one bucket: `tracking`, `movement`, or `internal`.
- Tracking-only section keeps the existing `Tracking Methods` heading and
  chip styling.
- Movement-only section uses a distinct heading (separate from
  `Tracking Methods`) so the two groups are unambiguous in the UI.
- Headings with no content in their group are omitted entirely (no empty
  `Tracking Methods` / no empty movement heading).
- `bilateral` no longer renders under `Tracking Methods`.
- `ExerciseDetailViewBody` is the single source of truth for both groups;
  both `ExerciseDetailViewScreen` (picker flow) and
  `ExerciseLibraryDetailScreen` (management flow) inherit the change
  automatically because they reuse that body.
- The workout screen's metric editors, and the bilateral logging note in
  the in-session info sheet, are not touched.

## Capability Classification (Reviewable)

| Capability | Bucket | Why |
|---|---|---|
| `time` | tracking | A measured value the user records (continuous duration). |
| `hold` | tracking | A measured value the user records (isometric hold duration). |
| `reps` | tracking | A measured value the user records (repetition count). |
| `sets` | tracking | A grouping of measurements the user records (set count). |
| `load` | tracking | A measured value the user records (external weight/resistance). |
| `distance` | tracking | A measured value the user records (distance covered). |
| `rounds` | tracking | A measured value the user records (round/period segments). |
| `bilateral` | movement | Describes how the movement is performed (one limb at a time; log both sides combined). It is not a measurement — it changes how `reps` and `load` are recorded, not what is measured. |
| (none currently) | internal | No capability in the current set is purely internal. If a future capability lands in this bucket it must not appear on the details screen at all. |

Movement heading label: **`Movement Properties`**. Chosen so the two
headings share a parallel noun (`Methods` / `Properties`) and so the label
is faithful to the bucket — these are properties of how the movement is
performed, not methods of measurement.

> If a future capability is added that does not fit either bucket
> (purely internal), the `ExerciseDetailViewBody` change must continue
> to drop it from both sections. The classification table above is the
> single source of truth.

## Acceptance Criteria
- [ ] Tracking Methods section contains only attributes classified as
      tracking (no `bilateral`, no future internal attributes).
- [ ] `bilateral` no longer appears under Tracking Methods.
- [ ] Movement Properties that are worth showing appear under a
      `Movement Properties` heading with their own chip styling.
- [ ] No purely internal capability renders anywhere on the details
      screen.
- [ ] An exercise carrying no tracking methods renders without an empty
      `Tracking Methods` heading.
- [ ] An exercise carrying no movement properties renders without an
      empty `Movement Properties` heading.
- [ ] Chip styling and layout are unchanged (same `_MetaChip`, same
      `_DetailRow`, same Wrap spacing).
- [ ] The workout screen's behavior, including which metric editors it
      shows, is unchanged.
- [ ] The bilateral logging note in the in-session info sheet is
      unchanged.

## Scenarios

### S-001: Bilateral exercise separates bilateral from tracking
- Trigger: Open exercise details for `Arnold Press` (capabilities
  `[reps, sets, load, bilateral, time]`).
- Precondition: `bilateral` is present on the seeded exercise.
- Flow: Render `ExerciseDetailViewBody`.
- Expected outcome: Tracking Methods shows `Reps`, `Sets`, `Load`,
  `Time` (4 chips). A separate `Movement Properties` heading shows
  `Bilateral` (1 chip).
- Edge case of: none

### S-002: Tracking-only exercise shows only Tracking Methods
- Trigger: Open exercise details for `Plank Hold` (capabilities
  `[hold, time, sets]`).
- Precondition: No movement properties present.
- Flow: Render `ExerciseDetailViewBody`.
- Expected outcome: Tracking Methods shows `Hold Time`, `Time`,
  `Sets`. No `Movement Properties` heading is rendered.
- Edge case of: S-001

### S-003: Movement-only exercise shows only Movement Properties
- Trigger: Open exercise details for an exercise whose only capability
  is `bilateral` (constructed in the test, not seeded — see S-006).
- Precondition: A hypothetical exercise whose only attribute is
  movement-property. No real seed exercise matches today; covered by
  a synthetic exercise in tests so we never render an empty
  `Tracking Methods` heading for it.
- Flow: Render `ExerciseDetailViewBody`.
- Expected outcome: `Movement Properties` shows `Bilateral`. No
  `Tracking Methods` heading is rendered.
- Edge case of: S-001

### S-004: Capability-less exercise renders cleanly
- Trigger: Open exercise details for an exercise with no capabilities.
- Precondition: Exercise exists with `capabilities: []`.
- Flow: Render `ExerciseDetailViewBody`.
- Expected outcome: Neither heading is rendered; description, discipline,
  and muscles still collapse cleanly when absent.
- Edge case of: S-002

### S-005: Cross-discipline sample exercises still render correctly
- Trigger: Open exercise details for one exercise per discipline:
  `Arnold Press` (resistance, bilateral), `Plank Hold`
  (isometric, tracking-only), `Easy Run` (cardio, tracking-only),
  `Heavy Bag Rounds` (sports, tracking-only).
- Precondition: Seeded exercises present.
- Flow: Render `ExerciseDetailViewBody` for each.
- Expected outcome: Each renders only the chips appropriate for its
  bucket; bilateral exercises always land under `Movement Properties`.
- Edge case of: S-001, S-002

### S-006: Workout screen metric editors are unchanged
- Trigger: Open any seeded bilateral exercise (e.g. `Arnold Press`)
  inside an active resistance session.
- Precondition: A bilateral-capability resistance exercise exists.
- Flow: Render the workout session screen for that exercise; capture
  the rendered `InlineMetricEditor` metric types.
- Expected outcome: The set of metric editors is exactly the same as
  before this change (`reps`, `weight` for `effortKind == 'set'`).
  No editor is added or removed by re-grouping capabilities on the
  details screen.
- Edge case of: none

### S-007: In-session info sheet bilateral logging note is unchanged
- Trigger: Tap the info control during a session for `Arnold Press`.
- Precondition: A bilateral-capability exercise is loaded.
- Flow: Render `_showExerciseInfoSheet`.
- Expected outcome: `LOGGING NOTE` section is still present, with the
  same text, for bilateral exercises; absent for non-bilateral
  exercises. The change to the details screen does not affect the
  info sheet.
- Edge case of: S-001

## Iteration 1

### DB Changes
None. No model, schema, or seed-data changes. The capability set is
unchanged; only the details-screen rendering buckets them.

### Backend Changes
None. No repository, no service, no state class touched.

### Frontend Changes
- `lib/features/exercise/exercise_detail_view_screen.dart` —
  `ExerciseDetailViewBody` (lines ~165–240): replace the single
  capability `_DetailRow` with two filtered rows. Helper logic is
  added in this file:
  - `Set<String> _trackingCapabilities = const { 'time', 'hold',
    'reps', 'sets', 'load', 'distance', 'rounds' };`
  - `Set<String> _movementCapabilities = const { 'bilateral' };`
  - Local filters:
    `final tracking = exercise.capabilities.where(_trackingCapabilities.contains).toList();`
    `final movement = exercise.capabilities.where(_movementCapabilities.contains).toList();`
  - Render `Tracking Methods` only when `tracking.isNotEmpty`.
  - Render `Movement Properties` (new key
    `exercise_detail_movement_section`) only when `movement.isNotEmpty`.
  - Chip styling, Wrap spacing, and `_MetaChip` are reused unchanged.
- Both rows keep distinct Keys so tests can target each section
  independently:
  - `exercise_detail_capabilities_section` (existing; unchanged key —
    tests targeting it continue to work because it still fires when
    `tracking.isNotEmpty`).
  - `exercise_detail_movement_section` (new).
- `lib/features/session/workout_session_global_timer.dart` — no
  change. The in-session info sheet's bilateral handling stays.
- `lib/features/session/workout_session_screen.dart` and its part
  files (`workout_session_detail_view.dart`,
  `workout_session_list_view.dart`, etc.) — no change. Metric editors
  are switched on `effortKind`, not on `capabilities`, so the
  re-grouping does not affect them.

### Implementation Steps
1. **TDD red**: write the scenario tests in `test/exercise_details_capability_grouping_test.dart`
   (or extend an existing test file if the mapping says so — see test
   map below). Tests must reference the live `ExerciseDetailViewBody`
   with `MockWorkoutRepository`, never a concrete repo, and must
   call state methods directly.
2. **Confirm red run** before any implementation edit.
3. Implement the split in `ExerciseDetailViewBody` and add the
   `Movement Properties` heading.
4. Run full suite — all Phase 0 scenario tests green, no previously
   passing tests broken.
5. Doc hygiene: `docs/navigation_and_screens.md` if the screen
   description needs to mention the new section; otherwise no doc
   change is needed because the body widget is unchanged from
   outside.

## Test File Map (per Phase 2.1)

| Changed code area | Expected test file |
|---|---|
| `lib/features/exercise/exercise_detail_view_screen.dart` | new `test/exercise_details_capability_grouping_test.dart` (render + assertion); cross-discipline assertions in same file. |
| Workout screen unchanged — covered by existing `test/workout_state_*` and existing screenshot/widget tests. The S-006 and S-007 scenarios are covered by exercising the existing in-session rendering against a bilateral exercise; new test file optional. |

Test mapping rules (Phase 2.1) say render tests land in
`test/screen_widget_test.dart` and interaction flows in
`test/interaction_flow_test.dart`. The closest existing analogue to
this work is `test/pr7_exercise_details_view_test.dart`. Because the
test surface here is small and tightly scoped to the body widget, a
new dedicated file is the clearest expression of intent; the
alternative would extend `pr7_exercise_details_view_test.dart` with
a new group. **Decision**: new file
`test/exercise_details_capability_grouping_test.dart` to keep the
scenario register self-contained and avoid touching the
already-approved PR 7 test surface.

## Unit Tests Required (rewrite + add)

Add (all in `test/exercise_details_capability_grouping_test.dart`):

- **T1 (S-001)**: Arnold Press (`[reps, sets, load, bilateral, time]`)
  renders `Tracking Methods` with exactly `Reps`, `Sets`, `Load`,
  `Time` chips and `Movement Properties` with exactly `Bilateral`.
  No `Bilateral` chip is found inside the `Tracking Methods` section.
- **T2 (S-002)**: Plank Hold (`[hold, time, sets]`) renders
  `Tracking Methods` with `Hold Time`, `Time`, `Sets` and does NOT
  render a `Movement Properties` section.
- **T3 (S-003)**: Synthetic movement-only exercise (`[bilateral]`)
  renders `Movement Properties` with `Bilateral` and does NOT
  render a `Tracking Methods` section.
- **T4 (S-004)**: Capability-less exercise (`capabilities: const []`)
  renders neither heading.
- **T5 (S-005)**: Cross-discipline sample (`Arnold Press`, `Plank Hold`,
  `Easy Run`, `Heavy Bag Rounds`) — each renders only the chips
  appropriate for its bucket.
- **T6 (S-006)**: Workout screen for a bilateral-capability exercise
  in a resistance session renders exactly the same `InlineMetricEditor`
  metric types it did before (`reps`, `weight`); the metric editor
  set is unchanged after the details-screen change.
- **T7 (S-007)**: In-session info sheet for a bilateral exercise
  still shows `LOGGING NOTE`; for a non-bilateral exercise still
  omits `LOGGING NOTE`. Asserted via the existing bilateral info
  sheet test surface (`test/exercise_info_sheet_bilateral_test.dart`)
  — it must remain green; no new assertion needed because the
  info sheet is not touched.

Rewrite / update:

- **T-rewrite-1**: The existing `discipline + capabilities + muscles
  render when present` test in
  `test/pr7_exercise_details_view_test.dart` (lines ~380–410) — its
  test exercise has `capabilities: const ['time', 'distance']` (both
  tracking). It asserts
  `find.byKey(const Key('exercise_detail_capabilities_section'))`
  is present. Because both `time` and `distance` are tracking
  methods, the section still renders. The assertion is still
  valid; no rewrite is required for this case.
- **T-rewrite-2**: Search results show no test asserting a specific
  count of chips under `Tracking Methods`. The PR 7 test that does
  mention capabilities uses only tracking capabilities and remains
  valid. No further rewrite needed.

## Progress
- [x] Phase 0 — Plan
- [x] Phase 1 — Data layer (N/A — no schema/model/repo changes; only frontend re-grouping)
- [x] Phase 2 — TDD red, implementation, green
  - TDD red run recorded: S-001, S-003, S-005 failed as expected
    (bilateral chip found inside Tracking Methods; movement section
    key not found). S-002, S-004, S-006, S-007 already green.
  - Implementation: split the single capability `_DetailRow` in
    `ExerciseDetailViewBody` into two filtered rows. Tracking caps
    live under "Tracking Methods" (existing key
    `exercise_detail_capabilities_section`); movement caps live
    under "Movement Properties" (new key
    `exercise_detail_movement_section`). Both rows are omitted
    when their filtered list is empty. Classification sets
    (`_trackingCapabilities`, `_movementCapabilities`) live as
    private static const on `ExerciseDetailViewBody`.
  - Test file added: `test/exercise_details_capability_grouping_test.dart`
    (7 tests across S-001..S-007).
  - Full suite: 2096 / 2096 pass, 5 pre-existing skipped, 0 failures
    (baseline was 2088 / 2088 before this work; +8 net new tests
    attributable to the new grouping test file plus inline widget
    helper discovery). No previously passing tests broken.
  - Doc hygiene: `docs/navigation_and_screens.md` updated — the
    `ExerciseDetailViewScreen` inventory row now reflects the
    split (Tracking Methods + Movement Properties), the new
    section key, and the heading-omit-empty contract.
- [ ] Phase 3 — Code review

## Feedback

### Phase 0 Complete ✓
### Phase 1 Complete ✓ (N/A — pure presentation re-grouping)
### Phase 2 Complete ✓
