#!/usr/bin/env node

const assert = require('node:assert/strict');

const WebSocket = require('ws');

const DEFAULT_BASE_URL = 'http://39.104.67.175';
const baseUrl = normalizeBaseUrl(process.argv[2] || process.env.REMOTE_BASE_URL || DEFAULT_BASE_URL);
const wsBaseUrl = baseUrl.replace(/^http:/, 'ws:').replace(/^https:/, 'wss:');
const timeoutMs = Number(process.env.REMOTE_TEST_TIMEOUT_MS || 12000);

const context = {
  owner: null,
  joined: null,
};

function normalizeBaseUrl(value) {
  return String(value).replace(/\/+$/, '');
}

function step(name, fn) {
  return async () => {
    const started = Date.now();
    try {
      const result = await fn();
      const elapsed = Date.now() - started;
      console.log(`ok   ${name} (${elapsed}ms)`);
      return result;
    } catch (error) {
      console.error(`fail ${name}`);
      throw error;
    }
  };
}

function withTimeout(promise, label, ms = timeoutMs) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function request(method, path, options = {}) {
  const response = await withTimeout(fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      accept: 'application/json',
      ...(options.body ? { 'content-type': 'application/json' } : {}),
      ...(options.token ? { 'x-player-token': options.token } : {}),
      ...(options.headers || {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  }), `${method} ${path}`);

  const text = await response.text();
  let body = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch (error) {
      throw new Error(`${method} ${path} returned non-JSON body: ${text.slice(0, 300)}`);
    }
  }

  return { response, body, text };
}

async function jsonOk(method, path, options = {}) {
  const { response, body, text } = await request(method, path, options);
  assert.equal(response.ok, true, `${method} ${path} expected 2xx, got ${response.status}: ${text}`);
  return body;
}

async function jsonError(method, path, expectedStatus, options = {}) {
  const { response, body, text } = await request(method, path, options);
  assert.equal(response.status, expectedStatus, `${method} ${path} expected ${expectedStatus}, got ${response.status}: ${text}`);
  assert.equal(body?.success, false);
  assert.ok(body?.error?.code);
  return body;
}

function openSocket(roomId, token) {
  const url = `${wsBaseUrl}/ws/v1/tables/${roomId}?playerToken=${encodeURIComponent(token)}`;
  const ws = new WebSocket(url);
  const queue = [];
  const waiters = [];

  ws.on('message', (raw) => {
    const message = JSON.parse(raw.toString());
    const waiterIndex = waiters.findIndex((waiter) => waiter.predicate(message));
    if (waiterIndex >= 0) {
      const [waiter] = waiters.splice(waiterIndex, 1);
      waiter.resolve(message);
    } else {
      queue.push(message);
    }
  });

  ws.on('error', (error) => {
    while (waiters.length) waiters.shift().reject(error);
  });

  ws.on('close', () => {
    while (waiters.length) waiters.shift().reject(new Error('WebSocket closed before expected message arrived'));
  });

  function waitFor(predicate, label) {
    const queuedIndex = queue.findIndex(predicate);
    if (queuedIndex >= 0) {
      const [message] = queue.splice(queuedIndex, 1);
      return Promise.resolve(message);
    }
    return withTimeout(new Promise((resolve, reject) => {
      waiters.push({ predicate, resolve, reject });
    }), label);
  }

  return withTimeout(new Promise((resolve, reject) => {
    ws.once('open', () => resolve({
      ws,
      send(type, requestId, payload = {}) {
        ws.send(JSON.stringify({ type, requestId, payload }));
      },
      waitFor,
      close() {
        ws.close();
      },
    }));
    ws.once('error', reject);
  }), `open WebSocket ${url}`);
}

function assertRoomShape(room) {
  assert.match(room.roomId, /^r_/);
  assert.match(room.roomCode, /^\d{6}$/);
  assert.equal(room.ruleSetId, 'zha_liujia_tianjin_basic_v1');
  assert.equal(room.maxPlayers, 6);
}

function testNickname(prefix) {
  return `${prefix}-${Math.floor(Math.random() * 100000)}`;
}

async function cleanupRoom() {
  if (!context.owner?.room?.roomId || !context.owner?.playerToken) return;
  try {
    await request('POST', `/api/v1/rooms/${context.owner.room.roomId}/leave`, {
      token: context.owner.playerToken,
      body: { reason: 'remote_smoke_test_cleanup' },
    });
  } catch (error) {
    console.warn(`warn cleanup failed: ${error.message}`);
  }
}

async function main() {
  console.log(`DoorSix remote smoke test: ${baseUrl}`);

  await step('health endpoint reports service and Redis', async () => {
    const body = await jsonOk('GET', '/health');
    assert.equal(body.ok, true);
    assert.equal(body.service, 'doorsix-server');
    assert.equal(body.ruleSetId, 'zha_liujia_tianjin_basic_v1');
    assert.equal(body.redis, true, 'remote deployment should be connected to Redis');
    assert.equal(typeof body.serverTime, 'number');
  })();

  await step('unknown room code returns structured 404', async () => {
    const body = await jsonError('GET', '/api/v1/rooms/by-code/999999', 404);
    assert.equal(body.error.code, 'ROOM_NOT_FOUND');
  })();

  await step('create room as owner', async () => {
    const nickname = testNickname('owner');
    const body = await jsonOk('POST', '/api/v1/rooms', {
      body: { nickname, seatIndex: 0 },
    });
    assert.equal(body.success, true);
    assertRoomShape(body.data.room);
    assert.equal(body.data.self.nickname, nickname);
    assert.equal(body.data.self.seatIndex, 0);
    assert.equal(body.data.self.team, 'B');
    assert.match(body.data.playerToken, /^tok_/);
    assert.equal(body.data.webSocketUrl, `${wsBaseUrl}/ws/v1/tables/${body.data.room.roomId}`);
    context.owner = body.data;
  })();

  await step('lookup created room by code', async () => {
    const body = await jsonOk('GET', `/api/v1/rooms/by-code/${context.owner.room.roomCode}`);
    assert.equal(body.success, true);
    assert.equal(body.data.room.roomId, context.owner.room.roomId);
    assert.equal(body.data.joinable, true);
  })();

  await step('join second human player', async () => {
    const nickname = testNickname('join');
    const body = await jsonOk('POST', `/api/v1/rooms/by-code/${context.owner.room.roomCode}/join`, {
      body: { nickname, seatIndex: 1 },
    });
    assert.equal(body.success, true);
    assert.equal(body.data.room.roomId, context.owner.room.roomId);
    assert.equal(body.data.self.nickname, nickname);
    assert.equal(body.data.self.seatIndex, 1);
    assert.equal(body.data.self.team, 'A');
    assert.match(body.data.playerToken, /^tok_/);
    context.joined = body.data;
  })();

  await step('snapshot, stats, and history endpoints authenticate by token', async () => {
    const snapshot = await jsonOk('GET', `/api/v1/rooms/${context.owner.room.roomId}/snapshot`, {
      token: context.owner.playerToken,
    });
    assert.equal(snapshot.success, true);
    assert.equal(snapshot.data.tableState.roomId, context.owner.room.roomId);
    assert.equal(snapshot.data.tableState.status, 'waiting');
    assert.equal(snapshot.data.tableState.seats.filter(Boolean).length, 2);

    const stats = await jsonOk('GET', '/api/v1/players/me/stats?limit=5', {
      token: context.owner.playerToken,
    });
    assert.equal(stats.success, true);
    assert.equal(typeof stats.data.totalRounds, 'number');
    assert.ok(Array.isArray(stats.data.recentResults));

    const history = await jsonOk('GET', `/api/v1/rooms/${context.owner.room.roomId}/history?limit=5`, {
      token: context.owner.playerToken,
    });
    assert.equal(history.success, true);
    assert.equal(history.data.roomId, context.owner.room.roomId);
    assert.ok(Array.isArray(history.data.rounds));
  })();

  await step('WebSocket ready/start flow reaches playing table', async () => {
    const ownerSocket = await openSocket(context.owner.room.roomId, context.owner.playerToken);
    const joinSocket = await openSocket(context.joined.room.roomId, context.joined.playerToken);

    try {
      const ownerInitial = await ownerSocket.waitFor((message) => message.type === 'table_snapshot', 'owner table_snapshot');
      assert.equal(ownerInitial.payload.tableState.status, 'waiting');

      const joinInitial = await joinSocket.waitFor((message) => message.type === 'table_snapshot', 'joined table_snapshot');
      assert.equal(joinInitial.payload.tableState.status, 'waiting');

      ownerSocket.send('ping', 'remote_ping');
      const pong = await ownerSocket.waitFor((message) => message.type === 'pong' && message.requestId === 'remote_ping', 'pong');
      assert.equal(pong.payload && typeof pong.payload, 'object');

      ownerSocket.send('ready', 'owner_ready', { ready: true });
      await ownerSocket.waitFor((message) => message.type === 'seat_updated' && message.requestId === 'owner_ready', 'owner ready ack');
      joinSocket.send('ready', 'join_ready', { ready: true });
      await joinSocket.waitFor((message) => message.type === 'seat_updated' && message.requestId === 'join_ready', 'join ready ack');

      ownerSocket.send('start_game', 'start_remote_game');
      const started = await ownerSocket.waitFor(
        (message) => message.type === 'game_started' || (message.type === 'error' && message.requestId === 'start_remote_game'),
        'game_started',
      );
      assert.notEqual(started.type, 'error', `start_game failed: ${JSON.stringify(started.payload)}`);
      assert.equal(started.requestId, 'start_remote_game');
      assert.equal(started.payload.tableState.status, 'playing');
      assert.equal(started.payload.tableState.seats.filter(Boolean).length, 6);
      assert.equal(started.payload.tableState.seats.filter((seat) => seat.isAi).length, 4);
      assert.equal(started.payload.myHand.length, 9);
    } finally {
      ownerSocket.close();
      joinSocket.close();
    }
  })();

  await step('snapshot sees started game and cleanup closes room', async () => {
    const snapshot = await jsonOk('GET', `/api/v1/rooms/${context.owner.room.roomId}/snapshot`, {
      token: context.owner.playerToken,
    });
    assert.equal(snapshot.data.tableState.status, 'playing');
    assert.equal(snapshot.data.tableState.seats.filter((seat) => seat && !seat.isAi).length, 2);
    assert.equal(snapshot.data.myHand.length, 9);

    const left = await jsonOk('POST', `/api/v1/rooms/${context.owner.room.roomId}/leave`, {
      token: context.owner.playerToken,
      body: { reason: 'remote_smoke_test_cleanup' },
    });
    assert.equal(left.data.left, true);
    assert.equal(left.data.roomClosed, true);
    context.owner = null;
  })();

  console.log('All remote smoke tests passed.');
}

main()
  .catch(async (error) => {
    await cleanupRoom();
    console.error(error.stack || error.message);
    process.exitCode = 1;
  });
