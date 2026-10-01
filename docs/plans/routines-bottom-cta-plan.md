# Feature: routines-bottom-cta

## Overview

Replace the `FloatingActionButton` on `MyRoutinesScreen` with the app's shared
`OmniBottomCTA` footer button labeled "+ New Routine". This brings the routines
list screen in line with the unified primary-bottom-CTA pattern used elsewhere
in the app (calendar day list, food library, etc.) and improves discoverability
of the create-routine action via a labeled full-width button.

No data layer changes. No state changes. The routine-creation flow itself is
unchanged — only the launchpad UI moves from a floating `+` icon to a labeled
footer CTA.

**Classification**: TRIVIAL — pure UI swap, no schema/state/behavior change.
Out of scope: changing the routine-creation flow or altering the unified button
component's design.

## Requirements

- Remove the `FloatingActionButton` from `MyRoutinesScreen`.
- Render `OmniBottomCTA(label: '+ New Routine', onPressed: ...)` in
  `Scaffold.bottomNavigationBar`.
- Tap behavior must open the same `RoutineSetupScreen` that the FAB opened.
- The body's `ListView.builder` must reserve bottom clearance for the CTA when
  the routines list is non-empty (via `OmniTheme.formBottomCTAClearance`),
  matching the day-session-list contract.
- The empty-state branch renders inside `Expanded`; the CTA still anchors at
  the bottom of the `Scaffold`.

## Acceptance Criteria

- [ ] `MyRoutinesScreen` no longer renders a `FloatingActionButton`.
- [ ] `MyRoutinesScreen` renders an `OmniBottomCTA` with label `'+ New Routine'`.
- [ ] Tapping the CTA opens `RoutineSetupScreen` (same target the FAB opened).
- [ ] The CTA matches the shared primary-bottom-CTA pattern (full width,
      56 dp height, 12 dp radius, safe-area-anchored bottom) — verified by
      reusing `OmniBottomCTA` as-is.

## Scenarios

### S-001: Routines screen renders the unified "+ New Routine" footer button
- Trigger: User opens `MyRoutinesScreen`.
- Precondition: Routines screen is built (empty or populated list).
- Flow: Render the screen.
- Expected outcome: An `OmniBottomCTA` with label `'+ New Routine'` is rendered.
  No `FloatingActionButton` is rendered.
- Edge case of: none

### S-002: Tapping "+ New Routine" opens the routine creation flow
- Trigger: User taps the `'+ New Routine'` button.
- Precondition: Routines screen is rendered.
- Flow: Tap the CTA.
- Expected outcome: `RoutineSetupScreen` is pushed onto the navigation stack
  (same screen the FAB previously pushed).
- Edge case of: none

## Iteration 1

### DB Changes

None.

### Backend Changes

None.

### Frontend Changes

- `lib/features/routine/my_routines_screen.dart`:
  - Drop the `floatingActionButton:` slot from the `Scaffold`.
  - Add a `bottomNavigationBar:` slot that renders
    `OmniBottomCTA(label: '+ New Routine', onPressed: () => _createNewRoutine(context))`.
  - When the routines list is non-empty, swap the `ListView` padding bottom
    for `OmniTheme.formBottomCTAClearance` so the last card clears the CTA.
  - When the routines list is empty, the empty-state `Column` continues to
    render inside the existing `ListenableBuilder` body (no change needed
    because the CTA is anchored by the `Scaffold`).
- Tests:
  - `test/screen_widget_test.dart`:
    - Update the existing "shows FAB to create routine" test to assert the
      `OmniBottomCTA` label `'+ New Routine'` is rendered and no
      `FloatingActionButton` is rendered.
  - `test/interaction_flow_test.dart`:
    - Update the existing "tapping FAB navigates to RoutineSetupScreen" test
      to find and tap the new CTA (`find.widgetWithText(FilledButton, '+ New Routine')`)
      and confirm navigation to `RoutineSetupScreen`.

### Implementation Steps

1. Write/update tests (Phase 2 — TDD red).
2. Replace `floatingActionButton:` with `bottomNavigationBar: OmniBottomCTA(...)`.
3. Add the CTA-clearance bottom padding to the routines `ListView`.
4. Run `flutter test` until green.
5. Doc hygiene:
   - `docs/my_routines.md` — update the "MyRoutinesScreen" UI
     section: replace the `FAB: (+) button` bullet with a note about the
     shared `OmniBottomCTA` labeled "+ New Routine" and update the
     "Creating a Routine" workflow step ("Tap FAB (+)") to "Tap '+ New Routine'".

## Progress

- [x] Phase 0 — Plan file authored
- [x] Phase 1 — Data layer (skipped: no changes)
- [x] Phase 2.1 — TDD: tests updated and confirmed red
- [x] Phase 2.2/2.3/2.4 — Implementation: FAB removed, OmniBottomCTA wired
- [x] Phase 2.6 — Tests green (320/320 across screen_widget, interaction_flow, header_standardization)
- [x] Phase 2.7 — Doc hygiene: my_routines.md
- [ ] Phase 3 — Code review
### Phase 3 Complete ✓

---

## Code Review: ✅ APPROVED

Layers in scope: features, tests, docs (my_routines.md)
Layers skipped: models, repositories, state, core, widgets (added one import only)

### Acceptance Criteria

| AC | Status | Evidence |
|----|--------|----------|
| FAB removed | ✅ | `my_routines_screen.dart` no longer renders `FloatingActionButton`; `floatingActionButton:` slot deleted |
| Unified "+ New Routine" footer button | ✅ | `bottomNavigationBar: OmniBottomCTA(label: '+ New Routine', ...)` |
| Tapping opens same routine-creation flow | ✅ | `onPressed: () => _createNewRoutine(context)` reuses the existing method that pushes `RoutineSetupScreen` |

### Scenario register

| Scenario | Test | Outcome |
|----------|------|---------|
| S-001 — Routines screen renders the unified "+ New Routine" footer button | `screen_widget_test.dart` "shows unified '+ New Routine' bottom CTA" | ✅ asserts `FilledButton` with `'+ New Routine'` is present, FAB absent |
| S-002 — Tapping "+ New Routine" opens routine creation flow | `interaction_flow_test.dart` "tapping '+ New Routine' CTA navigates to RoutineSetupScreen" | ✅ taps the new CTA, asserts `RoutineSetupScreen` is pushed |

### Doc hygiene table

| Doc | Status |
|-----|--------|
| `my_routines.md` | ✅ Updated — workflow step and UI section reflect the new CTA |
| `widget_catalog.md` | ✅ N/A — `OmniBottomCTA` entry already authoritative |
| `design_system.md` | ✅ N/A — primary-bottom-CTA rule already documented |
| `navigation_and_screens.md` | ✅ N/A — no new screen or route change |
| `state_management.md` | ✅ N/A — no state change |
| `data_models.md` | ✅ N/A — no model change |
| `db_integration.md` | ✅ N/A — no repo method or schema change |

### Global conventions

PASS (6 rules): Theme tokens only (`OmniTheme.formBottomCTAClearance`), Reuse canonical owner (`OmniBottomCTA`), Card chrome via `OmniSurface` (untouched in-scope), Effort-kind drives analytics (N/A — no analytics), Timestamps source data (N/A — no timestamps), Instrument panel (N/A — no motion/decorative changes)
N/A (1 rule): Units + canonical storage — no unit-bearing values changed

### Architecture compliance (features layer)

- ✅ State via constructor injection (unchanged)
- ✅ No direct repo/storage access
- ✅ Logic in state, not UI (CTA only invokes existing `_createNewRoutine`)
- ✅ `ListenableBuilder` reactivity (unchanged)

### Buttons (CTA went through `OmniBottomCTA`)

- ✅ Explicit `shape:` override (enforced by `OmniBottomCTA`)
- ✅ `borderRadius` from `OmniTheme.buttonBorderRadius` (12 dp, widget-enforced)
- ✅ Full-width: `SizedBox(width: double.infinity, height: OmniTheme.buttonPrimaryHeight)` (widget-enforced)
- ✅ Colors from `theme.colorScheme` (widget-enforced)
- ✅ No Material 3 `StadiumBorder`, no hand-styled button

### Environment safety

- ✅ No `dart:io`
- ✅ No SQLite imports in shared code
- ✅ No `Platform.is*`
- ✅ Repository injected via constructor (unchanged)

### DRY + clean code lens

- ✅ No duplicated logic — uses shared widget
- ✅ Naming clear: `label: '+ New Routine'`
- ✅ Magic number (16) for top/sides retained — matches existing `Scaffold` body-padding convention; bottom uses the shared `OmniTheme.formBottomCTAClearance` constant
- ✅ One responsibility per method (untouched)
- ✅ No commented-out code; no orphaned references

### Findings

None.

Critical: 0 | Warnings: 0 | Suggestions: 0
→ @developer: [no action] | → @dba: [no action]

---

⏸️ **PIPELINE COMPLETE** — Implementation and review delivered.
Ready to merge.
### Phase 1 Complete ✓ (no data layer changes — TRIVIAL feature)
### Phase 2 Complete ✓

### Phase 0 Complete ✓

## Feedback

(empty)