# Feature: First-Launch Onboarding Flow

## Overview
A one-time, three-screen swipeable onboarding flow shown before HomeScreen on fresh installs.
No user input. Purely informational. Persisted via `WorkoutRepository.setPreferenceBool('onboarding_complete', true)`.
Once dismissed (via "Get Started" or Skip), it is never shown again.

## Requirements
- Three swipeable pages using a `PageController`
- Skip button on pages 1 and 2; "Get Started" button on page 3
- `OmniGradientBackground` on all three screens
- Page indicator dots visible on all pages
- Uses `OmniTheme`, `OmniSurface`, and `ModalityColors` — no hardcoded colors
- On completion: write `onboarding_complete = true`, navigate to `HomeScreen`
- On launch: check `onboarding_complete` flag; if true, skip onboarding entirely
- Do NOT re-enable `OmniSplashScreen`

## Acceptance Criteria
- [ ] Fresh install (or cleared prefs) shows OnboardingScreen before HomeScreen
- [ ] After "Get Started" or Skip, HomeScreen appears and onboarding is never shown again
- [ ] Restarting the app after completion goes directly to HomeScreen
- [ ] All five modality tiles render with correct names, descriptions, and accent colors
- [ ] Page indicator updates correctly when swiping
- [ ] No hardcoded `Color(...)` values; all colors sourced from `OmniTheme` or `ModalityColors`
- [ ] No existing behavior or files are broken (OmniSplashScreen stays disabled)
- [ ] Works on web (Hive) and native (same code path)

## Scenarios
_Populated during implementation._

---

## Iteration 1

### Analysis
No onboarding exists. OmniSplashScreen exists but is disabled — must remain untouched.
The `getPreferenceBool` / `setPreferenceBool` API already exists on `WorkoutRepository` (Hive-backed).
The check must happen in `main.dart` before `runApp`, exactly like `hint_seen_maintenance`.
`MyApp` currently receives only state objects. We need to thread through both `showOnboarding: bool` and `WorkoutRepository` (for OnboardingScreen to write the flag).

### DB Changes
None — `getPreferenceBool` / `setPreferenceBool` already implemented for Hive and Mock repositories.

### Backend Changes
None

### Frontend Changes

**New file: `lib/features/onboarding/onboarding_screen.dart`**

`OnboardingScreen` — `StatefulWidget` owning a `PageController`.

Constructor: same parameters as `OmniSplashScreen` (all state objects) PLUS `WorkoutRepository repository`.

Internal structure:
- `Scaffold` wrapping `OmniGradientBackground`
- `PageView` with `controller: _pageController`, three child pages
- Overlay row at top: left = transparent placeholder, right = **Skip** `TextButton` (hidden on page 3 using `AnimatedOpacity` or `Visibility`)
- Page indicator row at bottom (three `Container` dots, filled/unfilled based on `_currentPage`)
- "Get Started" `ElevatedButton` at very bottom, visible only on page 3

Pages:
1. `_WelcomePage` — `AnimatedZenHalo` (optional, improves visual quality) or just the app name in large text, subtitle pitch
2. `_HowYouTrainPage` — title + 5 `_ModalityTile` widgets in a `ListView`
3. `_HowYouPlanPage` — title + descriptive paragraph + "Get Started" button area

`_ModalityTile` — private widget within the file:
- `OmniSurface` with `Border.all(color: accentColor.withOpacity(0.35))` for accent left edge via `BoxDecoration` override
- Left-side color bar (3px wide Container with `accentColor`)
- Modality name in `textTheme.titleMedium`
- Description in `textTheme.bodySmall` / `textMuted`

Complete/Skip flow:
```dart
Future<void> _complete(BuildContext context) async {
  await widget.repository.setPreferenceBool('onboarding_complete', true);
  if (!context.mounted) return;
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => HomeScreen(...all widget.* fields...)),
  );
}
```

**Modify: `lib/app.dart`**
- Add `final bool showOnboarding;` and `final WorkoutRepository repository;` fields
- Update constructor
- In `build`, select home widget:
  ```dart
  home: showOnboarding
      ? OnboardingScreen(repository: repository, workoutState: ..., ...)
      : HomeScreen(workoutState: ..., ...),
  ```

**Modify: `lib/main.dart`**
- After `repository.initialize()`, read pref:
  ```dart
  final onboardingComplete = await repository.getPreferenceBool('onboarding_complete');
  final showOnboarding = !onboardingComplete;
  ```
- Pass `showOnboarding` and `repository` to `MyApp(...)`

### Implementation Steps

**@developer**

#### Phase 1 — OnboardingScreen
1. [ ] Create `lib/features/onboarding/onboarding_screen.dart`
   - `StatefulWidget` with `PageController _pageController` and `int _currentPage = 0`
   - Three page builder methods: `_buildWelcomePage`, `_buildHowYouTrainPage`, `_buildHowYouPlanPage`
   - Private `_ModalityTile` widget (accent color bar, name, description)
   - Private `_PageDots` widget (three dots, highlight on current)
   - Skip `TextButton` with `IgnorePointer` / `Opacity(0)` on page 3
   - `_complete(context)` async method: saves pref, pushes `HomeScreen`
   - All imports: `WorkoutRepository`, `OmniGradientBackground`, `OmniSurface`, `OmniTheme`, `ModalityColors`, `HomeScreen`, all state objects

2. [ ] Welcome page content:
   - Vertically centred
   - App name: `"OMNITRAIN"` — `TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 3, color: themeColors.primary)`
   - Subtitle: `"one app for every way you train"` — `textTheme.titleMedium` or `bodyLarge`, `textMuted`
   - Optional: `AnimatedZenHalo` (small, ~120px) above the text

3. [ ] Modality tiles page:
   - Title "How You Train" at top
   - Five tiles, one per modality:
     | Label | Key | Description | Color |
     |---|---|---|---|
     | Cardio / Endurance | cardio_endurance | continuous time and distance based activities | `ModalityColors.cardioEndurance` |
     | Resistance / Lifting | resistance_lifting | set, rep, and load based strength training | `ModalityColors.resistanceLifting` |
     | Sports | sports | round and time based training for martial arts and sports | `ModalityColors.sports` |
     | Isometric / Stretching | isometric_stretching | hold based exercises and mobility work | `ModalityColors.isometricStretching` |
     | Free Training | — | mix anything, no modality constraint | `ModalityColors.freeTraining` |
   - Each tile: `OmniSurface`-based card with a 3px left accent bar in the modality color
   - `Column` inside each tile: name (bold) + description (muted)

4. [ ] Calendar/Plan page:
   - Title "How You Plan" at top
   - Three feature bullets (icon + text pairs):
     - Calendar icon → "Schedule upcoming training sessions by day"
     - Bookmark/flag icon → "Create named training periods and goals"
     - History icon → "Review your full session history at a glance"
   - No skip button
   - "Get Started" `ElevatedButton` with `themeColors.primary` background at bottom

5. [ ] Page indicator dots:
   - Row of three `Container(width: 8, height: 8, shape: circle)`
   - Active dot: `themeColors.primary` with `width: 24`
   - Inactive dots: `themeColors.textMuted.withOpacity(0.4)`
   - Animate width using `AnimatedContainer`

#### Phase 2 — Wire Up app.dart and main.dart
6. [ ] Modify `lib/app.dart`:
   - Add `WorkoutRepository` import
   - Add `final bool showOnboarding` and `final WorkoutRepository repository` fields
   - Update constructor accordingly
   - Import `OnboardingScreen`
   - In `build`, use ternary for `home:`

7. [ ] Modify `lib/main.dart`:
   - After `await repository.initialize()`, add pref check
   - Pass `showOnboarding` and `repository` to `MyApp`

## Progress
- [x] Create `lib/features/onboarding/onboarding_screen.dart`
- [x] Implement welcome page (_buildWelcomePage)
- [x] Implement modality tiles page (_buildHowYouTrainPage + _ModalityTile)
- [x] Implement calendar page (_buildHowYouPlanPage)
- [x] Implement page dots indicator
- [x] Implement Skip / Get Started button logic + _complete()
- [x] Modify `lib/app.dart` (add showOnboarding + repository)
- [x] Modify `lib/main.dart` (check onboarding_complete pref)
- [x] All 476 tests green — no regressions

### Phase Status: **Complete**

## Iteration 2 — Remove Onboarding Skip Button (TRIVIAL)

### Analysis
TRIVIAL signal: no schema change, no new state, no new user-facing behavior beyond removing an existing bypass. The existing `OnboardingScreen` already contains a `_complete(context)` method that persists the flag and navigates home; that method stays as-is and is still reachable from the "Get Started" `FilledButton` on the final card. The Skip control sits in its own overlay `Stack` child (`SafeArea` + `Align` + `AnimatedOpacity` + `IgnorePointer` + `TextButton`) — removing the whole subtree cleanly avoids any visual gap or dead tap target. No `lib/data/`, `lib/state/`, or repository changes are needed.

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes
**Modify: `lib/features/onboarding/onboarding_screen.dart`**
- Remove the entire top-bar subtree containing the Skip `TextButton` (lines ~130–162 of the current file).
- Page content, page dots, "Get Started" CTA, and `_complete()` are unchanged.

**Modify: `test/screen_widget_test.dart`**
- Rename `'renders welcome page with title and skip button'` → `'renders welcome page with no skip button'`; replace `expect(find.text('Skip'), findsOneWidget);` with `expect(find.text('Skip'), findsNothing);`.
- Inside `'swiping advances pages and final page shows get started'`: drop the `skipButton` lookup and the `AnimatedOpacity` / `IgnorePointer` assertions for it (obsolete — no Skip button exists).
- Delete `'tapping Skip completes onboarding and navigates home'` (its intent is already covered by the Get Started test).
- Add `'no skip button is present on any onboarding card'` — pump the screen, walk through all three pages, assert `find.text('Skip')` is `findsNothing` on each (first, middle, last).
- Do **not** touch `data_tracking_fixes_test.dart`, `edge_case_test.dart`, `widget_test.dart`, `utils_test.dart`, `resistance_emphasis_redesign_test.dart`, `in_session_pr_toast_test.dart` — they test the unrelated "skipped" flag on workout sets, a different concept.

### Implementation Steps
1. [ ] Remove Skip overlay subtree from `lib/features/onboarding/onboarding_screen.dart`.
2. [ ] Update `test/screen_widget_test.dart` per the Frontend Changes list.
3. [ ] Run `flutter test` — all onboarding tests + skipped-set tests pass.

## Progress
- [x] Create `lib/features/onboarding/onboarding_screen.dart`
- [x] Implement welcome page (_buildWelcomePage)
- [x] Implement modality tiles page (_buildHowYouTrainPage + _ModalityTile)
- [x] Implement calendar page (_buildHowYouPlanPage)
- [x] Implement page dots indicator
- [x] Implement Skip / Get Started button logic + _complete()
- [x] Modify `lib/app.dart` (add showOnboarding + repository)
- [x] Modify `lib/main.dart` (check onboarding_complete pref)
- [x] All 476 tests green — no regressions
- [x] Remove Skip overlay from `onboarding_screen.dart`
- [x] Update `screen_widget_test.dart` Skip-related assertions
- [x] Add no-skip-button-on-any-card guard test
- [x] `flutter test` green (onboarding + skipped-set)

### Phase Status: Iteration 2 implementation complete

## Feedback
_Leave empty until a specialist or reviewer adds notes._

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓
