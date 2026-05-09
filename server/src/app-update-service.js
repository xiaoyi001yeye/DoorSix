const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

const ACTIVE_STATUSES = new Set(['draft', 'active', 'paused', 'recalled']);
const CHANNELS = new Set(['stable']);

function defaultManifestPath() {
  return process.env.APP_UPDATE_MANIFEST_PATH ||
    '/opt/doorsix/releases/manifests/latest-android-stable.json';
}

function defaultEnvironment() {
  return process.env.APP_UPDATE_ENVIRONMENT || 'prod';
}

function defaultChannel() {
  return process.env.APP_UPDATE_DEFAULT_CHANNEL || 'stable';
}

async function loadLatestRelease({ platform = 'android', channel = defaultChannel() } = {}) {
  if (platform !== 'android') {
    throw validationError('UNSUPPORTED_PLATFORM', 'platform must be android');
  }
  if (!CHANNELS.has(channel)) {
    throw validationError('UNSUPPORTED_CHANNEL', 'channel must be stable');
  }

  const raw = await fs.readFile(defaultManifestPath(), 'utf8');
  const release = JSON.parse(raw);
  validateRelease(release);
  if (release.platform !== platform || release.channel !== channel) {
    throw validationError('MANIFEST_MISMATCH', 'manifest platform or channel does not match request');
  }
  return release;
}

async function loadReleaseByVersionCode({ platform = 'android', versionCode }) {
  const manifestDir = path.dirname(defaultManifestPath());
  const names = await fs.readdir(manifestDir);
  for (const name of names) {
    if (!name.startsWith('release-android-') || !name.endsWith('.json')) {
      continue;
    }
    const raw = await fs.readFile(path.join(manifestDir, name), 'utf8');
    const release = JSON.parse(raw);
    validateRelease(release);
    if (release.platform === platform && release.versionCode === versionCode) {
      return release;
    }
  }
  return null;
}

function decideUpdate({ release, clientVersionCode, deviceId, requestSeed }) {
  if (!release || release.status !== 'active') {
    return { hasUpdate: false };
  }
  if (!release.rollout?.enabled || clientVersionCode >= release.versionCode) {
    return { hasUpdate: false };
  }
  if (!isRolloutMatched({ release, deviceId, requestSeed })) {
    return { hasUpdate: false };
  }

  const force = release.forceUpdate === true ||
    clientVersionCode < release.minSupportedVersionCode;
  return {
    hasUpdate: true,
    updateType: force ? 'force' : 'optional',
    latest: publicReleasePayload(release),
  };
}

function isRolloutMatched({ release, deviceId, requestSeed }) {
  const percentage = Number(release.rollout?.percentage ?? 100);
  if (percentage <= 0) return false;
  if (percentage >= 100) return true;

  const seed = deviceId || requestSeed || 'anonymous';
  const input = `${release.platform}:${release.channel}:${release.versionCode}:${seed}`;
  const hash = crypto.createHash('sha256').update(input).digest('hex');
  const bucket = Number.parseInt(hash.slice(0, 8), 16) % 100;
  return bucket < percentage;
}

function validateRelease(release) {
  assertObject(release, 'release');
  assertEqual(release.platform, 'android', 'platform');
  if (!CHANNELS.has(release.channel)) {
    throw validationError('INVALID_CHANNEL', 'channel must be stable');
  }
  assertEqual(release.environment, defaultEnvironment(), 'environment');
  assertPattern(release.versionName, /^\d+\.\d+\.\d+$/, 'versionName');
  assertPositiveInteger(release.versionCode, 'versionCode');
  assertPositiveInteger(release.minSupportedVersionCode, 'minSupportedVersionCode');
  if (release.minSupportedVersionCode > release.versionCode) {
    throw validationError('INVALID_MIN_VERSION', 'minSupportedVersionCode must be <= versionCode');
  }
  if (!ACTIVE_STATUSES.has(release.status)) {
    throw validationError('INVALID_STATUS', 'status must be draft, active, paused, or recalled');
  }
  assertAbsoluteHttpUrl(release.downloadUrl, 'downloadUrl');
  assertPositiveInteger(release.fileSizeBytes, 'fileSizeBytes');
  assertPattern(release.sha256, /^[a-fA-F0-9]{64}$/, 'sha256');
  const rollout = release.rollout || {};
  if (typeof rollout.enabled !== 'boolean') {
    throw validationError('INVALID_ROLLOUT', 'rollout.enabled must be boolean');
  }
  const percentage = Number(rollout.percentage);
  if (!Number.isFinite(percentage) || percentage < 0 || percentage > 100) {
    throw validationError('INVALID_ROLLOUT', 'rollout.percentage must be 0..100');
  }
}

function publicReleasePayload(release) {
  return {
    versionName: release.versionName,
    versionCode: release.versionCode,
    title: release.title || `发现新版本 ${release.versionName}`,
    releaseNotes: Array.isArray(release.releaseNotes) ? release.releaseNotes : [],
    downloadUrl: release.downloadUrl,
    fileSizeBytes: release.fileSizeBytes,
    sha256: release.sha256,
    publishedAt: release.publishedAt,
  };
}

function requestSeedFor(req) {
  const ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '');
  const ua = String(req.headers['user-agent'] || '');
  return crypto.createHash('sha256').update(`${ip}:${ua}`).digest('hex');
}

function validationError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function assertObject(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw validationError('INVALID_MANIFEST', `${name} must be an object`);
  }
}

function assertEqual(value, expected, name) {
  if (value !== expected) {
    throw validationError('INVALID_MANIFEST', `${name} must be ${expected}`);
  }
}

function assertPattern(value, pattern, name) {
  if (typeof value !== 'string' || !pattern.test(value)) {
    throw validationError('INVALID_MANIFEST', `${name} is invalid`);
  }
}

function assertPositiveInteger(value, name) {
  if (!Number.isInteger(value) || value <= 0) {
    throw validationError('INVALID_MANIFEST', `${name} must be a positive integer`);
  }
}

function assertAbsoluteHttpUrl(value, name) {
  try {
    const url = new URL(value);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') {
      throw new Error('unsupported protocol');
    }
  } catch (_) {
    throw validationError('INVALID_MANIFEST', `${name} must be an absolute HTTP URL`);
  }
}

module.exports = {
  decideUpdate,
  defaultChannel,
  defaultEnvironment,
  defaultManifestPath,
  isRolloutMatched,
  loadLatestRelease,
  loadReleaseByVersionCode,
  publicReleasePayload,
  requestSeedFor,
  validateRelease,
};
