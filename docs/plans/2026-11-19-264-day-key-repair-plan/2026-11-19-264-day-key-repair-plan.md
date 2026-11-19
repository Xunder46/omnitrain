# Plan 264 — One-off repair of day keys written before plan 235

Owner decision 2026-11-19: "Yes, build repair" (targets and water saved before the plan 235 build looked reset).
Hive only; the Mock step is a no-op. No wire, watch or schema change.

## Cause

Plan 235 (2026-11-18) changed the stored day key of daily targets and water totals from the local midnight instant to the calendar date's UTC midnight and added no migration (its D-7). Entries saved by an earlier build sit under a key no read looks up. Proven on Hive in a UTC-5 zone: a target filed under the old key is not found for that day or for today, and stays in the box. Logged foods carry the day inside the row; an old row still reads as the right day west of UTC and a day early east of it.

## Goal and acceptance

Data migration step 20 `repairDayKeys` (data version 19 -> 20) moves old-style entries to the current key, once per device:

- targets: re-key and rewrite `date_ms`; a new-style entry for the date wins, the old one is dropped;
- water: re-key, rewrite `id` and `date_ms`; when a new-style total exists the two volumes are added;
- logged foods: rewrite the row's `date_ms`.

Acceptance: S-26401..S-26407 green, S-26402..S-26407 red with the step a no-op; `data_migration_test.dart` and `shipped_food_groups_repair_test.dart` updated for the new last step and green; `flutter analyze` not above 178 issues, 0 errors; no new red against the Windows base failing set; Docs delta applied.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-26401 | A stored day is old-style when it is not a whole number of days since the epoch. Its date is read as the local midnight it was in this phone's zone; if it is not a local midnight here (zone changed since), it is rounded to the nearest UTC midnight (right for UTC-11..UTC+11). | `day_key_repair.dart` `newKeyFor` |
| D-26402 | Conflicts: target, the new-style entry wins; water, volumes add (different builds, same date). Retry after a crash between write and delete could double-count one day of water; accepted (the window is one box write). | same |
| D-26403 | The Mock gets a no-op step 20 so both stores walk the same version sequence. | `mock_workout_repository.dart` |

## Scenarios

S-26401 `newKeyFor` (new-style null; local midnight; other-zone midnight). S-26402 an old target is found again and rolls forward. S-26403 a newer target wins. S-26404 old water returns and adds to a new total, id rewritten. S-26405 a food row gets the new-style day. S-26406 a second run changes nothing. S-26407 a device at version 19 reaches 20 on restart and finds the target.

## Input-reality checklist

1. Writers: the migration only. 2. Lifecycle: runs once (version 20); a fresh install has nothing to move. 3. Settings: none. 4. Time: the zone assumption in D-26401. 5. Cost: one pass over three boxes at startup. 6. Words: none. 7. Competition: runs in `initialize()` before the UI.

## Docs delta

`docs/db_integration.md` (step 20 paragraph), `docs/constants_reference.md` (`currentDataVersion` 20).

## Open items

1. (owner) Only helps a phone that still holds the old entries; a reinstall wiped them. Retire the step after launch (procedure in `day_key_repair.dart`).
