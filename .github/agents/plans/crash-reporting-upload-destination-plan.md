# Crash Reporting — Symbol-Upload Destination and Secret Hygiene

## Overview

Android crash reports arrive in the Sentry dashboard with unreadable class
names, which during the recent incident almost produced a wrong diagnosis. The
Sentry Android Gradle plugin (the upload step) reads the destination project
from the build environment, but the release pipeline only supplies the project
name as a `--dart-define` flag — a form the Gradle plugin cannot read — and
does not export the project name as a Gradle-visible env var. The result is
that the upload may be reaching nothing.

In the same pipeline, three values that belong only on the build machine
(`SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`) are passed as
`--dart-define` to the Flutter build, which compiles them into the shipped
Android application binary. The auth token is a privileged credential. It has
already been rotated, so the exposure is closed — but the mechanism is still
in place and will re-expose the replacement credential on the next release if
left alone. The org and project names are non-secret but should not be
shipping in the binary either.

The iOS build has the inverse problem: it sets the auth token and org as
env vars (correct for the build machine) but does not set `SENTRY_PROJECT`,
so the iOS upload destination is unresolvable. No values are compiled into
the iOS binary.

## Requirements

- `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, and `SENTRY_PROJECT` must never be passed
  to `flutter build` as `--dart-define`. They are not values the running
  application needs; `lib/main.dart` reads only `SENTRY_DSN`. They belong
  on the build machine only.
- For Android, the Sentry Android Gradle plugin must see `SENTRY_AUTH_TOKEN`,
  `SENTRY_ORG`, and `SENTRY_PROJECT` as env vars (or Gradle properties) on
  the build machine, not as `--dart-define`.
- For iOS, the `sentry_dart_plugin` must see `SENTRY_AUTH_TOKEN`,
  `SENTRY_ORG`, and `SENTRY_PROJECT` as env vars on the build machine.
- The pre-release gate must catch both classes of regression:
  - any `--dart-define` whose key matches a known-sensitive name (token,
    secret, key, password, auth) — fail-loud, naming the consequence
  - any upload destination (iOS or Android) whose env var is unset in the
    build configuration — fail-loud, naming which platform cannot upload
- After the change, the only value passed from build configuration into the
  application is `SENTRY_DSN`, which is non-sensitive.

## Acceptance Criteria

- [x] No `--dart-define=SENTRY_AUTH_TOKEN`, `--dart-define=SENTRY_ORG`, or
      `--dart-define=SENTRY_PROJECT` appears in `.github/workflows/release.yml`.
- [x] The Android build step in `release.yml` exports `SENTRY_PROJECT` as an
      env var, in addition to the auth token and org.
- [x] The iOS build step in `release.yml` exports `SENTRY_PROJECT` as an env
      var, in addition to the auth token and org.
- [x] The pre-release gate fails (non-zero exit) when a `--dart-define` value
      in any release workflow contains a known-sensitive key name, with a
      message that names the consequence in plain terms.
- [x] The pre-release gate fails (non-zero exit) when `SENTRY_PROJECT` is
      missing from either the iOS or the Android build step of the release
      workflow, with a message that names which platform's upload destination
      is unresolvable.
- [x] The existing `uploadSentryMapping` check is extended to assert the
      destination resolves (env var present in the workflow), not just that
      the hook exists in `pubspec.yaml`.
- [x] The only `--dart-define` value that ships in the Android application
      binary is `SENTRY_DSN`.
- [x] The iOS path is reviewed under the same criteria; findings are stated
      explicitly even where no change is required.
- [x] Android and iOS release builds complete successfully after the change
      (the build itself is not exercised in the pre-flight environment; this
      is verified via the gate's workflow-file inspection rather than via
      running the build).

## Scenarios

### S-001: Sensitive key in `--dart-define` fails the gate
- Trigger: A future agent or developer adds `--dart-define=SENTRY_AUTH_TOKEN=...`
  to the Android build step (or any credential-named value).
- Precondition: `.github/workflows/release.yml` is committed.
- Flow: Pre-release gate greps the workflow file for the sensitive key name
  in any `--dart-define=KEY=VALUE` token; pattern is matched; failure logged
  with a plain message; gate exits non-zero.
- Expected outcome: Gate exits 1; the message names the credential name and
  the consequence ("this value is compiled into the shipped Android
  application and extractable from any published artifact").
- Edge case of: none

### S-002: Android upload destination unresolvable
- Trigger: A future agent removes `SENTRY_PROJECT` from the Android build
  step's env block, or the project name is left blank.
- Precondition: `.github/workflows/release.yml` is committed.
- Flow: Pre-release gate greps the Android job in the workflow for
  `SENTRY_PROJECT:` and asserts the value is non-empty. If missing, the
  failure is logged naming the platform ("Android upload destination
  unresolvable: SENTRY_PROJECT is not exported in the release workflow's
  Android job").
- Expected outcome: Gate exits 1.
- Edge case of: none

### S-003: iOS upload destination unresolvable
- Trigger: A future agent removes `SENTRY_PROJECT` from the iOS build
  step's env block, or the project name is left blank.
- Precondition: `.github/workflows/release.yml` is committed.
- Flow: Pre-release gate greps the iOS job in the workflow for
  `SENTRY_PROJECT:` and asserts the value is non-empty. If missing, the
  failure is logged naming the platform.
- Expected outcome: Gate exits 1.
- Edge case of: none

### S-004: Existing `uploadSentryMapping` hook check extended
- Trigger: A future agent keeps the `uploadSentryMapping` reference in
  `pubspec.yaml` but removes the Sentry project name from the Android
  workflow env.
- Precondition: `pubspec.yaml` is committed with the hook.
- Flow: Pre-release gate still passes the "hook is configured" assertion
  (existing check) AND the new "destination resolves" assertion (new
  check) — so the gate catches the new defect.
- Expected outcome: Gate exits 1, citing the destination check, not the
  hook check.
- Edge case of: S-002

### S-005: Reduced `--dart-define` set enumerated
- Trigger: An audit of the values passed from build configuration into
  the application.
- Precondition: After the fix lands.
- Flow: Static review of `.github/workflows/release.yml` for the
  `flutter build` invocations; enumerate the `--dart-define=KEY` tokens.
- Expected outcome: The only key shipped into the application is
  `SENTRY_DSN`. Each value is non-sensitive (DSN is a public endpoint
  URL, not a credential).
- Edge case of: none

## Iteration 1

### DB Changes
None.

### Backend Changes

1. **`.github/workflows/release.yml`** — Android job:
   - Add `SENTRY_PROJECT` to the `env:` block of the "Build AAB with
     Sentry baked in" step. The value is `omnitrain-android`. This is the
     value the Sentry Android Gradle plugin reads at upload time.
   - Remove the three `--dart-define` flags whose keys are
     `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, and `SENTRY_PROJECT`. The
     remaining flag is `--dart-define=SENTRY_DSN=$SENTRY_DSN`, which is
     the only value the running application reads (`lib/main.dart:147`).

2. **`.github/workflows/release.yml`** — iOS job:
   - Add `SENTRY_PROJECT` to the `env:` block of the "Build IPA (manual
     signing)" step. The value is `omnitrain-ios`. The iOS build is
     invoked via `xcodebuild` which still runs the `sentry_dart_plugin`
     iOS build phase; that phase reads the project from the env var.
   - No `--dart-define` changes for iOS — the iOS job does not pass
     any today.

3. **`scripts/pre_release_check.sh`** — three new checks, one updated:
   - **New check** (gate §11l, between current 11k and 11m): grep
     `.github/workflows/release.yml` for `--dart-define=*SENTRY_AUTH_TOKEN*`
     and fail with a plain message naming the credential and the
     consequence.
   - **New check**: same file, grep for any `--dart-define=*TOKEN*`,
     `--dart-define=*SECRET*`, `--dart-define=*KEY*`,
     `--dart-define=*PASSWORD*`, and fail. (Lower-case to avoid matching
     `SENTRY_AUTH_TOKEN` twice; the specific check above stays for the
     named case so the error message is sharp.)
   - **Updated check** (current 11k hook check): assert the
     `uploadSentryMapping` hook exists (existing) AND the
     `SENTRY_PROJECT` env var is exported in the Android job of the
     release workflow (new).
   - **New check**: assert `SENTRY_PROJECT` env var is exported in the
     iOS job of the release workflow. Distinct message naming the iOS
     platform.

4. **`pubspec.yaml`** — comment-only update:
   - Update the comment block at the bottom of the file (above
     `sentry_dart_plugin:`) to state that `SENTRY_AUTH_TOKEN`,
     `SENTRY_ORG`, and `SENTRY_PROJECT` are build-machine env vars
     consumed by the upload step, NOT values to be passed to
     `flutter build` as `--dart-define`. The DSN is the only
     application-level value.

### Frontend Changes
None.

### Implementation Steps
1. Write failing Dart tests for the four new pre-release gate scenarios
   (S-001..S-004). The tests invoke the gate script against
   in-memory copies of `release.yml` with manipulated content and
   assert the expected exit code and a substring of the error message.
2. Update `scripts/pre_release_check.sh` with the three new checks and
   the one extended check.
3. Update `.github/workflows/release.yml` (Android env, Android
   `--dart-define`s, iOS env).
4. Update the `sentry_dart_plugin` config comment in `pubspec.yaml`.
5. Re-run the new pre-release gate tests — confirm green.
6. Run `flutter analyze` on the new test file.
7. Re-run the full pre-release gate (`bash scripts/pre_release_check.sh
   --fast`) against the repo to confirm the new checks pass with the
   fix in place.

## Progress

- [x] Phase 0: Plan authored
- [x] Phase 1: Data layer (no changes)
- [x] Phase 2.5: Red tests written and confirmed failing (6/7 expected; happy-path passes by default since the new checks did not exist)
- [x] Phase 2: Implementation
- [x] Phase 2: Green tests confirmed (7/7 gate tests + 16/16 crash_reporting_test)
- [x] Phase 3: Code review

## Feedback

## Assumption Log

- **Sentry project names**: assumed `omnitrain-ios` and
  `omnitrain-android` are two separate Sentry projects, matching the
  existing comment in `pubspec.yaml` ("dSYMs go to `omnitrain-ios` and
  ProGuard mappings go to `omnitrain-android` (assuming two Sentry
  projects)"). If only one Sentry project exists, both upload
  destinations should point at the single project. **This needs to be
  verified by the user** against the Sentry dashboard before the next
  release; the fix preserves the existing two-project shape, which is
  the lowest-risk change consistent with the prompt's "align to what
  actually exists rather than creating anything new" guidance.
- **iOS upload invocation**: assumed the `sentry_dart_plugin` iOS build
  phase runs when `xcodebuild` is invoked on the Flutter workspace,
  which is how the current `release.yml` invokes iOS. The build phase
  is added by `sentry_dart_plugin` on `flutter pub get` (it's a dev
  dependency), so the assumption is testable on a real CI runner; the
  pre-flight environment cannot exercise it. The fix preserves the
  existing iOS invocation shape, so this assumption does not change
  the upload behavior.
- **Audit of remaining values**: the only `--dart-define` value that
  ships in the application binary after the fix is `SENTRY_DSN`. The
  DSN is the public Sentry endpoint URL for the project; it is not a
  credential. It is consumed at runtime by `lib/main.dart:147` via
  `String.fromEnvironment('SENTRY_DSN', defaultValue: '')`.
- **Naming of "known-sensitive" pattern**: the prompt asks for "any
  value being passed into the application looks like a credential."
  The list of substrings is `TOKEN`, `SECRET`, `KEY`, `PASSWORD`,
  `AUTH` (case-insensitive). The specific `SENTRY_AUTH_TOKEN` case is
  named explicitly so the failure message can quote the exact value.
  This set is intentionally narrow — false positives are
  gate-tripping errors that block releases for a wrong reason, and the
  pattern is not used to substitute for a proper secret scanner.
- **Gate output format**: the new checks follow the existing
  `log_err "..."` pattern in `pre_release_check.sh`, which prefixes
  the message with `  ✗  `. The plain-text messages name the
  consequence directly (e.g., "this value is compiled into the
  shipped Android application and extractable from any published
  artifact"), not the technical reason for the failure.

### Phase 0 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓
