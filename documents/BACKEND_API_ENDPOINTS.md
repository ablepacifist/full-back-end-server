# Lexicon + Alchemy Backend API Reference

Last updated: 2026-03-05  
Source of truth: controller mappings in `lexiconServer/src/main/java/lexicon/api` and `alchemyServer/src/main/java/alchemy/api`

## 1) Base URLs

## Local
- Lexicon API: `http://localhost:36568`
- Alchemy API: `http://localhost:8080`

## Common public/tunnel URLs used in this workspace
- Frontend: `http://lexicon.playit.pub:15903`
- Lexicon API: `http://through-sponsor.gl.at.ply.gg:15856`
- Alchemy API: `http://type-magnetic.gl.at.ply.gg:15821`

## Frontend env vars
- `REACT_APP_LEXICON_API_URL` → Lexicon backend
- `REACT_APP_API_URL` → Alchemy backend

---

## 2) CORS Rules

## Lexicon (`lexiconServer`)
Configured in `LexiconSecurityConfig` + controller-level `@CrossOrigin`.

- `allowCredentials`: `true`
- Methods: `GET, POST, PUT, DELETE, OPTIONS, HEAD`
- Allowed headers: `*`
- Exposed headers: `Content-Range, Accept-Ranges, Content-Length, Content-Type, Cache-Control, X-Accel-Buffering`
- `maxAge`: `3600`

### Allowed origins/patterns (effective)
From `cors.allowed.origins` property + hardcoded additions:
- `http://localhost:3000`
- `http://localhost:3001`
- Property defaults include multiple tunnel/IP entries
- `http://147.185.221.24:*`
- `https://147.185.221.24:*`
- `http://*.playit.pub:*`
- `https://*.playit.pub:*`
- `https://alex-dyakin.com`
- `https://*.alex-dyakin.com`
- `http://localhost:3080`
- `https://voice.alex-dyakin.com`
- `https://mumble.alex-dyakin.com`

### SSE note
`/api/livestream/updates` explicitly sets `allowCredentials = false` at method level.

## Alchemy (`alchemyServer`)
Configured in both `SecurityConfig` and `CorsConfig`.

- `SecurityConfig`:
  - `allowCredentials`: `true`
  - Methods: `GET, POST, PUT, DELETE, OPTIONS, HEAD`
  - Allowed headers: `*`
  - Exposed headers: `X-Auth-Token`
  - Origins from `cors.allowed-origins` + `https://alex-dyakin.com` + `https://*.alex-dyakin.com`
- `CorsConfig` additionally registers:
  - `allowedOriginPatterns("*")`
  - `allowedMethods("*")`
  - `allowedHeaders("*")`

Practical result: Alchemy CORS is permissive in current codebase.

---

## 3) How to Connect

## Browser/Frontend (cookie/session-safe)
Use `credentials: 'include'` for auth/session endpoints.

```js
const LEXICON_API = process.env.REACT_APP_LEXICON_API_URL || 'http://localhost:36568';
const ALCHEMY_API = process.env.REACT_APP_API_URL || 'http://localhost:8080';

await fetch(`${LEXICON_API}/api/auth/login`, {
  method: 'POST',
  credentials: 'include',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username, password })
});
```

## Curl (persist cookies)
```bash
# Lexicon login
curl -i -c lexicon.cookies -H 'Content-Type: application/json' \
  -d '{"username":"demo","password":"demo"}' \
  http://localhost:36568/api/auth/login

# Authenticated call
curl -b lexicon.cookies http://localhost:36568/api/auth/me
```

SSE example:
```bash
curl -N "http://localhost:36568/api/livestream/updates?channel=video"
```

---

## 4) Lexicon API Endpoints (`/api/...`)

## Health/Test
- `GET /api/health`
- `GET /api/info`

## Auth (`/api/auth`)
- `POST /api/auth/login`
- `POST /api/auth/register`
- `GET /api/auth/me`
- `POST /api/auth/logout`

## Players (`/api/players`)
- `GET /api/players`
- `GET /api/players/{id}`
- `GET /api/players/username/{username}`
- `POST /api/players/register`
- `POST /api/players/login`
- `PUT /api/players/{id}`
- `DELETE /api/players/{id}`

## Media (`/api/media`)
- `POST /api/media/upload` (multipart; `file`, `userId`, `title`, optional metadata)
- `POST /api/media/upload-from-url`
- `GET /api/media/{id}`
- `GET /api/media/user/{userId}`
- `GET /api/media/public`
- `GET /api/media/search?q=...`
- `GET /api/media/recent?limit=...`
- `PUT /api/media/{id}`
- `DELETE /api/media/{id}?userId=...`
- `GET /api/media/{id}/access?userId=...`
- `GET /api/media/{id}/download`
- `GET /api/media/stream/{id}`

## Chunked media upload (`/api/media/chunked`)
- `POST /api/media/chunked/init`
- `POST /api/media/chunked/upload/{uploadId}`
- `GET /api/media/chunked/status/{uploadId}`
- `GET /api/media/chunked/missing/{uploadId}`
- `POST /api/media/chunked/finalize/{uploadId}`
- `DELETE /api/media/chunked/{uploadId}`
- `GET /api/media/chunked/progress/{uploadId}`

## Async download queue (`/api/download-queue`)
- `POST /api/download-queue/start`
- `GET /api/download-queue/status/{jobId}`
- `GET /api/download-queue/active/{userId}`
- `DELETE /api/download-queue/{jobId}`

## Playlists (`/api/playlists`)
- `POST /api/playlists`
- `GET /api/playlists`
- `GET /api/playlists/user/{userId}`
- `GET /api/playlists/public`
- `GET /api/playlists/{id}`
- `PUT /api/playlists/{id}`
- `DELETE /api/playlists/{id}`
- `POST /api/playlists/{id}/items`
- `DELETE /api/playlists/{id}/items/{mediaId}`
- `PUT /api/playlists/{id}/reorder`
- `POST /api/playlists/import-youtube`
- `GET /api/playlists/import-progress/{importId}`

## Playback positions (`/api/playback`)
- `POST /api/playback/position`
- `GET /api/playback/position/{userId}/{mediaFileId}`
- `GET /api/playback/user/{userId}`
- `DELETE /api/playback/position/{userId}/{mediaFileId}`

## Live stream full (`/api/livestream`)
Most endpoints accept `?channel=video|music` (default `video`).

- `GET /api/livestream/state`
- `GET /api/livestream/queue`
- `GET /api/livestream/eligible-media`
- `POST /api/livestream/queue`
- `DELETE /api/livestream/queue/{queueId}`
- `POST /api/livestream/skip`
- `GET /api/livestream/updates` (SSE)
- `POST /api/livestream/media-ended`
- `POST /api/livestream/advance`

## Stream transport (`/api/stream`)
- `GET /api/stream/{mediaFileId}`
- `GET /api/stream/{mediaFileId}/info`

## Messages (`/api/messages`)
- `POST /api/messages`
- `GET /api/messages/channel/{channelId}`
- `GET /api/messages/{id}`
- `PUT /api/messages/{id}`
- `DELETE /api/messages/{id}`
- `GET /api/messages/search`

## Chat Files (`/api/chat`) — Rich Media Chat
- `POST /api/chat/upload` — Upload image/GIF for chat (multipart: file, userId, channelId)
- `GET /api/chat/files/{fileId}` — Serve original file
- `GET /api/chat/files/{fileId}/thumb` — Serve thumbnail (max 400px wide)

## Avatar proxy (`/api/avatar`)
- `GET /api/avatar/{username}`
- `POST /api/avatar/upload`
- `POST /api/avatar/remove`

---

## 5) Alchemy API Endpoints (`/api/...`)

## Root/Home
- `GET /`

## Auth (`/api/auth`)
- `POST /api/auth/login`
- `POST /api/auth/register`
- `GET /api/auth/me`

## Game (`/api/game`)
- `POST /api/game/start`
- `POST /api/game/end`
- `GET /api/game/forage/{playerId}`

## Player (`/api/player`)
- `GET /api/player/{id}`
- `GET /api/player/username/{username}`
- `GET /api/player/all`
- `GET /api/player/inventory/{playerId}`
- `GET /api/player/forage/{playerId}`
- `POST /api/player/ingredient/consume`
- `POST /api/player/potion/consume`
- `POST /api/player/levelup`
- `GET /api/player/knowledge/{playerId}`

## Potion (`/api/potion`)
- `POST /api/potion/brew`

---

## 6) Notes / Gotchas

- Lexicon and Alchemy are separate services; authenticate against each service you call.
- Session cookies are per-origin/service; do not assume one login cookie covers both backends.
- For live stream state, always pass `channel` when you need deterministic behavior:
  - `?channel=music`
  - `?channel=video`
- If you expose new frontend origins, update CORS config and restart the affected backend.
