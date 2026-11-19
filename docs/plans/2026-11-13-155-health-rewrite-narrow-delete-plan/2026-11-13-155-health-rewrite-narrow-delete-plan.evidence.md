# Plan 155 — evidence

Phase 1 (developer), branch `claude_develop`, base HEAD `908d1da8`.

## Prove-red: S-15501 at HEAD (source change stashed)

Command:

```
.github/copilot/scripts/macos/gateway.sh prove-red HEAD test --plain-name "S-15501" -- test/health_platform_test.dart
```

Verdict line:

```
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the reason the test guards; a compile or load error means the test could not run there (use a mutation instead).
```

Failing assertion (the reason the test guards):

```
  Expected: [(DateTime, DateTime):(2026-11-12 09:00:00.000, 2026-11-12 09:00:01.000)]
    Actual: [(DateTime, DateTime):(2026-11-12 09:00:00.000, 2026-11-12 09:40:00.000)]
  S-15501 the delete window is the session's own start only
  test/health_platform_test.dart 934:7
```

A first prove-red attempt failed to compile (`b.start` on `TrainingSession`); the fixture was corrected to compare `w.start.millisecondsSinceEpoch == b.startedAtMs` and the run above is the real red.

## Green after the change

- `flutter test test/health_platform_test.dart` → **63 passed, 0 failed** (`All tests passed!`), including `S-15501 a late end deletes only the moved session's own workout, never the next session's` and `S-15502 the delete and the effort clear ask for exactly [start, start + 1 s)`.
- `flutter test test/health_platform_test.dart test/watch_session_import_test.dart test/watch_session_adoption_bridge_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` → **236 passed, 0 failed** (`All tests passed!`).
- `flutter analyze` → **181 issues** (baseline 181; none in `health_sync_service.dart`, `health_platform_test.dart` or the doc).

## Existing tests that encoded the old wide window (changed, not loosened)

- `test/health_platform_test.dart` › group `plan 146c: a moved end rewrites the Health workout` › `S-14670 a moved end rewrites the one workout, and a second move again`: expected `(at(0), at(40))` and `.last == (at(0), at(50))`. Now expects `(at(0), at(0) + 1 s)` for both, i.e. the exact narrow window D-15501 specifies — the assertion is tighter, not weaker.
- Same group › `S-14670 the phone's own catch-up rewrites the workout it wrote`: expected `(at(0), at(40))`, now `(at(0), at(0) + 1 s)`.
- `S-14671`, `S-15409` and `S-15410` assert store contents, write counts and effort order only; they stayed green unmodified.

## Mutation check (S-15502)

The source change is small enough that prove-red covers it. Mutating `windowEnd` back to `DateTime.fromMillisecondsSinceEpoch(math.max(previousEndedAtMs, endedAtMs))` was not run because that is exactly HEAD, which S-15501 proved red above.
