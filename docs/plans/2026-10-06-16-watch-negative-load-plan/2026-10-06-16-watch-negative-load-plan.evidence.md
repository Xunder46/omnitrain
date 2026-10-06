# Evidence — a negative load (band assist) on a set works on the phone and the watch

Plan: `2026-10-06-16-watch-negative-load-plan.md`. Implementers append; the Planner does not fill
this in. One row per Done-Criterion command, with the **observed** counts pasted, not a claim.

## Baselines (from the brief, re-observe before your first change)

| Command | Baseline |
|---|---|
| `flutter test` | 3949 passed / ~1 skipped / 0 failed |
| `flutter analyze` | 196 issues / 0 errors |
| `swift test` | 294 passed / 0 failed |

## Phase 1 — the contract (@dba)

(to be filled by the implementer)

## Phase 2 — the phone (@developer)

(to be filled by the implementer)

## Phase 3 — the wrist and the residue sweep (@developer)

(to be filled by the implementer)

## Red → green (required for every rule this feature reverses)

D-60 reverses the negative half of `A-14`/`F1`, D-61 and D-62 change two floors. For each, paste the
failing run taken **before** the source change and the passing run after, same command both times:

| Rule | Test | Before the fix | After the fix |
|---|---|---|---|
| D-60 projection | `test/watch_session_projection_test.dart` S-59/S-60 | (paste failure) | (paste pass) |
| D-62 floor | `test/watch_logging_stepping_test.dart` S-61 | (paste failure) | (paste pass) |
| D-61 emitter | `test/watch_logging_surfaces_test.dart` S-62 | (paste failure) | (paste pass) |
| D-63 correction floor | `test/watch_session_import_test.dart` S-65 | (paste failure) | (paste pass) |
