# DoorSix 后端接口测试报告

- 测试时间：2026-05-08 01:36:43 Asia/Shanghai
- 测试地址：http://127.0.0.1:59419
- 测试模式：本地自动拉起服务（内存状态）
- 测试结论：未发现后端接口阻断性问题
- 汇总：共 33 项，通过 33 项，失败 0 项，跳过 0 项

## HTTP 接口

| 编号 | 测试对象 | 场景 | 结果 | 耗时 | 说明 |
| --- | --- | --- | --- | ---: | --- |
| H01 | GET /health | 健康检查 | 通过 | 2ms | 服务可用，Redis=false |
| H02 | GET /api/v1/rooms/by-code/:roomCode | 未知房间号返回结构化 404 | 通过 | 1ms | 符合预期 |
| H03 | POST /api/v1/rooms | 创建房间拒绝空昵称 | 通过 | 4ms | 符合预期 |
| H04 | POST /api/v1/rooms | 创建房间拒绝非法座位 | 通过 | 1ms | 符合预期 |
| H05 | POST /api/v1/rooms | 创建房间成功 | 通过 | 2ms | 房间号 673465 |
| H06 | GET /api/v1/rooms/by-code/:roomCode | 按房间号查询成功 | 通过 | 0ms | 符合预期 |
| H07 | POST /api/v1/rooms/by-code/:roomCode/join | 加入房间拒绝空昵称 | 通过 | 1ms | 符合预期 |
| H08 | POST /api/v1/rooms/by-code/:roomCode/join | 加入房间拒绝非法座位 | 通过 | 1ms | 符合预期 |
| H09 | POST /api/v1/rooms/by-code/:roomCode/join | 加入房间拒绝已占座位 | 通过 | 1ms | 符合预期 |
| H10 | POST /api/v1/rooms/by-code/:roomCode/join | 加入房间成功 | 通过 | 0ms | 符合预期 |
| H11 | GET /api/v1/rooms/:roomId/snapshot | 快照接口缺 token 返回 401 | 通过 | 1ms | 符合预期 |
| H12 | GET /api/v1/rooms/:roomId/snapshot | 快照接口错误 token 返回 401 | 通过 | 0ms | 符合预期 |
| H13 | GET /api/v1/rooms/:roomId/snapshot | 快照接口成功且不泄露他人手牌 | 通过 | 0ms | 符合预期 |
| H14 | GET /api/v1/players/me/stats | 个人战绩接口成功 | 通过 | 1ms | 符合预期 |
| H15 | GET /api/v1/rooms/:roomId/history | 房间历史接口成功 | 通过 | 1ms | 符合预期 |
| H16 | POST /api/v1/rooms/:roomId/leave | 普通玩家离开等待房释放座位 | 通过 | 1ms | 符合预期 |
| H17 | POST /api/v1/rooms/by-code/:roomCode/join | 加入满房时返回 ROOM_FULL | 通过 | 3ms | 符合预期 |
| W10 | POST /api/v1/rooms/by-code/:roomCode/join | 开局后禁止新玩家加入 | 通过 | 0ms | 符合预期 |

## WebSocket

| 编号 | 测试对象 | 场景 | 结果 | 耗时 | 说明 |
| --- | --- | --- | --- | ---: | --- |
| W01 | POST /api/v1/rooms + join | 创建联机测试房间 | 通过 | 1ms | 房间号 356616 |
| W02 | WS /ws/v1/tables/:roomId | 错误 token 被拒绝连接 | 通过 | 3ms | 符合预期 |
| W03 | WS table_snapshot | 连接后收到初始快照 | 通过 | 2ms | 符合预期 |
| W04 | WS ping | ping 返回 pong | 通过 | 1ms | 符合预期 |
| W05 | WS play_cards | 未开局时出牌被拒绝 | 通过 | 0ms | 符合预期 |
| W06 | WS start_game | 非房主不能开局 | 通过 | 0ms | 符合预期 |
| W07 | WS start_game | 房主在玩家未准备时不能开局 | 通过 | 0ms | 符合预期 |
| W08 | WS ready | ready 状态广播 | 通过 | 1ms | 符合预期 |
| W09 | WS start_game | 房主开局成功，AI 补齐且仅返回自己的手牌 | 通过 | 5ms | 符合预期 |
| W11 | WS sync_state | sync_state 返回最新快照 | 通过 | 1ms | 符合预期 |
| W12 | WS play_cards | 非当前回合出牌被拒绝 | 通过 | 0ms | 符合预期 |
| W13 | WS play_cards | 当前玩家提交不存在的牌被拒绝 | 通过 | 0ms | 符合预期 |
| W14 | WS pass | 当前玩家领出时不能过牌 | 通过 | 1ms | 符合预期 |
| W15 | WS play_cards/pass | 当前玩家合法出牌或可过牌操作 | 通过 | 1ms | 提交 1 张牌成功 |
| W16 | WS reconnect | 断线后用同 token 重连可恢复快照 | 通过 | 152ms | 符合预期 |

## 接口健康判断

| 接口/消息 | 是否发现问题 | 覆盖点 |
| --- | --- | --- |
| GET /health | 未发现问题 | H01 |
| GET /api/v1/rooms/by-code/:roomCode | 未发现问题 | H02、H06 |
| POST /api/v1/rooms | 未发现问题 | H03、H04、H05 |
| POST /api/v1/rooms/by-code/:roomCode/join | 未发现问题 | H07、H08、H09、H10、H17、W10 |
| GET /api/v1/rooms/:roomId/snapshot | 未发现问题 | H11、H12、H13 |
| GET /api/v1/players/me/stats | 未发现问题 | H14 |
| GET /api/v1/rooms/:roomId/history | 未发现问题 | H15 |
| POST /api/v1/rooms/:roomId/leave | 未发现问题 | H16 |
| POST /api/v1/rooms + join | 未发现问题 | W01 |
| WS /ws/v1/tables/:roomId | 未发现问题 | W02 |
| WS table_snapshot | 未发现问题 | W03 |
| WS ping | 未发现问题 | W04 |
| WS play_cards | 未发现问题 | W05、W12、W13 |
| WS start_game | 未发现问题 | W06、W07、W09 |
| WS ready | 未发现问题 | W08 |
| WS sync_state | 未发现问题 | W11 |
| WS pass | 未发现问题 | W14 |
| WS play_cards/pass | 未发现问题 | W15 |
| WS reconnect | 未发现问题 | W16 |

## 备注

- 本程序重点判断后端 HTTP 接口、WebSocket 鉴权、状态同步、开局、出牌/过牌基础行为是否符合测试计划。
- 如果测试模式为本地自动拉起服务，则 Redis 会被显式置空，报告中的 Redis=false 属于预期；远程部署可通过 `BACKEND_TEST_BASE_URL` 指定地址后再测。
- 牌局存在随机发牌，本报告对合法出牌会动态计算当前玩家可出的牌；如果当前局面只能过牌，会以合法过牌验证替代。
