# Evidence — plan 52c (the phone keeps a watch set's added weight on a bodyweight exercise, and tells the watch)

## Scenario-to-test table

| Scenario | Test (`test/watch_bodyweight_load_test.dart`) |
|---|---|
| S-8001 a wrist push-up set with `loadKg` 10 keeps it in the extra-weight row, and a bench set is unchanged | `S-8001 a wrist push-up set with loadKg 10 keeps it in the extra-weight row, and a bench set is unchanged` |
| S-8002 a band assist lands in the extra-weight row with its sign | `S-8002 a band assist lands in the extra-weight row with its sign` |
| S-8003 the same wrist set delivered twice stays one set of rows, and a changed `loadKg` rewrites the extra-weight row | `S-8003 the same wrist set delivered twice stays one set of rows, and a changed loadKg rewrites the extra-weight row` |
| S-8004 a correction of `loadKg` staged after the import edits the extra-weight row, and a bench correction still edits the weight row | `S-8004 a correction of loadKg staged after the import edits the extra-weight row, and a bench correction still edits the weight row` |
| S-8005 a wrist set fills a phone-planned push-up row with its `loadKg` | `S-8005 a wrist set fills a phone-planned push-up row with its loadKg` |
| S-8006 a no-load set's extra-weight rides as `loadKg`, a with-load set's weight does, 0 omits the key, and below the floor omits the entry | `S-8006 a no-load set's extra-weight rides as loadKg, a with-load set's weight does, 0 omits the key, and below the floor omits the entry` |
| S-8007 the bridge's `plannedSets` carry the extra-weight row for a no-load slot, and the bench's rows their weight | `S-8007 the bridge's plannedSets carry the extra-weight row for a no-load slot, and the bench's rows their weight` |
| S-8008 a wrist set the phone merged is not sent back, and the planned rows are unaffected | `S-8008 a wrist set the phone merged is not sent back, and the planned rows are unaffected` |
| S-8009 a `loadKg` correction staged before the import stamps the extra-weight row, and the bench's weight row as before | `S-8009 a loadKg correction staged before the import stamps the extra-weight row, and the bench's weight row as before` |
| S-8010 a pass that did not finish is recognised: the entry rewrites its own rows instead of adding a second copy | `S-8010 a pass that did not finish is recognised: the entry rewrites its own rows instead of adding a second copy` |
| S-8011 the bridge passes the exercise's load capability to the entry projection | `S-8011 the bridge passes the exercise's load capability to the entry projection` |

## Measured results

- `flutter test test/watch_bodyweight_load_test.dart` (this keeper's own run,
  2026-10-21): 11 tests, 0 failures — `00:00 +11: All tests passed!`
- Full `flutter test`: run by the lead, see the plan.
- `flutter analyze`: 180 (baseline).
- The lead's mutation pass: 11 mutants of the importer, the projection and the
  bridge (the weight-row and extra-row writes, stamping on both rows, the
  matching of a written position on both rows, the correction target, both
  projection reads and the capability flag on both call sites). 6 caught at
  once; 5 (extra-row and weight-row stamping, both matching arms, the entries'
  capability flag) only after tests S-8009..S-8011 were added in a fix round.
  Every file restored byte-for-byte.
- NOT verified: the wrist half (plan 52d) and a real push-up logged on a watch
  — owner checks after 52d.
