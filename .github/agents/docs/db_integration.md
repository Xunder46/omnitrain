# DB Integration

## Overview

OmniTrain uses a repository-first persistence architecture:

- Runtime app persistence: `HiveWorkoutRepository` (web and current cross-platform runtime)
- SQL schema assets + migrations: maintained in `scripts/` and `lib/data/datasources/` for SQLite parity work
- Single abstraction contract: `WorkoutRepository`

This document explains how to validate DB assets and how profile-related persistence is represented in both Hive runtime and SQL assets.

---

## Key Files

- `lib/data/repositories/workout_repository.dart`
- `lib/data/repositories/hive_workout_repository.dart`
- `lib/data/repositories/mock_workout_repository.dart`
- `lib/data/datasources/database_provider.dart`
- `lib/data/datasources/migrations.dart`
- `scripts/sqlite_schema.sql`
- `scripts/sqlite_seed.sql`
- `test/db_seed_test.dart`

---

## Setup And Validation

1. Install dependencies.

```bash
flutter pub get
```

2. Validate schema + seed assets in deterministic test mode.

```bash
flutter test test/db_seed_test.dart
```

3. Validate profile repository behavior.

```bash
flutter test test/profile_data_layer_test.dart
```

---

## Repository Contract

`WorkoutRepository` now includes profile and measurement APIs:

- `getProfile()`
- `saveProfile(UserProfile profile)`
- `getMeasurementHistory(String measurementType)`
- `getLatestMeasurement(String measurementType)`
- `saveMeasurementEntry(BodyMeasurementEntry entry)`
- `deleteMeasurementEntry(String entryId)`
- `updateSessionFeeling(String sessionId, int feeling)`

Any repository implementation must satisfy this full contract and remain compile-safe.

---

## Hive Runtime Persistence

`HiveWorkoutRepository` now opens profile-specific boxes during `initialize()`:

- `user_profile`
- `body_measurements`

Behavior:

- Profiles are saved by profile id.
- Measurement entries are saved by entry id.
- Measurement history is filtered by `measurementType` and sorted `recordedAtMs` descending.
- Latest measurement is derived from sorted history.

### Hive Migration Keys

- `seed_units_migrated_v1`:
  - Backfills missing seed units (including `unit-cm` and `unit-pct`) for installs where seed bootstrap already ran.
- `exercise_round_defaults_migrated_v1`:
  - Existing migration for exercise round defaults.
- `session_feeling_fields_migrated_v1`:
  - Marker-only migration for newly nullable session feeling fields.

---

## SQLite Assets (Parity And Future Runtime)

`scripts/sqlite_schema.sql` now includes profile structures:

- `app_user_profile`
- `app_body_measurement_entry`
- Indexes for measurement history queries by type/user + recorded time desc

It also includes session/observation extensions:

- `app_training_session.session_feeling`
- `app_training_session.quality_rating`
- `app_effort_observation.rpe_rating`
- `app_effort_observation.rest_duration_ms`

`scripts/sqlite_seed.sql` now seeds stable unit IDs and metric IDs, including:

- `unit-cm`
- `unit-pct`
- canonical `metric-*` rows aligned with constant IDs

---

## SQLite Datasource Versioning

- `DatabaseProvider.open(..., version: 3)` is now the default.
- `migrations.dart` contains incremental SQL migrations for:
  - v2: `modality`, `intent` fields on `app_training_session`
  - v3: `session_feeling`, `quality_rating`, `rpe_rating`, `rest_duration_ms`

---

## Practical Notes

- DB schema/seed SQL are loaded from assets via `rootBundle`.
- `DatabaseProvider` supports `inMemory` mode for deterministic tests.
- Current runtime behavior is Hive-first; SQL assets are still maintained to preserve repository parity and avoid drift.

---

**Document Version**: 1.1
**Last Updated**: March 15, 2026
