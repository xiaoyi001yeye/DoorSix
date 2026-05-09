#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <versionName+versionCode> <release notes>" >&2
  echo "Example: $0 0.2.0+2 \"优化联机稳定性；修复重连后状态不同步\"" >&2
}

if [ "$#" -lt 2 ]; then
  usage
  exit 1
fi

target_version="$1"
shift
release_notes="$*"

if [[ ! "$target_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]; then
  usage
  exit 1
fi

if [ -z "${release_notes//[[:space:]]/}" ]; then
  echo "Release notes cannot be empty." >&2
  exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

current_json="$(node scripts/print_flutter_version.js)"
current_version="$(node -e 'const v = JSON.parse(process.argv[1]); console.log(v.pubspecVersion)' "$current_json")"
current_code="$(node -e 'const v = JSON.parse(process.argv[1]); console.log(v.versionCode)' "$current_json")"
target_code="${BASH_REMATCH[4]}"

if [ "$target_code" -le "$current_code" ]; then
  echo "Target versionCode ${target_code} must be greater than current ${current_code} (${current_version})." >&2
  exit 1
fi

echo "Current git status:"
git status --short
echo
echo "Preparing Android release ${target_version}"

perl -0pi -e "s/^version:\\s*[^\\n]+/version: ${target_version}/m" pubspec.yaml

notes_file="docs/release-notes/android/${target_version}.md"
mkdir -p "$(dirname "$notes_file")"
{
  echo "# DoorSix Android ${target_version}"
  echo
  IFS='；;' read -ra items <<< "$release_notes"
  for item in "${items[@]}"; do
    trimmed="$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -n "$trimmed" ]; then
      echo "- $trimmed"
    fi
  done
} > "$notes_file"

if command -v flutter >/dev/null 2>&1; then
  flutter pub get
  flutter analyze
  flutter test
else
  echo "Warning: flutter is not available on PATH; skipping local Flutter checks." >&2
fi

git add -A
git commit -m "release: android ${target_version}"
git push

echo "Release commit pushed. CI will build, tag, upload APK, and update latest manifest."
