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

# 11b. No microphone declaration (app never records audio)
if grep -q 'NSMicrophoneUsageDescription' "$INFO_PLIST"; then
  log_err "Info.plist declares microphone usage. The app does not record audio; remove the key."
else
  log_ok "No microphone declaration in Info.plist"
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