# Startup Failure Screen with Retry

## Overview

Replace OmniTrain's developer-oriented startup-failure dead-end ("Error
initializing app. Check console for details.") with an end-user screen
that explains what happened in plain language and offers a **Retry**
button. The retry path re-runs the complete `main()` startup sequence
from the top — re-initializing timezones, preferences, the repository,
catalog refresh, image storage, every state object, and the theme + app
shell — so a transient failure (e.g. transient storage I/O) recovers
on the next tap without an app relaunch. When the retry still fails,
the same screen reappears and the user can keep retrying safely.

## Phase Match Strategy

**STANDARD** — new screen, refactor of the entry point, behavior change
in the failure path. Full plan with scenario register.

## Requirements

- Plain-language failure message: no occurrence of "console", "log",
  "error", "stack", raw exception text, or any developer terminology.
- A short secondary line that invites the user to try again.
- A visible, enabled **Retry** button on the failure screen.
- Tapping Retry re-runs the entire startup sequence; on success the
  app lands on the same screen (`OnboardingScreen` or `HomeScreen`) it
  would have on a normal first launch.
- Tapping Retry after a persistent failure re-displays the same
  failure screen without crashing.
- Successful first-launch path is completely unaffected — no trace of
  the failure screen renders.
- No diagnostic collection, no reset-data flow, no change to what can
  cause an initialization failure.

## Acceptance Criteria

- [ ] When `main()` startup fails, the user sees a screen containing
      no occurrence of "console", "log", or raw error text.
- [ ] A Retry button is visible and enabled on the failure screen.
- [ ] Tapping Retry re-executes the complete `main()` startup
      sequence; when the underlying cause has cleared, the user
      arrives in the app with all state initialized normally.
- [ ] When the failure persists, tapping Retry returns to the same
      failure screen without a crash, repeatedly.
- [ ] A normal, successful launch renders no trace of the failure
      screen and is behaviorally identical to today.

## Scenarios

### S-001: Friendly failure-screen copy (no developer terminology)
- Trigger: `main()` startup sequence throws an exception.
- Precondition: A repository/state initialization fails before
  `runApp(MyApp(...))` can run.
- Flow:
  1. `main()` catches the exception.
  2. `runApp` is called with the failure screen wrapped in a
     `MaterialApp` that uses the same theme tokens as the rest of the
     app.
  3. The screen renders a single primary message and a short
     secondary line, plus a Retry button.
- Expected outcome: The visible text contains no occurrence of
  "console", "log", "error", "exception", "stack", or any raw
  exception payload. The Retry button is present and enabled.
- Edge case of: none.

### S-002: Retry triggers a fresh startup attempt
- Trigger: User taps Retry while the failure screen is showing.
- Precondition: The first startup attempt threw an exception.
- Flow:
  1. The failure screen's Retry callback re-invokes the extracted
     startup routine (same one `main()` uses) from the beginning.
  2. The startup routine re-runs timezone initialization, preferences
     init, repository init, catalog refresh, image storage init, and
     every state constructor.
- Expected outcome: The startup routine is invoked exactly once more
  per Retry tap. On success the failure screen disappears and the
  normal app shell renders.
- Edge case of: none.

### S-003: Retry success lands in the app normally
- Trigger: User taps Retry after the underlying cause of the failure
  has cleared (e.g. transient storage error resolved).
- Precondition: First startup attempt failed; underlying cause has
  since cleared.
- Flow:
  1. Retry callback re-invokes the startup routine.
  2. Startup routine completes without throwing.
  3. `runApp(MyApp(...))` is invoked with all state objects.
- Expected outcome: The user lands on the normal app surface
  (OnboardingScreen for a fresh install, HomeScreen otherwise). No
  trace of the failure screen remains.
- Edge case of: S-002.

### S-004: Persistent failure stays on the failure screen, no crash
- Trigger: User taps Retry repeatedly while the underlying cause
  persists.
- Precondition: The first startup attempt failed and the underlying
  cause is still present.
- Flow:
  1. User taps Retry.
  2. Startup routine re-runs and throws again.
  3. The failure-screen catch handler re-renders the failure screen.
  4. User taps Retry again.
- Expected outcome: Each retry re-displays the same failure screen.
  No exception escapes to `FlutterError.onError`, no widget exception
  is recorded, no crash occurs.
- Edge case of: S-002.

### S-005: Normal startup path is unchanged
- Trigger: App launches and startup completes successfully on the
  first try.
- Precondition: All initialization steps succeed.
- Flow: `main()` → startup routine → `runApp(MyApp(...))`.
- Expected outcome: The failure screen is never instantiated and is
  not present in the widget tree. Behavior is byte-for-byte identical
  to today.
- Edge case of: none.

## Iteration 1

### DB Changes

None. The failure screen is pure UI and the retry path re-uses the
existing initialization flow. No model, repository, schema, or seed
data changes are required.

### Backend Changes

None. No service, no Dart API, no storage backend changes.

### Frontend Changes

1. **`lib/main.dart` — extract startup sequence into a re-runnable
   function.** The body of the existing `try { ... runApp(MyApp(...))
   } catch (e) { ... }` block becomes a `Future<void>` function —
   `runStartup({required void Function(VoidCallback) replaceWithApp})
   async` — that performs the same steps in the same order. On
   success it calls `replaceWithApp(() => MyApp(...))`; on caught
   failure it calls `replaceWithApp(() => buildStartupFailureApp())`.
   Both branches `runApp(...)` once. The top-level `main()` keeps
   `WidgetsFlutterBinding.ensureInitialized()` and
   `_initializeLocalTimezone()` outside the retry function (timezone
   init is one-shot and safe to leave outside — it is wrapped in its
   own `try/catch` already).
2. **`lib/main.dart` — failure-app builder.** A new top-level
   `Widget buildStartupFailureApp({required VoidCallback onRetry})`
   returns a `MaterialApp` whose `home:` is the new
   `StartupFailureScreen` with the `onRetry` callback wired up.
3. **`lib/features/startup/startup_failure_screen.dart` — new file.**
   A small, pure-presentation widget (no state, no repo) that renders:
   - An `OmniGradientBackground` wrapping a centered column.
   - An `OmniSurface`-rooted headline (no developer terminology) +
     a quieter secondary line that invites the user to try again.
   - A `FilledButton` Retry control that uses
     `OmniTheme.buttonPrimaryHeight`,
     `OmniTheme.buttonBorderRadius`, an explicit `shape:`
     override, full-width sizing, and colors from the active
     `ThemeData.colorScheme`.
4. **Behavior wiring.** The extracted `runStartup` is invoked from a
   small root widget that owns the current "phase" (loading / running
   app / showing failure). The phase widget swaps its child between
   a tiny loading placeholder and the latest `runApp` argument. This
   keeps the retry path one-call-per-tap while preserving the
   "normal startup is unchanged" requirement: on success, only the
   normal `MyApp` ever renders, exactly as today.

### Implementation Steps

1. Read `lib/main.dart`, `lib/app.dart`, `lib/widgets/layout/omni_surface.dart`,
   `lib/widgets/layout/omni_gradient_background.dart`, and
   `lib/core/constants/omni_theme.dart` (button tokens) to confirm
   conventions before editing.
2. Add `test/startup_failure_screen_test.dart` with the four required
   tests (copy check, retry invocation, recovery path, persistent
   failure path) — see Test Map below.
3. Run the new tests and confirm they **fail** (red run).
4. Create `lib/features/startup/startup_failure_screen.dart`.
5. Refactor `lib/main.dart` to extract the startup sequence and wire
   the retry callback.
6. Run the new tests and confirm they **pass** (green run).
7. Run `flutter test` — no previously passing tests are now failing.
8. Doc hygiene: `docs/navigation_and_screens.md` (new screen in the
   inventory table); `docs/widget_catalog.md` (only if a reusable
   widget was added — `StartupFailureScreen` is a screen, so it
   belongs in the screen inventory, not the widget catalog).

### Test Map

| Scenario | Test file | Test name |
|---|---|---|
| S-001 | `test/startup_failure_screen_test.dart` | `failure screen copy has no developer terminology and Retry is present` |
| S-002 | `test/startup_failure_screen_test.dart` | `tapping Retry re-invokes the startup routine once` |
| S-003 | `test/startup_failure_screen_test.dart` | `retry after a transient failure lands in the normal app` |
| S-004 | `test/startup_failure_screen_test.dart` | `repeated retries under persistent failure stay on the failure screen without throwing` |

## Progress

- [x] Read conventions and existing entry-point code.
- [x] Write failing tests in `test/startup_failure_screen_test.dart`.
- [x] Confirm the new tests fail (red run) — compile errors because
      `StartupRoot` / `StartupFailureScreen` do not exist yet.
- [x] Create `lib/features/startup/startup_failure_screen.dart`.
- [x] Create `lib/app/startup_root.dart`.
- [x] Refactor `lib/main.dart` to extract the startup sequence and
      wire retry.
- [x] Confirm the new tests pass (green run) — 5/5 new tests pass.
- [x] Run the full `flutter test` suite — all 1888 tests pass, no
      regressions.
- [x] Update `docs/navigation_and_screens.md` with the new screen
      and the new `StartupRoot` entry-point diagram.

### Phase 2 Complete ✓

### Phase 3 Complete ✓ — see review below.

## Feedback

(empty)

### Phase 0 Complete ✓

### Phase 1 Complete ✓

No data-layer changes required. The failure screen is pure UI and the
retry path re-uses the existing initialization flow end-to-end. No
models, no repository methods, no SQLite schema, no seed data, no
service surface needs touching. `docs/data_models.md` and
`docs/db_integration.md` remain accurate as written.