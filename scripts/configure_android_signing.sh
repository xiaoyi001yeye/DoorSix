#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

required="${REQUIRE_ANDROID_SIGNING:-false}"
secrets=(
  ANDROID_KEYSTORE_BASE64
  ANDROID_KEYSTORE_PASSWORD
  ANDROID_KEY_ALIAS
  ANDROID_KEY_PASSWORD
)

missing=()
present=0
for secret in "${secrets[@]}"; do
  if [ -n "${!secret:-}" ]; then
    present=$((present + 1))
  else
    missing+=("$secret")
  fi
done

if [ "$present" -eq 0 ]; then
  if [ "$required" = "true" ]; then
    echo "Android release signing is required, but signing secrets are missing." >&2
    printf 'Missing: %s\n' "${missing[*]}" >&2
    exit 1
  fi
  echo "Android signing secrets are not configured; skipping release signing setup."
  exit 0
fi

if [ "$present" -ne "${#secrets[@]}" ]; then
  echo "Android signing secrets are partially configured." >&2
  printf 'Missing: %s\n' "${missing[*]}" >&2
  exit 1
fi

if [ ! -d android/app ]; then
  echo "Android scaffold is missing. Run scripts/prepare_android.sh first." >&2
  exit 1
fi

keystore_path="android/app/doorsix-release.jks"
properties_path="android/key.properties"

printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode >"$keystore_path"
chmod 600 "$keystore_path"

cat >"$properties_path" <<EOF
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyPassword=$ANDROID_KEY_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
storeFile=doorsix-release.jks
EOF
chmod 600 "$properties_path"

if command -v keytool >/dev/null 2>&1; then
  keytool -list \
    -keystore "$keystore_path" \
    -alias "$ANDROID_KEY_ALIAS" \
    -storepass "$ANDROID_KEYSTORE_PASSWORD" >/dev/null
fi

node <<'NODE'
const fs = require('fs');
const path = require('path');

const candidates = [
  path.join('android', 'app', 'build.gradle.kts'),
  path.join('android', 'app', 'build.gradle'),
];
const gradlePath = candidates.find((candidate) => fs.existsSync(candidate));
if (!gradlePath) {
  throw new Error('android/app/build.gradle(.kts) was not found.');
}

let source = fs.readFileSync(gradlePath, 'utf8');
const marker = 'DoorSix release signing';
if (source.includes(marker)) {
  process.exit(0);
}

if (gradlePath.endsWith('.kts')) {
  const importBlock = `import java.io.FileInputStream
import java.util.Properties

`;
  const propertiesBlock = `// DoorSix release signing
val releaseKeystoreProperties = Properties()
val releaseKeystorePropertiesFile = rootProject.file("key.properties")
if (releaseKeystorePropertiesFile.exists()) {
    releaseKeystoreProperties.load(FileInputStream(releaseKeystorePropertiesFile))
}

`;
  const signingBlock = `
    signingConfigs {
        create("release") {
            keyAlias = releaseKeystoreProperties["keyAlias"] as String
            keyPassword = releaseKeystoreProperties["keyPassword"] as String
            storeFile = releaseKeystoreProperties["storeFile"]?.let { file(it) }
            storePassword = releaseKeystoreProperties["storePassword"] as String
        }
    }
`;
  if (!source.includes('android {')) {
    throw new Error('Could not find android block in Kotlin Gradle file.');
  }
  if (!source.includes('\n    buildTypes {')) {
    throw new Error('Could not find buildTypes block in Kotlin Gradle file.');
  }
  source = importBlock + source;
  source = source.replace('\nandroid {', `\n${propertiesBlock}android {`);
  source = source.replace('\n    buildTypes {', `${signingBlock}\n    buildTypes {`);
  source = source.replace(
    /signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)/g,
    'signingConfig = signingConfigs.getByName("release")',
  );
  source = source.replace(
    /signingConfig\s*=\s*signingConfigs\.getByName\("release"\)/g,
    'signingConfig = signingConfigs.getByName("release")',
  );
} else {
  const propertiesBlock = `// DoorSix release signing
def doorsixKeystoreProperties = new Properties()
def doorsixKeystorePropertiesFile = rootProject.file('key.properties')
if (doorsixKeystorePropertiesFile.exists()) {
    doorsixKeystoreProperties.load(new FileInputStream(doorsixKeystorePropertiesFile))
}

`;
  const signingBlock = `
    signingConfigs {
        release {
            keyAlias doorsixKeystoreProperties['keyAlias']
            keyPassword doorsixKeystoreProperties['keyPassword']
            storeFile file(doorsixKeystoreProperties['storeFile'])
            storePassword doorsixKeystoreProperties['storePassword']
        }
    }
`;
  if (!source.includes('android {')) {
    throw new Error('Could not find android block in Gradle file.');
  }
  if (!source.includes('\n    buildTypes {')) {
    throw new Error('Could not find buildTypes block in Gradle file.');
  }
  source = source.replace('\nandroid {', `\n${propertiesBlock}android {`);
  source = source.replace('\n    buildTypes {', `${signingBlock}\n    buildTypes {`);
  source = source.replace(/signingConfig\s+signingConfigs\.debug/g, 'signingConfig signingConfigs.release');
  source = source.replace(/signingConfig\s*=\s*signingConfigs\.debug/g, 'signingConfig signingConfigs.release');
}

fs.writeFileSync(gradlePath, source);
NODE

echo "Android release signing has been configured for this build."
