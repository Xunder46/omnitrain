# Feature: User photos survive app updates and OS housekeeping relocations

> Status: DRAFT — Q&A inferred from the prompt, ready for Phase 1 handoff
> Next handoff: @dba (Phase 1 — `ImageStorageService` + service tests)
> Binding conventions: `docs/global_conventions.md` (cross-cutting rules);
> `docs/db_integration.md` (dual-backend parity, repository contract);
> `docs/state_management.md` (ChangeNotifier + constructor DI from `main.dart`).

---

## Progress

- [x] Phase 0 — Plan authored (Overview, Requirements, Acceptance Criteria, Scenarios, Iteration 1).
- [x] Phase 1 — `ImageStorageService` (IO + stub) updated for basename references + `resolveOrRelink`; service tests pass.
- [x] Phase 2 — State classes updated; rework S-1/S-2 + split S-5 + add S-R1..S-R5b; full suite green.
- [x] Phase 3 — Code review.
- [x] Phase 4 — Rendering bug fix (post-review user feedback): rendering widgets were passing the basename directly to `Image.file` which silently failed. Threaded `ImageStorageService.resolvePathSync` through the rendering widgets so they resolve the basename to the current managed dir at render time. New tests cover the resolver + the existing tests continue to pass.

## Feedback

_(empty — add a note here if a phase is blocked.)_

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
### Phase 4 Complete ✓

---

## Overview

The current image-persistence fix ships an `ImageStorageService` that copies
every picked photo into `<applicationDocumentsDirectory>/omni_images/`. It
stores **absolute paths** in `UserProfile.avatarPath` and `Food.imagePath`.
This is robust against the picker temp cache being purged, but it is **not**
robust against the OS relocating the app's documents directory during an
update, a reinstall, or routine storage housekeeping. After relocation, the
absolute path is stale and the photo stops rendering.

Foods and exercises already survive this scenario because their `Food` /
`Exercise` rows are written by a repository whose storage layer resolves
the correct location on every read; the photo's absolute path is recorded
once and never re-resolved. Worse, the current code self-heals a stale path
to `null` on load — which deletes a link to a photo whose file is still on
the device.

This plan makes user photos just as durable as the rest of the user's local
data: the stored reference becomes **location-independent** (the filename
only), and the service resolves the reference against the *current* managed
directory on every load. If the file is still present somewhere on disk
(typically because the OS moved the data along with the directory), the
service re-links the record by copying the file into the new managed
directory and normalizing the stored reference to the filename. The link is
cleared only when the file is genuinely, verifiably gone.

**Out of scope (explicit, matches prompt):** cloud backup or sync; recovery
after a full uninstall + reinstall or a clean wipe; web photo persistence
(unchanged — no-op + existing snackbar); any change to picker / crop /
placeholder visuals.

---

## Resolved Decisions (Ledger)

- **D-1 — Reference format is the filename only.** `ImageStorageService.persistPickedImage`
  returns the basename `<uuid-v4>.<ext>` instead of an absolute path. The
  stored `avatarPath` / `imagePath` is therefore a portable relative
  identifier under the managed directory. This is the central durability
  move: a basename does not encode the documents directory and survives
  any relocation.

- **D-2 — Service resolves the reference at read time.** `ImageStorageService.resolveOrRelink(String? reference)`
  takes any reference (a basename, a legacy absolute path, or `null`) and
  returns the canonical basename if a corresponding file is reachable
  anywhere on disk under a known candidate location, else `null`. The
  state classes call this on every load. No more "the reference is what
  the picker returned" — the reference is always re-resolved.

- **D-3 — Search algorithm.** Resolver tries (in order):
  1. `<currentManagedDir>/<basename>` — the common post-relocation case
     where the OS moved the data along with the directory.
  2. The literal `reference` itself — handles pre-fix records whose
     absolute path is still on disk (no relocation happened, the file is
     just at a path the resolver hasn't tried).
  3. The picker's temp directory
     (`<getTemporaryDirectory()>/<basename>`) — handles the rare case
     where the OS picked up the file into a separate cache.
  4. The application support directory
     (`<getApplicationSupportDirectory()>/<basename>`) — defensive
     fourth stop for unusual OS layouts.
  The list is bounded and contains no recursive scans, so the resolver
  remains O(1) work for the common path-1 case and bounded I/O for the
  fallback paths.

- **D-4 — One-time relink write.** When the resolver returns a basename
  that differs from the stored reference (typical for legacy absolute
  paths), the state writes the normalized basename back to the
  repository so future loads are O(1) on path 1. The write is skipped if
  the stored reference already equals the basename (no churn).

- **D-5 — Relink copies the file to the new managed dir.** When a file
  is found at a fallback location (not the current managed dir), the
  resolver copies it into the current managed dir before returning the
  basename. This is the migration step: the file becomes a managed file
  under the new directory so subsequent saves/loads are stable. The copy
  failure path is graceful — the resolver still returns the basename and
  the file remains accessible at its original location (which may be
  read-only after relocation; the data layer doesn't care because the
  reference is the basename, not the location).

- **D-6 — Self-heal only on truly absent files.** If the resolver
  returns `null` after exhausting all candidates, the state clears the
  stored reference to `null` and persists the cleared row. This is the
  existing self-heal behavior, narrowed to "file truly absent". The
  reference is **never** cleared while the file is reachable.

- **D-7 — Replace / remove cleanup unchanged.** When a food photo is
  replaced or cleared (or a profile avatar is replaced / removed), the
  state's D-7 cleanup calls `service.deleteIfManaged(previous)`. The
  service's `deleteIfManaged(basename)` deletes
  `<managedDir>/<basename>`; for legacy absolute paths the service still
  recognizes and deletes them via `isManaged`. The fallback-file path
  (D-5) means a re-linked file is always a managed file in the new dir,
  so subsequent replaces / removes delete the right file.

- **D-8 — Web behavior unchanged.** The stub variant continues to throw
  `UnsupportedError`; screens keep the existing `kIsWeb` early-return
  and the existing user-facing snackbar text. No web change.

- **D-9 — Models unchanged.** `UserProfile.avatarPath` and `Food.imagePath`
  remain `String?` opaque strings. The repo's `fromMap` / `toMap` is
  untouched. The reference format shift is entirely inside the
  service + state classes.

- **D-10 — Test architecture changes.** Existing S-1 ("avatar persists
  across state rebuild") and S-2 ("food photo persists across state
  rebuild") use a single `TestImageStorage` across save and reload, so
  they pass even with absolute paths. Per the prompt they must be
  reworked to vary the base location between save and reload. S-5
  ("stale record self-heals to null on load") must be split into (a)
  truly missing → null (keep) and (b) legacy old-location reference
  whose file is present → re-linked, displayed, not nulled (new). New
  service tests cover resolution across relocated bases and re-link
  on load.

---

## Feature Invariants

These bite in this feature and bind the implementer:

- **INV-1 — Opacity of image paths.** The repository never reads from
  or writes to an image file. It stores an opaque string in
  `avatar_path` / `image_path` and returns it on read. The string
  format shift (absolute → basename) is invisible to the repository.
- **INV-2 — Mock ↔ Hive parity on touched data.** The data layer shape
  is unchanged. The two implementations remain value-for-value on the
  string fields. Verified by re-running the existing
  `test/db_seed_test.dart` and `test/profile_data_layer_test.dart`.
- **INV-3 — Call-site orchestration only.** Only the screens /
  `FoodForm` may call `ImageStorageService.persistPickedImage`. The
  service's new `resolveOrRelink` is read-side and called by the
  state classes' load methods. State classes never copy files; they
  only resolve, normalize, and delete (via the service).
- **INV-4 — Self-heal is monotonic.** A self-heal transitions a
  truly-stale path to `null`. A re-link transitions a legacy absolute
  path to its basename. A second launch finds the path already
  basename-form and is a no-op on the resolve, and a no-op write
  because the basename is unchanged.
- **INV-5 — `deleteIfManaged` swallows "no such file" and treats a
  basename as managed.** The service swallows `FileSystemException`
  of the "no such file" kind. A basename is by convention a managed
  file (D-1), so `deleteIfManaged(basename)` always attempts
  `<managedDir>/<basename>`. Legacy absolute paths still flow through
  the `isManaged` gate so non-managed paths are never deleted.

---

## Requirements

- **R-1** A photo saved before the app's on-device storage location
  changes continues to display after that location change, given the
  image file is still on the device. (Core regression — the gap with
  foods/exercises today.)
- **R-2** A device restart with no storage-location change leaves all
  saved photos displaying, unchanged.
- **R-3** A pre-existing record whose stored reference points at a
  prior storage location but whose image file is still present on the
  device is re-linked by the first load after the fix and displays
  normally; the stored reference is normalized to the basename and
  **not** nulled.
- **R-4** A record whose image file is genuinely absent shows the
  placeholder and does not crash; only in this case is the stored
  reference cleared.
- **R-5** Replacing a photo still removes the previously stored image
  file; storage does not accumulate orphaned images.
- **R-6** Removing a photo still removes its image file and shows the
  placeholder.
- **R-7** The fix-shipping update, run against a data set created by
  the old version, results in zero displaying-photo loss for any
  photo whose file is still on the device.
- **R-8** Web behavior is unchanged: picking is a no-op for
  persistence and the existing snackbar text is identical.

---

## Acceptance Criteria (each maps to ≥1 scenario)

| ID | Criterion | Scenario |
|----|-----------|----------|
| AC-1 | Avatar survives an OS-driven relocation of the documents directory (data preserved). | S-R1 (new) |
| AC-2 | Food photo survives the same relocation. | S-R2 (new) |
| AC-3 | A legacy absolute-path record whose file is still present at the same path is normalized to the basename on first load, and the photo displays. | S-R3 (new) |
| AC-4 | A legacy absolute-path record whose file has moved to the current managed dir (post-relocation) is normalized to the basename and the photo displays. | S-R1 / S-R2 (via D-3 path 1) |
| AC-5 | A legacy absolute-path record whose file is truly absent is cleared to `null` on first load. | S-R5a (split from S-5) |
| AC-6 | Replacing a photo deletes the old managed file; no orphan accumulates. | S-3, S-4 (kept green) |
| AC-7 | Removing a photo (avatar or food) deletes the managed file and shows the placeholder. | S-6, S-7 (kept green) |
| AC-8 | Web behavior is unchanged. | S-8 (kept green) |
| AC-9 | Failed copy at write time surfaces snackbar, state unchanged, no partial file. | S-9 (kept green) |
| AC-10 | No reintroduction of the defect: existing tests S-1 / S-2 are reworked to vary the base location between save and reload (per prompt). | S-1, S-2 (reworked) |

---

## Scenarios

### S-R1 (new): Avatar resolves across relocated managed directory

- **Fixture:** Two distinct temp directories `baseA` and `baseB`. Service1
  built on `baseA`; Service2 built on `baseB`. The test moves the file
  from `baseA/omni_images/<uuid>.jpg` to `baseB/omni_images/<uuid>.jpg`
  (simulating the OS relocating the data along with the directory).
- **Trigger:** `ProfileState` (constructed with Service2) loads a profile
  whose `avatarPath` is the basename `<uuid>.jpg`.
- **Flow:** `ProfileState.loadProfile()` → `ImageStorageService.resolveOrRelink(basename)`
  → service tries `baseB/omni_images/<uuid>.jpg` → file present → returns
  basename. State saves nothing new (already a basename).
- **Expected outcome:** `state.profile?.avatarPath` is the basename; the
  file is reachable from the current managed dir; bytes match the source.
- **Edge case of:** none

### S-R2 (new): Food photo resolves across relocated managed directory

- **Fixture:** Same as S-R1 but against `FoodLibraryState`.
- **Trigger:** `FoodLibraryState.loadFoods()`.
- **Flow:** Resolver finds file at the new managed dir via basename.
- **Expected outcome:** Loaded food's `imagePath` is the basename; the
  file is reachable; bytes match.
- **Edge case of:** none

### S-R3 (new): Legacy absolute-path record is re-linked and displays

- **Fixture:** A `UserProfile` row whose `avatar_path` is an absolute
  path like `/old/base/omni_images/<uuid>.jpg`. The file exists at that
  absolute path on disk (e.g. test creates it there). A fresh service is
  constructed with a different `baseDirectory`.
- **Trigger:** `ProfileState.loadProfile()`.
- **Flow:** Resolver tries `currentManagedDir/<basename>` → not present.
  Resolver tries the literal absolute path → present. Resolver copies
  the file to `<currentManagedDir>/<basename>` (one-time migration copy)
  and returns the basename. State saves the normalized basename back to
  the repo (one write per record, per launch, on first detection).
- **Expected outcome:** `state.profile?.avatarPath` is the basename
  (normalized); the file is reachable from the current managed dir;
  `getProfile()` from the repo returns the basename; the photo displays.
- **Edge case of:** none

### S-R4 (new): Food photo legacy absolute-path record is re-linked

- **Fixture:** Same as S-R3 but for a `Food` row with `image_path`.
- **Trigger:** `FoodLibraryState.loadFoods()`.
- **Flow:** Resolver re-links via basename; state saves normalized
  basename back to the repo.
- **Expected outcome:** Loaded food's `imagePath` is the basename;
  `getFoodById` from the repo returns the basename; the photo displays.
- **Edge case of:** none

### S-R5a (split from S-5): Truly absent file is cleared to null

- **Fixture:** A `UserProfile` row whose `avatar_path` is
  `/var/folders/picker_tmp_xyz/temp.jpg`. The file does not exist on
  disk. No fallback candidate has a file matching the basename.
- **Trigger:** `ProfileState.loadProfile()`.
- **Flow:** Resolver tries all candidates → none present → returns
  `null`. State saves `avatarPath: null` back to the repo.
- **Expected outcome:** `state.profile?.avatarPath` is `null`; the
  repo row is updated; the widget tree renders the fallback; no
  exception is raised.
- **Edge case of:** none

### S-R5b (split from S-5): Food photo truly absent is cleared to null

- **Fixture:** Same as S-R5a but for a `Food` row.
- **Trigger:** `FoodLibraryState.loadFoods()`.
- **Expected outcome:** `food.imagePath` is `null`; repo row updated;
  no crash.
- **Edge case of:** none

### S-1 (reworked): Avatar persists across state rebuild with relocated base

- **Fixture:** Service1 on `baseA`; Service2 on `baseB`. The test
  saves an avatar with Service1, **moves** the file from
  `baseA/omni_images/<uuid>.jpg` to `baseB/omni_images/<uuid>.jpg`,
  then constructs a fresh `ProfileState` (Service2, same repo) and
  calls `loadProfile()`.
- **Expected outcome:** Fresh state resolves the basename, finds the
  file under Service2's managed dir, displays the photo.
- **Edge case of:** none

### S-2 (reworked): Food photo persists across state rebuild with relocated base

- **Fixture:** Same as S-1 but against `FoodLibraryState`.
- **Expected outcome:** Fresh state resolves the basename and the
  photo displays.

### S-3 (kept green): Replacing avatar deletes the old managed file

- **Trigger:** `updateAvatarPath(new)` while avatar is set.
- **Expected outcome:** Old file at `<managedDir>/<old-basename>` gone;
  new file at `<managedDir>/<new-basename>` present.

### S-4 (kept green): Replacing food photo deletes the old managed file

- **Trigger:** `updateCustomFood(imagePath: new)` while a photo is set.
- **Expected outcome:** Old file gone; new file present.

### S-6 (kept green): Remove Photo on avatar deletes the managed file

- **Trigger:** `updateAvatarPath(null)`.
- **Expected outcome:** File at `<managedDir>/<basename>` gone;
  `avatarPath` is `null`.

### S-7 (kept green): Clear food photo deletes the managed file

- **Trigger:** `updateCustomFood(imagePath: null)` / `updateCatalogFood(... imagePath: null)`.
- **Expected outcome:** File gone; `imagePath` is `null`.

### S-8 (kept green): Web behavior unchanged

- **Trigger:** `kIsWeb == true`; existing call-site early-return.
- **Expected outcome:** Existing snackbar text verbatim; service not
  constructed; no crash.

### S-9 (kept green): Copy failure surfaces snackbar, state unchanged

- **Trigger:** `persistPickedImage` against a read-only managed dir.
- **Expected outcome:** Snackbar; state unchanged; no partial file.

---

## Iteration 1

### Phase 1: `ImageStorageService` relocation-aware references — @dba

1. [ ] Update `lib/core/services/image_storage_service_io.dart`:
   - `persistPickedImage(picked)` now returns the **basename**
     `<uuid-v4>.<ext>` instead of the absolute path. The file is
     still copied into `<managedDir>/<basename>`; only the return
     value changes.
   - Add `Future<String?> resolveOrRelink(String? reference)`:
     - Returns `null` if `reference` is null/empty.
     - Computes `basename = p.basename(reference)`.
     - Tries `currentManagedDir/basename`; if present, returns
       `basename`.
     - Tries the literal `reference` as an absolute path; if
       present, copies it to `<currentManagedDir>/<basename>` and
       returns `basename`.
     - Tries `<getTemporaryDirectory()>/<basename>`; if present,
       copies and returns `basename`.
     - Tries `<getApplicationSupportDirectory()>/<basename>`; if
       present, copies and returns `basename`.
     - Else returns `null`.
   - `deleteIfManaged(String? path)`:
     - If `path` is a basename (no path separator), always delete
       `<managedDir>/<path>` (treat basename as managed by
       convention, D-1).
     - If `path` is an absolute path, fall back to the existing
       `isManaged` gate (legacy migration only).
     - No-op on null/empty/missing file (INV-5).
   - `isManaged`, `exists` unchanged in shape (still take any
     string and answer true/false).

2. [ ] Update `lib/core/services/image_storage_service_stub.dart`
   to mirror the new `resolveOrRelink` signature (throws
   `UnsupportedError`).

3. [ ] Update `lib/core/services/image_storage_service.dart` doc
   comment to reflect the relocation-aware contract.

4. [ ] Create / update tests in `test/image_storage_service_test.dart`:
   - S-1 service-level (updated): persist returns basename; bytes
     match; basename resolves to a file in the managed dir.
   - D-2 (extension preservation) (updated): basename ends with the
     picked extension.
   - resolveOrRelink (new):
     - Returns the basename when the file exists in the current
       managed dir (path 1).
     - Returns the basename when the file exists at the literal
       reference path and is missing from the current managed dir
       (path 2; re-link copy verified).
     - Returns the basename when the file exists in the picker's
       temp dir and is missing from path 1 / 2 (path 3; re-link
       copy verified).
     - Returns null when no candidate has the file.
     - Returns null for null / empty input.
   - deleteIfManaged (updated): deletes `<managedDir>/<basename>`
     for a basename input; swallows "no such file"; for an
     absolute non-managed path, no-op.

5. [ ] Run unit tests until green:
   - `flutter analyze lib/core/services/image_storage_service*.dart`
   - `flutter test test/image_storage_service_test.dart`
   - `flutter test test/db_seed_test.dart` (regression)
   - `flutter test test/profile_data_layer_test.dart` (regression)

**Predicted files** (diff target — nothing else):
- `lib/core/services/image_storage_service_io.dart`
- `lib/core/services/image_storage_service_stub.dart`
- `lib/core/services/image_storage_service.dart`
- `test/image_storage_service_test.dart`

---

### Phase 2: Wire state classes + rework tests — @developer

1. [ ] Update `lib/state/profile/profile_state.dart`:
   - `loadProfile()`: after loading the profile, call
     `_imageStorage.resolveOrRelink(_profile?.avatarPath)`. If
     non-null, normalize `_profile.avatarPath` to the basename and
     persist the normalized row (only if it differs from the stored
     value). If `null` AND the existing `avatarPath` was non-null,
     clear it and persist (true self-heal; D-6).
   - `updateAvatarPath(String? newPath)`: unchanged in behavior —
     accepts a basename (the new contract from `persistPickedImage`)
     and persists it; cleans up the previous managed file via
     `deleteIfManaged`.

2. [ ] Update `lib/state/food_library_state.dart`:
   - `_selfHealFoodImages()` is replaced by `_resolveAndNormalizeFoodImages()`:
     for each cached food with a non-null `imagePath`, call
     `resolveOrRelink`. If non-null and differs from the stored
     value, persist the normalized row. If null and the stored
     value was non-null, clear it and persist (D-6).
   - `loadFoods()` calls `_resolveAndNormalizeFoodImages()` after
     populating the cache.
   - `updateCustomFood` / `updateCatalogFood`: the D-7 cleanup of
     the previous image is unchanged (basename is the new normal,
     delete works the same way).

3. [ ] Rework `test/image_persistence_round_trip_test.dart`:
   - S-1: vary base location. Save with `TestImageStorage.create()`
     on a temp dir; **move** the file under the managed dir into a
     second temp dir's managed dir; construct a fresh state with a
     second `TestImageStorage` on the second temp dir; assert the
     photo still resolves and bytes are intact.
   - S-2: same but for `FoodLibraryState`.
   - S-5 (split): replace with S-R5a (truly absent → null, kept)
     and S-R5b (food truly absent → null, kept), plus S-R3
     (legacy absolute path with file present → re-linked,
     displayed, NOT nulled) and S-R4 (food legacy absolute path →
     re-linked).
   - S-3 / S-4 / S-6 / S-7 (kept): update path assertions to use
     the basename (no absolute paths in expectations).

4. [ ] Update `test/food_form_pick_saves_test.dart`:
   - The expectations that compare `updated.imagePath` against
     `picked.path` or against absolute paths must be updated to
     compare against a basename-shaped string and resolve via the
     service for file-existence / byte-equality assertions.

5. [ ] Add new relocation tests (S-R1 / S-R2) — see Phase 2 §1
   in this plan.

6. [ ] Run until green:
   - `flutter analyze`
   - `flutter test test/image_persistence_round_trip_test.dart`
   - `flutter test test/image_storage_service_test.dart`
   - `flutter test test/food_form_pick_saves_test.dart`
   - `flutter test test/profile_state_test.dart`
   - `flutter test test/profile_screen_test.dart`
   - `flutter test test/food_library_state_test.dart`
   - `flutter test test/food_library_edit_test.dart`
   - `flutter test test/nutrition_test.dart`
   - `flutter test test/db_seed_test.dart`
   - `flutter test test/profile_data_layer_test.dart`

**Predicted files** (diff target — nothing else):
- `lib/state/profile/profile_state.dart`
- `lib/state/food_library_state.dart`
- `test/image_persistence_round_trip_test.dart`
- `test/food_form_pick_saves_test.dart`

**No model changes. No repository interface changes. No SQL schema changes.**

---

### Phase 2 verification notes (target)

- New tests cover the relocation scenario (S-R1, S-R2), the
  legacy-absolute-path re-link (S-R3, S-R4), and the split S-5
  cases (S-R5a, S-R5b).
- Reworked S-1, S-2 vary the base location between save and reload
  and assert resolution (not string equality of the stored
  reference).
- All previously-passing tests remain green: image_storage_service,
  food_form_pick_saves, profile_state, profile_screen,
  food_library_state, food_library_edit, nutrition, db_seed,
  profile_data_layer, models, models_test.
- `flutter analyze` is clean across the affected files.

---

### Phase 3: Code review — @code-reviewer

Review against:
- `docs/global_conventions.md`
- INV-1..INV-5
- D-1..D-10
- R-1..R-8 / AC-1..AC-10
- Button shape + theme tokens (`docs/design_system.md`)
- Repository-pattern purity (no concrete imports in state)

---

### Phase 3 verification notes (target)

PASS rules per global_conventions: Units, Theme tokens, OmniSurface /
OmniCardHeader, Effort-kind, Timestamps, Reuse canonical, Instrument
panel.
PASS INV-1..INV-5.
PASS D-1..D-10.
PASS AC-1..AC-10.
N/A: any rule that doesn't apply (e.g. button shapes for non-button
files).
