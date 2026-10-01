# Feature: Retire category-martial-arts, Reparent Disciplines under category-sports

## Overview
`category-martial-arts` is a legacy top-level category whose UI tile was unified into Sports in Feb 2026. The data layer was never cleaned up. This task completes the merge: reparent the three martial-arts disciplines under `category-sports`, remove the dead category record, and purge every code reference to `martial_arts` as a distinct concept.

---

## Inventory (Pre-migration)

### Disciplines currently under `category-martial-arts` (3)
| Discipline ID | key | Name |
|---|---|---|
| `discipline-boxing` | `boxing` | Boxing |
| `discipline-bjj` | `bjj` | Brazilian Jiu-Jitsu |
| `discipline-muay-thai` | `muay_thai` | Muay Thai |

### Exercises under those disciplines
- **discipline-boxing** (10 exercises):
  - `exercise-heavy-bag-rounds`, `exercise-shadowboxing`, `exercise-pad-work`, `exercise-speed-bag`, `exercise-double-end-bag`, `exercise-sparring`, `exercise-defensive-drills`, `exercise-footwork-drills`, `exercise-conditioning-rounds`, `exercise-technical-rounds`
- **discipline-bjj**: 0 exercises in current seed data
- **discipline-muay-thai**: 0 exercises in current seed data

All 10 boxing exercises reference their discipline by `disciplineId` only — **no exercise references `category-martial-arts` directly**. Reparenting disciplines is sufficient to fix exercise resolution.

### Every codebase reference to `martial_arts` / `category-martial-arts`

#### Application code (`lib/`)
| File | Line(s) | What it does |
|---|---|---|
| `lib/mock/seed_data.dart` | 28–35 | `SportCategory` record with `id: 'category-martial-arts'`, `key: 'martial_arts'` |
| `lib/mock/seed_data.dart` | 139–162 | 3 `Discipline` records with `categoryId: 'category-martial-arts'` |
| `lib/core/constants/modality.dart` | 9 | `static const String martialArts = 'martial_arts'` |
| `lib/core/constants/modality.dart` | 29 | `modalityToCategoryId` entry: `martialArts: 'category-martial-arts'` |
| `lib/core/constants/modality.dart` | 40 | `modalityToCategoryIds` entry: `martialArts: ['category-martial-arts']` |
| `lib/core/constants/modality.dart` | 42 | `modalityToCategoryIds` entry for sports: `['category-martial-arts', 'category-sports']` |
| `lib/core/constants/modality.dart` | 57 | `Modality.all` includes `martialArts` |
| `lib/core/constants/modality.dart` | 73 | `getDisplayName` switch case `martialArts → 'Martial Arts'` |
| `lib/core/constants/modality_config.dart` | 77–89 | `'martial_arts': ModalityConfig(...)` entry (with `categoryId: 'category-martial-arts'`) |
| `lib/core/constants/modality_config.dart` | 180 | `getRoundsLabel` switch case `'martial_arts' → 'Rounds'` |
| `lib/core/constants/modality_display.dart` | 7 | `'martial_arts': 'Martial Arts'` in names map |
| `lib/core/constants/modality_display.dart` | 24 | `getRoundsLabel` switch case `'martial_arts' → 'Rounds'` |
| `lib/data/repositories/hive_workout_repository.dart` | 964 | Backward-compat guard: `rawModality == 'martial_arts' ? 'sports' : rawModality` |
| `lib/data/repositories/mock_workout_repository.dart` | 585 | Same backward-compat guard |
| `lib/data/repositories/workout_repository.dart` | 197 | Comment: `/// - 'martial_arts' is folded into 'sports'.` |

#### Scripts
| File | What it does |
|---|---|
| `scripts/sqlite_seed.sql` | `INSERT OR IGNORE` for `martial_arts` category; 3 discipline inserts using `c.key='martial_arts'`; comments referencing both strings |
| `scripts/sqlite_schema.sql` | Comments only (no executable SQL references to `martial_arts`) |

#### Tests
| File | Line(s) | What it does |
|---|---|---|
| `test/utils_test.dart` | 564–565 | Tests `ModalityConfig.getRoundsLabel('martial_arts') == 'Rounds'` |
| `test/utils_test.dart` | 578 | Tests `ModalityConfig.configs.length == 6` (will become 5 after removal) |
| `test/utils_test.dart` | 663–664 | Tests `ModalityConfig.forModality('martial_arts')` anti-capability scoring |
| `test/state_test.dart` | 1239, 1258, 1277, 1300, 1319 | 5 round-lifecycle tests using `createNewSession(modality: 'martial_arts')` |
| `test/models_test.dart` | 431, 437 | Uses `'sports_martial_arts'` — this is the Flutter icon name `Icons.sports_martial_arts`, **not the modality key**. No change needed. |

#### Documentation (`docs/`, `docs/plans/`)
These are agent/plan files, not application code. They do not need to satisfy the zero-matches requirement, but should be updated for accuracy where practical.

---

## Acceptance Criteria
- [ ] No discipline has `categoryId: 'category-martial-arts'`
- [ ] `category-martial-arts` record does not exist in seed data or SQLite seed
- [ ] Project-wide search for `category-martial-arts` returns zero matches in `lib/` and `scripts/`
- [ ] Project-wide search for `martial_arts` returns zero matches in `lib/` and `scripts/` (excluding doc files and icon names such as `sports_martial_arts`)
- [ ] All 10 boxing exercises still resolve: exercise → `discipline-boxing` → `discipline.categoryId == 'category-sports'`
- [ ] Boxing exercises score ≥ 50 (recommended) when ranked for the `sports` modality (affinity 40 + primary capability match ≥ 15)
- [ ] All existing tests pass (with necessary updates to remove `martial_arts` test fixtures)
- [ ] No user-visible change — Sports tile, exercise picker, and session UI are identical

---

## Scenarios

### Scenario: Boxing surfaces under Sports session
1. User taps Sports tile → new session created with `modality: 'sports'`
2. Exercise picker calls `getExercisesRankedForModality('sports', ...)`
3. Repository looks up `ModalityConfig.configs['sports'].categoryId` → `'category-sports'`
4. Heavy Bag Rounds: `disciplineId = 'discipline-boxing'` → `discipline.categoryId = 'category-sports'` (after reparent) → affinity = 40; capabilities `['time', 'rounds']` match primary `['time', 'rounds']` → +30; score = **70** ✅ recommended

### Scenario: Old Hive session with `modality: 'martial_arts'`
After removing the compat guard, any session stored in Hive with `modality = 'martial_arts'` will have an unknown modality at read time. **Resolution**: Since there is no production data, dev-environment Hive storage should be cleared on first run after this change (standard dev workflow). Document this in the PR description.

---

## Implementation Plan

### Phase 1: Data Layer (@dba)

#### 1a. `lib/mock/seed_data.dart` — Dart seed data (primary source of truth for Hive/Mock repos)
1. [ ] Remove the `SportCategory` block for `category-martial-arts` (approximately lines 27–36)
2. [ ] Change `discipline-boxing` `categoryId` from `'category-martial-arts'` to `'category-sports'`
3. [ ] Change `discipline-bjj` `categoryId` from `'category-martial-arts'` to `'category-sports'`
4. [ ] Change `discipline-muay-thai` `categoryId` from `'category-martial-arts'` to `'category-sports'`
5. [ ] Update `SportCategory` for `category-sports`: change `description` to reflect that it now includes boxing/BJJ/Muay Thai (currently already listed there, no change needed)
6. [ ] Confirm no remaining `'category-martial-arts'` or `'martial_arts'` string in the file

#### 1b. `scripts/sqlite_seed.sql` — SQLite seed (future production path)
7. [ ] Remove the `INSERT OR IGNORE INTO app_sport_category` line for `martial_arts` category (line 202)
8. [ ] Change the 3 discipline inserts (boxing, bjj, muay_thai) to use `c.key='sports'` instead of `c.key='martial_arts'` (lines 246, 251, 256)
9. [ ] Update the comments in the UNIFIED SPORTS MODALITY section: remove all references to `category-martial-arts` as a separate category; restate that sports now covers a single `category-sports` containing both martial arts and team sports disciplines
10. [ ] Confirm no remaining `'category-martial-arts'` or `'martial_arts'` string in the file (other than icon-name strings like `sports_martial_arts` which are fine)

#### 1c. `scripts/sqlite_schema.sql` — Comments only
11. [ ] Update the inline comments (lines 11, 19, 197, 571–572) to remove references to `category-martial-arts` and `martial_arts` as a separate modality; replace with a note that martial arts disciplines are part of `category-sports`

---

### Phase 2: Constants & Repository Cleanup (@developer)

#### 2a. `lib/core/constants/modality.dart`
12. [ ] Remove `static const String martialArts = 'martial_arts'` (line 9)
13. [ ] Remove `martialArts: 'category-martial-arts'` entry from `modalityToCategoryId` map
14. [ ] Remove `martialArts: ['category-martial-arts']` entry from `modalityToCategoryIds` map
15. [ ] Simplify `sports` entry in `modalityToCategoryIds`: change `['category-martial-arts', 'category-sports']` to `['category-sports']` — after reparenting, all sports exercises including boxing live under `category-sports`
16. [ ] Remove `martialArts` from `Modality.all` list
17. [ ] Remove `martialArts: 'Martial Arts'` case from `getDisplayName` switch
18. [ ] Update the block comment on `modalityToCategoryIds` to remove the now-outdated "sports modality includes exercises from both category-martial-arts and category-sports" example

#### 2b. `lib/core/constants/modality_config.dart`
19. [ ] Remove the entire `'martial_arts': ModalityConfig(...)` entry (lines 77–89) and its block comment
20. [ ] Remove `case 'martial_arts':` from `getRoundsLabel` switch (line 180)
    - Note: `default:` already returns `'Rounds'`, which is what `'martial_arts'` returned — no behavior change

#### 2c. `lib/core/constants/modality_display.dart`
21. [ ] Remove `'martial_arts': 'Martial Arts'` from the `names` map (line 7)
22. [ ] Remove `case 'martial_arts':` from `getRoundsLabel` switch (line 24)
    - Same as above: `default:` returns `'Rounds'`

#### 2d. Repository backward-compat guards
23. [ ] `lib/data/repositories/hive_workout_repository.dart` line 964: Remove the ternary `rawModality == 'martial_arts' ? 'sports' : rawModality` — simplify to just `rawModality` (or inline it)
24. [ ] `lib/data/repositories/mock_workout_repository.dart` line 585: Same removal
25. [ ] `lib/data/repositories/workout_repository.dart` line 197: Remove the comment line `/// - 'martial_arts' is folded into 'sports'.`

---

### Phase 3: Test Updates (@developer)

26. [ ] `test/utils_test.dart` line 564–565: Remove the `'martial_arts' → Rounds` getRoundsLabel test (the behavior now falls through to `default:` and is already covered)
27. [ ] `test/utils_test.dart` line 578: Update `expect(ModalityConfig.configs.length, 6)` → `expect(ModalityConfig.configs.length, 5)` — removing `martial_arts` leaves 4 named modalities + null = 5
28. [ ] `test/utils_test.dart` line 663–670: Remove the `martial_arts` anti-capability clamping test (it used `ModalityConfig.forModality('martial_arts')` which will return null after removal). Replace with an equivalent test using another modality if the zero-clamp behavior is still worth covering, or remove entirely since it's covered by the comment documentation.
29. [ ] `test/state_test.dart` lines 1239, 1258, 1277, 1300, 1319: Change `createNewSession(modality: 'martial_arts')` → `createNewSession(modality: 'sports')` in all 5 round-lifecycle tests. The `sports` modality has identical `effortKind: 'round'` and round tracking behavior, so the tests remain valid.

---

### Phase 4: Verification (@developer)
30. [ ] Run all tests: `flutter test` — expect green
31. [ ] Manual spot-check: start a Sports session in the web dev build, open exercise picker, confirm Heavy Bag Rounds appears in the recommended list
32. [ ] Confirm home screen has no Martial Arts tile (already confirmed — this was changed Feb 2026)
33. [ ] Confirm modality selector (if surfaced in any picker) shows no Martial Arts option
34. [ ] Search for `category-martial-arts` across `lib/` and `scripts/` — expect zero matches
35. [ ] Search for `martial_arts` across `lib/` and `scripts/` — expect zero matches (except icon names like `Icons.sports_martial_arts` which are unrelated)

---

## Files Affected

### Modified
- `lib/mock/seed_data.dart` (category removal, 3 discipline reparents)
- `lib/core/constants/modality.dart` (constant, 2 map entries, all list, display name)
- `lib/core/constants/modality_config.dart` (config entry, getRoundsLabel case)
- `lib/core/constants/modality_display.dart` (names map entry, getRoundsLabel case)
- `lib/core/constants/modality_colors.dart` (remove separate martial-arts color alias)
- `lib/core/utils/modality_color_utils.dart` (remove separate martial-arts label branch)
- `lib/data/repositories/hive_workout_repository.dart` (compat guard removal)
- `lib/data/repositories/mock_workout_repository.dart` (compat guard removal)
- `lib/data/repositories/workout_repository.dart` (comment removal)
- `scripts/sqlite_seed.sql` (category insert removal, 3 discipline reparents, comment updates)
- `scripts/sqlite_schema.sql` (comment updates)
- `test/utils_test.dart` (2 test removals, 1 count update)
- `test/state_test.dart` (5 modality string replacements)

### Not Modified
- All exercise records — no change needed (exercises reference disciplines only)
- Capability mappings — unchanged (live on exercises, not categories)
- Ranking algorithm — unchanged (only verify it still works correctly)
- `home_tiles.dart` — `Icons.sports_martial_arts` is a Flutter icon name, not the modality key; keep as-is
- `test/models_test.dart` — `'sports_martial_arts'` is a Flutter icon name serialized as a string; not the modality key; no change needed

---

## Notes & Risks

### Affinity scoring post-reparent
After reparenting, the `sports` `ModalityConfig` has `categoryId: 'category-sports'`. Boxing disciplines will resolve to `category-sports`. The `calculateRelevanceScore` method checks `exerciseCategoryId == categoryId` for the 40-point affinity bonus. This works correctly after reparenting — no changes to the scoring algorithm needed.

### Hive dev data migration
If a developer has Hive data stored in their browser with sessions using `modality: 'martial_arts'`, those sessions will have an unknown modality after removing the compat guard. Resolution: clear Hive storage in the browser (Application → IndexedDB → clear) on first run. This is a dev-only concern; no production data exists.

### `Modality.modalityToCategoryIds` simplification
After reparenting, `sports` only needs `['category-sports']`. The dual-category lookup was specifically for the period when martial arts exercises lived under `category-martial-arts`. Simplifying this is safe and removes the last implicit cross-category coupling.

### `Modality.all` still includes legacy modalities
`Modality.all` will still contain `strengthResistance`, `skillTechnique`, etc. (other legacy entries). Removing `martialArts` from this list is the only change needed here.

---

## Progress
- [x] 1a. Remove `category-martial-arts` from `lib/mock/seed_data.dart`
- [x] 1a. Reparent boxing, bjj, muay-thai disciplines in `lib/mock/seed_data.dart`
- [x] 1b. Remove `martial_arts` category insert from `scripts/sqlite_seed.sql`
- [x] 1b. Reparent discipline inserts in `scripts/sqlite_seed.sql`
- [x] 1b. Update UNIFIED SPORTS comments in `scripts/sqlite_seed.sql`
- [x] 1c. Update comments in `scripts/sqlite_schema.sql`
- [x] 2a. Remove `martialArts` constant and map entries from `lib/core/constants/modality.dart`
- [x] 2a. Simplify `sports` `modalityToCategoryIds` entry
- [x] 2b. Remove `'martial_arts'` config entry from `lib/core/constants/modality_config.dart`
- [x] 2b. Remove `getRoundsLabel` case from `lib/core/constants/modality_config.dart`
- [x] 2c. Remove entries from `lib/core/constants/modality_display.dart`
- [x] 2d. Remove compat guards from hive and mock repositories
- [x] 2d. Remove comment from `workout_repository.dart`
- [x] 3. Update test files (utils_test, state_test)
- [x] 4. Run `flutter test` and confirm green — 576/576 passed
- [ ] 4. Manual Sports session verification (boxing in picker)
- [x] 4. Zero-match search verification

### Phase 2 Complete ✓
Constants/repository cleanup done. Ready for Phase 3 test updates and Phase 4 verification.

### Phase 3 Complete ✓
Test files updated. All 576 tests green.

### Phase 4 Complete ✓ (automated)
Zero-match search verified. `flutter test` 576/576 passed. Manual Sports session verification (boxing in picker) is the sole remaining manual step.

## Feedback
- Phase 2 uncovered two additional app-code references not listed in the original inventory: `lib/core/constants/modality_colors.dart` and `lib/core/utils/modality_color_utils.dart`. Both were cleaned up to remove `martial_arts` as a first-class modality.

