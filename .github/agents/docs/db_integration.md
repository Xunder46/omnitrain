**DB Integration**

- **Purpose:** how to run the SQLite schema + seed and validate from Flutter
- **Files:**
  - `scripts/sqlite_schema.sql`
  - `scripts/sqlite_seed.sql`

Setup

1. Ensure dependencies are installed:

```bash
flutter pub get
```

2. Run the unit test that creates an in-memory DB and validates the seeds:

```bash
flutter test test/db_seed_test.dart
```

3. To inspect the on-disk DB created by the app (after first run), open the app and then use a sqlite client to open the DB file located in the app documents directory (`omnitrain.db`).

Notes

- The DB files are registered as Flutter assets and loaded via `rootBundle`.
- The `DatabaseProvider` supports an `inMemory` mode for deterministic tests.
- Migrations should be added to `lib/data/datasources/migrations.dart`.
- The web/cross-platform build uses `HiveWorkoutRepository` (Hive boxes) for persistence.
- The native build will use `SqliteWorkoutRepository` via `DatabaseProvider` (sqflite).
- Both implementations share the `WorkoutRepository` interface in `lib/data/repositories/workout_repository.dart`.

Hive migration note (March 2026)

- `HiveWorkoutRepository.initialize()` runs an idempotent backfill migration for
  `default_round_duration_secs` on exercises seeded before per-sport round defaults
  were introduced.
- Migration method: `_migrateExerciseRoundDefaults()`
- Meta key: `exercise_round_defaults_migrated_v1`
- Behavior: only fills missing values; does not overwrite existing stored values.
- Effect: new round entries for sports can use sport-specific defaults on existing
  installs instead of always falling back to 180 seconds.
- Existing already-created round entries remain unchanged (non-retroactive).
