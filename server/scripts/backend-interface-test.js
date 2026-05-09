#!/usr/bin/env node

const fs = require('node:fs/promises');
const net = require('node:net');
const path = require('node:path');
const { spawn } = require('node:child_process');

const WebSocket = require('ws');

const DEFAULT_TIMEOUT_MS = Number(process.env.BACKEND_TEST_TIMEOUT_MS || 8000);
const REPORT_DIR = path.resolve(__dirname, '..', 'test-reports');
const SERVER_DIR = path.resolve(__dirname, '..');
const REPORT_TIME_ZONE = process.env.BACKEND_TEST_TIME_ZONE || 'Asia/Shanghai';
const RULE_SET_ID = 'zha_liujia_tianjin_basic_v1';
const RANK_STRENGTH = {
  '4': 1,
  '5': 2,
  '6': 3,
  '7': 4,
  '8': 5,
  '9': 6,
  '10': 7,
  J: 8,
  Q: 9,
  K: 10,
  A: 11,
  '2': 12,
  '3': 13,
  small_joker: 14,
  big_joker: 15,
};
const WILD_RANKS = new Set(['big_joker', 'small_joker', '3', '2']);

const results = [];
const context = {
  baseUrl: normalizeBaseUrl(process.env.BACKEND_TEST_BASE_URL || process.argv[2] || ''),
  wsBaseUrl: '',
  localServer: null,
  localServerOutput: [],
  owner: null,
  joined: null,
  startedOwner: null,
  startedJoined: null,
  startedSockets: [],
};

function normalizeBaseUrl(value) {
  return String(value || '').replace(/\/+$/, '');
}

function nowText() {
  const parts = timeParts();
  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}:${parts.second} ${REPORT_TIME_ZONE}`;
}

function reportStamp() {
  const parts = timeParts();
  return `${parts.year}${parts.month}${parts.day}-${parts.hour}${parts.minute}${parts.second}`;
}

function timeParts() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: REPORT_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).formatToParts(new Date());
  return Object.fromEntries(parts.map((part) => [part.type, part.value]));
}

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

function withTimeout(promise, label, timeoutMs = DEFAULT_TIMEOUT_MS) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} 超时（${timeoutMs}ms）`)), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function waitForHealth(baseUrl) {
  const deadline = Date.now() + DEFAULT_TIMEOUT_MS;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${baseUrl}/health`);
      if (response.ok) return;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 120));
  }
  throw new Error(`服务未能启动：${lastError?.message || 'health 未通过'}`);
}

async function startLocalServerIfNeeded() {
  if (context.baseUrl) {
    context.wsBaseUrl = context.baseUrl.replace(/^http:/, 'ws:').replace(/^https:/, 'wss:');
    await waitForHealth(context.baseUrl);
    return;
  }

  const port = await freePort();
  context.baseUrl = `http://127.0.0.1:${port}`;
  context.wsBaseUrl = `ws://127.0.0.1:${port}`;
  const matchLogDir = path.join(SERVER_DIR, '.tmp-backend-interface-test-logs');
  const child = spawn(process.execPath, ['src/index.js'], {
    cwd: SERVER_DIR,
    env: {
      ...process.env,
      PORT: String(port),
      HOST: '127.0.0.1',
      PUBLIC_BASE_URL: context.baseUrl,
      REDIS_URL: '',
      MATCH_LOG_DIR: matchLogDir,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  context.localServer = child;
  child.stdout.on('data', (chunk) => context.localServerOutput.push(chunk.toString()));
  child.stderr.on('data', (chunk) => context.localServerOutput.push(chunk.toString()));
  await waitForHealth(context.baseUrl);
}

async function request(method, route, options = {}) {
  const response = await withTimeout(fetch(`${context.baseUrl}${route}`, {
    method,
    headers: {
      accept: 'application/json',
      ...(options.body !== undefined ? { 'content-type': 'application/json' } : {}),
      ...(options.token ? { 'x-player-token': options.token } : {}),
      ...(options.headers || {}),
    },
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  }), `${method} ${route}`);

  const text = await response.text();
  let body = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch (error) {
      throw new Error(`${method} ${route} 返回非 JSON：${text.slice(0, 200)}`);
    }
  }
  return { response, body, text };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function expectStatus(result, expectedStatus) {
  assert(
    result.response.status === expectedStatus,
    `期望 HTTP ${expectedStatus}，实际 HTTP ${result.response.status}，响应：${result.text}`,
  );
}

function expectSuccess(result) {
  assert(result.response.ok, `期望 2xx，实际 HTTP ${result.response.status}，响应：${result.text}`);
  assert(result.body?.success === true || result.body?.ok === true, `期望成功响应，实际：${result.text}`);
}

function expectError(result, expectedStatus, expectedCode) {
  expectStatus(result, expectedStatus);
  assert(result.body?.success === false, `期望 success=false，实际：${result.text}`);
  if (expectedCode) {
    assert(result.body?.error?.code === expectedCode, `期望错误码 ${expectedCode}，实际：${result.body?.error?.code}`);
  }
}

async function check(id, group, name, target, fn, options = {}) {
  const started = Date.now();
  try {
    if (options.skip) {
      results.push({
        id,
        group,
        name,
        target,
        status: '跳过',
        durationMs: 0,
        detail: options.skip,
      });
      console.log(`skip ${id} ${name}：${options.skip}`);
      return null;
    }
    const detail = await fn();
    const durationMs = Date.now() - started;
    results.push({
      id,
      group,
      name,
      target,
      status: '通过',
      durationMs,
      detail: detail || '符合预期',
    });
    console.log(`ok   ${id} ${name} (${durationMs}ms)`);
    return detail;
  } catch (error) {
    const durationMs = Date.now() - started;
    results.push({
      id,
      group,
      name,
      target,
      status: '失败',
      durationMs,
      detail: error.message,
    });
    console.error(`fail ${id} ${name}：${error.message}`);
    return null;
  }
}

function testNickname(prefix) {
  return `${prefix}-${Date.now().toString(36)}-${Math.floor(Math.random() * 10000)}`;
}

function roomShape(room) {
  assert(/^r_/.test(room.roomId), `roomId 格式异常：${room.roomId}`);
  assert(/^\d{6}$/.test(room.roomCode), `roomCode 格式异常：${room.roomCode}`);
  assert(room.ruleSetId === RULE_SET_ID, `规则版本异常：${room.ruleSetId}`);
  assert(room.maxPlayers === 6, `maxPlayers 异常：${room.maxPlayers}`);
}

function openSocket(roomId, token) {
  const url = `${context.wsBaseUrl}/ws/v1/tables/${roomId}?playerToken=${encodeURIComponent(token)}`;
  const ws = new WebSocket(url);
  const queue = [];
  const waiters = [];

  ws.on('message', (raw) => {
    const message = JSON.parse(raw.toString());
    const index = waiters.findIndex((waiter) => waiter.predicate(message));
    if (index >= 0) {
      const [waiter] = waiters.splice(index, 1);
      waiter.resolve(message);
    } else {
      queue.push(message);
    }
  });

  ws.on('error', (error) => {
    while (waiters.length) waiters.shift().reject(error);
  });

  ws.on('close', () => {
    while (waiters.length) waiters.shift().reject(new Error('WebSocket 在收到预期消息前关闭'));
  });

  function waitFor(predicate, label, timeoutMs = DEFAULT_TIMEOUT_MS) {
    const index = queue.findIndex(predicate);
    if (index >= 0) {
      const [message] = queue.splice(index, 1);
      return Promise.resolve(message);
    }
    return withTimeout(new Promise((resolve, reject) => {
      waiters.push({ predicate, resolve, reject });
    }), label, timeoutMs);
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
  }), `打开 WebSocket ${url}`);
}

async function expectWsRejected(roomId, token) {
  const url = `${context.wsBaseUrl}/ws/v1/tables/${roomId}?playerToken=${encodeURIComponent(token)}`;
  await withTimeout(new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.once('open', () => {
      ws.close();
      reject(new Error('错误 token 仍然成功建立了 WebSocket 连接'));
    });
    ws.once('unexpected-response', (_req, response) => {
      if (response.statusCode === 401) resolve();
      else reject(new Error(`期望 401，实际 ${response.statusCode}`));
    });
    ws.once('error', (error) => {
      if (String(error.message).includes('401')) resolve();
      else reject(error);
    });
  }), '错误 token WebSocket 鉴权');
}

function effectiveRank(cards) {
  if (cards.length === 1) return cards[0].rank;
  const naturalRanks = new Set(cards.filter((card) => !WILD_RANKS.has(card.rank)).map((card) => card.rank));
  if (naturalRanks.size > 1) return null;
  if (naturalRanks.size === 1) return [...naturalRanks][0];
  return '3';
}

function evaluateCombo(cards) {
  if (!Array.isArray(cards) || cards.length < 1 || cards.length > 4) return null;
  const rank = effectiveRank(cards);
  if (!rank) return null;
  const typeByLength = ['', 'single', 'pair', 'triple', 'quad'];
  return {
    comboType: typeByLength[cards.length],
    rankStrength: RANK_STRENGTH[rank],
    cardIds: cards.map((card) => card.cardId),
  };
}

function canBeat(candidate, target) {
  if (!candidate) return false;
  if (!target || target.comboType === 'invalid') return true;
  return candidate.comboType === target.comboType &&
    candidate.cardIds.length === target.cardIds.length &&
    candidate.rankStrength > target.rankStrength;
}

function combinations(cards, size) {
  const result = [];
  function collect(start, current) {
    if (current.length === size) {
      result.push(current.slice());
      return;
    }
    for (let i = start; i < cards.length; i += 1) {
      current.push(cards[i]);
      collect(i + 1, current);
      current.pop();
    }
  }
  collect(0, []);
  return result;
}

function findPlayableCards(hand, target) {
  const candidates = [];
  for (let size = 1; size <= Math.min(4, hand.length); size += 1) {
    candidates.push(...combinations(hand, size));
  }
  candidates.sort((a, b) => {
    const ca = evaluateCombo(a);
    const cb = evaluateCombo(b);
    if (!ca && !cb) return 0;
    if (!ca) return 1;
    if (!cb) return -1;
    const kind = ['invalid', 'single', 'pair', 'triple', 'quad'].indexOf(ca.comboType) -
      ['invalid', 'single', 'pair', 'triple', 'quad'].indexOf(cb.comboType);
    if (kind !== 0) return kind;
    return ca.rankStrength - cb.rankStrength;
  });
  return candidates.find((cards) => canBeat(evaluateCombo(cards), target)) || [];
}

async function waitForHumanTurn(label) {
  const ownerSocket = context.startedSockets[0];
  const joinedSocket = context.startedSockets[1];
  const ownerSeat = context.startedOwner.self.seatIndex;
  const joinedSeat = context.startedJoined.self.seatIndex;

  for (let attempt = 1; attempt <= 6; attempt += 1) {
    const ownerRequestId = `${label}_owner_${attempt}`;
    const joinedRequestId = `${label}_joined_${attempt}`;
    ownerSocket.send('sync_state', ownerRequestId);
    joinedSocket.send('sync_state', joinedRequestId);
    const ownerSnapshot = await ownerSocket.waitFor(
      (message) => message.type === 'table_snapshot' && message.requestId === ownerRequestId,
      `${label} owner 快照 ${attempt}`,
    );
    const joinedSnapshot = await joinedSocket.waitFor(
      (message) => message.type === 'table_snapshot' && message.requestId === joinedRequestId,
      `${label} joined 快照 ${attempt}`,
    );
    const currentSeat = ownerSnapshot.payload.tableState.currentTurnSeatIndex;
    if (currentSeat === ownerSeat) {
      return {
        socket: ownerSocket,
        snapshot: ownerSnapshot,
        seatIndex: ownerSeat,
      };
    }
    if (currentSeat === joinedSeat) {
      return {
        socket: joinedSocket,
        snapshot: joinedSnapshot,
        seatIndex: joinedSeat,
      };
    }

    await ownerSocket.waitFor(
      (message) => message.payload?.tableState &&
        message.payload.tableState.currentTurnSeatIndex !== currentSeat,
      `${label} 等待 AI 行动 ${attempt}`,
      9000,
    ).catch(() => null);
  }

  throw new Error('等待 6 次后当前回合仍未轮到测试中的真人玩家');
}

async function cleanup() {
  for (const socket of context.startedSockets) {
    try {
      socket.close();
    } catch (_) {
      // ignore cleanup errors
    }
  }
  const rooms = [
    context.owner,
    context.startedOwner,
  ].filter(Boolean);
  for (const roomData of rooms) {
    try {
      await request('POST', `/api/v1/rooms/${roomData.room.roomId}/leave`, {
        token: roomData.playerToken,
        body: { reason: 'backend_interface_test_cleanup' },
      });
    } catch (_) {
      // The room may already be closed by a test.
    }
  }
  if (context.localServer) {
    context.localServer.kill();
  }
}

async function runHttpTests() {
  await check('H01', 'HTTP 接口', '健康检查', 'GET /health', async () => {
    const result = await request('GET', '/health');
    expectStatus(result, 200);
    assert(result.body?.ok === true, 'health.ok 不是 true');
    assert(result.body?.service === 'doorsix-server', `service 异常：${result.body?.service}`);
    assert(result.body?.ruleSetId === RULE_SET_ID, `ruleSetId 异常：${result.body?.ruleSetId}`);
    assert(typeof result.body?.serverTime === 'number', 'serverTime 不是数字');
    return `服务可用，Redis=${Boolean(result.body.redis)}`;
  });

  await check('H02', 'HTTP 接口', '未知房间号返回结构化 404', 'GET /api/v1/rooms/by-code/:roomCode', async () => {
    const result = await request('GET', '/api/v1/rooms/by-code/999999');
    expectError(result, 404, 'ROOM_NOT_FOUND');
  });

  await check('H03', 'HTTP 接口', '创建房间拒绝空昵称', 'POST /api/v1/rooms', async () => {
    const result = await request('POST', '/api/v1/rooms', { body: { nickname: '', seatIndex: 0 } });
    expectError(result, 400, 'INVALID_REQUEST');
  });

  await check('H04', 'HTTP 接口', '创建房间拒绝非法座位', 'POST /api/v1/rooms', async () => {
    const result = await request('POST', '/api/v1/rooms', { body: { nickname: '房主', seatIndex: 6 } });
    expectError(result, 400, 'INVALID_REQUEST');
  });

  await check('H05', 'HTTP 接口', '创建房间成功', 'POST /api/v1/rooms', async () => {
    const nickname = testNickname('owner');
    const result = await request('POST', '/api/v1/rooms', { body: { nickname, seatIndex: 0 } });
    expectSuccess(result);
    roomShape(result.body.data.room);
    assert(result.body.data.self.nickname === nickname, 'self.nickname 与请求不一致');
    assert(result.body.data.self.seatIndex === 0, 'self.seatIndex 不是 0');
    assert(result.body.data.self.team === 'B', 'seat 0 应属于 B 队');
    assert(/^tok_/.test(result.body.data.playerToken), 'playerToken 格式异常');
    context.owner = result.body.data;
    return `房间号 ${context.owner.room.roomCode}`;
  });

  await check('H06', 'HTTP 接口', '按房间号查询成功', 'GET /api/v1/rooms/by-code/:roomCode', async () => {
    const result = await request('GET', `/api/v1/rooms/by-code/${context.owner.room.roomCode}`);
    expectSuccess(result);
    assert(result.body.data.room.roomId === context.owner.room.roomId, '查询到的 roomId 不一致');
    assert(result.body.data.joinable === true, '新房间应允许加入');
  });

  await check('H07', 'HTTP 接口', '加入房间拒绝空昵称', 'POST /api/v1/rooms/by-code/:roomCode/join', async () => {
    const result = await request('POST', `/api/v1/rooms/by-code/${context.owner.room.roomCode}/join`, {
      body: { nickname: '', seatIndex: 1 },
    });
    expectError(result, 400, 'INVALID_REQUEST');
  });

  await check('H08', 'HTTP 接口', '加入房间拒绝非法座位', 'POST /api/v1/rooms/by-code/:roomCode/join', async () => {
    const result = await request('POST', `/api/v1/rooms/by-code/${context.owner.room.roomCode}/join`, {
      body: { nickname: '加入者', seatIndex: -1 },
    });
    expectError(result, 400, 'INVALID_REQUEST');
  });

  await check('H09', 'HTTP 接口', '加入房间拒绝已占座位', 'POST /api/v1/rooms/by-code/:roomCode/join', async () => {
    const result = await request('POST', `/api/v1/rooms/by-code/${context.owner.room.roomCode}/join`, {
      body: { nickname: '抢座', seatIndex: 0 },
    });
    expectError(result, 409, 'SEAT_TAKEN');
  });

  await check('H10', 'HTTP 接口', '加入房间成功', 'POST /api/v1/rooms/by-code/:roomCode/join', async () => {
    const nickname = testNickname('join');
    const result = await request('POST', `/api/v1/rooms/by-code/${context.owner.room.roomCode}/join`, {
      body: { nickname, seatIndex: 1 },
    });
    expectSuccess(result);
    assert(result.body.data.room.roomId === context.owner.room.roomId, '加入到的 roomId 不一致');
    assert(result.body.data.self.seatIndex === 1, 'self.seatIndex 不是 1');
    assert(result.body.data.self.team === 'A', 'seat 1 应属于 A 队');
    context.joined = result.body.data;
  });

  await check('H11', 'HTTP 接口', '快照接口缺 token 返回 401', 'GET /api/v1/rooms/:roomId/snapshot', async () => {
    const result = await request('GET', `/api/v1/rooms/${context.owner.room.roomId}/snapshot`);
    expectError(result, 401, 'INVALID_PLAYER_TOKEN');
  });

  await check('H12', 'HTTP 接口', '快照接口错误 token 返回 401', 'GET /api/v1/rooms/:roomId/snapshot', async () => {
    const result = await request('GET', `/api/v1/rooms/${context.owner.room.roomId}/snapshot`, { token: 'tok_wrong' });
    expectError(result, 401, 'INVALID_PLAYER_TOKEN');
  });

  await check('H13', 'HTTP 接口', '快照接口成功且不泄露他人手牌', 'GET /api/v1/rooms/:roomId/snapshot', async () => {
    const result = await request('GET', `/api/v1/rooms/${context.owner.room.roomId}/snapshot`, {
      token: context.owner.playerToken,
    });
    expectSuccess(result);
    assert(result.body.data.tableState.roomId === context.owner.room.roomId, '快照 roomId 不一致');
    assert(result.body.data.tableState.status === 'waiting', '等待房间状态应为 waiting');
    assert(Array.isArray(result.body.data.myHand), 'myHand 不是数组');
    assert(result.body.data.myHand.length === 0, '未开局前 myHand 应为空');
    assert(!JSON.stringify(result.body.data.tableState.seats).includes('cardId'), '座位公共信息疑似包含完整手牌');
  });

  await check('H14', 'HTTP 接口', '个人战绩接口成功', 'GET /api/v1/players/me/stats', async () => {
    const result = await request('GET', '/api/v1/players/me/stats?limit=5', {
      token: context.owner.playerToken,
    });
    expectSuccess(result);
    assert(typeof result.body.data.totalRounds === 'number', 'totalRounds 不是数字');
    assert(Array.isArray(result.body.data.recentResults), 'recentResults 不是数组');
  });

  await check('H15', 'HTTP 接口', '房间历史接口成功', 'GET /api/v1/rooms/:roomId/history', async () => {
    const result = await request('GET', `/api/v1/rooms/${context.owner.room.roomId}/history?limit=5`, {
      token: context.owner.playerToken,
    });
    expectSuccess(result);
    assert(result.body.data.roomId === context.owner.room.roomId, 'history.roomId 不一致');
    assert(Array.isArray(result.body.data.rounds), 'rounds 不是数组');
  });

  await check('H16', 'HTTP 接口', '普通玩家离开等待房释放座位', 'POST /api/v1/rooms/:roomId/leave', async () => {
    const result = await request('POST', `/api/v1/rooms/${context.owner.room.roomId}/leave`, {
      token: context.joined.playerToken,
      body: { reason: 'test_leave' },
    });
    expectSuccess(result);
    assert(result.body.data.left === true, 'left 不是 true');
    assert(result.body.data.roomClosed === false, '非房主离开等待房不应关闭房间');
    const snapshot = await request('GET', `/api/v1/rooms/${context.owner.room.roomId}/snapshot`, {
      token: context.owner.playerToken,
    });
    expectSuccess(snapshot);
    assert(snapshot.body.data.tableState.seats.filter(Boolean).length === 1, '离开后座位数量应为 1');
  });

  await check('H17', 'HTTP 接口', '加入满房时返回 ROOM_FULL', 'POST /api/v1/rooms/by-code/:roomCode/join', async () => {
    const created = await request('POST', '/api/v1/rooms', {
      body: { nickname: testNickname('full-owner'), seatIndex: 0 },
    });
    expectSuccess(created);
    const room = created.body.data;
    for (let seat = 1; seat < 6; seat += 1) {
      const joined = await request('POST', `/api/v1/rooms/by-code/${room.room.roomCode}/join`, {
        body: { nickname: testNickname(`full-${seat}`), seatIndex: seat },
      });
      expectSuccess(joined);
    }
    const full = await request('POST', `/api/v1/rooms/by-code/${room.room.roomCode}/join`, {
      body: { nickname: '第七人' },
    });
    expectError(full, 409, 'ROOM_FULL');
    await request('POST', `/api/v1/rooms/${room.room.roomId}/leave`, {
      token: room.playerToken,
      body: { reason: 'close_full_room' },
    });
  });
}

async function runWebSocketTests() {
  await check('W01', 'WebSocket', '创建联机测试房间', 'POST /api/v1/rooms + join', async () => {
    const owner = await request('POST', '/api/v1/rooms', {
      body: { nickname: testNickname('ws-owner'), seatIndex: 0 },
    });
    expectSuccess(owner);
    const joined = await request('POST', `/api/v1/rooms/by-code/${owner.body.data.room.roomCode}/join`, {
      body: { nickname: testNickname('ws-join'), seatIndex: 1 },
    });
    expectSuccess(joined);
    context.startedOwner = owner.body.data;
    context.startedJoined = joined.body.data;
    return `房间号 ${context.startedOwner.room.roomCode}`;
  });

  await check('W02', 'WebSocket', '错误 token 被拒绝连接', 'WS /ws/v1/tables/:roomId', async () => {
    await expectWsRejected(context.startedOwner.room.roomId, 'tok_wrong');
  });

  await check('W03', 'WebSocket', '连接后收到初始快照', 'WS table_snapshot', async () => {
    const ownerSocket = await openSocket(context.startedOwner.room.roomId, context.startedOwner.playerToken);
    const joinedSocket = await openSocket(context.startedJoined.room.roomId, context.startedJoined.playerToken);
    context.startedSockets.push(ownerSocket, joinedSocket);
    const ownerInitial = await ownerSocket.waitFor((message) => message.type === 'table_snapshot', 'owner 初始快照');
    const joinedInitial = await joinedSocket.waitFor((message) => message.type === 'table_snapshot', 'joined 初始快照');
    assert(ownerInitial.payload.tableState.status === 'waiting', 'owner 初始状态不是 waiting');
    assert(joinedInitial.payload.tableState.status === 'waiting', 'joined 初始状态不是 waiting');
    assert(ownerInitial.payload.myHand.length === 0, '未开局 owner myHand 应为空');
    assert(joinedInitial.payload.myHand.length === 0, '未开局 joined myHand 应为空');
  });

  await check('W04', 'WebSocket', 'ping 返回 pong', 'WS ping', async () => {
    const ownerSocket = context.startedSockets[0];
    ownerSocket.send('ping', 'ping_1');
    const pong = await ownerSocket.waitFor((message) => message.type === 'pong' && message.requestId === 'ping_1', 'pong');
    assert(pong.payload && typeof pong.payload === 'object', 'pong payload 异常');
  });

  await check('W05', 'WebSocket', '未开局时出牌被拒绝', 'WS play_cards', async () => {
    const ownerSocket = context.startedSockets[0];
    ownerSocket.send('play_cards', 'play_before_start', { cardIds: ['not-exists'] });
    const error = await ownerSocket.waitFor(
      (message) => message.type === 'error' && message.requestId === 'play_before_start',
      '未开局出牌错误响应',
    );
    assert(error.payload.code === 'GAME_NOT_STARTED', `错误码应为 GAME_NOT_STARTED，实际 ${error.payload.code}`);
  });

  await check('W06', 'WebSocket', '非房主不能开局', 'WS start_game', async () => {
    const joinedSocket = context.startedSockets[1];
    joinedSocket.send('start_game', 'join_start');
    const error = await joinedSocket.waitFor(
      (message) => message.type === 'error' && message.requestId === 'join_start',
      '非房主开局错误响应',
    );
    assert(error.payload.code === 'NOT_ROOM_OWNER', `错误码应为 NOT_ROOM_OWNER，实际 ${error.payload.code}`);
  });

  await check('W07', 'WebSocket', '房主在玩家未准备时不能开局', 'WS start_game', async () => {
    const ownerSocket = context.startedSockets[0];
    ownerSocket.send('start_game', 'not_ready_start');
    const error = await ownerSocket.waitFor(
      (message) => message.type === 'error' && message.requestId === 'not_ready_start',
      '未准备开局错误响应',
    );
    assert(error.payload.code === 'NOT_READY', `错误码应为 NOT_READY，实际 ${error.payload.code}`);
  });

  await check('W08', 'WebSocket', '玩家可换到空座位', 'WS move_seat', async () => {
    const joinedSocket = context.startedSockets[1];
    joinedSocket.send('move_seat', 'joined_move_seat', { seatIndex: 2 });
    const moved = await joinedSocket.waitFor(
      (message) => message.type === 'seat_updated' && message.requestId === 'joined_move_seat',
      '换座广播',
    );
    const seats = moved.payload.tableState.seats;
    assert(seats[1] === null, '原座位应为空');
    assert(seats[2]?.playerId === context.startedJoined.self.playerId, '目标座位不是换座玩家');
    assert(seats[2]?.team === 'B', '换到 2 号座位后应属于 B 队');
    assert(seats[2]?.ready === false, '换座后准备状态应取消');
    context.startedJoined.self.seatIndex = 2;
    context.startedJoined.self.team = 'B';
  });

  await check('W09', 'WebSocket', '房主可移出等待房玩家', 'WS kick_player', async () => {
    const owner = await request('POST', '/api/v1/rooms', {
      body: { nickname: testNickname('kick-owner'), seatIndex: 0 },
    });
    expectSuccess(owner);
    const joined = await request('POST', `/api/v1/rooms/by-code/${owner.body.data.room.roomCode}/join`, {
      body: { nickname: testNickname('kick-join'), seatIndex: 1 },
    });
    expectSuccess(joined);
    const ownerSocket = await openSocket(owner.body.data.room.roomId, owner.body.data.playerToken);
    const joinedSocket = await openSocket(joined.body.data.room.roomId, joined.body.data.playerToken);
    await ownerSocket.waitFor((message) => message.type === 'table_snapshot', '踢人房主初始快照');
    await joinedSocket.waitFor((message) => message.type === 'table_snapshot', '踢人目标初始快照');

    ownerSocket.send('kick_player', 'owner_kick_joined', { seatIndex: 1 });
    const kicked = await joinedSocket.waitFor(
      (message) => message.type === 'player_kicked',
      '被踢玩家收到通知',
    );
    assert(kicked.payload.playerId === joined.body.data.self.playerId, '被踢通知 playerId 不一致');
    const ownerEvent = await ownerSocket.waitFor(
      (message) => message.type === 'player_kicked' && message.requestId === 'owner_kick_joined',
      '房主收到踢人广播',
    );
    assert(ownerEvent.payload.seatIndex === 1, '踢人广播座位不一致');
    const snapshot = await request('GET', `/api/v1/rooms/${owner.body.data.room.roomId}/snapshot`, {
      token: owner.body.data.playerToken,
    });
    expectSuccess(snapshot);
    assert(snapshot.body.data.tableState.seats[1] === null, '被踢后座位应为空');
    const kickedSnapshot = await request('GET', `/api/v1/rooms/${owner.body.data.room.roomId}/snapshot`, {
      token: joined.body.data.playerToken,
    });
    expectError(kickedSnapshot, 401, 'INVALID_PLAYER_TOKEN');
    ownerSocket.close();
    joinedSocket.close();
    await request('POST', `/api/v1/rooms/${owner.body.data.room.roomId}/leave`, {
      token: owner.body.data.playerToken,
      body: { reason: 'close_kick_test_room' },
    });
  });

  await check('W10', 'WebSocket', 'ready 状态广播', 'WS ready', async () => {
    const ownerSocket = context.startedSockets[0];
    const joinedSocket = context.startedSockets[1];
    ownerSocket.send('ready', 'owner_ready', { ready: true });
    const ownerAck = await ownerSocket.waitFor(
      (message) => message.type === 'seat_updated' && message.requestId === 'owner_ready',
      'owner ready ack',
    );
    assert(ownerAck.payload.seat.ready === true, 'owner ready 未变为 true');
    joinedSocket.send('ready', 'joined_ready', { ready: true });
    const joinedAck = await joinedSocket.waitFor(
      (message) => message.type === 'seat_updated' && message.requestId === 'joined_ready',
      'joined ready ack',
    );
    assert(joinedAck.payload.seat.ready === true, 'joined ready 未变为 true');
  });

  await check('W11', 'WebSocket', '房主开局成功，AI 补齐且仅返回自己的手牌', 'WS start_game', async () => {
    const ownerSocket = context.startedSockets[0];
    ownerSocket.send('start_game', 'owner_start');
    const started = await ownerSocket.waitFor(
      (message) => message.type === 'game_started' && message.requestId === 'owner_start',
      'game_started',
    );
    assert(started.payload.tableState.status === 'playing', '开局后状态不是 playing');
    assert(started.payload.tableState.seats.filter(Boolean).length === 6, '开局后应有 6 个座位');
    assert(started.payload.tableState.seats.filter((seat) => seat?.isAi).length === 4, '应补齐 4 个 AI');
    assert(started.payload.myHand.length === 9, 'owner 应收到 9 张自己的手牌');
    assert(!JSON.stringify(started.payload.tableState.seats).includes('cardId'), '公共座位信息疑似泄露手牌');
  });

  await check('W12', 'HTTP 接口', '开局后禁止新玩家加入', 'POST /api/v1/rooms/by-code/:roomCode/join', async () => {
    const result = await request('POST', `/api/v1/rooms/by-code/${context.startedOwner.room.roomCode}/join`, {
      body: { nickname: '迟到玩家', seatIndex: 2 },
    });
    expectError(result, 409, 'ROOM_ALREADY_PLAYING');
  });

  await check('W13', 'WebSocket', 'sync_state 返回最新快照', 'WS sync_state', async () => {
    const ownerSocket = context.startedSockets[0];
    ownerSocket.send('sync_state', 'sync_after_start');
    const snapshot = await ownerSocket.waitFor(
      (message) => message.type === 'table_snapshot' && message.requestId === 'sync_after_start',
      'sync_state 快照',
    );
    assert(snapshot.payload.tableState.status === 'playing', 'sync_state 状态不是 playing');
    assert(snapshot.payload.myHand.length === 9, 'sync_state owner 手牌不是 9 张');
  });

  await check('W14', 'WebSocket', '非当前回合出牌被拒绝', 'WS play_cards', async () => {
    const ownerSocket = context.startedSockets[0];
    const joinedSocket = context.startedSockets[1];
    ownerSocket.send('sync_state', 'owner_turn_probe');
    joinedSocket.send('sync_state', 'joined_turn_probe');
    const ownerSnapshot = await ownerSocket.waitFor(
      (message) => message.type === 'table_snapshot' && message.requestId === 'owner_turn_probe',
      'owner turn probe',
    );
    const joinedSnapshot = await joinedSocket.waitFor(
      (message) => message.type === 'table_snapshot' && message.requestId === 'joined_turn_probe',
      'joined turn probe',
    );
    const currentSeat = ownerSnapshot.payload.tableState.currentTurnSeatIndex;
    const ownerSeat = context.startedOwner.self.seatIndex;
    const joinedSeat = context.startedJoined.self.seatIndex;
    const notCurrent = currentSeat === ownerSeat ? joinedSocket : ownerSocket;
    const notCurrentHand = currentSeat === ownerSeat ? joinedSnapshot.payload.myHand : ownerSnapshot.payload.myHand;
    assert(notCurrentHand.length > 0, '非当前玩家没有可提交的手牌');
    notCurrent.send('play_cards', 'not_your_turn', { cardIds: [notCurrentHand[0].cardId] });
    const error = await notCurrent.waitFor(
      (message) => message.type === 'error' && message.requestId === 'not_your_turn',
      '非当前回合出牌错误响应',
    );
    assert(error.payload.code === 'NOT_YOUR_TURN', `错误码应为 NOT_YOUR_TURN，实际 ${error.payload.code}`);
  });

  await check('W15', 'WebSocket', '当前玩家提交不存在的牌被拒绝', 'WS play_cards', async () => {
    const turn = await waitForHumanTurn('invalid_card_probe');
    turn.socket.send('play_cards', 'invalid_cards', { cardIds: ['not-a-card'] });
    const error = await turn.socket.waitFor(
      (message) => message.type === 'error' && message.requestId === 'invalid_cards',
      '不存在牌错误响应',
    );
    assert(error.payload.code === 'INVALID_CARDS', `错误码应为 INVALID_CARDS，实际 ${error.payload.code}`);
  });

  await check('W16', 'WebSocket', '当前玩家领出时不能过牌', 'WS pass', async () => {
    const turn = await waitForHumanTurn('pass_probe');
    if (turn.snapshot.payload.tableState.tableCombo) {
      return '当前桌面已有牌，此局面不是领出，跳过领出过牌校验';
    }
    turn.socket.send('pass', 'lead_pass');
    const error = await turn.socket.waitFor(
      (message) => message.type === 'error' && message.requestId === 'lead_pass',
      '领出过牌错误响应',
    );
    assert(error.payload.code === 'INVALID_REQUEST', `错误码应为 INVALID_REQUEST，实际 ${error.payload.code}`);
  });

  await check('W17', 'WebSocket', '当前玩家合法出牌或可过牌操作', 'WS play_cards/pass', async () => {
    const turn = await waitForHumanTurn('play_probe');
    const playable = findPlayableCards(
      turn.snapshot.payload.myHand,
      turn.snapshot.payload.tableState.tableCombo,
    );
    if (playable.length > 0) {
      turn.socket.send('play_cards', 'valid_play', { cardIds: playable.map((card) => card.cardId) });
      const message = await turn.socket.waitFor(
        (candidate) => candidate.requestId === 'valid_play' &&
          (candidate.type === 'table_snapshot' || candidate.type === 'game_started' || candidate.type === 'error'),
        '合法出牌响应',
      );
      assert(message.type !== 'error', `合法出牌被拒绝：${JSON.stringify(message.payload)}`);
      assert(message.payload.tableState.status === 'playing' || message.payload.tableState.status === 'settled', '出牌后状态异常');
      return `提交 ${playable.length} 张牌成功`;
    }
    assert(turn.snapshot.payload.tableState.tableCombo, '无可出牌且桌面无目标牌，无法验证过牌');
    turn.socket.send('pass', 'valid_pass');
    const message = await turn.socket.waitFor(
      (candidate) => candidate.requestId === 'valid_pass' &&
        (candidate.type === 'player_passed' || candidate.type === 'new_lead_started' || candidate.type === 'table_snapshot' || candidate.type === 'error'),
      '合法过牌响应',
    );
    assert(message.type !== 'error', `合法过牌被拒绝：${JSON.stringify(message.payload)}`);
    return '无可压牌，合法过牌成功';
  });

  await check('W18', 'WebSocket', '断线后用同 token 重连可恢复快照', 'WS reconnect', async () => {
    const temporary = await openSocket(context.startedOwner.room.roomId, context.startedOwner.playerToken);
    const initial = await temporary.waitFor((message) => message.type === 'table_snapshot', '临时连接初始快照');
    assert(initial.payload.tableState.roomId === context.startedOwner.room.roomId, '临时连接 roomId 异常');
    temporary.close();
    await new Promise((resolve) => setTimeout(resolve, 150));
    const reconnected = await openSocket(context.startedOwner.room.roomId, context.startedOwner.playerToken);
    const snapshot = await reconnected.waitFor((message) => message.type === 'table_snapshot', '重连快照');
    assert(snapshot.payload.tableState.roomId === context.startedOwner.room.roomId, '重连 roomId 异常');
    assert(Array.isArray(snapshot.payload.myHand), '重连 myHand 不是数组');
    reconnected.close();
  });
}

function escapeCell(value) {
  return String(value ?? '')
    .replace(/\|/g, '\\|')
    .replace(/\n/g, '<br>');
}

async function writeReport() {
  await fs.mkdir(REPORT_DIR, { recursive: true });
  const file = path.join(REPORT_DIR, `backend-interface-test-${reportStamp()}.md`);
  const total = results.length;
  const passed = results.filter((result) => result.status === '通过').length;
  const failed = results.filter((result) => result.status === '失败').length;
  const skipped = results.filter((result) => result.status === '跳过').length;
  const hasProblem = failed > 0;
  const groups = [...new Set(results.map((result) => result.group))];
  const lines = [];

  lines.push('# DoorSix 后端接口测试报告');
  lines.push('');
  lines.push(`- 测试时间：${nowText()}`);
  lines.push(`- 测试地址：${context.baseUrl}`);
  lines.push(`- 测试模式：${context.localServer ? '本地自动拉起服务（内存状态）' : '外部服务'}`);
  lines.push(`- 测试结论：${hasProblem ? '后端存在需要处理的问题' : '未发现后端接口阻断性问题'}`);
  lines.push(`- 汇总：共 ${total} 项，通过 ${passed} 项，失败 ${failed} 项，跳过 ${skipped} 项`);
  lines.push('');

  if (hasProblem) {
    lines.push('## 失败项');
    lines.push('');
    lines.push('| 编号 | 测试对象 | 场景 | 问题 |');
    lines.push('| --- | --- | --- | --- |');
    for (const result of results.filter((item) => item.status === '失败')) {
      lines.push(`| ${result.id} | ${escapeCell(result.target)} | ${escapeCell(result.name)} | ${escapeCell(result.detail)} |`);
    }
    lines.push('');
  }

  for (const group of groups) {
    lines.push(`## ${group}`);
    lines.push('');
    lines.push('| 编号 | 测试对象 | 场景 | 结果 | 耗时 | 说明 |');
    lines.push('| --- | --- | --- | --- | ---: | --- |');
    for (const result of results.filter((item) => item.group === group)) {
      const icon = result.status === '通过' ? '通过' : result.status === '失败' ? '失败' : '跳过';
      lines.push(`| ${result.id} | ${escapeCell(result.target)} | ${escapeCell(result.name)} | ${icon} | ${result.durationMs}ms | ${escapeCell(result.detail)} |`);
    }
    lines.push('');
  }

  lines.push('## 接口健康判断');
  lines.push('');
  lines.push('| 接口/消息 | 是否发现问题 | 覆盖点 |');
  lines.push('| --- | --- | --- |');
  for (const target of [...new Set(results.map((result) => result.target))]) {
    const related = results.filter((result) => result.target === target);
    const failedRelated = related.filter((result) => result.status === '失败');
    lines.push(`| ${escapeCell(target)} | ${failedRelated.length ? '有问题' : '未发现问题'} | ${related.map((result) => result.id).join('、')} |`);
  }
  lines.push('');
  lines.push('## 备注');
  lines.push('');
  lines.push('- 本程序重点判断后端 HTTP 接口、WebSocket 鉴权、状态同步、开局、出牌/过牌基础行为是否符合测试计划。');
  lines.push('- 如果测试模式为本地自动拉起服务，则 Redis 会被显式置空，报告中的 Redis=false 属于预期；远程部署可通过 `BACKEND_TEST_BASE_URL` 指定地址后再测。');
  lines.push('- 牌局存在随机发牌，本报告对合法出牌会动态计算当前玩家可出的牌；如果当前局面只能过牌，会以合法过牌验证替代。');

  await fs.writeFile(file, `${lines.join('\n')}\n`, 'utf8');
  return file;
}

async function main() {
  try {
    await startLocalServerIfNeeded();
    console.log(`DoorSix 后端接口测试：${context.baseUrl}`);
    await runHttpTests();
    await runWebSocketTests();
  } finally {
    await cleanup();
  }

  const reportFile = await writeReport();
  const failed = results.filter((result) => result.status === '失败');
  console.log('');
  console.log(`测试报告已生成：${reportFile}`);
  if (failed.length) {
    console.log(`发现 ${failed.length} 个问题：`);
    for (const result of failed) {
      console.log(`- ${result.id} ${result.target} ${result.name}：${result.detail}`);
    }
    process.exitCode = 1;
  } else {
    console.log('未发现后端接口阻断性问题。');
  }
}

main().catch(async (error) => {
  results.push({
    id: 'BOOT',
    group: '测试程序',
    name: '测试程序执行',
    target: 'backend-interface-test',
    status: '失败',
    durationMs: 0,
    detail: error.stack || error.message,
  });
  try {
    const reportFile = await writeReport();
    console.error(`测试程序异常，报告已生成：${reportFile}`);
  } catch (_) {
    // ignore report failure
  }
  console.error(error);
  if (context.localServer) context.localServer.kill();
  process.exit(1);
});
