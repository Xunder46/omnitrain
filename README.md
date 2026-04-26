# OmniTrain

OmniTrain is a multimodal fitness tracking app built in Flutter, targeting iOS and Android. It adapts its interface to the type of training being performed — resistance, cardio, sports, isometric, and free training — so the right metrics and controls are always visible without manual configuration.

## What makes it different

Most fitness apps treat every exercise the same way. OmniTrain uses a modality system: each exercise carries a set of capabilities (reps, weight, duration, distance, effort rating) and the workout session screen renders only what that exercise requires. A single unified data model serves all training contexts, so a user can move between a barbell squat and a 5K run within the same workout without switching apps or modes.

## Current status

The app is currently in private TestFlight beta. It is not yet publicly released.

## How it's built

Development is driven through a custom GitHub Copilot agent pipeline. A set of specialized agents — coordinator, DBA, developer, code reviewer, and prompt engineer — collaborate on each feature through a shared plan file, with a structured handoff protocol between phases. This pipeline also maintains the documentation system described below.

The full documentation index is at [`.github/agents/docs/README.md`](.github/agents/docs/README.md).

## Where to go next

| Document | Contents |
|---|---|
| [`.github/agents/docs/README.md`](.github/agents/docs/README.md) | Documentation index — start here |
| [`.github/agents/docs/app_philosophy.md`](.github/agents/docs/app_philosophy.md) | Product vision, scope, session and block architecture |
| [`.github/agents/docs/state_management.md`](.github/agents/docs/state_management.md) | State layer: ChangeNotifier classes, repository interfaces, data flow |
| [`.github/agents/docs/data_models.md`](.github/agents/docs/data_models.md) | Core data models and relationships |
| [`.github/agents/docs/design_system.md`](.github/agents/docs/design_system.md) | Color tokens, typography, spacing, component patterns |

## Tech stack

- Flutter / Dart
- Hive (local persistence)
- ChangeNotifier (state management)
- Material 3 theming
