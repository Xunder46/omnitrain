# OmniTrain

A multi-sport training log for iOS and Android, built in Flutter. OmniTrain adapts its logging screen to the kind of training you're doing — lifting, cardio, sports, holds and stretches, or free training — so the right fields are always in front of you without any setup.

The app is built around one job: logging your work quickly. Everything else supports that.

## What makes it different

Most fitness apps treat every exercise the same way. In OmniTrain, each exercise declares what it can track — time, hold, reps, sets, load, distance, rounds — and the session screen shows only those controls. One data model covers every kind of training, so a barbell squat and a 5K run can sit in the same workout without switching apps or modes.

## Features

- **Adaptive workout sessions** — set, timed, round, and drill logging, chosen per exercise, with rest tracked automatically between efforts
- **Rolling sessions** — continuous, open-ended free training without a fixed plan
- **Routines** — reusable workout templates you can start a session from
- **Custom exercises** — create your own, starting from the type of training
- **Session summary** — a post-workout breakdown with changes against previous sessions and an optional effort rating
- **Stats, records and trends** — all-time totals, strength and cardio trends, personal records, and per-exercise progress
- **Calendar and training periods** — browse past sessions by month and group them into training blocks
- **Nutrition** — daily food and water logging against your own targets
- **Profile and measurements** — body measurement logging with a history chart
- **Themes and settings** — multiple themes, unit preferences, and timer alerts

All data is stored locally on the device.

## Status

OmniTrain is publicly available on iOS and Android. An Apple Watch companion is in development.

## Getting started

Requires the Flutter SDK (Dart `^3.10.7`).

```bash
flutter pub get
```

```bash
flutter run
```

```bash
flutter test
```

The minimum supported screen size is **360 × 640** logical pixels in portrait, defined in `lib/core/constants/supported_viewport.dart` and covered by `test/supported_viewport_test.dart`. Smaller screens are not supported.

## Tech stack

- Flutter / Dart
- Hive for local persistence, behind a repository interface
- `ChangeNotifier` state with constructor dependency injection
- Material 3 theming

## How it's built

Development runs through an AI agent pipeline. Claude Code plans each change and reviews the result; GitHub Copilot CLI agents (database, developer, and code-review roles) do the implementation against a shared plan file, with a structured handoff between phases. Each change is held to a fixed scope budget and has to pass the test suite before it lands. The same pipeline keeps the documentation in step with the code.

Agent definitions live in [`.github/agents/`](.github/agents/).

## Documentation

The docs are generated from the source and checked against it; where they disagree, the code wins.

| Document | Contents |
|---|---|
| [`docs/README.md`](docs/README.md) | Documentation index — start here |
| [`docs/global_conventions.md`](docs/global_conventions.md) | Cross-cutting rules for the codebase |
| [`docs/app_philosophy.md`](docs/app_philosophy.md) | Product goals and the core entity model |
| [`docs/modality_tracking.md`](docs/modality_tracking.md) | Exercise capabilities, training types, and effort kinds |
| [`docs/navigation_and_screens.md`](docs/navigation_and_screens.md) | Screen map and navigation flow |
| [`docs/state_management.md`](docs/state_management.md) | State classes, services, and how data flows |
| [`docs/data_models.md`](docs/data_models.md) | Domain models and their relationships |
| [`docs/design_system.md`](docs/design_system.md) | Colors, typography, spacing, motion, and components |

## License

Copyright © 2026 Xunder46. All rights reserved.

This repository is published for viewing only. No license is granted to use, copy, modify, distribute, or create derivative works from any part of this code, documentation, or assets without prior written permission.
