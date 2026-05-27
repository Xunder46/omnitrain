# Feature: period-current-badge-text

## Overview
Change the Training Periods list badge label for a period covering today from "Active" to "Current". This is copy-only and must not alter badge behavior, styling, or placement.

## Requirements
- On `PeriodListScreen`, keep the current active-period detection logic exactly as-is: `startDateMs <= now && endDateMs >= now`.
- Change only the badge text shown for that condition from `Active` to `Current`.
- Do not modify badge layout, spacing, color, typography, border radius, or position.
- Do not change any other use of the word "active" in the app.
- Update/add tests to cover:
- A period including today shows `Current`.
- Past-only and future-only periods do not show the badge.
- Existing in-progress session "active" semantics remain untouched and passing.

## Acceptance Criteria
- [x] A period whose start date is on or before today and end date is on or after today shows a badge reading `Current`.
- [x] A period fully in the past shows no `Current` badge.
- [x] A period fully in the future shows no `Current` badge.
- [x] Badge styling (color, size, placement) is unchanged from before.
- [x] No non-period screen or flow has wording changes from `active` to `current`.
- [x] Unit tests asserting period badge text are updated to `Current`.
- [x] A widget test explicitly verifies one current period renders `Current` while past/future-only periods do not.
- [x] Existing tests for in-progress session "active" behavior remain unchanged and pass.

## Scenarios
- Training Period spans today: badge visible and text is `Current`.
- Training Period ends before today: no badge.
- Training Period starts after today: no badge.
- Existing workout session states and labels using "active" continue unchanged.

## Analysis
This request is a low-risk copy update on one screen with no data-model, repository, state API, or behavioral changes. The only code change should be the literal badge text in the period row widget, plus test updates/additions in period list widget tests.

## Questions (if any)
1. None. Scope and constraints are clear.

## Iteration 1

### DB Changes
None.

### Backend Changes
None.

### Frontend Changes (@developer)
1. Update period badge label text in `lib/features/period/period_list_screen.dart` from `Active` to `Current` within `_PeriodRow`.
2. Do not modify `isActive` boolean calculation or surrounding widget tree/styling properties.

### Implementation Steps
1. [x] Edit `lib/features/period/period_list_screen.dart` and replace only the badge `Text` literal `Active` -> `Current`.
2. [x] Search tests for any period badge expectation tied to `Active`; replace with `Current` where relevant.
3. [x] Add/extend a `PeriodListScreen` widget test in `test/screen_widget_test.dart` to seed three periods (past/current/future) and assert:
4. [x] Exactly one `Current` badge is present for the current period.
5. [x] Past-only and future-only periods do not produce additional `Current` badges.
6. [x] Run targeted tests for period list rendering and related session-labeling tests to confirm no unintended string changes.
7. [x] Run full test suite if feasible, or document any skipped scope.

## Progress
- [x] Update period badge copy in `period_list_screen.dart`
- [x] Update existing period badge test expectations (if present)
- [x] Add/confirm current-vs-past-vs-future badge coverage test
- [x] Verify in-progress session "active" labeling tests remain untouched and passing
- [x] Execute targeted tests and report results

### Phase 1 Complete ✓
Implementation done. All scoped tests green. Ready for Code Reviewer.

## Doc Updates
- docs/navigation_and_screens.md: no update required (no route/screen constructor change)
- docs/state_management.md: no update required (no state API/class changes)
- docs/widget_catalog.md: no update required (no reusable widget contract changes)

## Global Conventions Audit
- Units + canonical storage: N/A
- Theme tokens only: PASS
- Effort-kind drives analytics: N/A
- Timestamps are source data: N/A
- Reuse the canonical owner: PASS
- Instrument panel, not influencer: PASS

## Files Affected
- lib/features/period/period_list_screen.dart
- test/screen_widget_test.dart
- (Only if already present) Any period-specific tests that currently assert `Active` badge wording

## Notes
- Fast-track eligible: this fix has no new user-facing behavior beyond copy, no schema change, and no new state methods; user may skip Conductor and go directly to Developer.
- Keep all other `active` usages out of scope, especially workout/session state labels and transitions.

## Feedback
(none)
