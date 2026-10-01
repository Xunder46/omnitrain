# Feature: Active Session Screen — Set Management Relocation and Toolbar Cleanup

## Overview

Relocate the add-set and remove-set controls from the bottom toolbar to flank the "Set X of Y"
text in the set indicator zone. Replace the trashcan icon with a minus icon. Give the Log Set
button full horizontal width in the toolbar between the two nav arrows.

---

## Requirements

- Add-set and remove-set removed from bottom toolbar (both live and edit mode).
- Minus (remove-set) appears to the LEFT of the "Set X of Y" text.
- Plus (add-set) appears to the RIGHT of the "Set X of Y" text.
- Plus is primary (higher prominence); minus is secondary (lower prominence).
- Remove-set icon: `Icons.remove` (not `Icons.delete_outline`).
- Both flanking buttons meet platform accessibility minimums (44×44 tap target).
- Log Set button fills the space between back arrow and forward arrow (via `Expanded`).
- For logged sets and edit mode, the center nav arrow does NOT fill — it behaves as today.
- Dots row beneath "Set X of Y" is unchanged.
- All logic (caps, disabled states, confirmation dialogs, sequence rules) is unchanged.
- Applies to all modalities: resistance, isometric, cardio, weighted cardio, sports.

---

## Acceptance Criteria

- [ ] Add-set and remove-set no longer appear in the bottom toolbar.
- [ ] Minus icon (remove-set) appears left of "Set X of Y" text; icon is `Icons.remove`.
- [ ] Plus icon (add-set) appears right of "Set X of Y" text; icon is `Icons.add`.
- [ ] Plus button renders with higher visual prominence (primary color or higher opacity).
- [ ] Minus button renders with lower visual prominence (secondary/muted opacity).
- [ ] Both buttons have at least 44×44 dp tap area.
- [ ] Trashcan icon (`Icons.delete_outline`) no longer appears anywhere on this screen.
- [ ] Bottom toolbar in live mode: `back | [Expanded: Log Set] | forward` (3 controls).
- [ ] Bottom toolbar for logged/future sets: `back | center nav arrow | forward` (arrow does not expand).
- [ ] Bottom toolbar in edit mode: `back | center nav arrow | forward` (no add/remove, arrow does not expand).
- [ ] All confirmation dialogs and edge-case logic for add/remove are unchanged.
- [ ] Dots row position and behavior unchanged.
- [ ] Tests S-014, S-015, S-016 updated to find `Icons.remove` instead of `Icons.delete_outline`.

---

## Scenarios

Populated by Developer agent during Phase 0.

---

## Iteration 1

### DB Changes
None.

### Backend Changes
None. `_addSet()` and `_deleteCurrentSet()` in `workout_session_screen.dart` are untouched.

### Frontend Changes

All changes are in `lib/features/session/workout_session_detail_view.dart` and
`test/session_toolbar_rework_test.dart`.

#### 1. `_buildSetProgress()` — extend with flanking buttons

**Current** (line ~613): returns a plain `Text` widget.

**New**: wrap in a `Row` with the set management buttons on each side.

```dart
Widget _buildSetProgress(int totalEntries, String effortKind, ThemeData theme) {
  // ... existing label switch for `label` string (unchanged) ...

  return Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      // Minus — remove-set (secondary, lower prominence)
      Tooltip(
        message: 'Remove set',
        child: InkWell(
          onTap: _deleteCurrentSet,
          customBorder: const CircleBorder(),
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            alignment: Alignment.center,
            child: Icon(
              Icons.remove,
              size: 20,
              color: theme.colorScheme.onSurface.withAlpha((0.35 * 255).round()),
            ),
          ),
        ),
      ),
      // "Set X of Y" text (unchanged appearance)
      Text(label, style: ...),
      // Plus — add-set (primary, higher prominence)
      Tooltip(
        message: 'Add set',
        child: InkWell(
          onTap: _addSet,
          customBorder: const CircleBorder(),
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            alignment: Alignment.center,
            child: Icon(
              Icons.add,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    ],
  );
}
```

**Visual hierarchy decisions**:
- Plus (add-set): `theme.colorScheme.primary` — full primary color, matches existing primary icon
  conventions in the app.
- Minus (remove-set): `theme.colorScheme.onSurface.withAlpha((0.35 * 255).round())` — same muted
  treatment as disabled/secondary icons used throughout the session screen (e.g., the back arrow
  disabled state at 0.2, enabled at 0.5, info button at 0.45). 0.35 sits clearly below the enabled
  arrow (0.5) to communicate lower prominence while remaining legible.

#### 2. `_buildSetControls()` — remove add/delete, expand Log Set

**Live mode — current** (line ~854):
```dart
return Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    backArrow,
    _buildIconButton(Icons.delete_outline, theme, _deleteCurrentSet, tooltip: 'Delete'),
    center,
    _buildIconButton(Icons.playlist_add, theme, _addSet, tooltip: 'Add set'),
    forwardArrow,
  ],
);
```

**Live mode — new**:
- Remove delete and add icon buttons.
- When `center` is the Log Set FilledButton, wrap with `Expanded` to fill available space.
- When `center` is a nav arrow (logged set), do NOT expand — keep it compact as today.
- Add horizontal padding around the Expanded Log Set so it doesn't collide with the arrows.

```dart
return Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    backArrow,
    if (!isLogged && !widget.editMode)
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: center,      // Log Set FilledButton — already fills its container
        ),
      )
    else
      center,                 // nav arrow — compact, no expansion
    forwardArrow,
  ],
);
```

**Edit mode — current** (line ~836):
```dart
return Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    backArrow,
    center,
    Row(mainAxisSize: MainAxisSize.min, children: [
      _buildIconButton(Icons.playlist_add, theme, _addSet, tooltip: 'Add set'),
    ]),
    forwardArrow,
  ],
);
```

**Edit mode — new**: remove the add-set icon button entirely. Center nav arrow stays compact.
```dart
if (widget.editMode) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      backArrow,
      center,
      forwardArrow,
    ],
  );
}
```

#### 3. Log Set button style — fill width

`_buildLogSetButton()` currently has fixed horizontal padding `EdgeInsets.symmetric(horizontal: 20, vertical: 12)`.
When wrapped in `Expanded`, it should set `minimumSize` or let its parent width determine its size.
Update `_buildLogSetButton()` to use `ButtonStyle` with `minimumSize: WidgetStateProperty.all(const Size(double.infinity, 48))` so it fills the Expanded width:

```dart
Widget _buildLogSetButton(String effortKind, ThemeData theme) {
  return FilledButton(
    style: ButtonStyle(
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
        ),
      ),
      minimumSize: WidgetStateProperty.all(const Size(double.infinity, 48)),
    ),
    onPressed: _logSet,
    child: Text(_logSetLabel(effortKind)),
  );
}
```

Remove the old `padding: WidgetStateProperty.all(EdgeInsets.symmetric(horizontal: 20, vertical: 12))` property since `minimumSize` drives the height and the `Expanded` drives the width.

### Test Updates

**File**: `test/session_toolbar_rework_test.dart`

Tests S-014, S-015, S-016 all use `find.byIcon(Icons.delete_outline)` to tap the delete/remove
control. After this change, the icon is `Icons.remove`. Update all three:

| Test | Line (approx) | Change |
|------|--------------|--------|
| S-014 | ~392 | `find.byIcon(Icons.delete_outline)` → `find.byIcon(Icons.remove)` |
| S-015 | ~422 | `find.byIcon(Icons.delete_outline)` → `find.byIcon(Icons.remove)` |
| S-016 | ~454 | `find.byIcon(Icons.delete_outline)` → `find.byIcon(Icons.remove)` |

No other test logic changes are required. The dialogs, confirmation text, and set-count assertions
are unchanged because the underlying `_deleteCurrentSet()` is untouched.

### Implementation Steps

**Phase 1 — Extend `_buildSetProgress`**
1. [ ] In `_buildSetProgress()`, wrap the existing `Text(label, ...)` in a `Row` with a minus
       button on the left and plus button on the right.
2. [ ] Minus: `Icons.remove`, `onTap: _deleteCurrentSet`, color at 0.35 opacity on `onSurface`,
       min 44×44 tap target.
3. [ ] Plus: `Icons.add`, `onTap: _addSet`, color `theme.colorScheme.primary`,
       min 44×44 tap target.
4. [ ] Both wrapped in `Tooltip` with "Remove set" / "Add set" messages.
5. [ ] Preserve the existing `Row(mainAxisAlignment: MainAxisAlignment.center, ...)` structure so
       the indicator zone stays centred.

**Phase 2 — Rework `_buildSetControls` live mode**
6. [ ] Remove the `_buildIconButton(Icons.delete_outline, ...)` call.
7. [ ] Remove the `_buildIconButton(Icons.playlist_add, ...)` call.
8. [ ] Wrap the `center` in `Expanded` + padding when `!isLogged && !widget.editMode`.
9. [ ] Leave `center` compact (no expansion) when `isLogged` or `widget.editMode`.

**Phase 3 — Rework `_buildSetControls` edit mode**
10. [ ] Remove the `Row(mainAxisSize: MainAxisSize.min, children: [_buildIconButton(Icons.playlist_add, ...)])` block.
11. [ ] Edit mode Row now has exactly: `backArrow | center | forwardArrow`.

**Phase 4 — Log Set button fill**
12. [ ] Update `_buildLogSetButton()`: replace fixed `padding` with `minimumSize: Size(double.infinity, 48)`.

**Phase 5 — Test updates**
13. [ ] Update S-014 finder: `Icons.delete_outline` → `Icons.remove`.
14. [ ] Update S-015 finder: `Icons.delete_outline` → `Icons.remove`.
15. [ ] Update S-016 finder: `Icons.delete_outline` → `Icons.remove`.

**Phase 6 — Validation**
16. [ ] Run `session_toolbar_rework_test.dart` — all tests pass.
17. [ ] Run full test suite — no regressions.
18. [ ] Manual verify: all modalities show plus/minus flanking "Set X of Y" text.
19. [ ] Manual verify: toolbar is back | Log Set (expanded) | forward in live mode.
20. [ ] Manual verify: toolbar is back | nav arrow (compact) | forward for logged sets and edit mode.
21. [ ] Manual verify: dots row is unchanged.

---

## Files Affected

| File | Change |
|------|--------|
| `lib/features/session/workout_session_detail_view.dart` | `_buildSetProgress` (flanking buttons), `_buildSetControls` (remove add/delete, expand Log Set), `_buildLogSetButton` (fill width) |
| `test/session_toolbar_rework_test.dart` | S-014/S-015/S-016: change `Icons.delete_outline` → `Icons.remove` |

No model, repository, state, or timer mixin changes required.

---

## Progress

- [x] Phase 1: Extend `_buildSetProgress` with flanking buttons
- [x] Phase 2: Rework `_buildSetControls` live mode
- [x] Phase 3: Rework `_buildSetControls` edit mode
- [x] Phase 4: Log Set button fill width
- [x] Phase 5: Test updates
- [x] Phase 6: Validation

### Phase 1 Complete ✓
All 685 tests pass. Ready for Code Reviewer.

---

## Feedback

