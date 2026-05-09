#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/generate_android_release_keystore.sh [--force]

Generates a local Android release keystore and a GitHub Secrets value file.
The generated files are written under .local/secrets/android-signing, which
must never be committed.
EOF
}

force=false
if [ "${1:-}" = "--force" ]; then
  force=true
elif [ "$#" -gt 0 ]; then
  usage
  exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_dir/.local/secrets/android-signing"
keystore_path="$output_dir/doorsix-release.jks"
secrets_path="$output_dir/github-secrets.env"
alias_name="doorsix"

if [ -e "$keystore_path" ] && [ "$force" != true ]; then
  echo "Keystore already exists: $keystore_path" >&2
  echo "Re-run with --force only if you intentionally want a new signing key." >&2
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 36 | tr -d '\n'
  else
    LC_ALL=C tr -dc 'A-Za-z0-9_@%+=:,.~-' </dev/urandom | head -c 48
  fi
}

base64_file() {
  if base64 --help 2>&1 | grep -q -- '-w'; then
    base64 -w 0 "$1"
  else
    base64 <"$1" | tr -d '\n'
  fi
}

require_command keytool
require_command base64

mkdir -p "$output_dir"
chmod 700 "$repo_dir/.local/secrets" "$output_dir" 2>/dev/null || true

keystore_password="$(random_secret)"
key_password="$(random_secret)"

rm -f "$keystore_path" "$secrets_path"
keytool -genkeypair -v \
  -keystore "$keystore_path" \
  -storetype JKS \
  -alias "$alias_name" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "$keystore_password" \
  -keypass "$key_password" \
  -dname "CN=DoorSix, OU=DoorSix, O=DoorSix, L=Unknown, ST=Unknown, C=US"

keystore_base64="$(base64_file "$keystore_path")"
cert_sha256="$(keytool -list -v \
  -keystore "$keystore_path" \
  -alias "$alias_name" \
  -storepass "$keystore_password" |
  awk -F': ' '/SHA256:/ { print $2; exit }')"

cat >"$secrets_path" <<EOF
ANDROID_KEYSTORE_BASE64=$keystore_base64
ANDROID_KEYSTORE_PASSWORD=$keystore_password
ANDROID_KEY_ALIAS=$alias_name
ANDROID_KEY_PASSWORD=$key_password
EOF

chmod 600 "$keystore_path" "$secrets_path"

cat <<EOF
Generated Android release signing files.

Keystore: $keystore_path
GitHub Secrets values: $secrets_path
Signer certificate SHA-256: $cert_sha256

Add the four values from github-secrets.env to GitHub repository Secrets.
Keep doorsix-release.jks backed up somewhere private. If it is lost, existing
users cannot receive seamless APK overwrite updates signed by this key.
EOF
