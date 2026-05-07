# DoorSix 多人服务端核心设计

## 1. 文档目的

本文描述 DoorSix 为支持多人同时在一张桌子上打 `砸六家` 所需的服务端核心功能，以及 Flutter/安卓端需要调用的接口、参数和返回值。

当服务端、客户端、规则引擎或需求发生变更时，必须核对本文是否仍然与代码一致。

## 2. 设计目标

服务端需要承担权威状态，不允许客户端自行决定关键牌局结果。

核心目标：

- 支持账号登录和玩家身份识别。
- 支持创建房间、加入房间、离开房间。
- 支持 6 人同桌。
- 支持两队三人、隔位坐。
- 支持房主选择规则版本。
- 支持准备、开局、发牌。
- 支持出牌、过牌、回合轮转。
- 支持断线重连和牌桌状态恢复。
- 支持单局结算和总战绩。
- 支持把历史战绩写入结构化日志，并从日志读取战绩。
- 支持服务端校验牌型、出牌合法性和结算。

## 3. 总体架构

建议分为两类接口：

- HTTP 接口：登录、房间列表、创建房间、加入房间、获取历史战绩等非实时操作。
- WebSocket 接口：牌桌内实时事件，包括准备、开局、发牌、出牌、过牌、聊天、断线恢复、结算广播。
- 历史战绩首版不使用数据库，服务端通过追加式结构化日志保存结算记录，再从日志聚合读取。

推荐通信格式统一使用 JSON。

```text
Flutter/安卓端
  ├── HTTP API
  │   ├── 登录
  │   ├── 房间列表
  │   ├── 创建房间
  │   ├── 加入房间
  │   └── 查询战绩
  └── WebSocket
      ├── 进入牌桌
      ├── 准备/取消准备
      ├── 开始对局
      ├── 出牌/过牌
      ├── 牌桌状态同步
      └── 结算广播
```

## 4. 关键概念

### 4.1 玩家 Player

```json
{
  "playerId": "p_10001",
  "nickname": "小乙",
  "avatarUrl": "",
  "status": "online"
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `playerId` | string | 玩家唯一 ID |
| `nickname` | string | 昵称 |
| `avatarUrl` | string | 头像地址，可为空 |
| `status` | string | `online`、`offline`、`in_room`、`playing` |

### 4.2 房间 Room

```json
{
  "roomId": "r_90001",
  "roomCode": "384921",
  "ownerId": "p_10001",
  "status": "waiting",
  "ruleSetId": "tianjin_common",
  "playerCount": 4,
  "maxPlayers": 6,
  "createdAt": 1778150000000
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `roomId` | string | 房间唯一 ID |
| `roomCode` | string | 短房间号，用于邀请加入 |
| `ownerId` | string | 房主玩家 ID |
| `status` | string | `waiting`、`playing`、`settling`、`closed` |
| `ruleSetId` | string | 规则版本 ID |
| `playerCount` | number | 当前人数 |
| `maxPlayers` | number | 固定为 6 |
| `createdAt` | number | 毫秒时间戳 |

### 4.3 座位 Seat

座位固定 0 到 5。队伍按隔位分配：

- 0、2、4 为一队
- 1、3、5 为另一队

服务端可以根据房主规则或用户选择决定哪一组是 A 队。

```json
{
  "seatIndex": 0,
  "playerId": "p_10001",
  "team": "A",
  "ready": true,
  "connected": true,
  "cardCount": 18,
  "finishRank": null
}
```

### 4.4 卡牌 Card

服务端内部必须给每张牌分配唯一 ID，避免两副牌中重复牌面混淆。

```json
{
  "cardId": "d1-spades-A",
  "deckIndex": 1,
  "suit": "spades",
  "rank": "A"
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `cardId` | string | 单张牌唯一 ID |
| `deckIndex` | number | 第几副牌 |
| `suit` | string | `spades`、`hearts`、`diamonds`、`clubs`、`joker` |
| `rank` | string | `3` 到 `2`、`small_joker`、`big_joker` |

### 4.5 牌型 Combo

```json
{
  "comboType": "pair",
  "rankStrength": 13,
  "cardIds": ["d0-spades-K", "d1-hearts-K"],
  "label": "对子 K"
}
```

### 4.6 规则 RuleSet

```json
{
  "ruleSetId": "tianjin_common",
  "name": "天津通用",
  "deckCount": 2,
  "enableTribute": false,
  "enableReturnTribute": false,
  "enableAntiTribute": false,
  "enableFollowLead": false,
  "enableWildCards": false,
  "settlementMode": "finish_order_and_caught"
}
```

### 4.7 战绩日志 MatchLog

历史战绩首版不设计数据库表。服务端在每局结算时写入一条结构化 JSON 日志，后续查询战绩时从日志文件或日志流中读取并聚合。

推荐日志形态：一行一个 JSON 对象，方便追加、grep、按日期归档和离线重算。

日志文件建议：

```text
logs/matches/2026-05-07.ndjson
```

单条日志结构：

```json
{
  "logType": "round_settled",
  "logVersion": 1,
  "createdAt": 1778150000000,
  "roomId": "r_90001",
  "roomCode": "384921",
  "gameId": "g_70001",
  "roundNo": 1,
  "ruleSetId": "tianjin_common",
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

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `logType` | string | 日志类型，结算日志固定为 `round_settled` |
| `logVersion` | number | 日志结构版本，后续变更时递增 |
| `createdAt` | number | 毫秒时间戳 |
| `roomId` | string | 房间 ID |
| `roomCode` | string | 房间号 |
| `gameId` | string | 对局 ID |
| `roundNo` | number | 局号 |
| `ruleSetId` | string | 规则版本 |
| `winnerTeam` | string | 胜方队伍，`A` 或 `B` |
| `finishOrder` | object[] | 出完顺序 |
| `caughtPlayers` | object[] | 被逮玩家 |
| `scoreDelta` | object | 本局积分变化 |
| `totalScoreAfterRound` | object | 本局结束后的房间总分 |
| `players` | object[] | 本局所有参与玩家快照 |
| `settlementReason` | string | 结算原因 |

日志写入要求：

- 只在服务端完成结算后写入。
- 必须追加写入，不能覆盖旧日志。
- 单条日志必须是完整 JSON，不能依赖上下文才能解析。
- 写入失败时，服务端仍可广播结算，但必须记录错误日志并允许后台补写。
- 查询战绩接口只从日志聚合，不直接读内存牌桌状态。
- 后续如需上数据库，数据库数据应可由这些日志重放生成。

## 5. 通用返回结构

HTTP 接口统一返回：

```json
{
  "success": true,
  "requestId": "req_abc",
  "data": {},
  "error": null
}
```

失败：

```json
{
  "success": false,
  "requestId": "req_abc",
  "data": null,
  "error": {
    "code": "ROOM_FULL",
    "message": "房间已满"
  }
}
```

常见错误码：

| 错误码 | 说明 |
| --- | --- |
| `UNAUTHORIZED` | 未登录或 token 无效 |
| `ROOM_NOT_FOUND` | 房间不存在 |
| `ROOM_FULL` | 房间已满 |
| `ROOM_ALREADY_PLAYING` | 房间已开局 |
| `NOT_ROOM_OWNER` | 只有房主可操作 |
| `SEAT_TAKEN` | 座位已被占用 |
| `INVALID_ACTION` | 操作不合法 |
| `NOT_YOUR_TURN` | 未轮到该玩家 |
| `INVALID_CARDS` | 牌不存在、不是自己的牌或重复提交 |
| `INVALID_COMBO` | 牌型不合法 |
| `CANNOT_BEAT_TABLE_COMBO` | 压不过当前桌面牌型 |
| `GAME_NOT_STARTED` | 对局未开始 |
| `GAME_ALREADY_SETTLED` | 本局已结算 |

## 6. HTTP 接口

### 6.1 登录

用于建立玩家身份。首版可以使用游客登录。

```http
POST /api/v1/auth/guest
```

请求参数：

```json
{
  "deviceId": "android_device_uuid",
  "nickname": "小乙"
}
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `deviceId` | string | 是 | 设备唯一 ID |
| `nickname` | string | 否 | 昵称，不传则服务端生成 |

返回：

```json
{
  "success": true,
  "requestId": "req_001",
  "data": {
    "accessToken": "jwt_token",
    "expiresIn": 604800,
    "player": {
      "playerId": "p_10001",
      "nickname": "小乙",
      "avatarUrl": "",
      "status": "online"
    }
  },
  "error": null
}
```

### 6.2 获取规则版本列表

```http
GET /api/v1/rule-sets
```

请求 Header：

```text
Authorization: Bearer <accessToken>
```

返回：

```json
{
  "success": true,
  "requestId": "req_002",
  "data": {
    "ruleSets": [
      {
        "ruleSetId": "tianjin_common",
        "name": "天津通用",
        "deckCount": 2,
        "enableTribute": false,
        "enableReturnTribute": false,
        "enableAntiTribute": false,
        "enableFollowLead": false,
        "enableWildCards": false,
        "settlementMode": "finish_order_and_caught"
      },
      {
        "ruleSetId": "tanggu",
        "name": "塘沽路",
        "deckCount": 2,
        "enableTribute": true,
        "enableReturnTribute": true,
        "enableAntiTribute": true,
        "enableFollowLead": true,
        "enableWildCards": false,
        "settlementMode": "finish_order_and_caught"
      }
    ]
  },
  "error": null
}
```

### 6.3 创建房间

```http
POST /api/v1/rooms
```

请求参数：

```json
{
  "ruleSetId": "tianjin_common",
  "isPrivate": true,
  "seatIndex": 0,
  "allowSpectators": false
}
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `ruleSetId` | string | 是 | 规则版本 ID |
| `isPrivate` | boolean | 否 | 是否私密房间 |
| `seatIndex` | number | 否 | 房主希望坐的位置，0 到 5 |
| `allowSpectators` | boolean | 否 | 是否允许旁观 |

返回：

```json
{
  "success": true,
  "requestId": "req_003",
  "data": {
    "room": {
      "roomId": "r_90001",
      "roomCode": "384921",
      "ownerId": "p_10001",
      "status": "waiting",
      "ruleSetId": "tianjin_common",
      "playerCount": 1,
      "maxPlayers": 6,
      "createdAt": 1778150000000
    },
    "tableState": {
      "roomId": "r_90001",
      "seats": [
        {
          "seatIndex": 0,
          "playerId": "p_10001",
          "team": "A",
          "ready": false,
          "connected": true,
          "cardCount": 0,
          "finishRank": null
        }
      ]
    },
    "webSocketUrl": "wss://api.example.com/ws/v1/tables/r_90001"
  },
  "error": null
}
```

### 6.4 获取房间列表

```http
GET /api/v1/rooms?status=waiting&page=1&pageSize=20
```

查询参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `status` | string | 否 | `waiting`、`playing` |
| `page` | number | 否 | 页码 |
| `pageSize` | number | 否 | 每页数量 |

返回：

```json
{
  "success": true,
  "requestId": "req_004",
  "data": {
    "rooms": [
      {
        "roomId": "r_90001",
        "roomCode": "384921",
        "ownerId": "p_10001",
        "status": "waiting",
        "ruleSetId": "tianjin_common",
        "playerCount": 4,
        "maxPlayers": 6,
        "createdAt": 1778150000000
      }
    ],
    "page": 1,
    "pageSize": 20,
    "total": 1
  },
  "error": null
}
```

### 6.5 通过房间号查询房间

```http
GET /api/v1/rooms/by-code/{roomCode}
```

返回：

```json
{
  "success": true,
  "requestId": "req_005",
  "data": {
    "room": {
      "roomId": "r_90001",
      "roomCode": "384921",
      "ownerId": "p_10001",
      "status": "waiting",
      "ruleSetId": "tianjin_common",
      "playerCount": 4,
      "maxPlayers": 6,
      "createdAt": 1778150000000
    }
  },
  "error": null
}
```

### 6.6 加入房间

```http
POST /api/v1/rooms/{roomId}/join
```

请求参数：

```json
{
  "seatIndex": 2,
  "asSpectator": false
}
```

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `seatIndex` | number | 否 | 指定座位，0 到 5；不传由服务端分配 |
| `asSpectator` | boolean | 否 | 是否旁观 |

返回：

```json
{
  "success": true,
  "requestId": "req_006",
  "data": {
    "room": {
      "roomId": "r_90001",
      "roomCode": "384921",
      "ownerId": "p_10001",
      "status": "waiting",
      "ruleSetId": "tianjin_common",
      "playerCount": 5,
      "maxPlayers": 6,
      "createdAt": 1778150000000
    },
    "seatIndex": 2,
    "webSocketUrl": "wss://api.example.com/ws/v1/tables/r_90001"
  },
  "error": null
}
```

### 6.7 离开房间

```http
POST /api/v1/rooms/{roomId}/leave
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
  "requestId": "req_007",
  "data": {
    "roomId": "r_90001",
    "left": true,
    "roomClosed": false
  },
  "error": null
}
```

### 6.8 获取房间快照

用于进入房间前或断线后补状态。

```http
GET /api/v1/rooms/{roomId}/snapshot
```

返回：

```json
{
  "success": true,
  "requestId": "req_008",
  "data": {
    "tableState": {
      "roomId": "r_90001",
      "gameId": "g_70001",
      "roundNo": 1,
      "status": "playing",
      "ruleSetId": "tianjin_common",
      "dealerSeatIndex": 0,
      "currentTurnSeatIndex": 3,
      "lastPlayedSeatIndex": 1,
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

说明：`myHand` 只返回当前玩家自己的手牌。其他玩家只能看到余牌数量。

### 6.9 获取玩家战绩

从结算日志中聚合玩家战绩。首版不查询数据库。

```http
GET /api/v1/players/me/stats
```

查询参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `from` | number | 否 | 起始毫秒时间戳 |
| `to` | number | 否 | 结束毫秒时间戳 |
| `ruleSetId` | string | 否 | 只统计某个规则版本 |
| `limit` | number | 否 | 最近结果数量，默认 20 |

返回：

```json
{
  "success": true,
  "requestId": "req_009",
  "data": {
    "totalGames": 20,
    "wins": 12,
    "losses": 8,
    "winRate": 0.6,
    "recentResults": [
      {
        "gameId": "g_70001",
        "ruleSetId": "tianjin_common",
        "result": "win",
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

### 6.10 获取房间历史战绩

从结算日志中读取某个房间的历史局记录。

```http
GET /api/v1/rooms/{roomId}/history?limit=20
```

查询参数：

| 参数 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `limit` | number | 否 | 返回最近多少局，默认 20 |
| `before` | number | 否 | 返回该时间戳之前的记录 |

返回：

```json
{
  "success": true,
  "requestId": "req_010",
  "data": {
    "roomId": "r_90001",
    "rounds": [
      {
        "gameId": "g_70001",
        "roundNo": 1,
        "ruleSetId": "tianjin_common",
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

## 7. WebSocket 连接

### 7.1 连接地址

```text
wss://api.example.com/ws/v1/tables/{roomId}?token=<accessToken>
```

连接成功后，服务端推送 `table_snapshot`。

### 7.2 WebSocket 通用消息结构

客户端发送：

```json
{
  "type": "client_event_type",
  "requestId": "req_ws_001",
  "roomId": "r_90001",
  "seq": 12,
  "payload": {}
}
```

服务端推送：

```json
{
  "type": "server_event_type",
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
| `requestId` | string | 请求 ID；广播事件可为空 |
| `roomId` | string | 房间 ID |
| `seq` | number | 客户端递增序号，用于排查重复请求 |
| `eventSeq` | number | 服务端事件递增序号，用于断线补偿 |
| `serverTime` | number | 服务端毫秒时间戳 |
| `payload` | object | 业务数据 |

## 8. WebSocket 客户端事件

### 8.1 心跳

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

### 8.2 准备

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

服务端校验：

- 玩家在房间内。
- 房间状态为 `waiting`。
- 玩家已坐下。

服务端广播：

```json
{
  "type": "seat_updated",
  "roomId": "r_90001",
  "eventSeq": 131,
  "serverTime": 1778150000000,
  "payload": {
    "seatIndex": 2,
    "playerId": "p_10002",
    "ready": true,
    "connected": true
  }
}
```

### 8.3 取消准备

```json
{
  "type": "ready",
  "requestId": "req_ws_011",
  "roomId": "r_90001",
  "seq": 11,
  "payload": {
    "ready": false
  }
}
```

返回同 `seat_updated`。

### 8.4 房主开始游戏

```json
{
  "type": "start_game",
  "requestId": "req_ws_012",
  "roomId": "r_90001",
  "seq": 12,
  "payload": {}
}
```

服务端校验：

- 发送者是房主。
- 房间有 6 名玩家。
- 6 名玩家都已准备。
- 房间状态为 `waiting`。

服务端广播：

```json
{
  "type": "game_started",
  "roomId": "r_90001",
  "eventSeq": 132,
  "serverTime": 1778150000000,
  "payload": {
    "gameId": "g_70001",
    "roundNo": 1,
    "dealerSeatIndex": 0,
    "currentTurnSeatIndex": 0,
    "seats": [
      {
        "seatIndex": 0,
        "playerId": "p_10001",
        "team": "A",
        "ready": true,
        "connected": true,
        "cardCount": 18,
        "finishRank": null
      }
    ],
    "myHand": [
      {
        "cardId": "d0-spades-A",
        "deckIndex": 0,
        "suit": "spades",
        "rank": "A"
      }
    ]
  }
}
```

说明：`myHand` 必须按接收者不同分别推送，不能把某个玩家手牌广播给所有人。

### 8.5 出牌

```json
{
  "type": "play_cards",
  "requestId": "req_ws_013",
  "roomId": "r_90001",
  "seq": 13,
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
- 当前玩家在房间内且连接有效。
- 当前轮到该玩家。
- `cardIds` 都属于该玩家手牌。
- `cardIds` 无重复。
- 牌型合法。
- 该牌型能压过当前桌面牌型，或当前为新一轮领出。

服务端返回给请求者：

```json
{
  "type": "action_accepted",
  "requestId": "req_ws_013",
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

如果玩家出完，`finishRank` 返回数字：

```json
{
  "finishRank": 1
}
```

### 8.6 过牌

```json
{
  "type": "pass",
  "requestId": "req_ws_014",
  "roomId": "r_90001",
  "seq": 14,
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

如果一圈过牌后进入新一轮：

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

### 8.7 请求提示

提示可以由客户端本地算，也可以由服务端根据权威状态算。为防止规则不一致，正式多人模式建议服务端提供提示。

```json
{
  "type": "request_hint",
  "requestId": "req_ws_015",
  "roomId": "r_90001",
  "seq": 15,
  "payload": {
    "gameId": "g_70001",
    "roundNo": 1
  }
}
```

服务端返回给请求者：

```json
{
  "type": "hint_result",
  "requestId": "req_ws_015",
  "roomId": "r_90001",
  "eventSeq": 137,
  "serverTime": 1778150000000,
  "payload": {
    "cardIds": ["d0-spades-A", "d1-hearts-A"],
    "combo": {
      "comboType": "pair",
      "rankStrength": 14,
      "cardIds": ["d0-spades-A", "d1-hearts-A"],
      "label": "对子 A"
    },
    "message": "可以出对子 A"
  }
}
```

### 8.8 请求状态同步

用于客户端发现事件序号断层、切后台恢复或网络抖动。

```json
{
  "type": "sync_state",
  "requestId": "req_ws_016",
  "roomId": "r_90001",
  "seq": 16,
  "payload": {
    "lastEventSeq": 130
  }
}
```

服务端返回：

```json
{
  "type": "table_snapshot",
  "requestId": "req_ws_016",
  "roomId": "r_90001",
  "eventSeq": 138,
  "serverTime": 1778150000000,
  "payload": {
    "tableState": {},
    "myHand": [],
    "missedEvents": []
  }
}
```

说明：

- 如果缺失事件数量较少，可以返回 `missedEvents`。
- 如果缺失过多，直接返回完整 `tableState`。

### 8.9 发送快捷聊天

```json
{
  "type": "quick_chat",
  "requestId": "req_ws_017",
  "roomId": "r_90001",
  "seq": 17,
  "payload": {
    "messageId": "nice",
    "text": "漂亮"
  }
}
```

服务端广播：

```json
{
  "type": "quick_chat_received",
  "roomId": "r_90001",
  "eventSeq": 139,
  "serverTime": 1778150000000,
  "payload": {
    "seatIndex": 0,
    "playerId": "p_10001",
    "messageId": "nice",
    "text": "漂亮"
  }
}
```

## 9. WebSocket 服务端主动事件

### 9.1 牌桌快照

```json
{
  "type": "table_snapshot",
  "roomId": "r_90001",
  "eventSeq": 140,
  "serverTime": 1778150000000,
  "payload": {
    "tableState": {
      "roomId": "r_90001",
      "gameId": "g_70001",
      "roundNo": 1,
      "status": "playing",
      "ruleSetId": "tianjin_common",
      "currentTurnSeatIndex": 0,
      "lastPlayedSeatIndex": null,
      "tableCombo": null,
      "seats": [],
      "finishOrder": [],
      "score": {
        "teamA": 0,
        "teamB": 0
      }
    },
    "myHand": [],
    "eventSeq": 140
  }
}
```

### 9.2 玩家加入

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
      "team": "A",
      "ready": false,
      "connected": true,
      "cardCount": 0,
      "finishRank": null
    },
    "player": {
      "playerId": "p_10002",
      "nickname": "玩家2",
      "avatarUrl": "",
      "status": "in_room"
    }
  }
}
```

### 9.3 玩家离开

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

### 9.4 玩家断线

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

### 9.5 玩家重连

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

### 9.6 单局结算

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

### 9.7 新一局开始

```json
{
  "type": "next_round_started",
  "roomId": "r_90001",
  "eventSeq": 146,
  "serverTime": 1778150000000,
  "payload": {
    "gameId": "g_70002",
    "roundNo": 2,
    "dealerSeatIndex": 1,
    "currentTurnSeatIndex": 1,
    "seats": [],
    "myHand": []
  }
}
```

## 10. 权威状态与安全要求

服务端必须保证：

- 洗牌和发牌在服务端完成。
- 每张牌有唯一 `cardId`。
- 每个玩家只能收到自己的完整手牌。
- 出牌必须由服务端校验。
- 当前轮到谁由服务端决定。
- 出完名次由服务端记录。
- 单局结算由服务端计算。
- 客户端事件必须有幂等保护，重复请求不能重复生效。
- 断线玩家可以保留座位一段时间。
- 超时未操作时，服务端可以托管过牌或自动出牌。
- 历史战绩以结构化结算日志为事实来源，首版不依赖数据库。
- 写入结算日志时要保证一局只写一次，重复结算事件不能产生重复战绩。

## 11. 安卓/Flutter 端状态映射

客户端建议维护：

| 客户端状态 | 来源 |
| --- | --- |
| 当前房间 | HTTP 创建/加入房间返回、`table_snapshot` |
| 当前座位 | HTTP 加入房间返回、`table_snapshot` |
| 队伍关系 | `seats` |
| 我的手牌 | `myHand` |
| 其他玩家余牌数 | `seats[].cardCount` |
| 当前桌面牌型 | `tableCombo`、`cards_played` |
| 当前出牌者 | `currentTurnSeatIndex` |
| 出完顺序 | `finishOrder`、`cards_played.finishRank` |
| 单局结果 | `round_settled` |
| 总比分 | `score`、`round_settled.totalScore` |
| 历史战绩 | HTTP 战绩接口，从结算日志聚合 |

客户端不应自行修改这些权威状态，只能根据服务端事件更新。

## 12. 首版实现优先级

第一阶段：

1. 游客登录。
2. 创建房间。
3. 加入房间。
4. WebSocket 入桌。
5. 准备。
6. 开局发牌。
7. 出牌。
8. 过牌。
9. 断线重连状态同步。
10. 单局结算。
11. 结算日志写入。
12. 从日志读取玩家战绩。

第二阶段：

1. 房间列表。
2. 房间号邀请。
3. 快捷聊天。
4. 托管。
5. 房间历史战绩。
6. 自定义规则。

第三阶段：

1. 好友系统。
2. 语音。
3. 观战。
4. 回放。
5. 排行榜。

## 13. 文档一致性要求

以下情况必须同步核对本文：

- 新增、删除或修改服务端接口。
- 修改 WebSocket 消息结构。
- 修改牌局状态字段。
- 修改规则版本字段。
- 修改客户端模型。
- 修改 `lib/services/rule_engine.dart`。
- 修改多人房间、座位、出牌、过牌、结算逻辑。
- 修改结算日志结构或历史战绩读取逻辑。
- 新增服务端代码目录或后端仓库。

核对要求：

- 参数名、类型、必填项与代码一致。
- 返回结构与代码一致。
- 错误码与代码一致。
- WebSocket 事件名与代码一致。
- 客户端状态映射与 Flutter model 一致。
- 结算日志字段与战绩接口聚合逻辑一致。
- 如果代码暂未实现，应在本文标注为后续阶段，而不是让文档假装已经完成。
