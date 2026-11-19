# Evidence — plan 134a (calories burned: phone estimate and Session Summary)

Observed by the lead on 2026-11-08/09, base commit `ff398e1a7ec18409d9fc8c890bf35d2fde656e69`, branch `claude_develop`, nothing committed.

## Baselines and counts

| Check | Result |
|---|---|
| `flutter analyze` | 181 issues before; 181 issues after P1, P2A, P2B, P3, the fix round and the lead's test additions (0 errors) |
| Invariant grep (`import .*hive_workout_repository` in `lib/state`, `lib/features`, `lib/widgets`, `lib/core`) | no hit |
| `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart` | `+54: All tests passed!` (run together, after the docs phase) |
| Full `flutter test` after the review (before the fix round) | `+7154 ~2: All tests passed!` |
| Full `flutter test` after the fix round | `+7168 ~2: All tests passed!`, 0 failures |
| New test files | `active_energy_service_test` 42, `session_energy_repository_test` 19, `active_energy_lifecycle_test` 8, `active_energy_import_test` 10, `session_summary_calories_test` 7 (each run on its own by the lead) |
| `plan-lint after` | clean (21 scenarios, 16 Docs delta rows) |

## Phases

| Phase | Agent | Result |
|---|---|---|
| P1 stored layer | crew-builder-data | 12 tests green on first run; lead read the repository diff |
| P2A estimate + read-out | crew-builder-app | 48 tests green; lead read `active_energy_service.dart` in full |
| P2B lifecycle wiring | crew-builder-app | 99 tests green across the touched and neighbouring files |
| P3a screen + reader tests | crew-builder-app | the four reader files and neighbours green (161) |
| P3b new screen test file | crew-builder-app | 6 tests green first run |
| P4A, P4B docs | crew-docs-keeper (two in parallel) | rows applied; lead repaired four markers the keeper wrapped over two lines and one Old marker that was a prefix of its own New marker |
| Review | crew-reviewer | APPROVE WITH FIXES: 1 Blocker (a false "un-awaited" doc sentence), 2 Major (watch-imported sessions got no estimate; a wrist-run Free Training session was priced before its timed entries landed), 1 Minor (no test for a figure that rounds to 0) |
| Fix round 1 | crew-builder-app + lead | `WatchSessionInbox.onSessionHistoryChanged` (D-13420) wired through `main.dart` and `watch_sync_wiring.dart`; new `test/active_energy_import_test.dart`; doc sentence fixed; zero-kcal tests added |

## Layout measurement (390x844, throwaway probe, removed)

The Effort row renders without a size problem in the real card width except one 14 px overflow in the test font (the widget-test font is wider than the real one): left half 33..187 px (pen 139..187), Calories pill 203..357. The look on a real phone is an owner check.

## Lead mutation pass

First pass: 39 mutants, 30 killed, 9 survived. Closed by lead-written tests (rolling session with a modality id, zero duration, repository `clear()`, the model's invariants, the `main.dart` wiring): all 9 then killed. Three survivors stay as equivalent by design (a `measured` row is protected by both the service and the repository; the zero-weight and unfinished cases are backstopped by the model's own invariants). Fix-round pass: 4 mutants (the history-changed gate both ways, the shielded callback, the wiring) — two survived at first (the throwing-callback test could not tell shielded from unshielded; the wiring was unguarded), both closed, all 4 killed. Every mutated file was restored and compared byte for byte.

## Known gaps (for the owner)

- (Resolved 2026-11-09 by plans 134c1 and 134c2: the watch now sends its measured energy and the phone stores it; a session with no watch stays on the estimate.)
- (Built 2026-11-09: Fuel card 134b, phone active-session bar 134d, watch rest screen 134e.) A live watch-to-phone energy feed is still not built.
- The MET numbers (resistance 3.5, cardio 7.0, isometric 2.3, sports 6.0) are the lead's defaults (A-2).
- `(owner)` the Session Summary's Effort row on a real phone: the pen sits in the narrow left half beside the rating, and the caption `How hard the session felt` wraps there.
- `(owner)` end a Free Training session on the phone and on the watch and read the Calories pill.
