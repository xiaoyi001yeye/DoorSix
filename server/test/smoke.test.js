const { spawn } = require('node:child_process');
const net = require('node:net');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const WebSocket = require('ws');

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

function waitForHealth(baseUrl) {
  const deadline = Date.now() + 6000;
  return new Promise((resolve, reject) => {
    async function poll() {
      try {
        const response = await fetch(`${baseUrl}/health`);
        if (response.ok) {
          resolve();
          return;
        }
      } catch (_) {
        // The process may still be starting.
      }
      if (Date.now() > deadline) {
        reject(new Error('server did not become healthy'));
        return;
      }
      setTimeout(poll, 100);
    }
    poll();
  });
}

test('creates a room and starts a WebSocket game', async (t) => {
  const port = await freePort();
  const baseUrl = `http://127.0.0.1:${port}`;
  const serverDir = path.resolve(__dirname, '..');
  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: serverDir,
    env: {
      ...process.env,
      PORT: String(port),
      HOST: '127.0.0.1',
      PUBLIC_BASE_URL: baseUrl,
      REDIS_URL: '',
      MATCH_LOG_DIR: path.join(serverDir, '.tmp-test-logs'),
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(() => child.kill());

  await waitForHealth(baseUrl);

  const created = await fetch(`${baseUrl}/api/v1/rooms`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ nickname: 'owner', seatIndex: 0 }),
  }).then((response) => response.json());

  assert.equal(created.success, true);
  assert.equal(created.data.room.ruleSetId, 'zha_liujia_tianjin_basic_v1');
  assert.equal(created.data.self.team, 'B');

  await new Promise((resolve, reject) => {
    const ws = new WebSocket(
      `ws://127.0.0.1:${port}/ws/v1/tables/${created.data.room.roomId}?playerToken=${created.data.playerToken}`,
    );
    const timeout = setTimeout(() => reject(new Error('game_started not received')), 5000);

    ws.on('message', (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.type === 'table_snapshot') {
        ws.send(JSON.stringify({
          type: 'ready',
          requestId: 'ready_1',
          payload: { ready: true },
        }));
        setTimeout(() => {
          ws.send(JSON.stringify({
            type: 'start_game',
            requestId: 'start_1',
            payload: {},
          }));
        }, 100);
      }

      if (message.type === 'game_started') {
        clearTimeout(timeout);
        assert.equal(message.payload.tableState.status, 'playing');
        assert.equal(message.payload.myHand.length, 9);
        ws.close();
        resolve();
      }
    });
    ws.on('error', reject);
  });
});
