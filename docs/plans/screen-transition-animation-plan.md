# Feature: Screen Transition Animation Fix

## Overview
Screen-to-screen navigation on non-iOS/macOS platforms (Android, web) uses
`FadeUpwardsPageTransitionsBuilder`, which produces a very subtle 10% upward
fade with **no animation on the exiting route**. This makes navigation feel
instant. iOS/macOS already uses `CupertinoPageTransitionsBuilder` (slide),
which is the "rest of the app." The fix is to apply `CupertinoPageTransitionsBuilder`
uniformly across all platforms inside `OmniRoute`.

## Requirements
- All screen pushes use a slide transition (Cupertino-style) on every platform.
- No screen snaps instantly — every push/replacement/pop has a visible transition.
- Transition style is consistent with the existing iOS behavior.
- No logic, model, or state changes — pure UI/routing polish.

## Acceptance Criteria
- [ ] Pushing any screen slides in from the right on all platforms (iOS, Android, web, macOS).
- [ ] Popping a screen slides it back to the right on all platforms.
- [ ] `OmniRoute.buildTransitions` no longer contains a `FadeUpwardsPageTransitionsBuilder` branch.
- [ ] All existing `omni_route_test.dart` tests pass.
- [ ] New tests confirm: (a) slide transition is active on Android platform, (b) transition duration is non-zero.

## Root Cause (Conductor Analysis)

`OmniRoute.buildTransitions` (lib/core/navigation/omni_route.dart) has this logic:

```dart
final platform = Theme.of(context).platform;
if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
  const builder = CupertinoPageTransitionsBuilder();
  return builder.buildTransitions<T>(...);
}
const builder = FadeUpwardsPageTransitionsBuilder(); // ← the problem
return builder.buildTransitions<T>(...);
```

`FadeUpwardsPageTransitionsBuilder` issues:
1. The entering route only moves 10% upward with a fade — barely perceptible.
2. The **exiting** route receives NO animation — it just disappears when the
   entering route fully occludes it.
3. Result on Android/web: navigation feels "instant" because no sliding occurs.

`CupertinoPageTransitionsBuilder` is already the target behaviour — it is
already used on iOS/macOS and passes the existing edge-swipe-back test. The fix
is to remove the platform guard and use Cupertino everywhere.

All navigation in this app goes through `OmniNavigator` → `OmniRoute`, so
**there is exactly one place to change**.

## Scenarios

N/A — no new screens or state. This touches only the route transition builder.

## Iteration 1

### DB Changes
None.

### Backend / State Changes
None.

### Frontend Changes

#### File 1: `lib/core/navigation/omni_route.dart`
Remove the `if (platform == TargetPlatform.iOS || ...)` branch in
`OmniRoute.buildTransitions`. Use `CupertinoPageTransitionsBuilder` for all
platforms.

Before:
```dart
@override
Widget buildTransitions(BuildContext context, Animation<double> animation,
    Animation<double> secondaryAnimation, Widget child) {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    const builder = CupertinoPageTransitionsBuilder();
    return builder.buildTransitions<T>(
        this, context, animation, secondaryAnimation, child);
  }
  const builder = FadeUpwardsPageTransitionsBuilder();
  return builder.buildTransitions<T>(
      this, context, animation, secondaryAnimation, child);
}
```

After:
```dart
@override
Widget buildTransitions(BuildContext context, Animation<double> animation,
    Animation<double> secondaryAnimation, Widget child) {
  const builder = CupertinoPageTransitionsBuilder();
  return builder.buildTransitions<T>(
      this, context, animation, secondaryAnimation, child);
}
```

Also remove `import 'package:flutter/material.dart'` if `FadeUpwardsPageTransitionsBuilder` was the only Material-specific symbol (keep `import 'package:flutter/cupertino.dart'`). Double-check imports after the change.

#### File 2: `test/omni_route_test.dart`
Update and extend tests:

1. **Update Test 3 comment** (line ~74):
   Old: `// Force iOS platform so CupertinoPageTransitionsBuilder activates the back-swipe gesture recognizer.`
   New: `// CupertinoPageTransitionsBuilder is used on all platforms; test the back-swipe on iOS.`
   The test itself can remain unchanged (forcing iOS is fine — the gesture is tested on iOS target).

2. **Add Test: slide transition is used on Android** — set `TargetPlatform.android`,
   push a route via `OmniNavigator.push`, call `tester.pump()` (single frame),
   confirm the new route content is present in the tree but the old route content
   is also still present (mid-slide), then `pumpAndSettle()` and confirm only
   new route is visible. This proves animation is running (not instant).

3. **Add Test: OmniRoute has non-zero transitionDuration** — construct an
   `OmniRoute` directly and assert `transitionDuration > Duration.zero`.

### Implementation Steps
1. [ ] Open `lib/core/navigation/omni_route.dart`.
2. [ ] Remove the `if (platform == TargetPlatform.iOS || ...)` branch and
       `FadeUpwardsPageTransitionsBuilder` usage from `buildTransitions`.
3. [ ] Verify imports — `flutter/material.dart` is still needed for `PageRoute`,
       `Theme`, `BuildContext` etc., but confirm `FadeUpwardsPageTransitionsBuilder`
       is no longer needed. It lives in `material.dart` so no import removal is needed.
4. [ ] Run `flutter analyze` — expect no errors.
5. [ ] Open `test/omni_route_test.dart`.
6. [ ] Update the comment in Test 3 (iOS edge-swipe-back).
7. [ ] Add Test: slide transition on Android (mid-animation check).
8. [ ] Add Test: `transitionDuration` is non-zero.
9. [ ] Run `flutter test test/omni_route_test.dart` — all pass.

## Progress
- [x] Update `OmniRoute.buildTransitions` to use `CupertinoPageTransitionsBuilder` for all platforms
- [x] Update Test 3 comment in `omni_route_test.dart`
- [x] Add Android slide transition test
- [x] Add `transitionDuration` non-zero test
- [x] Run all tests green (833/833)

## Files Affected
- `lib/core/navigation/omni_route.dart` — remove platform branch, use Cupertino everywhere
- `test/omni_route_test.dart` — update comment + add 2 new tests

## Feedback
<!-- Leave empty until a specialist adds notes -->
