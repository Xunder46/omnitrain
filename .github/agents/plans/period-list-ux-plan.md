# Feature: period-list-ux

## Overview
UI polish pass on the Training Periods list screen (`PeriodListScreen`):
1. Remove the **Edit** icon button from each row's trailing area.
2. Make the entire list item tappable to open the edit screen.
3. Replace hardcoded `OmniTheme` static color constants with theme-aware values so the row responds to the active app theme.

## Requirements
- Tapping anywhere on a period row navigates to `CreatePeriodScreen` (edit mode) — same behaviour that the old Edit button had.
- The delete icon remains in the trailing area.
- Surface color, text colours, and border colour must change when the user switches theme in Settings.
- No new models, repositories, or state changes required.

---

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes (@developer)

#### `_PeriodRow` widget in `lib/features/period/period_list_screen.dart`

**1. Remove the Edit `IconButton`**
- In `_PeriodRow.build()`, the `trailing` property is currently a `Row` with two `IconButton`s: edit and delete.
- Remove the edit `IconButton` entirely.
- The trailing `Row` becomes a single `IconButton` for delete. Because a single child no longer needs a `Row`, simplify to just the delete `IconButton` directly.

**2. Make the row tappable**
- Add `onTap: onEdit` on the `ListTile`.
- The `ListTile` tap zone already covers the full row width, giving the correct affordance.
- Remove the now-unused `onEdit` field from `_PeriodRow`'s constructor and the `required this.onEdit` parameter — **wait**, `onEdit` is still needed for the `onTap` callback. Keep it but rename semantics: it is already named `onEdit`, which is correct.

**3. Inherit main app theme**

Replace the following hardcoded static constants with theme-aware lookups:

| Hardcoded value | Replace with |
|---|---|
| `OmniTheme.surfaceColor.withOpacity(0.85)` on the `Container` `decoration.color` | `Theme.of(context).colorScheme.surface.withOpacity(0.85)` |
| `OmniTheme.surfaceBorderColor` for the inactive border colour | `OmniTheme.colorsForTheme(OmniTheme.activeTheme).surfaceBorder` |
| `const TextStyle(color: OmniTheme.textPrimary …)` on the period name | `TextStyle(color: Theme.of(context).colorScheme.onSurface, …)` (drop `const`) |
| `OmniTheme.textSecondary.withOpacity(0.75)` on the date range text | `Theme.of(context).colorScheme.onSurface.withOpacity(0.55)` |

> `textPrimary` maps to `colorScheme.onSurface` in `buildTheme` (`app.dart`).  
> `textSecondary` has no direct ColorScheme slot; use `onSurface` at a lower opacity to stay theme-reactive.  
> `surfaceBorderColor` has no ColorScheme slot; use `OmniTheme.colorsForTheme(OmniTheme.activeTheme).surfaceBorder`.

### Implementation Steps
1. [ ] Open `lib/features/period/period_list_screen.dart`.
2. [ ] In `_PeriodRow`'s `trailing`, remove the edit `IconButton` and simplify the trailing to just the delete `IconButton`.
3. [ ] Add `onTap: onEdit` to the `ListTile`.
4. [ ] Change `Container` `decoration.color` from `OmniTheme.surfaceColor.withOpacity(0.85)` → `Theme.of(context).colorScheme.surface.withOpacity(0.85)`.
5. [ ] Change inactive border colour from `OmniTheme.surfaceBorderColor` → `OmniTheme.colorsForTheme(OmniTheme.activeTheme).surfaceBorder`.
6. [ ] Change period name `TextStyle` color from `OmniTheme.textPrimary` → `Theme.of(context).colorScheme.onSurface` (drop `const` qualifier).
7. [ ] Change date range text color from `OmniTheme.textSecondary.withOpacity(0.75)` → `Theme.of(context).colorScheme.onSurface.withOpacity(0.55)`.
8. [ ] Verify no remaining `OmniTheme.surfaceColor`, `OmniTheme.textPrimary`, or `OmniTheme.textSecondary` static refs remain in `_PeriodRow`.
9. [ ] Hot-reload on web; confirm row is tappable, edit button is gone, and switching theme in Settings updates row colours.

## Progress
- [x] Remove edit button from `_PeriodRow` trailing
- [x] Add `onTap: onEdit` to `ListTile`
- [x] Replace `OmniTheme.surfaceColor` with `colorScheme.surface`
- [x] Replace `OmniTheme.surfaceBorderColor` with `colorsForTheme.surfaceBorder`
- [x] Replace `OmniTheme.textPrimary` with `colorScheme.onSurface`
- [x] Replace `OmniTheme.textSecondary` with `colorScheme.onSurface` (lower opacity)
- [ ] Smoke-test: tap row opens edit, theme switches update colours

## Acceptance Criteria
- [ ] Tapping any part of a period row opens `CreatePeriodScreen` in edit mode.
- [ ] No edit icon button is visible on the row.
- [ ] Delete button remains visible and functional.
- [ ] Row surface and text colours change when the active theme is switched in Settings.
- [ ] No hardcoded static `OmniTheme` colour constants remain inside `_PeriodRow`.

## Files Affected
- `lib/features/period/period_list_screen.dart` — only `_PeriodRow` widget

## Notes
- The `_PeriodListScreenState._openEdit` method is still needed for the `onTap` callback; do not remove it.
- The `_PeriodRow` constructor `onEdit` parameter must be kept.
- `modality_colors` chips (inside `subtitle`) use `ModalityColorUtils` which is intentionally theme-independent — leave those unchanged.
- `const` keyword must be removed from the period name `TextStyle` once the colour becomes a runtime value.

## Feedback
