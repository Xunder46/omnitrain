# Feature: 52c — the phone keeps a watch set's added weight on a bodyweight exercise, and tells the watch

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE, two minors: one left, a second read of the effort rows that mirrors the per-row read already in that loop; one doc clause fixed). Full flutter +5427 ~2, analyze 180 (baseline), swift 739/0; 11 mutants caught (five only after tests S-8009..S-8011); `docs/watch_session_sync.md` crossed the size band and its "What does not sync" section moved to `docs/watch_session_sync/what_does_not_sync.md`. The wrist half is plan 52d. Seeded 2026-10-21 (owner, in chat: "plank has weight adjustment but push up or wheel rollout don't, on the phone they do"; and "keep going without asking"). Not built. Base commit: `.work/2026-10-21-52c/base.txt`. Team: the crew. Scout sheets: `.work/crew/2026-10-21-52c/scout-importer.md`, `scout-projection.md` (every quote below was read from them and spot-checked). The wrist half is plan 52d. Series: `docs/plans/2026-10-21-51a-wrist-crown-and-layout-plan/2026-10-21-51a-wrist-crown-and-layout-plan.md`. Binding conventions: docs/global_conventions.md; docs/watch_session_sync.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

On the phone a set of an exercise that carries no `load` capability (Push-Up: reps, sets, time; Ab Wheel Rollout) keeps its added weight, or a negative band assist, in the set's extra-weight row; the watch has no such row today, so a push-up on the watch cannot carry a weight (plan 52d adds it). The wire already has the field: a set's `loadKg`. 52c makes the phone read and write it for such exercises.

| What happens | Now | After 52c |
|---|---|---|
| The watch logs a push-up set with `loadKg` 10 | the phone writes 10 into the hidden weight row and 0 into the extra-weight row: the phone's set shows no added weight | the extra-weight row holds 10 and the weight row 0, exactly as if the set were logged on the phone |
| The watch logs it with `loadKg` -20 (band assist) | the same loss | the extra-weight row holds -20 |
| The watch corrects that set's `loadKg` afterwards | edits the hidden weight row | edits the extra-weight row |
| The same wrist set arrives twice (a resend) | one set of rows | still one set of rows |
| The wrist's set fills a phone-planned push-up row | the planned rows are replaced, extra weight 0 | replaced, extra weight = the wrist's `loadKg` |
| The phone logs a push-up set with 12.5 kg added and sends the session to the watch | the entry carries no `loadKg` | the entry carries `loadKg` 12.5 (and the planned set rows carry it too, so the watch starts each set from it) |
| An exercise WITH `load` (bench) | unchanged | unchanged |
| An added weight of 0 | no `loadKg` key | no `loadKg` key (as an entry omits a zero load today) |

No wire change: `loadKg` stays "the set's load in kilograms, negative for an assist, floored at -200 kg". Only the reading of it for an exercise without `load` is stated.

## Decision Ledger

- D-1 Importer, `lib/core/services/watch_session_importer.dart` `_createEntry` (set case, `:1380-1389`): `hasLoad = exercise?.capabilities.contains('load') ?? false`; the row builder gets `weightKg: hasLoad ? (entry.loadKg ?? 0.0) : 0.0` and `extraWeightKg: hasLoad ? 0.0 : (entry.loadKg ?? 0.0)` (`LoggedEntryRows.setObservations` already writes the extra-weight row exactly when `exerciseHasLoad` is false). `_stampedByCorrections` (`:1590`) learns which of the two rows is the load: `weight` is the load's row with `load`, `extra-weight` without.
- D-2 Importer matching, `_EffortRows.unfinishedPlaceOf` (`:1842`) and `_holdsWhatItWrites` (`:1860`): a position written for an exercise without `load` has an extra-weight row, so the check infers it from the rows (`hasExtra`): the weight row must hold `hasExtra ? 0.0 : loadKg`, the extra-weight row `loadKg`. (Today `MetricIds.extraWeight => row.valueReal == 0.0` mirrors the writer that never passed an extra weight.)
- D-3 Importer corrections, `_applyCorrections` set case (`:1514-1550`): a correction of `loadKg` edits `extra-weight` when the entry's position has an extra-weight row (id `obs-<effort>-<index>-extra-weight`), else `weight`. The pair list is no longer `const`.
- D-4 Projection: `PhoneEntries.project` (`lib/core/sync_protocol/phone_entries.dart:66`) and `_entry` (`:440`) gain `required bool exerciseHasLoad`; the load they send is `set['weight']` with `load`, `set['extra-weight']` without (the same floor, the same omission of exactly 0). The bridge's `_entriesFor` (`:295`) passes `exerciseHasLoad` from the slot's capabilities (the slot map already carries them), and `_plannedSetOf` (`:581`) gets the same parameter from the `plannedSets` loop (`:252-262`). The doc comment sentence "A set's added weight is not sent either" is replaced.
- D-5 Contract: a new amendment row in `watch/sync_protocol/PROTOCOL.md` (the table's last rows are `:694`-`:696`; format `| 1 (amended) | 2026-10-21 | ... |`), and the sentence in the 2026-10-07 row (`:683`) that says a set's added weight stays off the wire gets "(superseded 2026-10-21)". No schema, validator or version change. A builder-watch docs-only run (the keeper's ceiling is `docs/**`).
- D-6 Not in scope: the wrist (52d), the Dart watch client under `lib/watch`, timed/hold extra weight (already carried as `extraLoadKg`), routine templates' targets.

## Readers listed (premise check, rule x)

- No test pins "a set's added weight is not sent" (scout `Q3`: the projection fixture builder always passes `exerciseHasLoad: true`); the nearest pins are zero-weight omission (`test/watch_session_projection_test.dart:731-737`, `:1871-1875`, `:2593-2608`), which D-4 keeps.
- The only importer test with a no-load set is `S-274` in `test/watch_session_import_test.dart` (~:1492, `ex-pushup` capabilities `['sets','reps']`, `loadKg: null`): its shape assertions stay true.
- `PhoneEntries.project` has one production caller (the bridge `:309`); `_plannedSetOf` one (`:258`); tests reach both through `projectSession`. `_stampedByCorrections` has one caller (`_createEntry` `:1419`). `_holdsWhatItWrites` one (`unfinishedPlaceOf`).
- Fixtures under `watch/sync_protocol/fixtures` all use `["sets","reps","load"]` slots: untouched.
- Wrist reads of `loadKg` (carry-over and planned-row dial-in, both stacks) are unchanged and become useful in 52d.
- Scenario ids S-8001..S-8010 checked free in `test/`, `docs/`, `watch/`.

## Core scenarios

`test/watch_bodyweight_load_test.dart` (new; Mock repository first; harnesses copied from `test/watch_session_import_test.dart` (`_repository()` with a catalog that also seeds `ex-pushup` with `['sets','reps']`) and `test/watch_session_projection_test.dart` (its `_Set`/fixture builder, but writing the extra-weight row for no-load sets)):
- S-8001 a wrist push-up set with `loadKg` 10 imports as weight row 0.0 and extra-weight row 10.0 (value unlike any default), reps unchanged; the same exercise with `load` (bench) still writes weight 10 and no extra-weight row.
- S-8002 an assist: `loadKg` -20 imports as extra-weight -20.0.
- S-8003 the same wrist set delivered twice (a resend through the unfinished-pass check) leaves exactly one set of rows for that entry (three observations: reps, weight, extra-weight), and a re-import with a CHANGED `loadKg` rewrites the position's extra-weight row, not adds one.
- S-8004 a correction of `loadKg` staged after the import edits the extra-weight row and leaves the weight row at 0.0; the correction of a bench set still edits `weight`.
- S-8005 a wrist set fills a phone-planned push-up row (planned rows reps 10, weight 0, extra-weight 5): after the import there is one set, extra-weight = the wrist's `loadKg`, no row of the planned group left over.
- S-8006 projection: a phone-logged push-up set (extra-weight 12.5) is a snapshot entry with `loadKg` 12.5; a bench set still carries its weight; an extra-weight of exactly 0 carries no `loadKg`; -10 carries -10; an extra-weight below the -200 floor omits the entry (as a weight below the floor does).
- S-8007 planned sets: the push-up's `plannedSets` rows carry `loadKg` from the extra-weight row (5 and 7.5 for two rows; a 0 row omits the key); the bench's rows unchanged.
- S-8008 round trip: a phone-logged push-up set projected to the wrist and a wrist set imported back keep their loads (a wrist set with `loadKg` 10 appears on the phone as extra-weight 10 and in the next projection is claimed by the wrist's own entry, not sent back).

## Phases

- P1 (`crew-builder-app`, glm, `--scope "lib/core/services/watch_session_importer.dart,lib/core/sync_protocol/phone_entries.dart,lib/state/watch/watch_session_adoption_bridge.dart,.work/crew/2026-10-21-52c/**"`): D-1..D-4 as exact text. Done: `flutter analyze` count, `test/watch_session_import_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_session_merge_test.dart`, `test/watch_capture_import_test.dart` and `test/sync_protocol_fixtures_test.dart` (names as found), never the full suite.
- P2 (`crew-builder-app`, glm, after P1, `--scope "test/watch_bodyweight_load_test.dart,.work/crew/2026-10-21-52c/**"`, a SEPARATE run per rule z): S-8001..S-8008; Mock and, for the importer scenarios, Hive if `test/watch_session_merge_test.dart`'s Hive harness can be copied in a few lines (rule i).
- P3 (`crew-builder-watch`, glm, docs only, `--scope "watch/sync_protocol/PROTOCOL.md,.work/crew/2026-10-21-52c/**"`): D-5.
- P4 (`crew-docs-keeper`): `docs/watch_session_sync.md` (search "added weight"), `docs/rest_tracking.md` untouched, the evidence file. Lead: analyze, the touched tests, full `flutter test` once, `swift test` unchanged check, mutations (each of D-1..D-4 one at a time, both arms of every `hasLoad` branch, the `hasExtra` inference, the correction target, the zero and floor omissions), reviewer, commit.

## Owner checks (owner)

- (owner) With 52d on the watch: log a push-up with +10 on the watch; the phone's session screen shows 10 as the added weight on that set. Log one on the phone with +5; the watch starts the next push-up from 5.

## Scope budget

About 70 production lines (Dart), about 300 of test, docs about 20. One main track (the phone) with a contract-doc row; four phases (one is docs).
