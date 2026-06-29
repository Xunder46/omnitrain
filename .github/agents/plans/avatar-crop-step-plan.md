# Feature: avatar-crop-step

## Overview

Add a square crop step with a circular preview overlay between the
photo picker and the avatar save in `ProfileScreen`. Today the picked
photo is persisted as-is, so off-center subjects get clipped by the
avatar's `ClipOval` display. The crop step runs for both camera and
gallery picks; canceling leaves the existing avatar untouched and
discards the picked photo. The crop UI is built from
`InteractiveViewer` + `RepaintBoundary` (no new plugin dependency),
and a new `ImageStorageService.persistImageBytes(...)` method handles
the cropped byte buffer the same way `persistPickedImage(XFile)`
handles the raw pick (basename + managed-dir copy + D-6 cleanup).

## Requirements

- After the user picks a photo from camera or gallery, present a
  crop step before the avatar is persisted.
- The crop region is square with a circular preview overlay that
  matches how the avatar displays, so what the user frames is what
  they will see.
- The user can pinch-zoom and drag to reposition the photo.
- Confirming the crop saves exactly the framed region as the new
  avatar.
- Canceling the crop leaves the existing avatar unchanged and
  discards the picked photo (the picker temp file is never copied
  into the managed directory).
- The existing "Remove Photo" action is unaffected.
- Out of scope: filters, free rotation, multiple aspect ratios,
  editing the current avatar without re-picking, food photo crops.

## Acceptance Criteria

- [ ] After picking from camera or gallery, a crop step appears
      before the avatar is persisted.
- [ ] The crop region is square with a circular preview overlay
      matching the avatar's displayed shape.
- [ ] The user can pinch-zoom and drag to reposition the photo.
- [ ] Confirming saves exactly the framed region as the avatar.
- [ ] A deliberately off-center, zoomed crop is preserved and
      reflected when the avatar displays (asserted via re-load).
- [ ] Canceling the crop leaves the existing avatar unchanged and
      does not write any new file under the managed directory.
- [ ] The "Remove Photo" path is unchanged.
- [ ] The web (`kIsWeb`) early-return and snackbar are preserved
      verbatim.
- [ ] The crop UI does not introduce new plugin dependencies.
- [ ] All buttons on the new crop screen set an explicit `shape:`
      using `OmniTheme.button*Radius` tokens.

## Scenarios

### S-001: camera pick routes through the crop step before persisting
- Trigger: User taps avatar → Take Photo → grants permission → picks photo.
- Precondition: An avatar is already saved (or not — the crop step is the same).
- Flow: Picker returns an `XFile`; `_pickAvatar` pushes `AvatarCropSheet`; user taps Use Photo; bytes are captured via `RepaintBoundary.toImage`, persisted via `imageStorage.persistImageBytes`, then `state.updateAvatarPath(newBasename)`.
- Expected outcome: `UserProfile.avatarPath` holds a fresh basename; the managed directory has a new file matching that basename.
- Edge case of: none.

### S-002: gallery pick routes through the crop step before persisting
- Trigger: User taps avatar → Choose from Gallery → picks a photo.
- Precondition: An avatar may or may not exist.
- Flow: Same as S-001 with `ImageSource.gallery`.
- Expected outcome: Identical to S-001 — the crop step runs for both sources.
- Edge case of: none.

### S-003: confirming the crop persists cropped bytes; stored image differs from raw pick when a non-default crop is applied
- Trigger: User picks, optionally pans/zooms, taps Use Photo.
- Precondition: An existing avatar may or may not exist (replace path works either way).
- Flow: The crop sheet captures the framed region as PNG bytes via `RepaintBoundary.toImage(format: ImageByteFormat.png)`. The bytes are written to the managed directory. The previous avatar file (if any) is deleted by `updateAvatarPath`'s D-7 cleanup.
- Expected outcome: The new file exists at `<managedDir>/<newBasename>`; its bytes are non-empty and differ from the raw pick (format change + region re-encode). On a subsequent state load, `state.profile?.avatarPath` still resolves to the new basename (resolve-fast-path).
- Edge case of: none.

### S-004: canceling the crop leaves the existing avatar unchanged and discards the pick
- Trigger: User picks, taps Cancel on the crop sheet.
- Precondition: An existing avatar may or may not be set.
- Flow: The crop sheet pops with `null`; `_pickAvatar` returns without persisting anything. The picker temp file is never copied into the managed directory.
- Expected outcome: `UserProfile.avatarPath` is unchanged from before the flow. No new files appear under the managed directory. The picked file may still live in the picker's temp cache (OS will purge).
- Edge case of: none.

### S-005: "Remove Photo" path is unaffected
- Trigger: User taps avatar → Remove Photo (only enabled when an avatar is set).
- Precondition: An avatar is currently saved.
- Flow: Sheet pops; `state.updateAvatarPath(null)` runs, which deletes the previous managed file via D-7 and persists the null avatar.
- Expected outcome: Identical to the pre-feature behavior — no crop sheet is shown for the remove path.
- Edge case of: none.

### S-006: web path is unchanged
- Trigger: User taps avatar → Take Photo or Choose from Gallery on web.
- Precondition: `kIsWeb` is true.
- Flow: The existing `kIsWeb` early-return shows the existing snackbar verbatim and the crop sheet is never pushed.
- Expected outcome: Snackbar shows "Photo selection works on web, but avatar persistence is not supported there yet." Avatar state is not mutated.
- Edge case of: S-001 / S-002 (same picker early-return path).

## Iteration 1

### DB Changes
- None. No model or repository changes — the persisted shape
  (`UserProfile.avatarPath` = basename) is unchanged.

### Backend Changes
1. [ ] Extend `ImageStorageService` (IO + stub variants) with
       `persistImageBytes(Uint8List bytes, {String extension =
       '.png'})`:
   - Writes `bytes` to `<managedDir>/<uuid-v4><extension>`.
   - Returns the basename.
   - On write failure, deletes any partial destination file before
     rethrowing (mirrors D-6 contract).
   - Web stub throws `UnsupportedError` like the other methods
     (callers already early-return on `kIsWeb`).
   - Update file-level doc comment to mention the new method.
2. [ ] No state-class changes. `ProfileState.updateAvatarPath` is
       reused — the D-7 delete-previous + save-new flow applies
       identically to cropped bytes.

### Frontend Changes
1. [ ] Create `lib/features/profile/widgets/avatar_crop_sheet.dart`:
   - Full-screen route pushed via `Navigator.push` from
     `_pickAvatar`. Returns `Uint8List?` — `null` = cancel,
     non-null = captured PNG bytes.
   - Layout:
     - `OmniBackHeader(title: 'Crop Photo')` (translucent on the
       gradient).
     - Body: square viewport via `AspectRatio(aspectRatio: 1.0)`
       with `RepaintBoundary` → `InteractiveViewer` (`minScale:
       1.0`, `maxScale: 4.0`) → `Image.memory(bytes, fit:
       BoxFit.contain)`.
     - Above the viewport: a circular dim scrim drawn with a
       `CustomPaint` so the user can see what the avatar will
       look like inside the circle (matches the avatar's
       `ClipOval` display).
     - Hint text: "Pinch & drag to position".
     - Bottom CTA row: `OutlinedButton` Cancel + `FilledButton`
       Use Photo. Both set `shape:` explicitly using
       `OmniTheme.button*Radius` tokens. Use Photo uses the
       standard primary-height + full-width treatment.
   - Capture path:
     - On Use Photo, get the `RenderRepaintBoundary`, call
       `toImage(pixelRatio: 3.0)` (renders 3× the viewport), then
       `image.toByteData(format: ui.ImageByteFormat.png)`.
     - `Navigator.pop(context, pngBytes)` with the bytes.
   - Lifecycle:
     - Track `_isSaving` so the Use Photo button is disabled
       while capture is in flight.
2. [ ] Update `lib/features/profile/profile_screen.dart`
       `_pickAvatar`:
   - After `pickImage` returns non-null and the `kIsWeb` branch
     is not taken, push `AvatarCropSheet` with the picked bytes.
   - On non-null result: `imageStorage.persistImageBytes(bytes)`
     → `updateAvatarPath(basename)`.
   - On null result: do nothing.
   - Expose `@visibleForTesting handlePickedImage(XFile picked)`
     for tests that bypass the picker platform channel (mirrors
     `FoodForm.handlePickedImage`).
   - Expose `@visibleForTesting handleCroppedBytes(Uint8List
     bytes)` for tests that bypass both the picker and the crop
     sheet.
3. [ ] No navigation contract changes — `AvatarCropSheet` is
       pushed as a plain `MaterialPageRoute` (full-screen
       dialog). It does not need to use `OmniRoute` because it is
       a modal action sheet, not a forward screen transition;
       verify in review.
4. [ ] No changes to `main.dart`, `app.dart`, or any other
       call-site. `ProfileScreen` owns the picker and the crop
       step.

### Implementation Steps
1. [ ] Add `persistImageBytes` to the IO variant of
       `ImageStorageService`. Add `persistImageBytes` to the web
       stub (throws `UnsupportedError`).
2. [ ] Create `AvatarCropSheet` widget.
3. [ ] Wire `_pickAvatar` → crop sheet → persist → update path in
       `ProfileScreen`. Add `@visibleForTesting` hooks.
4. [ ] Update docs (see Doc hygiene below).
5. [ ] Write tests.
6. [ ] Run `flutter test`. Confirm green.

## Progress
- [x] Phase 0 — Plan (this file)
- [x] Phase 1 — Data Layer (no-op for this feature; no DB Changes)
- [x] Phase 2 — Logic & UI
  - [x] `ImageStorageService.persistImageBytes` (IO + stub)
  - [x] `AvatarCropSheet` widget
  - [x] `ProfileScreen._pickAvatar` rewired
  - [x] `@visibleForTesting` hooks on `_ProfileScreenState`
- [x] Phase 3 — Code Review
- [x] Phase 4 — Iteration 2: page-transition bleed-through fix

### Phase 0 Complete ✓
### Phase 1 Complete ✓ (no DB changes; service contract expansion only)
### Phase 2 Complete ✓
### Phase 3 Complete ✓
### Phase 4 Complete ✓ (OmniNavigator route fix)

## Code Review: ✅ APPROVED

Layers in scope: core (ImageStorageService IO + stub), features (AvatarCropSheet), state (ProfileScreen handlePickedImage / handlePickedBytes / handleCroppedBytes)
Layers skipped: data models, repository interface, widgets/*, core/constants

### Findings

PASS (no rule violations):
- **Units / canonical storage** — PNG bytes flow through `ImageStorageService.persistImageBytes` with the same `.png` extension, basename returned, managed-dir copy + D-6 cleanup. Storage shape unchanged.
- **Theme tokens** — All new buttons use `OmniTheme.buttonBorderRadius` (12) for `shape:` and `OmniTheme.buttonPrimaryHeight` (56) for sizing.
- **Card chrome** — Not applicable (AvatarCropSheet uses standard `Scaffold` + `OmniBackHeader`, no card chrome needed).
- **Effort-kind** — Not applicable (no session data).
- **Timestamps** — Not applicable (avatar doesn't carry a timestamp).
- **Reuse canonical owner** — AvatarCropSheet is pure presentation; `ImageStorageService` is the canonical owner of image persistence; `ProfileState.updateAvatarPath` is the canonical owner of the avatar path. No local recreations.
- **Instrument panel** — No decorative chrome; the crop step is a precise instrument (square viewport + circular scrim).
- **No new dependencies** — `InteractiveViewer` + `RepaintBoundary` + `Image.memory` are all in Flutter's core widget set. `ImageByteFormat.png` encoder is built into Flutter.

### Architecture compliance
- Models: untouched. No Flutter/IO imports added to model layer.
- Repositories: untouched. `UserProfile.avatarPath` shape unchanged (basename contract preserved).
- State: `ProfileState` untouched. The avatar flow goes through existing `updateAvatarPath` (which already handles D-7 delete-previous).
- Features: state injected via constructor (already was). State methods called via screen state (no direct repo access). `AvatarCropSheet` is pure presentation (no repository/service).
- Widgets: `AvatarCropSheet` is reusable (no hardcoded refs to ProfileScreen).
- Core: `ImageStorageService.persistImageBytes` matches `persistPickedImage` contract exactly.

### Buttons
- `AvatarCropSheet` Cancel: `OutlinedButton` with `shape:` override using `OmniTheme.buttonBorderRadius` (12). No `StadiumBorder`.
- `AvatarCropSheet` Use Photo: `FilledButton` with `shape:` override using `OmniTheme.buttonBorderRadius` (12). Full-width with `OmniTheme.buttonPrimaryHeight` (56). No `StadiumBorder`.
- Both have `Key` for test targeting: `avatar_crop_cancel`, `avatar_crop_use_photo`.

### Environment safety
- `AvatarCropSheet` does not import `dart:io`.
- `persistImageBytes` (IO) uses `dart:io` — IO service only.
- Web stub symmetric with other methods (throws `UnsupportedError`).
- State depends on repository interface only.
- Service injected at app startup.

### Doc hygiene

| Doc | Status |
|---|---|
| profile_and_measurements.md | ✅ Avatar Crop Step section added; Core Files lists AvatarCropSheet |
| db_integration.md | ✅ persistImageBytes added to the ImageStorageService contract narrative |
| widget_catalog.md | ✅ AvatarCropSheet entry added under Profile Primitives |
| data_models.md | ✅ N/A (no model changes) |
| navigation_and_screens.md | ✅ N/A (AvatarCropSheet uses plain `MaterialPageRoute(fullscreenDialog: true)` — modal action sheet, not a forward screen transition; does not need `OmniRoute`) |
| state_management.md | ✅ N/A (no new state class) |

### Test coverage
- **Service** (`test/image_storage_service_test.dart`): 5 new tests for `persistImageBytes` (basename, extension, D-6 cleanup, UUID uniqueness, assert contract).
- **State** (`test/profile_state_test.dart`): unaffected — `updateAvatarPath` contract unchanged.
- **Widget render** (`test/avatar_crop_test.dart`): S-001 (camera pick → sheet appears → save), S-002 (gallery pick → sheet appears → save), S-003 (persist cropped bytes + UUID basename + round-trip), S-004 (cancel leaves existing avatar unchanged + no managed-dir writes), S-005 (Remove Photo unaffected).
- **Edge cases**: capture-only path tested via direct `handleCroppedBytes` invocation in `runAsync` so real `writeAsBytes` I/O completes deterministically.

Critical: 0 | Warnings: 0 | Suggestions: 0

⏸️ **PIPELINE COMPLETE** — Implementation, review, and doc hygiene delivered. Ready to merge.

## Feedback

### Iteration 2 (June 2026): Fix page-transition bleed-through

**Symptom**: The transition from `ProfileScreen` to the avatar crop
sheet showed the underlying ProfileScreen bleeding through during
the slide-up animation — looks broken, the same symptom seen with
other new screens in the past.

**Root cause**: `_showCropSheet` was pushing the crop sheet with a
raw `MaterialPageRoute(fullscreenDialog: true)`. That route does
not set `opaque => true` and does not wrap the destination page in
the `OmniGradientBackground`. The crop sheet's `Scaffold` is
transparent (`backgroundColor: Colors.transparent`), so the
underlying ProfileScreen remained visible mid-transition.

**Fix**: Switch `_showCropSheet` to
`OmniNavigator.push<Uint8List>(context, builder,
fullscreenDialog: true)`. The `OmniRoute` has `opaque => true` and
wraps the destination in `OmniGradientBackground`, which fully
occludes the underlying route during the transition. Same pattern
every other modal screen in the app uses; see the navigation
contract in `docs/navigation_and_screens.md`.

**Files touched**:
- `lib/features/profile/profile_screen.dart` — replaced the raw
  `MaterialPageRoute` with `OmniNavigator.push`; added the
  `OmniNavigator` import.
- `test/avatar_crop_test.dart` — the S-004 cancel-test was using
  a raw `MaterialPageRoute` to push the sheet from a button
  onPressed. Switched it to `OmniNavigator.push` so the test
  exercises the same route the production wiring uses — catches
  future drift between production and test.

**Docs touched**:
- `docs/profile_and_measurements.md` — added a paragraph in the
  Avatar Crop Step section explaining why `OmniNavigator` is
  mandatory (transparent Scaffold + raw `MaterialPageRoute` =
  bleed-through).
- `docs/widget_catalog.md` — `AvatarCropSheet` entry now
  documents the route type and the rationale.