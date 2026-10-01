# Crash Reporting — Three Interacting Defects

## Overview

Three defects landed together in the iOS crash-reporting change that
enabled the second reporting-destination fix, and a third was present
since symbol upload was first set up.

**Defect 1 — iOS reporting destination never reaches the app.**
The recent change intended to enable iOS crash reporting supplies the
DSN via `EXTRA_FRONT_END_OPTIONS` on the `xcodebuild` step in
`.github/workflows/release.yml`. The `EXTRA_FRONT_END_OPTIONS`
mechanism is supported by the Flutter Xcode build phase
(`xcode_backend.sh`), but the iOS build invokes `xcodebuild` from a
custom shell script that performs manual-signing setup first. The
mechanism may technically still be available, but its integration with
the manual-signing prologue is fragile and unverified end-to-end —
there is no test that proves the DSN actually compiles into the
produced iOS artifact. The iOS binary ships with whatever the Dart
front-end received, and the iOS Sentry dashboard has been empty.

**Defect 2 — The iOS pre-release check cannot detect Defect 1.**
The §11p / §11q checks added alongside the iOS fix inspect the
workflow file, not the produced artifact. They confirm the workflow
claims the right thing — which is precisely the defect. They pass
today while iOS ships unmonitored.

**Defect 3 — Symbol uploads target projects that do not exist.**
`.github/workflows/release.yml` configures `SENTRY_PROJECT: omnitrain-ios`
in the iOS job and `SENTRY_PROJECT: omnitrain-android` in the Android
job. Only one Sentry project exists in the reporting organisation,
named `omnitrain`. Both platforms' symbol uploads have been arriving
at (and failing against) destinations that do not exist. Android stack
traces have never been readable because the mappings were never
uploaded to a real project. This has been wrong since the upload
plumbing was first set up.

The three defects share the same files (the workflow, the gate
script, and the upload-destination test file). They are fixed
together. Android runtime reporting is unchanged.

## Root-Cause Analysis

### Why `EXTRA_FRONT_END_OPTIONS` did not deliver the DSN end-to-end

The previous fix (commit `d7655c6`, plan
`docs/plans/crash-reporting-ios-destination-plan.md`)
attempted to forward the DSN through `xcodebuild` by setting
`EXTRA_FRONT_END_OPTIONS: --dart-define=SENTRY_DSN=$SENTRY_DSN` on
the iOS build step. The mechanism is documented in the Flutter
source tree (`xcode_backend.sh` reads `EXTRA_FRONT_END_OPTIONS` and
forwards the contained `--dart-define=KEY=VALUE` flags to the Dart
front-end via `--ExtraFrontEndOptions`). It is the supported way to
inject a `--dart-define` through an `xcodebuild` invocation.

The mechanism is technically available regardless of whether the
build is invoked directly via `xcodebuild` or indirectly via
`flutter build ipa`. In practice, however, the existing iOS job
does far more than invoke `xcodebuild`:

- It imports a signing certificate into a temporary keychain.
- It installs a provisioning profile.
- It uses `PlistBuddy` to set the development team.
- It invokes `xcodebuild` with manual-signing parameters
  (`CODE_SIGN_STYLE=Manual`, `DEVELOPMENT_TEAM=...`,
   `PROVISIONING_PROFILE_SPECIFIER=...`).
- It then invokes `xcodebuild -exportArchive` against
  `ios/ExportOptions.plist`.

The `EXTRA_FRONT_END_OPTIONS` mechanism relies on the Flutter
Xcode build phase reading the variable from the environment the
Dart compiler inherits. Whether the variable actually survives the
PlistBuddy edit, the manual-signing configuration, and the
two-stage `xcodebuild` (archive + exportArchive) invocation is not
tested. The empty-DSN runtime guard added in
`crash_reporting_service.dart` made this defect silent rather than
loud. There is no unit test that proves the DSN is compiled into
the produced iOS artifact — the §11p / §11q checks only inspect the
workflow file, and they would have passed even if `EXTRA_FRONT_END_OPTIONS`
were silently dropped by `xcodebuild` or by `xcode_backend.sh`.

### Why switching to `flutter build ipa` is the cleaner fix

`flutter build ipa` is the supported, end-to-end build invocation
that produces a signed, archived IPA ready for TestFlight or App
Store distribution. It invokes `xcodebuild` internally with the
arguments Flutter knows to be correct, including the propagation of
`--dart-define` flags to the Dart front-end. The build phase that
the `sentry_dart_plugin` installs is also run by `flutter build ipa`,
so dSYM and ProGuard mapping uploads continue to work.

The trade-off is that `flutter build ipa` wants to drive signing
itself: it reads `ExportOptions.plist`, accepts `--export-options-plist`,
and resolves the signing identity from the keychain. The current
manual-signing prologue (cert import + profile install + PlistBuddy
edit + `DEVELOPMENT_TEAM=` etc.) is unnecessary when `flutter build
ipa` is used. Two reasonable configurations:

- **(a) Use `flutter build ipa` for the whole iOS build.**
  Drop the cert-import / profile-install / PlistBuddy steps; pass
  `--export-options-plist=ios/ExportOptions.plist` and let
  `flutter build ipa` resolve the signing identity from the keychain.
  This is the cleaner change. It removes ~15 lines of bespoke
  shell that duplicates what the tooling already does. Signing
  continues to work — `ExportOptions.plist` declares the
  distribution method and the development team is set in the Xcode
  project (`productBundleIdentifier`, `DEVELOPMENT_TEAM`).
  Trade-off: the workflow loses the explicit per-step logging of
  the manual-signing setup. Anyone reading the workflow now sees
  the standard Flutter invocation.
- **(b) Keep the manual `xcodebuild` invocation and try a
  different DSN-forwarding mechanism.** This is strictly worse
  than (a): we already have one mechanism that is unverified
  end-to-end, adding a second does not reduce the uncertainty.
  Rejected.

This change **adopts (a)**. The implications:

- The `Import signing certificate`, `Install provisioning profile`,
  and `PlistBuddy` lines are no longer needed — `flutter build ipa`
  reads the signing certificate from the default keychain and the
  provisioning profile from the standard location
  (`~/Library/MobileDevice/Provisioning Profiles/`). The cert-import
  prologue can stay as a convenience for any signing step
  `flutter build ipa` performs internally; the `flutter-action@v2`
  step already handles this for the certificate it manages.
  Concretely, we keep the cert-import + profile-install steps
  (they are still required because the GitHub-Actions keychain
  is temporary and the provisioning profile is not at the standard
  location), and drop the `PlistBuddy` edit and the bespoke
  `DEVELOPMENT_TEAM=` / `CODE_SIGN_STYLE=Manual` arguments.
- The archive + exportArchive split collapses into a single
  `flutter build ipa --export-options-plist=ios/ExportOptions.plist`
  invocation. The artifact path changes from
  `$RUNNER_TEMP/Runner.xcarchive + $RUNNER_TEMP/ipa/*.ipa` to
  `build/ios/ipa/*.ipa` (Flutter's default), and the
  `actions/upload-artifact` step's `path:` is updated.
- The iOS build still produces an IPA; symbol upload via
  `sentry_dart_plugin` still runs because the plugin's build phase
  is invoked by `flutter build` for iOS dSYMs (the
  `upload_sources: true` and `upload_native_symbols: true`
  flags in `pubspec.yaml`'s `sentry_dart_plugin` block remain).
- The `EXTRA_FRONT_END_OPTIONS` line is no longer needed. The DSN
  reaches the Dart front-end through `--dart-define=SENTRY_DSN=$SENTRY_DSN`.

### Why symbol uploads land at non-existent destinations

`SENTRY_PROJECT: omnitrain-ios` and `SENTRY_PROJECT: omnitrain-android`
were chosen when symbol upload was first wired up under the
assumption that two separate Sentry projects existed. The pubspec.yaml
comment block at the time explicitly hedged this as
"assuming two Sentry projects". Only one project exists (`omnitrain`),
so both uploads have been silently failing. The pre-release gate
(§11n / §11o) caught the case where the env var is missing or
empty — it did not catch the case where the env var names a
non-existent project.

## Requirements

- **R1**: iOS release artifacts produced by the pipeline contain the
  real `SENTRY_DSN` value compiled into the binary. Verified by
  inspecting the produced artifact (the IPA, looking for the DSN
  string in the App binary or App.framework), not the workflow
  file.
- **R2**: The iOS build switches from the bespoke `xcodebuild`
  invocation to `flutter build ipa` so `--dart-define=SENTRY_DSN`
  flows through the supported mechanism. Signing and archiving
  still succeed; the change is called out in the plan and the
  commit message, not folded in silently.
- **R3**: The pre-release gate fails when an iOS artifact would
  ship without a working reporting destination. The check inspects
  the produced artifact, not the workflow file, and produces a
  message that names the user-facing consequence.
- **R4**: Both platforms' `SENTRY_PROJECT` env var is set to
  `omnitrain` (the single existing project). The
  `Sentry Android Gradle plugin` and the `sentry_dart_plugin`
  iOS build phase both upload to that single project.
- **R5**: The pre-release gate fails if either platform's
  `SENTRY_PROJECT` names anything other than `omnitrain`. A future
  agent who reintroduces per-platform destinations fails the gate.
- **R6**: No code comment in the workflow, the gate, or the
  pubspec.yaml `sentry_dart_plugin` block describes the
  two-project arrangement. Comments that hedged the assumption
  are removed, not corrected.
- **R7**: Android runtime reporting behaviour is unchanged. The
  existing `test/crash_reporting_test.dart` tests continue to pass.
- **R8**: Debug and profile builds still report nothing.
- **R9**: The `sentry_dart_plugin` iOS build phase continues to run
  under `flutter build ipa` so dSYMs and ProGuard mappings are
  uploaded. The build itself remains the source of truth for
  whether this happens.
- **R10**: The single Sentry project receives a fresh Android crash
  report with readable class and method names (verified by
  inspection of the Sentry dashboard, not by an automated test —
  the test environment cannot trigger a real Sentry upload).

## Acceptance Criteria

- [ ] An iOS release artifact produced by the pipeline contains the
      real `SENTRY_DSN` value, verified by inspecting the built
      artifact (the `Runner.app/Runner` binary's data section, or
      `App.framework/App` for Flutter on iOS), and not the
      workflow file.
- [ ] The iOS build invocation in `.github/workflows/release.yml`
      uses `flutter build ipa` so `--dart-define=SENTRY_DSN=$SENTRY_DSN`
      flows through the supported mechanism. Signing and archiving
      continue to succeed; the change is called out explicitly in
      the commit.
- [ ] The pre-release gate fails when the iOS artifact would ship
      without a working reporting destination — verified by
      inspecting the produced IPA, not the workflow file. There is
      no branch that passes on workflow-file contents alone.
- [ ] The replacement iOS check is demonstrated failing against an
      artifact built without the DSN (the test injects a workflow
      mutation that causes `flutter build ipa` to omit the
      `--dart-define=SENTRY_DSN=...` flag and confirms the gate
      fails against the resulting IPA).
- [ ] The pre-release gate passes when the iOS artifact contains
      the DSN.
- [ ] Both platforms' `SENTRY_PROJECT` env var is set to
      `omnitrain`, confirmed by reading
      `.github/workflows/release.yml`.
- [ ] The pre-release gate fails when either platform's
      `SENTRY_PROJECT` names anything other than `omnitrain`. A
      future agent who re-introduces per-platform destinations
      fails the gate.
- [ ] The Android runtime reporting behaviour is unchanged: the
      existing `test/crash_reporting_test.dart` tests continue to
      pass without modification. The Android release build still
      reports after the change (verified by inspection, not by an
      automated test).
- [ ] No code comment in `.github/workflows/release.yml`,
      `scripts/pre_release_check.sh`, or `pubspec.yaml`'s
      `sentry_dart_plugin` block describes the two-project
      arrangement. The pubspec.yaml comment block that hedged the
      assumption as "(assuming two Sentry projects)" is removed,
      not corrected.
- [ ] The iOS build invocation change does not silently regress
      signing or archiving. The plan and the commit message call
      out the change explicitly.

## Scenarios

### S-001: iOS pre-release gate fails when the produced IPA does not contain the DSN
- Trigger: A future regression causes `flutter build ipa` to omit
  the `--dart-define=SENTRY_DSN=...` flag (e.g. an env-var
  resolution bug, a typo, or a `--dart-define` removed by an
  agent during a refactor).
- Precondition: `.github/workflows/release.yml` is committed;
  `flutter build ipa` ran successfully; an IPA exists at the
  configured output path.
- Flow: Pre-release gate extracts the IPA (an `unzip` step), reads
  the produced `Runner.app/Runner` binary (or, for Flutter-built
  apps, the `App.framework/App` binary), and greps for the DSN
  value. If the DSN is not present in the binary, the gate fails
  with a message naming the user-facing consequence.
- Expected outcome: Gate exits 1; the message names iOS, the
  reporting destination, and the consequence ("the iOS artifact
  would ship with no reporting destination and silently never
  report — iOS would appear monitored in the dashboard but
  produce nothing").
- Edge case of: none

### S-002: iOS pre-release gate passes when the produced IPA contains the DSN
- Trigger: Post-fix state — the workflow's `flutter build ipa`
  invocation includes
  `--dart-define=SENTRY_DSN=$SENTRY_DSN` and the build completes.
- Precondition: Workflow committed, IPA produced.
- Flow: Gate extracts the IPA, reads the binary, greps for the
  DSN; DSN present; gate passes.
- Expected outcome: Gate exits 0 (modulo other unrelated checks).
- Edge case of: S-001

### S-003: iOS pre-release gate fails when the produced IPA contains a placeholder rather than the real DSN
- Trigger: An agent changes the workflow to use a placeholder DSN
  (e.g. `--dart-define=SENTRY_DSN=https://placeholder@sentry/0`)
  instead of `$SENTRY_DSN`.
- Precondition: Workflow committed; IPA produced.
- Flow: Gate extracts the IPA, reads the binary, greps for the
  DSN value; placeholder present; gate fails because the literal
  `placeholder` value is not a real DSN (the check does not
  attempt to validate the DSN format, but a separate check
  inspects the binary for the literal `--dart-define=SENTRY_DSN=`
  substitution path — if the binary contains the literal env
  reference `$SENTRY_DSN` rather than the resolved value, the
  gate fails; this catches a different class of regression where
  the shell substituted an empty value).
- Expected outcome: Gate exits 1.
- Edge case of: S-001

### S-004: Symbol-upload destination must be `omnitrain` (Android)
- Trigger: A future agent changes the Android job's
  `SENTRY_PROJECT` to anything other than `omnitrain` (e.g.
  `omnitrain-android`, an empty string, or a placeholder).
- Precondition: `.github/workflows/release.yml` is committed.
- Flow: Pre-release gate extracts the Android job's
  `SENTRY_PROJECT` value; asserts the value is exactly
  `omnitrain` (whitespace-tolerant, case-sensitive). Fails
  otherwise.
- Expected outcome: Gate exits 1; the failure message names the
  platform and the correct value (`omnitrain`) so the reader
  knows what to type.
- Edge case of: none

### S-005: Symbol-upload destination must be `omnitrain` (iOS)
- Trigger: Same as S-004 but for the iOS job.
- Precondition: `.github/workflows/release.yml` is committed.
- Flow: Gate extracts the iOS job's `SENTRY_PROJECT` value;
  asserts the value is exactly `omnitrain`. Fails otherwise.
- Expected outcome: Gate exits 1; the failure message names the
  iOS platform and the correct value.
- Edge case of: none

### S-006: Pre-release gate does not depend on per-platform destinations
- Trigger: A future agent tries to re-introduce per-platform
  destinations (`omnitrain-ios`, `omnitrain-android`).
- Precondition: Workflow committed.
- Flow: S-004 and S-005 already fail on those values. The
  combined S-006 asserts that the upload-destination shape as a
  whole does not regress to per-platform — i.e. that the gate
  fails when either value matches a known per-platform
  placeholder.
- Expected outcome: Gate exits 1.
- Edge case of: S-004, S-005

### S-007: iOS build invocation uses `flutter build ipa` (not raw `xcodebuild`)
- Trigger: A future agent reverts the iOS build back to the
  bespoke `xcodebuild` invocation.
- Precondition: Workflow committed.
- Flow: Gate greps the iOS job's `run:` block for
  `flutter build ipa`. Fails if absent.
- Expected outcome: Gate exits 1; the failure message names the
  consequence (the DSN will not be compiled into the iOS
  binary because the bespoke `xcodebuild` invocation does not
  have a verified `--dart-define`-forwarding path).
- Edge case of: S-001

### S-008: §11n / §11o extensions assert `SENTRY_PROJECT == omnitrain`
- Trigger: Same as S-004 / S-005 but the assertion text matches
  what the previous gate's §11n / §11o checks produced (a
  destination unresolvable failure message). After the change,
  the existing §11n / §11o messages are replaced with versions
  that quote the actual project name expected.
- Precondition: Workflow committed; gate script updated.
- Flow: The replacement §11n message names `omnitrain` as the
  expected value and fails when the value differs. The
  replacement §11o message does the same for the iOS job.
- Expected outcome: Gate exits 1 when the value differs from
  `omnitrain`.
- Edge case of: S-004, S-005

### S-009: Existing crash-reporting gate section still fails as a whole when any single invariant fails
- Trigger: One of §11k–§11q (the existing crash-reporting
  section) or the new §11iOS / §11n-ext / §11o-ext checks
  fails; every other check passes.
- Precondition: Workflow has a single defect.
- Flow: Gate runs every check; one fails; `errors` is incremented;
  final summary says "1 blocking error(s) found" and the script
  exits 1.
- Expected outcome: Script exits non-zero.
- Edge case of: S-001, S-004, S-005, S-007, S-008

## Iteration 1

### DB Changes
None.

### Backend Changes

1. **`.github/workflows/release.yml`** — iOS job, "Build IPA
   (manual signing)" step:

   - Rename the step to "Build IPA with Sentry baked in".
   - Remove the `PlistBuddy` line (the dev team is set in
     `project.pbxproj`).
   - Replace the `xcodebuild ... archive` + `xcodebuild
     -exportArchive` two-step invocation with a single
     `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist --dart-define=SENTRY_DSN=$SENTRY_DSN`
     invocation. Drop the bespoke `CODE_SIGN_STYLE=Manual`,
     `DEVELOPMENT_TEAM=`, `CODE_SIGN_IDENTITY=`, and
     `PROVISIONING_PROFILE_SPECIFIER=` arguments — `flutter build
     ipa` resolves signing from the keychain and
     `ExportOptions.plist`.
   - Drop `EXTRA_FRONT_END_OPTIONS` (the `--dart-define` flows
     through the supported `flutter build` path now).
   - Keep the cert-import and profile-install steps (they make
     the certificate and profile available to the keychain that
     `flutter build ipa` will use).
   - Update the `actions/upload-artifact` step's `path:` to
     `build/ios/ipa/*.ipa` (the canonical `flutter build ipa`
     output path).
   - Change `SENTRY_PROJECT: omnitrain-ios` to
     `SENTRY_PROJECT: omnitrain` and update the explanatory
     comment block to state that both platforms upload to the
     single `omnitrain` project.

2. **`.github/workflows/release.yml`** — Android job,
   "Build AAB with Sentry baked in" step:

   - Change `SENTRY_PROJECT: omnitrain-android` to
     `SENTRY_PROJECT: omnitrain`.
   - Update the comment block above the build step to remove
     the "(assuming two Sentry projects)" language. The comment
     now states that both platforms upload to `omnitrain`.

3. **`scripts/pre_release_check.sh`** — three changes:

   - **Replace §11p** (iOS DSN in env block): removed.
   - **Replace §11q** (iOS DSN forwarded to xcodebuild): removed.
   - **Add §11p (new)** — iOS build invocation shape. Asserts
     the iOS job's `run:` block contains `flutter build ipa`.
     Fails if absent. Demonstrates that the iOS build uses the
     tooling-driven path.
   - **Add §11q (new)** — iOS reporting destination reaches
     the artifact. Runs against the produced iOS IPA at
     `build/ios/ipa/*.ipa`. Extracts the IPA, reads the binary
     in `Runner.app/Runner` (or the App binary inside
     `Runner.app/`), and greps for the literal DSN string. The
     gate builds a fake iOS artifact via a test-only hook
     (`PRE_RELEASE_GATE_FAKE_IP_BUILD`) mirroring the
     `PRE_RELEASE_GATE_FAKE_BUILD` Android hook used by §11s.
     In live (non-test) mode, if the iOS build was not run (no
     IPA on disk), the gate fails (refusing to pass by default
     — the same rule §11s enforces for Android). The check
     inspects the artifact, not the workflow file.
   - **Replace §11n** (Android upload destination): the existing
     check verifies the env var is set; the replacement
     asserts the value is exactly `omnitrain`. Fails
     otherwise. Failure message names the correct value.
   - **Replace §11o** (iOS upload destination): same as §11n
     for the iOS job.

4. **`pubspec.yaml`** — `sentry_dart_plugin` block comment:

   - Remove the line "Set the following in your release
     environment (`.xcode.env`, `android/local.properties`,
     or your CI secret store): ... `SENTRY_PROJECT=omnitrain-ios`
     (and `...-android` for Android)".
   - Replace with: "`SENTRY_PROJECT=omnitrain` (single project;
     both iOS and Android symbol uploads land here)".

5. **`test/pre_release_gate_upload_destination_test.dart`** —
   update and add tests:

   - **Remove** the existing S-001 iOS DSN-in-env-but-not-used
     test — that test was a regression test for the previous
     defect, and the underlying check (§11p / §11q) is being
     replaced with an artifact-inspection check.
   - **Remove** the existing S-002 iOS DSN-removed-from-env
     test — same reason.
   - **Add** an artifact-inspection green-path test: invokes
     the gate with a fake iOS IPA whose binary contains the
     DSN string; asserts the gate exits 0 and that §11q
     announces the success.
   - **Add** an artifact-inspection red-path test: invokes the
     gate with a fake iOS IPA whose binary does NOT contain
     the DSN string; asserts the gate exits 1 and the failure
     message names iOS and the consequence.
   - **Add** an iOS-build-invocation test: mutates the workflow
     to revert from `flutter build ipa` back to the bespoke
     `xcodebuild` invocation; asserts the gate exits 1.
   - **Add** a §11n-extension test: mutates the Android
     `SENTRY_PROJECT` to `omnitrain-android`; asserts the gate
     exits 1 with a message naming the correct value.
   - **Add** a §11o-extension test: same for the iOS job.
   - **Update** the existing happy-path test to confirm the
     post-fix state of the live workflow (no per-platform
     destinations, `flutter build ipa` present, DSN env-var
     present) does not fire any of the new checks.

### Frontend Changes
None.

### Implementation Steps

1. Write failing Dart tests for S-001, S-002, S-004, S-005,
   S-006, S-007, S-008 (green and red paths). Create a new
   test file `test/pre_release_gate_ios_artifact_test.dart`
   for the iOS artifact-inspection scenarios; add the §11n /
   §11o extension tests to the existing
   `test/pre_release_gate_upload_destination_test.dart`.
2. Run the new tests — confirm red against the unmodified repo.
3. Update `.github/workflows/release.yml`:
   - iOS: switch to `flutter build ipa`; change `SENTRY_PROJECT`
     to `omnitrain`.
   - Android: change `SENTRY_PROJECT` to `omnitrain`.
   - Update comment blocks in both jobs.
4. Update `pubspec.yaml` `sentry_dart_plugin` comment block.
5. Update `scripts/pre_release_check.sh`:
   - Remove §11p / §11q (old).
   - Add §11p (new) — `flutter build ipa` invocation check.
   - Add §11q (new) — iOS artifact-inspection check.
   - Replace §11n / §11o with strict `omnitrain` value checks.
6. Remove the obsolete S-001 / S-002 iOS tests from
   `test/pre_release_gate_upload_destination_test.dart`.
7. Re-run the new tests — confirm green.
8. Run `flutter test` — confirm no other tests regressed.
9. Run `flutter analyze` — confirm clean.
10. Run `bash scripts/pre_release_check.sh --fast` against the
    live repo — confirm all §11* checks pass with the fix in
    place.

## Progress

- [x] Phase 0: Plan authored
- [x] Phase 2.5: Red tests written and confirmed failing
- [x] Phase 2: Implementation (workflow + pubspec + script + tests)
- [x] Phase 2: Green tests confirmed
- [x] Phase 3: Code review

## Feedback

## Assumption Log

- **Switching to `flutter build ipa` is the cleaner fix (R2)**.
  The previous mechanism (`EXTRA_FRONT_END_OPTIONS` on
  `xcodebuild`) is technically supported, but its end-to-end
  behaviour is not verified by any automated test and the
  bespoke manual-signing prologue makes the integration
  fragile. `flutter build ipa` is the supported, end-to-end
  invocation that produces a signed IPA. The trade-off is that
  the workflow loses the explicit per-step logging of the
  manual-signing setup; in exchange, every
  `--dart-define`-forwarding path is now standard.
- **Single Sentry project is `omnitrain` (R4)**. The previous
  workflow and pubspec.yaml both hedged this assumption as
  "assuming two Sentry projects". The defect itself
  demonstrates the assumption was wrong: symbol uploads have
  been arriving at non-existent destinations for the lifetime
  of the integration. The user has confirmed that only one
  project exists and it is named `omnitrain`.
- **The `sentry_dart_plugin` iOS build phase continues to run
  under `flutter build ipa`**. The plugin's iOS build phase is
  added at `flutter pub get` time and is invoked by any
  `flutter build` invocation that drives an Xcode archive. The
  `--export-options-plist` flag does not suppress the phase.
  Verified by reading the plugin's source tree (out of scope
  for this plan); the build itself is the source of truth.
- **iOS IPA contains the DSN at a known binary location**. The
  `--dart-define=SENTRY_DSN=...` value is compiled into the
  Dart front-end's output as a string constant. The string
  lives in the `App.framework/App` (Flutter on iOS) or
  `Runner.app/Runner` (legacy Xcode build) binary's data
  section. A simple `strings`-equivalent grep over the binary
  finds the DSN. The check accepts any of the canonical
  binary paths.
- **Test-only iOS build hook (`PRE_RELEASE_GATE_FAKE_IP_BUILD`)**.
  The Android build is faked via `PRE_RELEASE_GATE_FAKE_BUILD`;
  iOS uses a parallel `PRE_RELEASE_GATE_FAKE_IP_BUILD` hook so
  tests can inject a fake IPA without paying the minute-long
  Flutter build cost on every CI run. The hook is documented as
  test-only.
- **iOS pre-release check inspects the artifact, not the
  workflow file**. The previous §11p / §11q checks inspected
  workflow text and passed today while iOS shipped
  unmonitored. The replacement checks inspect the produced IPA
  (the same approach §11r uses for Android notifications).
- **`SENTRY_PROJECT` value is checked exactly (case-sensitive,
  whitespace-trimmed)**. The check is strict on purpose —
  `omnitrain-android` was a real regression that
  previously passed the gate. A whitespace-tolerant equality
  check (`omn itrain`) would not catch the real bug.

### Phase 0 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓