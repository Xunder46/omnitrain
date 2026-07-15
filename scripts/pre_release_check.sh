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
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PUBSPEC="pubspec.yaml"
LAST_BUILD_FILE="docs/releases/.last-released-build"
INFO_PLIST="ios/Runner/Info.plist"
PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
PRIVACY_MANIFEST="ios/Runner/PrivacyInfo.xcprivacy"

SKIP_HEAVY=0
if [[ "${1:-}" == "--fast" ]]; then
  SKIP_HEAVY=1
fi

errors=0
failed_checks=()

log_ok()   { echo "  ✓  $*"; }
log_err()  { echo "  ✗  $*"; failed_checks+=("$*"); (( errors++ )) || true; }
log_warn() { echo "  ⚠  $*"; }

# ── Guard: must be run from repo root ───────────────────────────────────────
if [[ ! -f "$PUBSPEC" ]]; then
  echo "ERROR: $PUBSPEC not found. Run this script from the repo root."
  exit 1
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
# (Excludes RunnerTests targets)
bundle_ids_count=$(grep 'PRODUCT_BUNDLE_IDENTIFIER' "$PBXPROJ" \
  | grep -v RunnerTests \
  | grep -oE '= [^;]+;' \
  | sed 's/= //; s/;//; s/[[:space:]]//g' \
  | sort -u \
  | wc -l \
  | tr -d ' ')

if [[ "$bundle_ids_count" -eq 1 ]]; then
  bundle_id=$(grep 'PRODUCT_BUNDLE_IDENTIFIER' "$PBXPROJ" \
    | grep -v RunnerTests \
    | grep -oE '= [^;]+;' \
    | sed 's/= //; s/;//; s/[[:space:]]//g' \
    | head -1)
  log_ok "Bundle identifier is consistent across all configs: $bundle_id"
else
  log_err "Inconsistent PRODUCT_BUNDLE_IDENTIFIER across build configurations. All Runner configs must use the same bundle ID."
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

# 11f. iPhone-only: no build config may target iPad (one-way door once shipped)
bad_family=$(grep 'TARGETED_DEVICE_FAMILY' "$PBXPROJ" | grep -vE '= *"?1"? *;' || true)
if [[ -n "$bad_family" ]]; then
  log_err "A build configuration targets iPad (TARGETED_DEVICE_FAMILY != 1). v1 ships iPhone-only; iPad support cannot be removed after shipping."
else
  log_ok "All build configurations are iPhone-only"
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

# The sentry_dart_plugin pubspec block must declare the Android mapping
# upload hook. A future refactor that drops the block from pubspec.yaml
# must fail the gate.
if grep -q 'uploadSentryMapping' "$PUBSPEC"; then
  log_ok "Android mapping upload hook (:app:uploadSentryMapping) is configured in pubspec.yaml"
else
  log_err "Android mapping upload hook (uploadSentryMapping) is missing from pubspec.yaml. JVM stack traces will not symbolicate."
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

# ── 12–13. Analyzer and test suite (the actual code gate) ────────────────────
echo ""
if [[ $SKIP_HEAVY -eq 1 ]]; then
  log_warn "Skipping flutter analyze and flutter test (--fast). Do NOT archive from a --fast run."
else
  if ! command -v flutter >/dev/null 2>&1; then
    log_err "flutter not found on PATH — cannot run analyzer or tests."
  else
    echo "  — flutter analyze —"
    if flutter analyze; then
      log_ok "Analyzer passed"
    else
      log_err "flutter analyze failed. Fix analyzer errors before archiving."
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

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────"
if [[ $errors -eq 0 ]]; then
  echo "  All checks passed. Ready to Archive."
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