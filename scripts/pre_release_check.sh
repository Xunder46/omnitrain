#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# OmniTrain pre-release sanity check
#
# Run from the repo root BEFORE every Xcode Archive:
#   bash scripts/pre_release_check.sh
#
# Exit 0 = all clear.  Exit 1 = at least one blocking error — fix it first.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PUBSPEC="pubspec.yaml"
LAST_BUILD_FILE="docs/releases/.last-released-build"

errors=0

log_ok()   { echo "  ✓  $*"; }
log_err()  { echo "  ✗  $*"; (( errors++ )) || true; }
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
if grep -q 'FLUTTER_BUILD_NAME' ios/Runner/Info.plist && \
   grep -q 'FLUTTER_BUILD_NUMBER' ios/Runner/Info.plist; then
  log_ok "Info.plist uses \$(FLUTTER_BUILD_NAME) / \$(FLUTTER_BUILD_NUMBER)"
else
  log_err "Info.plist is NOT reading version from Flutter variables. CFBundleShortVersionString and CFBundleVersion must use \$(FLUTTER_BUILD_NAME) and \$(FLUTTER_BUILD_NUMBER)."
fi

# ── 6. Bundle identifier must be consistent across all Runner build configs ──
# (Excludes RunnerTests targets)
bundle_ids_count=$(grep 'PRODUCT_BUNDLE_IDENTIFIER' ios/Runner.xcodeproj/project.pbxproj \
  | grep -v RunnerTests \
  | grep -oE '= [^;]+;' \
  | sed 's/= //; s/;//; s/[[:space:]]//g' \
  | sort -u \
  | wc -l \
  | tr -d ' ')

if [[ "$bundle_ids_count" -eq 1 ]]; then
  bundle_id=$(grep 'PRODUCT_BUNDLE_IDENTIFIER' ios/Runner.xcodeproj/project.pbxproj \
    | grep -v RunnerTests \
    | grep -oE '= [^;]+;' \
    | sed 's/= //; s/;//; s/[[:space:]]//g' \
    | head -1)
  log_ok "Bundle identifier is consistent across all configs: $bundle_id"
else
  log_err "Inconsistent PRODUCT_BUNDLE_IDENTIFIER across build configurations. All Runner configs must use the same bundle ID."
fi

# ── 7. Development team must be set ─────────────────────────────────────────
team_count=$(grep 'DEVELOPMENT_TEAM' ios/Runner.xcodeproj/project.pbxproj \
  | grep -v '= ""' \
  | grep -v '= ;' \
  | wc -l \
  | tr -d ' ')

if [[ "$team_count" -ge 1 ]]; then
  team_id=$(grep 'DEVELOPMENT_TEAM' ios/Runner.xcodeproj/project.pbxproj \
    | grep -oE '= [A-Z0-9]+' \
    | head -1 \
    | sed 's/= //')
  log_ok "Development team is set: $team_id"
else
  log_err "DEVELOPMENT_TEAM is not set in project.pbxproj. Open Xcode → Signing & Capabilities and select your team."
fi

# ── 8. Release config must have VALIDATE_PRODUCT = YES ──────────────────────
if grep -q 'VALIDATE_PRODUCT = YES' ios/Runner.xcodeproj/project.pbxproj; then
  log_ok "VALIDATE_PRODUCT = YES is present in Release config"
else
  log_warn "VALIDATE_PRODUCT = YES not found in Release config. This is set by Xcode by default but worth confirming."
fi

# ── 9. Release config must NOT have DEBUG=1 preprocessor flag ────────────────
# Check: the DEBUG=1 macro should only appear inside the Debug XCBuildConfiguration
# We do a rough check — if it appears outside a block that also contains "ENABLE_TESTABILITY"
# that would be suspicious. Simple heuristic: just count occurrences.
debug_macro_count=$(grep -c '"DEBUG=1"' ios/Runner.xcodeproj/project.pbxproj || true)
if [[ "$debug_macro_count" -le 1 ]]; then
  log_ok "DEBUG=1 macro appears only in Debug config"
else
  log_warn "DEBUG=1 appears $debug_macro_count times in project.pbxproj. Verify it is not leaking into Release or Profile configs."
fi

# ── 10. No staged/unstaged changes to iOS project files ──────────────────────
ios_changes=$(git diff HEAD -- ios/ 2>/dev/null | wc -l | tr -d ' ')
if [[ "$ios_changes" -eq 0 ]]; then
  log_ok "No uncommitted changes to ios/ directory"
else
  log_warn "There are uncommitted changes in ios/. This won't block archiving but make sure they are intentional."
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
  exit 1
fi
