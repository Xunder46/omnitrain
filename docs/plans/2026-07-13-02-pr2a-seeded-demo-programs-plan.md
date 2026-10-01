# Feature: Seeded Demo Workout Programs

> **Tier 1 — Phone quick wins.**
> Last reconciled against source: 2026-07-13.

## Overview

Day-one users currently land in OmniTrain with no ready-made content and
have to build a routine from scratch, which fights the "templates over
blank states" principle already established in the app philosophy. This
item ships 6–10 demo routines spanning multiple modalities — resistance,
cardio / endurance, round-based, isometric / mobility — as ready-to-use
templates in the existing My Routines system, delivered through the
versioned catalog refresh mechanism so both fresh installs and existing
installs receive them exactly once. The mechanics also rehearse the
Release 4 marketplace delivery pipeline (authored content arriving on
user devices) and respect user modifications and deletions on subsequent
refreshes.

## Requirements

- Ship 6–10 demo routines spanning multiple modalities so no single sport
  looks like the app's only audience.
- Demo routines are clearly labelled as built-in demos in the UI and, once
  present on the device, are usable, editable, and deletable exactly like
  user-created routines.
- Delivery routes through the existing versioned content refresh
  mechanism: a user who installed at v1.0 receives the demos on update
  without affecting their own data; if demos are re-seeded in a future
  version, user modifications and deletions are respected (a deleted demo
  must not resurrect).
- Every demo template references only exercise IDs present in the seeded
  catalog (no dangling references).
- Every demo template validates against the template model — every effort
  carries targets appropriate to its effort kind.
- Out of scope: progression logic, multi-week scheduling, calendar
  integration, paid / marketplace mechanics, any program-discovery UI
  beyond the existing routines list.

## Acceptance Criteria

- [ ] A fresh install shows the demo routines in My Routines on first
      launch.
- [ ] An install upgraded from the previous version receives the demo
      routines exactly once after the update.
- [ ] Starting a session from each demo routine works end to end and logs
      correctly for its modality.
- [ ] Deleting a demo routine and then triggering a content refresh does
      not restore it.
- [ ] User-created routines are entirely unaffected by the demo seed.
- [ ] Editing a demo routine on the device is preserved across a subsequent
      content refresh.
- [ ] Every demo template's exercise IDs resolve to entries in the seeded
      catalog at build time and at refresh time.
- [ ] Every demo template's efforts carry targets appropriate to their
      effort kind (e.g. set efforts carry `targetReps` and `targetLoad`
      when those metrics apply).

## Scenarios

### S-001: Fresh install receives demos on first launch
- Trigger: New user installs the app and opens My Routines.
- Precondition: Device catalog version < bundled catalog version (typical
  fresh install).
- Flow: App launches → content refresh runs → demo routines land in
  My Routines → user opens the list.
- Expected outcome: Demo routines appear alongside any empty state, each
  labelled as a built-in demo. Each opens into a routine detail view and
  can be started.
- Edge case of: none

### S-002: Existing install receives demos after update
- Trigger: User updates the app from a build that did not include demos
  to one that does.
- Precondition: Device has at least one user-created routine, stored
  catalog version is older than the bundled version.
- Flow: App launches → content refresh runs → demo routines materialise
  in My Routines.
- Expected outcome: Demo routines are present; existing user routines
  are unchanged in name, ordering, and content.
- Edge case of: S-001

### S-003: Deleting a demo is respected across refresh
- Trigger: User deletes a built-in demo, then triggers a content refresh
  (e.g. by updating the app to a newer bundled catalog).
- Precondition: Demo is present on the device, then user deletes it,
  bundled catalog version is newer than stored.
- Flow: Content refresh runs → orchestrator iterates seed entries →
  user's tombstone marker for that demo id is set → entry is skipped.
- Expected outcome: Deleted demo does not reappear after the refresh.
- Edge case of: S-001

### S-004: User-edited demo is not overwritten
- Trigger: User renames a built-in demo (e.g. "Push Day" → "Push (heavy)"),
  then triggers a content refresh.
- Precondition: Demo is on the device, user's tombstone / edit marker is
  set for that entry.
- Flow: Refresh runs → edit marker detected → entry skipped.
- Expected outcome: User's renamed demo retains the new name; other
  demos are updated as expected.
- Edge case of: S-001

### S-005: Routine starts and logs end to end for its modality
- Trigger: User starts a session from each demo routine.
- Precondition: Each demo routine is loaded and validated.
- Flow: User taps "Start" → routine-to-session conversion runs → session
  screen opens with the planned structure → user logs at least one
  effort per exercise → user finishes the session.
- Expected outcome: Session is persisted with the correct modality-driven
  effort kinds; session summary renders without errors; analytics
  classify the observations correctly.
- Edge case of: S-001

### S-006: Build-time validation of demo seed
- Trigger: Build runs in CI / pre-release check.
- Precondition: Demo seed list is present in source.
- Flow: Validator iterates each demo → resolves each `exerciseId`
  against the catalog → validates each effort's targets.
- Expected outcome: Build fails loudly with a precise list of offending
  demo ids, exercise ids, and effort indices.
- Edge case of: S-005

## Iteration 1

### DB Changes

- Add demo routine templates to the bundled catalog source
  (`lib/mock/seed_data.dart` and any catalog-data file the existing
  versioned refresh mechanism ships from). Each demo carries:
  - `id` (stable, namespaced under a demo prefix)
  - `name`, `description`
  - `modality` (one of the seeded modalities)
  - `segments` → `efforts` → per-metric targets
  - `isBuiltInDemo: true` flag (or equivalent — see Backend Changes)
- Update `lib/data/repositories/workout_repository.dart` only if the
  existing refresh contract needs a new field; otherwise reuse the
  current `Routine` / `RoutineEffort` shapes.
- Update `scripts/sqlite_schema.sql` only if new columns are required
  for the demo flag; otherwise the existing routines table is sufficient.

### Backend Changes

- Add a small catalog-data file (e.g. `assets/data/demo_routines.json`
  or a Dart constant list) loaded by the existing refresh orchestrator.
- Add a validator that runs at app start (and is exercised by the
  pre-release script) verifying every demo:
  - references exercise ids present in the catalog,
  - carries targets appropriate to each effort kind.
- Add a "built-in demo" flag to the routine model (or use the catalog's
  tombstone / source marker already in place for user-edited seed
  entries). Demo deletion must be respected by the refresh.

### Frontend Changes

- My Routines list: render the built-in demo flag as a subtle label
  (e.g. "Demo" chip on the routine card) sourced from `OmniTheme`
  typography / color tokens.
- Routine detail view: no change to behaviour; demo routines are
  editable and deletable exactly like user routines.
- No new screens, no new settings entry, no new navigation routes.

### Implementation Steps

1. Author 6–10 demo routines covering: barbell / dumbbell resistance,
   bodyweight circuit, treadmill cardio, interval round-based sport
   (boxing-style), isometric hold, mobility flow. Each picks exercises
   present in the seeded catalog.
2. Encode the demos in the bundled catalog and verify the versioned
   refresh delivers them.
3. Add the build-time / startup validator. Wire it into the pre-release
   check so CI catches dangling references and invalid targets.
4. Surface the built-in flag in the routines list using existing UI
   primitives.
5. Tests (see Unit Tests Required).
6. Verify fresh-install and upgrade flows against `MockWorkoutRepository`.

## Unit Tests Required

- `test/seeded_demos_test.dart` — versioned refresh paths:
  - Fresh seed: stored version < bundled → demos materialise.
  - Idempotent re-run: stored version = bundled → no write.
  - Upgrade-from-consumed-version: stored catalog is at the older
    bundled version → demos materialise exactly once, no duplicates.
  - Deletion-respected re-seed: deleted demo id has a tombstone →
    refresh does not restore it.
- `test/seeded_demos_test.dart` — every demo routine references only
  exercise IDs present in the seeded catalog. Build a synthetic catalog
  fixture, assert no dangling references.
- `test/seeded_demos_test.dart` — every demo template validates against
  the template model: every effort carries targets appropriate to its
  effort kind (e.g. set effort → `targetReps` and, if load is in
  capability, `targetLoad`; timed effort → `targetDurationSec`).
- `test/seeded_demos_test.dart` — user-created routines are entirely
  unaffected by the demo seed (their ids are absent from the demo list).

## Progress

- [x] TDD: tests authored, red run recorded
- [x] Phase 1 — Data Layer (catalog additions + validator)
- [x] Phase 2 — Logic & UI (refresh wiring + routines list label)
- [x] Phase 3 — Code Review
- [x] Release-ready

## Feedback

_(empty — fold contents into a new `## Iteration N` block if blocked.)_

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
