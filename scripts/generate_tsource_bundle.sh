#!/usr/bin/env bash

# OmniTrain grounding bundle generator (.tsource)
#
# Purpose:
# - Collect source code, unit tests, docs, and settings/deployment files.
# - Exclude plan docs and generated/binary artifacts.
# - Emit one text bundle for LLM grounding.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./scripts/generate_tsource_bundle.sh [output_path]

Description:
  Builds a single .tsource text bundle for LLM grounding.
  Includes source code, unit tests, documentation (excluding plan files),
  and settings/deployment files.

Default output path:
  ./omnitrain-grounding.tsource
EOF
  exit 0
fi

OUTPUT_PATH="${1:-$ROOT_DIR/omnitrain-grounding.tsource}"

if [[ "$OUTPUT_PATH" != /* ]]; then
  OUTPUT_PATH="$PWD/$OUTPUT_PATH"
fi

TMP_CANDIDATES="$(mktemp)"
TMP_UNIQUE="$(mktemp)"
TMP_FINAL="$(mktemp)"

cleanup() {
  rm -f "$TMP_CANDIDATES" "$TMP_UNIQUE" "$TMP_FINAL"
}
trap cleanup EXIT

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_text_file() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    return 0
  fi
  LC_ALL=C grep -Iq . "$file"
}

is_excluded_relpath() {
  local rel="$1"
  local lower
  lower="$(to_lower "$rel")"

  case "$lower" in
    .git/*|.dart_tool/*|build/*|ios/build/*|macos/build/*|linux/build/*|windows/build/*|android/.gradle/*)
      return 0
      ;;
    ios/pods/*|macos/pods/*|ios/flutter/appframeworkinfo.plist|ios/flutter/flutter.framework/*|ios/flutter/flutter.podspec)
      return 0
      ;;
    ios/flutter/ephemeral/*|macos/flutter/ephemeral/*|android/app/build/*|web/icons/icon-*maskable*.png)
      return 0
      ;;
    native_assets/*|test_cache/*|.vscode/*|.idea/*|.ds_store)
      return 0
      ;;
    assets/icon/*|assets/sounds/*)
      return 0
      ;;
    *.ipa|*.a|*.so|*.dylib|*.jar|*.class|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.mp3|*.wav|*.ogg|*.ttf|*.otf|*.z|*.zip)
      return 0
      ;;
  esac

  if [[ "$lower" == *"/plans/"* ]]; then
    return 0
  fi

  if [[ "$lower" == *plan*.md ]]; then
    return 0
  fi

  return 1
}

classify_file() {
  local rel="$1"
  local lower
  lower="$(to_lower "$rel")"

  case "$lower" in
    test/*)
      printf '%s' "unit-test"
      return
      ;;
    *.md)
      printf '%s' "documentation"
      return
      ;;
    pubspec.yaml|pubspec.lock|analysis_options.yaml|.metadata|.gitignore|.github/workflows/*)
      printf '%s' "settings-deployment"
      return
      ;;
    *.gradle|*.gradle.kts|*.properties|*podfile|*.plist|*.xcconfig|*.pbxproj|*.entitlements|*/cmakelists.txt|web/manifest.json|android/app/src/main/androidmanifest.xml)
      printf '%s' "settings-deployment"
      return
      ;;
  esac

  printf '%s' "source"
}

collect_dir_files() {
  local dir="$1"
  [[ -d "$ROOT_DIR/$dir" ]] || return 0

  while IFS= read -r -d '' abs; do
    printf '%s\n' "${abs#$ROOT_DIR/}" >> "$TMP_CANDIDATES"
  done < <(find "$ROOT_DIR/$dir" -type f -print0)
}

collect_docs_markdown() {
  while IFS= read -r -d '' abs; do
    printf '%s\n' "${abs#$ROOT_DIR/}" >> "$TMP_CANDIDATES"
  done < <(
    find "$ROOT_DIR" \
      \( -path "$ROOT_DIR/.git" -o -path "$ROOT_DIR/.dart_tool" -o -path "$ROOT_DIR/build" -o -path "$ROOT_DIR/ios/build" -o -path "$ROOT_DIR/macos/build" -o -path "$ROOT_DIR/ios/Pods" -o -path "$ROOT_DIR/macos/Pods" -o -path "$ROOT_DIR/native_assets" -o -path "$ROOT_DIR/test_cache" \) -prune \
      -o -type f \( -name '*.md' -o -name '*.MD' \) -print0
  )
}

collect_root_files() {
  local rel
  for rel in \
    "README.md" \
    "pubspec.yaml" \
    "pubspec.lock" \
    "analysis_options.yaml" \
    ".metadata" \
    ".gitignore"; do
    if [[ -f "$ROOT_DIR/$rel" ]]; then
      printf '%s\n' "$rel" >> "$TMP_CANDIDATES"
    fi
  done
}

collect_dir_files "lib"
collect_dir_files "test"
collect_dir_files "scripts"
collect_dir_files "assets"
collect_dir_files "android"
collect_dir_files "ios"
collect_dir_files "macos"
collect_dir_files "linux"
collect_dir_files "windows"
collect_dir_files "web"
collect_dir_files ".github"
collect_docs_markdown
collect_root_files

LC_ALL=C sort -u "$TMP_CANDIDATES" > "$TMP_UNIQUE"

while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  is_excluded_relpath "$rel" && continue

  abs="$ROOT_DIR/$rel"
  [[ -f "$abs" ]] || continue
  is_text_file "$abs" || continue

  printf '%s\n' "$rel" >> "$TMP_FINAL"
done < "$TMP_UNIQUE"

LC_ALL=C sort -u "$TMP_FINAL" -o "$TMP_FINAL"

FILE_COUNT="$(wc -l < "$TMP_FINAL" | tr -d ' ')"
GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$(dirname "$OUTPUT_PATH")"

{
  echo "# OmniTrain TSource Bundle"
  echo "generated_at_utc: $GENERATED_AT"
  echo "repository_root: $ROOT_DIR"
  echo "included_files: $FILE_COUNT"
  echo "notes:"
  echo "- Plan files are excluded (paths containing /plans/ and filenames matching *plan*.md)."
  echo "- Binary and generated artifacts are excluded."
  echo
  echo "## Manifest"

  while IFS= read -r rel; do
    category="$(classify_file "$rel")"
    echo "[$category] $rel"
  done < "$TMP_FINAL"

  echo
  echo "## Files"

  while IFS= read -r rel; do
    abs="$ROOT_DIR/$rel"
    echo "===== BEGIN FILE: $rel ====="
    cat "$abs"
    echo
    echo "===== END FILE: $rel ====="
    echo
  done < "$TMP_FINAL"
} > "$OUTPUT_PATH"

echo "Bundle created: $OUTPUT_PATH"
echo "Included files: $FILE_COUNT"
