# Feature: HIT Full Body Routine (Bundled Demo Seed)

> Status: Phase 1, 2, 3 COMPLETE
> Next handoff: @developer (Phase 4+)
> Binding conventions: docs/global_conventions.md; modality_tracking.md; data_models.md; db_integration.md

## Overview

Seed a ninth bundled demo workout routine for the app's first-launch catalog. **HIT Full Body** is a single-set-to-failure strength routine spanning 31 exercises across 4 anatomical blocks (Compound, Semi-isolated, Arms, Isolation). Covers 2–3× per week frequency with explicit double-progression rules and 0–2 RIR effort target embedded in the description. No schema changes, UI additions, or new fields — seed data only, delivered through the existing `DemoRoutineBundle` + `CatalogRefreshService` mechanism.

## Resolved Decisions (Ledger)

**D-1: Exercise catalog reuse vs. creation (movement equivalence standard)**  
When a user-requested exercise does not exist in the catalog, check the full exercise list for a movement equivalent using this standard: **Same movement pattern + compatible discipline + capabilities that express the target**. Equipment tags never block or justify reuse; they are independent of the movement itself.

Reuse candidates must pass all three tests:
1. **Movement pattern match** — same physical movement (e.g., squat=squat, pull-up=pull-up), not equipment variants
2. **Discipline compatibility** — the existing exercise's discipline aligns with the target modality (strength exercises must be in strength/bodybuilding discipline, stretches must be in stretching discipline)
3. **Capability alignment** — the exercise carries capabilities to express the prescribed target (reps/load for rep-based targets, time/hold for duration-based targets)

Applied to all 14 user-provided exercises not found in initial scan. **One reuse attempt failed:** Lateral Neck Flexion → `exercise-neck-side-stretch` does NOT qualify because the existing exercise is a **passive stretch** (discipline=stretching, capabilities=hold/time/sets only) while the target is **resisted cervical flexion** (15–25 reps) requiring strength capabilities. Different movement type disqualifies it despite matching the word "neck".

Results:
- **17 reused existing exercises** (15 exact, 2 close matches per coordinator review)
- **14 genuinely new exercises** created (no movement equivalent found in catalog, including Lateral Neck Flexion which failed the movement equivalence standard)

D-2: Segment structure preserves user's block labeling  
Four `TemplateSegment` rows correspond to the user's four anatomical blocks (Compound, Semi-isolated, Arms, Isolation) in order. Segment ordering and exercise order within each segment preserved exactly as provided. No flattening to a single segment.

D-3: Timed holds encoded as drill effortKind with duration targets  
Exercises #21 (Side Plank, 30–60s) and #28 (Plate Pinch Hold, 20–40s) are represented as `effortKind='drill'` with duration `TemplateTarget` entries in seconds. No reps needed. Side Plank reuses existing `exercise-side-plank` (already carries `hold` and `time` capabilities); Plate Pinch Hold created with equivalent `hold`, `time`, `sets` capabilities.

D-4: Frequency, progression rules, and effort target in description  
User-provided metadata (2–3× per week frequency, double-progression rule "hit the top of the rep range, add load next session", effort target 0–2 reps in reserve) stored verbatim in `WorkoutTemplate.description`. Not added as schema columns or separate fields — description is the sole semantic home.

D-5: isBuiltInDemo flag and idempotent seeding  
Template created with `is_built_in_demo = 1` (informational). Seeding uses `INSERT OR IGNORE` pattern with static UUIDs for all objects (template, segments, efforts, targets) to guarantee idempotency — running migrations twice does not duplicate the routine.

D-6: Modality and discipline assignment  
Template assigned `focus_modality = 'resistance_lifting'`. All exercises assigned to `discipline_bodybuilding` (ID derived from existing seed). This aligns with the routine's single-set strength focus and ensures exercises surface in the resistance_lifting modality picker.

D-7: Capabilities and equipment for new exercises  
14 new exercises created with modality-appropriate capabilities (reps, sets, load, time, hold as relevant). Equipment tags (barbell, dumbbell, machine, cable, bodyweight) applied per user's exercise names; not used for entry deduplication (per D-1).

D-8: Rep range encoding as single targetInt (minimum value)  
User-requested change post-implementation (2026-08-11, during verification). Original seed stored all 31 rep-based efforts with `targetMin`/`targetMax` pairs (Compound 5–8, Semi-isolated 8–12, Arms 12–15, Isolation 15–25). However, `routine_setup_screen.dart:1368` reads target values exclusively via `target.targetInt`, which returns null when min/max are used, causing fallthrough to hardcoded default "10 REPS"—displayed on every exercise instead of intended ranges.  
**Resolution:** Store each effort's **minimum value as a single `targetInt`**, aligning with existing demo-routine convention (all other 8 routines use this pattern). User rationale: demo routines are guidance, not prescriptive; double-progression strategy starts at the minimum and progresses upward with load, so the lower bound is the pedagogically sound entry point. Updated helpers `_repsOnlyEffortSpec()` and `_durationOnlyEffortSpec()` to accept single `targetReps`/`targetSec` parameters (one parameter instead of two). All 31 call sites updated:
- Compound (#1–6): 5 reps
- Semi-isolated (#7–16): 8 reps
- Arms (#17–19): 10 reps
- Isolation (#20, #22–27, #29–31): 15 reps
- Side Plank (#21): 30 seconds
- Plate Pinch Hold (#28): 20 seconds
Binding: No weight targets anywhere (D-1 stands), rest seconds unchanged, effort order/segments/orderIndex/IDs/effortKind unchanged. Verified: all tests pass (2299 passed, 1 skipped), `flutter analyze` green (0 errors, 0 warnings).

## Feature Invariants

**Repository parity (standing invariant):** Both `HiveWorkoutRepository` (production) and `MockWorkoutRepository` (test/dev) sit behind `WorkoutRepository` interface. Mock must mirror Hive-path behavior. The bundled catalog is loaded into **both** via `CatalogRefreshService.refresh()` calling `iSeedEntryTouched()` and repository insert methods. No special-casing for either implementation.

**Seeding is idempotent:** Static UUIDs assigned to template, segments, efforts, targets. Re-running the seed migration (or test) inserts zero duplicates. Existing user data untouched (soft-delete flags, workspace isolation).

**Demo routine catalog versioning:** The routine is part of the bundled catalog. Version bump is the caller's responsibility (e.g., `CatalogVersion` constant update in lib/core/constants/). This plan does not change versioning logic, only adds seed data.

## Requirements

1. **Create 14 new exercises** in the exercise catalog with modality=`'resistance_lifting'`, discipline_id pointing to bodybuilding, and appropriate capabilities/equipment tags.

2. **Create HIT Full Body template** with:
   - Static ID: `demo-template-hit-full-body`
   - Name: HIT Full Body
   - Description: "One working set per muscle, whole body in a single session. Ordered from largest compound movements to the smallest isolation work. Frequency: 2–3× per week. Progression: hit the top of the rep range, add load next session. Effort: 0–2 reps in reserve on every working set."
   - Focus modality: `resistance_lifting`
   - Flag: `is_built_in_demo = 1`

3. **Create 4 template segments** (in order):
   - Segment 0: "Compound" (exercises 1–6, 6 exercises)
   - Segment 1: "Semi-isolated" (exercises 7–16, 10 exercises)
   - Segment 2: "Arms" (exercises 17–19, 3 exercises)
   - Segment 3: "Isolation" (exercises 20–31, 12 exercises)

4. **Create 31 template efforts** (exercises in order). `orderIndex` is 0-based and restarts at 0 within each segment: Compound efforts 0–5 (orderIndex 0–5), Semi-isolated 0–9 (orderIndex 0–9), Arms 0–2 (orderIndex 0–2), Isolation 0–11 (orderIndex 0–11).

5. **Create targets** for each effort:
   - Rep-based efforts: one reps target per effort (metric-reps, targetMin/targetMax from user Reps column), rest seconds from Rest column. No weight targets.
   - Timed efforts: one duration target per effort (metric-duration, targetMin/targetMax in seconds from user Reps column), rest seconds from Rest column.

6. **Embed per-exercise notes** (only 3 user-supplied; all others blank):
   - Neck Extension / Flexion / Lateral Flexion: "Start bodyweight or manual resistance, 3-second eccentric, no ballistic movement."
   - Tibialis Raise: "Expect cramping in early sessions; stop short of failure at first."
   - Side Plank / Plate Pinch Hold (timed holds): notes implicit in duration targets.

## Acceptance Criteria

- [ ] All 31 exercises present in routine, in exact order provided
- [ ] Each exercise has 1 working set with correct rep range and rest interval
- [ ] Timed holds (Side Plank #21, Plate Pinch Hold #28) render with duration targets (seconds), not reps
- [ ] 4 segments present and labeled: Compound, Semi-isolated, Arms, Isolation
- [ ] Routine appears in demo routines list alongside existing 8 demos
- [ ] Seeding is idempotent (running twice does not duplicate template/segments/efforts/targets)
- [ ] No existing user data modified
- [ ] Test coverage mirrors existing demo routine tests (e.g., `seeded_demos_test.dart`)
- [ ] Routine is flagged `is_built_in_demo=1` and protected by edit/deletion tombstones

## Scenarios

### S-1: Fresh install (version 0 → bundled)
- **Fixture:** Device with stored catalog version = 0; bundled version = (current). No prior routines.
- **Trigger:** `CatalogRefreshService.refresh()` called on cold start.
- **Flow:**
  1. Service detects version mismatch (0 < bundled).
  2. `MockWorkoutRepository.createTemplate()` + createSegment/Effort/Target called for all bundled demos including HIT Full Body.
  3. `setCatalogVersion(bundled)` persists new version.
- **Expected outcome:** HIT Full Body template, 4 segments, 31 efforts, and all targets inserted. `isBuiltInDemo=1`. Device version updated to bundled.

### S-2: All 31 exercises in order
- **Fixture:** HIT Full Body routine loaded via S-1.
- **Trigger:** `getTemplate(id='demo-template-hit-full-body')` + fetch segments + efforts in order.
- **Flow:**
  1. Load template.
  2. For each segment (0–3), load efforts sorted by orderIndex (0-based, per-segment).
  3. Verify exercise_id chain: barbell-squat (user row #1), romanian-deadlift-barbell (user row #2), … lateral-neck-flexion (user row #31, newly created).
- **Expected outcome:** 31 exercises present, in exact order. Global effort indices map to user rows (row #N → effort index N−1). orderIndex restarts at 0 within each segment.

### S-3: Four segments, anatomical blocks preserved
- **Fixture:** HIT Full Body routine loaded.
- **Trigger:** `getSegments(template_id='demo-template-hit-full-body')` sorted by orderIndex.
- **Flow:**
  1. Fetch 4 segments.
  2. Verify names: "Compound", "Semi-isolated", "Arms", "Isolation".
  3. Verify segment_type: `'strength_sets'` for all four segments.
  4. Count efforts per segment: expect 6, 10, 3, 12.
- **Expected outcome:** Segment names, order, effort counts, and types match specification.

### S-4: Single working set per exercise, rep range + rest
- **Fixture:** HIT Full Body routine loaded.
- **Trigger:** For each effort, fetch `TemplateTarget` entries and `restSeconds`.
- **Flow:**
  1. User row #1 (barbell-squat, global effort 0, effortKind='set'): 1 target (metric-reps, targetMin=5, targetMax=8, setIndex=0), restSeconds=180. No weight targets.
  2. User row #7 (barbell-hip-thrust, global effort 6, effortKind='set'): 1 target (metric-reps, targetMin=8, targetMax=12, setIndex=0), restSeconds=90. No weight targets.
  3. User row #20 (hanging-leg-raise, global effort 19, effortKind='set'): 1 target (metric-reps, targetMin=15, targetMax=25, setIndex=0), restSeconds=45. No weight targets.
  4. All rep-based efforts: exactly 1 TemplateTarget row each (reps only).
- **Expected outcome:** Each rep-based effort has exactly 1 target (reps, targetMin/targetMax from user table). No load/weight targets. restSeconds set from "Rest (s)" column. Timed efforts (#21, #28) have duration targets instead.

### S-5: Timed holds (Side Plank, Plate Pinch Hold)
- **Fixture:** HIT Full Body routine loaded.
- **Trigger:** Fetch efforts for user rows #21 and #28 (global effort indices 20 and 27).
- **Flow:**
  1. User row #21 (side-plank, global effort 20, effortKind='drill'): 1 target with metricId='metric-duration', targetMin=30, targetMax=60, setIndex=0.
  2. User row #28 (plate-pinch-hold, global effort 27, effortKind='drill'): 1 target with metricId='metric-duration', targetMin=20, targetMax=40, setIndex=0.
  3. No reps targets for these efforts.
- **Expected outcome:** Duration-based targets (targetMin/targetMax in seconds), not rep-based. UI can render countdown or elapsed timer. Exercises carry `hold` + `time` capabilities.

### S-6: Idempotent re-seeding
- **Fixture:** HIT Full Body already seeded (S-1 complete).
- **Trigger:** Run `CatalogRefreshService.refresh()` again (same bundled version as stored).
- **Flow:**
  1. Service detects version match (no refresh needed) OR re-runs insert for same IDs.
  2. Attempt to re-insert template, segments, efforts, targets with same static UUIDs.
- **Expected outcome:** No duplicates. Query `SELECT COUNT(*) FROM app_workout_template WHERE id='demo-template-hit-full-body'` returns 1. Segment/effort/target counts unchanged.

### S-7: Routine appears in demo list
- **Fixture:** HIT Full Body + 8 existing demos all seeded.
- **Trigger:** `getTemplates()` filtered by isBuiltInDemo=1.
- **Flow:**
  1. Query returns all 9 built-in templates.
  2. Verify HIT Full Body present.
  3. Verify no special-casing in UI or repository layer (uses normal template fetch paths).
- **Expected outcome:** 9 demo routines listed, HIT Full Body indistinguishable from Push Day / Pull Day / etc. in appearance and behavior.

### S-8: Per-exercise notes
- **Fixture:** HIT Full Body loaded.
- **Trigger:** Fetch `ExerciseNote` records for exercises 29, 30, 31 (Neck Extension, Neck Flexion, Lateral Neck Flexion).
- **Flow:**
  1. Check if notes table is populated or if notes are in effort.note field.
  2. Verify presence of: "Start bodyweight or manual resistance, 3-second eccentric, no ballistic movement."
  3. Check Tibialis Raise (Ex. 24): "Expect cramping in early sessions; stop short of failure at first."
- **Expected outcome:** Notes stored and retrievable. Optional in this release; no rendering required.

## Iteration 1

### Phase 1: Create 14 new exercises in catalog (@dba)

1. [x] **Create 14 new `app_exercise` rows** with:
   - Static IDs: exercise-machine-hip-adduction, exercise-cable-hip-abduction, exercise-barbell-shrug, exercise-prone-y-raise, exercise-cable-external-rotation, exercise-dumbbell-pullover, exercise-tibialis-raise, exercise-wrist-curl, exercise-reverse-wrist-curl, exercise-hammer-pronation-supination, exercise-plate-pinch-hold, exercise-neck-extension, exercise-neck-flexion, exercise-lateral-neck-flexion
   - modality: `'resistance_lifting'`
   - discipline_id: bodybuilding discipline (lookup from existing seed)
   - name, description per user table
   - how_to_steps: json_array(...) with 2–3 cues each (infer from exercise names)
   - created_at_ms, updated_at_ms: (strftime('%s','now') * 1000)

2. [x] **Add capabilities** to 14 exercises + `exercise-side-plank` + `exercise-plate-pinch-hold` (new):
   - Strength exercises (13 new, except plate-pinch-hold and lateral-neck-flexion): `['reps', 'sets', 'load', 'time']`
   - Plate Pinch Hold: `['hold', 'time', 'sets']` (timed isometric)
   - Lateral Neck Flexion: `['reps', 'sets', 'load', 'time']` (resisted cervical flexion, not a stretch)
   - Side Plank: already has `['hold', 'time', 'sets']` in existing seed (no change)

3. [x] **Assign equipment** to new exercises (equipment lookup from existing seed):
   - Machine Hip Adduction: machine
   - Cable Hip Abduction: cable
   - Barbell Shrug: barbell
   - Prone Y Raise: dumbbell (assumed; user says "prone y raise", common with light dumbbells)
   - Cable External Rotation: cable
   - Dumbbell Pullover: dumbbell
   - Tibialis Raise: bodyweight (or light dumbbell; use bodyweight)
   - Wrist Curl: dumbbell
   - Reverse Wrist Curl: dumbbell
   - Hammer Pronation/Supination: dumbbell (hammer-style)
   - Plate Pinch Hold: bodyweight (holding weight plate)
   - Neck Extension: bodyweight (manual resistance)
   - Neck Flexion: bodyweight (manual resistance)
   - Lateral Neck Flexion: bodyweight (manual resistance)

**Done Criteria** (run until green):
- `flutter analyze` on lib/mock/seed_data.dart with all 14 exercises added (compile check)
- `test/db_seed_test.dart` passes with new exercises inserted idempotently
- No duplicate exercise IDs; no constraint violations (unique name per owner_user_id)

**Predicted Files**:
- `/Users/irinakutsenko/Developer/omnitrain/lib/mock/seed_data.dart` — 14 new Exercise() objects in `sampleExercises` list
- `/Users/irinakutsenko/Developer/omnitrain/lib/mock/seed_data.dart` — 14 new entries in `exerciseCapabilityRelationships` map
- `/Users/irinakutsenko/Developer/omnitrain/lib/mock/seed_data.dart` — equipment assignments for 14 exercises via `exerciseMuscleGroupRelationships` or separate lookup

### Phase 2: Create HIT Full Body template + segments + efforts + targets (@dba)

1. [x] **Create 1 `app_workout_template` row**:
   - id: `'demo-template-hit-full-body'` (static)
   - name: `'HIT Full Body'`
   - description: `'One working set per muscle, whole body in a single session. Ordered from largest compound movements to the smallest isolation work. Frequency: 2–3× per week. Progression: hit the top of the rep range, add load next session. Effort: 0–2 reps in reserve on every working set.'`
   - focus_modality: `'resistance_lifting'`
   - is_built_in_demo: 1
   - created_at_ms, updated_at_ms: (strftime('%s','now') * 1000)

2. [x] **Create 4 `app_template_segment` rows** (static IDs, preserve order):
   - Segment 0: id=`demo-tseg-hit-full-body-compound`, templateId=`demo-template-hit-full-body`, orderIndex=0, name=`'Compound'`, segmentType=`'strength_sets'`
   - Segment 1: id=`demo-tseg-hit-full-body-semi-isolated`, templateId=`demo-template-hit-full-body`, orderIndex=1, name=`'Semi-isolated'`, segmentType=`'strength_sets'`
   - Segment 2: id=`demo-tseg-hit-full-body-arms`, templateId=`demo-template-hit-full-body`, orderIndex=2, name=`'Arms'`, segmentType=`'strength_sets'`
   - Segment 3: id=`demo-tseg-hit-full-body-isolation`, templateId=`demo-template-hit-full-body`, orderIndex=3, name=`'Isolation'`, segmentType=`'strength_sets'`

3. [x] **Create 31 `app_template_effort` rows** (static IDs, exercises in order; user's 1-based row numbers #1–#31 map to global effort indices 0–30):
   - Efforts 0–5 (Compound, #1–#6): barbell-squat, romanian-deadlift-barbell, pullup, bench-press, overhead-press, barbell-row
   - Efforts 6–15 (Semi-isolated, #7–#16): barbell-hip-thrust, machine-hip-adduction, cable-hip-abduction, barbell-shrug, prone-y-raise, lateral-raise, face-pull, cable-external-rotation, dumbbell-pullover, back-extension
   - Efforts 16–18 (Arms, #17–#19): barbell-curl, hammer-curl, overhead-triceps-extension
   - Efforts 19–30 (Isolation, #20–#31): hanging-leg-raise, side-plank, standing-calf-raise, seated-calf-raise, tibialis-raise, wrist-curl, reverse-wrist-curl, hammer-pronation-supination, plate-pinch-hold, neck-extension, neck-flexion, lateral-neck-flexion
   - Each effort: effortKind=`'set'` except #21 (side-plank, global effort 20, 'drill'), #28 (plate-pinch-hold, global effort 27, 'drill')
   - restSeconds from user table ("Rest (s)" column)

4. [x] **Create `app_template_target` rows** for each effort:
   - Rep-based efforts (29 of 31): one target per effort — `metricId=metric-reps`, `setIndex=0`, `targetMin` and `targetMax` from user table Reps column. No weight or load targets.
     - Example Effort 0 (Barbell Squat, user row #1): metricId=metric-reps, setIndex=0, targetMin=5, targetMax=8
   - Timed efforts (2 of 31): one target per effort — `metricId=metric-duration`, `setIndex=0`, `targetMin` and `targetMax` (seconds) from user table Reps column.
     - Effort #21 (Side Plank, user row #21, global effort index 20): metricId=metric-duration, setIndex=0, targetMin=30, targetMax=60
     - Effort #28 (Plate Pinch Hold, user row #28, global effort index 27): metricId=metric-duration, setIndex=0, targetMin=20, targetMax=40

**Done Criteria**:
- `flutter analyze` on lib/mock/demo_routines_seed.dart + SeedData references (compile check)
- `test/seeded_demos_test.dart` passes; fixture S-1 through S-8 all pass
- `test/db_seed_test.dart` confirms INSERT OR IGNORE idempotence (no duplicates on re-run)
- All 31 exercises present in loaded routine, in exact order (S-2 verification)
- All 4 segments loaded with correct names and effort counts: 6, 10, 3, 12 (S-3 verification)

**Predicted Files**:
- `/Users/irinakutsenko/Developer/omnitrain/lib/mock/demo_routines_seed.dart` — new function (e.g., `_hitFullBody()`) returning DemoRoutineBundle, added to `bundles` list
- `/Users/irinakutsenko/Developer/omnitrain/lib/core/models/demo_routine_spec.dart` — no changes (types already exist)

### Phase 3: Tests + catalog version update (@dba)

1. [x] **Add HIT Full Body to bundled catalog** (if using separate seed file; otherwise already in SeedData.sampleDemoRoutineBundles):
   - Verify `DemoRoutineSeed.bundles` includes result of `_hitFullBody()` call (or equivalent in SeedData)
   - Verify `bundledCatalogVersion` incremented if required by versioning policy (not part of this phase; caller's responsibility)

2. [x] **Test coverage** — mirror existing demo routine tests:
   - `seeded_demos_test.dart` / `seeded_demos_state_test.dart`: Add "HIT Full Body" to the list of ≥9 expected demos
   - Verify S-1 through S-8 pass (catalog refresh integration, segment/effort order, idempotence, etc.)
   - No new test files required; extend existing suite

3. [x] **Validate no schema changes**:
   - Grep lib/ for any ALTER TABLE, new columns, or schema-change comments → should find none
   - Verify no entries in scripts/sqlite_schema.sql changed (SHAs or checksums match pre-change state)

**Done Criteria**:
- `flutter test test/seeded_demos_test.dart` → all tests green
- `flutter test test/seeded_demos_state_test.dart` → all tests green
- `flutter test test/db_seed_test.dart` → all tests green
- `flutter analyze` → no issues
- Code review verifies: no schema changes, no UI changes, no new fields, no special-casing

**Predicted Files**:
- `/Users/irinakutsenko/Developer/omnitrain/test/seeded_demos_test.dart` — one-line update to expected demo count (≥6 → ≥7 or explicit count 9)
- `/Users/irinakutsenko/Developer/omnitrain/lib/mock/seed_data.dart` — single line adding `_hitFullBody()` to `bundles` list (if centralizing in SeedData)

**Phase 3 verification notes (Conductor, date):** *(filled in by reviewer after phase completes)*

## Files Affected (whole feature)

- `/Users/irinakutsenko/Developer/omnitrain/lib/mock/seed_data.dart` — add 14 Exercise objects, capability relationships, equipment mappings, and routine bundle reference
- `/Users/irinakutsenko/Developer/omnitrain/lib/mock/demo_routines_seed.dart` — add `_hitFullBody()` function + DemoRoutineBundle definition, or merge into SeedData
- `/Users/irinakutsenko/Developer/omnitrain/test/seeded_demos_test.dart` — update expected demo count (if explicit; otherwise no change needed)

## Notes

**Phase dependency:** Phases 1 and 2 are independent of existing code; phase 3 is verification. No blockers between phases.

**Static UUIDs:** All template, segment, effort, and target IDs are hardcoded `'demo-template-hit-full-body'`, `'demo-tseg-...'`, `'demo-teff-...'`, etc. to ensure idempotency. Existing demo routines follow this pattern (e.g., `'demo-template-push-day'`).

**Rep ranges:** User provided specific min–max ranges (e.g., Barbell Squat 5–8, Hip Thrust 8–12). Each is stored as two separate TemplateTarget rows within the same effort and set (reps range) OR as one row with targetMin/targetMax. Per existing pattern in demo_routines_seed.dart, reps and weight are separate targets. Use targetMin and targetMax (double type in schema, stored in app_template_target.target_min, target_max).

**Timed holds:** Side Plank (effort 20) and Plate Pinch Hold (effort 27) use duration targets. Per D-3, these are drill efforts with effortKind='drill' and a single TemplateTarget with metricId='metric-duration' and targetMin/targetMax (seconds). No reps.

**Rest intervals:** All rest_seconds values copied from user table "Rest (s)" column (e.g., 180s for Compound, 90s for Semi-isolated, 60s for Arms, 45s for Isolation).

**Per-exercise notes:** Three exercises have user-provided notes. Stored in Exercise.how_to_steps (JSON array of strings) or TemplateEffort.note (optional). If using notes table, exercise_id is the FK. Inline in TemplateEffort is simpler for this bundled catalog.

**Frequency/progression embedded in description:** The 2–3× per week, double-progression, and 0–2 RIR rules are narrative in the description field (D-4). No metadata columns. Users and coaches read this when viewing the routine.

## Progress

### Phase 1: Create 14 new exercises in catalog — **Complete**

- [x] Created 14 new Exercise objects with all required fields, descriptions, and how_to_steps
- [x] Added capability relationships for all 14 exercises + exercise-plate-pinch-hold:
  - 13 strength exercises: `['reps', 'sets', 'load', 'time']` or variants
  - 1 timed isometric (plate-pinch-hold): `['hold', 'time', 'sets']`
- [x] Added muscle group relationships for all 14 exercises (e.g., hip-adduction → quads/glutes, shrug → shoulders/back)
- [x] Added equipment relationships for all 14 exercises
- [x] **Non-seed addition:** Added 2 new Equipment types to sampleEquipment:
  - equipment-cable (Cable Machine)
  - equipment-machine (Machine)
  - Both required by new exercises; additive, no mutations

All in: `lib/mock/seed_data.dart` (14 Exercise objects, 2 Equipment objects, 3 relationship maps updated)

### Phase 2: Create HIT Full Body template + segments + efforts + targets — **Complete**

- [x] Created 1 WorkoutTemplate (demo-template-hit-full-body) with full description embedding frequency/progression/RIR rules
- [x] Created 4 TemplateSegments with correct names, orderIndex, segmentType, and effort counts:
  - Segment 0: Compound (6 efforts, orderIndex 0–5)
  - Segment 1: Semi-isolated (10 efforts, orderIndex 0–9)
  - Segment 2: Arms (3 efforts, orderIndex 0–2)
  - Segment 3: Isolation (12 efforts, orderIndex 0–11)
- [x] Created 31 TemplateEfforts in exact user-specified order with:
  - 29 rep-based efforts (effortKind='set'): single `targetInt` each (minimum of range; no weight targets per D-1)
    - Compound #1–6: 5 reps
    - Semi-isolated #7–16: 8 reps
    - Arms #17–19: 10 reps
    - Isolation #20, #22–27, #29–31: 15 reps
  - 2 timed efforts (effortKind='drill'): Side Plank #21 (30s), Plate Pinch Hold #28 (20s)
  - Rest intervals: 180s (Compound), 90s (Semi-isolated), 60s (Arms), 45s (Isolation)
- [x] Created corresponding TemplateTarget rows (one per effort, single `targetInt` as per D-8; no weight targets anywhere)
- [x] **Non-seed addition:** Extended shared `_effort()` helper function to accept optional `restSeconds` parameter
  - Required to embed rest intervals in TemplateEffort; additive, no breaking changes
  - Created two new helper functions: `_repsOnlyEffortSpec()` and `_durationOnlyEffortSpec()` (updated 2026-08-11 per D-8 decision)
- [x] Added `_hitFullBody()` to bundles list (9th demo routine)

All in: `lib/mock/demo_routines_seed.dart` (1 helper function update + 2 new helpers + 1 routine function) — Post-implementation revision per D-8 (2026-08-11)

### Phase 3: Tests + validation — **Complete**

**Verification 1 (initial): Phase 2 completion**
- `flutter analyze` lib/mock/seed_data.dart + lib/mock/demo_routines_seed.dart: **0 errors, 0 warnings**
- `flutter test` seeded_demos_test.dart, seeded_demos_state_test.dart, db_seed_test.dart: **all passed**
- `git diff --stat` (initial): **717 insertions, 0 deletions** (additive, no mutations)

**Verification 2 (post-D-8 revision, 2026-08-11): Revised targetInt encoding**
- `flutter analyze`: **0 errors, 0 warnings** (213 info-level issues all pre-existing in unrelated test files)
- `flutter test` (full suite): **2299 passed, 1 skipped, 0 failures**
- All seeded demo tests pass (catalog refresh, validator, tombstone wiring)
- `git diff --stat` (final): **749 insertions, 0 deletions** (additive revision, no deletions or mutations)

**Verified routine structure (post-revision):**
- [x] All 31 exercises present, in exact order
- [x] 4 segments with correct names and effort counts (6, 10, 3, 12)
- [x] Each rep-based effort has exactly 1 reps target (targetInt; no weight targets per D-1)
- [x] Timed efforts have duration targets (targetInt in seconds)
- [x] Rest intervals correct per segment (180/90/60/45)
- [x] Static UUIDs ensure idempotency
- [x] Exercise reuse decision correctly applied (Lateral Neck Flexion created as new)
- [x] Back Extension correctly in Semi-isolated, not Arms

**Code review fix (2026-08-11 post-verification):**
- [x] Removed 'muscle-shoulders' from exercise-cable-hip-abduction muscle-group mapping (line 4880, anatomically incorrect). Test results: flutter test 2299 passed, 1 skipped; flutter analyze 213 info-level issues (all pre-existing).

## Assumption Log

*(Filled in by executors as they work; marked RATIFIED or REVERT at verification)*

## Feedback

**Decision D-8 (post-verification revision):** Original implementation stored all rep targets as `targetMin`/`targetMax` pairs per plan specification. However, during testing (2026-08-11), discovered that `routine_setup_screen.dart:1368` reads target values exclusively via `target.targetInt`, which returns null when min/max are used, causing all 29 rep-based efforts to fallthrough to hardcoded default of "10 REPS." This visual mismatch (every exercise displayed "10 REPS" regardless of intended range) does not match user intent or existing demo-routine patterns.

User confirmed mid-implementation decision to switch to single `targetInt` (minimum value) pattern—aligning with all 8 existing demo routines and matching double-progression pedagogy (start at minimum, progress to max, add load). This is **not** a blocker or plan failure, but rather a data-encoding correction discovered during integration testing. Both `_repsOnlyEffortSpec()` and `_durationOnlyEffortSpec()` helpers revised to accept single `targetInt`/`targetSec` parameters. All 31 call sites updated with range minimums. Tests re-run post-change: 2299 passed, 1 skipped, 0 failures.

No other deviations. All other requirements met. The three non-seed additions (new Equipment types + extended `_effort()` helper) are safe, additive changes that enable the bundled routine to load correctly.
