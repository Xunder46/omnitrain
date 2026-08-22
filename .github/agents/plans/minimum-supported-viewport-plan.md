# Minimum Supported Viewport Plan

## Overview
OmniTrain will declare 360 × 640 logical pixels as its minimum supported portrait viewport. A shared production constant and test harness will make the contract discoverable and ensure required single-viewport screens are rendered at the floor, including the maximum font scale honored by the app.

## Requirements
- Define the minimum supported viewport once as 360 × 640 logical pixels.
- State in project documentation that smaller screens are unsupported and receive no special handling.
- Provide a shared test utility for floor rendering and overflow assertions.
- Cover Home, Exercise Library, and Exercise Detail at the floor and at the app's maximum honored font scale.
- Add a negative-control overflow fixture proving the harness fails on overflow.
- Preserve existing larger-canvas tests and audit other hardcoded sizes.

## Acceptance Criteria
- [ ] A single named value defines 360 × 640 in code and tests use it.
- [ ] Documentation states the minimum and unsupported smaller screens.
- [ ] Shared utility produces the declared floor dimensions.
- [ ] Home, exercise list, and exercise detail pass floor overflow tests.
- [ ] The same screens pass at maximum honored font scale.
- [ ] Deliberate overflow fails through the harness.
- [ ] Existing larger-canvas tests pass unmodified.

## Scenarios
### S-001: Floor contract
- Trigger: Test utility is used.
- Precondition: Shared viewport contract exists.
- Flow: Render a fixture through the utility and inspect the test view size.
- Expected outcome: Exact 360 × 640 logical-pixel dimensions are applied.
- Edge case of: none

### S-002: Required screens at floor
- Trigger: Floor widget tests render Home, Exercise Library, or Exercise Detail.
- Precondition: Required state/repository fixtures are initialized.
- Flow: Pump each screen at the floor and collect Flutter layout exceptions.
- Expected outcome: No overflow or overlap exception is reported.
- Edge case of: S-003

### S-003: Maximum font scale at floor
- Trigger: Floor widget tests render each required screen with max text scale.
- Precondition: App honors the configured maximum scale.
- Flow: Pump each screen with max scale and collect layout exceptions.
- Expected outcome: No overflow or overlap exception is reported.
- Edge case of: S-002

### S-004: Harness negative control
- Trigger: Deliberately overflowing fixture is pumped through the utility.
- Precondition: Overflow assertion is active.
- Flow: Pump fixture and assert the harness detects the overflow.
- Expected outcome: The harness reports failure for the fixture.
- Edge case of: none

## Iteration 1
### DB Changes
Not applicable.

### Backend Changes
Not applicable.

### Frontend Changes
- Add shared supported viewport contract and test harness.
- Add floor and maximum-scale coverage for required screens.
- Add documentation pointer and unsupported-size policy.

### Implementation Steps
1. Add production viewport constants and test helper.
2. Add red tests for contract, overflow detection, and required screens.
3. Run tests, fix only accompanying layout defects if revealed.
4. Run full tests/analyze and review documentation/architecture.

## Progress
- [x] Phase 0: plan authored
- [x] Phase 1: data layer checked
- [ ] Phase 2: tests and implementation complete — **Blocked**: HomeScreen still reports a 14 px right RenderFlex overflow at the maximum honored text scale; required exercise list/detail coverage is not yet added.
- [ ] Phase 3: review complete

## Feedback

### Phase 0 Complete ✓

### Phase 1 Complete ✓
No models, repositories, or schema changes apply.

### Phase 2 Blocked
The shared viewport contract and harness self-tests are implemented. The normal HomeScreen floor test passes, but the maximum-scale HomeScreen test exposes a real 14 px right RenderFlex overflow. The initial EnergyTile label shrink fix did not remove it. Per pipeline protocol, stop and re-plan the remaining layout diagnosis and exercise list/detail coverage in a fresh Coordinator session.
