const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const http = require('node:http');
const path = require('node:path');

const cors = require('cors');
const express = require('express');
const { createClient } = require('redis');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || `http://localhost:${PORT}`;
const REDIS_URL = process.env.REDIS_URL || '';
const ROOM_TTL_SECONDS = Number(process.env.ROOM_TTL_SECONDS || 7200);
const MATCH_LOG_DIR = process.env.MATCH_LOG_DIR || path.join(process.cwd(), 'logs', 'matches');

const RULE_SET_ID = 'zha_liujia_tianjin_basic_v1';
const MAX_PLAYERS = 6;
const TEAM_BY_SEAT = ['B', 'A', 'B', 'A', 'B', 'A'];
const COMBO_TYPES = ['invalid', 'single', 'pair', 'triple', 'quad'];
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
const RANK_LABEL = {
  small_joker: '小王',
  big_joker: '大王',
};
const WILD_RANKS = new Set(['big_joker', 'small_joker', '3', '2']);

function now() {
  return Date.now();
}

function id(prefix) {
  return `${prefix}_${crypto.randomBytes(8).toString('hex')}`;
}

function roomCode() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, '0');
}

function requestId(req) {
  return req.headers['x-request-id'] || id('req');
}

function ok(req, res, data, meta) {
  res.json({ success: true, requestId: requestId(req), data, meta, error: null });
}

function fail(req, res, status, code, message) {
  res.status(status).json({
    success: false,
    requestId: requestId(req),
    data: null,
    error: { code, message },
  });
}

function teamForSeat(seatIndex) {
  return TEAM_BY_SEAT[seatIndex];
}

function validateSeatIndex(seatIndex) {
  return Number.isInteger(seatIndex) && seatIndex >= 0 && seatIndex < MAX_PLAYERS;
}

function normalizeNickname(value) {
  const nickname = String(value || '').trim();
  return nickname.slice(0, 24);
}

function wsUrlFor(roomId) {
  const url = new URL(PUBLIC_BASE_URL);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.pathname = `/ws/v1/tables/${roomId}`;
  url.search = '';
  return url.toString();
}

class StateStore {
  constructor() {
    this.redis = null;
    this.memory = {
      rooms: new Map(),
      codes: new Map(),
      tokens: new Map(),
    };
  }

  async connect() {
    if (!REDIS_URL) {
      console.warn('[store] REDIS_URL not set, using in-memory state');
      return;
    }

    const client = createClient({ url: REDIS_URL });
    client.on('error', (error) => {
      console.error('[redis]', error.message);
    });

    try {
      await client.connect();
      await client.ping();
      this.redis = client;
      console.log('[store] connected to redis');
    } catch (error) {
      console.warn(`[store] redis unavailable, using in-memory state: ${error.message}`);
      try {
        await client.disconnect();
      } catch (_) {
        // ignore disconnect errors
      }
    }
  }

  async getRoom(roomId) {
    if (this.redis) {
      const raw = await this.redis.get(`room:${roomId}:state`);
      return raw ? JSON.parse(raw) : null;
    }
    return this.memory.rooms.get(roomId) || null;
  }

  async setRoom(state) {
    if (this.redis) {
      await this.redis.set(`room:${state.room.roomId}:state`, JSON.stringify(state), {
        EX: ROOM_TTL_SECONDS,
      });
      await this.redis.set(`room_code:${state.room.roomCode}`, state.room.roomId, {
        EX: ROOM_TTL_SECONDS,
      });
      for (const [token, playerId] of Object.entries(state.tokens)) {
        await this.redis.set(`player_token:${token}`, JSON.stringify({
          roomId: state.room.roomId,
          playerId,
        }), { EX: ROOM_TTL_SECONDS });
      }
      return;
    }

    this.memory.rooms.set(state.room.roomId, state);
    this.memory.codes.set(state.room.roomCode, state.room.roomId);
    for (const [token, playerId] of Object.entries(state.tokens)) {
      this.memory.tokens.set(token, { roomId: state.room.roomId, playerId });
    }
  }

  async deleteRoom(state) {
    if (this.redis) {
      await this.redis.del(`room:${state.room.roomId}:state`);
      await this.redis.del(`room_code:${state.room.roomCode}`);
      for (const token of Object.keys(state.tokens)) {
        await this.redis.del(`player_token:${token}`);
      }
      return;
    }
    this.memory.rooms.delete(state.room.roomId);
    this.memory.codes.delete(state.room.roomCode);
    for (const token of Object.keys(state.tokens)) {
      this.memory.tokens.delete(token);
    }
  }

  async getRoomIdByCode(code) {
    if (this.redis) {
      return this.redis.get(`room_code:${code}`);
    }
    return this.memory.codes.get(code) || null;
  }

  async getSessionByToken(token) {
    if (this.redis) {
      const raw = await this.redis.get(`player_token:${token}`);
      return raw ? JSON.parse(raw) : null;
    }
    return this.memory.tokens.get(token) || null;
  }
}

const store = new StateStore();
const socketsByRoom = new Map();

function createDeck() {
  const cards = [];
  const suits = ['spades', 'hearts', 'diamonds', 'clubs'];
  const ranks = ['3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A', '2'];
  for (const suit of suits) {
    for (const rank of ranks) {
      cards.push({
        cardId: `d0-${suit}-${rank}`,
        deckIndex: 0,
        suit,
        rank,
      });
    }
  }
  cards.push({ cardId: 'd0-small-joker', deckIndex: 0, suit: 'joker', rank: 'small_joker' });
  cards.push({ cardId: 'd0-big-joker', deckIndex: 0, suit: 'joker', rank: 'big_joker' });
  return cards;
}

function shuffle(cards) {
  const deck = cards.slice();
  for (let i = deck.length - 1; i > 0; i -= 1) {
    const j = crypto.randomInt(0, i + 1);
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

function sortCards(cards) {
  return cards.slice().sort((a, b) => {
    const rank = RANK_STRENGTH[a.rank] - RANK_STRENGTH[b.rank];
    if (rank !== 0) return rank;
    const suit = a.suit.localeCompare(b.suit);
    if (suit !== 0) return suit;
    return a.cardId.localeCompare(b.cardId);
  });
}

function dealHands() {
  const deck = shuffle(createDeck());
  const hands = Array.from({ length: MAX_PLAYERS }, () => []);
  deck.forEach((card, index) => {
    hands[index % MAX_PLAYERS].push(card);
  });
  return hands.map(sortCards);
}

function cardLabel(rank) {
  return RANK_LABEL[rank] || rank;
}

function effectiveRank(cards) {
  if (cards.length === 1) return cards[0].rank;
  const naturalRanks = new Set(cards.filter((card) => !WILD_RANKS.has(card.rank)).map((card) => card.rank));
  if (naturalRanks.size > 1) return null;
  if (naturalRanks.size === 1) return [...naturalRanks][0];
  return '3';
}

function evaluateCombo(cards) {
  if (!Array.isArray(cards) || cards.length < 1 || cards.length > 4) {
    return { comboType: 'invalid', rankStrength: 0, cardIds: [], label: '牌型不成立' };
  }
  const rank = effectiveRank(cards);
  if (!rank) {
    return { comboType: 'invalid', rankStrength: 0, cardIds: cards.map((card) => card.cardId), label: '牌型不成立' };
  }
  const comboType = COMBO_TYPES[cards.length];
  const typeLabel = {
    single: '单张',
    pair: '对子',
    triple: '三张',
    quad: '四张',
  }[comboType];
  return {
    comboType,
    rankStrength: RANK_STRENGTH[rank],
    cardIds: cards.map((card) => card.cardId),
    label: `${typeLabel} ${cardLabel(rank)}`,
    effectiveRank: rank,
  };
}

function canBeat(candidate, target) {
  if (!candidate || candidate.comboType === 'invalid') return false;
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

function suggestCards(hand, target) {
  if (!target) return hand.length ? [sortCards(hand)[0]] : [];
  const candidates = [];
  const sorted = sortCards(hand);
  for (let size = 1; size <= Math.min(4, sorted.length); size += 1) {
    candidates.push(...combinations(sorted, size));
  }
  candidates.sort((a, b) => {
    const ca = evaluateCombo(a);
    const cb = evaluateCombo(b);
    const type = COMBO_TYPES.indexOf(ca.comboType) - COMBO_TYPES.indexOf(cb.comboType);
    if (type !== 0) return type;
    return ca.rankStrength - cb.rankStrength;
  });
  return candidates.find((cards) => canBeat(evaluateCombo(cards), target)) || [];
}

function publicRoom(room) {
  return {
    roomId: room.roomId,
    roomCode: room.roomCode,
    ownerPlayerId: room.ownerPlayerId,
    status: room.status,
    playerCount: room.playerCount,
    maxPlayers: MAX_PLAYERS,
    ruleSetId: RULE_SET_ID,
    createdAt: room.createdAt,
    expiresAt: room.expiresAt,
  };
}

function seatView(seat) {
  return seat ? {
    seatIndex: seat.seatIndex,
    playerId: seat.playerId,
    nickname: seat.nickname,
    team: seat.team,
    isAi: seat.isAi,
    ready: seat.ready,
    connected: seat.connected,
    cardCount: seat.cardCount || 0,
    finishRank: seat.finishRank ?? null,
  } : null;
}

function tableStateFor(state) {
  return {
    roomId: state.room.roomId,
    gameId: state.game.gameId,
    roundNo: state.game.roundNo,
    status: state.room.status,
    ruleSetId: RULE_SET_ID,
    ownerPlayerId: state.room.ownerPlayerId,
    currentTurnSeatIndex: state.game.currentTurnSeatIndex,
    lastPlayedSeatIndex: state.game.lastPlayedSeatIndex,
    passCount: state.game.passCount,
    tableCombo: state.game.tableCombo,
    seats: state.seats.map(seatView),
    finishOrder: state.game.finishOrder,
    score: state.game.score,
  };
}

function snapshotFor(state, playerId) {
  return {
    tableState: tableStateFor(state),
    myHand: sortCards(state.hands[playerId] || []),
    eventSeq: state.eventSeq,
  };
}

function findPlayerByToken(state, token) {
  const playerId = state.tokens[token];
  if (!playerId) return null;
  const seat = state.seats.find((candidate) => candidate && candidate.playerId === playerId);
  return seat ? { playerId, seat } : null;
}

async function authenticateRoomRequest(req, res) {
  const token = req.headers['x-player-token'];
  if (!token) {
    fail(req, res, 401, 'INVALID_PLAYER_TOKEN', '房间内身份无效');
    return null;
  }
  const state = await store.getRoom(req.params.roomId);
  if (!state) {
    fail(req, res, 404, 'ROOM_NOT_FOUND', '房间不存在');
    return null;
  }
  const auth = findPlayerByToken(state, token);
  if (!auth) {
    fail(req, res, 401, 'INVALID_PLAYER_TOKEN', '房间内身份无效');
    return null;
  }
  return { state, auth, token };
}

function createInitialState(nickname, requestedSeatIndex) {
  const createdAt = now();
  const roomId = id('r');
  const playerId = id('p');
  const token = id('tok');
  const seatIndex = validateSeatIndex(requestedSeatIndex) ? requestedSeatIndex : 0;
  const code = roomCode();
  const seats = Array.from({ length: MAX_PLAYERS }, (_, index) => null);
  seats[seatIndex] = {
    seatIndex,
    playerId,
    nickname,
    team: teamForSeat(seatIndex),
    isAi: false,
    ready: false,
    connected: false,
    cardCount: 0,
    finishRank: null,
  };
  return {
    room: {
      roomId,
      roomCode: code,
      ownerPlayerId: playerId,
      status: 'waiting',
      playerCount: 1,
      maxPlayers: MAX_PLAYERS,
      ruleSetId: RULE_SET_ID,
      createdAt,
      expiresAt: createdAt + ROOM_TTL_SECONDS * 1000,
    },
    seats,
    tokens: { [token]: playerId },
    hands: {},
    game: {
      gameId: null,
      roundNo: 0,
      currentTurnSeatIndex: null,
      lastPlayedSeatIndex: null,
      passCount: 0,
      tableCombo: null,
      finishOrder: [],
      score: { teamA: 0, teamB: 0 },
      settled: false,
    },
    eventSeq: 0,
  };
}

function nextEventSeq(state) {
  state.eventSeq += 1;
  return state.eventSeq;
}

function activeSeats(state) {
  return state.seats.filter((seat) => seat && seat.finishRank == null);
}

function advanceTurn(state) {
  let next = (state.game.currentTurnSeatIndex + 1) % MAX_PLAYERS;
  while (state.seats[next]?.finishRank != null) {
    next = (next + 1) % MAX_PLAYERS;
  }
  state.game.currentTurnSeatIndex = next;
  return next;
}

function findFirstLeadSeat(handsBySeat) {
  for (let seat = 0; seat < handsBySeat.length; seat += 1) {
    if (handsBySeat[seat].some((card) => card.suit === 'hearts' && card.rank === '4')) {
      return seat;
    }
  }
  return 0;
}

async function appendMatchLog(state, result) {
  await fs.mkdir(MATCH_LOG_DIR, { recursive: true });
  const date = new Date().toISOString().slice(0, 10);
  const file = path.join(MATCH_LOG_DIR, `${date}.ndjson`);
  const players = state.seats.filter(Boolean).map((seat) => ({
    seatIndex: seat.seatIndex,
    playerId: seat.playerId,
    nickname: seat.nickname,
    team: seat.team,
    isAi: seat.isAi,
  }));
  const log = {
    logType: 'round_settled',
    logVersion: 1,
    createdAt: now(),
    roomId: state.room.roomId,
    roomCode: state.room.roomCode,
    gameId: state.game.gameId,
    roundNo: state.game.roundNo,
    ruleSetId: RULE_SET_ID,
    winnerTeam: result.winnerTeam,
    finishOrder: state.game.finishOrder,
    caughtPlayers: result.caughtPlayers,
    scoreDelta: result.scoreDelta,
    totalScoreAfterRound: state.game.score,
    players,
    settlementReason: 'basic_gong_no_teammate_left_home',
  };
  await fs.appendFile(file, `${JSON.stringify(log)}\n`, 'utf8');
}

function settleIfNeeded(state) {
  if (state.game.settled || state.game.finishOrder.length < MAX_PLAYERS - 1) {
    return null;
  }

  const first = state.game.finishOrder[0];
  const unfinished = state.seats.find((seat) => seat && seat.finishRank == null);
  const lastHome = unfinished || state.game.finishOrder[state.game.finishOrder.length - 1];
  const winnerTeam = first.team === lastHome.team ? (first.team === 'A' ? 'B' : 'A') : first.team;
  const caughtPlayers = state.seats
    .filter((seat) => seat && seat.team !== winnerTeam && seat.finishRank == null)
    .map((seat) => ({
      seatIndex: seat.seatIndex,
      playerId: seat.playerId,
      nickname: seat.nickname,
      team: seat.team,
    }));
  const delta = 3 + caughtPlayers.length;
  const scoreDelta = {
    teamA: winnerTeam === 'A' ? delta : 0,
    teamB: winnerTeam === 'B' ? delta : 0,
  };
  state.game.score.teamA += scoreDelta.teamA;
  state.game.score.teamB += scoreDelta.teamB;
  state.game.settled = true;
  state.room.status = 'settled';
  return {
    gameId: state.game.gameId,
    roundNo: state.game.roundNo,
    winnerTeam,
    finishOrder: state.game.finishOrder,
    caughtPlayers,
    scoreDelta,
    totalScore: state.game.score,
    settlementReason: 'basic_gong_no_teammate_left_home',
  };
}

async function broadcast(roomId, message, options = {}) {
  const sockets = socketsByRoom.get(roomId);
  if (!sockets) return;
  for (const ws of sockets) {
    if (ws.readyState !== ws.OPEN) continue;
    if (options.excludePlayerId && ws.playerId === options.excludePlayerId) continue;
    ws.send(JSON.stringify(message));
  }
}

async function sendSnapshot(ws, state, requestIdValue, type = 'table_snapshot') {
  ws.send(JSON.stringify({
    type,
    requestId: requestIdValue || null,
    roomId: state.room.roomId,
    eventSeq: state.eventSeq,
    serverTime: now(),
    payload: snapshotFor(state, ws.playerId),
  }));
}

async function broadcastStateSnapshots(state, type, requestIdValue) {
  const sockets = socketsByRoom.get(state.room.roomId);
  if (!sockets) return;
  for (const ws of sockets) {
    if (ws.readyState === ws.OPEN) {
      await sendSnapshot(ws, state, requestIdValue, type);
    }
  }
}

function ensureAiSeats(state) {
  for (let seatIndex = 0; seatIndex < MAX_PLAYERS; seatIndex += 1) {
    if (!state.seats[seatIndex]) {
      const playerId = `ai_${seatIndex}_${crypto.randomBytes(3).toString('hex')}`;
      state.seats[seatIndex] = {
        seatIndex,
        playerId,
        nickname: `AI ${seatIndex + 1}`,
        team: teamForSeat(seatIndex),
        isAi: true,
        ready: true,
        connected: false,
        cardCount: 0,
        finishRank: null,
      };
    }
  }
  state.room.playerCount = state.seats.filter((seat) => seat && !seat.isAi).length;
}

function startGame(state) {
  ensureAiSeats(state);
  const handsBySeat = dealHands();
  state.hands = {};
  state.seats.forEach((seat, seatIndex) => {
    state.hands[seat.playerId] = handsBySeat[seatIndex];
    seat.cardCount = handsBySeat[seatIndex].length;
    seat.ready = true;
    seat.finishRank = null;
  });
  state.room.status = 'playing';
  state.game.gameId = id('g');
  state.game.roundNo += 1;
  state.game.currentTurnSeatIndex = findFirstLeadSeat(handsBySeat);
  state.game.lastPlayedSeatIndex = null;
  state.game.passCount = 0;
  state.game.tableCombo = null;
  state.game.finishOrder = [];
  state.game.settled = false;
}

function cardsByIds(hand, cardIds) {
  if (!Array.isArray(cardIds) || cardIds.length === 0) return null;
  const unique = new Set(cardIds);
  if (unique.size !== cardIds.length) return null;
  const map = new Map(hand.map((card) => [card.cardId, card]));
  const cards = cardIds.map((cardId) => map.get(cardId));
  if (cards.some((card) => !card)) return null;
  return cards;
}

async function playCards(state, seat, cards) {
  const hand = state.hands[seat.playerId] || [];
  const combo = evaluateCombo(cards);
  if (combo.comboType === 'invalid') {
    return { error: ['INVALID_COMBO', '牌型不合法'] };
  }
  if (!canBeat(combo, state.game.tableCombo)) {
    return { error: ['CANNOT_BEAT_TABLE_COMBO', '压不过当前桌面牌型'] };
  }

  const ids = new Set(cards.map((card) => card.cardId));
  state.hands[seat.playerId] = hand.filter((card) => !ids.has(card.cardId));
  seat.cardCount = state.hands[seat.playerId].length;
  state.game.tableCombo = combo;
  state.game.lastPlayedSeatIndex = seat.seatIndex;
  state.game.passCount = 0;

  let finishRank = null;
  if (seat.cardCount === 0 && seat.finishRank == null) {
    finishRank = state.game.finishOrder.length + 1;
    seat.finishRank = finishRank;
    state.game.finishOrder.push({
      seatIndex: seat.seatIndex,
      playerId: seat.playerId,
      nickname: seat.nickname,
      team: seat.team,
      rank: finishRank,
    });
  }

  const settlement = settleIfNeeded(state);
  if (!settlement) {
    advanceTurn(state);
  }
  return { combo, finishRank, settlement };
}

async function passTurn(state, seat) {
  if (!state.game.tableCombo) {
    return { error: ['INVALID_REQUEST', '新一轮领出不能过牌'] };
  }
  state.game.passCount += 1;
  let newLead = false;
  if (state.game.passCount >= activeSeats(state).length - 1) {
    newLead = true;
    state.game.tableCombo = null;
    state.game.passCount = 0;
    state.game.currentTurnSeatIndex = state.game.lastPlayedSeatIndex;
  } else {
    advanceTurn(state);
  }
  return { newLead };
}

async function runAiTurns(state) {
  let safety = 200;
  const events = [];
  while (safety > 0 && state.room.status === 'playing') {
    safety -= 1;
    const seat = state.seats[state.game.currentTurnSeatIndex];
    if (!seat?.isAi || seat.finishRank != null) break;

    const suggestion = suggestCards(state.hands[seat.playerId] || [], state.game.tableCombo);
    if (suggestion.length === 0) {
      const passed = await passTurn(state, seat);
      events.push({ kind: 'pass', seat, result: passed });
    } else {
      const played = await playCards(state, seat, suggestion);
      events.push({ kind: 'play', seat, result: played });
      if (played.settlement) break;
    }
  }
  return events;
}

async function loadLogs() {
  try {
    const names = await fs.readdir(MATCH_LOG_DIR);
    const files = names.filter((name) => name.endsWith('.ndjson')).sort();
    const logs = [];
    for (const name of files) {
      const content = await fs.readFile(path.join(MATCH_LOG_DIR, name), 'utf8');
      for (const line of content.split('\n')) {
        if (line.trim()) logs.push(JSON.parse(line));
      }
    }
    return logs;
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
}

async function resolveToken(token) {
  const session = await store.getSessionByToken(token);
  if (!session) return null;
  const state = await store.getRoom(session.roomId);
  if (!state) return null;
  const seat = state.seats.find((candidate) => candidate && candidate.playerId === session.playerId);
  return seat ? { state, playerId: session.playerId, seat } : null;
}

const app = express();
app.use(cors());
app.use(express.json({ limit: '128kb' }));

app.get('/health', async (_req, res) => {
  res.json({
    ok: true,
    service: 'doorsix-server',
    ruleSetId: RULE_SET_ID,
    redis: Boolean(store.redis),
    serverTime: now(),
  });
});

app.post('/api/v1/rooms', async (req, res) => {
  const nickname = normalizeNickname(req.body?.nickname);
  if (!nickname) return fail(req, res, 400, 'INVALID_REQUEST', '昵称不能为空');
  const seatIndex = req.body?.seatIndex;
  if (seatIndex != null && !validateSeatIndex(seatIndex)) {
    return fail(req, res, 400, 'INVALID_REQUEST', '座位号必须是 0 到 5');
  }

  let state;
  do {
    state = createInitialState(nickname, seatIndex);
  } while (await store.getRoomIdByCode(state.room.roomCode));

  await store.setRoom(state);
  const token = Object.keys(state.tokens)[0];
  const self = state.seats.find((seat) => seat?.playerId === state.tokens[token]);
  ok(req, res, {
    room: publicRoom(state.room),
    self: seatView(self),
    playerToken: token,
    webSocketUrl: wsUrlFor(state.room.roomId),
  });
});

app.get('/api/v1/rooms/by-code/:roomCode', async (req, res) => {
  const roomId = await store.getRoomIdByCode(req.params.roomCode);
  const state = roomId ? await store.getRoom(roomId) : null;
  if (!state) return fail(req, res, 404, 'ROOM_NOT_FOUND', '房间不存在');
  ok(req, res, {
    room: publicRoom(state.room),
    joinable: state.room.status === 'waiting' && state.seats.filter(Boolean).length < MAX_PLAYERS,
  });
});

app.post('/api/v1/rooms/by-code/:roomCode/join', async (req, res) => {
  const nickname = normalizeNickname(req.body?.nickname);
  if (!nickname) return fail(req, res, 400, 'INVALID_REQUEST', '昵称不能为空');
  const roomId = await store.getRoomIdByCode(req.params.roomCode);
  const state = roomId ? await store.getRoom(roomId) : null;
  if (!state) return fail(req, res, 404, 'ROOM_NOT_FOUND', '房间不存在');
  if (state.room.status !== 'waiting') return fail(req, res, 409, 'ROOM_ALREADY_PLAYING', '房间已开局');

  let seatIndex = req.body?.seatIndex;
  if (seatIndex != null && !validateSeatIndex(seatIndex)) {
    return fail(req, res, 400, 'INVALID_REQUEST', '座位号必须是 0 到 5');
  }
  if (seatIndex == null) {
    seatIndex = state.seats.findIndex((seat) => !seat);
  }
  if (seatIndex === -1) return fail(req, res, 409, 'ROOM_FULL', '房间已满');
  if (state.seats[seatIndex]) return fail(req, res, 409, 'SEAT_TAKEN', '座位已被占用');

  const playerId = id('p');
  const token = id('tok');
  const seat = {
    seatIndex,
    playerId,
    nickname,
    team: teamForSeat(seatIndex),
    isAi: false,
    ready: false,
    connected: false,
    cardCount: 0,
    finishRank: null,
  };
  state.seats[seatIndex] = seat;
  state.tokens[token] = playerId;
  state.room.playerCount = state.seats.filter((candidate) => candidate && !candidate.isAi).length;
  nextEventSeq(state);
  await store.setRoom(state);
  await broadcast(state.room.roomId, {
    type: 'player_joined',
    roomId: state.room.roomId,
    eventSeq: state.eventSeq,
    serverTime: now(),
    payload: { seat: seatView(seat) },
  });
  ok(req, res, {
    room: publicRoom(state.room),
    self: seatView(seat),
    playerToken: token,
    webSocketUrl: wsUrlFor(state.room.roomId),
  });
});

app.post('/api/v1/rooms/:roomId/leave', async (req, res) => {
  const authenticated = await authenticateRoomRequest(req, res);
  if (!authenticated) return;
  const { state, auth, token } = authenticated;
  const roomClosed = auth.playerId === state.room.ownerPlayerId || state.room.status !== 'waiting';
  if (roomClosed) {
    state.room.status = 'closed';
    await store.deleteRoom(state);
  } else {
    state.seats[auth.seat.seatIndex] = null;
    delete state.tokens[token];
    state.room.playerCount = state.seats.filter((seat) => seat && !seat.isAi).length;
    nextEventSeq(state);
    await store.setRoom(state);
  }
  await broadcast(state.room.roomId, {
    type: 'player_left',
    roomId: state.room.roomId,
    eventSeq: state.eventSeq,
    serverTime: now(),
    payload: {
      seatIndex: auth.seat.seatIndex,
      playerId: auth.playerId,
      reason: req.body?.reason || 'user_exit',
      roomClosed,
    },
  });
  ok(req, res, { roomId: state.room.roomId, left: true, roomClosed });
});

app.get('/api/v1/rooms/:roomId/snapshot', async (req, res) => {
  const authenticated = await authenticateRoomRequest(req, res);
  if (!authenticated) return;
  ok(req, res, snapshotFor(authenticated.state, authenticated.auth.playerId));
});

app.get('/api/v1/players/me/stats', async (req, res) => {
  const token = req.headers['x-player-token'];
  const resolved = token ? await resolveToken(token) : null;
  if (!resolved) return fail(req, res, 401, 'INVALID_PLAYER_TOKEN', '房间内身份无效');
  const limit = Math.max(1, Math.min(Number(req.query.limit || 20), 100));
  const logs = await loadLogs();
  const related = logs
    .filter((log) => log.players?.some((player) => player.playerId === resolved.playerId))
    .slice(-limit)
    .reverse();
  const recentResults = related.map((log) => {
    const me = log.players.find((player) => player.playerId === resolved.playerId);
    const finish = log.finishOrder.find((item) => item.playerId === resolved.playerId);
    const won = log.winnerTeam === me.team;
    return {
      roomId: log.roomId,
      gameId: log.gameId,
      roundNo: log.roundNo,
      winnerTeam: log.winnerTeam,
      myTeam: me.team,
      result: won ? 'win' : 'loss',
      myRank: finish?.rank ?? null,
      scoreDelta: won ? log.scoreDelta[`team${me.team}`] : 0,
      createdAt: log.createdAt,
    };
  });
  const wins = recentResults.filter((result) => result.result === 'win').length;
  ok(req, res, {
    totalRounds: recentResults.length,
    wins,
    losses: recentResults.length - wins,
    winRate: recentResults.length ? wins / recentResults.length : 0,
    recentResults,
  }, { source: 'match_log', logVersion: 1 });
});

app.get('/api/v1/rooms/:roomId/history', async (req, res) => {
  const authenticated = await authenticateRoomRequest(req, res);
  if (!authenticated) return;
  const limit = Math.max(1, Math.min(Number(req.query.limit || 20), 100));
  const before = req.query.before ? Number(req.query.before) : Infinity;
  const logs = await loadLogs();
  const rounds = logs
    .filter((log) => log.roomId === req.params.roomId && log.createdAt < before)
    .slice(-limit)
    .reverse()
    .map((log) => ({
      gameId: log.gameId,
      roundNo: log.roundNo,
      winnerTeam: log.winnerTeam,
      finishOrder: log.finishOrder,
      caughtPlayers: log.caughtPlayers,
      scoreDelta: log.scoreDelta,
      totalScoreAfterRound: log.totalScoreAfterRound,
      createdAt: log.createdAt,
    }));
  ok(req, res, { roomId: req.params.roomId, rounds }, { source: 'match_log', logVersion: 1 });
});

const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', async (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const match = url.pathname.match(/^\/ws\/v1\/tables\/([^/]+)$/);
  if (!match) {
    socket.destroy();
    return;
  }
  const roomId = match[1];
  const token = url.searchParams.get('playerToken');
  const state = await store.getRoom(roomId);
  const auth = state && token ? findPlayerByToken(state, token) : null;
  if (!state || !auth) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    ws.roomId = roomId;
    ws.playerId = auth.playerId;
    ws.playerToken = token;
    wss.emit('connection', ws, req);
  });
});

wss.on('connection', async (ws) => {
  if (!socketsByRoom.has(ws.roomId)) socketsByRoom.set(ws.roomId, new Set());
  socketsByRoom.get(ws.roomId).add(ws);

  const state = await store.getRoom(ws.roomId);
  const seat = state?.seats.find((candidate) => candidate && candidate.playerId === ws.playerId);
  if (state && seat) {
    seat.connected = true;
    nextEventSeq(state);
    await store.setRoom(state);
    await sendSnapshot(ws, state, null);
    await broadcast(ws.roomId, {
      type: 'player_reconnected',
      roomId: ws.roomId,
      eventSeq: state.eventSeq,
      serverTime: now(),
      payload: { seatIndex: seat.seatIndex, playerId: seat.playerId },
    }, { excludePlayerId: ws.playerId });
  }

  ws.on('message', async (buffer) => {
    let message;
    try {
      message = JSON.parse(buffer.toString());
    } catch (_) {
      ws.send(JSON.stringify({ type: 'error', payload: { code: 'INVALID_REQUEST', message: '消息不是合法 JSON' } }));
      return;
    }

    const state = await store.getRoom(ws.roomId);
    const seat = state?.seats.find((candidate) => candidate && candidate.playerId === ws.playerId);
    if (!state || !seat) {
      ws.send(JSON.stringify({ type: 'error', requestId: message.requestId, payload: { code: 'INVALID_PLAYER_TOKEN', message: '房间内身份无效' } }));
      return;
    }

    async function persistAndSnapshots(type) {
      const aiEvents = await runAiTurns(state);
      nextEventSeq(state);
      await store.setRoom(state);
      if (aiEvents.some((event) => event.result?.settlement)) {
        const settlement = aiEvents.find((event) => event.result?.settlement).result.settlement;
        await appendMatchLog(state, settlement);
      }
      await broadcastStateSnapshots(state, type, message.requestId);
    }

    try {
      if (message.type === 'ping') {
        nextEventSeq(state);
        await store.setRoom(state);
        ws.send(JSON.stringify({
          type: 'pong',
          requestId: message.requestId,
          roomId: ws.roomId,
          eventSeq: state.eventSeq,
          serverTime: now(),
          payload: {},
        }));
        return;
      }

      if (message.type === 'sync_state') {
        await sendSnapshot(ws, state, message.requestId);
        return;
      }

      if (message.type === 'ready') {
        if (state.room.status !== 'waiting') throw ['ROOM_ALREADY_PLAYING', '房间已开局'];
        seat.ready = Boolean(message.payload?.ready);
        nextEventSeq(state);
        await store.setRoom(state);
        await broadcast(ws.roomId, {
          type: 'seat_updated',
          requestId: message.requestId,
          roomId: ws.roomId,
          eventSeq: state.eventSeq,
          serverTime: now(),
          payload: { seat: seatView(seat) },
        });
        return;
      }

      if (message.type === 'start_game') {
        if (state.room.ownerPlayerId !== ws.playerId) throw ['NOT_ROOM_OWNER', '只有房主可操作'];
        if (state.room.status !== 'waiting') throw ['ROOM_ALREADY_PLAYING', '房间已开局'];
        const humans = state.seats.filter((candidate) => candidate && !candidate.isAi);
        if (!humans.every((candidate) => candidate.ready)) throw ['NOT_READY', '玩家未准备'];
        startGame(state);
        await persistAndSnapshots('game_started');
        return;
      }

      if (message.type === 'play_cards') {
        if (state.room.status !== 'playing') throw ['GAME_NOT_STARTED', '对局未开始'];
        if (state.game.currentTurnSeatIndex !== seat.seatIndex) throw ['NOT_YOUR_TURN', '未轮到该玩家'];
        const hand = state.hands[seat.playerId] || [];
        const cards = cardsByIds(hand, message.payload?.cardIds);
        if (!cards) throw ['INVALID_CARDS', '牌不存在、不是自己的牌或重复提交'];
        const result = await playCards(state, seat, cards);
        if (result.error) throw result.error;
        nextEventSeq(state);
        await store.setRoom(state);
        if (result.settlement) await appendMatchLog(state, result.settlement);
        await persistAndSnapshots('table_snapshot');
        return;
      }

      if (message.type === 'pass') {
        if (state.room.status !== 'playing') throw ['GAME_NOT_STARTED', '对局未开始'];
        if (state.game.currentTurnSeatIndex !== seat.seatIndex) throw ['NOT_YOUR_TURN', '未轮到该玩家'];
        const result = await passTurn(state, seat);
        if (result.error) throw result.error;
        await persistAndSnapshots(result.newLead ? 'new_lead_started' : 'player_passed');
        return;
      }

      throw ['INVALID_REQUEST', `未知消息类型：${message.type}`];
    } catch (error) {
      const [code, errorMessage] = Array.isArray(error) ? error : ['INVALID_REQUEST', error.message || '请求失败'];
      ws.send(JSON.stringify({
        type: 'error',
        requestId: message.requestId,
        roomId: ws.roomId,
        eventSeq: state.eventSeq,
        serverTime: now(),
        payload: { code, message: errorMessage },
      }));
    }
  });

  ws.on('close', async () => {
    socketsByRoom.get(ws.roomId)?.delete(ws);
    const state = await store.getRoom(ws.roomId);
    const seat = state?.seats.find((candidate) => candidate && candidate.playerId === ws.playerId);
    if (state && seat) {
      seat.connected = false;
      nextEventSeq(state);
      await store.setRoom(state);
      await broadcast(ws.roomId, {
        type: 'player_disconnected',
        roomId: ws.roomId,
        eventSeq: state.eventSeq,
        serverTime: now(),
        payload: {
          seatIndex: seat.seatIndex,
          playerId: seat.playerId,
          autoPlayAfterSeconds: 30,
        },
      });
    }
  });
});

store.connect().then(() => {
  server.listen(PORT, HOST, () => {
    console.log(`[server] DoorSix listening on http://${HOST}:${PORT}`);
  });
});
