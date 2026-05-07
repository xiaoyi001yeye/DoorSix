#!/usr/bin/env bash
set -euo pipefail

if [ ! -d android ]; then
  flutter create --platforms=android --project-name door_six .
fi

manifest="android/app/src/main/AndroidManifest.xml"
ensure_permission() {
  local permission="$1"

  if [ -f "$manifest" ] && ! grep -q "android.permission.${permission}" "$manifest"; then
    perl -0pi -e "s/(^\\s*<application\\b)/    <uses-permission android:name=\"android.permission.${permission}\" \\/>\\n\$1/m" "$manifest"
  fi
}

ensure_permission INTERNET
ensure_permission ACCESS_NETWORK_STATE

if [ -f "$manifest" ] && ! grep -q 'android:usesCleartextTraffic=' "$manifest"; then
  perl -0pi -e 's/<application\b/<application android:usesCleartextTraffic="true"/s' "$manifest"
fi
