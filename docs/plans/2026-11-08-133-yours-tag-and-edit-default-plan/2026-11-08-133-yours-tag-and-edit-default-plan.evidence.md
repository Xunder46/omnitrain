# Evidence — plan 133

Base `fcd727b3afc81a5deb3d1c75712c298809256f61` (branch `claude_develop`). Nothing committed.

## Runs (observed)

| Step | Result |
|---|---|
| 133a red/green | S-13301 red on the HEAD source (`library_merge_test.dart:170`), green with the fix; source restored `cmp`-identical; `library_merge_test.dart` `+12` |
| 133b1 (crew) | own-copy `+10`, state `+73`, delete-guard `+4`, persistence `+3`, orphan-category `+3` |
| 133b2a (crew) | analyzer 186 = 181 + 5 expected test-file errors; screen_widget `+237`, own-copy `+10` |
| 133b2b (crew) | analyzer 181; `edit_default_food_test.dart` `+12` |
| First full suite | one red: `food_form_serving_test` S-92b.6 (seeded ids `egg`/`rice` are default foods, so Save hit the new dialog); ids changed to `egg_of_mine`/`rice_of_mine`; file `+20` |
| Mutation pass 1 | M1-M9 (no dialog, no restore, old copy kept, pencil closed, photo shared, untouched form copies, no re-log, added to list, seed marker touched): 8 killed, M6 survived (untouched-form test did not assert nothing was created); test strengthened; M6 killed |
| Review (crew-reviewer) | 1 Blocker, 2 Major, 4 Minor: `docs/plans/.../2026-11-08-133-yours-tag-and-edit-default-plan.review.md` |
| Fix round 1 | state reorder (add new food, then remove old copy), photo cleanup on failure, legacy-copy `_openEdit`, 2 doc sentences, stale comment; tests +7 (S-13321, S-13326, S-13329, S-13330, S-13331, S-13333, S-13334) by the crew: own-copy `+13`, edit-default `+16` |
| Mutation pass 2 | M10-M14 (legacy copy opens on copy, photo left on failed create, new catalog food left on failed add, old copy removed before add, photo left on failed add): all killed; sources restored by `cmp` |
| Final | `flutter analyze` 181; `flutter test` full: `+7081 ~2: All tests passed!`; `plan-lint after` clean; invariant grep empty; ui_standards + docs_indexing `+54` |

## Not proven

- Not run on a device or simulator (owner checks in the plan's Progress).
- Review finding 3: S-13322 (copy flow twice), S-13323 (draft photo deleted before Save), S-13325 (remove-after-add ordering as a spy) have no dedicated test; the ordering is pinned indirectly by S-13329/S-13334/M13.
- A Save whose validation then fails re-asks the question on the next press (minor, accepted).
