# DoorSix 最小多人服务端设计

## 1. 文档目的

本文重新规划 DoorSix 的最小多人服务端接口和依赖服务。

当前目标是先砍掉非必要能力：

- 不做大厅。
- 不做观战。
- 不做自定义规则。
- 不做账号体系。

只保留最小闭环：

- 房间号组局。
- 6 座牌桌，真人不足 6 人时由服务端 AI 补齐。
- 房间内临时玩家身份。
- Redis 运行态状态存储。
- WebSocket 实时同步。
- 服务端权威发牌、出牌校验和结算。
- 历史战绩以结构化日志文件保存，方便后续研究。

当服务端、Flutter/安卓端、规则引擎或需求发生变更时，必须核对本文和代码是否一致。

## 2. 非目标

以下能力明确不在最小版本范围内：

| 能力 | 处理方式 |
| --- | --- |
| 账号登录 | 不做账号系统，创建/加入房间时生成房间内临时身份 |
| 大厅和房间列表 | 不做公开大厅，只支持房间号加入 |
| 观战 | 不支持，房间最多 6 个真人玩家 |
| 自定义规则 | 不支持，固定一套 `砸六家简化规则` |
| 好友系统 | 不支持 |
| 排行榜 | 不支持 |
| 聊天/语音 | 最小版不支持 |
| 数据库 | 最小版不依赖数据库 |

## 3. 设计目标

服务端必须是牌桌权威状态源。

服务端负责：

- 创建房间并生成房间号。
- 通过房间号加入房间。
- 为每个玩家生成房间内临时 `playerToken`。
- 管理 6 个座位。
- 开局时用 AI 填充空座位，保证牌桌始终有 6 个参赛席位。
- 固定隔位分队。
- 管理准备状态。
- 开局时洗牌和发牌。
- 只把完整手牌发给对应玩家。
- 校验出牌是否轮到该玩家。
- 校验提交的牌是否属于该玩家。
- 校验牌型是否合法。
- 校验是否能压过当前桌面牌型。
- 推进回合。
- 记录出完顺序。
- 计算单局结果。
- 将每局结算结果追加写入结构化日志文件。
- 从结构化日志中读取历史战绩。
- 支持断线重连时恢复牌桌快照。

## 4. 通信方式

```text
Flutter/安卓端
  ├── HTTP
  │   ├── 创建房间
  │   ├── 通过房间号查询房间
  │   ├── 加入房间
  │   ├── 离开房间
  │   ├── 获取房间快照
  │   ├── 查询玩家历史战绩
  │   └── 查询房间历史战绩
  └── WebSocket
      ├── 入桌快照
      ├── 准备/取消准备
      ├── 开始游戏
      ├── 出牌
      ├── 过牌
      ├── 状态同步
      └── 结算广播
```

接口统一使用 JSON。

## 5. 依赖服务规划

### 5.1 外部依赖

最小版本保留 Redis，但不引入数据库。Redis 保存实时运行态，日志文件保存历史战绩。

| 依赖 | 是否必需 | 用途 |
| --- | --- | --- |
| HTTP 服务 | 必需 | 创建房间、加入房间、快照查询 |
| WebSocket 服务 | 必需 | 牌桌实时同步 |
| Redis | 必需 | 保存房间、牌桌、手牌、连接状态、`playerToken`、锁、事件序号和 TTL |
| 结构化战绩日志 | 必需 | 每局结算后追加写入，供历史战绩读取和后续研究 |
| 文件运行日志 | 可选 | 运行日志和错误排查 |
| 数据库 | 不使用 | 最小版本不引入 |

建议落地顺序：

1. 先实现 Redis 版房间和牌桌状态。
2. 同步实现结算日志追加写入。
3. 再实现从日志读取玩家和房间历史战绩。
4. 数据库等后续确实需要账号、排行榜或复杂查询时再评估。

### 5.2 Redis 职责

Redis 负责保存会随牌桌进行而变化的实时状态。

推荐 key 设计：

| Key | 类型 | 说明 |
| --- | --- | --- |
| `room:{roomId}` | hash/json | 房间基础信息 |
| `room_code:{roomCode}` | string | 房间号到 `roomId` 的映射 |
| `room:{roomId}:seats` | hash/json | 6 个座位状态 |
| `room:{roomId}:game` | hash/json | 当前牌桌公共状态 |
| `room:{roomId}:hand:{playerId}` | list/json | 某玩家完整手牌 |
| `room:{roomId}:token:{playerToken}` | string | `playerToken` 到 `playerId` 的映射 |
| `room:{roomId}:connections` | hash | 玩家连接状态 |
| `room:{roomId}:eventSeq` | string/integer | 服务端递增事件序号 |
| `lock:room:{roomId}` | string | 房间操作锁 |

Redis 需要支持：

- 房间 TTL，过期自动清理无人房间。
- 出牌/过牌操作加锁，避免并发修改同一牌桌。
- `playerToken` 校验。
- 断线重连时读取最新快照。
- 如果后端多实例部署，用 Redis Pub/Sub 或 Streams 分发牌桌事件。

### 5.3 结构化战绩日志职责

历史战绩不进数据库，使用追加式日志文件。

推荐路径：

```text
logs/matches/2026-05-07.ndjson
```

一行一局结算结果，格式为 JSON。该日志是历史战绩的事实来源。

### 5.4 服务端内部模块

| 模块 | 职责 |
| --- | --- |
| `RoomService` | 创建房间、查询房间、加入/离开房间、座位管理 |
| `PlayerSessionService` | 生成和校验房间内临时 `playerToken` |
| `GameStateService` | 管理牌桌状态、当前回合、手牌、出完顺序 |
| `RuleEngine` | 识别牌型、校验出牌、比较牌型大小、计算结算 |
| `AIPlayerService` | 为未满 6 人的空座补 AI，并执行最简单出牌策略 |
| `TableGateway` | WebSocket 连接、消息接收、事件广播 |
| `SnapshotService` | 生成不同玩家视角的牌桌快照 |
| `RedisStateStore` | 读写 Redis 中的房间、牌桌、手牌、锁和事件序号 |
| `MatchLogService` | 追加写入结算日志，并从日志聚合历史战绩 |
| `TurnTimerService` | 可选，处理玩家超时自动过牌 |
| `RuntimeLogService` | 可选，写运行日志和错误日志 |

## 6. 固定规则版本

最小版只支持一个规则：

```json
{
  "ruleSetId": "zha_liujia_tianjin_basic_v1",
  "name": "天津砸六家基础规则",
  "deckCount": 1,
  "playerCount": 6,
  "minHumanPlayersToStart": 1,
  "fillAiSeats": true,
  "teamMode": "alternate_seats",
  "seatTeams": {
    "0": "B",
    "1": "A",
    "2": "B",
    "3": "A",
    "4": "B",
    "5": "A"
  },
  "enabledCombos": ["single", "pair", "triple", "quad"],
  "wildCards": ["big_joker", "small_joker", "3", "2"],
  "settlementMode": "basic_gong_no_teammate_left_home"
}
```

说明：

- 不提供规则列表接口。
- 不提供自定义规则接口。
- 创建房间时不传 `ruleSetId`。
- 服务端始终使用 `zha_liujia_tianjin_basic_v1`。
- 房间内至少 1 名真人即可开局，空座位由服务端 AI 补齐到 6 个席位。

## 7. AI 补位与最简单出牌策略

### 7.1 AI 补位规则

- 房主可以在真人不足 6 人时开始游戏。
- 开局时，服务端扫描 0 到 5 号座位。
- 空座位由服务端创建 AI 玩家补齐。
- AI 玩家也属于 A 队或 B 队，队伍仍按座位隔位分配。
- AI 玩家没有 `playerToken`，不接受客户端连接。
- AI 玩家出牌由服务端 `AIPlayerService` 自动执行。

AI 座位示例：

```json
{
  "seatIndex": 4,
  "playerId": "ai_4",
  "nickname": "AI 4",
  "team": "A",
  "ready": true,
  "connected": false,
  "isAi": true,
  "cardCount": 9,
  "finishRank": null
}
```

### 7.2 最简单 AI 出牌策略

第一版 AI 不做配合，不记牌，不考虑队友，只保证能让游戏跑通。

策略：

1. 如果当前是新一轮领出，AI 出手牌中最小的一张单牌。
2. 如果需要跟牌，AI 找出所有能压过当前桌面牌型的合法组合。
3. 如果存在可出组合，选择点数最小、张数匹配的组合出牌。
4. 如果没有可出组合，AI 过牌。
5. AI 跟牌必须保持相同牌型和张数；四张只能压四张，不能跨牌型压单张、对子或三张。
6. AI 出完手牌后，服务端记录出完名次。

伪代码：

```text
if tableCombo == null:
  play lowest single
else:
  candidates = find legal combos that beat tableCombo
  candidates = filter same combo type first
  if candidates not empty:
    play lowest strength candidate
  else:
    pass
```

## 8. 核心数据结构

### 8.1 Player

最小版没有账号，`Player` 只在房间内有效。

```json
{
  "playerId": "p_10001",
  "nickname": "小乙",
  "seatIndex": 0,
  "team": "A",
  "isAi": false,
  "connected": true,
  "ready": false
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `playerId` | string | 房间内玩家 ID |
| `nickname` | string | 昵称 |
| `seatIndex` | number | 座位号，0 到 5 |
| `team` | string | `A` 或 `B` |
| `isAi` | boolean | 是否服务端 AI |
| `connected` | boolean | WebSocket 是否在线 |
| `ready` | boolean | 是否准备 |

### 8.2 PlayerSession

创建或加入房间后由服务端返回，客户端需要本地保存，用于 WebSocket 和后续 HTTP 请求。

```json
{
  "roomId": "r_90001",
  "playerId": "p_10001",
  "playerToken": "room_scoped_token"
}
```

说明：

- `playerToken` 不是账号 token。
- `playerToken` 只对当前房间有效。
- 房间关闭后失效。
- 服务端可以把它实现成签名 token 或随机字符串。

### 8.3 Room

```json
{
  "roomId": "r_90001",
  "roomCode": "384921",
  "ownerPlayerId": "p_10001",
  "status": "waiting",
  "playerCount": 1,
  "maxPlayers": 6,
  "ruleSetId": "zha_liujia_tianjin_basic_v1",
  "createdAt": 1778150000000,
  "expiresAt": 1778157200000
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `roomId` | string | 房间 ID |
| `roomCode` | string | 6 位房间号 |
| `ownerPlayerId` | string | 房主玩家 ID |
| `status` | string | `waiting`、`playing`、`settled`、`closed` |
| `playerCount` | number | 当前玩家数 |
| `maxPlayers` | number | 固定 6 |
| `ruleSetId` | string | 固定 `zha_liujia_tianjin_basic_v1` |
| `createdAt` | number | 创建时间 |
| `expiresAt` | number | 房间过期时间 |

### 8.4 Seat

```json
{
  "seatIndex": 0,
  "playerId": "p_10001",
  "nickname": "小乙",
  "team": "A",
  "isAi": false,
  "ready": true,
  "connected": true,
  "cardCount": 9,
  "finishRank": null
}
```

### 8.5 Card

服务端必须给每张牌唯一 ID，方便客户端精确同步手牌、选牌和出牌记录。

```json
{
  "cardId": "d0-spades-A",
  "deckIndex": 0,
  "suit": "spades",
  "rank": "A"
}
```

### 8.6 Combo

```json
{
  "comboType": "pair",
  "rankStrength": 13,
  "cardIds": ["d0-spades-K", "d1-hearts-K"],
  "label": "对子 K"
}
```

### 8.7 TableState

```json
{
  "roomId": "r_90001",
  "gameId": "g_70001",
  "roundNo": 1,
  "status": "playing",
  "ruleSetId": "zha_liujia_tianjin_basic_v1",
  "ownerPlayerId": "p_10001",
  "currentTurnSeatIndex": 0,
  "lastPlayedSeatIndex": null,
  "passCount": 0,
  "tableCombo": null,
  "seats": [],
  "finishOrder": [],
  "score": {
    "teamA": 0,
    "teamB": 0
  }
}
```

说明：

- `TableState` 是公共状态，不包含其他玩家完整手牌。
- 客户端自己的完整手牌由 `myHand` 单独返回。

### 8.8 MatchLog

每局结算后，服务端追加写入一条结构化战绩日志。

```json
{
  "logType": "round_settled",
  "logVersion": 1,
  "createdAt": 1778150000000,
  "roomId": "r_90001",
  "roomCode": "384921",
  "gameId": "g_70001",
  "roundNo": 1,
  "ruleSetId": "zha_liujia_tianjin_basic_v1",
  "winnerTeam": "A",
  "finishOrder": [
    {
      "seatIndex": 0,
      "playerId": "p_10001",
      "nickname": "小乙",
      "team": "A",
      "rank": 1
    }
  ],
  "caughtPlayers": [
    {
      "seatIndex": 3,
      "playerId": "p_10004",
      "nickname": "玩家4",
      "team": "B"
    }
  ],
  "scoreDelta": {
    "teamA": 5,
    "teamB": 0
  },
  "totalScoreAfterRound": {
    "teamA": 5,
    "teamB": 0
  },
  "players": [
    {
      "seatIndex": 0,
      "playerId": "p_10001",
      "nickname": "小乙",
      "team": "A"
    }
  ],
  "settlementReason": "team_all_finished"
}
```

写入要求：

- 一局只写一次。
- 追加写入，不覆盖旧日志。
- 一行一个完整 JSON。
- 查询历史战绩时从该日志读取和聚合。
- 该日志用于后续研究、回放分析和可能的数据迁移。

## 8. HTTP 通用返回结构

成功：

```json
{
  "success": true,
  "requestId": "req_001",
  "data": {},
  "error": null
}
```

失败：

```json
{
  "success": false,
  "requestId": "req_001",
  "data": null,
  "error": {
    "code": "ROOM_FULL",
    "message": "房间已满"
  }
}
```

最小版错误码：

| 错误码 | 说明 |
| --- | --- |
| `INVALID_REQUEST` | 请求参数不合法 |
| `ROOM_NOT_FOUND` | 房间不存在 |
| `ROOM_FULL` | 房间已满 |
| `ROOM_CLOSED` | 房间已关闭 |
| `ROOM_ALREADY_PLAYING` | 房间已开局 |
| `INVALID_PLAYER_TOKEN` | 房间内身份无效 |
| `SEAT_TAKEN` | 座位已被占用 |
| `NOT_ROOM_OWNER` | 只有房主可操作 |
| `NOT_READY` | 玩家未准备 |
| `NOT_YOUR_TURN` | 未轮到该玩家 |
| `INVALID_CARDS` | 牌不存在、不是自己的牌或重复提交 |
| `INVALID_COMBO` | 牌型不合法 |
| `CANNOT_BEAT_TABLE_COMBO` | 压不过当前桌面牌型 |
| `GAME_NOT_STARTED` | 对局未开始 |
| `GAME_ALREADY_SETTLED` | 本局已结算 |

## 9. HTTP 接口

### 9.1 创建房间

```http
POST /api/v1/rooms
```

请求参数：

```json
{
  "nickname": "小乙",
  "seatIndex": 0
}
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `nickname` | string | 是 | 玩家昵称 |
| `seatIndex` | number | 否 | 希望坐的位置，0 到 5；不传默认 0 |

返回：

```json
{
  "success": true,
  "requestId": "req_001",
  "data": {
    "room": {
      "roomId": "r_90001",
      "roomCode": "384921",
      "ownerPlayerId": "p_10001",
      "status": "waiting",
      "playerCount": 1,
      "maxPlayers": 6,
      "ruleSetId": "zha_liujia_tianjin_basic_v1",
      "createdAt": 1778150000000,
      "expiresAt": 1778157200000
    },
    "self": {
      "playerId": "p_10001",
      "nickname": "小乙",
      "seatIndex": 0,
      "team": "A",
      "connected": false,
      "ready": false
    },
    "playerToken": "room_scoped_token",
    "webSocketUrl": "wss://api.example.com/ws/v1/tables/r_90001"
  },
  "error": null
}
```

### 9.2 通过房间号查询房间

只用于输入房间号后预览房间是否存在、是否可加入。不返回完整牌桌状态。

```http
GET /api/v1/rooms/by-code/{roomCode}
```

返回：

```json
{
  "success": true,
  "requestId": "req_002",
  "data": {
    "room": {
      "roomId": "r_90001",
      "roomCode": "384921",
      "ownerPlayerId": "p_10001",
      "status": "waiting",
      "playerCount": 4,
      "maxPlayers": 6,
      "ruleSetId": "zha_liujia_tianjin_basic_v1",
      "createdAt": 1778150000000,
      "expiresAt": 1778157200000
    },
    "joinable": true
  },
  "error": null
}
```

### 9.3 通过房间号加入房间

```http
POST /api/v1/rooms/by-code/{roomCode}/join
```

请求参数：

```json
{
  "nickname": "玩家2",
  "seatIndex": 2
}
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `nickname` | string | 是 | 玩家昵称 |
| `seatIndex` | number | 否 | 希望坐的位置；不传由服务端分配空位 |

返回：

```json
{
  "success": true,
  "requestId": "req_003",
  "data": {
    "room": {
      "roomId": "r_90001",
      "roomCode": "384921",
      "ownerPlayerId": "p_10001",
      "status": "waiting",
      "playerCount": 5,
      "maxPlayers": 6,
      "ruleSetId": "zha_liujia_tianjin_basic_v1",
      "createdAt": 1778150000000,
      "expiresAt": 1778157200000
    },
    "self": {
      "playerId": "p_10002",
      "nickname": "玩家2",
      "seatIndex": 2,
      "team": "A",
      "connected": false,
      "ready": false
    },
    "playerToken": "room_scoped_token",
    "webSocketUrl": "wss://api.example.com/ws/v1/tables/r_90001"
  },
  "error": null
}
```

### 9.4 离开房间

```http
POST /api/v1/rooms/{roomId}/leave
```

请求 Header：

```text
X-Player-Token: <playerToken>
```

请求参数：

```json
{
  "reason": "user_exit"
}
```

返回：

```json
{
  "success": true,
  "requestId": "req_004",
  "data": {
    "roomId": "r_90001",
    "left": true,
    "roomClosed": false
  },
  "error": null
}
```

### 9.5 获取房间快照

用于重进房间、断线恢复或 App 从后台回来后补状态。

```http
GET /api/v1/rooms/{roomId}/snapshot
```

请求 Header：

```text
X-Player-Token: <playerToken>
```

返回：

```json
{
  "success": true,
  "requestId": "req_005",
  "data": {
    "tableState": {
      "roomId": "r_90001",
      "gameId": "g_70001",
      "roundNo": 1,
      "status": "playing",
      "ruleSetId": "zha_liujia_tianjin_basic_v1",
      "ownerPlayerId": "p_10001",
      "currentTurnSeatIndex": 3,
      "lastPlayedSeatIndex": 1,
      "passCount": 0,
      "tableCombo": {
        "comboType": "pair",
        "rankStrength": 13,
        "cardIds": ["hidden_1", "hidden_2"],
        "label": "对子 K"
      },
      "seats": [],
      "finishOrder": [],
      "score": {
        "teamA": 0,
        "teamB": 0
      }
    },
    "myHand": [
      {
        "cardId": "d0-spades-A",
        "deckIndex": 0,
        "suit": "spades",
        "rank": "A"
      }
    ],
    "eventSeq": 128
  },
  "error": null
}
```

### 9.6 获取玩家历史战绩

从结构化战绩日志中读取和聚合当前玩家历史战绩。

```http
GET /api/v1/players/me/stats?limit=20
```

请求 Header：

```text
X-Player-Token: <playerToken>
```

查询参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `limit` | number | 否 | 最近结果数量，默认 20 |
| `from` | number | 否 | 起始毫秒时间戳 |
| `to` | number | 否 | 结束毫秒时间戳 |

返回：

```json
{
  "success": true,
  "requestId": "req_006",
  "data": {
    "totalRounds": 20,
    "wins": 12,
    "losses": 8,
    "winRate": 0.6,
    "recentResults": [
      {
        "roomId": "r_90001",
        "gameId": "g_70001",
        "roundNo": 1,
        "winnerTeam": "A",
        "myTeam": "A",
        "result": "win",
        "myRank": 1,
        "scoreDelta": 5,
        "createdAt": 1778150000000
      }
    ]
  },
  "meta": {
    "source": "match_log",
    "logVersion": 1
  },
  "error": null
}
```

### 9.7 获取房间历史战绩

从结构化战绩日志中读取某个房间的历史局记录。

```http
GET /api/v1/rooms/{roomId}/history?limit=20
```

请求 Header：

```text
X-Player-Token: <playerToken>
```

查询参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `limit` | number | 否 | 最近局数，默认 20 |
| `before` | number | 否 | 返回该时间戳之前的记录 |

返回：

```json
{
  "success": true,
  "requestId": "req_007",
  "data": {
    "roomId": "r_90001",
    "rounds": [
      {
        "gameId": "g_70001",
        "roundNo": 1,
        "winnerTeam": "A",
        "finishOrder": [
          {
            "seatIndex": 0,
            "playerId": "p_10001",
            "nickname": "小乙",
            "team": "A",
            "rank": 1
          }
        ],
        "caughtPlayers": [],
        "scoreDelta": {
          "teamA": 5,
          "teamB": 0
        },
        "totalScoreAfterRound": {
          "teamA": 5,
          "teamB": 0
        },
        "createdAt": 1778150000000
      }
    ]
  },
  "meta": {
    "source": "match_log",
    "logVersion": 1
  },
  "error": null
}
```

## 10. WebSocket 连接

### 10.1 连接地址

```text
wss://api.example.com/ws/v1/tables/{roomId}?playerToken=<playerToken>
```

连接成功后，服务端必须推送 `table_snapshot`。

### 10.2 客户端消息结构

```json
{
  "type": "ready",
  "requestId": "req_ws_001",
  "roomId": "r_90001",
  "seq": 1,
  "payload": {}
}
```

### 10.3 服务端消息结构

```json
{
  "type": "seat_updated",
  "requestId": "req_ws_001",
  "roomId": "r_90001",
  "eventSeq": 129,
  "serverTime": 1778150000000,
  "payload": {}
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `type` | string | 消息类型 |
| `requestId` | string | 请求 ID，广播事件可为空 |
| `roomId` | string | 房间 ID |
| `seq` | number | 客户端递增序号 |
| `eventSeq` | number | 服务端递增事件序号 |
| `serverTime` | number | 服务端毫秒时间戳 |
| `payload` | object | 业务数据 |

## 11. WebSocket 客户端事件

### 11.1 心跳

客户端发送：

```json
{
  "type": "ping",
  "requestId": "req_ws_ping_1",
  "roomId": "r_90001",
  "seq": 1,
  "payload": {}
}
```

服务端返回：

```json
{
  "type": "pong",
  "requestId": "req_ws_ping_1",
  "roomId": "r_90001",
  "eventSeq": 130,
  "serverTime": 1778150000000,
  "payload": {}
}
```

### 11.2 准备或取消准备

客户端发送：

```json
{
  "type": "ready",
  "requestId": "req_ws_010",
  "roomId": "r_90001",
  "seq": 10,
  "payload": {
    "ready": true
  }
}
```

服务端广播：

```json
{
  "type": "seat_updated",
  "requestId": "req_ws_010",
  "roomId": "r_90001",
  "eventSeq": 131,
  "serverTime": 1778150000000,
  "payload": {
    "seat": {
      "seatIndex": 2,
      "playerId": "p_10002",
      "nickname": "玩家2",
      "team": "A",
      "isAi": false,
      "ready": true,
      "connected": true,
      "cardCount": 0,
      "finishRank": null
    }
  }
}
```

### 11.3 房主开始游戏

客户端发送：

```json
{
  "type": "start_game",
  "requestId": "req_ws_011",
  "roomId": "r_90001",
  "seq": 11,
  "payload": {}
}
```

服务端校验：

- 发送者是房主。
- 房间状态为 `waiting`。
- 房间内至少有 1 名真人玩家。
- 房间内所有真人玩家都已准备。
- 空座位会在开局时由服务端 AI 补齐到 6 个席位。

服务端向每名玩家分别推送：

```json
{
  "type": "game_started",
  "requestId": "req_ws_011",
  "roomId": "r_90001",
  "eventSeq": 132,
  "serverTime": 1778150000000,
  "payload": {
    "tableState": {
      "roomId": "r_90001",
      "gameId": "g_70001",
      "roundNo": 1,
      "status": "playing",
      "ruleSetId": "zha_liujia_tianjin_basic_v1",
      "ownerPlayerId": "p_10001",
      "currentTurnSeatIndex": 0,
      "lastPlayedSeatIndex": null,
      "passCount": 0,
      "tableCombo": null,
      "seats": [
        {
          "seatIndex": 0,
          "playerId": "p_10001",
          "nickname": "小乙",
          "team": "A",
          "isAi": false,
          "ready": true,
          "connected": true,
          "cardCount": 9,
          "finishRank": null
        },
        {
          "seatIndex": 1,
          "playerId": "ai_1",
          "nickname": "AI 1",
          "team": "B",
          "isAi": true,
          "ready": true,
          "connected": false,
          "cardCount": 9,
          "finishRank": null
        }
      ],
      "finishOrder": [],
      "score": {
        "teamA": 0,
        "teamB": 0
      }
    },
    "myHand": []
  }
}
```

说明：`myHand` 每名玩家不同，不能广播同一份手牌给所有连接。

### 11.4 出牌

客户端发送：

```json
{
  "type": "play_cards",
  "requestId": "req_ws_012",
  "roomId": "r_90001",
  "seq": 12,
  "payload": {
    "gameId": "g_70001",
    "roundNo": 1,
    "cardIds": ["d0-spades-K", "d1-hearts-K"],
    "clientKnownEventSeq": 132
  }
}
```

请求参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `gameId` | string | 是 | 当前对局 ID |
| `roundNo` | number | 是 | 当前局号 |
| `cardIds` | string[] | 是 | 要出的牌 ID |
| `clientKnownEventSeq` | number | 是 | 客户端已处理的最新事件序号 |

服务端校验：

- 对局状态为 `playing`。
- 当前轮到该玩家。
- `cardIds` 都属于该玩家手牌。
- `cardIds` 无重复。
- 牌型合法。
- 当前为新一轮，或该牌型能压过当前桌面牌型。

服务端先返回给请求者：

```json
{
  "type": "action_accepted",
  "requestId": "req_ws_012",
  "roomId": "r_90001",
  "eventSeq": 133,
  "serverTime": 1778150000000,
  "payload": {
    "action": "play_cards"
  }
}
```

服务端广播：

```json
{
  "type": "cards_played",
  "roomId": "r_90001",
  "eventSeq": 134,
  "serverTime": 1778150000000,
  "payload": {
    "gameId": "g_70001",
    "roundNo": 1,
    "seatIndex": 0,
    "playerId": "p_10001",
    "combo": {
      "comboType": "pair",
      "rankStrength": 13,
      "cardIds": ["d0-spades-K", "d1-hearts-K"],
      "label": "对子 K"
    },
    "remainingCardCount": 16,
    "nextTurnSeatIndex": 1,
    "passCount": 0,
    "finishRank": null
  }
}
```

如果玩家出完，`finishRank` 返回数字。

### 11.5 过牌

客户端发送：

```json
{
  "type": "pass",
  "requestId": "req_ws_013",
  "roomId": "r_90001",
  "seq": 13,
  "payload": {
    "gameId": "g_70001",
    "roundNo": 1,
    "clientKnownEventSeq": 134
  }
}
```

服务端校验：

- 当前轮到该玩家。
- 当前不是必须领出的新一轮。
- 对局状态为 `playing`。

服务端广播：

```json
{
  "type": "player_passed",
  "roomId": "r_90001",
  "eventSeq": 135,
  "serverTime": 1778150000000,
  "payload": {
    "gameId": "g_70001",
    "roundNo": 1,
    "seatIndex": 1,
    "playerId": "p_10002",
    "nextTurnSeatIndex": 2,
    "passCount": 1,
    "newLead": false
  }
}
```

如果一圈过牌后进入新一轮，服务端广播：

```json
{
  "type": "new_lead_started",
  "roomId": "r_90001",
  "eventSeq": 136,
  "serverTime": 1778150000000,
  "payload": {
    "gameId": "g_70001",
    "roundNo": 1,
    "leadSeatIndex": 0,
    "tableCombo": null,
    "passCount": 0
  }
}
```

### 11.6 请求状态同步

客户端发送：

```json
{
  "type": "sync_state",
  "requestId": "req_ws_014",
  "roomId": "r_90001",
  "seq": 14,
  "payload": {
    "lastEventSeq": 130
  }
}
```

服务端返回：

```json
{
  "type": "table_snapshot",
  "requestId": "req_ws_014",
  "roomId": "r_90001",
  "eventSeq": 137,
  "serverTime": 1778150000000,
  "payload": {
    "tableState": {},
    "myHand": [],
    "eventSeq": 137
  }
}
```

最小版直接返回完整快照，不做事件补偿列表。

## 12. WebSocket 服务端主动事件

### 12.1 牌桌快照

```json
{
  "type": "table_snapshot",
  "roomId": "r_90001",
  "eventSeq": 140,
  "serverTime": 1778150000000,
  "payload": {
    "tableState": {},
    "myHand": [],
    "eventSeq": 140
  }
}
```

### 12.2 玩家加入

```json
{
  "type": "player_joined",
  "roomId": "r_90001",
  "eventSeq": 141,
  "serverTime": 1778150000000,
  "payload": {
    "seat": {
      "seatIndex": 2,
      "playerId": "p_10002",
      "nickname": "玩家2",
      "team": "A",
      "isAi": false,
      "ready": false,
      "connected": true,
      "cardCount": 0,
      "finishRank": null
    }
  }
}
```

### 12.3 玩家离开

```json
{
  "type": "player_left",
  "roomId": "r_90001",
  "eventSeq": 142,
  "serverTime": 1778150000000,
  "payload": {
    "seatIndex": 2,
    "playerId": "p_10002",
    "reason": "user_exit",
    "roomClosed": false
  }
}
```

### 12.4 玩家断线

```json
{
  "type": "player_disconnected",
  "roomId": "r_90001",
  "eventSeq": 143,
  "serverTime": 1778150000000,
  "payload": {
    "seatIndex": 2,
    "playerId": "p_10002",
    "autoPlayAfterSeconds": 30
  }
}
```

### 12.5 玩家重连

```json
{
  "type": "player_reconnected",
  "roomId": "r_90001",
  "eventSeq": 144,
  "serverTime": 1778150000000,
  "payload": {
    "seatIndex": 2,
    "playerId": "p_10002"
  }
}
```

### 12.6 单局结算

```json
{
  "type": "round_settled",
  "roomId": "r_90001",
  "eventSeq": 145,
  "serverTime": 1778150000000,
  "payload": {
    "gameId": "g_70001",
    "roundNo": 1,
    "winnerTeam": "A",
    "finishOrder": [
      {
        "seatIndex": 0,
        "playerId": "p_10001",
        "team": "A",
        "rank": 1
      }
    ],
    "caughtPlayers": [
      {
        "seatIndex": 3,
        "playerId": "p_10004",
        "team": "B"
      }
    ],
    "scoreDelta": {
      "teamA": 5,
      "teamB": 0
    },
    "totalScore": {
      "teamA": 5,
      "teamB": 0
    },
    "settlementReason": "team_all_finished"
  }
}
```

## 13. 权威状态要求

服务端必须保证：

- 洗牌和发牌在服务端完成。
- 每张牌有唯一 `cardId`。
- 每个玩家只能收到自己的完整手牌。
- 其他玩家只能看到余牌数。
- 当前轮到谁由服务端决定。
- 出牌必须由服务端校验。
- 客户端不能自行决定牌型是否合法。
- 客户端不能自行决定是否压过桌面牌。
- 出完名次由服务端记录。
- 单局结算由服务端计算。
- 真人不足 6 人开局时，空座必须由服务端 AI 补齐。
- AI 的出牌也必须经过同一套 `RuleEngine` 校验。
- 第一版 AI 使用最简单策略：新一轮出最小单张，跟牌时出最小可压牌，否则过牌。
- 结算完成后必须追加写入结构化战绩日志。
- 历史战绩接口只能从结构化战绩日志读取和聚合。
- Redis 是运行态事实来源，战绩日志是历史事实来源。
- 重复请求不能重复生效。
- 断线重连后必须能恢复当前玩家视角快照。

## 14. Flutter/安卓端状态映射

| 客户端状态 | 来源 |
| --- | --- |
| 房间信息 | 创建/加入房间返回、`table_snapshot` |
| 自己身份 | 创建/加入房间返回 |
| `playerToken` | 创建/加入房间返回，本地保存 |
| 座位和队伍 | `seats` |
| 我的手牌 | `myHand` |
| 其他玩家余牌数 | `seats[].cardCount` |
| 当前桌面牌型 | `tableCombo`、`cards_played` |
| 当前出牌者 | `currentTurnSeatIndex` |
| 出完顺序 | `finishOrder`、`cards_played.finishRank` |
| 单局结果 | `round_settled` |
| 总比分 | `score`、`round_settled.totalScore` |
| 历史战绩 | HTTP 战绩接口，从结构化战绩日志聚合 |

客户端不应自行修改这些权威状态，只能根据服务端事件更新。

## 15. 最小实现优先级

第一阶段：

1. 创建房间。
2. 通过房间号查询房间。
3. 通过房间号加入房间。
4. WebSocket 连接和 `playerToken` 校验。
5. Redis 状态读写。
6. 牌桌快照。
7. 准备/取消准备。
8. 房主开始游戏。
9. AI 补齐空座。
10. 最简单 AI 出牌策略。
11. 服务端洗牌和发牌。
12. 出牌校验和广播。
13. 过牌和新一轮。
14. 出完名次。
15. 单局结算。
16. 结算日志写入。
17. 从日志读取玩家历史战绩。
18. 从日志读取房间历史战绩。
19. 断线重连后重新推送快照。

第二阶段：

1. 超时自动过牌。
2. 房间过期清理。
3. Redis Pub/Sub 或 Streams 支持多实例事件分发。
4. 运行日志。
5. 更完整的天津/塘沽路规则。

## 16. 文档一致性要求

以下情况必须同步核对本文：

- 新增、删除或修改 HTTP 接口。
- 新增、删除或修改 WebSocket 事件。
- 修改 `playerToken` 机制。
- 修改房间、座位、牌桌状态字段。
- 修改出牌、过牌、发牌、结算逻辑。
- 修改 AI 补位或 AI 出牌策略。
- 修改 Redis key 设计或状态存储结构。
- 修改结构化战绩日志字段或历史战绩读取逻辑。
- 修改 Flutter 端联网模型。
- 新增服务端代码目录或后端仓库。

核对要求：

- 参数名、类型、必填项与代码一致。
- 返回结构与代码一致。
- 错误码与代码一致。
- WebSocket 事件名与代码一致。
- Flutter model 与服务端 JSON 字段一致。
- Redis key 和字段与实现一致。
- MatchLog 字段与战绩接口聚合逻辑一致。
- 如果代码暂未实现，应在本文标注为后续阶段，而不是让文档假装已经完成。
