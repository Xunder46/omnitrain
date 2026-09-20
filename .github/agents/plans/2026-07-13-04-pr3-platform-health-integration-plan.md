# Feature: Platform Health Integration (Phone)

> **Tier 1 — Phone quick wins.**
> Last reconciled against source: 2026-07-13.

## Overview

Logged sessions should flow into Apple Health (iOS) and Health Connect
(Android) with mapped activity types, and useful basics like body weight
should flow back. This integration is the universal wearable bridge on
the phone side: owners of Garmin, Whoop, Polar, and other bands already
sync into the platform health stores, so writing OmniTrain workouts to
those stores plus reading body weight back is what makes OmniTrain work
alongside any wearable ecosystem. Both directions are entirely opt-in
and off by default, with separate Settings toggles for write and read,
consistent with the local-first privacy story.

## Requirements

### Write path

- When the user completes a training session, it is written to the
  platform health store as a workout with the activity type mapped from
  its modality, plus start time, end time, and duration.
- Activation is from the point of toggle-on forward only — no bulk
  historical export.
- Disabling write stops future writes but does not delete previously
  written workouts.

### Read path

- The user can enable importing body weight from the health store;
  weight samples are surfaced in the Profile measurement history alongside
  the user's logged weight data. (Originally written as "in Stats" —
  amended 2026-07-20, see AC 3 and F-1.)
- Disabling read stops future imports; previously imported data is
  retained (this is the user's logged data once imported).

### Permission and toggle rules

- Settings exposes two independent toggles: `Write workouts` and
  `Read body weight`, each with a plain-language explanation of what is
  shared or read.
- OS-level permission denial degrades gracefully: the app stays fully
  functional, the toggle reflects the denied state, and the user is
  pointed to system settings.
- Uninstalling and reinstalling does not resurrect either toggle as
  enabled (toggles live in the same persistence as other Settings).

### Out of scope

- Live heart rate (watch scope, separate item).
- Bulk historical import / export.
- Writing nutrition data to the health stores.
- Reading workouts from other apps into OmniTrain.

## Acceptance Criteria

- [ ] With write enabled, completing a session in each of the four
      effort-kind families produces a workout entry in Apple Health /
      Health Connect with the correct activity type, start time, and
      duration.
- [ ] With write disabled, no entry is produced for a completed
      session.
- [ ] With read enabled and body weight present in the health store,
      body weight appears in the Profile measurement history and weight
      display within one app-foreground cycle.
      **Amended 2026-07-20** — the original wording said "in Stats".
      Stats has no measurement surface and the product owner has ruled
      that it should not gain one: body weight is logged and displayed
      on Profile, so that is where imported samples land. No Stats UI
      changes. See F-1 in `## Feedback`.
- [ ] Denying the OS permission leaves the app functional, with the
      toggle accurately reflecting the denied state and a plain-language
      pointer to system settings.
- [ ] Uninstalling and reinstalling does not resurrect either toggle as
      enabled.
- [ ] An unmapped modality falls back to a generic workout type
      instead of crashing.
- [ ] Settings copy is plain-language and explains exactly what is
      shared / read per toggle.

## Scenarios

### S-001: Write a completed session to Apple Health
- Trigger: User finishes a resistance session on iOS; `Write workouts`
  toggle is enabled and OS permission is granted.
- Precondition: Session has modality `resistance_lifting`, completed
  timestamp, duration.
- Flow: Session completion triggers the write pipeline → modality maps
  to `HKWorkoutActivityType.traditionalStrengthTraining` →
  `HKWorkout` is saved with start, end, duration.
- Expected outcome: Apple Health shows a strength-training workout with
  matching start, end, and duration within seconds.
- Edge case of: none

### S-002: Write a completed cardio session to Health Connect
- Trigger: User finishes a cardio session on Android; `Write workouts`
  toggle is enabled and OS permission is granted.
- Precondition: Session modality `cardio_endurance`.
- Flow: Session completion → modality maps to Health Connect exercise
  type → `HealthConnectWorkout` is saved.
- Expected outcome: Health Connect shows a cardio workout with
  matching start, end, and duration.
- Edge case of: S-001

### S-003: Disabled write does not produce an entry
- Trigger: User completes any session with `Write workouts` disabled.
- Precondition: Toggle is off, OS permission may or may not be granted.
- Flow: Session completes.
- Expected outcome: No write pipeline call; no entry appears in the
  platform health store.
- Edge case of: S-001

### S-004: Body weight read appears in the Profile measurement history
- Trigger: User enables `Read body weight` and grants OS permission.
- Precondition: Body weight samples exist in Apple Health /
  Health Connect for the past 90 days.
- Flow: App foregrounds → read pipeline queries the most recent N
  samples → samples merge into the user's measurement history.
- Expected outcome: Imported samples appear in the Profile weight
  display within one foreground cycle, in the user's preferred unit.
- Edge case of: none
- **Amended 2026-07-20** — title and outcome originally said "Stats"; see
  the amendment note on AC 3 and F-1 in `## Feedback`.

### S-005: OS permission denial degrades gracefully
- Trigger: User denies the OS permission prompt for either write or
  read.
- Precondition: Toggle is on; the OS prompt is presented.
- Flow: Denial is captured → toggle state is updated to reflect denied
  state; explanation copy surfaces a pointer to system settings.
- Expected outcome: App remains fully usable. Toggling back on prompts
  the OS again. Profile renders normally with only the user's logged
  data.
- Edge case of: S-001, S-004

### S-006: Uninstall and reinstall resets both toggles
- Trigger: User uninstalls the app, reinstalls, and opens Settings.
- Precondition: Pre-uninstall state had both toggles enabled.
- Flow: Reinstall → onboarding (if applicable) → Settings.
- Expected outcome: Both toggles are off. The user must opt in again.
- Edge case of: S-001, S-004

### S-007: Unmapped modality falls back to a generic type
- Trigger: A new modality is added to the catalog that has no mapping
  rule yet; the user finishes a session of that modality with
  `Write workouts` enabled.
- Precondition: Mapping table lacks the modality.
- Flow: Modality-to-type lookup falls back to a generic workout type
  (e.g. `HKWorkoutActivityType.other` / Health Connect equivalent).
- Expected outcome: An entry is still written with the generic type
  and correct timing; no crash, no missed write.
- Edge case of: S-001

### S-008: Write pipeline invoked exactly once per completion
- Trigger: Session completion with write enabled.
- Precondition: Idempotency contract for the write pipeline.
- Flow: Session transitions to completed → write pipeline fires once
  and only once.
- Expected outcome: Exactly one platform-health entry exists for that
  session, regardless of subsequent foregrounds or app restarts.
- Edge case of: S-001

## Iteration 1

### DB Changes

- Add two settings keys (`health.writeWorkouts`, `health.readBodyWeight`)
  to the existing settings persistence. No new model class is required
  if Settings already uses a typed wrapper; if not, add a small
  `HealthSettings` struct in `lib/data/models/`.
- No new session / observation schema. Body weight samples are mapped
  into the existing measurement model on import.

### Backend Changes

- New `lib/core/services/health_platform_service.dart`:
  - `requestPermissions({required bool write, required bool read})`.
  - `writeWorkout(Session session)` — internal call after session
    completion; idempotent per session id.
  - `readBodyWeight({required DateTime since})` — returns samples
    consumable by the measurement flow.
- New `lib/core/services/health_modality_mapper.dart` (or extend the
  constants file) for modality → platform activity type mapping, with a
  generic fallback.
- A thin wrapper that the `WorkoutSession` state owner (or
  `SessionState`) calls once on session completion when the toggle is
  on; integration happens through the repository / settings, not by
  importing platform SDKs into shared state.
- Unit conversion for body weight (kg ↔ lb) honours `SettingsState` /
  `UnitFormatter` from `docs/global_conventions.md`.

### Frontend Changes

- Two new toggles in `SettingsScreen` under a new "Health" section:
  `Write workouts` and `Read body weight`, each with plain-language
  copy explaining what is shared / read and a system-settings deep link
  on denied.
- Profile: body weight samples merge into the existing measurement
  history and weight display; no new UI is added. (Originally written as
  "Stats ... no new tile" — amended 2026-07-20, see AC 3 and F-1.)
- No new screens, no new routes.

### Implementation Steps

1. Choose the Flutter plugins (`health` package is the common choice
   across both platforms; record the decision in a comment).
2. Add the settings persistence keys.
3. Implement `HealthPlatformService` with permission, write, and read
   methods. Make `writeWorkout` idempotent keyed on session id.
4. Wire session completion → write call (gated by settings).
5. Wire app foreground → read call (gated by settings) → merge into the
   measurement flow.
6. Add the two toggles in Settings with the denied-state UI.
7. Tests (see Unit Tests Required).

## Unit Tests Required

- `test/health_platform_mapper_test.dart` — modality → platform activity
  type mapping for every seeded modality; an unmapped modality returns
  the generic fallback type, never throws.
- `test/health_platform_test.dart` — the write pipeline is invoked
  exactly once per session completion when enabled and never when
  disabled. Mock the platform service; verify call counts.
- `test/health_platform_test.dart` — read-path parsing for body weight
  samples, including kg ↔ lb unit conversion honouring the user's
  preference.
- `test/health_platform_test.dart` — OS permission denial updates the
  toggle state to denied and does not surface an unhandled error.
- `test/health_platform_test.dart` — toggles reset to off after a
  simulated uninstall / reinstall (settings persistence rebuilt).

## Progress

- [x] TDD: tests authored, red run recorded
      Red run (2026-09-20): `flutter test test/health_platform_mapper_test.dart test/health_platform_test.dart`
      → compile failure only, with `No such file or directory` for
      `lib/core/constants/health_constants.dart`,
      `lib/core/services/health_modality_mapper.dart`, and
      `lib/core/services/health_platform_gateway_io.dart`.
      No test-configuration errors; the implementation is absent as expected.
- [x] Phase 1 — Data Layer (settings keys + mapper constants)
- [x] Phase 2 — Logic & UI (service + Settings toggles + Profile
      measurement merge)
- [x] Phase 3 — Code Review
      Iteration 1 review raised F-1…F-5 (see `## Feedback`); all resolved.
      Re-validated 2026-07-20 — see "Iteration 1 validation" below.
- [ ] Release-ready — blocked only by an unrelated working-tree artefact, not
      by this plan. See "Iteration 1 validation" → Outstanding.

### Phase notes

- Plugin decision (step 1): `health: ^13.3.1` — one package for both Apple
  Health and Health Connect. It imports `dart:io`, so it is isolated behind
  the conditional export in `health_platform_gateway.dart` (mirrors
  `image_storage_service.dart`) and never enters the web compilation path.
- The plugin validates activity types per platform and throws on a
  cross-over (`TRADITIONAL_STRENGTH_TRAINING` is iOS-only;
  `STRENGTH_TRAINING` is Android-only), so the gateway translates
  `HealthActivityKind` per platform. Pinned by
  `test/health_platform_mapper_test.dart`.
- iOS deployment target raised 13.0 → 14.0 (project-level, all three
  configurations) because the plugin's podspec requires 14.0. This is a
  user-facing platform-support change: iOS 13 devices are no longer
  supported. `ios/Runner/Runner.entitlements` (HealthKit capability) is
  referenced from all three Runner build configurations.
- Android SDK is not installed on this machine, so the debug APK build
  could not be run; the manifest edits were validated for well-formedness
  and against the plugin's documented Health Connect requirements only.
  `flutter build ios --debug --no-codesign` and `flutter build web
  --release` both succeed.
- Two pre-existing test failures lived in `SettingsScreen` tests that
  assumed all sections fit the test viewport (`Switch` not found at
  `interaction_flow_test.dart`, `findsNWidgets(4)` headers in
  `header_standardization_test.dart`). Both were rewritten to scroll the
  target into view (the codebase's existing pattern in
  `screen_widget_test.dart`) and the header test now covers the new
  `HEALTH` section.
- Docs updated: `state_management.md` (index + class lookup),
  `state_management/services_and_utils.md` (`HealthSyncService` layer
  contract + invariants), `state_management/app_state.md` (`SettingsState`
  toggles), `state_management/workout_state.md` (`endSession` delegation),
  `navigation_and_screens.md` (Settings row + DI graph).
  `widget_catalog.md`: no update required (the new settings section is a
  private in-file widget, not a catalogued reusable one).

## Feedback

Iteration 1 review (2026-07-20) returned three blocking items and two loose
ends. All five are now resolved; the resolutions are recorded against the
original findings.

### F-1 — RESOLVED: surface decision made, plan amended

Review question: AC 3 required imported body weight to "appear in Stats", but
Stats has no measurement surface at all.

Product owner's decision: **no Stats changes.** Body weight is already logged
and displayed on Profile, so that is where imported samples belong.

What changed: AC 3 and S-004 now name the Profile measurement history and weight
display, each carrying an explicit amendment note so the original wording stays
visible rather than being silently rewritten. No UI was added.

### F-2 — RESOLVED: documentation corrected

- `docs/theme_and_settings.md` — the "four surfaced sections" count is gone; the
  document now points at the Settings section test instead of enumerating
  labels, and the section list names platform-health sync.
- `docs/theme_and_settings.md` — the false "limited to …" enumeration is
  replaced by the invariant that survives (no account-management rows) plus the
  denied-state contract.
- `docs/state_management/app_state.md` — the two private-field rows are removed;
  the getter/setter rows added alongside already carry the structure.
- `docs/profile_and_measurements.md` — now states that measurement rows can also
  arrive from the platform store, and that an imported row is an ordinary
  `BodyMeasurementEntry` in canonical kilograms with a deterministic id.
- `docs/constants_reference.md` — the health vocabulary is now indexed
  (`HealthPrefs`, `HealthToggleState`, `HealthActivityKind`, the state
  serialization pair).

### F-3 — RESOLVED: test gaps closed

- The foreground trigger now has end-to-end coverage. `main.dart` exposes
  `createHealthLifecycleListener` and `syncHealthBodyWeight` (both
  `@visibleForTesting`); the new `foreground trigger` group builds the listener
  the way the app does, drives a background → foreground cycle, and asserts the
  import landed in the measurement history and the Profile view. Verified to
  fail when the listener's `onResume` is stubbed out, then pass again.
- The two health toggles carry widget keys (`healthWriteToggleKey`,
  `healthReadToggleKey`). The tests target them by key — the
  "first switch in the list" and "exactly two switches" assertions are gone, so
  the checks no longer depend on which lazy rows happen to be built.

### F-4 — RESOLVED: generic type confirmed intentional

Product owner's decision: keep the generic workout type. A session records a
modality (`cardio_endurance`), not a discipline, so the app cannot tell a run
from a ride and does not claim to. The rationale is documented on
`pluginActivityTypeFor`.

### F-5 — RESOLVED: cleanup done

- `HealthWorkoutDraft.duration` removed (unused).
- `HealthSyncService` no longer imports or mutates state. Toggle state arrives as
  `isWriteEnabled` / `isReadEnabled` callbacks, and `syncOnForeground` returns
  the rows it imported instead of pushing them into `ProfileState`. The caller
  owns the refresh, so the service now depends only on the repository interface
  and the platform gateway — correct for the lowest layer.

### Iteration 1 validation — 2026-07-20

Re-checked against the working tree rather than the handoff summary. Everything
this plan owns is present and green.

**Deliverables present** — 7 health source files, `health_constants.dart`,
`Runner.entitlements`, the 2 spec-named test files, plus the amended docs. All
accounted for.

**Green in isolation:**

| Check | Result |
|---|---|
| `test/health_platform_test.dart` + `test/health_platform_mapper_test.dart` | 35 passed, 0 failed |
| `test/header_standardization_test.dart` + `test/interaction_flow_test.dart` | 119 passed, 0 failed |
| `test/docs_indexing_contract_test.dart` (this plan's doc edits) | passes when the foreign file is absent |

**F-1…F-5 verified in the tree, not just asserted in the write-up:**

- F-1 — AC 3, S-004, the Read-path requirement and the Progress line all name
  Profile; every "Stats" reference corrected; each amendment carries a dated
  note.
- F-2 — `theme_and_settings.md` count gone and now points at the test;
  `app_state.md` field rows gone (getters/setters remain);
  `constants_reference.md` has the Health Sync section;
  `profile_and_measurements.md` documents imported rows.
- F-3 — `healthWriteToggleKey` / `healthReadToggleKey` defined and applied;
  `syncHealthBodyWeight` + `createHealthLifecycleListener` exported and used by
  `main.dart`; foreground-trigger tests present and proven meaningful.
- F-4 — the "app cannot be more specific than the modality" rationale is on
  `pluginActivityTypeFor`; generic type retained per the product call.
- F-5 — `HealthWorkoutDraft.duration` gone; `HealthSyncService` takes
  `isWriteEnabled` / `isReadEnabled` callbacks and no longer imports or mutates
  state.

### Adjacent state — resolved 2026-09-20

**1. `docs-standard-audit-2026-07-30.md` — RESOLVED.** Now at
`.github/agents/plans/docs-standard-audit-2026-07-30.md`, outside the contract's
scan root, so the size / warning-band / link / reachability / walkthrough /
roadmap checks no longer apply to it. `test/docs_indexing_contract_test.dart`
passes 9/9.

It did **not** belong in `docs/` beside `docs-audit-2026-07-26.md`. That sibling
is a completed record of an audit whose corrections were applied; this file
opens with *"Status: PROPOSAL FOR HUMAN REVIEW. Nothing here has been acted on"*
and is an open decision list of 110 numbered items. It also states in its own
header that it lives outside `.github/agents/docs/` deliberately — *"a review
artefact, not reference documentation, and should not be indexed and served to
agents as though it were."* Relocating it into `docs/` would additionally have
failed on size (58,372 B against a 52,429 B warning band, which no exemption
covers) and on the content guards, since its name does not match the
`docs-audit-YYYY-MM-DD.md` freeze pattern while its evidence quotes walkthroughs
and roadmap text.

Repointed as part of the move: its `documentation_standard.md` link (now
`../docs/…`), its line-542 self-reference, and the citations in
`.github/agents/code-reviewer.agent.md` and `.claude/agents/code-reviewer.md`.

**2. The move is pending staging.** `git status` shows `D
.github/agents/docs-standard-audit-2026-07-30.md` plus an untracked
`.github/agents/plans/docs-standard-audit-2026-07-30.md`. This is a rename, not
a deletion — stage both paths together so git records `R`.

**3. Four pipeline agent files are modified** (`code-reviewer.agent.md`,
`conductor.agent.md`, `dba.agent.md`, `developer.agent.md`). Unrelated to this
plan; noted only so they are not mistaken for part of it.

The pre-release gate tests also time out at their 30-second limit when the full
suite runs under load: `pre_release_gate_upload_destination_test.dart`,
`pre_release_gate_notification_and_build_test.dart` and
`pre_release_gate_ios_artifact_test.dart` each rsync the repository into a temp
dir in `setUp` and shell out to `scripts/pre_release_check.sh`. Under parallel
full-suite load the timeout is exceeded and the temp dir is then deleted out
from under a still-running setup (`PathNotFoundException: Deletion failed
…/omnitrain_gate_*/repo`). They pass 28/28 in isolation, and the test file's own
comment records this exact failure mode.

### Verification after the changes

- `flutter test test/health_platform_test.dart` — 27 passed (including the two
  new foreground-trigger tests). Verified the new trigger test is meaningful by
  stubbing `onResume` to a no-op: it fails (`Expected: <1> Actual: <0>`), then
  passes again once restored.
- `flutter analyze` — no new issues; only the pre-existing infos in the touched
  files (`withOpacity` deprecations, an existing `BuildContext` warning, an
  existing `if`-without-braces) remain.
- Docs indexing contract — passes 9/9 with these edits.

### Phase 0 Complete ✓
