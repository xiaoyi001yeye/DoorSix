const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const {
  decideUpdate,
  isRolloutMatched,
  listPublishedAndroidApks,
  validateRelease,
} = require('../src/app-update-service');

function release(overrides = {}) {
  return {
    id: 'android-stable-2',
    platform: 'android',
    channel: 'stable',
    environment: 'prod',
    versionName: '0.2.0',
    versionCode: 2,
    minSupportedVersionCode: 1,
    forceUpdate: false,
    status: 'active',
    title: '发现新版本 0.2.0',
    releaseNotes: ['优化联机稳定性'],
    downloadUrl: 'http://39.104.67.175/downloads/android/0.2.0+2/door_six-0.2.0+2-stable.apk',
    fileSizeBytes: 32100000,
    sha256: 'a'.repeat(64),
    gitTag: 'android-v0.2.0+2',
    commitSha: 'abc123',
    publishedAt: '2026-05-09T12:00:00Z',
    rollout: {
      enabled: true,
      percentage: 100,
    },
    ...overrides,
  };
}

test('validates release manifest shape', () => {
  assert.doesNotThrow(() => validateRelease(release()));
  assert.throws(
    () => validateRelease(release({ sha256: 'bad' })),
    /sha256 is invalid/,
  );
});

test('decides optional and force update states', () => {
  const optional = decideUpdate({
    release: release(),
    clientVersionCode: 1,
    deviceId: 'device-a',
  });
  assert.equal(optional.hasUpdate, true);
  assert.equal(optional.updateType, 'optional');
  assert.equal(optional.latest.versionCode, 2);

  const force = decideUpdate({
    release: release({ minSupportedVersionCode: 2 }),
    clientVersionCode: 1,
    deviceId: 'device-a',
  });
  assert.equal(force.updateType, 'force');

  const current = decideUpdate({
    release: release(),
    clientVersionCode: 2,
    deviceId: 'device-a',
  });
  assert.deepEqual(current, { hasUpdate: false });
});

test('rollout percentage buckets devices deterministically', () => {
  const stableRelease = release({ rollout: { enabled: true, percentage: 50 } });
  assert.equal(
    isRolloutMatched({ release: stableRelease, deviceId: 'same-device' }),
    isRolloutMatched({ release: stableRelease, deviceId: 'same-device' }),
  );
  assert.equal(
    isRolloutMatched({
      release: release({ rollout: { enabled: true, percentage: 0 } }),
      deviceId: 'device-a',
    }),
    false,
  );
  assert.equal(
    isRolloutMatched({
      release: release({ rollout: { enabled: true, percentage: 100 } }),
      deviceId: 'device-a',
    }),
    true,
  );
});

test('lists manifest-backed and loose APK downloads', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'doorsix-releases-'));
  const manifestDir = path.join(root, 'manifests');
  const androidDir = path.join(root, 'android');
  const previousEnv = {
    APP_UPDATE_MANIFEST_PATH: process.env.APP_UPDATE_MANIFEST_PATH,
    APP_RELEASE_ANDROID_DIR: process.env.APP_RELEASE_ANDROID_DIR,
    APP_UPDATE_DOWNLOAD_BASE_URL: process.env.APP_UPDATE_DOWNLOAD_BASE_URL,
  };
  t.after(async () => {
    for (const [key, value] of Object.entries(previousEnv)) {
      if (value == null) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
    await fs.rm(root, { recursive: true, force: true });
  });

  process.env.APP_UPDATE_MANIFEST_PATH = path.join(
    manifestDir,
    'latest-android-stable.json',
  );
  process.env.APP_RELEASE_ANDROID_DIR = androidDir;
  process.env.APP_UPDATE_DOWNLOAD_BASE_URL = 'http://example.test/downloads/android';

  const stableRelease = release();
  await fs.mkdir(path.join(androidDir, '0.2.0+2'), { recursive: true });
  await fs.mkdir(manifestDir, { recursive: true });
  await fs.writeFile(
    path.join(androidDir, '0.2.0+2', 'door_six-0.2.0+2-stable.apk'),
    'manifest apk',
  );
  await fs.writeFile(path.join(androidDir, 'manual.apk'), 'manual apk');
  await fs.writeFile(
    path.join(manifestDir, 'release-android-0.2.0+2.json'),
    JSON.stringify(stableRelease),
  );

  const releases = await listPublishedAndroidApks();

  assert.equal(releases.length, 2);
  assert.equal(releases[0].source, 'manifest');
  assert.equal(releases[0].versionCode, stableRelease.versionCode);
  assert.equal(releases[0].fileName, 'door_six-0.2.0+2-stable.apk');
  assert.equal(releases[0].available, true);
  assert.equal(releases[1].source, 'file');
  assert.equal(releases[1].fileName, 'manual.apk');
  assert.equal(
    releases[1].downloadUrl,
    'http://example.test/downloads/android/manual.apk',
  );
});
