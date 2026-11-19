# Review: 249-last-time-line · P1–P5 · e4c1fe19..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 0 · minor 1 · tests: not run — the brief says the lead already ran the full suite (reported: 44 pass; `flutter analyze` at baseline 178, 0 errors). Per the brief I did not re-run it.
Diff vs Predicted Files: outside: `test/food_catalog_load_test.dart` (see finding 1)

## Findings

1. [Minor] `test/food_catalog_load_test.dart:270` — a one-line change outside the plan's Predicted Files and named by no phase: `byId['chicken_thigh']!.fat!` → `byId['chicken_thigh']!.fat` (dropped `!`). Behaviour-neutral — `fat` is a non-nullable `double` (`lib/data/models/models.dart:1852`), so the removed `!` was redundant — but it is unexplained scope creep in a file this plan does not own, and a future reader cannot tell why it moved. Fix: revert it, or the owner records one sentence in the plan saying it is a redundant-`!` tidy. Guard: none needed (no behaviour).
2. [Minor] `lib/features/session/workout_session_screen.dart:343` — `_onSettingsChanged` does not `setState`, so a weight-unit change reaching the logger depends entirely on the root `ListenableBuilder(listenable: settingsState)` in `lib/app.dart:95` rebuilding pushed routes; the screen itself adds no listener that rebuilds. No user-visible failure today because the unit can only be changed on the Settings screen while the logger is not the foreground route, and the root listener covers it the same way it does every other screen that receives `settingsState` as a plain field. Fix: none required for this plan; the plan's Input-reality item 3 claim ("the screen rebuilds when settings change") is true only through that root listener — if the owner ever moves off it, the line goes stale until the next rebuild. Guard: none (unreachable in current flows). Listed as a note, not a defect of this diff.

## Assumption Log rulings
The plan carries no `## Assumption Log` section (phases P1–P4 had exact code in the brief, so few assumptions were free). Nothing to rule. The one accepted wrongness — a pre-pruning workout can show a bare default `10` as its last set — is recorded as Open item 2, ratified as documented and owned.

## Scenario coverage
S-24901 -> `test/last_performance_service_test.dart` · "S-24901 the newest finished workout answers, the running one does not" (Mock and Hive)
S-24902 -> same file · "S-24902 excludeSessionId falls through to the older workout" (Mock and Hive)
S-24903 -> same file · "S-24903a skipped and empty sets are not kept" + "S-24903b an all-skipped workout falls through to the older one" (Mock and Hive)
S-24904 -> same file · "S-24904a an exercise with no history answers null" + "S-24904b a timed effort is not a set effort, even with set rows" (Mock and Hive)
S-24905 -> same file · "S-24905 two blocks list both, in block order" (Mock and Hive)
S-24906 -> same file · "S-24906 store order does not decide" (Mock and Hive)
S-24907 -> same file · "S-24907 the running workout is not its own last time" + "S-24907b the loaded workout is not its own last time" (Mock; the b-case is beyond the plan and welcome)
S-24911..S-24913 -> `test/last_sets_line_test.dart` · the three `describe` unit tests (kg, lbs, no-load/mixed/8-sets)
S-24914 -> same file · "S-24914 the logger shows the line for a set effort with history"
S-24915 -> same file · "S-24915a no seeded history: no line" + "S-24915b a timed (hold) effort shows no line even with history"
S-24916 -> same file · "S-24916 the line fits and sits above the reps controls at 360x640, text scale 1.3"
No scenario without a test; every test asserts values a wrong implementation would break (recency, exclusion, kind, block order, exact strings) — none would survive `lastSetsFor` returning the oldest workout or a timed effort's sets.

## Brief's five questions — answers
1. Stale/exercise-swap: safe. The future is cached per exercise id in `_WorkoutSessionScreenState._lastSetsByExercise` (`workout_session_screen.dart:168-177`), and `FutureBuilder` resets its snapshot when it receives a different future object, so Previous/Next swaps cannot show another exercise's sets; the same exercise twice shows the same correct line in both blocks. Unit change: the line formats `widget.settingsState` at build, so it is correct whenever the tree rebuilds (see finding 2's note). The `catchError((_) => null)` on the cached future means a transient read failure hides the line for that exercise for the screen's lifetime — intended by D-24904 ("on error it renders nothing").
2. Per-frame calls: none. `lastSetsFor` is invoked only from `_lastSetsLine` (list view:782) through the `putIfAbsent` cache; nothing on Home, lists or per rebuild outside the cache. Four bulk reads per exercise per screen lifetime, as the plan states.
3. Watch/rolling reads: correct. `EntryRows.setEntries` -> `setGroups` ignores any row whose id does not parse as `obs-<effortId>-<n>-<metricKey>` (`number == null -> continue`) — a UUID id or an unnumbered row belongs to no entry and cannot crash the service; the watch importer writes numbered rows in the same shape (`watch_session_importer.dart:1585` groups through `EntryRows.parseId`; `logged_entry_rows.dart:41` builds the ids). Rolling sessions are excluded by `endedAtMs == null` (the harness seeds rolling as `endedAtMs: null`).
4. Behaviour, not presence: all assertions are on values (startedAtMs of the right session, exact set lists, exact rendered strings, `findsNothing`, dy comparison). Covered above; no surviving-wrongly assertion found.
5. Docs: the three added sentences match the code and name tests that exist (S-24901..S-24906 in the service file, S-24907/S-24907b in the state row, S-24911..S-24916 in the widget entry). Grep of current docs for `previousValues` / `last value` / `pre-fill` / `last time` outside `docs/plans`, `docs/history`, `docs/releases` turned up only carry-forward and prefill sentences unrelated to this change (`stats_best_load_investigation.md:411,443`, `modality_tracking.md:222`, nutrition/exercise-editor prefills) — none made false by this diff.

## Project checks
- State/features depend on `WorkoutRepository` only: `LastPerformanceService` takes the interface; `lib/state`, `lib/features`, `lib/widgets`, `lib/core` never import a concrete store; Mock and Hive stay in parity (service tests run under both harnesses).
- No model change -> `scripts/sqlite_schema.sql` untouched, still conforms.
- No new button, no hex colour, no raw Card/SnackBar/IconButton; the line is a themed `Text` using `OmniTheme.colors.textMuted` (theme-resolved via `OmniTheme.colors => colorsForTheme(activeTheme)`, `omni_theme.dart:417`). No allowlist entry added, no ratchet raised.
- `docs/plans/...-plan.md` itself is in the diff (the plan file), expected.

## Docs delta
| Row | Status |
|---|---|
| `docs/widget_catalog/session_widgets.md` ADDED `LastSetsLine` -> applied |
| `docs/state_management/workout_state.md` ADDED `lastSetsFor` -> applied |
| `docs/state_management/services_and_utils.md` ADDED `LastPerformanceService` -> applied |
Doc edits the table does not name: none — the diff touches only these three docs plus the plan file itself.

## Lead dispositions

1. Minor `test/food_catalog_load_test.dart:270`: not this plan's change; the file was already modified before the unit started and stays unstaged (owner's).
2. Minor `_onSettingsChanged` does not `setState`: noted, no flow changes the weight unit while the logger is the foreground screen; left as is.
