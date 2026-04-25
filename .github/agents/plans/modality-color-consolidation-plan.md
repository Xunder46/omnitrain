# Feature: modality-color-consolidation

## Overview
Consolidate modality accent colors into a single source of truth derived from home/landing tile accent values, replace all hardcoded/redefined usages, update documentation to point to the unified constants, and apply modality-specific header label colors in Session Summary.

## Requirements
- Use home tile accent colors as the canonical values (no color changes):
  - `cardio_endurance` / Cardio-Endurance: `#43A047`
  - `resistance_lifting` / Strength-Resistance: `#5B9BD5`
  - `sports`: `#E63946`
  - `isometric_stretching`: `#FFA726`
  - `free_training` fallback: `#7E57C2`
- Define one shared constants source for modality colors (preferred: `lib/core/constants/modality_colors.dart`).
- Replace redefinitions/hardcoded modality color mappings across the codebase with imports from the constants source.
- Add a top-of-file comment in the constants file declaring single source-of-truth policy and usage requirements.
- Update design/theme documentation to reference the new constants file as canonical for modality accents.
- Session Summary category headers must use modality colors for header label text only, not aggregate suffix text.

## Iteration 1

### Analysis
Request has four explicit phases:
1. Audit all current modality color definitions and usage points.
2. Consolidate to one source file using home tile accents as canonical.
3. Document source-of-truth policy and update style docs.
4. Apply consolidated colors to Session Summary category header labels only.

### Audit Findings (Step 1)
- Canonical source currently implied by home tile accents in `lib/core/constants/home_tiles.dart` (tile `accentColor`).
- Redefined hardcoded modality map exists in `lib/core/utils/modality_color_utils.dart` with direct `Color(0xFF...)` returns.
- Modality-color consumers currently route through `ModalityColorUtils`:
  - `lib/features/calendar/calendar_screen.dart` (calendar dots)
  - `lib/features/calendar/day_session_list_screen.dart` (session rows + indicators)
  - `lib/features/period/create_period_screen.dart` (focus modality chips)
  - `lib/features/period/period_list_screen.dart` (focus modality badges)
- Session Summary headers currently use theme primary color, not modality color mapping:
  - `lib/features/session/session_summary_screen.dart` group header label styling in `_buildExerciseGroupHeader(...)`.

### Questions (if any)
1. Resolved: Session Summary should use `Sports` (not `Rounds`) as the group/header name for round-based efforts.

### DB Changes (@dba)
1. [ ] No database schema changes required.
2. [ ] No repository interface updates required.

### Backend Changes (@developer)
1. [ ] Create a single modality color constants source in `lib/core/constants/modality_colors.dart`.
2. [ ] Add canonical maps/helpers for:
   - modality key -> color
  - session summary group key -> color (for `strength`, `cardio`, `sports`, `isometric`)
3. [x] ~~Keep compatibility mapping for legacy `martial_arts` -> sports color.~~ (`martial_arts` retired Apr 2026 — mapping removed)
4. [ ] Refactor `lib/core/utils/modality_color_utils.dart` to consume the new constants (remove duplicate color hex definitions from utility layer).

### Frontend Changes (@developer)
1. [ ] Replace direct/hardcoded modality color usage with constants import route (directly or via refactored `ModalityColorUtils`) in:
   - `lib/core/constants/home_tiles.dart`
   - `lib/features/calendar/calendar_screen.dart`
   - `lib/features/calendar/day_session_list_screen.dart`
   - `lib/features/period/create_period_screen.dart`
   - `lib/features/period/period_list_screen.dart`
2. [ ] Update `lib/features/session/session_summary_screen.dart` so group header label text color is driven by consolidated modality/group color constants, and rename the round-based group header label from `Rounds` to `Sports`.
3. [ ] Ensure aggregate suffix text (`· X sets/rounds/time`) remains unchanged (existing muted color).

### Documentation Changes (@developer)
1. [ ] Add a top comment block in `lib/core/constants/modality_colors.dart` stating it is the single source of truth and must be imported by new screens/components.
2. [ ] Update `.github/agents/docs/design_system.md` Color System section to reference `lib/core/constants/modality_colors.dart` as canonical modality accent source.
3. [ ] If needed, add a short cross-reference note in `.github/agents/docs/modality_tracking.md` under modality tiles mentioning colors are defined centrally in `modality_colors.dart`.

### Implementation Steps
1. [ ] Capture the exact canonical values from `HomeTiles.all` accent colors and codify them once in `modality_colors.dart`.
2. [ ] Wire `HomeTiles` accentColor fields to those constants (ensures home tiles consume same source they define semantically).
3. [ ] Refactor `ModalityColorUtils.colorForModality(...)` to read from constants map and keep existing API for consumers.
4. [ ] Run grep for legacy hex values (`43A047|5B9BD5|E63946|FFA726|7E57C2`) and remove duplicates outside the constants source.
5. [ ] Apply modality/group color mapping in Session Summary `_buildExerciseGroupHeader` label style only, with round-based efforts grouped under `Sports`.
6. [ ] Validate calendar dots, day session list indicators, and period focus chips still match home tile accents.
7. [ ] Run tests and analyzer for touched files.

### Acceptance Criteria
- [ ] Exactly one constants source defines modality accent colors.
- [ ] Home/landing tile accent colors and all modality indicators remain visually identical to current values.
- [ ] No duplicate hardcoded modality accent hex values remain outside the consolidated constants source (excluding non-modality unrelated palette values).
- [ ] Calendar dots and period/chip modality indicators resolve colors from the consolidated source.
- [ ] Session Summary category header label text uses modality colors, with `Sports` replacing `Rounds` in the round-based group label.
- [ ] Session Summary aggregate suffix text color remains unchanged.
- [ ] Documentation references the consolidated modality color constants file.

### Files Affected
- `lib/core/constants/modality_colors.dart` (new)
- `lib/core/constants/home_tiles.dart`
- `lib/core/utils/modality_color_utils.dart`
- `lib/features/calendar/calendar_screen.dart` (if direct mapping usage changes)
- `lib/features/calendar/day_session_list_screen.dart` (if direct mapping usage changes)
- `lib/features/period/create_period_screen.dart` (if direct mapping usage changes)
- `lib/features/period/period_list_screen.dart` (if direct mapping usage changes)
- `lib/features/session/session_summary_screen.dart`
- `.github/agents/docs/design_system.md`
- `.github/agents/docs/modality_tracking.md` (optional note)

### Notes
- Keep environment strategy intact: color constants are platform-agnostic and shared by web + native.
- Favor minimal API churn by preserving `ModalityColorUtils` public methods while moving color ownership to constants.
- Round-based efforts should display under the `Sports` group label for this iteration.

## Progress
- [x] Confirm `Sports` vs `Rounds` header treatment for Session Summary
- [x] Add unified modality color constants source
- [x] Refactor utilities and consumers to import consolidated colors
- [x] Apply header label color mapping in Session Summary
- [x] Update documentation references
- [ ] Run validation (analyzer/tests)

## Feedback
<!-- Leave empty until a specialist or reviewer adds notes -->

---

@developer - Please proceed with Phase 2 (Logic/UI + documentation) above after confirming Question #1. No data-layer work is required.
