#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# OmniTrain pre-release sanity check
#
# Run from the repo root BEFORE every Xcode Archive:
#   bash scripts/pre_release_check.sh          # full gate (analyze + tests)
#   bash scripts/pre_release_check.sh --fast   # metadata/invariants only
#
# Exit 0 = all clear.  Exit 1 = at least one blocking error — fix it first.
#
# Sections 1–10:  release metadata checks (version, signing, bundle ID…)
# Section  11:    configuration invariants — guards against agent regressions
#                 of the July 2026 pre-launch fix pack. These are meant to
#                 FAIL until the fix pack has landed. Do not soften to warnings.
# Sections 12–13: flutter analyze + full test suite (skipped by --fast)
# Section  14:    swift test for the watchOS package in watch/watchos
#                 (skipped by --fast; skipped with a warning on a host that
#                 cannot build that package)
#
# ── Platform scoping ────────────────────────────────────────────────────────
# Some sections need a real build artifact: the iOS checks need an IPA, the
# Android checks need an AAB plus R8 mapping output. No single developer
# machine can produce both (macOS cannot build the AAB without the Android
# SDK; Windows cannot build an IPA at all), so a host-scoped run is the
# normal case, not an exception.
#
#   --ios       run iOS platform sections, scope OUT Android
#   --android   run Android platform sections, scope OUT iOS
#   --all       force BOTH (fails if a toolchain is missing)
#   (default)   auto-detect from the host toolchain
#
# A scoped-out platform is reported as SKIPPED and the final verdict becomes
# PARTIAL — never a green "all clear". This preserves the script's core
# principle: a missing artifact for an IN-SCOPE platform is still a hard
# error. Scoping changes what is claimed, never whether an absent artifact
# can pass by default.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PUBSPEC="pubspec.yaml"
LAST_BUILD_FILE="docs/releases/.last-released-build"
INFO_PLIST="ios/Runner/Info.plist"
PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
PRIVACY_MANIFEST="ios/Runner/PrivacyInfo.xcprivacy"

SKIP_HEAVY=0
PLATFORM_SCOPE="auto"
for arg in "$@"; do
  case "$arg" in
    --fast)    SKIP_HEAVY=1 ;;
    --ios)     PLATFORM_SCOPE="ios" ;;
    --android) PLATFORM_SCOPE="android" ;;
    --all)     PLATFORM_SCOPE="all" ;;
    *)
      echo "ERROR: unknown argument '$arg'."
      echo "Usage: bash scripts/pre_release_check.sh [--fast] [--ios|--android|--all]"
      exit 1
      ;;
  esac
done

errors=0
failed_checks=()
skipped_platforms=()

log_ok()   { echo "  ✓  $*"; }
log_err()  { echo "  ✗  $*"; failed_checks+=("$*"); (( errors++ )) || true; }
log_warn() { echo "  ⚠  $*"; }
log_skip() { echo "  ⊘  $*"; }

# ── Resolve which platform sections are in scope ────────────────────────────
# Auto-detection asks the host what it can actually build. `xcodebuild` only
# exists on a Mac with Xcode; the Android SDK is located the same way Gradle
# locates it (ANDROID_HOME / ANDROID_SDK_ROOT, or `adb` on PATH).
host_has_ios_toolchain() {
  [[ "$(uname -s)" == "Darwin" ]] && command -v xcodebuild >/dev/null 2>&1
}
host_has_android_toolchain() {
  [[ -n "${ANDROID_HOME:-}" ]] || [[ -n "${ANDROID_SDK_ROOT:-}" ]] \
    || command -v adb >/dev/null 2>&1 || command -v sdkmanager >/dev/null 2>&1
}

case "$PLATFORM_SCOPE" in
  ios)     IOS_IN_SCOPE=1; ANDROID_IN_SCOPE=0 ;;
  android) IOS_IN_SCOPE=0; ANDROID_IN_SCOPE=1 ;;
  all)     IOS_IN_SCOPE=1; ANDROID_IN_SCOPE=1 ;;
  auto)
    IOS_IN_SCOPE=0; ANDROID_IN_SCOPE=0
    host_has_ios_toolchain     && IOS_IN_SCOPE=1
    host_has_android_toolchain && ANDROID_IN_SCOPE=1
    if (( IOS_IN_SCOPE == 0 && ANDROID_IN_SCOPE == 0 )); then
      echo "ERROR: no mobile toolchain detected on this host (no Xcode, no Android SDK)."
      echo "Nothing platform-specific can be verified here. Run this on a build machine,"
      echo "or pass --ios / --android explicitly if you know better than the detection."
      exit 1
    fi
    ;;
esac

(( IOS_IN_SCOPE == 0 ))     && skipped_platforms+=("iOS")
(( ANDROID_IN_SCOPE == 0 )) && skipped_platforms+=("Android")
true  # keep the `set -e` guard happy after the arithmetic tests above

# ── Guard: must be run from repo root ───────────────────────────────────────
if [[ ! -f "$PUBSPEC" ]]; then
  echo "ERROR: $PUBSPEC not found. Run this script from the repo root."
  exit 1
fi

# ── Scope a project.pbxproj check to the iPhone app ─────────────────────────
# `project.pbxproj` describes every target in the project, not just the app:
# the test bundle, and — since the watch work — the watch app that embeds into
# Runner. Only Runner's own build settings describe what ships as the iPhone
# app, so checks about the app's bundle identifier and device family must read
# those and nothing else. The watch app legitimately carries a different value
# for both: its bundle identifier is `<runner-id>.watchkitapp` (required for the
# companion relationship, and it cannot be the same string as the app it pairs
# with), and `TARGETED_DEVICE_FAMILY = 4` is watchOS, required to install at
# all. Neither is a regression in the iPhone app.
#
# The scope is every configuration list whose owner comment says "Runner" —
# both the PBXNativeTarget and the PBXProject whose defaults it inherits.
# `"Runner" */` matches exactly those two and not `"RunnerTests"`.
runner_pbxproj_settings() {
  local ids
  ids=$(awk '
    /\/\* Begin XCConfigurationList section \*\// { lists = 1; next }
    /\/\* End XCConfigurationList section \*\//   { lists = 0; next }
    lists && /"Runner" \*\// { in_list = 1; next }
    lists && in_list && /^[[:space:]]*[0-9A-F]+[[:space:]]*\/\*/ { print $1; next }
    lists && in_list && /^[[:space:]]*\};/ { in_list = 0; next }
  ' "$PBXPROJ" | tr '\n' ' ')

  awk -v ids="$ids" '
    BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) runner[a[i]] = 1 }
    /\/\* Begin XCBuildConfiguration section \*\// { section = 1; next }
    /\/\* End XCBuildConfiguration section \*\//   { exit }
    !section { next }
    /^[[:space:]]*[0-9A-F]+[[:space:]]*\/\*/ { printing = ($1 in runner); next }
    printing { print }
    printing && /^[[:space:]]*\};/ { printing = 0 }
  ' "$PBXPROJ"
}

# Read once: both checks below need it, and it costs two awk passes.
RUNNER_SETTINGS=$(runner_pbxproj_settings)

# An empty scope would make both checks pass by having nothing to look at,
# which is the failure mode they exist to prevent.
if ! grep -q 'isa = XCBuildConfiguration' <<<"$RUNNER_SETTINGS"; then
  log_err "Could not find the Runner app's build configurations in $PBXPROJ (expected configuration lists owned by Runner). The bundle-identifier and device-family checks below cannot be trusted, so they have not run."
fi

# ── 1. Parse version from pubspec.yaml ──────────────────────────────────────
version_line=$(grep '^version:' "$PUBSPEC" | head -1 | tr -d '\r')
version_full=$(echo "$version_line" | sed 's/version:[[:space:]]*//')  # e.g. "1.0.1+3"
version_name="${version_full%%+*}"                                      # e.g. "1.0.1"
build_number="${version_full##*+}"                                      # e.g. "3"

echo ""
echo "OmniTrain pre-release check"
echo "────────────────────────────────────────"
echo "  Version:       $version_name"
echo "  Build number:  $build_number"
if [[ $SKIP_HEAVY -eq 1 ]]; then
  echo "  Mode:          --fast (analyzer and tests SKIPPED)"
fi
scope_label=""
(( IOS_IN_SCOPE == 1 ))     && scope_label="iOS"
(( ANDROID_IN_SCOPE == 1 )) && scope_label="${scope_label:+$scope_label + }Android"
echo "  Platforms:     $scope_label$([[ "$PLATFORM_SCOPE" == "auto" ]] && echo "  (auto-detected from host toolchain)")"
echo ""

# ── 2. Version must not be the default placeholder ──────────────────────────
if [[ "$version_full" == "1.0.0+1" ]]; then
  log_warn "Version is still 1.0.0+1 — the Flutter default. If this is intentional for your first build, ignore this warning. Otherwise increment it."
fi

# ── 3. Build number must be greater than the last uploaded build ─────────────
if [[ -f "$LAST_BUILD_FILE" ]]; then
  last_build=$(cat "$LAST_BUILD_FILE" | tr -d '[:space:]')
  if ! [[ "$build_number" =~ ^[0-9]+$ ]] || ! [[ "$last_build" =~ ^[0-9]+$ ]]; then
    log_err "Could not compare build numbers (non-numeric). Check pubspec.yaml and $LAST_BUILD_FILE."
  elif (( build_number <= last_build )); then
    log_err "Build number $build_number is NOT greater than the last uploaded build ($last_build). Increment the build number in pubspec.yaml before archiving."
  else
    log_ok "Build number $build_number > last released ($last_build)"
  fi
else
  log_warn "$LAST_BUILD_FILE not found."
  log_warn "After your first successful TestFlight upload, run:"
  log_warn "  echo '$build_number' > $LAST_BUILD_FILE && git add $LAST_BUILD_FILE && git commit -m 'chore: record released build $build_number'"
fi

# ── 4. pubspec.yaml must be committed (no uncommitted version bumps) ─────────
if git diff --quiet HEAD -- "$PUBSPEC" 2>/dev/null; then
  log_ok "pubspec.yaml has no uncommitted changes"
else
  log_err "pubspec.yaml has uncommitted changes. Commit the version bump before archiving so the build number is traceable."
fi

# ── 5. Info.plist must still use Flutter build variables ─────────────────────
if grep -q 'FLUTTER_BUILD_NAME' "$INFO_PLIST" && \
   grep -q 'FLUTTER_BUILD_NUMBER' "$INFO_PLIST"; then
  log_ok "Info.plist uses \$(FLUTTER_BUILD_NAME) / \$(FLUTTER_BUILD_NUMBER)"
else
  log_err "Info.plist is NOT reading version from Flutter variables. CFBundleShortVersionString and CFBundleVersion must use \$(FLUTTER_BUILD_NAME) and \$(FLUTTER_BUILD_NUMBER)."
fi

# ── 6. Bundle identifier must be consistent across all Runner build configs ──
bundle_id=$(grep 'PRODUCT_BUNDLE_IDENTIFIER' <<<"$RUNNER_SETTINGS" \
  | grep -oE '= [^;]+;' \
  | sed 's/= //; s/;//; s/[[:space:]]//g' \
  | sort -u)

bundle_ids_count=$(grep -c . <<<"$bundle_id" || true)

if [[ "$bundle_ids_count" -eq 1 ]]; then
  log_ok "Bundle identifier is consistent across all Runner configs: $bundle_id"
else
  log_err "Inconsistent PRODUCT_BUNDLE_IDENTIFIER across the Runner app's build configurations ($bundle_ids_count distinct values: $(tr '\n' ' ' <<<"$bundle_id")). Every Runner config must use the same bundle ID."
fi

# ── 7. Development team must be set ─────────────────────────────────────────
team_count=$(grep 'DEVELOPMENT_TEAM' "$PBXPROJ" \
  | grep -v '= ""' \
  | grep -v '= ;' \
  | wc -l \
  | tr -d ' ')

if [[ "$team_count" -ge 1 ]]; then
  team_id=$(grep 'DEVELOPMENT_TEAM' "$PBXPROJ" \
    | grep -oE '= [A-Z0-9]+' \
    | head -1 \
    | sed 's/= //')
  log_ok "Development team is set: $team_id"
else
  log_err "DEVELOPMENT_TEAM is not set in project.pbxproj. Open Xcode → Signing & Capabilities and select your team."
fi

# ── 8. Release config must have VALIDATE_PRODUCT = YES ──────────────────────
if grep -q 'VALIDATE_PRODUCT = YES' "$PBXPROJ"; then
  log_ok "VALIDATE_PRODUCT = YES is present in Release config"
else
  log_warn "VALIDATE_PRODUCT = YES not found in Release config. This is set by Xcode by default but worth confirming."
fi

# ── 9. Release config must NOT have DEBUG=1 preprocessor flag ────────────────
# Rough heuristic: the DEBUG=1 macro should only appear once (Debug config).
debug_macro_count=$(grep -c '"DEBUG=1"' "$PBXPROJ" || true)
if [[ "$debug_macro_count" -le 1 ]]; then
  log_ok "DEBUG=1 macro appears only in Debug config"
else
  log_warn "DEBUG=1 appears $debug_macro_count times in project.pbxproj. Verify it is not leaking into Release or Profile configs."
fi

# ── 10. No staged/unstaged changes to iOS project files ──────────────────────
ios_changes=$( (git diff HEAD -- ios/ 2>/dev/null || true) | wc -l | tr -d ' ')
if [[ "$ios_changes" -eq 0 ]]; then
  log_ok "No uncommitted changes to ios/ directory"
else
  log_warn "There are uncommitted changes in ios/. This won't block archiving but make sure they are intentional."
fi

# ── 11. Configuration invariants (pre-launch fix pack guards) ────────────────
# These encode decisions from the July 2026 pre-launch inspection. They exist
# so a coding agent can never silently regress them. Expected to FAIL until
# the fix pack has landed — that is the point.
echo ""
echo "  — Configuration invariants —"

# 11a. No location declarations anywhere in the iOS plist (no location feature exists)
if grep -q 'NSLocation' "$INFO_PLIST"; then
  log_err "Info.plist contains a location declaration (NSLocation*). OmniTrain has no location feature; remove it."
else
  log_ok "No location declarations in Info.plist"
fi

# 11b. Microphone purpose string must be present and non-empty
# A bundled audio component (the `audio_session` plugin used for rest-timer
# alert sounds) references microphone-related AVAudioSession APIs in the
# binary. Apple rejects uploads that include any reference to a sensitive
# API without a corresponding purpose string. The string must be honest:
# it must not claim the app records audio, and must not be the prior
# "unused capability" placeholder.
if ! grep -q 'NSMicrophoneUsageDescription' "$INFO_PLIST"; then
  log_err "Info.plist is missing NSMicrophoneUsageDescription. The `audio_session` plugin pulls microphone-related APIs into the binary; Apple rejects the upload without this string."
else
  mic_value=$(grep -A1 'NSMicrophoneUsageDescription' "$INFO_PLIST" \
    | sed -n 's:.*<string>\(.*\)</string>.*:\1:p' \
    | head -1 \
    | tr -d '[:space:]')
  if [[ -z "$mic_value" ]]; then
    log_err "NSMicrophoneUsageDescription is present but empty. It must explain the binary's microphone-API reference."
  elif echo "$mic_value" | grep -qi 'unused\|not used\|never used\|capability is unused'; then
    log_err "NSMicrophoneUsageDescription contains the obsolete 'unused capability' placeholder. It must be a user-facing explanation, not a disclaimer that the capability is unused."
  else
    log_ok "NSMicrophoneUsageDescription is present and non-empty"
  fi
fi

# 11c. No dead notification usage key (not a real iOS key)
if grep -q 'NSUserNotificationUsageDescription' "$INFO_PLIST"; then
  log_err "Info.plist contains NSUserNotificationUsageDescription — not an iOS key; remove it."
else
  log_ok "No dead notification usage key in Info.plist"
fi

# 11d. Camera purpose string must describe the camera, not the photo library
if grep -q 'NSCameraUsageDescription' "$INFO_PLIST"; then
  if grep -A2 'NSCameraUsageDescription' "$INFO_PLIST" | grep -qi 'photo library'; then
    log_err "Camera purpose string mentions the photo library. It must describe camera capture (profile/food photos)."
  else
    log_ok "Camera purpose string describes the camera"
  fi
else
  log_err "NSCameraUsageDescription missing — camera is used for profile and food photos."
fi

# 11e. Display name must be the brand name
if grep -A1 'CFBundleDisplayName' "$INFO_PLIST" | grep -q '<string>OmniTrain</string>'; then
  log_ok "Display name is OmniTrain"
else
  log_err "CFBundleDisplayName is not 'OmniTrain'. This is the name under the icon on every home screen."
fi

# 11f. iPhone-only: no Runner config may target iPad (one-way door once shipped)
bad_family=$(grep 'TARGETED_DEVICE_FAMILY' <<<"$RUNNER_SETTINGS" | grep -vE '= *"?1"? *;' || true)
if [[ -n "$bad_family" ]]; then
  log_err "The Runner app targets iPad (TARGETED_DEVICE_FAMILY != 1): $(tr '\n' ' ' <<<"$bad_family"). v1 ships iPhone-only; iPad support cannot be removed after shipping."
else
  log_ok "Every Runner build configuration is iPhone-only"
fi

# 11g. Retired SQLite runtime must not return to dependencies
if grep -qE '^[[:space:]]{2}sqflite:' "$PUBSPEC"; then
  log_err "sqflite is back in pubspec.yaml. The runtime was retired; only the schema docs and the dev-only FFI test dependency remain."
else
  log_ok "No SQLite runtime dependency in pubspec.yaml"
fi

# 11h. No SQL files may ship as app assets (internal schema must not reach users)
if grep -qE '^[[:space:]]*-[[:space:]].*\.sql' "$PUBSPEC"; then
  log_err "A .sql file is declared as a bundled asset. Schema/seed docs stay in scripts/ but must never ship in the app."
else
  log_ok "No SQL files declared as app assets"
fi

# 11i. Privacy manifest must exist and be in the Runner Resources build phase
if [[ ! -f "$PRIVACY_MANIFEST" ]]; then
  log_err "PrivacyInfo.xcprivacy is missing."
elif ! grep -q 'PrivacyInfo.xcprivacy in Resources' "$PBXPROJ"; then
  log_err "PrivacyInfo.xcprivacy exists but is not in the Runner Resources build phase."
else
  log_ok "Privacy manifest present and in Resources build phase"
fi

# 11j. Privacy manifest declares exactly the two APIs the live app uses
if [[ -f "$PRIVACY_MANIFEST" ]]; then
  category_count=$(grep -c 'NSPrivacyAccessedAPICategory' "$PRIVACY_MANIFEST" || true)
  if grep -q 'DiskSpace' "$PRIVACY_MANIFEST"; then
    log_err "Privacy manifest still declares DiskSpace access — that justification left with the SQLite runtime."
  elif [[ "$category_count" -ne 2 ]]; then
    log_err "Privacy manifest declares $category_count accessed-API categories; expected exactly 2 (FileTimestamp, UserDefaults)."
  elif grep -q 'FileTimestamp' "$PRIVACY_MANIFEST" && grep -q 'UserDefaults' "$PRIVACY_MANIFEST"; then
    log_ok "Privacy manifest declares exactly FileTimestamp + UserDefaults"
  else
    log_err "Privacy manifest categories are not the expected FileTimestamp + UserDefaults pair."
  fi
fi

# 11k. Crash-reporting integration is wired and release-only.
# Pre-launch invariant for the crash-reporting plan: a release that
# could ship without telemetry must fail loudly. The five checks below
# cover the four failure modes a regression can introduce — missing
# dependency, missing SDK init, missing symbol-upload hook, or an
# accidental flip on debug builds.
if grep -qE '^[[:space:]]{2}sentry_flutter:' "$PUBSPEC"; then
  log_ok "sentry_flutter is declared in pubspec.yaml dependencies"
else
  log_err "sentry_flutter is not in pubspec.yaml dependencies. The release build has no crash reporting configured."
fi

if grep -qE '^  sentry_dart_plugin:|^  sentry_dart_plugin:' "$PUBSPEC"; then
  log_ok "sentry_dart_plugin is declared in pubspec.yaml dev_dependencies"
else
  log_err "sentry_dart_plugin is not in pubspec.yaml dev_dependencies. iOS dSYM and Android ProGuard mapping uploads will not run."
fi

# Find lines that contain the bootstrap call, ignoring Dart
# line/block comments. The pattern requires the literal call
# `await CrashReportingService.bootstrap(` — bare imports or commented
# code do not satisfy the check.
if [[ -f "lib/main.dart" ]]; then
  non_comment_call=$(grep -nE 'CrashReportingService\.bootstrap\(' "lib/main.dart" \
    | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*//' \
    | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*\*' \
    | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*/\*' \
    | grep -vE '/\*.*CrashReportingService\.bootstrap\(' \
    || true)
  if echo "$non_comment_call" | grep -q 'await CrashReportingService\.bootstrap('; then
    log_ok "CrashReportingService.bootstrap is awaited from lib/main.dart"
  else
    log_err "CrashReportingService.bootstrap call is missing or commented out from lib/main.dart. The SDK will never initialise and the release build will produce no crash reports."
  fi
else
  log_err "lib/main.dart not found — cannot verify crash-reporting bootstrap."
fi

# The debug-build guard is the heart of the privacy contract: it must
# gate the bootstrap call on kReleaseMode (or equivalent). The check is
# deliberately permissive — any of the recognised patterns is acceptable.
DEBUG_BUILD_GUARD_OK=0
if [[ -f "lib/main.dart" ]]; then
  if grep -qE 'enabled:[[:space:]]*kReleaseMode|kReleaseMode[[:space:]]*&&.*enabled' "lib/main.dart"; then
    DEBUG_BUILD_GUARD_OK=1
  fi
fi
if [[ "$DEBUG_BUILD_GUARD_OK" -eq 1 ]]; then
  log_ok "Crash reporting is gated on kReleaseMode — debug builds will not report"
else
  log_err "Crash reporting is not gated on kReleaseMode. A debug build will ship telemetry to the crash service."
fi

# Symbol-upload plumbing must be present in both platform configs.
# Android: release must be minified (so a mapping.txt is produced) and
# the build must reference the uploadSentryMapping task (injected by
# sentry_dart_plugin).
if [[ -f "android/app/build.gradle.kts" ]]; then
  if grep -q 'isMinifyEnabled = true' "android/app/build.gradle.kts"; then
    log_ok "Android release build is minified (mapping.txt will be produced)"
  else
    log_err "Android release build is not minified. Without mapping.txt, JVM stack frames will not symbolicate."
  fi
else
  log_err "android/app/build.gradle.kts is missing — cannot verify Android symbol-upload config."
fi

# The symbol-upload config must be under the `sentry:` key and the CLI
# must actually be invoked by the release workflow.
#
# This check previously grepped the pubspec for `uploadSentryMapping` and
# passed. That was validating a fiction: `sentry_dart_plugin` reads
# `pubspec['sentry']`, so a block keyed `sentry_dart_plugin:` was ignored
# entirely, `buildscripts:` was never a real option, and the plugin has
# no Gradle integration that could run such a task. The gate reported a
# working symbol pipeline while nothing was uploaded at all.
#
# What is verified now is what actually has to be true:
#   (a) the config lives under the `sentry:` key the plugin reads, and
#   (b) the release workflow explicitly runs `dart run sentry_dart_plugin`
#       (a CLI — no build hook invokes it implicitly).
if grep -qE '^sentry:' "$PUBSPEC"; then
  log_ok "Sentry symbol-upload config is under the 'sentry:' key the plugin actually reads"
else
  log_err "Sentry symbol-upload config is missing or misnamed in pubspec.yaml. sentry_dart_plugin reads pubspec['sentry'] — a block keyed anything else (e.g. 'sentry_dart_plugin:') is silently ignored and NOTHING is uploaded."
fi

# The config alone uploads nothing — the CLI has to be run. Both release
# jobs must invoke it after their build step, or symbols never leave the
# runner. One invocation per platform job; require at least two so a
# refactor cannot drop one platform silently.
SENTRY_CLI_INVOCATIONS=$(grep -c 'dart run sentry_dart_plugin' ".github/workflows/release.yml" 2>/dev/null || true)
SENTRY_CLI_INVOCATIONS=${SENTRY_CLI_INVOCATIONS:-0}
if (( SENTRY_CLI_INVOCATIONS >= 2 )); then
  log_ok "Release workflow runs 'dart run sentry_dart_plugin' in both platform jobs ($SENTRY_CLI_INVOCATIONS invocations)"
else
  log_err "Release workflow invokes 'dart run sentry_dart_plugin' $SENTRY_CLI_INVOCATIONS time(s); both the iOS and Android jobs need it. sentry_dart_plugin is a CLI — no Gradle task and no Xcode build phase runs it implicitly, so a job without this step ships that platform with no debug symbols and unsymbolicated crash reports."
fi

# 11l. SENTRY_AUTH_TOKEN must never appear as a --dart-define value.
# A previous release pipeline passed it this way, which compiled the
# privileged credential into the shipped Android application binary
# (extractable from any published artifact). The rotated credential
# closes the exposure; this check closes the mechanism so a future
# agent cannot re-introduce the same leak. The full check (any
# credential-shaped name) is 11m; this is the named-credential
# fast-path so the failure message is sharp.
RELEASE_WORKFLOW=".github/workflows/release.yml"
if [[ -f "$RELEASE_WORKFLOW" ]]; then
  if grep -qE '^[[:space:]]*--dart-define=.*SENTRY_AUTH_TOKEN' "$RELEASE_WORKFLOW"; then
    log_err "SENTRY_AUTH_TOKEN appears as a --dart-define in $RELEASE_WORKFLOW. This value is compiled into the shipped Android application and extractable from any published artifact. Use the workflow's env: block so it stays on the build machine."
  else
    log_ok "SENTRY_AUTH_TOKEN is not compiled into the shipped Android binary"
  fi
else
  log_warn "$RELEASE_WORKFLOW is missing — cannot verify --dart-define hygiene."
fi

# 11m. Any credential-shaped --dart-define key (TOKEN, SECRET, KEY,
# PASSWORD) must be rejected. The named check (11l) catches
# SENTRY_AUTH_TOKEN with a precise message; this catches every
# other future addition of the same shape (e.g. FRESHDESK_TOKEN,
# STRIPE_KEY, ROLLBAR_SECRET) before a release ships with a
# credential in the binary.
if [[ -f "$RELEASE_WORKFLOW" ]]; then
  bad_defines=$(grep -nE '^[[:space:]]*--dart-define=[A-Z_]*(TOKEN|SECRET|KEY|PASSWORD)[A-Z_]*=' "$RELEASE_WORKFLOW" || true)
  if [[ -n "$bad_defines" ]]; then
    while IFS= read -r line; do
      key=$(echo "$line" | sed -nE 's/.*--dart-define=([A-Z_]+)=.*/\1/p')
      log_err "--dart-define=$key=... appears in $RELEASE_WORKFLOW. A credential-shaped key would be compiled into the shipped Android application and extractable from any published artifact. Pass such values through the workflow's env: block instead."
    done <<< "$bad_defines"
  else
    log_ok "No credential-shaped --dart-define keys in the release workflow"
  fi
fi

# 11n. Android upload destination must be `omnitrain`. The Sentry
# Android Gradle plugin (the upload step) reads SENTRY_PROJECT from
# the Gradle environment, which the workflow provides via the
# Android job's env: block. Only the `omnitrain` Sentry project
# exists; both iOS and Android uploads land there. Per-platform
# destinations (`omnitrain-android`) and the empty / blank / missing
# cases all fail this check.
# Extract one job's full YAML block by job key. Scanning the WHOLE job —
# rather than anchoring on the build step, as this check used to — means
# SENTRY_PROJECT is found whether it is declared at job level (the
# preferred form: one declaration inherited by every step) or repeated on
# an individual step. Anchoring on the build step made a correct
# job-level declaration read as '<unset>'.
#
# A job block runs from `  <job>:` to the next key at the same (2-space)
# indentation, or EOF.
extract_workflow_job_block() {
  local job="$1"
  awk -v job="$job" '
    $0 ~ "^  " job ":[[:space:]]*$" { flag=1; next }
    flag && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { exit }
    flag { print }
  ' "$RELEASE_WORKFLOW"
}

if [[ -f "$RELEASE_WORKFLOW" ]]; then
  android_block=$(extract_workflow_job_block android)
  android_project=$(echo "$android_block" \
    | sed -nE 's/^[[:space:]]+SENTRY_PROJECT:[[:space:]]+([^[:space:]#]+).*/\1/p' \
    | head -1)
  if [[ "$android_project" == "omnitrain" ]]; then
    log_ok "Android upload destination is 'omnitrain' (SENTRY_PROJECT in the Android job's env: block)"
  else
    log_err "Android upload destination is wrong: SENTRY_PROJECT in the release workflow's Android job is '${android_project:-<unset>}' but must be exactly 'omnitrain' (the single Sentry project). ProGuard mappings will not reach the correct Sentry project."
  fi
else
  log_warn "$RELEASE_WORKFLOW is missing — cannot verify Android upload destination."
fi

# 11o. iOS upload destination must be `omnitrain`. The
# `sentry_dart_plugin` iOS build phase (run by `flutter build ipa`)
# reads SENTRY_PROJECT from the environment. Only the `omnitrain`
# Sentry project exists; per-platform destinations (`omnitrain-ios`)
# are rejected so the regression that previously shipped iOS dSYMs
# to a non-existent project cannot reappear.
if [[ -f "$RELEASE_WORKFLOW" ]]; then
  ios_block=$(extract_workflow_job_block ios)
  ios_project=$(echo "$ios_block" \
    | sed -nE 's/^[[:space:]]+SENTRY_PROJECT:[[:space:]]+([^[:space:]#]+).*/\1/p' \
    | head -1)
  if [[ "$ios_project" == "omnitrain" ]]; then
    log_ok "iOS upload destination is 'omnitrain' (SENTRY_PROJECT in the iOS job's env: block)"
  else
    log_err "iOS upload destination is wrong: SENTRY_PROJECT in the release workflow's iOS job is '${ios_project:-<unset>}' but must be exactly 'omnitrain' (the single Sentry project). dSYMs will not reach the correct Sentry project."
  fi
else
  log_warn "$RELEASE_WORKFLOW is missing — cannot verify iOS upload destination."
fi

# 11p. iOS build must use `flutter build ipa` (the tooling-driven
# build). The previous bespoke `xcodebuild` invocation relied on
# `EXTRA_FRONT_END_OPTIONS` to inject the DSN; the DSN-forwarding
# path was not verified end-to-end, and iOS shipped unmonitored.
# `flutter build ipa` is the supported, end-to-end invocation that
# forwards `--dart-define=SENTRY_DSN=...` to the Dart front-end via
# the standard mechanism. A workflow that reverts to a raw
# `xcodebuild` invocation fails this check so the regression
# cannot reappear.
if [[ -f "$RELEASE_WORKFLOW" ]]; then
  if grep -qE 'flutter[[:space:]]+build[[:space:]]+ipa' "$RELEASE_WORKFLOW"; then
    log_ok 'iOS build uses flutter build ipa so --dart-define=SENTRY_DSN is forwarded to the Dart front-end via the supported mechanism'
  else
    log_err 'iOS build does not use flutter build ipa. The previous bespoke xcodebuild invocation relied on EXTRA_FRONT_END_OPTIONS to inject the DSN; that path is not verified end-to-end and iOS shipped unmonitored. Use "flutter build ipa --release --export-options-plist=ios/ExportOptions.plist --dart-define=SENTRY_DSN=\$SENTRY_DSN" in the iOS job so the Flutter Xcode build phase forwards the DSN to the Dart front-end.'
  fi
else
  log_warn "$RELEASE_WORKFLOW is missing — cannot verify iOS build invocation shape."
fi

# 11q. iOS reporting destination must reach the produced iOS
# artifact. The previous check (§11p / §11q in older revisions)
# inspected the workflow file and passed today while iOS shipped
# unmonitored. This check inspects the produced IPA: it extracts
# the IPA (an `unzip` step), reads the `Runner.app/Runner` (or
# `App.framework/App` for Flutter-on-iOS) binary, and greps for
# the literal DSN value. Passes only when the DSN is present in
# the binary. Mirrors how §11r inspects the produced Android AAB
# for the notification keep rules.
#
# The `PRE_RELEASE_GATE_FAKE_IP_BUILD` hook (test-only) mirrors
# the Android `PRE_RELEASE_GATE_FAKE_BUILD` hook: when set, the
# build helper is skipped and instead the helper writes whatever
# artifacts the variable describes directly into the build output
# paths. Live (non-test) mode runs the actual `flutter build ipa`
# invocation and inspects the resulting IPA.
#
# Scoped out by `--android` (or by auto-detection on a host with no
# Xcode). Skipping is NOT the same as passing: the run's final verdict
# becomes PARTIAL and names iOS as unverified.
FAKE_IP_BUILD="${PRE_RELEASE_GATE_FAKE_IP_BUILD:-}"
IPA_BUILD_ARTIFACT_PATH=""
if (( IOS_IN_SCOPE == 0 )); then
  log_skip "§11q iOS artifact checks SKIPPED — iOS is not in scope for this run. The iOS reporting destination is NOT verified. Run 'bash scripts/pre_release_check.sh --ios' on a macOS host with the IPA built before you ship an iOS release."
elif [[ -n "$FAKE_IP_BUILD" ]]; then
  if [[ "$FAKE_IP_BUILD" == ok ]]; then
    log_ok "iOS release build completed (test faked)"
    # Trust whatever artifacts are already on disk for §11q to
    # inspect. The test is responsible for laying down the IPA
    # before invoking the gate.
  elif [[ "$FAKE_IP_BUILD" == fail:* ]]; then
    log_err "iOS release build could not be produced: ${FAKE_IP_BUILD#fail:}. A broken iOS configuration just slipped past the previous gate, which read files rather than exercising them. Fix the iOS build so it produces an IPA before archiving."
  else
    log_err "PRE_RELEASE_GATE_FAKE_IP_BUILD has an unexpected value: $FAKE_IP_BUILD. The test-only hook must be 'ok' or 'fail:<error text>'."
  fi
else
  # Live mode: the gate does NOT invoke `flutter build ipa`
  # itself. The upstream CI workflow has already produced the
  # IPA at the canonical output path
  # (`build/ios/ipa/*.ipa`) — that is the right separation of
  # concerns. The gate's job is to verify the artifact, not
  # reproduce the build. If no IPA exists, the gate fails
  # (refusing to pass by default — the same rule §11r enforces
  # for Android seeds.txt / AAB).
  log_ok 'iOS artifact check expects an IPA at build/ios/ipa/*.ipa (produced by the upstream flutter build ipa invocation)'
fi

# Locate the produced IPA. Either `build/ios/ipa/*.ipa` (the
# canonical `flutter build ipa` output) or a custom path set by
# the upstream CI job. The gate accepts whichever exists.
for candidate in build/ios/ipa/*.ipa; do
  if [[ -f "$candidate" ]]; then
    IPA_BUILD_ARTIFACT_PATH="$candidate"
    break
  fi
done

if (( IOS_IN_SCOPE == 0 )); then
  : # iOS scoped out — already reported above as SKIPPED.
elif [[ -z "$IPA_BUILD_ARTIFACT_PATH" ]]; then
  log_err "iOS reporting destination cannot be verified: expected build output is missing — no IPA at build/ios/ipa/*.ipa. The iOS build either did not run or did not produce an IPA at the canonical path. Refusing to pass by default — pass-by-default when build output is absent is exactly the regression this check exists to prevent."
else
  if ! command -v unzip >/dev/null 2>&1; then
    log_err "iOS reporting destination cannot be verified: unzip is not on PATH. Install unzip and re-run — the artifact check needs it to inspect the produced IPA."
  else
    # The Dart front-end compiles `--dart-define=SENTRY_DSN=<value>`
    # into the App binary as a string constant. The string lives in
    # `Runner.app/Runner` (legacy Xcode build) or `App.framework/App`
    # (Flutter on iOS, the modern path). `unzip -l` shows the
    # central directory; we pipe the binary through `strings`-equivalent
    # grep. `tr` strips NULs so the grep matches across string
    # boundaries (the DSN may not be word-aligned).
    ipa_dsn_match=$(unzip -p "$IPA_BUILD_ARTIFACT_PATH" \
      'Runner.app/Runner' 2>/dev/null \
      | tr '\0' '\n' \
      | grep -E 'https://[A-Za-z0-9_-]+@[A-Za-z0-9.-]+/[0-9]+' \
      | head -1 \
      || true)
    if [[ -n "$ipa_dsn_match" ]]; then
      log_ok "iOS reporting destination is in the produced artifact (Runner.app/Runner contains a Sentry DSN string: ${ipa_dsn_match})"
    else
      # Fall back to App.framework/App (Flutter-on-iOS path). The
      # Dart front-end compiles to native code and embeds the DSN
      # there.
      app_dsn_match=$(unzip -p "$IPA_BUILD_ARTIFACT_PATH" \
        'Runner.app/Frameworks/App.framework/App' 2>/dev/null \
        | tr '\0' '\n' \
        | grep -E 'https://[A-Za-z0-9_-]+@[A-Za-z0-9.-]+/[0-9]+' \
        | head -1 \
        || true)
      if [[ -n "$app_dsn_match" ]]; then
        log_ok "iOS reporting destination is in the produced artifact (Runner.app/Frameworks/App.framework/App contains a Sentry DSN string: ${app_dsn_match})"
      else
        log_err "iOS reporting destination is absent: the produced IPA at $IPA_BUILD_ARTIFACT_PATH does not contain a Sentry DSN string in either Runner.app/Runner or Runner.app/Frameworks/App.framework/App. The iOS artifact would ship with no reporting destination and silently never report — iOS would appear monitored but produce nothing. Inspect the build invocation: --dart-define=SENTRY_DSN must reach the Dart front-end, which requires flutter build ipa (the supported mechanism), not a bespoke xcodebuild invocation. The empty-DSN runtime guard in lib/core/services/crash_reporting_service.dart is a defensive second line; the artifact check is the primary defense."
      fi
    fi
  fi
fi

# iOS: the Xcode project must keep dSYMs (COPY_PHASE_STRIP=NO and
# DEBUG_INFORMATION_FORMAT=dwarf-with-dsym on the Release config).
if [[ -f "$PBXPROJ" ]]; then
  if grep -qE 'COPY_PHASE_STRIP = NO' "$PBXPROJ" && \
     grep -qE '"dwarf-with-dsym"' "$PBXPROJ"; then
    log_ok "iOS Release config keeps dSYMs (COPY_PHASE_STRIP=NO + dwarf-with-dsym)"
  else
    log_err "iOS Release config does not keep dSYMs (need COPY_PHASE_STRIP=NO + DEBUG_INFORMATION_FORMAT=dwarf-with-dsym). Native stack frames will not symbolicate."
  fi
else
  log_err "ios/Runner.xcodeproj/project.pbxproj is missing — cannot verify iOS dSYM config."
fi

# ── 11r. Android notification protections must take effect in the
#       produced release artifact, not just the configuration files.
#
# The Android release build applies two configurations to prevent a
# known notification-schedule failure that floods the crash-reporting
# service in production:
#
#   (a) `android/app/proguard-rules.pro` keeps
#       `com.dexterous.flutterlocalnotifications.**` so R8 cannot
#       strip the Gson `TypeToken` generic that the plugin's
#       `loadScheduledNotifications()` reads back. Without the keep,
#       every Android schedule / cancel call throws
#       `Missing type parameter.` (flutter_local_notifications #2014)
#       and a cluster of in-workout timer alerts becomes a sustained
#       crash-report flood.
#
#   (b) `android/app/src/main/res/raw/keep.xml` keeps the five raw
#       sound resources used by `RawResourceAndroidNotificationSound()`
#       in `lib/core/utils/rest_notification_service.dart`. Without
#       the resource keep, R8's resource shrinker strips them from the
#       release APK and every schedule call throws
#       `PlatformException(invalid_sound, …)`, again producing a
#       crash-report flood in active workouts.
#
# The previous gate only verified the configuration text was present
# in the source files. Both protections can be silently bypassed by an
# edit to the configuration that does not take effect in the produced
# artifact (e.g. the wrong ProGuard rule, a typo in the package name,
# a R8 version that no longer honours the keep directive). This check
# inspects the artifact the release build produced, so the contract is
# verified at the level that actually reaches users.
#
# Both subchecks run only against release-build output and MUST fail
# (not pass by default) when expected output is missing — the
# acceptance criterion explicitly rejects "passes when absent" because
# a quiet pass would let a missing build hide a regression.
#
# Scoped out by `--ios` (or by auto-detection on a host with no Android
# SDK). Skipping is NOT the same as passing: the run's final verdict
# becomes PARTIAL and names Android as unverified.
echo ""
echo "  — Release-build artifact checks (§11r / §11s) —"

if (( ANDROID_IN_SCOPE == 0 )); then
  log_skip "§11r / §11s Android artifact checks SKIPPED — Android is not in scope for this run. The notification keep rules and the release build itself are NOT verified. Run 'bash scripts/pre_release_check.sh --android' on a host with the Android SDK before you ship an Android release."
else

# §11s first — the build must succeed. §11r reads its output. A
# build that does not complete makes both artifact checks
# meaningless, so we fail loudly here and let the §11r subchecks
# report "expected build output absent" so the reader can see both
# problems at once.
#
# `flutter build appbundle --release` is the canonical Android
# release invocation. When AAB is not the goal (e.g. the release is
# distributed as APK instead), `flutter build apk --release`
# produces the same R8 outputs (seeds.txt, mapping.txt) and an APK
# at `build/app/outputs/flutter-apk/app-release.apk` which is also
# a valid zip whose resource entries §11r can inspect. We try the
# AAB first; if it does not produce the artifact (older Flutter
# versions, or a release pipeline that only builds APK), fall back
# to the APK. Either is acceptable.
#
# `--dart-define=SENTRY_DSN=development` mirrors production shape
# without requiring a real secret on PATH. The Sentry upload step
# in pubspec.yaml's sentry_dart_plugin block requires SENTRY_DSN
# (and SENTRY_AUTH_TOKEN + SENTRY_PROJECT) to be present, but those
# come from the release workflow's env: block — not from a
# --dart-define on the build itself. We use the literal string
# `development` so any code path that checks the format of the DSN
# still works.
#
# `PRE_RELEASE_GATE_FAKE_BUILD` is a test-only hook: when set,
# §11s skips the actual `flutter build` and either reports success
# (`=ok`) or failure (`=fail:<error text>`) with the surfaced
# error. This lets the unit test inject green / red build results
# without paying the minute-long Flutter build cost on every CI run.
FAKE_BUILD="${PRE_RELEASE_GATE_FAKE_BUILD:-}"
BUILD_ARTIFACT_KIND=""
BUILD_ARTIFACT_PATH=""
BUILD_ERR_LOG=""
if [[ -n "$FAKE_BUILD" ]]; then
  # Test mode. Honour the hook; do not invoke flutter build.
  if [[ "$FAKE_BUILD" == ok ]]; then
    log_ok "release build completed (test faked)"
    # Trust whatever artifacts are already on disk for §11r to
    # inspect. The test is responsible for laying down the green /
    # red seeds.txt + AAB / APK before invoking the gate.
  elif [[ "$FAKE_BUILD" == fail:* ]]; then
    BUILD_ERR_LOG="${FAKE_BUILD#fail:}"
    log_err "release build could not be produced: $BUILD_ERR_LOG. A broken configuration change just slipped past the previous gate, which read files rather than exercising them. Fix the configuration changes so a release build completes successfully before archiving — do not ship a release whose configuration could not compile."
  else
    log_err "PRE_RELEASE_GATE_FAKE_BUILD has an unexpected value: $FAKE_BUILD. The test-only hook must be 'ok' or 'fail:<error text>'."
  fi
else
  if ! command -v flutter >/dev/null 2>&1; then
    log_err "flutter not found on PATH — the release build (§11s) cannot run. Install Flutter or invoke the gate from a machine with the toolchain."
  else
    echo "    Running flutter build appbundle --release (this can take several minutes)..."
    # Capture stderr separately so the underlying diagnostic is
    # surfaced verbatim when the build fails.
    if BUILD_ERR_LOG=$(flutter build appbundle --release \
          --dart-define=SENTRY_DSN=development 2>&1); then
      log_ok "release build (flutter build appbundle --release) completed"
    else
      log_err "release build could not be produced (flutter build appbundle --release exited non-zero). The build configuration has an error that the previous gate could not detect because it read files rather than exercising them. Underlying build output (verbatim — do not mask): $(echo "$BUILD_ERR_LOG" | tail -40 | tr '\n' ' ')"
    fi
  fi
fi

# Locate the produced artifact. §11r uses whichever exists.
# Either path is acceptable; AAB is the canonical release format
# for Play Store uploads. APK is the local-test fallback.
if [[ -f "build/app/outputs/bundle/release/app-release.aab" ]]; then
  BUILD_ARTIFACT_KIND="aab"
  BUILD_ARTIFACT_PATH="build/app/outputs/bundle/release/app-release.aab"
elif [[ -f "build/app/outputs/flutter-apk/app-release.apk" ]]; then
  BUILD_ARTIFACT_KIND="apk"
  BUILD_ARTIFACT_PATH="build/app/outputs/flutter-apk/app-release.apk"
fi

SEEDS_PATH="android/app/build/outputs/mapping/release/seeds.txt"

# §11r (a) — code protection. R8 writes `seeds.txt` recording every
# class matched by a `-keep` rule. If the kept notification classes
# are absent, the protection did not apply. The file is text; a
# simple grep is the canonical signal.
if [[ -f "$SEEDS_PATH" ]]; then
  if grep -q 'com\.dexterous\.flutterlocalnotifications\.' "$SEEDS_PATH"; then
    log_ok "Android notification code protection is in the produced artifact (R8 seeds.txt contains com.dexterous.flutterlocalnotifications.**)"
  else
    log_err "Android notification code protection did not apply: the release build's R8 seeds.txt at $SEEDS_PATH does not contain any com.dexterous.flutterlocalnotifications.** entry. ProGuard was meant to keep these classes so flutter_local_notifications #2014 (TypeToken generic stripped) cannot break every Android schedule/cancel call in release. Without the keep, every notification schedule call will throw Missing type parameter. and flood the crash-reporting service with a notification-failure signature that takes weeks to surface from telemetry. Restore the -keep directive in android/app/proguard-rules.pro and re-run."
  fi
else
  log_err "Android notification code protection cannot be verified: expected build output is missing — $SEEDS_PATH does not exist. The release build either did not run (failed in §11s above) or did not produce R8 mapping output. Refusing to pass by default — pass-by-default when build output is absent is exactly the regression this check exists to prevent."
fi

# §11r (b) — resource protection. The `keep.xml` declarations must
# survive into the produced AAB / APK. Extract the expected raw
# resource names from keep.xml (one declaration per
# `@raw/<name>`), then verify each is present in the artifact's
# zip central directory.
if [[ -f "$BUILD_ARTIFACT_PATH" ]]; then
  if ! command -v unzip >/dev/null 2>&1; then
    log_err "Android notification resource protection cannot be verified: unzip is not on PATH. Install unzip and re-run — the resource-protection check needs it to inspect the produced $BUILD_ARTIFACT_KIND."
  else
    # Parse keep.xml for `@raw/<name>` declarations. The file uses
    # `tools:keep="@mipmap/ic_launcher,@raw/boxing_bell,..."` so a
    # regex over `@raw/([a-z0-9_]+)` is sufficient.
    expected_raw_resources=$(grep -oE '@raw/[a-z0-9_]+' android/app/src/main/res/raw/keep.xml 2>/dev/null | sed 's:@raw/::' | sort -u || true)
    if [[ -z "$expected_raw_resources" ]]; then
      log_err "Android notification resource protection cannot be verified: android/app/src/main/res/raw/keep.xml does not declare any @raw/* resources. Either the keep file is missing or its declarations were removed; without them, R8's resource shrinker strips the timer-alert sounds and every Android notification schedule call throws PlatformException(invalid_sound, …)."
    else
      missing_resources=""
      while IFS= read -r res; do
        # The zip entry path is `res/raw/<name>` (no extension).
        # `unzip -l` prefixes the path with whitespace, so a word
        # boundary is the simplest way to match `res/raw/<name>` as
        # a path component. Using `\<` / `\>` ensures we match
        # `res/raw/boxing_bell` but not `res/raw/boxing_belle`.
        if ! unzip -l "$BUILD_ARTIFACT_PATH" 2>/dev/null \
             | grep -qE "(^|[[:space:]]|/)res/raw/${res}([[:space:]]|\$)"; then
          missing_resources+="$res "
        fi
      done <<< "$expected_raw_resources"
      if [[ -z "$missing_resources" ]]; then
        log_ok "Android notification resource protection is in the produced artifact ($BUILD_ARTIFACT_KIND contains all keep.xml-declared raw resources)"
      else
        log_err "Android notification resource protection did not apply: the produced $BUILD_ARTIFACT_KIND at $BUILD_ARTIFACT_PATH is missing the raw resource(s) declared in keep.xml: $missing_resources. Without the keep, R8's resource shrinker strips the timer-alert sounds from the release APK and every Android notification schedule call throws PlatformException(invalid_sound, …), flooding the crash-reporting service with a notification-failure signature that takes weeks to surface from telemetry. Restore the @raw/<name> declarations in android/app/src/main/res/raw/keep.xml and re-run."
      fi
    fi
  fi
else
  log_err "Android notification resource protection cannot be verified: expected build output is missing — $BUILD_ARTIFACT_KIND not produced at $BUILD_ARTIFACT_PATH. The release build either did not run (failed in §11s above) or did not produce an AAB/APK at the canonical path. Refusing to pass by default — pass-by-default when build output is absent is exactly the regression this check exists to prevent."
fi

fi  # end ANDROID_IN_SCOPE guard (§11r / §11s)

# ── 12–13. Analyzer and test suite (the actual code gate) ────────────────────
echo ""
if [[ $SKIP_HEAVY -eq 1 ]]; then
  log_warn "Skipping flutter analyze and flutter test (--fast). Do NOT archive from a --fast run."
else
  if ! command -v flutter >/dev/null 2>&1; then
    log_err "flutter not found on PATH — cannot run analyzer or tests."
  else
    echo "  — flutter analyze —"
    # `--no-fatal-infos` keeps errors AND warnings blocking while letting
    # style-level infos through. Those infos are overwhelmingly lint
    # preferences in `test/` (leading underscores on locals, deprecated
    # test-only APIs) that do not affect shipped code. Gating the release
    # on them meant the gate was permanently red, which trains people to
    # ignore it — a gate nobody trusts blocks nothing.
    #
    # Errors and warnings still fail here. If you want the infos clean
    # too, run plain `flutter analyze` yourself; do not re-tighten this
    # line without clearing them first.
    if flutter analyze --no-fatal-infos; then
      log_ok "Analyzer passed (no errors, no warnings)"
    else
      log_err "flutter analyze reported errors or warnings. Fix them before archiving. (Style-level infos are not fatal here — see the comment in this script.)"
    fi

    echo ""
    echo "  — flutter test —"
    if flutter test; then
      log_ok "Full test suite passed"
    else
      log_err "flutter test failed. A red suite never ships."
    fi
  fi
fi

# ── 14. The watchOS package's suite (swift test) ─────────────────────────────
# The watch engine, its append-only store, its sensors and the capture
# contract's wrist half are proven by `swift test` in watch/watchos, which
# `flutter test` never runs (Stats PR 2, D-144). A red suite blocks exactly as
# a red `flutter test` does.
#
# The package imports Apple frameworks (Combine, SwiftUI), so it builds only on
# macOS. A host that is not a Mac, or has no usable Swift toolchain (`swift
# --version` fails — the /usr/bin/swift stub of a Mac without Xcode tools
# does), cannot run it: that is reported as a warning, never passed silently
# and never failed, because that host cannot build the watch app either.
echo ""
if [[ $SKIP_HEAVY -eq 1 ]]; then
  log_warn "Skipping swift test for watch/watchos (--fast). Do NOT archive from a --fast run."
elif [[ "$(uname -s)" != "Darwin" ]] || ! swift --version >/dev/null 2>&1; then
  log_warn "swift test for watch/watchos SKIPPED: this host has no usable Swift toolchain for the watchOS package (it needs macOS with Xcode). Run the gate on a Mac before shipping the watch app."
else
  echo "  — swift test (watch/watchos) —"
  if (cd watch/watchos && swift test); then
    log_ok "watchOS package suite passed (swift test in watch/watchos)"
  else
    log_err "swift test failed in watch/watchos. The watch engine's suite is red, and a red suite never ships."
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────"
if [[ $errors -eq 0 ]]; then
  if (( ${#skipped_platforms[@]} > 0 )); then
    # A scoped run is a PARTIAL pass. Saying "all checks passed" here
    # would let a half-verified release read as fully verified — the
    # exact pass-by-default failure mode the artifact checks exist to
    # prevent, just relocated to the summary line.
    echo "  PARTIAL PASS — every in-scope check passed, but not every platform ran."
    echo ""
    echo "  NOT verified on this host: ${skipped_platforms[*]}"
    for p in "${skipped_platforms[@]}"; do
      case "$p" in
        iOS)     echo "    • iOS      → run 'bash scripts/pre_release_check.sh --ios' on macOS with build/ios/ipa/*.ipa present" ;;
        Android) echo "    • Android  → run 'bash scripts/pre_release_check.sh --android' on a host with the Android SDK" ;;
      esac
    done
    echo ""
    echo "  Do NOT ship a platform whose sections did not run."
    echo ""
    exit 0
  fi
  echo "  All checks passed (iOS + Android). Ready to Archive."
  echo ""
  echo "  Next step: open Xcode → Product → Archive"
  echo ""
  exit 0
else
  echo "  $errors blocking error(s) found. Fix the issues marked ✗ above before archiving."
  echo ""
  echo "  Failed checks:"
  for msg in "${failed_checks[@]}"; do
    echo "    ✗  $msg"
  done
  echo ""
  exit 1
fi