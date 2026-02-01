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
- Migrations should be added to `lib/src/data/migrations.dart`.
