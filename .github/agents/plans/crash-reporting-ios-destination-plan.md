# Crash Reporting — iOS Reporting Destination Live

## Overview

Crash reporting has never been active on iOS, despite the release pipeline
appearing to configure it. The iOS build step in
`.github/workflows/release.yml` declares `SENTRY_DSN` (and the three
upload-side values) in its `env:` block, but the iOS step invokes
`xcodebuild` directly rather than `flutter build`. `xcodebuild` does not
forward arbitrary environment variables to `flutter assemble` as
dart-defines. The Dart front-end therefore sees `SENTRY_DSN` as the empty
default at runtime (`String.fromEnvironment('SENTRY_DSN', defaultValue: '')`
in `lib/main.dart:147`), and `SentryCrashReporter.init` initializes the
SDK against an empty DSN — which the SDK rejects silently. Reports never
reach Sentry. The wrapper's "continue without complaint when no destination"
behaviour (correct, must be preserved) is exactly why this stayed invisible:
a broken iOS setup and a working one look identical from outside.

The Android path is structurally different: the Android step calls
`flutter build appbundle --release --dart-define=SENTRY_DSN=$SENTRY_DSN`,
which bakes the DSN into the Android binary at compile time. Copying that
line into the iOS step does not address the actual gap, because the iOS
step does not call `flutter build` at all — it calls `xcodebuild`. The
gap on iOS is the missing mechanism that gets the DSN from the build
environment into the compiled Dart code.

## Root Cause Analysis

The two paths differ in two distinct ways; both are load-bearing:

1. **Build command**: Android uses `flutter build appbundle --release
   --dart-define=SENTRY_DSN=$SENTRY_DSN`. iOS uses
   `xcodebuild ... archive` with no Flutter invocation.
2. **Compile-time injection**: `flutter build --dart-define=KEY=VALUE`
   compiles the value into the binary. `xcodebuild` does not consume
   `--dart-define` flags; it consumes Xcode build settings and a
   different set of environment variables.

The mechanism that does work for iOS is the `EXTRA_FRONT_END_OPTIONS`
environment variable, which the Flutter Xcode build phase (`xcode_backend.sh`)
reads and forwards to the Dart front-end. This is the supported way to
inject dart-defines through an `xcodebuild` invocation. Setting
`EXTRA_FRONT_END_OPTIONS: --dart-define=SENTRY_DSN=$SENTRY_DSN` on the
xcodebuild step resolves the gap without restructuring the existing
manual-signing pipeline.

## Requirements

- iOS release builds must ship with the Sentry DSN compiled into the
  binary at build time, matching the Android path.
- The existing `flutter build` invocation pattern is not adopted wholesale
  on iOS — that would discard the manual-signing configuration that the
  pipeline relies on. The fix uses `EXTRA_FRONT_END_OPTIONS` because it
  addresses the actual gap (DSN injection through xcodebuild) without
  restructuring the rest of the build.
- `SentryCrashReporter.init` must explicitly detect an empty DSN at
  runtime and disable itself quietly, with a debug-log line that
  distinguishes the empty-DSN failure mode from the deliberately
  disabled (debug/profile) mode. This is defensive — if the gate ever
  fails to catch a regression, the runtime still reports a diagnosable
  condition rather than silently dropping events.
- The pre-release gate fails when an iOS artifact would ship without a
  working reporting destination, with a message that names the
  user-facing consequence ("iOS crash reports would silently never
  reach Sentry, and the absence of iOS crashes would read as the
  absence of iOS crashes rather than the absence of reporting").
- Debug and profile builds still report nothing and install no
  reporting handlers.
- Startup never blocks or fails because of reporting.
- The set of collected fields is unchanged.
- Android reporting is unchanged. Verified by the existing tests in
  `test/crash_reporting_test.dart` continuing to pass.

## Acceptance Criteria

- [x] The iOS build step in `.github/workflows/release.yml` forwards
      `SENTRY_DSN` into the xcodebuild invocation via
      `EXTRA_FRONT_END_OPTIONS`, so the value is compiled into the
      iOS binary.
- [x] The pre-release gate fails (non-zero exit) when the iOS build
      step has `SENTRY_DSN` in its env block but does not reference it
      in the build command — i.e. when the iOS artifact would ship
      without a reporting destination.
- [x] The pre-release gate passes when `SENTRY_DSN` is present in the
      iOS env block AND is referenced in the build command.
- [x] `SentryCrashReporter.init` detects an empty DSN at runtime and
      disables itself with a debug-log line that distinguishes the
      empty-DSN failure mode from the deliberately disabled
      (debug/profile) mode.
- [x] `bootstrap(enabled: true, ...)` with a reporter constructed
      against an empty DSN does not throw, completes startup, and
      installs no error sinks (or installs them but routes nothing to
      a live destination).
- [x] Debug and profile builds still report nothing.
- [x] Android reporting is unchanged: the existing
      `test/crash_reporting_test.dart` tests continue to pass without
      modification.

## Scenarios

### S-001: Pre-release gate fails when iOS DSN is in env but unused in build command
- Trigger: A future agent removes the `EXTRA_FRONT_END_OPTIONS` line
  (or any equivalent `SENTRY_DSN` reference) from the iOS build step,
  leaving `SENTRY_DSN` only in the env block.
- Precondition: `.github/workflows/release.yml` is committed.
- Flow: Pre-release gate greps the iOS job's body for any reference to
  `SENTRY_DSN` outside the env: block. If none found, the gate fails
  with a plain message naming the consequence.
- Expected outcome: Gate exits 1; the message names the iOS platform
  and the consequence ("the iOS artifact would ship with no reporting
  destination and would silently never report").
- Edge case of: none

### S-002: Pre-release gate fails when iOS DSN is not in env block
- Trigger: A future agent removes `SENTRY_DSN` from the iOS job's env
  block entirely (e.g. during a secret rotation).
- Precondition: `.github/workflows/release.yml` is committed.
- Flow: Pre-release gate greps the iOS job's env: block for
  `SENTRY_DSN:` and fails if missing.
- Expected outcome: Gate exits 1.
- Edge case of: none

### S-003: Pre-release gate passes when iOS DSN is in env AND used
- Trigger: The post-fix state — `SENTRY_DSN` in env block,
  `EXTRA_FRONT_END_OPTIONS=--dart-define=SENTRY_DSN=$SENTRY_DSN` in the
  build command.
- Precondition: `.github/workflows/release.yml` is committed.
- Flow: Pre-release gate verifies both conditions; both hold; gate
  passes.
- Expected outcome: Gate exits 0 (modulo other unrelated checks).
- Edge case of: none

### S-004: SentryCrashReporter detects empty DSN and disables with diagnosable log
- Trigger: `SentryCrashReporter` is constructed with an empty DSN;
  `init(enabled: true, metadata: ...)` is called (the bootstrap path).
- Precondition: Service has not been previously initialized.
- Flow: `init` checks for empty DSN before calling `SentryFlutter.init`;
  detects the empty DSN; sets `_enabled = false`; emits a debugPrint
  line that names the cause and is distinguishable from the
  kReleaseMode-gated disable message.
- Expected outcome: `init` returns without throwing; `isEnabled` is
  false; the debug log contains the empty-DSN-specific phrase.
- Edge case of: none

### S-005: CrashReportingService.bootstrap completes with empty DSN
- Trigger: `bootstrap(reporter: SentryCrashReporter(dsn: ''), enabled: true, ...)`
  is awaited from a startup path.
- Precondition: Service is fresh.
- Flow: `bootstrap` constructs the service, calls `reporter.init`,
  which detects the empty DSN and disables itself; bootstrap then
  proceeds to install error sinks (since `enabled: true` was passed
  at the call site).
- Expected outcome: `bootstrap` returns without throwing; the
  reporter's `isEnabled` is false; any subsequent `recordError` call
  is a no-op because the reporter is disabled; `FlutterError.onError`
  is installed (so framework errors are routed through the wrapper,
  which then short-circuits to a no-op) rather than crashing.
- Edge case of: S-004

### S-006: Group-wide gate semantics preserved
- Trigger: A single invariant in the gate fails (e.g. the new §11p
  fails while every other §11 check passes).
- Precondition: Workflow file has a single defect.
- Flow: Gate runs §11a–§11p; one fails; `errors` is incremented;
  final summary line says "1 blocking error(s) found" and the script
  exits 1.
- Expected outcome: Script exits non-zero; the failure is summarized
  at the bottom of the output. Verified by the existing happy-path
  test plus the new failure-path tests collectively.
- Edge case of: S-001, S-002

## Iteration 1

### DB Changes
None.

### Backend Changes

1. **`.github/workflows/release.yml`** — iOS job, "Build IPA (manual
   signing)" step:
   - Add an `EXTRA_FRONT_END_OPTIONS` env var set to
     `--dart-define=SENTRY_DSN=$SENTRY_DSN`. This is the supported
     mechanism that the Flutter Xcode build phase (`xcode_backend.sh`)
     reads and forwards to the Dart front-end, so the DSN is compiled
     into the iOS binary. Keep the existing manual-signing
     configuration unchanged.

2. **`lib/core/services/crash_reporting_service.dart`** —
   `SentryCrashReporter.init`:
   - After the existing `!enabled || kIsWeb` guard, add a guard for
     `dsn.isEmpty`. When the DSN is empty, set `_enabled = false`,
     emit a single `debugPrint` line that names the cause and
     distinguishes it from the kReleaseMode-gated disable, and return
     without calling `SentryFlutter.init`. This is defensive: the
     pre-release gate (added in 3) is the primary defense, but if a
     future regression slips past the gate (e.g. a workflow-file
     change that the gate does not yet cover), the runtime still
     surfaces a diagnosable condition rather than silently dropping
     events.

3. **`scripts/pre_release_check.sh`** — three new checks:
   - **§11p**: iOS job must have `SENTRY_DSN:` in its env block. If
     missing, fail with a message naming the iOS platform and the
     consequence.
   - **§11q**: iOS job's build command must reference `SENTRY_DSN`
     outside the env: block (e.g. via `EXTRA_FRONT_END_OPTIONS`). If
     no reference exists, fail with a message that names the
     consequence in plain terms ("iOS crash reports would silently
     never reach Sentry").
   - These checks use `awk` to isolate the iOS job body (same
     pattern as §11o) so they are robust against future additions of
     other jobs.

### Frontend Changes
None.

### Implementation Steps
1. Write failing tests for S-001..S-005 (the five scenarios above).
   Two test files: the gate tests in
   `test/pre_release_gate_upload_destination_test.dart` (already
   houses related checks), the runtime tests in
   `test/crash_reporting_test.dart` (existing service-test file).
2. Update `scripts/pre_release_check.sh` with §11p and §11q.
3. Update `.github/workflows/release.yml` with the
   `EXTRA_FRONT_END_OPTIONS` env var.
4. Update `lib/core/services/crash_reporting_service.dart` with the
   empty-DSN guard and the diagnostic debugPrint.
5. Re-run the new gate tests — confirm green.
6. Re-run `test/crash_reporting_test.dart` — confirm green; confirm
   no other tests regressed.
7. Run `flutter analyze` — confirm clean.
8. Run `bash scripts/pre_release_check.sh --fast` against the live
   repo — confirm §11p and §11q pass.

## Progress

- [x] Phase 0: Plan authored
- [x] Phase 1: Data layer (no changes)
- [x] Phase 2.5: Red tests written and confirmed failing
- [x] Phase 2: Implementation (workflow + service + script)
- [x] Phase 2: Green tests confirmed (28/28 crash-reporting + gate tests pass)
- [x] Phase 3: Code review

## Feedback

## Assumption Log

- **`EXTRA_FRONT_END_OPTIONS` is the supported mechanism**: The
  Flutter Xcode build phase (`xcode_backend.sh`) reads this env var
  and forwards it to the Dart front-end via
  `--ExtraFrontEndOptions`. This is the standard mechanism documented
  in the Flutter source tree for passing dart-defines through an
  `xcodebuild` invocation. The alternative — restructuring the iOS
  build to call `flutter build ipa` directly — would discard the
  manual-signing configuration the pipeline relies on and is not
  adopted.
- **Empty-DSN runtime check is defensive, not primary**: The
  pre-release gate (§11p, §11q) is the primary defense. The runtime
  empty-DSN guard in `SentryCrashReporter.init` is a second line of
  defense — if a future regression slips past the gate (e.g. a new
  iOS build invocation shape that the gate does not yet cover), the
  runtime still surfaces a diagnosable condition rather than silently
  dropping events. The guard logs once at init time; it does not log
  per-event.
- **No Android change**: The Android path continues to use
  `--dart-define=SENTRY_DSN=$SENTRY_DSN` on `flutter build appbundle`.
  This change is iOS-specific. The Android upload-destination fix
  (commit history) is unrelated to this change.
- **Coordinate, do not duplicate, with the symbol-upload fix**:
  The symbol-upload fix (`.github/agents/plans/crash-reporting-upload-destination-plan.md`)
  added §11l–§11o to the same gate script. The new §11p and §11q
  extend the same script but check a different shape of bug
  (destination-in-binary vs. destination-supplied-to-build). The
  two checks are independent: §11p/§11q verify DSN reaches the
  iOS binary; §11n/§11o verify `SENTRY_PROJECT` reaches the
  upload step.

### Phase 0 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓
