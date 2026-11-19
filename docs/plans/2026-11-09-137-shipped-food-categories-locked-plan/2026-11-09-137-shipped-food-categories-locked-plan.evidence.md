# Plan 137 — evidence

Observed 2026-11-09 by the lead (not builders' claims). Base commit `ff398e1a`; branch `claude_develop`.

## Runs

| Run | Agent | Result |
|---|---|---|
| P1a | crew-builder-app | lock + Categories row + 3 rewritten tests + lock test: done in 9 min. Lead's diff read found a regression the brief caused (cold-cache catalog load deleted) |
| P1a fix 1 | crew-builder-app | S-13710 added (tests only) |
| P2a | crew-builder-app | `ShippedFoodGroupsRepair` + `currentDataVersion` 19 |
| P1b | crew-builder-app | `test/shipped_food_groups_ui_test.dart` from exact code in the brief |
| P2b | crew-builder-data | step 19 in both stores, pinned tests, repair tests |
| P2b fix 1 | crew-builder-data | surviving mutant M10 killed by a custom-category catalog row case |
| P3 | crew-docs-keeper | Docs delta applied; one stale test-index row reported (lead fixed) |
| Review 1 | crew-reviewer | APPROVE WITH FIXES: 0 blocker, 0 major, 2 minor (both fixed) |
| Review fix 1 | crew-builder-app | `updateFoodGroup` refuses to store a shipped category archived (S-13711) |

## Verification

- `flutter analyze`: 181 issues before and after (baseline 181, shared tree).
- Invariant grep (`hive_workout_repository` imports in state/features/widgets/core): empty.
- Touched tests: lock 11, ui 2, repair 8, delete-guard, membership, orphan integration, data_migration, routine backfill, retire orphan rows (22), catalog refresh, ui standards contract, docs indexing contract: all pass.
- Full `flutter test` #1 (before the fix): `+7304 ~2 -2`; the 2 failures were `retire_orphan_template_rows_test` S-19207 (pins `currentDataVersion == 18`), a reader the seed missed; lead changed the pin to 19, file passes (+22).
- Full `flutter test` #2 (after review fix): `+7312 ~2 -4`; the 4 failures are 30-second timeouts in `pre_release_gate_ios_artifact_test` / `pre_release_gate_notification_and_build_test` (heavy temp-repo copies under suite load); the two files pass alone (`+20 All tests passed`) and were green in run #1. Not related to this plan.
- Full `flutter test` #3 (rerun, another session was running its own `flutter test` at the same time): `+7309 ~2 -7`; the 7 failures were in `delete_focused_timer_test`, `logger_feedback_controls_test`, `timer_digits_hours_test` and the three `pre_release_gate_*` files (timing tests and the 30-second gate timeouts under machine load). Each file run on its own afterwards passes: timers and logger `+21`, gate upload `+8`, gate notification `+8`, gate ios `+12`. No full suite was green end to end after the last change; the only failures seen in any run after the version-pin fix are these load-sensitive files, none touching food categories.
- Docs: `plan-lint after` clean (11 scenarios, 9 rows); `docs_indexing_contract_test` passes; db_integration.md 51,447 bytes (< 52,428 band).

## Mutation pass (lead, in place, byte-restored with `cmp`)

| Mutant | Result |
|---|---|
| M1 delete lock off | killed (S-13702) |
| M2 archive lock off | killed (S-13703) |
| M3 cold-cache load off | killed (S-13710) |
| M4 trash always shown | killed (S-13705) |
| M5 trash never shown | killed (S-13705) |
| M6 constant loses `food-group-condiments` | killed (S-13701) |
| M7 repair rule 1 ignores the archived flag | killed (S-13708) |
| M8 rule 1 restores custom categories too | killed (S-13706) |
| M9 rule 2 overwrites copies that have a category | killed (S-13707) |
| M10 rule 2 accepts any target category | **survived**, then killed after the fix round added a custom-category catalog row |
| M11 rule 2 reads no catalog target | killed (S-13707) |
| M12 rule 2 skips the reassign | killed (S-13707) |
| M13 rule 1 keeps the group archived | killed (S-13706) |
| M14 `updateFoodGroup` lock off | killed (S-13711) |

A bug-fix test must fail without the fix: the lock and repair tests above fail when the guard or rule is turned off (M1-M14). The whole repair step is new (its tests do not compile against the base).

## Not verified here

- (owner) device checks: Dairy and its foods are back after the update; no trash on the nine built-in categories; a category you made still deletes.
- Root cause of the original archive: not reproduced.
