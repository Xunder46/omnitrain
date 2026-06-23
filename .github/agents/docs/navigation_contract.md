# Navigation Contract

## Rule

> **Any `MaterialPageRoute` or `PageRouteBuilder` outside `lib/core/navigation/` is a code-review blocker.**

All screen-level navigation in OmniTrain must go through `OmniNavigator`. Callers never construct route objects directly.

## Enforcement

This rule is enforced automatically by
`test/navigation_contract_enforcement_test.dart`. That test walks
`lib/` recursively, excludes `lib/core/navigation/` (which legitimately
defines the standard route primitive), and fails the build if any
application feature or UI file contains a `MaterialPageRoute(` or
`PageRouteBuilder(` construction. Test code is excluded because
`MaterialPageRoute` is used as harness setup in `pumpWidget` scaffolds.

A test failure message names every offending file and points the
caller at `OmniNavigator` (`lib/core/navigation/omni_navigator.dart`)
as the required fix.

The historical route-migration audit
(`.github/agents/docs/route-migration-audit.md`) is preserved as a
record of the original migration, but is **no longer the enforcement
mechanism** — the automated test above is. If the audit and the test
ever disagree, the test wins.

---

## Why This Rule Exists

### The bleed-through bug

OmniTrain uses an app-level `OmniGradientBackground` (in `app.dart` `builder:`) to solve static bleed-through: status bar tints, sheet-minimum gaps, overscroll rubber-band, and AppBar surface color. Every `Scaffold` is transparent, so the gradient paints correctly through all static gaps.

However, `MaterialPageRoute` sets `opaque = false` by default. With every `Scaffold` transparent and `opaque = false`, Flutter keeps the outgoing route painted throughout and after the slide animation. When the compositor finally culls it, the previous screen's content (e.g. the Hub sheet) visibly snaps out. This is the bleed-through bug.

### The dual-layer fix

`OmniRoute` solves this with two changes:

1. **`opaque = true`** — tells Flutter it can cull the route below as soon as the incoming route fully covers the screen. This is truthful because the route-level gradient fills edge to edge.

2. **`OmniGradientBackground` in `buildPage`** — wraps every pushed page in the same gradient widget used at the app level, so the route is genuinely opaque to the user. The app-level gradient remains as the safety net for uncovered window areas.

### Visual tradeoff (accepted)

During the ~300 ms slide, both routes paint their own `OmniGradientBackground`. The overlap zone shows a brief doubling of the 5%-opacity radial highlight. At that opacity level, during motion, this is below the perceptual threshold. Removing the route-level highlight to avoid this would regress the steady-state aesthetic on every screen permanently — an unacceptable tradeoff. The transient doubling is accepted and documented here.

---

## What `OmniRoute` Does

| Property | Value | Reason |
|---|---|---|
| `opaque` | `true` | Allows Flutter to cull the route below; eliminates bleed-through |
| `buildPage` | wraps in `OmniGradientBackground` | Backs the transparent Scaffold; makes `opaque = true` truthful |
| `buildTransitions` | `CupertinoPageTransitionsBuilder` on iOS/macOS, `FadeUpwardsPageTransitionsBuilder` on Android | Matches platform conventions; preserves iOS edge-swipe-back |
| `maintainState` | `true` | State of pushed screens is preserved across navigation |

`OmniFadeRoute` provides the same gradient-wrapping guarantee with a `FadeTransition` instead of a slide. Used for the splash→home transition.

---

## How to Add a New Screen

```dart
// Push
OmniNavigator.push(context, (_) => MyNewScreen(state: myState));

// Push with replacement (current route removed from stack)
OmniNavigator.pushReplacement(context, (_) => MyNewScreen(state: myState));

// Fade-replace (splash → home style)
OmniNavigator.pushReplacementFade(context, (_) => MyNewScreen(state: myState));

// Pop multiple routes
OmniNavigator.popUntil(context, (route) => route.isFirst);
```

Never write:

```dart
// ❌ Review blocker
Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyNewScreen()));
Navigator.of(context).push(PageRouteBuilder(...));
```

---

## How to Add Cross-Cutting Concerns

`OmniNavigator` is the single place to add:

- **Analytics** — log the route name before pushing
- **Auth gates** — check auth state before allowing navigation
- **Deep links** — map URL paths to `OmniNavigator` calls

All such concerns belong in `lib/core/navigation/omni_navigator.dart`. No call site should be patched individually.

---

## File Locations

| File | Purpose |
|---|---|
| `lib/core/navigation/omni_route.dart` | `OmniRoute<T>` and `OmniFadeRoute<T>` primitives |
| `lib/core/navigation/omni_navigator.dart` | `OmniNavigator` static helper (the only public API) |
| `lib/core/navigation/navigation.dart` | Barrel export |

---

## Relation to the Gradient Architecture

The bleed-through fix ("No screen transition produces a flash of mismatched background") is part of the gradient window-layer plan. This navigation contract is the resolution of that criterion. The app-level `OmniGradientBackground` in `app.dart` `builder:` is **not** removed; it continues to cover system insets and any uncovered window area behind the Navigator.
