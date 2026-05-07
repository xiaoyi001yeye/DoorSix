# DoorSix Remote Smoke Test Report

- Test time: 2026-05-08 00:18 CST
- Target: `http://39.104.67.175`
- Command: `npm run test:remote`
- Result: Passed

## Summary

The remote DoorSix backend is reachable on port 80 and passed the smoke test suite. Redis is connected, HTTP APIs respond correctly, WebSocket gameplay setup works, AI seats are filled, and the temporary test room is cleaned up.

## Test Results

| Check | Result |
| --- | --- |
| Health endpoint reports service and Redis | Passed |
| Unknown room code returns structured 404 | Passed |
| Create room as owner | Passed |
| Lookup created room by code | Passed |
| Join second human player | Passed |
| Snapshot, stats, and history endpoints authenticate by token | Passed |
| WebSocket ready/start flow reaches playing table | Passed |
| Snapshot sees started game and cleanup closes room | Passed |

## Raw Output

```text
> doorsix-server@0.1.0 test:remote
> node scripts/remote-smoke-test.js

DoorSix remote smoke test: http://39.104.67.175
ok   health endpoint reports service and Redis (57ms)
ok   unknown room code returns structured 404 (38ms)
ok   create room as owner (25ms)
ok   lookup created room by code (20ms)
ok   join second human player (28ms)
ok   snapshot, stats, and history endpoints authenticate by token (63ms)
ok   WebSocket ready/start flow reaches playing table (261ms)
ok   snapshot sees started game and cleanup closes room (60ms)
All remote smoke tests passed.
```

## Coverage

- `GET /health`
- `GET /api/v1/rooms/by-code/:roomCode`
- `POST /api/v1/rooms`
- `POST /api/v1/rooms/by-code/:roomCode/join`
- `GET /api/v1/rooms/:roomId/snapshot`
- `GET /api/v1/players/me/stats`
- `GET /api/v1/rooms/:roomId/history`
- `POST /api/v1/rooms/:roomId/leave`
- `WS /ws/v1/tables/:roomId?playerToken=...`

