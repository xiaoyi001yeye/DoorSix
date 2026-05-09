#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
const match = pubspec.match(/^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$/m);

if (!match) {
  console.error('pubspec.yaml version must look like: version: 0.2.0+2');
  process.exit(1);
}

const versionName = match[1];
const versionCode = Number(match[2]);
const pubspecVersion = `${versionName}+${versionCode}`;

process.stdout.write(`${JSON.stringify({
  versionName,
  versionCode,
  pubspecVersion,
  expectedTag: `android-v${pubspecVersion}`,
})}\n`);
