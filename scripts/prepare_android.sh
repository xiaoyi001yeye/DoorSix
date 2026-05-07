#!/usr/bin/env bash
set -euo pipefail

if [ ! -d android ]; then
  flutter create --platforms=android --project-name door_six .
fi

manifest="android/app/src/main/AndroidManifest.xml"
if [ -f "$manifest" ] && ! grep -q 'android:usesCleartextTraffic=' "$manifest"; then
  perl -0pi -e 's/<application(\s+)/<application$1        android:usesCleartextTraffic="true"\n/s' "$manifest"
fi
