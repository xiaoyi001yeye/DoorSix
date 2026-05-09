#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  RELEASE_HOST
  RELEASE_USER
  RELEASE_REMOTE_DIR
  RELEASE_PUBLIC_BASE_URL
  APK_PATH
  VERSION_NAME
  VERSION_CODE
  RELEASE_NOTES_FILE
)

for name in "${required_vars[@]}"; do
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
done

if [ ! -f "$APK_PATH" ]; then
  echo "APK_PATH does not exist: $APK_PATH" >&2
  exit 1
fi

if [ ! -f "$RELEASE_NOTES_FILE" ]; then
  echo "Release notes file does not exist: $RELEASE_NOTES_FILE" >&2
  exit 1
fi

RELEASE_CHANNEL="${RELEASE_CHANNEL:-stable}"
RELEASE_ENVIRONMENT="${RELEASE_ENVIRONMENT:-prod}"
FORCE_UPDATE="${FORCE_UPDATE:-false}"
MIN_SUPPORTED_VERSION_CODE="${MIN_SUPPORTED_VERSION_CODE:-1}"
ROLLOUT_PERCENTAGE="${ROLLOUT_PERCENTAGE:-100}"
GIT_TAG="${GIT_TAG:-android-v${VERSION_NAME}+${VERSION_CODE}}"
COMMIT_SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
RUN_ID="${GITHUB_RUN_ID:-local-$(date +%Y%m%d%H%M%S)}"

version_key="${VERSION_NAME}+${VERSION_CODE}"
apk_name="door_six-${version_key}-${RELEASE_CHANNEL}.apk"
sha_name="door_six-${version_key}-${RELEASE_CHANNEL}.sha256"
manifest_name="release-android-${version_key}.json"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

cp "$APK_PATH" "$work_dir/$apk_name"
file_size="$(wc -c < "$work_dir/$apk_name" | tr -d ' ')"
sha256="$(shasum -a 256 "$work_dir/$apk_name" | awk '{print $1}')"
printf '%s  %s\n' "$sha256" "$apk_name" > "$work_dir/$sha_name"

download_url="${RELEASE_PUBLIC_BASE_URL%/}/${version_key}/${apk_name}"
published_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export RELEASE_CHANNEL RELEASE_ENVIRONMENT FORCE_UPDATE MIN_SUPPORTED_VERSION_CODE
export ROLLOUT_PERCENTAGE GIT_TAG COMMIT_SHA VERSION_NAME VERSION_CODE
export DOWNLOAD_URL="$download_url"
export FILE_SIZE="$file_size"
export SHA256="$sha256"
export PUBLISHED_AT="$published_at"

node - "$RELEASE_NOTES_FILE" "$work_dir/$manifest_name" <<'NODE'
const fs = require('node:fs');
const [
  notesFile,
  manifestFile,
] = process.argv.slice(2);

const rawNotes = fs.readFileSync(notesFile, 'utf8');
const notes = rawNotes
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line.startsWith('- ') || line.startsWith('* '))
  .map((line) => line.slice(2).trim())
  .filter(Boolean);

const env = process.env;
const versionName = env.VERSION_NAME;
const versionCode = Number(env.VERSION_CODE);
const manifest = {
  id: `android-${env.RELEASE_CHANNEL}-${versionCode}`,
  platform: 'android',
  channel: env.RELEASE_CHANNEL,
  environment: env.RELEASE_ENVIRONMENT,
  versionName,
  versionCode,
  minSupportedVersionCode: Number(env.MIN_SUPPORTED_VERSION_CODE),
  forceUpdate: env.FORCE_UPDATE === 'true',
  status: 'active',
  title: `发现新版本 ${versionName}`,
  releaseNotes: notes.length ? notes : [rawNotes.trim()].filter(Boolean),
  downloadUrl: env.DOWNLOAD_URL,
  fileSizeBytes: Number(env.FILE_SIZE),
  sha256: env.SHA256,
  gitTag: env.GIT_TAG,
  commitSha: env.COMMIT_SHA,
  publishedAt: env.PUBLISHED_AT,
  rollout: {
    enabled: true,
    percentage: Number(env.ROLLOUT_PERCENTAGE),
  },
};
fs.writeFileSync(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

ssh_target="${RELEASE_USER}@${RELEASE_HOST}"
remote_tmp="${RELEASE_REMOTE_DIR%/}/.tmp/${RUN_ID}-${version_key}"
remote_version_dir="${RELEASE_REMOTE_DIR%/}/android/${version_key}"
remote_manifest_dir="${RELEASE_REMOTE_DIR%/}/manifests"

ssh "$ssh_target" "mkdir -p '$remote_tmp' '$remote_version_dir' '$remote_manifest_dir'"
scp "$work_dir/$apk_name" "$work_dir/$sha_name" "$work_dir/$manifest_name" "$ssh_target:$remote_tmp/"
ssh "$ssh_target" "cd '$remote_tmp' && sha256sum -c '$sha_name'"
ssh "$ssh_target" "\
  set -euo pipefail; \
  mv '$remote_tmp/$apk_name' '$remote_version_dir/$apk_name'; \
  mv '$remote_tmp/$sha_name' '$remote_version_dir/$sha_name'; \
  mv '$remote_tmp/$manifest_name' '$remote_manifest_dir/$manifest_name'; \
  cp '$remote_manifest_dir/$manifest_name' '$remote_manifest_dir/latest-android-${RELEASE_CHANNEL}.json'; \
  rmdir '$remote_tmp'"

curl --fail --location --head "$download_url" >/dev/null

{
  echo "### DoorSix Android release"
  echo
  echo "- Version: ${version_key}"
  echo "- Tag: ${GIT_TAG}"
  echo "- APK: ${download_url}"
  echo "- Size: ${file_size} bytes"
  echo "- SHA-256: ${sha256}"
  echo "- Manifest: ${remote_manifest_dir}/${manifest_name}"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
