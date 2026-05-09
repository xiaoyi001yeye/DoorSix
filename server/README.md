# DoorSix Server

Minimal multiplayer backend for DoorSix.

## Run locally

```bash
npm install
npm start
```

If `REDIS_URL` is not reachable, the server falls back to in-memory state for local development. Production should use Redis.

## Run with Docker

```bash
docker compose up -d --build
```

## Test remote deployment

```bash
npm run test:remote
```

By default this tests `http://39.104.67.175`. To test another deployment:

```bash
REMOTE_BASE_URL=http://example.com npm run test:remote
```

## API

- `GET /health`
- `POST /api/v1/rooms`
- `GET /api/v1/rooms/by-code/:roomCode`
- `POST /api/v1/rooms/by-code/:roomCode/join`
- `POST /api/v1/rooms/:roomId/leave`
- `GET /api/v1/rooms/:roomId/snapshot`
- `GET /api/v1/players/me/stats`
- `GET /api/v1/rooms/:roomId/history`
- `GET /api/v1/app-updates/latest`
- `GET /api/v1/app-updates/releases/android`
- `GET /api/v1/app-updates/releases/:platform/:versionCode`
- `GET /downloads/android`
- `WS /ws/v1/tables/:roomId?playerToken=...`
