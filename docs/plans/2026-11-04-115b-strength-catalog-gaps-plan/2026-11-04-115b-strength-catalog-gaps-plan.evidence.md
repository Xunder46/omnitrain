# Evidence: plan 115b (20 core, leg/hip and press exercises; Trap Bar and Sled equipment)

Base: `7631ea34` (115a) on `claude_develop`. Not committed. Production change: `seed_data.dart` (2 equipment rows, 20 exercise rows with their capability, muscle and equipment entries), `catalog_version.dart` (version 15, lead-made), `sqlite_seed.sql` (+4 equipment inserts), `sqlite_schema.sql` (one comment).

## Baselines and results (all observed by the lead)

| Check | Result |
|---|---|
| `flutter analyze` | 181 issues before and after (baseline 181) |
| Phase 1 files (gaps, db_seed, referential integrity, catalog refresh, strength refresh, tibialis refresh, muscle filter) | `+110: All tests passed!` |
| Phase 2A files after rows 1-10 | `+109: All tests passed!` (290 exercises) |
| Phase 2B files after rows 11-18 | `+117: All tests passed!` (298 exercises) |
| Phase 2B files after rows 19-20 | `+119: All tests passed!` (300 exercises) |
| Full `flutter test` on the 300-exercise catalog (run 1, output saved) | `+6475 ~2: All other tests passed!` (0 `[E]` lines) |
| Phase 3 files (muscle_filter, v15 refresh, strength refresh, tibialis refresh, catalog refresh) | `+61: All tests passed!` |
| Final full `flutter test` (run 2, output saved) | see "Final full run" below |

## Red to green (the lead applied each mutation by hand, ran the guards, restored from a copy, `cmp` identical)

| Mutation | Red tests |
|---|---|
| Sled equipment row removed from the seed | S-19002 (three tests), S-19003 |
| Sled equipment insert removed from the SQL seed | S-19003 |
| `bundledCatalogVersion` left at 14 | S-19006 and S-19007 on Mock and Hive |
| touched-skip removed in `_refreshExercises` | S-19007 on Mock and Hive |
| Push Press with Triceps as a main muscle | S-19001 (push-press row), S-19005 on Mock and Hive |
| Curtsy Lunge with Abductors as a main muscle | S-19001 (curtsy-lunge row), S-19005 on Mock and Hive, the 115a S-18905 group on Mock and Hive, the S-3 approved-rows test |
| Hanging Knee Raise equipment changed to bodyweight | S-19001 (hanging-knee-raise row), S-19008 on Mock and Hive |
| Dead Bug renamed "Dead Bug Hold" | the bundled-name uniqueness test, S-19001 (dead-bug row) |

S-19008(b) (a link pointing at a missing equipment row, Hive only) is a guard only: it is green on today's code once the rows exist.

## Final full run

Run 2 (output saved, 0 `[E]` lines): `+6485 ~2: All other tests passed!`. After it: docs and UI contract tests `+54`; `flutter analyze` 181; diff boundary and repository import invariant print nothing. Review fix (Leg Press Calf Raise step 2 reworded) re-checked: gaps, v15 refresh and docs contract tests `+75: All tests passed!`.

## Review

Verdict APPROVE WITH FIXES. Finding 1 (Blocker, an unrelated header change in the diff) was a false alarm: the owner committed `4c7d9f1a` (Stats title centering) between the base `7631ea34` and the review, so a diff against `7631ea34` included it; the working tree holds only this unit. Finding 2 (series index bookkeeping) is expected. Finding 3 (Leg Press Calf Raise wording) fixed.

## Deviations and notes

- `catalog_version.dart` was edited by the lead (the data builder's ceiling excludes `lib/core/**`): version 15 and its history sentence.
- **Sled logging (open owner question, Q1):** rows 19-20 were built with the plan's default (a): the Farmer's Carry capability set `time, distance, load`, no movement pattern. The owner had not answered when they were built. Changing to (b) is two capability lines plus two table rows in the test; (c) is a separate logger PR.
- The three docs edits were made by the lead: `db_integration.md` (a version-15 sentence citing S-19006, S-19007 and S-19008), `constants_reference.md` (14 to 15), `watch_reference_data.md` ("252 seeded exercises" to "300 ... tens of kilobytes").
- The plan's sweep `grep -n "Trap\|Sled" docs/data_models.md` expected 0; it finds 2 hits, both the Traps muscle (unrelated).
- Rows 19-20 also required the assisting-Calves exact set in `catalog_referential_integrity_test.dart` to gain `sled-push` and `sled-drag` (the plan's S-19004 names it).
- Docs sizes: db_integration 42,715 B; constants_reference 27,482 B; watch_reference_data 22,917 B (all < 53,248).
