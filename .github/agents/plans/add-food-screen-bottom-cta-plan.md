# Feature: add-food-screen-bottom-cta

## Overview
Continue the shared-bottom-CTA consistency pass
(`primary-bottom-cta-anchor-width-plan.md`). The
`AddFoodScreen` ("Manage Food Library") has **two tabs that still
render their own bottom buttons inline**, bypassing the shared
`OmniBottomCTA` contract:

* **My Foods tab** — an `_AddNewFoodButton` (inline `SizedBox +
  FilledButton.icon`) at the bottom of the tab's `Column`. Not
  safe-area-aware on iOS (no `SafeArea` wrapper), and not at the
  same vertical anchor as every other primary bottom CTA in the
  app.
* **Groups tab** — an `OutlinedButton.icon` for `+ New
  Group` at the bottom of the tab's `Column`. Uses an
  *outlined* style (different from the rest of the app's primary
  bottom CTAs which are *filled*), and is positioned in the body
  rather than the `Scaffold.bottomNavigationBar` slot.

This iteration: (1) routes both buttons through the shared
`OmniBottomCTA` as the `Scaffold.bottomNavigationBar` of
`AddFoodScreen`, (2) makes the CTA tab-aware so each tab's
primary action sits at the shared placement and width, and (3)
adds tests asserting the shared placement, width, and label on
both tabs. Button label, color, and on-press behavior are
unchanged.

## Requirements
- `AddFoodScreen` (`lib/features/nutrition/add_food_screen.dart`)
  has a `Scaffold.bottomNavigationBar` that listens to
  `_tabController` and renders the correct `OmniBottomCTA` for
  the active tab:
  - **Library** tab: no bottom CTA (browse-only).
  - **My Foods** tab: `OmniBottomCTA(label: 'New Food', ...)`
    (the existing `_AddNewFoodButton` label).
  - **Groups** tab: `OmniBottomCTA(label: '+ New Group', ...)`
    (the existing `OutlinedButton.icon` label).
- The `_AddNewFoodButton` widget and the inline `OutlinedButton.icon`
  in the two tabs are removed. The tab bodies' `ListView`s grow
  a bottom padding of `OmniTheme.formBottomCTAClearance` so the
  last row is never hidden behind the CTA.
- The `Key('new_group_button')` is preserved on the
  Groups tab's bottom CTA (forwards via the new
  `OmniBottomCTA.buttonKey` prop) so the existing test contract
  continues to work.
- The text-tap affordance for the "New Food" / "+ New Group"
  buttons in the existing tests continues to work — `find.text(
  'New Food')` and `find.byKey(Key('new_group_button'))` both
  hit the new `OmniBottomCTA`.
- Empty-state `My Foods` tab: the centered `_AddNewFoodButton`
  inside the empty-state `Center + Column` is removed; the
  primary CTA is now on the host's `bottomNavigationBar`. The
  empty state still shows the "No custom foods yet" copy and
  helper text.
- Button label, color, and on-press action for both buttons are
  preserved verbatim.
- No new repository, state, or model changes. Pure UI migration.

## Acceptance Criteria
- [ ] `AddFoodScreen` renders `OmniBottomCTA` on
      `Scaffold.bottomNavigationBar` for the My Foods and
      Groups tabs, and no bottom CTA for the Library tab.
- [ ] The My Foods tab's bottom CTA has the same width, height,
      and vertical anchor as every other primary bottom CTA in
      the app (via `OmniTheme.bottomCTA*` tokens + `SafeArea`).
- [ ] The Groups tab's bottom CTA has the same width,
      height, and vertical anchor; the `Key('new_group_button')`
      is preserved on the rendered `FilledButton`.
- [ ] The My Foods tab's `ListView` and the Groups tab's
      `ListView` both have a `bottomContentPadding` of
      `OmniTheme.formBottomCTAClearance` so the last row is never
      hidden behind the CTA.
- [ ] The empty-state `My Foods` tab no longer renders an inline
      `_AddNewFoodButton` in its `Center + Column`. The empty
      state copy remains.
- [ ] `find.text('New Food')` and `find.byKey(Key('new_group_button'))`
      continue to hit the bottom CTA in the existing tests.
- [ ] New widget tests assert that `AddFoodScreen` exposes
      `OmniBottomCTA` on the `Scaffold.bottomNavigationBar` when
      the My Foods and Groups tabs are active, at the shared
      width and vertical anchor.

## Scenarios

### S-001: AddFoodScreen hosts the shared bottom CTA on the My Foods tab
- Trigger: open `AddFoodScreen`, switch to "My Foods" tab
- Precondition: food library state initialized
- Flow: pumpWidget → switch to "My Foods" tab → pumpAndSettle
- Expected outcome: `Scaffold.bottomNavigationBar` is
  `OmniBottomCTA` with label "New Food" and the shared width /
  vertical anchor. `find.text('New Food')` returns the CTA.
- Edge case of: none

### S-002: AddFoodScreen hosts the shared bottom CTA on the Groups tab
- Trigger: open `AddFoodScreen`, switch to "Groups" tab
- Precondition: food groups loaded
- Flow: pumpWidget → switch to "Groups" tab → pumpAndSettle
- Expected outcome: `Scaffold.bottomNavigationBar` is
  `OmniBottomCTA` with label "+ New Group" and the shared
  width / vertical anchor. `find.byKey(Key('new_group_button'))`
  returns the CTA.
- Edge case of: none

### S-003: Library tab has no bottom CTA
- Trigger: open `AddFoodScreen` (default = Library tab)
- Precondition: catalog loaded
- Flow: pumpWidget → pumpAndSettle
- Expected outcome: `Scaffold.bottomNavigationBar` is `null`
  (or a `SizedBox.shrink()` equivalent), preserving the existing
  browse-only behaviour of the Library tab.
- Edge case of: none

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes (@developer)

#### 1. Add a tab-aware bottom CTA to `_AddFoodScreenState`
File: `lib/features/nutrition/add_food_screen.dart`
- Add an `AnimatedBuilder(animation: _tabController, builder: ...)`
  (or `ListenableBuilder` over a small `ChangeNotifier` derived
  from the controller) that returns the correct `OmniBottomCTA`:
  - `Library` tab → `SizedBox.shrink()` (no bottom CTA).
  - `My Foods` tab → `OmniBottomCTA(label: 'New Food', ...)`
    that calls `_MyFoodsTabState._openNewFoodForm(context)` (or
    the existing `_AddNewFoodButton._openNewFoodForm` method
    hoisted to the host).
  - `Groups` tab → `OmniBottomCTA(label: '+ New Group',
    buttonKey: const Key('new_group_button'), ...)` that
    calls the existing `_GroupsTabState._createGroup`
    (hoist the method to the host or expose it via a callback).
- Add `Scaffold.bottomNavigationBar: <tab-aware CTA>` to the
  `_AddFoodScreenState.build` method.

#### 2. Remove the inline buttons from the two tabs
File: `lib/features/nutrition/add_food_screen.dart`
- `_MyFoodsTab` (empty state + non-empty state): remove the
  `_AddNewFoodButton` from both the empty-state `Center + Column`
  and the non-empty-state `Column` footer. Replace each with a
  bare `ListView` whose bottom padding is
  `OmniTheme.formBottomCTAClearance` so the last row is never
  hidden behind the host's bottom CTA.
- `_GroupsTab`: remove the `SafeArea + Padding +
  OutlinedButton.icon` footer. The `ListView`'s bottom padding
  is `OmniTheme.formBottomCTAClearance`.
- Delete the now-unused `_AddNewFoodButton` class.

#### 3. Doc hygiene
File: `.github/agents/docs/widget_catalog.md` and
`.github/agents/docs/design_system.md`
- No content changes required (the call-site rule already covers
  this case; the previous iteration's `design_system.md` already
  says no inline `Spacer() + SizedBox + FilledButton` is
  permitted at the bottom of a screen).

#### 4. Test hygiene
- Add a new test asserting `Scaffold.bottomNavigationBar` is
  `OmniBottomCTA` when the My Foods tab is active (S-001).
- Add a new test asserting `Scaffold.bottomNavigationBar` is
  `OmniBottomCTA` with `Key('new_group_button')` when the
  Groups tab is active (S-002).
- Add a new test asserting `Scaffold.bottomNavigationBar` is
  `null` when the Library tab is active (S-003).
- Existing tests that `find.text('New Food')` or `find.byKey(
  Key('new_group_button'))` continue to work — the
  affordance moved, the surface key/label is preserved.

### Implementation Steps
1. [ ] Add failing tests for the tab-aware bottom CTA
       (S-001, S-002, S-003).
2. [ ] Hoist the new-food and new-Group callbacks out of the
       tab widgets and into `_AddFoodScreenState` (or expose them
       via callbacks on the tab widgets).
3. [ ] Add a tab-aware `bottomNavigationBar` to
       `_AddFoodScreenState`'s `Scaffold` and wire the existing
       labels and callbacks.
4. [ ] Remove the inline buttons from `_MyFoodsTab` (both empty
       and non-empty states) and `_GroupsTab`. Apply
       `formBottomCTAClearance` to the relevant `ListView`s.
5. [ ] Delete the now-unused `_AddNewFoodButton` class.
6. [ ] Run `flutter test test/screen_widget_test.dart
       test/nutrition_test.dart` until green.
7. [ ] Run `flutter test` for the full suite.
8. [ ] Update the plan file with progress and Phase 3 review
       notes.

## Progress
- [x] Phase 0 complete ✓
- [x] Phase 1 complete (skipped; UI-only)
- [x] Phase 2 complete ✓
- [x] Phase 3 complete ✓

## Feedback
(none)

### Phase 0 Complete ✓
Plan filed. Iteration 1 scope: 1 screen (`AddFoodScreen`) gains a
tab-aware `Scaffold.bottomNavigationBar`; 2 inline buttons removed
(`_AddNewFoodButton` and `OutlinedButton.icon`); 1 obsolete
class deleted (`_AddNewFoodButton`); 1 obsolete method deleted
(`_GroupsTabState._createGroup`); 3 new widget tests added
(S-001, S-002, S-003). Phase 1 skipped: this iteration is pure
UI migration, no repository / state / model changes.

### Phase 2 Complete ✓
Implementation done. `_AddFoodScreenState` now owns a tab-aware
`Scaffold.bottomNavigationBar` (an `AnimatedBuilder` on
`_tabController` that returns the right `OmniBottomCTA` per tab:
`New Food` for the My Foods tab, `+ New Group` for the
Groups tab, `SizedBox.shrink()` for the Library tab). The
host's `_openNewFoodForm` and `_createGroup` methods replace
the previous inline button handlers. The `_AddNewFoodButton`
class and the inline `OutlinedButton.icon` are deleted. Both
tab `ListView`s have a bottom padding of
`OmniTheme.formBottomCTAClearance` so the last row clears the
shared CTA.

Test coverage added:
- S-001 — My Foods tab's bottom CTA at the shared width, height,
  and vertical anchor.
- S-002 — Groups tab's bottom CTA at the shared width, height,
  and vertical anchor; the `Key('new_group_button')` is
  preserved on the rendered FilledButton.
- S-003 — Library tab has no `OmniBottomCTA` on the host's
  `bottomNavigationBar`.

Full test suite: 1442 passing (vs 1439 on the previous iteration —
+3 new passes, 0 new failures). The 2 pre-existing failures
(`Catalog row on the Library tab opens EditFoodScreen on row tap`
and `NutritionStripBar empty state`) are unrelated to this work
and were already failing on master.

### Phase 3 Complete ✓
Review verdict: ✅ APPROVED. All 8 acceptance criteria verified.
All 3 scenarios mapped to passing tests. Doc hygiene: N/A (the
previous iteration's doc updates already cover this case).
Global conventions: PASS (5 rules), N/A (1 rule), FAIL 0.
Architecture compliance: ✅ across all in-scope layers. Buttons
rule: ✅ both migrated tabs now use the shared `OmniBottomCTA`.
Dead code: `_AddNewFoodButton` class and
`_GroupsTabState._createGroup` method both removed. Test
coverage: +3 new passing tests, 0 new failures.
