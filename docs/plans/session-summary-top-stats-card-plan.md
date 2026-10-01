# Feature: session-summary-top-stats-card

## Overview
Redesign the Session Summary top stats card to avoid uneven wrapping and orphaned metrics. The card should render primary workout metrics in a stable, balanced layout while preserving existing accent semantics for values.

## Requirements
- Replace the current wrap-based top stats arrangement in Session Summary with a deterministic layout.
- Ensure four core stats render evenly with no orphan row behavior:
  - Duration
  - Exercises
  - Sets
  - Sports
- Acceptable layouts:
  - One evenly-spaced single row (4 equal columns), or
  - A clean 2x2 grid with consistent column widths.
- Keep the current teal accent color behavior for stat values.
- Maintain mobile readability and no overflow on narrow devices.
- Preserve existing card visual style and spacing language used on Session Summary.

## Iteration 1

### DB Changes (@dba)
1. [ ] No database schema changes required.
2. [ ] No repository interface or datasource updates required.

### Backend Changes (@developer)
1. [ ] No business-logic or service changes required for this UI-only update.
2. [ ] Keep existing `SessionSummary` data usage unchanged.

### Frontend Changes (@developer)
1. [ ] Refactor top stats card builder in [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart#L589) to remove `Wrap`-driven layout for the top stat pills.
2. [ ] Define a fixed list for the four primary stats (Duration, Exercises, Sets, Sports) and render them in deterministic positions.
3. [ ] Implement one of the approved layout strategies:
4. [ ] Option A: single row with 4 equal-width children (`Expanded` per metric), centered text, consistent inter-item spacing.
5. [ ] Option B: 2x2 grid using equal-width columns (`GridView`/`Table`/`Row+Column`), fixed spacing, no uneven widths.
6. [ ] Ensure values continue to use the existing teal accent style from `_StatPill` and current theme tokens.
7. [ ] Preserve conditional handling safely:
8. [ ] If `Sets` or `Sports` are zero, still maintain balanced visual structure (either show 0, or define placeholder behavior without collapsing layout consistency).
9. [ ] Verify card does not overflow and remains legible across common phone widths.
10. [ ] Keep all other summary sections unchanged.

### Implementation Steps
1. [ ] Inspect current `_buildStatsCard` and `_StatPill` usage in [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart#L589).
2. [ ] Replace dynamic `Wrap` composition with deterministic 4-metric layout container.
3. [ ] Keep value color styling untouched by reusing `_StatPill` or extracting a reusable stat cell that inherits existing text theme/color behavior.
4. [ ] Add spacing/alignment guards for compact widths (avoid text clipping and overflow).
5. [ ] Run widget tests or targeted screen verification for Session Summary.
6. [ ] Validate that Duration/Exercises/Sets/Sports display evenly for mixed-modality sessions and single-modality sessions.

### Acceptance Criteria
- [ ] Top stats card no longer shows an orphaned metric row.
- [ ] Duration, Exercises, Sets, and Sports are displayed in an even, deterministic layout.
- [ ] Teal accent color for values is preserved.
- [ ] Layout remains visually balanced on small and standard mobile widths.
- [ ] No regressions in other Session Summary sections.

### Files Affected
- [lib/features/session/session_summary_screen.dart](lib/features/session/session_summary_screen.dart)
- [test/widget_test.dart](test/widget_test.dart) (only if current suite is extended for this case)

### Notes
- This request states "Redesign two components" but only the top stats card details were provided. Plan currently scopes implementation to component 1; component 2 can be added in Iteration 2 once requirements are provided.
- Keep implementation environment-agnostic and avoid introducing platform-specific UI branches.

## Progress
- [x] Finalize top stats layout strategy (single row vs 2x2 grid)
- [x] Implement deterministic 4-metric rendering in Session Summary
- [x] Validate teal accent preservation and responsive behavior
- [ ] Add/adjust tests if needed

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->

---

@developer - Please proceed with Phase 2 (Logic/UI) above. No data-layer work is required for this iteration.
