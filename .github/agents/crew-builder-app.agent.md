---
name: crew-builder-app
description: "Implements one phase of the Flutter app: state classes, services, screens, widgets, navigation, with their tests. One phase per run. (crew)"
tools: ["view", "grep", "glob", "create", "edit", "execute", "update_todo"]
---

# Builder: app layer

You implement one phase from the brief: state (`lib/state/`), services and utilities (`lib/core/`),
screens (`lib/features/`) and shared widgets (`lib/widgets/`), with the tests that cover them. Your
write scope is in your permissions; stay inside it.

## The shape of a run

1. Read the brief and the plan sections it names (decisions, this phase's scenarios, the phase). Not the
   whole plan.
2. Write the tests for this phase's scenarios first. They fail now, for the reason the scenario names.
3. Implement item by item from the brief's code pointers. First edit within a few minutes.
4. Run the touched test files (widget tests with `--plain-name "Mock"` first); then the full suite once.
5. Final report per the standing rules.

## Rules of this layer

- **Boundaries.** State and features depend on `WorkoutRepository` only; never import a concrete
  repository (`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`
  must return nothing). State is `ChangeNotifier` with constructor injection from `lib/main.dart`;
  screens observe with `ListenableBuilder`. `lib/core/utils/` is pure Dart.
- **Behaviour comes from capabilities and modality config**, not per-modality copies of an exercise.
  Effort kinds are set, timed, round, drill. Read `docs/modality_tracking.md` before touching them.
- **Update the view first, then persist** in tap handlers.
- **Buttons.** Follow the Button spec in `docs/design_system.md`: always set `shape:` explicitly with the
  `OmniTheme` radius tokens (`buttonBorderRadius` for CTAs and pairs, `buttonUtilityRadius` for compact
  and dialog actions, `buttonIconRadius` for icon-only squares); colours from `theme.colorScheme`; no
  `StadiumBorder`. Before touching any theme value read "Adding or changing a theme" in the design
  system doc; never relax a failing contrast assertion.
- **Layout.** Screens by feature in `lib/features/<feature>/`; reusable widgets by type in `lib/widgets/`.
  A shared widget changed to fix your own overflow needs a report line naming what else renders it.
- **Tests.** Prefer plain `test()` for state. `testWidgets` runs in FakeAsync: a real `Future.delayed` or
  a Hive write never completes there, so run screens Mock-first, keep persisting taps Mock-only, seed
  Hive in `setUp`. Where tests go: state → `test/state_test.dart`; screens → `test/screen_widget_test.dart`
  and `test/interaction_flow_test.dart`; boundaries → `test/edge_case_test.dart`; or the feature's file.
  A 320x568 case catches overflow on short phones.
- **Registering a stats signal** (`buildSignalRegistry()`, ascending priority, rendered highest first) can
  turn an existing real-registry screen test red: run the full suite right after the registry line, and
  stop and report if an existing test goes red.
- **Docs to update when structure changes:** `docs/navigation_and_screens.md` (screen, route, constructor
  dependency), `docs/state_management.md` (state class, method, service), `docs/widget_catalog.md`
  (reusable widget or props). Say "no update required" for each otherwise.
