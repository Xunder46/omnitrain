# Review: 134a calories burned · phone estimate + Session Summary · <base>..working tree (uncommitted)
Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 2 · minor 1 · tests: 7154 passed / 0 failed / 2 skipped (`flutter test`, full suite, `All tests passed!`, exit 0 — log `.work/gateway/test-20261109-000846-87457.log`)
Diff vs Predicted Files: conforms — every file in `git-diff --stat` is a plan Predicted file or a Docs-delta doc (32 files: 14 lib, 1 SQL, 9 test, 8 docs). Nothing outside.

## Findings

1. [Major] `lib/core/services/watch_session_importer.dart:588-617` — an inbox pass that finds no phone session writes an already-finished one (`endedAtMs: end.endedAtMs`, :604) straight through `_repository.createSession` (:599) and never touches energy. `ActiveEnergyService.settle` is called from exactly two places, `session_core_lifecycle.dart:51,201`, so this writer leaves a finished session without a Calories value: the pill reads `—` where a phone-ended equivalent shows `~estimate`. The plan's Input-reality claim "imported watch sessions end through `endSession`" describes only the adopted-while-held path (`watch_session_adoption_bridge.dart:852`), so D-13408's "they are covered" is false for this writer. Fix (smallest): after a pass creates the session (or after each `_settleNow` pass whose import materialises rows for it), trigger `settle(sessionId)` — the service reaches the importer through the same injection `main.dart:405` already builds. Guard: a test staging an inbox `session_end` for a session the phone does not hold, asserting an estimated row is stored.
2. [Major] `lib/core/services/active_energy_service.dart:48-55` — a wrist-run Free Training (or unknown-id) session is estimated before the wrist's measured seconds exist. At the wrist's `completed` the bridge calls `endSession(writeToHealth: false)` (`watch_session_adoption_bridge.dart:852`), which settles immediately; but `_writeLadder` (:1094) that ran from snapshots writes only set efforts and planned observations — `TimedInstance`/`RoundInstance` are created only by the inbox importer (`watch_session_importer.dart:1500-1552`), after the end arrives. So the estimate sees nothing measured and stores the whole duration at the resistance MET (3.5 − 1 = 2.5 kcal/kg·h) whatever the wrist actually did; a later import never corrects it (no caller of `settle` besides the lifecycle, per finding 1's grep). A-1's rationale ("only Free Training could move, and by a few percent") is not derived and does not hold here: the gap can be the whole MET spread (2.5 vs 6.0 for cardio, ~2.4×). Fix (smallest): re-settle the session after the importer pass materialises its timed/round instances — safe, because a modality-session recompute is idempotent (same duration, reused stored weight) and `putSessionEnergy` refuses an estimate over a measured row. Guard: a fixture where the wrist's timed cardio entries land through the inbox after `endSession`, asserting the stored row changes from the resistance-remainder value.
3. [Blocker] `docs/state_management/services_and_utils.md` (`ActiveEnergyService` section, second paragraph) — "SessionCore calls the service — un-awaited, inside a try/catch" is a false doc claim: the code awaits it, `session_core_lifecycle.dart:51` and `:201` (`try { await _activeEnergy?.settle(...); } catch (_) {}`, per OQ-3/OQ-4). A maintainer trusting the sentence would treat the end persistence as free of the settle's latency and could break S-13401's deterministic read. Fix (smallest): replace "un-awaited" with "awaited inside its own try/catch (bounded by one repository read and at most one history index)".
4. [Minor] D-13412 ("a value that rounds to 0 reads `0 kcal` (a real result), never `—`") has no test: no test in `test/session_summary_calories_test.dart` or `test/active_energy_service_test.dart` stores/reads a figure that rounds to 0 (grep over the touched test files finds no `0 kcal` assertion). A settle of a tiny session (e.g. 60 s isometric at 40 kg → 1.3×40×60/3600 ≈ 0.4) writes a row and the screen shows `~0 kcal`; nothing asserts that string instead of `—`. Guard: a read-out test storing `activeKcal` 0.4 and a screen fixture asserting the pill reads `~0 kcal`.

Not findings (checked, clean): the new pen `IconButton` meets the standards (see Q3 below); the model, Hive/Mock repositories, the SQL table, the cascade and `clear()` are as decided (D-13401/D-13402); `sectionForModality` covers exactly the four ids, everything else falls to the free branch; the whole suite is green.

## Assumption Log rulings

- A-1 — ESCALATE in part. Ratify for sessions with a modality id (a re-run settle is idempotent: whole duration, reused stored weight). Escalate the wrist-run Free Training case: the "by a few percent" rationale is not derived (OQ-5 says so itself) and contradicts finding 2, where the whole MET spread can apply and the wrist precisely holds the data that would correct it. Remedy is finding 2's fix, or the owner accepting the permanent wrong figure for those sessions.
- A-2 — Ratify. The four MET values sit in one map (`lib/core/constants/active_energy.dart:8-13`) and are listed owner-visible here and in the docs.

## Answers to the five questions

### 1. Ending paths (every writer that can store a finished session)

| Writer | Verdict |
|---|---|
| `SessionCore.endSession` (`session_core_lifecycle.dart:23-62`: `endedAtMs: math.max(startedAtMs, now)` :30, settle :51) | covered; settle fires before the health write |
| `SessionCore.updateSessionEndTime` (:161-210: `endedAtMs: newEndedAtMs` :183, settle :201) | covered |
| Other lifecycle writers (`resetSessionTimerStart` :87-107, `updateSessionNote` :141, `updateSessionFeeling` :228-247, `adoptSessionFeeling` :285, `updateSessionRpe` :314) — every one preserves `endedAtMs: _currentSession!.endedAtMs` verbatim | never turn an unfinished session finished; n/a |
| Watch inbox importer, first pass with no phone row (`watch_session_importer.dart:599-617`, `endedAtMs: end.endedAtMs` :604) | **leaves a finished session without Calories — finding 1** |
| Adoption bridge `_startSessionRow` (:975-1020) and `_adopt` (:1046-1092): `createSession` with `startedAtMs: atMs`, no `endedAtMs` | unfinished; the later held end goes through `endSession` — covered |
| Watch engine paths (`watch/watch_session_engine.dart:310`, `watch/debug/*`, `watch/start/*`) | write the watch side, never a phone `TrainingSession` row — n/a |
| `session_core_io.dart:19-32` `createNewSession` | unfinished — n/a; `loadHistoricalSession` restores an already-stored row |
| `lib/mock/seed_data.dart:6837-6853` — a finished seed session (`endedAtMs: 1744016400000`) | dev/test fixture, no energy row → `—`; consistent with the designed no-row state, not a production writer |
| Health import (`health_sync_service.dart`) and routine templates | no `TrainingSession(` construction and no `createSession` call anywhere in either — nothing to settle |

### 2. The Free Training branch and the wrist's measured seconds

`sessionTimeBySectionFor` (`stats_progress_service.dart:939-950`) returns `_sessionSplit(history, session).timeBySection`, whose measured seconds come from `_measuredSecsFor` (:963-990) reading `history.timedInstancesOf`/`roundInstancesOf` — instances the wrist only materialises post-end (finding 2's evidence). At `endSession` the settle therefore sees `measured == {}`, and `sessionTimeByModality` (`training_load.dart:210-214`) hands the whole remainder to resistance. No later import corrects it: `settle` is called only from the two lifecycle sites. A-1 ruled above.

### 3. UI standards in the new pen

`session_summary_screen.dart:965-983`: the pen is an `IconButton` with `tooltip: feeling != null ? 'Change rating' : 'Add rating'` (:967), `constraints: const BoxConstraints(minWidth: 48, minHeight: 48)` (:973-976), an explicit `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius))` (:977-982), and the key `omni_session_effort_rating_button` kept (:966). No raw colour, no bare icon button; `ui_standards_contract_test.dart` green in the full run. The `OmniUtilityButton` import is gone from the screen (the diff removes it), the class doc no longer names the Session Summary (`omni_utility_button.dart:4-6`), and no stale doc comment, import or key remains in lib/ (grep over the old wordings returns only the truthful new ones). New owner-visible words to sign off: the pill label `Calories` (:993), the `~`-prefix convention (`_energyLabel` :1005-1010) with the `—` fallback (pre-existing convention); the tooltips are the old words in a new home.

### 4. Input-reality answers

All seven check out against the code: weight is written only by the Profile screen (`profile_screen.dart:1032`, `logMeasurement(type, canonicalValue, unitId)` with `UnitFormatter.toCanonicalWeight`) and Health (`health_sync_service.dart:263-267`, `value: sample.kilograms`, `unitId: ProfileMeasurements.bodyweight.unitId`); both land in the same measurement store the service reads via `getLatestMeasurement('bodyweight')`, guarded `unitId == MetricIds.unitKg` and finite above zero (`active_energy_service.dart:42-43`). Legacy ids exist (`modality.dart:14-19`) and take the free branch. Rolling is read, never duration-computed (the `!session.isRolling` gate at :48). The kg/lb display setting is cosmetic here (kg stored, the label shows a plain number); no setting flips the answer while the screen sits open — the only recompute on an open screen is the wrist-summary path, which is deliberate (D-13411). Nothing missed beyond finding 2.

### 5. Docs delta (one line per row)

1. docs/session_summary.md `once a rating exists and`→`pen button with the tooltip` -> applied (tests verified below)
2. docs/session_summary.md ADDED `Calories pill` -> applied
3. docs/design_system.md `(Change rating on the Session`→`(the package-serving switch on the food form)` -> applied
4. docs/widget_catalog/layout_and_inputs.md `Used by Change rating /`→`Used by the package-serving switch on the food form` -> applied
5. docs/data_models.md ADDED `SessionEnergy` -> applied
6. docs/db_integration.md ADDED `app_session_energy` -> applied
7. docs/state_management/services_and_utils.md ADDED `ActiveEnergyService` -> applied as a section, but the section carries the false "un-awaited" claim — finding 3
8. docs/session_summary.md `an outlined Utility button...`→`an icon-only pen IconButton...` -> applied
9. docs/session_summary.md `the EFFORT row for every session`→`...with its Calories pill for every session` -> applied
10. docs/session_summary.md `then the EFFORT row (rolling sessions`→`...with its Calories pill (rolling sessions` -> applied
11. docs/state_management/services_and_utils.md ADDED `getSessionEnergy` -> applied
12. docs/db_integration.md ADDED `putSessionEnergy` -> applied
13. docs/README.md `RoutineSessionService, SessionSummaryService, StatsProgressService,`→`...ActiveEnergyService...` -> applied
14. docs/state_management.md `` `SessionSummaryService`, `HealthSyncService` ``→`..., ActiveEnergyService, ...` -> applied
15. docs/design_system.md `two migrated sites keep their keys`→`the food form keeps its key...; the pen keeps omni_session_effort_rating_button` -> applied

Every named test, group, type or constant in the new sentences exists and was read this run: `session_summary_calories_test.dart` groups/tests :130-316; `active_energy_service_test.dart` group `'${harness.name} — ActiveEnergyService.settle'` (:158) resolving to the two cited names with the cited tests; `active_energy_lifecycle_test.dart:69-253`; `session_energy_repository_test.dart:40/:162` groups, tests :52-143; `db_seed_test.dart:810` group; `omni_utility_button_test.dart:14/:55`; `food_form_serving_test.dart:256/:969` (cited by design_system); `session_summary_effort_row_test.dart:887/986` (S-3211/S-3212). Doc edit the table does not name: none — the new `### Calories` section is covered by rows 2/8, and the changed docs (8 files) are exactly the delta's named files.

## Scenario coverage

S-13401 -> `active_energy_service_test.dart:169` + `active_energy_lifecycle_test.dart:69`
S-13402 -> `active_energy_service_test.dart:186` + read-out `:524` + `session_summary_calories_test.dart:149`
S-13403 -> `active_energy_service_test.dart:203, 219`
S-13404 -> `active_energy_service_test.dart:235`
S-13405 -> `active_energy_service_test.dart:320`
S-13406 -> `active_energy_service_test.dart:369` + `active_energy_lifecycle_test.dart:96`
S-13407 -> `active_energy_service_test.dart:408` + `active_energy_lifecycle_test.dart:132` + `session_energy_repository_test.dart:82`
S-13408 -> `session_energy_repository_test.dart:111, 143` + `active_energy_lifecycle_test.dart:169`
S-13409 -> `active_energy_service_test.dart:437, 444, 457, 482, 511`
S-13410 -> `session_energy_repository_test.dart:52-105`
S-13411 -> `session_summary_calories_test.dart:130, 186`
S-13412 -> `session_summary_calories_test.dart:245-316`
S-13413 -> `db_seed_test.dart:810` (`app_session_energy contract (D-13401 / D-13402)`)
S-13414 -> `active_energy_service_test.dart:268`
S-13415 -> `active_energy_service_test.dart:343, 356`
S-13416 -> `active_energy_service_test.dart:299`
S-13417 -> `active_energy_lifecycle_test.dart:196`

No scenario MISSING. The three mutants the lead established as equivalent are the double-protected `measured` row (S-13407/S-13410) and the zero/unfinished backstop (S-13409/S-13415) — covered.
