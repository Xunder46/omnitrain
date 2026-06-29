# Feature: profile-lean-mass-caption-fix

## Overview

The Lean Mass card on the Profile screen shows a "Computed" caption with the derivation formula (`Body weight × (1 − body fat)`) underneath. The formula `Text` is currently rendered with `maxLines: 1` and `overflow: TextOverflow.ellipsis`, which causes it to clip mid-expression on typical phone widths and display a half-shown formula that reads as broken. This iteration drops the truncation so the formula wraps to additional lines and displays in full. The computed value column (`128 lbs` / `—`) is unchanged and remains the card's primary visual element.

## Requirements

- The Lean Mass caption never displays a formula that ends in a mid-expression ellipsis (`…`).
- The formula either wraps onto additional lines and displays in full, or is omitted in favor of the "Computed" label alone.
- The computed Lean Mass value column is unchanged and remains visually primary.
- No clipping or overflow warning is produced by the caption at the card's current size.

## Acceptance Criteria

- [ ] The Lean Mass card's formula `Text` never truncates with a mid-expression `…`.
- [ ] When the card has enough horizontal room, the full formula text `Body weight × (1 − body fat)` is rendered (possibly wrapped onto two lines) and matches in full.
- [ ] The "Computed" label is always present above the formula (or alone, if the formula is omitted).
- [ ] The computed Lean Mass value column (key `measurement_value`) is unchanged.
- [ ] No `TextOverflow.ellipsis` is applied to the formula `Text`.

## Scenarios

### S-301: Lean Mass formula renders in full (no mid-expression ellipsis)

- Trigger: Profile screen mounts with body weight and body fat entries present.
- Precondition: User has both body weight and body fat % entries so `computedLeanMassKg` is non-null.
- Flow: Profile renders → Lean Mass card renders.
- Expected outcome: The Lean Mass card contains the full formula string `Body weight × (1 − body fat)` as a descendant. No `…` truncation marker is present.
- Edge case of: none.

### S-302: Computed label is always present

- Trigger: Profile screen mounts (with or without body weight / body fat inputs).
- Precondition: Any.
- Flow: Profile renders → Lean Mass card renders.
- Expected outcome: The `Computed` text is rendered above the formula (or alone, if the formula is omitted).
- Edge case of: none.

### S-303: Formula Text does not apply ellipsis overflow

- Trigger: Profile screen mounts.
- Precondition: None.
- Flow: Profile renders.
- Expected outcome: The `Text` widget rendering the formula has no `overflow: TextOverflow.ellipsis` and no `maxLines: 1` constraint.
- Edge case of: none.

## Iteration 1

### DB Changes

None.

### Backend Changes

None.

### Frontend Changes

- `lib/features/profile/profile_screen.dart`
  - In `_buildLeanMassCard`, drop `maxLines: 1` and `overflow: TextOverflow.ellipsis` from the formula `Text` (line 373-377). The formula now wraps to multiple lines as needed. The card body is already inside an `Expanded`, so the available width is bounded and the wrap is contained.
  - Keep `Body weight × (1 − body fat)` as the formula text — no copy change. The `bodySmall` style + `textMuted` color stay the same.
  - No other changes to the Lean Mass card (the value column, "Computed" label, padding, and key all stay).
  - No changes to other measurement cards.

- `docs/profile_and_measurements.md`
  - "Measurement Sections → Lean Mass" subsection: note that the derivation formula wraps onto additional lines if needed (no mid-expression truncation).

- `test/profile_cleanup_test.dart`
  - Existing `S-005/S-006: Lean Mass card is read-only and computed` tests do NOT assert the truncated caption string (they only assert the value column "68 kg" and the absence of an add button). They remain unchanged.

- `test/profile_cleanup_test.dart` — add a new test in the `S-005/S-006` group asserting the full formula text is present (no truncation).

### Implementation Steps

1. Phase 0 — write this plan file.
2. Phase 2.1 — TDD: add a red widget test in `test/profile_cleanup_test.dart` asserting the full formula is rendered; confirm it fails against the current implementation (the truncated string would not match the full formula assertion).
3. Phase 2.2 — drop `maxLines: 1` + `overflow: TextOverflow.ellipsis` on the formula `Text`; confirm the test passes.
4. Phase 2.7 — doc hygiene (one small update to `profile_and_measurements.md`).
5. Phase 3 — code review.

## Progress

- [x] Phase 0 — plan written.
- [x] Phase 2 — red test added (failed against `TextOverflow.ellipsis`), fix applied (dropped `maxLines: 1` + `overflow`), all tests green.
- [x] Phase 3 — review verdict recorded.

## Feedback

### Phase 0 Complete ✓
### Phase 2 Complete ✓

**Red phase**: Added one new test (`caption renders the full derivation formula (no mid-expression ellipsis)`) in `test/profile_cleanup_test.dart` S-005/S-006 group. The test asserts:
- The `Computed` label is rendered (S-302).
- The full formula string `Body weight × (1 − body fat)` is rendered in the widget tree (S-301).
- No descendant text contains the `…` truncation marker (S-301).
- The formula `Text` widget has no `overflow: TextOverflow.ellipsis` (S-303).
- The formula `Text` widget has no `maxLines: 1` (S-303).

The test initially failed with `Expected: not TextOverflow:<TextOverflow.ellipsis> / Actual: TextOverflow:<TextOverflow.ellipsis>` against the current implementation.

**Green phase**: `lib/features/profile/profile_screen.dart` `_buildLeanMassCard`: dropped `maxLines: 1` and `overflow: TextOverflow.ellipsis` from the formula `Text`. Kept the formula string, style, and color unchanged. Added a comment explaining why (no mid-expression truncation).

**Doc hygiene**: `docs/profile_and_measurements.md` "Measurement Sections → Lean Mass" entry updated to note the derivation formula wraps onto additional lines as needed, and that the formula `Text` has no `maxLines: 1` / `TextOverflow.ellipsis` constraint.

**Full test run**: 1,792 passed, 5 skipped, 0 failed (1 new test added on top of the Iteration 3 baseline). No regressions.

### Phase 3 — Code Review

**Layers in scope**: features (`lib/features/profile/profile_screen.dart`), tests (`test/profile_cleanup_test.dart`), docs (`docs/profile_and_measurements.md`).
**Layers skipped**: models, repositories, state, core, widgets, `data_models.md`, `db_integration.md`, `navigation_and_screens.md`, `state_management.md`, `widget_catalog.md` — no changes warranted.

#### Acceptance Criteria

| Criterion | Status | Where |
|---|---|---|
| Lean Mass caption never shows a mid-expression ellipsis | ✅ | `profile_screen.dart:382-386` (no overflow / maxLines on the formula Text) |
| Formula displays in full (wraps as needed) or is omitted | ✅ | wraps to multiple lines as needed (the formula `Text` is inside an `Expanded`, so the available width is bounded and wrap is contained) |
| Computed Lean Mass value column unchanged | ✅ | value column at `profile_screen.dart:401-419` is unchanged; same key `measurement_value`, same style, same `OmniSurface` chrome |
| No clipping/overflow warning at the card's current size | ✅ | formula wraps; no overflow marker (`…`) — asserted by the test `find.textContaining('…')` is `findsNothing` |
| Existing tests don't assert the truncated caption string | ✅ | confirmed via grep — the only mention of the formula text in `test/profile_cleanup_test.dart` is in the new test, which asserts the full string |

#### Scenario Register vs Tests

| Scenario | Test file | Status |
|---|---|---|
| S-301 (full formula renders, no `…` truncation) | `test/profile_cleanup_test.dart` (S-005/S-006 group: `caption renders the full derivation formula`) | ✅ |
| S-302 (Computed label always present) | same test (asserts `find.text('Computed')` is `findsOneWidget`) | ✅ |
| S-303 (formula Text has no `overflow: TextOverflow.ellipsis` and no `maxLines: 1`) | same test (inspects `Text.overflow` and `Text.maxLines` directly) | ✅ |

#### Doc Hygiene

| Doc | Status |
|---|---|
| navigation_and_screens.md | ✅ N/A — no route changes |
| state_management.md | ✅ N/A — no state changes |
| widget_catalog.md | ✅ N/A — no new reusable widget |
| data_models.md | ✅ N/A — no model changes |
| db_integration.md | ✅ N/A — no repository changes |
| profile_and_measurements.md | ✅ Updated — "Measurement Sections → Lean Mass" entry now notes the formula wraps onto additional lines as needed and that no `maxLines: 1` / `TextOverflow.ellipsis` constraint is applied |

#### Global Conventions

```
PASS (5 rules): Card chrome via OmniSurface (unchanged); timestamps are source data (unchanged); reuse the canonical owner (UnitFormatter.formatWeight path unchanged; ProfileState.computedLeanMassKg unchanged); instrument panel not influencer (the fix removes a half-shown broken-looking formula and replaces it with the full formula, which is a functional / readable improvement); theme tokens only (color via OmniTheme.colors.textMuted, unchanged).
N/A (3 rules): Units + canonical storage (no change to height/weight/lean-mass units); effort-kind drives analytics (no effort tracking touched); section/card headers via OmniCardHeader (no headers added or changed).
```

#### Architecture Compliance

- **Features**: state via constructor injection ✅; no direct repository call from `_buildLeanMassCard` ✅; no business logic ✅; `ListenableBuilder` already in `build` (pre-existing) ✅.
- **Widgets**: presentation-only ✅; no state mutation ✅; no repo/service access ✅; no business logic ✅.

#### Buttons

No new `FilledButton`/`OutlinedButton`/`TextButton` introduced. The card body's button-less structure is unchanged.

#### Dead Code

None. The formula `Text` widget is still wired in `_buildLeanMassCard`. `textMuted` color reference unchanged.

#### Test Coverage

| File | Status |
|---|---|
| `lib/features/profile/profile_screen.dart` | ✅ formula `Text` no longer has `maxLines: 1` / `overflow: TextOverflow.ellipsis`. |
| `test/profile_cleanup_test.dart` | ✅ One new test in the S-005/S-006 group asserting full formula + no `…` + no overflow / no maxLines: 1. The existing tests in this group (`renders the computed lean mass value`, `no manual add button`, `updates when body weight changes`, etc.) were verified to NOT assert the truncated caption string — they assert the value column or button absence. |

#### Environment Safety

- No `dart:io` introduced.
- No new SQLite imports.
- No `Platform.is*` checks.
- State still depends on the repository interface only.

#### DRY + Clean Code Lens

- The diff is a 2-line removal (`maxLines: 1`, `overflow: TextOverflow.ellipsis`) plus a comment explaining the WHY. No magic numbers added; no duplicated logic.
- The comment on the formula `Text` explains why (no mid-expression truncation), not what (the absence of the two lines speaks for itself in the code). Consistent with the file's commenting convention.

#### Findings

```
PASS (no critical, no warnings, no suggestions).
```

#### Review Verdict

✅ **Approved.**

The fix removes the `maxLines: 1` + `overflow: TextOverflow.ellipsis` from the Lean Mass formula `Text`. The formula now wraps onto additional lines and displays in full. The computed value column, "Computed" label, card chrome, padding, and key are all unchanged. The new test makes the contract explicit and guards against regressions. No regressions in 1,792 tests.

### Phase 3 Complete ✓