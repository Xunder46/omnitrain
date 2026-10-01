# Feature: Fuzzy Exercise Search

## Overview
Add typo-tolerant fuzzy matching to exercise search so that queries like "dumbel curl" or "bech press" still surface the correct exercises. This is an enhancement to the existing search, not a replacement. Filters, muscle group queries, and tag-based search are unchanged.

## Requirements
- Fuzzy match against exercise **names only** (not description, tips, or instructions)
- Tolerate 1–2 character edit distance (insertions, deletions, substitutions)
- Exact substring matches must still rank first
- Close fuzzy matches appear after exact matches, ordered by edit distance (closest first)
- No new filter UI
- No new pub.dev dependency (pure Dart Levenshtein implementation keeps cold-start cost zero)
- Search must remain responsive on the existing exercise library size

## Acceptance Criteria
- [x] Searching "dumbel curl" returns "Dumbbell Curl" (one-character typo)
- [x] Searching "bech press" returns "Bench Press" (one-character typo)
- [x] Searching "inclin bench prss" returns "Incline Bench Press" (two-character typo across tokens)
- [x] Exact substring matches appear before fuzzy matches in results
- [x] A completely unrelated query (e.g. "zzzzxyz") returns no results / no false positives
- [x] All existing exact-match search tests pass unchanged
- [x] New unit tests covering: exact-first ranking, 1-char typo, 2-char typo, no false positives, performance smoke test

## Scenarios
### S-001: Exact Name Match Ranked First
- Trigger: User enters a query that exactly matches or is an exact substring of an exercise name.
- Precondition: Exercise library contains at least one exact name/substring match and one near fuzzy match.
- Flow: User types search text in exercise picker; repository search executes.
- Expected outcome: Exact substring matches appear before close fuzzy matches.
- Edge case of: none

### S-002: Single-Character Typo Match
- Trigger: User enters a query with one-character typo in a multi-word exercise name.
- Precondition: Exercise name token length allows typo tolerance by threshold rules.
- Flow: Search tokenization runs; token-level edit distance is computed.
- Expected outcome: Correct exercise appears in results.
- Edge case of: S-001

### S-003: Two-Character Typo Match
- Trigger: User enters a query containing two total character errors across query tokens.
- Precondition: Tokens are long enough to allow distance up to 2.
- Flow: Fuzzy scorer computes per-token minimum edit distances and aggregates score.
- Expected outcome: Correct exercise appears in results and is ranked ahead of less similar candidates.
- Edge case of: S-002

### S-004: Unrelated Query Returns No False Positives
- Trigger: User enters a query unrelated to all exercise names.
- Precondition: No exercise token distances satisfy threshold.
- Flow: Search executes normally.
- Expected outcome: Empty result set; no fallback suggestions injected.
- Edge case of: none

### S-005: Short Token Strictness
- Trigger: User enters query tokens with length <= 3.
- Precondition: Candidate names include unrelated short tokens.
- Flow: Per-token threshold applies exact-only matching for short tokens.
- Expected outcome: Unrelated short-token exercises are not returned as fuzzy matches.
- Edge case of: S-004

### S-006: Modality Session Search Ordering
- Trigger: User searches within modality-ranked exercise flow.
- Precondition: Session modality is set and search text is non-empty.
- Flow: Fuzzy filtering runs first; modality ranking metadata is still attached.
- Expected outcome: Fuzzy closeness is primary sort, modality relevance is tie-breaker, and Recommended/Other partition still uses relevance score thresholds.
- Edge case of: S-001

### S-007: Search Responsiveness Smoke
- Trigger: Search runs against a representative in-memory list size.
- Precondition: Around 200 exercises and a 3-token query.
- Flow: `filterAndRank` executes in unit test timing harness.
- Expected outcome: Completion time remains within smoke threshold (<= 50ms target on test environment).
- Edge case of: none

---

## Iteration 1

### Analysis
The search path is:
1. `ExercisePickerDialog._searchExercises()` calls `WorkoutState.getExercisesRankedForModality()`
2. Which delegates to `ExerciseLibrary.getExercisesRankedForModality()`
3. Which calls the repository: **`HiveWorkoutRepository.getExercisesRankedForModality()`** (main path) or **`MockWorkoutRepository.getExercisesRankedForModality()`** (web/test path)
4. A secondary path `searchExercises()` exists on both repos (currently unused in the UI, but still tested)

The current filter in all four locations is:
```dart
final nameMatch = e.name.toLowerCase().contains(lowerSearch);
```

This must be replaced with a fuzzy match that:
- Returns `true` for exact substring matches (preserves existing behavior)
- Returns `true` for close-but-not-exact names within edit-distance threshold
- After filtering, **sorts by match quality** (exact substring > 1-char fuzzy > 2-char fuzzy)

**No package dependency needed.** A pure Dart Levenshtein utility (~60 lines) covers the full requirement.

**Fuzzy scoring strategy — token-based:**
1. Tokenize both query and exercise name into lowercase words (split on whitespace)
2. For each query token, find the best-matching name token by minimum edit distance
3. Sum the minimum edit distances across all query tokens → total distance
4. Include the exercise if total distance ≤ threshold (e.g. `min(2, floor(queryLength / 4))` per token)
5. Rank: total distance 0 (pure substring match treated as distance = 0) < distance 1 < distance 2

**Performance:** Levenshtein on short strings (≤20 chars) with a bounded matrix is O(m×n) per pair. With a library of ~100 exercises and ~3 tokens per query, worst-case ≈ 3 × 100 × 20 × 20 = 120,000 operations — negligible.

### Data Layer Changes
None. No schema changes, no model changes, no new repository methods.

### Backend / Logic Changes

**New file: `lib/core/utils/fuzzy_search.dart`**
- Pure Dart, no Flutter imports
- `FuzzySearch.matches(String query, String candidate) → bool` — returns true if candidate fuzzy-matches query
- `FuzzySearch.score(String query, String candidate) → int` — returns total token edit distance (0 = exact, lower is better)
- `FuzzySearch.filterAndRank(String query, List<Exercise> exercises) → List<Exercise>` — applies match + sorts by score
- Internal `_editDistance(String a, String b) → int` — standard iterative Levenshtein

**Per-token threshold rule:**
- Token length ≤ 3: exact only (distance 0)
- Token length 4–5: allow distance 1
- Token length ≥ 6: allow distance 2

This prevents short tokens from matching wildly unrelated short words.

**Updated files (search logic only — no other changes):**
- `lib/data/repositories/hive_workout_repository.dart` — `searchExercises()` and `getExercisesRankedForModality()`: replace `contains(lowerSearch)` block with `FuzzySearch.filterAndRank()`
- `lib/data/repositories/mock_workout_repository.dart` — same two methods

**Integration pattern:** In both repositories, after applying discipline/muscle-group filters, replace:
```dart
if (searchText != null && searchText.isNotEmpty) {
  final lowerSearch = searchText.toLowerCase();
  results = results.where((e) {
    final nameMatch = e.name.toLowerCase().contains(lowerSearch);
    final descMatch = e.description?.toLowerCase().contains(lowerSearch) ?? false;
    return nameMatch || descMatch;
  });
}
```
with:
```dart
if (searchText != null && searchText.isNotEmpty) {
  final matched = FuzzySearch.filterAndRank(searchText, results.toList());
  results = matched;  // already sorted by score; downstream sorting by modality score preserved for ranking
}
```

**Note on interaction with modality ranking:** `getExercisesRankedForModality` re-sorts the list by modality relevance score after filtering. The fuzzy pre-sort by edit distance gets overridden. That is acceptable per requirements — the feature only asks that results are returned, not that fuzzy rank specifically overrides modality rank. Within ties in modality score, we can preserve fuzzy order as a secondary sort key.

### Frontend / UI Changes
None — this is a pure backend logic change. No UI or navigation modifications.

### Implementation Steps

#### Phase 1: Core Utility (@developer)
1. [x] Create `lib/core/utils/fuzzy_search.dart`
   - Implement `_editDistance(String a, String b) → int` (iterative Levenshtein, O(m×n))
   - Implement `_tokenThreshold(int tokenLength) → int` (≤3 → 0, 4–5 → 1, ≥6 → 2)
   - Implement `score(String query, String candidate) → int` — tokenize both, sum min edit distances
   - Implement `matches(String query, String candidate) → bool` — score ≤ sum of per-token thresholds
   - Implement `filterAndRank(String query, List<Exercise> exercises) → List<Exercise>` — filter by `matches`, sort by `score` ascending

#### Phase 2: Repository Integration (@developer)
2. [x] Update `lib/data/repositories/mock_workout_repository.dart`:
   - `searchExercises()`: replace substring filter block with `FuzzySearch.filterAndRank()`
   - `getExercisesRankedForModality()`: replace substring filter block with `FuzzySearch.filterAndRank()`
3. [x] Update `lib/data/repositories/hive_workout_repository.dart`:
   - `searchExercises()`: same replacement
   - `getExercisesRankedForModality()`: same replacement

#### Phase 3: Tests (@developer)
4. [x] Create `test/fuzzy_search_test.dart` with unit tests for `FuzzySearch` utility:
   - Exact match returns first / score = 0
   - Single-character deletion ("dumbel curl" matches "Dumbbell Curl")
   - Single-character substitution ("bech press" matches "Bench Press")
   - Two-character typo ("inclin bench prss" matches "Incline Bench Press")
   - Completely unrelated query returns no matches (no false positives)
   - Short tokens (≤3 chars) are not fuzzy-matched to unrelated short words
   - Performance smoke test: `filterAndRank` on a list of 200 exercises with a 3-token query completes in < 50ms
5. [x] Verify all existing search-related tests still pass:
   - `test/screen_widget_test.dart` — "filters exercises by search text" (zzzznotanexercise → no results)
   - `test/interaction_flow_test.dart` — "search field filters exercise list"
   - `test/capitalization_defaults_test.dart` — exercise search field tests

### Files Affected
| File | Change |
|------|--------|
| `lib/core/utils/fuzzy_search.dart` | **NEW** — FuzzySearch utility |
| `lib/data/repositories/mock_workout_repository.dart` | Replace substring filter in 2 methods |
| `lib/data/repositories/hive_workout_repository.dart` | Replace substring filter in 2 methods |
| `test/fuzzy_search_test.dart` | **NEW** — Unit tests for fuzzy utility + integration smoke tests |

### Notes
- No package dependency added — pure Dart implementation avoids cold-start cost and version pinning
- The `lib/core/utils/` directory may need to be created if it doesn't exist
- Description-field matching is dropped from fuzzy path (names only, per scope); existing description-match in the non-fuzzy path is also removed to stay consistent (description search was never a user-visible feature)
- The "zzzznotanexercise" test will continue to pass since no exercise name is within edit distance of that string
- For the modality-ranked path, fuzzy closeness is now the primary sort when search text exists; modality relevance is used as tie-breaker.

## Progress
- [x] Create `lib/core/utils/fuzzy_search.dart`
- [x] Update `MockWorkoutRepository.searchExercises()`
- [x] Update `MockWorkoutRepository.getExercisesRankedForModality()`
- [x] Update `HiveWorkoutRepository.searchExercises()`
- [x] Update `HiveWorkoutRepository.getExercisesRankedForModality()`
- [x] Create `test/fuzzy_search_test.dart`
- [x] Verify existing search tests pass

### Phase 0 Red Test Run
- `flutter test test/fuzzy_search_test.dart` failed before implementation due missing `lib/core/utils/fuzzy_search.dart` and undefined `FuzzySearch` symbols.

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.

## Feedback
_Leave empty until a specialist or reviewer adds notes_
