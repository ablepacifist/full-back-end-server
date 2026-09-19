# Lexicon Server API Documentation

**Version:** 2.4  
**Base URL (Frontend):** `https://alex-dyakin.com`  
**Base URL (Direct API):** `https://api.alex-dyakin.com` (production) or `http://localhost:36568` (local)  
**Last Updated:** September 19, 2026 (Full endpoint audit: app update/version, avatar proxy, events & polls, notifications, voice relay, health/info, live stream channels, and Alchemy Auth/Game/Player/Potion endpoints)

## Environment Info
- **Frontend:** Running on https://alex-dyakin.com via Cloudflare Tunnel (port 3001)
- **Lexicon API:** Port 36568 via https://api.alex-dyakin.com (Cloudflare Tunnel)
- **Alchemy API:** Port 8080 via https://alchemy.alex-dyakin.com (Cloudflare Tunnel)
- **Database:** HSQLDB 2.7.4 on port 9002
- **Host OS:** Windows 11 with WSL2 (ext4 USB HDD for media storage)
- **Authentication:** HTTP session-based with JSESSIONID cookie
- **CORS:** Configured for alex-dyakin.com, PlayIt origins, and localhost
- **Media Storage:** `\\wsl.localhost\Ubuntu\mnt\wsl\PHYSICALDRIVE1p2\lexicon-storage`

## Table of Contents
1. [Authentication & Security](#authentication--security)
2. [CORS Configuration](#cors-configuration)
3. [Authentication Endpoints](#authentication-endpoints)
4. [SSO Tokens (Lexicon -> Voice Bridge)](#sso-tokens-lexicon---voice-bridge)
5. [Player Management](#player-management)
6. [Media Management](#media-management)
7. [Chunked Upload (Large Files)](#chunked-upload-large-files)
8. [Async Download Queue](#async-download-queue)
9. [Playlist Management](#playlist-management)
10. [Playback Position Tracking](#playback-position-tracking)
11. [Live Stream](#live-stream)
12. [Media Streaming](#media-streaming)
13. [Chat Files (Rich Media Chat)](#chat-files-rich-media-chat)
14. [Text Messages](#text-messages)
15. [Push Notifications (Web Push)](#push-notifications-web-push)
16. [Notifications (In-App / Mumble Bridge)](#notifications-in-app--mumble-bridge)
17. [Events & Polls](#events--polls)
18. [Voice Relay (Lexi)](#voice-relay-lexi)
19. [Avatar Proxy (Mumble Bridge)](#avatar-proxy-mumble-bridge)
20. [App Version & Update](#app-version--update)
21. [Health & Info](#health--info)
22. [Data Models](#data-models)
23. [Holdfast Management (Alchemy API)](#holdfast-management-alchemy-api)
24. [Alchemy Authentication](#alchemy-authentication)
25. [Alchemy Player](#alchemy-player)
26. [Alchemy Potion Brewing](#alchemy-potion-brewing)
27. [Alchemy Game Lifecycle](#alchemy-game-lifecycle)

> **Note on section 11:** an earlier revision of this doc referenced a separate "Live Stream (Lightweight)" endpoint set. No such implementation exists in current source — `LiveStreamController` is the only live-stream controller. That TOC entry has been removed.

---

## Authentication & Security

### Session-Based Authentication
The Lexicon Server uses **HTTP session-based authentication**. Sessions are stored server-side and identified by a session cookie (`JSESSIONID`).

#### Key Points:
- **Session Cookie:** `JSESSIONID` (HttpOnly, Path=/api, SameSite=Lax)
- **Session Timeout:** 30 days of inactivity
- **Credentials Required:** Must include `credentials: 'include'` in fetch requests
- **CORS:** Proper CORS headers must be configured (see below)
- **Domain:** Works across https://alex-dyakin.com and PlayIt origins
- **Note:** Session cookies are NOT transferred between different domains - each microservice needs its own login

#### Authentication Flow:
1. Client sends POST to `/api/auth/login` with username/password
2. Server validates credentials and creates HTTP session
3. Server returns session cookie in `Set-Cookie` header
4. Client includes cookie in subsequent requests via `credentials: 'include'`
5. Server validates session on protected endpoints

#### Protected Endpoints:
- Use `/api/auth/me` to check if session is valid
- **Important:** `LexiconSecurityConfig` currently `permitAll()`s nearly every `/api/**` path at the Spring Security filter level — including `/api/players/**`, `/api/media/**`, `/api/playlists/**`, `/api/playback/**`, `/api/livestream/**`, `/api/stream/**`, `/api/download-queue/**`, `/api/messages/**`, `/api/chat/**`, `/api/push/**`, `/api/notifications/**`, `/api/events/**`, `/api/avatar/**`, and the auth entry points themselves. Only `/api/voice/**` and `/api/app/**` (version/update metadata, gated by a property that defaults to requiring auth) fall through to the catch-all `authenticated()` rule.
- In practice this means most endpoints do **not** return 401 for missing sessions at the framework level — any "auth" on them is whatever the controller/service manually checks (a session attribute, or nothing at all). Several endpoints trust a plain `userId` query/body parameter with **no verification that it matches the caller's session** (e.g. Playback Position, Messages, Push subscribe/send). Treat `userId` on those endpoints as client-asserted, not server-verified.
- Endpoints that do manually check for an active session: `GET /api/auth/me`, `POST /api/auth/sso/generate-token`, `GET /api/voice/status`, `POST /api/voice/turn`. These return `401 Unauthorized` on a missing/invalid session even though Spring Security itself would let the request through.

#### Authorization:
- **User-Based Permissions:** Some resources (playlists, media, messages) verify `userId` matches the resource's stored owner before update/delete and throw a `403`-mapped exception if not — but only for the specific mutation endpoints that implement that check (see each section below). Creation and most read endpoints do not verify ownership at all.
- **Public Access:** Public media/playlists are readable by anyone, authenticated or not (per the `permitAll()` posture above).
- **Known gap:** `GET /api/players`, `GET /api/players/{id}`, and `GET /api/players/username/{username}` (Lexicon) and `GET /api/player/{id}`, `GET /api/player/username/{username}`, `GET /api/player/all` (Alchemy) currently serialize the full `Player` object, which includes the password field — there is no `@JsonIgnore` on it. Do not expose these responses directly to untrusted clients without stripping `password` first.

---

## CORS Configuration

### Required Headers
The server is configured with the following CORS origins:

**Configured Origins (as of Feb 14, 2026):**
```
http://localhost:3000
http://localhost:3001
http://192.168.4.29:3001
http://192.168.4.29:8080
http://192.168.4.29:36568
https://alex-dyakin.com
https://*.alex-dyakin.com
http://147.185.221.24:*
https://147.185.221.24:*
http://*.playit.pub:*
https://*.playit.pub:*
```

**To Add New Origins:**
Update `LexiconSecurityConfig.java` in Lexicon server and rebuild:
```bash
cd lexiconServer && ./gradlew clean build -x test
```

### Important CORS Notes:
1. **Credentials:** All CORS requests support `Access-Control-Allow-Credentials: true`
2. **Exposed Headers:** Server exposes: `Content-Range`, `Accept-Ranges`, `Content-Length`, `Content-Type`, `Cache-Control`, `X-Accel-Buffering`
3. **SSE Endpoints:** SSE (Server-Sent Events) endpoints have explicit CORS configuration
4. **Wildcard Origins:** Controllers use `@CrossOrigin(origins = "*")` but actual filtering in `LexiconSecurityConfig.java`
5. **Session Cookies:** NOT shared across different microservices - each microservice gets its own session

### For Microservice Integration:
**Steps to integrate your microservice:**
1. Add your origin to `LexiconSecurityConfig.java` originPatterns list
2. Update the `/api/auth/login` call in your microservice to use PlayIt URL:
   ```
   http://147.185.221.24:15856/api/auth/login
   ```
3. Store the JSESSIONID cookie and include it in all subsequent requests
4. Use `credentials: 'include'` in all fetch requests
5. Rebuild and restart Lexicon server

---

## Authentication Endpoints

Base Path: `/api/auth`

### POST /api/auth/login
Authenticate user and create session.

**Request:**
```json
{
  "username": "string",
  "password": "string",
  "rememberMe": false,
  "platform": "mobile"
}
```
- `rememberMe` (boolean, optional): if `true`, also sets a long-lived `remember-me` cookie (HttpOnly, `Path=/`, 30-day) so `/api/auth/me` can silently re-establish a session without re-login.
- `platform` (string, optional): pass `"mobile"` to additionally receive a bearer-style `mobileToken` in the response, for clients that can't rely on cookies.

**Response (200):**
```json
{
  "success": true,
  "playerId": 1,
  "id": 1,
  "username": "john_doe",
  "displayName": "John Doe",
  "email": "john@example.com",
  "level": 5,
  "mobileToken": "opaque-token-here"
}
```
`mobileToken` is only present when `platform` was `"mobile"`.

**Errors:**
- `400 Bad Request`: Missing username/password. **Note:** unlike most other endpoints, this and the other `/api/auth/*` error responses are returned as a **plain text string**, not a JSON object (e.g. body is literally `Username and password required`).
- `401 Unauthorized`: Invalid credentials (plain text `Invalid username or password`)
- `500 Internal Server Error`: Server error (plain text)

**Sets Cookie:** `JSESSIONID` (30 day expiration); `remember-me` (30 day, only if `rememberMe: true`)

---

### POST /api/auth/register
Register a new user account.

**Request:**
```json
{
  "username": "string (required)",
  "password": "string (required)",
  "confirmPassword": "string (optional)",
  "email": "string (optional)",
  "displayName": "string (optional)"
}
```

**Response (200):**
```json
{
  "success": true,
  "playerId": 42,
  "username": "new_user",
  "message": "Registration successful"
}
```

**Errors:**
- `400 Bad Request`: Validation error (username exists, passwords don't match, etc.)
- `500 Internal Server Error`: Server error

**Notes:**
- Email defaults to `{username}@lexicon.local` if not provided
- Does NOT automatically log in - call `/login` separately

---

### GET /api/auth/me
Get current authenticated user from session.

**Request:** None (uses session cookie)

**Response (200):**
```json
{
  "id": 1,
  "username": "john_doe",
  "displayName": "John Doe",
  "email": "john@example.com",
  "level": 5
}
```

**Errors:**
- `401 Unauthorized`: No valid session and no valid `remember-me` cookie, or the remembered user no longer exists (empty body)

**Use Case:** Check if user is logged in, get user details

**Notes:**
- If there is no active session but a valid `remember-me` cookie is present, the server transparently re-establishes a session and **rotates** the remember-me cookie (issues a new token, invalidates the old one) before returning the user.

---

### POST /api/auth/logout
Invalidate current session.

**Request:** None (uses session cookie)

**Response (200):**
```json
{
  "success": true,
  "message": "Logged out successfully"
}
```

**Notes:**
- Also revokes the caller's `remember-me` token(s) and any issued `mobileToken`(s), and clears the `remember-me` cookie. Works even if there is no active session (a no-op in that case beyond clearing cookies).

---

## SSO Tokens (Lexicon -> Voice Bridge)

Base Path: `/api/auth/sso`

**Use Case:** Single sign-on handoff from Lexicon frontend to `https://voice.alex-dyakin.com`.
Tokens are short-lived (60 seconds) and single-use.

### POST /api/auth/sso/generate-token
Generate an SSO token for the currently authenticated session user.

**Auth Required:** Yes (valid `JSESSIONID` session)

**Request:** No body

**Response (200):**
```json
{
  "token": "base64url-token",
  "expiresInSeconds": 60
}
```

**Errors:**
- `401 Unauthorized`: No authenticated session

---

### POST /api/auth/sso/validate-token
Validate and consume an SSO token. This endpoint is intended for bridge service server-to-server validation.

**Request:**
```json
{
  "token": "base64url-token"
}
```

**Response (200):**
```json
{
  "valid": true,
  "userId": 7,
  "username": "alex",
  "displayName": "Alex"
}
```

**Errors:**
- `400 Bad Request`: Missing token
- `401 Unauthorized`: Invalid, expired, or already-used token

**Notes:**
- Token is deleted after validation attempt (single-use)
- Expiration is 60 seconds from generation

---

## Player Management

Base Path: `/api/players`

**Note:** This controller predates `/api/auth/*` and duplicates its login/register functionality with different response shapes and, notably, `/api/players/login` does **not** create a session or set `JSESSIONID` — it just validates credentials and returns the player. Prefer `/api/auth/login` and `/api/auth/register` for anything that needs a real session; `/api/players/register` and `/api/players/login` remain available for backward compatibility.

### GET /api/players
Get all players.

**Response (200):**
```json
[
  {
    "id": 1,
    "username": "john_doe",
    "displayName": "John Doe",
    "email": "john@example.com",
    "level": 5,
    "registrationDate": "2026-01-15T10:30:00",
    "lastLoginDate": "2026-02-14T08:00:00"
  }
]
```

---

### GET /api/players/{id}
Get player by ID.

**Path Parameters:**
- `id` (integer): Player ID

**Response (200):**
```json
{
  "id": 1,
  "username": "john_doe",
  "displayName": "John Doe",
  "email": "john@example.com",
  "level": 5,
  "registrationDate": "2026-01-15T10:30:00",
  "lastLoginDate": "2026-02-14T08:00:00"
}
```

**Errors:**
- `404 Not Found`: Player doesn't exist

---

### GET /api/players/username/{username}
Get player by username.

**Path Parameters:**
- `username` (string): Player username

**Response:** Same as GET by ID

---

### POST /api/players/register
Register a new player (duplicate of `/api/auth/register`, different response shape; does not create a session).

**Request Body:**
```json
{
  "username": "string (required)",
  "password": "string (required)",
  "email": "string (optional)",
  "displayName": "string (optional)"
}
```

**Response (201 Created):**
```json
{
  "success": true,
  "message": "Player registered successfully",
  "playerId": 42,
  "username": "new_user"
}
```

**Errors:**
- `400 Bad Request`: `{ "error": "message" }` — missing fields or duplicate username
- `500 Internal Server Error`: `{ "error": "message" }`

---

### POST /api/players/login
Validate credentials and return the player (duplicate of `/api/auth/login`; does **not** create a session or set `JSESSIONID`).

**Request Body:**
```json
{
  "username": "string",
  "password": "string"
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Login successful",
  "player": {
    "id": 1,
    "username": "john_doe",
    "displayName": "John Doe",
    "email": "john@example.com",
    "level": 5
  }
}
```

**Errors:**
- `400 Bad Request`: `{ "error": "Invalid username or password" }` — note this endpoint uses `400`, not `401`, for bad credentials

---

### PUT /api/players/{id}
Update player fields.

**Path Parameters:**
- `id` (integer): Player ID

**Request Body:** `{ "field": "value", ... }` (arbitrary map)

**⚠️ Not implemented:** This endpoint currently performs no update regardless of the request body. It only checks that the player exists and always returns:
```json
{
  "message": "Update functionality requires database method implementation",
  "playerId": 1
}
```
**Errors:**
- `404 Not Found`: Player doesn't exist

---

### DELETE /api/players/{id}
Delete a player by ID. **No ownership or auth check** — any caller can delete any player.

**Path Parameters:**
- `id` (integer): Player ID

**Response (200):**
```json
{
  "message": "Player deleted successfully",
  "playerId": 1
}
```

**Errors:**
- `404 Not Found`: `{ "error": "Player not found" }`
- `500 Internal Server Error`: `{ "error": "message" }`

---

## Media Management

Base Path: `/api/media`

### POST /api/media/upload
Upload a media file (direct upload, max ~100MB).

**Request (multipart/form-data):**
- `file` (file, required): Media file
- `userId` (integer, required): Uploader user ID
- `title` (string, required): Media title
- `description` (string, optional): Description
- `isPublic` (boolean, default: false): Public visibility
- `mediaType` (string, default: "OTHER"): MUSIC, VIDEO, AUDIOBOOK, OTHER

**Response (200):**
```json
{
  "success": true,
  "message": "File uploaded successfully",
  "mediaFile": {
    "id": 123,
    "filename": "song.mp3",
    "originalFilename": "song.mp3",
    "contentType": "audio/mpeg",
    "fileSize": 5242880,
    "filePath": "music/20260214_103045_abc123_song.mp3",
    "uploadedBy": 1,
    "uploadDate": "2026-02-14T10:30:45",
    "title": "My Song",
    "description": "A great song",
    "mediaType": "MUSIC",
    "isPublic": true
  }
}
```

**Errors:**
- `400 Bad Request`: Invalid file or parameters
- `500 Internal Server Error`: Upload failed

**Note:** For files >100MB, use Chunked Upload instead.

---

### POST /api/media/upload-from-url
Download media from URL using yt-dlp (YouTube, SoundCloud, etc.).

**Request Parameters:**
- `url` (string, required): Media URL
- `userId` (integer, required): User ID
- `title` (string, required): Media title
- `description` (string, optional): Description
- `isPublic` (boolean, default: false): Public visibility
- `mediaType` (string, default: "OTHER"): Media type
- `downloadType` (string, default: "AUDIO_ONLY"): AUDIO_ONLY, VIDEO, BEST_QUALITY

**Response (200):**
```json
{
  "success": true,
  "message": "Media downloaded and uploaded successfully",
  "mediaFile": { /* MediaFile object */ }
}
```

**Errors:**
- `400 Bad Request`: Invalid URL or parameters
- `500 Internal Server Error`: Download/upload failed

**Note:** This is synchronous and blocks until the yt-dlp download finishes — for long media, prefer the async `/api/download-queue/start`, which wraps the identical download logic but returns a job ID immediately.

---

### GET /api/media/{id}
Get media file metadata by ID.

**Path Parameters:**
- `id` (integer): Media file ID

**Response (200):**
```json
{
  "id": 123,
  "filename": "song.mp3",
  "originalFilename": "song.mp3",
  "contentType": "audio/mpeg",
  "fileSize": 5242880,
  "filePath": "music/20260214_103045_abc123_song.mp3",
  "uploadedBy": 1,
  "uploadDate": "2026-02-14T10:30:45",
  "title": "My Song",
  "description": "A great song",
  "mediaType": "MUSIC",
  "sourceUrl": "https://youtube.com/watch?v=...",
  "isPublic": true
}
```

**Errors:**
- `404 Not Found`: Media file doesn't exist

---

### GET /api/media/user/{userId}
Get all media files by user.

**Path Parameters:**
- `userId` (integer): User ID

**Response (200):**
```json
[ /* Array of MediaFile objects */ ]
```

---

### GET /api/media/public
Get all public media files.

**Response (200):**
```json
[ /* Array of public MediaFile objects */ ]
```

---

### GET /api/media/search?q=searchTerm
Search media files by title or description.

**Query Parameters:**
- `q` (string, required): Search term

**Response (200):**
```json
[ /* Array of matching MediaFile objects */ ]
```

---

### GET /api/media/recent?limit=10
Get recent media files.

**Query Parameters:**
- `limit` (integer, default: 10): Number of results

**Response (200):**
```json
[ /* Array of recent MediaFile objects */ ]
```

---

### PUT /api/media/{id}?userId={userId}
Update media file metadata.

**Path Parameters:**
- `id` (integer): Media file ID

**Query Parameters:**
- `userId` (integer): User ID (must match owner)

**Request Body:**
```json
{
  "title": "Updated Title",
  "description": "Updated description",
  "isPublic": true,
  "mediaType": "MUSIC"
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Media file updated successfully"
}
```

**Errors:**
- `403 Forbidden`: User doesn't own media file
- `404 Not Found`: Media file doesn't exist

---

### DELETE /api/media/{id}?userId={userId}
Delete media file.

**Path Parameters:**
- `id` (integer): Media file ID

**Query Parameters:**
- `userId` (integer): User ID (must match owner)

**Response (200):**
```json
{
  "success": true,
  "message": "Media file deleted successfully"
}
```

**Errors:**
- `403 Forbidden`: User doesn't own media file
- `404 Not Found`: Media file doesn't exist

---

### GET /api/media/{id}/access?userId={userId}
Check if user has access to media file.

**Path Parameters:**
- `id` (integer): Media file ID

**Query Parameters:**
- `userId` (integer): User ID

**Response (200):**
```json
{
  "hasAccess": true
}
```

---

### GET /api/media/{id}/download
Download media file (full file).

**Path Parameters:**
- `id` (integer): Media file ID

**Response (200):**
- Binary file data
- Headers: `Content-Type`, `Content-Disposition: attachment`

**Errors:**
- `404 Not Found`: Media file doesn't exist
- `204 No Content`: File data not available

---

### GET /api/media/stream/{id}
Stream media file with HTTP Range support (for video/audio playback).

**Path Parameters:**
- `id` (integer): Media file ID

**Request Headers:**
- `Range` (optional): e.g., `bytes=0-1023` for seeking

**Response (200 or 206):**
- Binary file data
- Status: `200 OK` (full file) or `206 Partial Content` (range request)
- Headers: `Content-Range`, `Accept-Ranges: bytes`, `Content-Length`

**Use Case:** Video player seeking, audio streaming

---

### GET /api/media/storage-info
Get disk usage/capacity info for the configured storage drive(s). Operational/ops endpoint — not part of the media CRUD flow, and has no auth check.

**Response (200):** Shape returned by `OptimizedFileStorageService.getStorageInfo()` (drive capacity/usage details).

**Errors:**
- `500 Internal Server Error`: Plain text error message

---

## Chunked Upload (Large Files)

Base Path: `/api/media/chunked`

**Use Case:** Upload files >100MB by splitting into chunks (typically 10MB each).

### POST /api/media/chunked/init
Initialize a chunked upload session.

**Request Parameters:**
- `filename` (string): Original filename
- `contentType` (string): MIME type
- `totalSize` (long): Total file size in bytes
- `chunkSize` (integer): Chunk size in bytes (e.g., 10485760)
- `userId` (integer): User ID
- `title` (string): Media title
- `description` (string, optional): Description
- `isPublic` (boolean, default: false): Public visibility
- `mediaType` (string, default: "OTHER"): Media type
- `checksum` (string, optional): File checksum for verification

**Response (200):**
```json
{
  "success": true,
  "uploadId": "uuid-here",
  "totalChunks": 150,
  "chunkSize": 10485760,
  "message": "Chunked upload session initialized"
}
```

**Notes:**
- Store the `uploadId` for subsequent chunk uploads
- `totalChunks = ceil(totalSize / chunkSize)`

---

### POST /api/media/chunked/upload/{uploadId}
Upload a single chunk.

**Path Parameters:**
- `uploadId` (string): Upload session ID from init

**Request (multipart/form-data):**
- `chunkNumber` (integer): Chunk number (0-indexed)
- `chunk` (file): Chunk binary data
- `checksum` (string, optional): Chunk checksum (SHA-256 hex)

**Response (200):**
```json
{
  "success": true,
  "progress": 66.67,
  "uploadedChunks": 100,
  "totalChunks": 150,
  "isComplete": false,
  "message": "Chunk uploaded successfully"
}
```

**When All Chunks Uploaded:**
```json
{
  "success": true,
  "progress": 100.0,
  "uploadedChunks": 150,
  "totalChunks": 150,
  "isComplete": true,
  "assembling": true,
  "message": "All chunks uploaded, starting assembly..."
}
```

**Errors:**
- `400 Bad Request`: Invalid chunk or upload session
- `500 Internal Server Error`: Upload failed

---

### GET /api/media/chunked/status/{uploadId}
Get upload status and progress.

**Path Parameters:**
- `uploadId` (string): Upload session ID

**Response (200):**
```json
{
  "success": true,
  "uploadId": "uuid-here",
  "filename": "large-video.mp4",
  "totalSize": 1500000000,
  "totalChunks": 150,
  "uploadedChunks": 75,
  "progress": 50.0,
  "status": "UPLOADING",
  "isComplete": false,
  "lastActivity": "2026-02-14T10:45:30"
}
```

**Status Values:**
- `UPLOADING`: Chunks being uploaded
- `ASSEMBLING`: All chunks uploaded, file being assembled
- `COMPLETED`: Assembly complete, media file created
- `CANCELLED`: Upload cancelled

---

### GET /api/media/chunked/missing/{uploadId}
Get list of missing chunks (for resume functionality).

**Path Parameters:**
- `uploadId` (string): Upload session ID

**Response (200):**
```json
{
  "success": true,
  "uploadId": "uuid-here",
  "missingChunks": [10, 15, 23],
  "missingCount": 3,
  "totalChunks": 150
}
```

---

### POST /api/media/chunked/finalize/{uploadId}
Finalize upload and create MediaFile.

**Path Parameters:**
- `uploadId` (string): Upload session ID

**Response (200):**
```json
{
  "success": true,
  "message": "Large file uploaded successfully",
  "mediaFile": { /* MediaFile object */ }
}
```

**Response (200, still assembling):**
```json
{
  "success": false,
  "status": "assembling",
  "message": "File is still being assembled, please retry finalize shortly"
}
```

**Errors:**
- `400 Bad Request`: Upload not complete or already finalized
- `500 Internal Server Error`: Finalization failed

**Notes:**
- This is called automatically when all chunks are uploaded
- Finalize may return `status=assembling` while background assembly continues
- Clients should poll finalize every few seconds until `success=true`
- Server-side wait is bounded to avoid proxy timeouts
- Creates the final MediaFile in database

---

### DELETE /api/media/chunked/{uploadId}
Cancel an upload session.

**Path Parameters:**
- `uploadId` (string): Upload session ID

**Response (200):**
```json
{
  "success": true,
  "message": "Upload cancelled successfully"
}
```

---

### GET /api/media/chunked/progress/{uploadId}
Get real-time progress via Server-Sent Events (SSE).

**Path Parameters:**
- `uploadId` (string): Upload session ID

**Response:** SSE stream

**Event Types:**
- `progress`: Upload progress updates
- `complete`: Upload completed
- `error`: Upload error

**Example Event:**
```
event: progress
data: {"uploadId": "uuid", "progress": 45.5, "uploadedChunks": 68, "totalChunks": 150, "status": "UPLOADING"}
```

---

## Async Download Queue

Base Path: `/api/download-queue`

**Use Case:** Download media from URLs asynchronously (queue-based).

### POST /api/download-queue/start
Queue a new download job (returns immediately).

**Request Parameters:**
- `url` (string): Media URL
- `userId` (integer): User ID
- `title` (string): Media title
- `description` (string, optional): Description
- `isPublic` (boolean, default: false): Public visibility
- `mediaType` (string, default: "OTHER"): Media type
- `downloadType` (string, default: "AUDIO_ONLY"): Download type

**Response (200):**
```json
{
  "success": true,
  "jobId": "job-uuid-here",
  "message": "Download queued successfully. Check status with /api/download-queue/status/job-uuid-here",
  "statusUrl": "/api/download-queue/status/job-uuid-here"
}
```

**Notes:**
- Returns immediately with job ID
- Download happens in background
- Poll `/status/{jobId}` to check progress

---

### GET /api/download-queue/status/{jobId}
Check status of a download job.

**Path Parameters:**
- `jobId` (string): Job ID from start response

**Response (200):**
```json
{
  "success": true,
  "jobId": "job-uuid-here",
  "url": "https://youtube.com/watch?v=...",
  "title": "My Video",
  "status": "PROCESSING",
  "queuedAt": "2026-02-14T10:00:00",
  "startedAt": "2026-02-14T10:01:00",
  "completedAt": null,
  "progress": {
    "percentage": 45.5,
    "message": "Downloading...",
    "status": "DOWNLOADING"
  }
}
```

**Status Values:**
- `QUEUED`: Waiting in queue
- `PROCESSING`: Download in progress
- `COMPLETED`: Download complete, media file created
- `FAILED`: Download failed

**When Completed:**
```json
{
  "success": true,
  "jobId": "job-uuid",
  "status": "COMPLETED",
  "completedAt": "2026-02-14T10:05:00",
  "mediaFileId": 456
}
```

**When Failed:**
```json
{
  "success": true,
  "jobId": "job-uuid",
  "status": "FAILED",
  "error": "Download failed: Invalid URL"
}
```

**Errors:**
- `404 Not Found`: Job doesn't exist

---

### GET /api/download-queue/active/{userId}
Get all active downloads for a user.

**Path Parameters:**
- `userId` (integer): User ID

**Response (200):**
```json
{
  "success": true,
  "count": 2,
  "jobs": {
    "job-uuid-1": {
      "url": "https://youtube.com/watch?v=...",
      "title": "Video 1",
      "status": "PROCESSING",
      "queuedAt": "2026-02-14T10:00:00"
    },
    "job-uuid-2": {
      "url": "https://youtube.com/watch?v=...",
      "title": "Video 2",
      "status": "QUEUED",
      "queuedAt": "2026-02-14T10:05:00"
    }
  }
}
```

---

### DELETE /api/download-queue/{jobId}
Cancel a download job.

**Path Parameters:**
- `jobId` (string): Job ID

**Response (200):**
```json
{
  "success": true,
  "message": "Download cancelled"
}
```

**Notes:**
- Can only cancel jobs that haven't started or are still queued
- Jobs in progress cannot be cancelled

---

## Playlist Management

Base Path: `/api/playlists`

### POST /api/playlists?userId={userId}
Create a new playlist.

**Query Parameters:**
- `userId` (integer, required): Creator user ID

**Request Body:**
```json
{
  "name": "My Playlist",
  "description": "A great playlist",
  "isPublic": true,
  "mediaFileIds": [1, 2, 3, 4]
}
```

**Response (200):**
```json
{
  "id": 10,
  "name": "My Playlist",
  "description": "A great playlist",
  "isPublic": true,
  "createdBy": 1,
  "createdDate": "2026-02-14T10:00:00",
  "itemCount": 4,
  "mediaFileIds": [1, 2, 3, 4]
}
```

**Errors:**
- `400 Bad Request`: Invalid playlist data
- `401 Unauthorized`: User ID required
- `500 Internal Server Error`: Creation failed

---

### GET /api/playlists?userId={userId}
Get playlists by user or get public playlists.

**Query Parameters:**
- `userId` (integer, optional): If provided, gets user's playlists. If omitted, gets public playlists.

**Response (200):**
```json
[ /* Array of Playlist objects */ ]
```

---

### GET /api/playlists/user/{userId}
Get playlists created by a specific user.

**Path Parameters:**
- `userId` (integer): User ID

**Response (200):**
```json
[ /* Array of Playlist objects */ ]
```

---

### GET /api/playlists/public
Get all public playlists.

**Response (200):**
```json
[ /* Array of public Playlist objects */ ]
```

---

### GET /api/playlists/{id}
Get a specific playlist with all items.

**Path Parameters:**
- `id` (integer): Playlist ID

**Response (200):**
```json
{
  "id": 10,
  "name": "My Playlist",
  "description": "A great playlist",
  "isPublic": true,
  "createdBy": 1,
  "createdDate": "2026-02-14T10:00:00",
  "itemCount": 4,
  "items": [
    {
      "id": 1,
      "title": "Song 1",
      "mediaType": "MUSIC",
      /* ... full MediaFile object ... */
    },
    {
      "id": 2,
      "title": "Song 2",
      "mediaType": "MUSIC",
      /* ... */
    }
  ]
}
```

**Errors:**
- `404 Not Found`: Playlist doesn't exist

---

### PUT /api/playlists/{id}?userId={userId}
Update playlist metadata.

**Path Parameters:**
- `id` (integer): Playlist ID

**Query Parameters:**
- `userId` (integer): User ID (must match owner)

**Request Body:**
```json
{
  "name": "Updated Name",
  "description": "Updated description",
  "isPublic": false
}
```

**Response (200):**
```json
{ /* Updated Playlist object */ }
```

**Errors:**
- `403 Forbidden`: User doesn't own playlist
- `404 Not Found`: Playlist doesn't exist

---

### DELETE /api/playlists/{id}?userId={userId}&deleteMediaFiles={boolean}
Delete a playlist.

**Path Parameters:**
- `id` (integer): Playlist ID

**Query Parameters:**
- `userId` (integer): User ID (must match owner)
- `deleteMediaFiles` (boolean, default: false): Also delete media files

**Response (200):**
```json
"Playlist deleted successfully"
```

**Errors:**
- `403 Forbidden`: User doesn't own playlist
- `404 Not Found`: Playlist doesn't exist

---

### POST /api/playlists/{id}/items?userId={userId}
Add a media file to playlist.

**Path Parameters:**
- `id` (integer): Playlist ID

**Query Parameters:**
- `userId` (integer): User ID (must match owner)

**Request Body:**
```json
{
  "mediaFileId": 123
}
```

**Response (200):**
```json
"Item added to playlist"
```

**Errors:**
- `403 Forbidden`: User doesn't own playlist
- `404 Not Found`: Playlist or media file doesn't exist

---

### DELETE /api/playlists/{id}/items/{mediaId}?userId={userId}
Remove a media file from playlist.

**Path Parameters:**
- `id` (integer): Playlist ID
- `mediaId` (integer): Media file ID

**Query Parameters:**
- `userId` (integer): User ID (must match owner)

**Response (200):**
```json
"Item removed from playlist"
```

---

### PUT /api/playlists/{id}/reorder?userId={userId}
Reorder playlist items.

**Path Parameters:**
- `id` (integer): Playlist ID

**Query Parameters:**
- `userId` (integer): User ID (must match owner)

**Request Body:**
```json
{
  "mediaFileIds": [3, 1, 4, 2]
}
```

**Response (200):**
```json
"Playlist reordered"
```

---

### POST /api/playlists/import-youtube
Import a YouTube playlist.

**Request Parameters:**
- `url` (string): YouTube playlist URL
- `userId` (integer): User ID
- `playlistName` (string, optional): Playlist name (defaults to YouTube playlist name)
- `isPublic` (boolean, default: true): Playlist visibility
- `mediaIsPublic` (boolean, default: false): Media files visibility
- `mediaType` (string, default: "MUSIC"): Media type for all items
- `downloadType` (string, default: "AUDIO_ONLY"): Download type

**Response (200):**
```json
{
  "status": "processing",
  "message": "Playlist import started",
  "importId": "import_1708000000000_1"
}
```

**Notes:**
- Returns immediately with import ID
- Use SSE endpoint to track progress
- Downloads all videos/songs in background

---

### GET /api/playlists/import-progress/{importId}
Get real-time import progress via SSE.

**Path Parameters:**
- `importId` (string): Import ID from import-youtube response

**Response:** SSE stream

**Event Types:**
- `connected`: Connection established
- `progress`: Import progress updates
- `completed`: Import completed
- `error`: Import error

**Example Events:**
```
event: connected
data: {"type":"connected","message":"Connected to progress stream","importId":"import_123"}

event: progress
data: {"type":"progress","message":"Downloading track 5/10","total":10,"successful":4,"failed":0,"processed":5,"percentage":50}

event: completed
data: {"type":"completed","playlistId":42,"totalTracks":10,"successfulTracks":9,"failedTracks":1,"message":"Import completed: 9/10 tracks successful"}
```

---

## Playback Position Tracking

Base Path: `/api/playback`

**Use Case:** Remember playback position for resuming media.

### POST /api/playback/position
Save or update playback position.

**Request Body:**
```json
{
  "userId": 1,
  "mediaFileId": 123,
  "position": 125.5,
  "duration": 300.0,
  "completed": false
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Playback position saved"
}
```

---

### GET /api/playback/position/{userId}/{mediaFileId}
Get playback position for a specific media file.

**Path Parameters:**
- `userId` (integer): User ID
- `mediaFileId` (integer): Media file ID

**Response (200):**
```json
{
  "found": true,
  "position": 125.5,
  "duration": 300.0,
  "completed": false,
  "progressPercentage": 41.83,
  "lastUpdated": "2026-02-14T10:30:00"
}
```

**When No Position Saved:**
```json
{
  "found": false
}
```

---

### GET /api/playback/user/{userId}
Get all playback positions for a user.

**Path Parameters:**
- `userId` (integer): User ID

**Response (200):**
```json
[
  {
    "userId": 1,
    "mediaFileId": 123,
    "position": 125.5,
    "duration": 300.0,
    "completed": false,
    "progressPercentage": 41.83,
    "lastUpdated": "2026-02-14T10:30:00"
  },
  /* ... */
]
```

---

### DELETE /api/playback/position/{userId}/{mediaFileId}
Delete playback position.

**Path Parameters:**
- `userId` (integer): User ID
- `mediaFileId` (integer): Media file ID

**Response (200):**
```json
{
  "success": true,
  "message": "Playback position deleted"
}
```

---

## Live Stream

Base Path: `/api/livestream`

**Use Case:** Synchronized video/music stream for all users.

**Channels:** Every endpoint below accepts an optional `?channel=video|music` query parameter (default: `video`). The server runs two independent live-stream states/queues in parallel — one per channel — so `state`, `queue`, and SSE events are all channel-scoped. Pass the same `channel` consistently across state/queue/SSE calls for a given player UI.

### GET /api/livestream/state?channel={channel}
Get current live stream state.

**Query Parameters:**
- `channel` (string, optional, default: `video`): `video` or `music`

**Response (200):**
```json
{
  "success": true,
  "state": {
    "id": 1,
    "currentMediaId": 123,
    "currentMedia": { /* MediaFile object */ },
    "currentStartTime": "2026-02-14T10:00:00",
    "currentPositionMs": 0,
    "totalSkipVotes": 0,
    "requiredSkipVotes": 1,
    "queuedItems": []
  }
}
```

---

### GET /api/livestream/queue?channel={channel}
Get current queue.

**Query Parameters:**
- `channel` (string, optional, default: `video`): `video` or `music`

**Response (200):**
```json
{
  "success": true,
  "queue": [
    {
      "id": 1,
      "mediaFileId": 124,
      "mediaFile": { /* MediaFile object */ },
      "queuedBy": 1,
      "queuedAt": "2026-02-14T10:05:00",
      "position": 1,
      "status": "QUEUED"
    }
  ],
  "count": 1
}
```

**Status Values:**
- `QUEUED`: Waiting in queue
- `PLAYING`: Currently playing
- `COMPLETED`: Already played

---

### GET /api/livestream/eligible-media?channel={channel}
Get all media eligible for livestream queue.

**Query Parameters:**
- `channel` (string, optional, default: `video`): `video` or `music`

**Response (200):**
```json
{
  "success": true,
  "media": [ /* Array of MediaFile objects */ ],
  "count": 150
}
```

**Notes:**
- Includes public media + private media in public playlists

---

### POST /api/livestream/queue?channel={channel}
Add media to queue.

**Query Parameters:**
- `channel` (string, optional, default: `video`): `video` or `music`

**Request Body:**
```json
{
  "userId": 1,
  "mediaFileId": 123
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Added to queue",
  "queueItem": { /* LiveStreamQueue object */ }
}
```

**Errors:**
- `400 Bad Request`: Missing `userId`/`mediaFileId`, or invalid media

---

### POST /api/livestream/queue/playlist?channel={channel}
Add every media item in a playlist to the queue in one call.

**Query Parameters:**
- `channel` (string, optional, default: `video`): `video` or `music`

**Request Body:**
```json
{
  "userId": 1,
  "playlistId": 10
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Playlist added to queue",
  "addedCount": 12
}
```

**Errors:**
- `400 Bad Request`: Missing `userId`/`playlistId`, or invalid playlist
- `403 Forbidden`: Playlist is private and not owned by `userId`

---

### DELETE /api/livestream/queue/{queueId}?userId={userId}&channel={channel}
Remove item from queue.

**Path Parameters:**
- `queueId` (integer): Queue item ID

**Query Parameters:**
- `userId` (integer): User ID (must match queuer)
- `channel` (string, optional, default: `video`): `video` or `music`

**Response (200):**
```json
{
  "success": true,
  "message": "Removed from queue"
}
```

**Errors:**
- `500 Internal Server Error`: Covers not-found/not-owner cases too — this endpoint does not return a distinct `404`/`403`

---

### POST /api/livestream/skip?channel={channel}
Vote to skip current media.

**Query Parameters:**
- `channel` (string, optional, default: `video`): `video` or `music`

**Request Body:**
```json
{
  "userId": 1
}
```

**Response (200):**
```json
{
  "success": true,
  "skipped": true,
  "message": "Media skipped"
}
```

**Notes:**
- If `requiredSkipVotes` reached, media is skipped immediately
- Otherwise, vote is recorded

---

### GET <mark>/api/livestream/updates?channel={channel}</mark>
**Server-Sent Events (SSE)** endpoint for real-time updates.

**Query Parameters:**
- `channel` (string, optional, default: `video`): `video` or `music`

**Response:** SSE stream

**Event Types:**
- `heartbeat`: Connection established
- `init`: Initial state + queue
- `state-update`: Stream state changed (media changed, etc.)
- `queue-update`: Queue changed (item added/removed)

**Example Events:**
```
event: heartbeat
data: "connected"

event: init
data: {"type":"init","channel":"video","state":{...},"queue":[...(up to 6 items, centered on the currently playing item)...],"queueSize":5,"timestamp":1708000000000}

event: state-update
data: {"type":"state-update","data":{...}}

event: queue-update
data: {"type":"queue-update","data":{"items":[...],"totalCount":6}}
```

**Connection Details:**
- Timeout: 30 minutes
- Reconnect on disconnect
- Sends minimal payload on init for fast connection

---

### POST /api/livestream/media-ended?channel={channel}
Report that current media has ended (called by frontend).

**Query Parameters:**
- `channel` (string, optional, default: `video`): `video` or `music`

**Response (200):**
```json
{
  "success": true,
  "message": "Advanced to next media",
  "timeMs": 45
}
```
`timeMs` is server-side timing instrumentation for the advance operation, not media playback time.

**Notes:**
- Automatically advances to next media in queue
- If queue empty, plays random media

---

### POST /api/livestream/advance?channel={channel}
Manually advance to next media (admin/testing). Functionally similar to `/media-ended` but intended as a manual trigger rather than an end-of-playback report.

**Query Parameters:**
- `channel` (string, optional, default: `video`): `video` or `music`

**Response (200):**
```json
{
  "success": true,
  "message": "Advanced to next media"
}
```

---

## Media Streaming

Base Path: `/api/stream`

**Use Case:** Enhanced streaming with HTTP Range support.

**Note:** This overlaps with `GET /api/media/stream/{id}` (see Media Management) — both implement HTTP range streaming for the same `MediaFile` resource. This controller is the intended canonical path for files stored on disk (it 302-redirects to `/api/media/stream/{id}` for files that only exist in the database, delegating to that controller's DB-read fallback).

### GET /api/stream/{mediaFileId}
Stream media file with range support.

**Path Parameters:**
- `mediaFileId` (integer): Media file ID

**Request Headers:**
- `Range` (optional): e.g., `bytes=0-1023` for seeking

**Response (200, 206, or 302):**
- `200 OK`: Full file (no `Range` header), with `Accept-Ranges: bytes`, `Content-Length`
- `206 Partial Content`: Range request satisfied, with `Content-Range`, `Content-Length`
- `302 Found`: Media has no on-disk `filePath` (DB-stored) — redirects to `GET /api/media/stream/{id}`
- `416 Range Not Satisfiable`: Requested range is out of bounds, with `Content-Range: bytes */{totalSize}`

**Errors:**
- `404 Not Found`: Media file doesn't exist
- `500 Internal Server Error`: I/O error while streaming

**Notes:**
- Automatically handles file system or database storage
- Supports video seeking via range requests
- Better performance than `/api/media/stream/{id}` for large on-disk files

---

### GET /api/stream/{mediaFileId}/info
Get stream metadata for a media file without downloading its bytes (useful for a player to pre-check seekability/size).

**Path Parameters:**
- `mediaFileId` (integer): Media file ID

**Response (200):**
```json
{
  "id": 123,
  "title": "My Video",
  "contentType": "video/mp4",
  "fileSize": 52428800,
  "supportsRanges": true,
  "mediaType": "VIDEO"
}
```

**Errors:**
- `404 Not Found`: Media file doesn't exist
- `500 Internal Server Error`: Server error

---

## Chat Files (Rich Media Chat)

Base Path: `/api/chat`

**Use Case:** Upload and serve images/GIFs in chat channels. Used by the Mumble bridge for rich media chat messages.

### POST /api/chat/upload
Upload an image or GIF for use in chat messages.

**Content-Type:** `multipart/form-data`

**Form Fields:**
| Field | Type | Required | Description |
|---|---|---|---|
| file | File | Yes | Image/GIF file to upload |
| userId | integer | Yes | Lexicon user ID of uploader |
| channelId | integer | Yes | Mumble channel ID where file is shared |

**Constraints:**
- Max file size: **8 MB**
- Accepted MIME types: `image/jpeg`, `image/png`, `image/gif`, `image/webp`
- Thumbnails generated automatically (max 400px wide, JPEG)
- GIFs are served as-is (no static thumbnail conversion)

**Response (200):**
```json
{
  "id": 12345,
  "url": "/api/chat/files/12345",
  "thumbnailUrl": "/api/chat/files/12345/thumb",
  "originalFilename": "screenshot.png",
  "mimeType": "image/png",
  "width": 1920,
  "height": 1080,
  "fileSize": 245760,
  "uploadedBy": 7,
  "createdAt": "2026-04-03T12:00:00"
}
```

**Error Responses:**
- `400`: File too large, unsupported type, or missing fields
- `500`: Storage or processing failure

---

### GET /api/chat/files/{fileId}
Serve the original uploaded file.

**Path Parameters:**
- `fileId` (long): Chat file ID from upload response

**Response (200):**
- Binary file data with correct `Content-Type` header
- `Cache-Control: public, max-age=31536000` (immutable files)

**Error Responses:**
- `404`: File not found

---

### GET /api/chat/files/{fileId}/thumb
Serve the thumbnail version of an uploaded file.

**Path Parameters:**
- `fileId` (long): Chat file ID from upload response

**Response (200):**
- Thumbnail image (JPEG, max 400px wide)
- Falls back to original file if no thumbnail was generated (e.g., small images, GIFs)
- `Cache-Control: public, max-age=31536000`

**Error Responses:**
- `404`: File not found

---

## Text Messages

Base Path: `/api/messages`

**Use Case:** Store and retrieve text messages for Mumble bridge chat integration. Supports rich media messages with image/GIF attachments.

### POST /api/messages
Store a new text message.

**Request Body:**
```json
{
  "channelId": 1,
  "channelName": "general",
  "userId": 7,
  "username": "alex",
  "content": "Check this out!",
  "messageType": "IMAGE",
  "mediaFileId": 12345
}
```

**Message Types:**
| Type | Description |
|---|---|
| `TEXT` | Plain text message (default) |
| `IMAGE` | Message with uploaded image attachment |
| `GIF` | Message with uploaded GIF attachment |
| `MIXED` | Text message with one or more attachments |
| `MEDIA_SHARE` | Shared media library item |
| `SYSTEM` | System notification |
| `BOT_COMMAND` | Bot command message |

**Response (200):**
```json
{
  "success": true,
  "messageId": 501
}
```

---

### GET /api/messages/channel/{channelId}
Get message history for a channel with pagination.

**Path Parameters:**
- `channelId` (integer): Channel ID

**Query Parameters:**
| Parameter | Type | Default | Description |
|---|---|---|---|
| limit | integer | 50 | Max messages to return (1-200) |
| before | string | null | ISO 8601 timestamp for pagination |

**Response (200):**
```json
[
  {
    "id": 501,
    "channelId": 1,
    "channelName": "general",
    "userId": 7,
    "username": "alex",
    "content": "Check this out!",
    "messageType": "IMAGE",
    "mediaFileId": 12345,
    "attachment": {
      "id": 12345,
      "url": "/api/chat/files/12345",
      "thumbnailUrl": "/api/chat/files/12345/thumb",
      "originalFilename": "screenshot.png",
      "mimeType": "image/png",
      "width": 1920,
      "height": 1080,
      "fileSize": 245760
    },
    "isPinned": false,
    "createdAt": "2026-04-03T12:00:00",
    "editedAt": null,
    "deletedAt": null
  }
]
```

**Notes:**
- Messages with `messageType` of `IMAGE`, `GIF`, or `MIXED` include an `attachment` object with file metadata and serving URLs
- `attachment` is `null` for plain `TEXT` messages
- Messages are returned in reverse chronological order

---

### GET /api/messages/{id}
Get a single message by ID.

**Response (200):** Single message object (same shape as above)

---

### PUT /api/messages/{id}?userId={userId}
Edit a message (owner only).

**Query Parameters:**
- `userId` (integer): ID of the user attempting the edit

**Request Body:**
```json
{
  "content": "Updated message text"
}
```

**Response (200):**
```json
{
  "success": true
}
```

---

### DELETE /api/messages/{id}?userId={userId}
Soft-delete a message (owner only).

**Response (200):**
```json
{
  "success": true
}
```

---

### GET /api/messages/search?q={term}&channelId={channelId}
Search messages by content.

**Query Parameters:**
| Parameter | Type | Default | Description |
|---|---|---|---|
| q | string | required | Search term |
| channelId | integer | -1 | Filter by channel (-1 = all) |

**Response (200):** Array of matching message objects (with attachment data if applicable)

---

## Push Notifications (Web Push)

Base Path: `/api/push`

**Use Case:** Register browser push subscriptions and send encrypted push notifications to offline users.

**Security/Architecture Notes:**
- API layer (`PushNotificationController`) delegates to logic layer (`PushNotificationService`)
- Logic layer handles payload creation, VAPID auth, ECDH, and AES-128-GCM encryption
- Data layer persists subscriptions via `IPushSubscriptionDatabase`/`HSQLPushSubscriptionDatabase`
- Payloads are encrypted per RFC 8291 before delivery

### GET /api/push/vapid-key
Get VAPID public key used by browser clients when calling `PushManager.subscribe()`.

**Response (200):**
```json
{
  "publicKey": "BLOnJPlh4qyMxl1N2Yw2jmYUkmASl8FZ9HBE3EqZXOn6BcexT4fsOhWXx5cp_hWr3bwwoGRuWR9owjI68UP43Ec"
}
```

**Errors:**
- `503 Service Unavailable`: Push is not configured (missing VAPID keys)

---

### POST /api/push/subscribe
Register or update a device push subscription.

**Request Body:**
```json
{
  "userId": 7,
  "endpoint": "https://fcm.googleapis.com/fcm/send/abcdef...",
  "keys": {
    "p256dh": "base64url-key",
    "auth": "base64url-auth"
  },
  "userAgent": "Mozilla/5.0 ..."
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Push subscription registered"
}
```

---

### POST /api/push/unsubscribe
Remove a device push subscription.

**Request Body:**
```json
{
  "endpoint": "https://fcm.googleapis.com/fcm/send/abcdef..."
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Push subscription removed"
}
```

---

### POST /api/push/send
Send an encrypted push notification to one user.

**Request Body:**
```json
{
  "userId": 7,
  "title": "New message",
  "body": "You have a new DM",
  "url": "https://voice.alex-dyakin.com/dm/7",
  "data": { "channelId": 10 }
}
```

**Response (200):**
```json
{
  "success": true,
  "sent": 1
}
```

---

### POST /api/push/send-bulk
Send an encrypted push notification to multiple users.

**Request Body:**
```json
{
  "userIds": [7, 8, 9],
  "title": "Channel mention",
  "body": "You were mentioned",
  "url": "https://voice.alex-dyakin.com/channels/42"
}
```

**Response (200):**
```json
{
  "success": true,
  "sent": 2
}
```

**⚠️ No auth:** Neither `/send` nor `/send-bulk` verify the caller — any client that can reach the API can push an arbitrary title/body/url/data to any `userId`. These are intended to be called only by the Mumble bridge or other internal services; there is currently no server-side enforcement of that.

---

## Notifications (In-App / Mumble Bridge)

Base Path: `/api/notifications`

**Use Case:** In-app notification feed (bell icon) backing the [[notification-system-mumble-lexicon]] integration — the Mumble bridge machine calls `POST /api/notifications` to originate voice-chat events (messages, joins, @mentions), and Lexicon itself creates `music` notifications for "now playing" events internally. The frontend/Android app reads history via `GET` and gets live delivery via SSE. No endpoint in this controller requires a session — `userId` is always a plain, unauthenticated request parameter.

**Notification object:**
```typescript
{
  id: number;
  targetUserId: number | null; // null = broadcast to all eligible users
  type: "message" | "voice_join" | "mention" | "music";
  title: string;
  body: string;
  source: string; // default "mumble"
  fromUsername: string;
  fromUserId: number; // excluded from recipients (actor never notified of own action)
  channelId: number | null;
  link: string | null;
  createdAt: string; // ISO 8601
  deliverPush?: boolean; // request-only; false skips push fan-out; not persisted
}
```

**NotificationPrefs object:**
```typescript
{
  userId: number;
  enableMessage: boolean;   // default true
  enableVoiceJoin: boolean; // default true
  enableMention: boolean;   // default true
  enableMusic: boolean;     // default false
  enablePush: boolean;      // default true
  lastReadAt: string | null; // ISO 8601
}
```

### POST /api/notifications
Create a notification. Persists it, fans it out live over SSE to every eligible connected user, and asynchronously delivers OS/browser push to users who opted in — excluding the actor (`fromUserId`) and respecting each recipient's `NotificationPrefs`.

**Request:**
```json
{
  "targetUserId": null,
  "type": "message",
  "title": "New message in #general",
  "body": "hey everyone",
  "source": "mumble",
  "fromUsername": "alex",
  "fromUserId": 3,
  "channelId": 1,
  "link": "/lexicon-dashboard",
  "deliverPush": true
}
```
Omit/null `targetUserId` to broadcast to all eligible users; set it for a directed notification (e.g. a mention).

**Response (200):**
```json
{ "success": true, "id": 142 }
```

**Errors:**
- `400 Bad Request`: `{ "success": false, "message": "..." }`
- `500 Internal Server Error`: `{ "success": false, "message": "Failed to create notification: ..." }`

---

### GET /api/notifications?userId={userId}&limit={limit}&before={before}
List a user's notification history (targeted + broadcast), newest first.

**Query Parameters:**
- `userId` (integer, required)
- `limit` (integer, optional, default: 50; values ≤0 or >200 are clamped back to 50)
- `before` (long, optional): pagination cursor — returns notifications created before this notification ID

**Response (200):** Array of Notification objects (see above)

**Errors:**
- `500 Internal Server Error`: `{ "success": false, "message": "..." }`

---

### GET /api/notifications/unread-count?userId={userId}
Get a user's unread notification count.

**Response (200):**
```json
{ "count": 4 }
```

---

### POST /api/notifications/read-all?userId={userId}
Mark all of a user's notifications as read (advances their `lastReadAt` cursor).

**Response (200):**
```json
{ "success": true }
```

---

### GET /api/notifications/prefs?userId={userId}
Get a user's notification preferences (creates defaults on first access).

**Response (200):** NotificationPrefs object (see above)

---

### PUT /api/notifications/prefs?userId={userId}
Update a user's notification preferences.

**Request:** NotificationPrefs JSON body (the `userId` query param wins over any `userId` in the body):
```json
{
  "enableMessage": true,
  "enableVoiceJoin": false,
  "enableMention": true,
  "enableMusic": true,
  "enablePush": true
}
```

**Response (200):**
```json
{ "success": true }
```

---

### GET /api/notifications/stream?userId={userId}
**Server-Sent Events (SSE)** endpoint for live notification delivery to one user.

**Response:** SSE stream (connection held up to 30 minutes; server sends a `heartbeat` every 30s to keep proxies like Cloudflare from closing it)

**Example Events:**
```
event: heartbeat
data: "connected"

event: init
data: {"unreadCount": 4}

event: heartbeat
data: "ping"

event: notification
data: {"id":142,"targetUserId":null,"type":"message","title":"New message in #general","body":"hey everyone","source":"mumble","fromUsername":"alex","fromUserId":3,"channelId":1,"link":"/lexicon-dashboard","createdAt":"2026-09-19T10:00:00"}
```
A `notification` event fires only if the connected user is an eligible recipient (not the actor, notification type enabled in their prefs, and either broadcast or directly targeted at them).

---

## Events & Polls

Base Path: `/api/events`

**Use Case:** Lightweight event creation with attached polls (e.g. "Where should we eat for my birthday?") and anonymous voting. No endpoint requires a session — creation is "gated client-side" per the security config comment, and voter identity is a client-generated `voterKey` (e.g. a device ID), not a user account.

**Model shapes:**
```typescript
Event:      { id, title, description, eventDate /* ISO date */, createdByUserId, createdAt, pollCount }
Poll:       { id, eventId, question, allowAddOptions, displayOrder, createdAt }
PollOption: { id, pollId, text, addedByName, createdAt, voteCount, voters: string[], votedByMe }
```

### POST /api/events
Create a new event.

**Request:**
```json
{ "title": "My Birthday", "description": "Aug 7 party", "eventDate": "2026-08-07", "userId": 12 }
```
`title` required (non-blank); `description`, `eventDate`, `userId` optional.

**Response (200):** The created Event object.

**Errors:**
- `400 Bad Request`: `{ "success": false, "message": "Event title cannot be empty" }`
- `500 Internal Server Error`: `{ "success": false, "message": "Failed to create event: ..." }`

---

### GET /api/events
List all events, each annotated with its poll count.

**Response (200):** Array of Event objects.

---

### GET /api/events/{eventId}
Get one event plus all of its polls.

**Path Parameters:**
- `eventId` (long)

**Response (200):**
```json
{
  "event": { "id": 5, "title": "My Birthday", "description": "...", "eventDate": "2026-08-07", "createdByUserId": 12, "createdAt": "..." },
  "polls": [ { "id": 9, "eventId": 5, "question": "Where to eat?", "allowAddOptions": true, "displayOrder": 0, "createdAt": "..." } ]
}
```
**Note:** an unknown `eventId` does not 404 — `event` comes back `null` and `polls` is an empty array.

---

### POST /api/events/{eventId}/polls
Add a poll to an event, optionally seeded with initial options.

**Path Parameters:**
- `eventId` (long)

**Request:**
```json
{ "question": "Where to eat?", "allowAddOptions": true, "seedOptions": ["Pizza", "Sushi"] }
```
`question` required. `allowAddOptions` optional, defaults `true`. `seedOptions` optional — each becomes an unvoted PollOption.

**Response (200):** The created Poll object (does not include seeded options — fetch the poll detail endpoint below to see them).

**Errors:**
- `400 Bad Request`: `{ "success": false, "message": "Poll question cannot be empty" }`
- `500 Internal Server Error`: `{ "success": false, "message": "Failed to add poll: ..." }`

---

### GET /api/events/{eventId}/polls/{pollId}?voterKey={voterKey}
Get a poll plus its options, with per-option vote counts/voters, optionally personalized to a voter.

**Path Parameters:**
- `eventId` (long, present in path but not used to scope the lookup — only `pollId` matters)
- `pollId` (long)

**Query Parameters:**
- `voterKey` (string, optional): if provided, each option's `votedByMe` reflects that voter's votes

**Response (200):**
```json
{
  "poll": { "id": 9, "eventId": 5, "question": "Where to eat?", "allowAddOptions": true, "displayOrder": 0, "createdAt": "..." },
  "options": [
    { "id": 21, "pollId": 9, "text": "Pizza", "addedByName": null, "createdAt": "...", "voteCount": 3, "voters": ["Alex", "Sam", "Jo"], "votedByMe": true }
  ]
}
```

---

### POST /api/events/{eventId}/polls/{pollId}/options
Add a new option to a poll — this simultaneously registers as the submitter's vote for it.

**Path Parameters:**
- `eventId` (long, unused by the service), `pollId` (long)

**Request:**
```json
{ "text": "Tacos", "voterKey": "device-abc123", "voterName": "Jo" }
```
`text`, `voterName`, `voterKey` all required (non-blank).

**Response (200):** The created PollOption, pre-populated as the submitter's vote.

**Errors:**
- `400 Bad Request`: one of `{ "message": "Option text cannot be empty" }`, `{ "message": "A name is required to add an option" }`, `{ "message": "A voter identity is required to add an option" }`
- `500 Internal Server Error`

---

### PUT /api/events/{eventId}/polls/{pollId}/votes
Set the full set of options a voter has selected in a poll (diffed against their current votes — add/remove to match exactly what's requested).

**Path Parameters:**
- `eventId` (long, unused by the service), `pollId` (long)

**Request:**
```json
{ "voterKey": "device-abc123", "voterName": "Jo", "optionIds": [21, 23] }
```
`voterName`, `voterKey` required. `optionIds` optional — `null`/omitted clears all of this voter's votes in the poll. IDs outside this poll are silently ignored.

**Response (200):**
```json
{ "success": true }
```

**Errors:**
- `400 Bad Request`: `{ "message": "A name is required to vote" }` or `{ "message": "A voter identity is required to vote" }`
- `500 Internal Server Error`

---

## Voice Relay (Lexi)

Base Path: `/api/voice`

**Use Case:** Relays a browser-recorded voice clip from the Lexicon frontend to **Lexi**, the local voice-assistant process bound to `127.0.0.1:8765` on the same host (aragon), and returns Lexi's reply. This exists because aragon's microphone isn't always physically accessible, so recording happens in the browser instead. This is distinct from `voice.alex-dyakin.com` (the Mumble Bridge / SSO target) — this endpoint talks to Lexi over localhost only, and is not reachable if Lexi isn't running on the same machine as this Lexicon instance.

**Auth Required:** Yes, for both endpoints — this is one of the few controllers Spring Security actually gates (`/api/voice/**` falls through to the catch-all `authenticated()` rule), and the controller additionally self-checks the session.

### GET /api/voice/status
Report whether the voice relay is configured, so the frontend can explain itself before the user records anything.

**Response (200):**
```json
{ "configured": true }
```
`configured` reflects whether the server has a `lexi.tool.token` configured (i.e. whether it *can* authenticate to Lexi at all) — not whether Lexi is currently running/reachable.

**Errors:**
- `401 Unauthorized`: `{ "error": "Not authenticated" }`

---

### POST /api/voice/turn
Relay one recorded audio clip to Lexi and return its reply.

**Request:** Raw binary body (any `Content-Type` accepted — whatever container the browser's `MediaRecorder` produced, e.g. WebM/Opus or MP4/AAC). Max 8MB.

**Response:** Status code and JSON body are passed through **verbatim** from Lexi's own `/turn` endpoint — Lexicon does not reinterpret or re-wrap it, since Lexi already distinguishes cases like "no speech," "could not decode," and "brain down."

**Errors:**
- `401 Unauthorized`: `{ "error": "Not authenticated" }`
- `400 Bad Request`: `{ "error": "No audio was uploaded" }` (empty/missing clip) or `{ "error": "Clip is larger than 8MB" }`
- `503 Service Unavailable`: `{ "error": "Lexi tool token is not configured on the server" }` (fails closed rather than calling Lexi unauthenticated) or `{ "error": "Lexi is not running on this machine" }` (connection refused)
- `500 Internal Server Error`: `{ "error": "Voice relay failed: ..." }`
- Any other status/body Lexi itself returns is passed through unchanged.

---

## Avatar Proxy (Mumble Bridge)

Base Path: `/api/avatar`

**Use Case:** Proxies avatar get/upload/remove/image requests from the Lexicon frontend through to the Mumble Bridge (`https://voice.alex-dyakin.com`), so browsers with strict cross-origin protections (e.g. Brave) can still load bridge-hosted avatar images. No auth required on any endpoint (`permitAll`).

### GET /api/avatar/{username}
Fetch a user's avatar metadata (proxies to bridge `GET /api/avatar/{username}`).

**Response (200):** Whatever JSON the bridge returns (bridge-defined shape — typically avatar URL/metadata).

**Errors:**
- Bridge error status is forwarded as-is: `{ "success": false, "message": "Bridge returned error: 404 NOT_FOUND" }`
- `502 Bad Gateway`: `{ "success": false, "message": "Failed to reach avatar service: ..." }` (bridge unreachable)

---

### POST /api/avatar/upload
Upload an avatar image (proxied as multipart to bridge `POST /api/avatar/upload`).

**Request (multipart/form-data):**
- `username` (string, required)
- `userId` (integer, optional)
- `avatar` (file, required)

**Response (200):** Bridge's JSON response, passed through.

**Errors:** Same forwarding pattern as above, with `"Failed to upload avatar: ..."` on unreachable bridge.

---

### POST /api/avatar/remove
Remove a user's avatar (proxied as JSON to bridge `POST /api/avatar/remove`).

**Request:**
```json
{ "username": "someuser", "userId": 123 }
```

**Response (200):** Bridge's JSON response, passed through.

**Errors:** Same forwarding pattern, with `"Failed to remove avatar: ..."` on unreachable bridge.

---

### GET /api/avatar/image/{*path}
Proxy the actual avatar image bytes through Lexicon, avoiding a direct cross-origin image request to the bridge (proxies to bridge `GET /uploads/avatars/{path}`).

**Path Parameters:**
- `path` (string, required): everything after `/image/`, e.g. `user123/avatar.png`

**Response (200):** Raw image bytes. `Content-Type` from the bridge response (falls back to `image/jpeg`). `Cache-Control: no-cache, must-revalidate`.

**Errors:**
- `404 Not Found`: Bridge responded without 2xx, or with an empty body
- `502 Bad Gateway`: Bridge unreachable

---

## App Version & Update

Base Path: `/api/app`

**Use Case:** Metadata + APK download the Lexicon Android app polls to detect and prompt for in-app updates.

**Auth Required:** By default, **yes** for both endpoints (they fall through to the `/api/app/**` → `authenticated()` rule). They can be made public via server properties (`app.update.public-metadata=true` for the version endpoint, `app.update.public-download=true` for the download endpoint), but both properties default to `false`.

### GET /api/app/version
Return the latest available app version metadata. All values come from application properties — nothing is computed or read from disk.

**Response (200):**
```json
{
  "versionCode": 1,
  "versionName": "0.1.0",
  "downloadUrl": "https://api.alex-dyakin.com/api/app/download/latest",
  "critical": false,
  "changelog": ""
}
```
`sha256` is included only if the `app.update.sha256` property is set (non-blank); otherwise the key is omitted, not null.

---

### GET /api/app/download/latest
Download the latest Android APK build.

**Response (200):** Binary APK stream.
- `Content-Type: application/vnd.android.package-archive`
- `Content-Disposition: attachment; filename=lexicon-latest.apk`
- `Content-Length`

**Errors:**
- `404 Not Found`: Configured APK path (`app.update.apk-path`, default `./releases/lexicon-latest.apk`) doesn't exist

---

## Health & Info

Base Path: `/api`

**Use Case:** Basic health-check and static service-info endpoints. No auth required (`permitAll`).

### GET /api/health
Health check.

**Response (200):**
```json
{ "status": "OK", "service": "Lexicon API", "message": "Lexicon backend is running!" }
```

---

### GET /api/info
Static service metadata.

**Response (200):**
```json
{
  "service": "Lexicon Media Sharing API",
  "version": "1.0.0",
  "description": "Personal video and audio sharing platform",
  "features": ["User authentication", "Media file upload", "Video sharing", "Audio sharing", "Public/private media"]
}
```

---

## Data Models

### Player / User
```typescript
{
  id: number;
  username: string;
  displayName: string;
  email: string;
  level: number;
  registrationDate: string; // ISO 8601
  lastLoginDate: string; // ISO 8601
}
```

### MediaFile
```typescript
{
  id: number;
  filename: string;
  originalFilename: string;
  contentType: string; // MIME type
  fileSize: number; // bytes
  filePath: string; // relative path on disk
  uploadedBy: number; // user ID
  uploadDate: string; // ISO 8601
  title: string;
  description: string;
  mediaType: "MUSIC" | "VIDEO" | "AUDIOBOOK" | "OTHER";
  sourceUrl: string | null; // original URL if downloaded
  isPublic: boolean;
}
```

### ChatFile
```typescript
{
  id: number;
  originalFilename: string;
  storedFilename: string;
  mimeType: string; // image/jpeg, image/png, image/gif, image/webp
  fileSize: number; // bytes
  width: number | null; // pixels
  height: number | null; // pixels
  thumbnailFilename: string | null;
  uploadedBy: number; // user ID
  channelId: number | null;
  createdAt: string; // ISO 8601
}
```

### TextMessage
```typescript
{
  id: number;
  channelId: number;
  channelName: string;
  userId: number;
  username: string;
  content: string;
  messageType: "TEXT" | "IMAGE" | "GIF" | "MIXED" | "MEDIA_SHARE" | "SYSTEM" | "BOT_COMMAND";
  mediaFileId: number | null; // references ChatFile.id for IMAGE/GIF/MIXED
  replyToId: number | null;
  isPinned: boolean;
  attachment: { // populated for IMAGE/GIF/MIXED messages
    id: number;
    url: string;
    thumbnailUrl: string;
    originalFilename: string;
    mimeType: string;
    width: number | null;
    height: number | null;
    fileSize: number;
  } | null;
  createdAt: string; // ISO 8601
  editedAt: string | null;
  deletedAt: string | null;
}
```

### Playlist
```typescript
{
  id: number;
  name: string;
  description: string;
  isPublic: boolean;
  createdBy: number; // user ID
  createdDate: string; // ISO 8601
  itemCount: number;
  items?: MediaFile[]; // included in GET /{id}
  mediaFileIds?: number[]; // for create/update
}
```

### LiveStreamState
```typescript
{
  id: number;
  currentMediaId: number | null;
  currentMedia: MediaFile | null;
  currentStartTime: string; // ISO 8601
  currentPositionMs: number;
  totalSkipVotes: number;
  requiredSkipVotes: number;
  queuedItems: LiveStreamQueue[];
}
```

### LiveStreamQueue
```typescript
{
  id: number;
  mediaFileId: number;
  mediaFile: MediaFile;
  queuedBy: number; // user ID
  queuedAt: string; // ISO 8601
  position: number;
  status: "QUEUED" | "PLAYING" | "COMPLETED";
}
```

### PlaybackPosition
```typescript
{
  userId: number;
  mediaFileId: number;
  position: number; // seconds
  duration: number; // seconds
  completed: boolean;
  progressPercentage: number;
  lastUpdated: string; // ISO 8601
}
```

### Notification
```typescript
{
  id: number;
  targetUserId: number | null; // null = broadcast
  type: "message" | "voice_join" | "mention" | "music";
  title: string;
  body: string;
  source: string; // default "mumble"
  fromUsername: string;
  fromUserId: number;
  channelId: number | null;
  link: string | null;
  createdAt: string; // ISO 8601
}
```

### NotificationPrefs
```typescript
{
  userId: number;
  enableMessage: boolean;
  enableVoiceJoin: boolean;
  enableMention: boolean;
  enableMusic: boolean;
  enablePush: boolean;
  lastReadAt: string | null; // ISO 8601
}
```

### Event
```typescript
{
  id: number;
  title: string;
  description: string | null;
  eventDate: string | null; // ISO date (YYYY-MM-DD)
  createdByUserId: number | null;
  createdAt: string; // ISO 8601
  pollCount: number;
}
```

### Poll
```typescript
{
  id: number;
  eventId: number;
  question: string;
  allowAddOptions: boolean;
  displayOrder: number;
  createdAt: string; // ISO 8601
}
```

### PollOption
```typescript
{
  id: number;
  pollId: number;
  text: string;
  addedByName: string | null;
  createdAt: string; // ISO 8601
  voteCount: number;
  voters: string[];
  votedByMe: boolean; // only meaningful when a voterKey was supplied on the request
}
```

### ChunkedUpload
```typescript
{
  uploadId: string; // UUID
  originalFilename: string;
  contentType: string;
  totalSize: number; // bytes
  chunkSize: number; // bytes
  totalChunks: number;
  uploadedChunks: number;
  progress: number; // percentage
  status: "UPLOADING" | "ASSEMBLING" | "COMPLETED" | "CANCELLED";
  uploadedBy: number; // user ID
  title: string;
  description: string;
  isPublic: boolean;
  mediaType: string;
  lastActivity: string; // ISO 8601
}
```

### DownloadJob
```typescript
{
  jobId: string; // UUID
  url: string;
  userId: number;
  title: string;
  description: string;
  mediaType: string;
  status: "QUEUED" | "PROCESSING" | "COMPLETED" | "FAILED";
  queuedAt: string; // ISO 8601
  startedAt: string | null; // ISO 8601
  completedAt: string | null; // ISO 8601
  mediaFileId: number | null; // available when COMPLETED
  error: string | null; // available when FAILED
}
```

---

## Holdfast Management (Alchemy API)

**Base URL:** `https://alchemy.alex-dyakin.com` (production) or `http://localhost:8080` (local)  
**Auth:** ⚠️ **None actually enforced.** `SecurityConfig` in this server sets `.anyRequest().permitAll()` app-wide, and `HoldfastController` never checks the session. Any caller can create/read/modify/delete any group's holdfast by name with no `JSESSIONID`. (`GET /api/auth/me` is the only endpoint in this whole server that checks a session — see [Alchemy Authentication](#alchemy-authentication).)  
**Path prefix:** `/api/holdfast`

A D&D settlement management system. Holdfasts have buildings, resources, population, and gold — time advances day-by-day with raids, production events, and population growth.

**Error response format note:** almost every error in this controller (and every other controller in this server) is returned as a **plain text string** body (e.g. `groupName is required`), not a JSON object — despite the examples below sometimes showing JSON for illustration. The only Holdfast endpoints with genuinely JSON error bodies are `POST /build` and `POST /advance`.

---

### GET /api/holdfast/all
Return all holdfasts.

**Response `200`:**
```json
[
  {
    "id": 1,
    "groupName": "zx",
    "holdfastName": "Ironkeep",
    "baseGoldPerDay": 40.0,
    "population": 40,
    "castleType": "wood_fort",
    "gold": 608.7,
    "silver": 0,
    "wood": 0,
    "stone": 0,
    "iron": 0,
    "food": 0,
    "happiness": 50.0,
    "targetHappiness": 50.0,
    "daysElapsed": 7,
    "beer": 3,
    "grain": 0,
    "wine": 0,
    "tools": 0,
    "raidsSurvived": 0,
    "foodMarketEnabled": false,
    "buildings": { "tavern": 1, "blacksmith": 1 },
    "wheatFieldPlantDays": [],
    "ryeFieldPlantDays": [],
    "vegetableGardenPlantDays": [],
    "orchardPlantDays": [],
    "vineyardPlantDays": [],
    "berryPatchPlantDays": [],
    "mushroomCavePlantDays": [],
    "foodBatchDays": [],
    "foodBatchAmounts": [],
    "populationGrowthHistory": []
  }
]
```
**Note:** `wood`, `stone`, `iron`, `food`, `ryeFieldPlantDays`, `berryPatchPlantDays`, `mushroomCavePlantDays`, `foodBatchDays`, `foodBatchAmounts`, and `foodMarketEnabled` were added since this doc was first written — added here for accuracy.

---

### GET /api/holdfast/{groupName}
Return full status for one holdfast, including a computed building menu.

**Response `200`:**
```json
{
  "holdfast": { "...same fields as GET /all..." },
  "dailyIncome": 44.1,
  "dailyUpkeep": 1.4,
  "netDailyGold": 42.7,
  "protection": 47.8,
  "raidChance": 4.42,
  "daysOfFood": 12.5,
  "nextSpoilIn": 3,
  "foodShelfLife": 15,
  "foodMarketEnabled": false,
  "populationChange": 2,
  "avgDailyGrowth": 0.3,
  "populationHistory": [],
  "buildingMenu": [
    {
      "type": "tavern",
      "name": "Tavern",
      "status": "maxed",
      "current": 1,
      "max": 3,
      "lockReason": null,
      "baseCost": 60,
      "cost": 60,
      "resourceCost": {},
      "dailySilver": 10.0,
      "dailyUpkeep": 0.5,
      "happiness": 5.0,
      "harvestFood": 0,
      "harvestGold": 0,
      "harvestDays": 0,
      "productionItem": "beer",
      "productionAmount": 3,
      "productionDays": 7,
      "description": "Produces beer every 7 days"
    }
  ]
}
```
**Note:** the top-level status object gained `daysOfFood`, `nextSpoilIn`, `foodShelfLife`, `foodMarketEnabled`, `populationChange`, `avgDailyGrowth`, and `populationHistory` since this doc was first written. The `buildingMenu` entry fields were also corrected here — the actual JSON keys are `current`/`max` (not `currentCount`/`maxCount`), and each entry also carries `lockReason`, `baseCost`, `resourceCost`, `harvestFood`, `harvestGold`, `harvestDays`, `productionItem`, `productionAmount`, and `productionDays`.

**Response `404`:** `{ "error": "Holdfast not found" }`

---

### POST /api/holdfast/create
Create a new holdfast.

**Request:**
```json
{ "groupName": "zx", "holdfastName": "Ironkeep" }
```

**Response `200`:** Full holdfast object (see GET /all)  
**Response `400`:** plain text `groupName is required` or `A holdfast for group '<name>' already exists`

---

### POST /api/holdfast/import
Import a fully-formed holdfast object (e.g. for migrating/restoring data), instead of creating a fresh default one.

**Request:** Full `Holdfast` JSON object (see GET /all for shape) — `groupName` required.

**Response `200`:** The imported holdfast object.  
**Response `400`:** plain text — `groupName` blank, or a holdfast for that group already exists.

---

### POST /api/holdfast/advance
Advance time by N days. Returns a day-by-day event log.

**Request:**
```json
{ "groupName": "zx", "days": 30 }
```

**Response `200`:**
```json
{
  "events": [
    "Advancing 30 day(s)...",
    "DAY 7 - Taverns produced 3 beer (Total: 3)",
    "DAY 14 - BANDIT RAID! Bandits stole 280g!",
    "  Buildings destroyed: Tavern",
    "  Population casualties: 3",
    "Day 20: Net +40.0g | Total: 620.0g",
    "Day 30: Net +40.0g | Total: 1020.0g"
  ],
  "holdfast": { "...updated holdfast..." }
}
```

**Response `400`:** plain text — `days must be greater than 0` or `Cannot advance more than 365 days at once`

---

### GET /api/holdfast/{groupName}/events
Return the raw event log for a holdfast (the underlying records behind the `events` array `POST /advance` returns).

**Path Parameters:**
- `groupName` (string): Group identifier

**Response `200`:** `List<Map>` of event-log entries.  
**Response `404`:** Holdfast not found (empty body).

---

### POST /api/holdfast/build
Build one unit of a building type. Deducts gold; tracks plant days for crop fields.

**Request:**
```json
{ "groupName": "zx", "buildingType": "tavern" }
```

**Response `200`:** `{ "success": true, "message": "Built Tavern for 60g", "holdfast": { "..." } }`  
**Response `400`:** `{ "success": false, "message": "Insufficient funds. Need: 60g, Have: 20.0g. Advance ~1 days." }`  
            or `{ "success": false, "message": "Market requires at least 60 population (current: 40)" }`  
            or `{ "success": false, "message": "Maximum Taverns reached (3)" }`

(These are the two endpoints in this controller whose error bodies are actually JSON — see the note at the top of this section.)

**Building types (35 total):** five building types (`granary`, `rye_field`, `berry_patch`, `mushroom_cave`, `food_market`) were added since this doc was first written and are marked **NEW** below.

| Type | Min Pop | Base Cost | Daily Silver | Resource Cost | Notes |
|------|---------|-----------|--------------|---------------|-------|
| `alchemy_garden` | 0 | 80g | 8s | — | +1 happiness *(doc previously said 20s — corrected)* |
| `mine` | 0 | 120g | 0 | — | +2 stone +1 iron per 7d; -5 happiness |
| `logging_camp` | 0 | 70g | 0 | — | +3 wood per 7d |
| `tavern` | 0 | 60g | 10s | — | +3 beer per 7d; +5 happiness (max 3 per holdfast, +2 more unlocked at pop ≥100) |
| `guard_tower` | 0 | 25g | 0 | 4 wood | +10 protection |
| `wheat_field` | 0 | 50g | 0 | — | +20 food per 14d, auto-replants |
| **`granary`** (NEW) | 0 | 80g | 0 | — | -5 upkeep; extends food shelf life by +15 days per granary |
| **`rye_field`** (NEW) | 0 | 65g | 0 | — | +40 food per 28d, annual crop (fallow after harvest — see `/replant`) |
| `vegetable_garden` | 30 | 45g | 0 | — | +10 food per 10d, auto-replants; +1 happiness |
| **`berry_patch`** (NEW) | 20 | 40g | 0 | — | +8 food per 7d, perennial (no replant needed) |
| `orchard` | 50 | 150g | 0 | — | +8 food +40g per 30d; +2 happiness |
| **`mushroom_cave`** (NEW) | 50 | 150g | 0 | — | +25 food per 21d, perennial; requires `mine` |
| `vineyard` | 60 | 180g | 0 | — | +2 wine per 7d; +4 happiness |
| **`food_market`** (NEW) | 60 | 400g | 0 | — | Sells surplus food for gold when toggled on via `/toggle-food-market`; requires `granary` |
| `blacksmith` | 35 | 140g | 15s | — | +2 tools per 14d; +5 protection; +1 happiness |
| `carpenter` | 30 | 110g | 12s | — | -10% build costs per carpenter |
| `chapel` | 40 | 250g | 0 | 5 stone | +15 happiness |
| `market` | 60 | 320g | 20s | 5 wood, 5 stone | +10% all building gold; +8 happiness |
| `festival_ground` | 70 | 220g | 0 | 4 wood, 3 stone | +80g per 30d; +10 happiness |
| `library` | 75 | 380g | 0 | 4 wood, 3 stone | +8 happiness |
| `hospital` | 90 | 480g | 0 | 4 wood, 3 iron | +3 pop growth; +12 happiness |
| `lighthouse` | 80 | 420g | 25s | 5 stone | +6 happiness |
| `stone_walls` | 80 | 1000g | 0 | 20 stone | +30 protection; -2 happiness; upgrades to stone_fort |
| `castle_keep` | 150 | 1800g | 0 | 12 stone, 8 iron | +50 protection; -4 happiness; upgrades to stone_castle |
| `church` | 100 | 650g | 0 | 8 stone, 2 iron | +30 happiness; +2 pop growth; requires chapel |
| `grand_theater` | 110 | 550g | 30s | 6 wood, 4 stone | +12 happiness |
| `university` | 130 | 800g | 0 | 5 stone, 3 iron | +15 happiness; requires library |
| `mint` | 140 | 900g | 40s | 8 iron, 5 stone | -2 happiness |
| `aqueduct` | 150 | 1200g | 0 | 10 stone, 5 iron | +18 happiness; +2 pop growth |
| `canal_small` | 160 | 800g | 10s | — | +8 happiness; requires aqueduct |
| `canal_major` | 200 | 2500g | 40s | — | +15% gold on all buildings; +25 happiness; requires canal_small |
| `harbor` | 170 | 1400g | 100s | 8 wood, 8 stone | +15 happiness |
| `palace` | 200 | 3000g | 0 | — | +35 happiness |
| `colosseum` | 180 | 2200g | 50s | — | +20 happiness |
| `museum` | 160 | 1600g | 0 | — | +12 happiness |

> **Note:** Daily silver is reduced by 15% before conversion to gold (10s = 1g after reduction). Market (+10%) and Major Canal (+15%) bonuses are multiplicatively equivalent whether applied before or after the 15% reduction — current code applies them before the reduction, but the net result is the same either way.

**Food & crops (added since this doc was first written):** annual crops (`wheat_field`, `rye_field`, `vegetable_garden`) go fallow after each harvest and must be manually re-planted via `POST /api/holdfast/replant`; perennial crops (`berry_patch`, `mushroom_cave`, `orchard`, `vineyard`) keep producing without replanting. `granary` buildings extend how long harvested food keeps before spoiling; `food_market` (requires `granary`) can be toggled to automatically sell surplus food for gold via `POST /api/holdfast/toggle-food-market`.

---

### Game Mechanics Summary

**Daily Loop (per day advanced):**
1. Gold income: `baseGoldPerDay (40) + population/10 + building silver×0.85/10`
2. Gold upkeep: sum of building daily upkeep / 10
3. Food consumption: `ceil(population × 0.2)` food/day
   - No food → spend `population × 2g` per day on emergency rations
   - No food AND no gold → happiness −3/day (famine)
4. Happiness drifts 0.5/day toward target happiness
5. Raid check: chance = `max(0.5%, 8% − protection × 0.075)`
6. Every 7 days: population growth check; mine/logging camp production
7. Field harvests trigger when `currentDay − plantDay ≥ harvestDays`

**Target Happiness:**
- Base: 75 + sum of building happiness bonuses
- Crowding penalty: `1.04^max(0, population−40)` (exponential — each person above 40 compounds 4%)
- Example: pop 80 → penalty ≈ 4.8; pop 100 → penalty ≈ 10.5; pop 120 → penalty ≈ 23

**Population Growth (every 7 days):**
- Requires happiness ≥ 65
- Chance = `(happiness − 65) / 100 + 0.10`
- Growth = 1–3 people; bonuses from hospital (+3), church (+2), aqueduct (+2)

---

### POST /api/holdfast/deposit
Add gold to the holdfast treasury.

**Request:**
```json
{ "groupName": "zx", "gold": 500.0 }
```

**Response `200`:** The full, updated `Holdfast` object directly (same shape as one item of `GET /all`) — **not** wrapped in a `{ message, holdfast }` envelope as previously documented.  
**Response `400`:** plain text `Gold amount must be positive` (if `gold` ≤ 0)  
**Response `404`:** Holdfast not found (empty body)

---

### POST /api/holdfast/withdraw
Withdraw gold and/or resources from the holdfast.

**Request:**
```json
{ "groupName": "zx", "gold": 100.0, "beer": 2, "wine": 0, "grain": 0, "tools": 1 }
```

**Response `200`:** `{ "message": "Resources withdrawn successfully", "success": true }`  
**Response `400`:** plain text `Insufficient resources` — **not** the JSON body previously documented here

---

### POST /api/holdfast/replant
Re-plant a fallow annual crop field for a per-field seed cost. Only applies to annual crops (`wheat_field`, `rye_field`, `vegetable_garden`) — perennial crops don't need this.

**Request:**
```json
{ "groupName": "zx", "fieldType": "wheat_field" }
```

**Response `200`:** `{ "success": true, "message": "Replanted ... field(s)", "holdfast": { "..." } }`  
**Response `400`:** plain text — `fieldType` isn't an annual crop, there are no fallow fields of that type, or insufficient gold for the seed cost (wheat_field 10g, rye_field 12g, vegetable_garden 8g per field)

---

### POST /api/holdfast/toggle-food-market
Flip the holdfast's `foodMarketEnabled` flag (requires a built `food_market`) — when enabled, surplus food is automatically sold for gold each day.

**Request:**
```json
{ "groupName": "zx" }
```

**Response `200`:** `{ "success": true, "foodMarketEnabled": true, "holdfast": { "..." } }`  
**Response `404`:** Holdfast not found (empty body)

---

### DELETE /api/holdfast/{groupName}
Delete a holdfast and all its data.

**Response `200`:** `{ "message": "Holdfast deleted", "success": true }`  
**Response `404`:** `{ "error": "Holdfast not found" }`

---

## Alchemy Authentication

**Base URL:** `https://alchemy.alex-dyakin.com` (production) or `http://localhost:8080` (local)  
**Path prefix:** `/api/auth`

A separate login/session system from Lexicon's `/api/auth` — the Alchemy API has its own `Player` accounts and its own `JSESSIONID` session, backed by Spring Security's `AuthenticationManager`. Sessions are **not** shared between the two servers. This is the only controller in the Alchemy server where auth is actually enforced (via `SecurityContextHolder`) — every other Alchemy endpoint is `permitAll()`.

### POST /api/auth/login
Authenticate and create an Alchemy session.

**Request:**
```json
{ "username": "string", "password": "string" }
```

**Response `200`:**
```json
{ "playerId": 1, "username": "john_doe" }
```

**Errors:**
- `401 Unauthorized`: plain text `Invalid credentials`
- `500 Internal Server Error`: plain text `Error during login: ...`

**Sets Cookie:** `JSESSIONID`

---

### POST /api/auth/register
Register a new Alchemy player.

**Request:**
```json
{ "username": "string", "password": "string" }
```
**Note:** there is no `confirmPassword` field — the server passes the same password twice internally, so client-side confirmation is the only check.

**Response `200`:**
```json
{ "message": "Registration successful" }
```

**Errors:**
- `409 Conflict`: plain text `Username is already taken.`
- `500 Internal Server Error`: plain text `Error during registration: ...`

---

### GET /api/auth/me
Get the current authenticated Alchemy player.

**Response `200`:**
```json
{ "id": 1, "username": "john_doe", "level": 5 }
```

**Errors:**
- `401 Unauthorized`: No valid session, or anonymous principal (empty body)
- `500 Internal Server Error`: plain text `Error retrieving current user: ...`

---

## Alchemy Player

**Path prefix:** `/api/player` (singular — distinct from Holdfast's `/api/holdfast` and note this is *not* the same base path as Lexicon's `/api/players`)

**No auth enforced** on any endpoint below — `playerId` is trusted as-is from the URL/body. ⚠️ `GET` endpoints that return a full `Player` object include the `password` field (no `@JsonIgnore`) — see the note in [Authentication & Security](#authentication--security).

### GET /api/player/{id}
Get a player by ID, including inventory, knowledge book, and level.

**Response `200`:** Full `Player` object.  
**Response `404`:** Not found (empty body)  
**Response `500`:** plain text error

---

### GET /api/player/username/{username}
Get a player by username. Same shape/behavior as above.

---

### GET /api/player/all
List every player (same password-exposure caveat as above).

**Response `200`:** JSON array of `Player` objects.

---

### GET /api/player/inventory/{playerId}
Get a player's ingredient and potion inventory.

**Response `200`:**
```json
{
  "ingredients": [
    {
      "id": 1,
      "name": "Moonpetal",
      "effects": [ { "id": 3, "title": "Clarity", "description": "..." } ],
      "quantity": 2
    }
  ],
  "potions": [
    {
      "id": 5,
      "name": "Elixir of Focus",
      "quantity": 1,
      "description": "...",
      "duration": 10.0,
      "brewLevel": 2,
      "dice": "1d6",
      "effects": [ { "id": 3, "title": "Clarity", "description": "..." } ]
    }
  ]
}
```
An ingredient's `effects` are filtered to only those the player's knowledge book has learned; potion `effects` are not filtered.

**Response `404`:** Inventory is null (empty body)

---

### GET /api/player/forage/{playerId}
Forage a random ingredient for the player.

**Response `200`:**
```json
{ "forage": "Moonpetal" }
```

**Errors:**
- `400 Bad Request`: plain text `No ingredient available to forage.`
- `500 Internal Server Error`: plain text error

---

### POST /api/player/ingredient/consume
Consume an ingredient from a player's inventory.

**Request:**
```json
{ "playerId": 1, "ingredientId": 3 }
```

**Response `200`:** plain text `Ingredient consumed successfully.`

**Errors:**
- `400 Bad Request`: plain text `Ingredient not found in inventory.`
- `500 Internal Server Error`: plain text error (also thrown if `playerId`/`ingredientId` aren't JSON integers)

---

### POST /api/player/potion/consume
Consume a potion from a player's inventory.

**Request:**
```json
{ "playerId": 1, "potionId": 5 }
```

**Response `200`:** plain text `Potion consumed successfully.`

**Errors:**
- `400 Bad Request`: plain text `Potion not found in inventory.`
- `500 Internal Server Error`: plain text error

---

### POST /api/player/levelup
Level up a player, gated by a hardcoded shared secret (not a per-user password) checked server-side. Max level is 10.

**Request:**
```json
{ "playerId": 1, "secretPassword": "string" }
```

**Response `200`:** Full updated `Player` object (includes `password` field).

**Errors:**
- `400 Bad Request`: plain text `Player not found.` or `Level up failed: either maximum level reached or incorrect password.` (these two distinct failure modes share one message)
- `500 Internal Server Error`: plain text error

---

### GET /api/player/knowledge/{playerId}
Get everything a player's knowledge book knows about ingredient effects.

**Response `200`:**
```json
[
  {
    "ingredientId": 1,
    "ingredientName": "Moonpetal",
    "effects": [ { "id": 3, "title": "Clarity", "description": "..." } ]
  }
]
```
`ingredientName` is resolved by scanning the player's own inventory; if the ingredient isn't in their inventory it falls back to `"Unknown Ingredient"`.

**Errors:**
- `404 Not Found`: knowledge book or inventory is null (empty body)
- `500 Internal Server Error`: plain text error

---

## Alchemy Potion Brewing

**Path prefix:** `/api/potion`

**No auth enforced.**

### POST /api/potion/brew
Brew a potion from two ingredients in the player's inventory.

**Request:**
```json
{ "playerId": 1, "ingredientId1": 3, "ingredientId2": 7 }
```
Both ingredients must already be present in the player's inventory (looked up there, not from a global catalog).

**Response `200`:**
```json
{
  "message": "Potion brewed successfully",
  "potion": {
    "id": 12,
    "name": "Elixir of Focus",
    "effects": [ { "id": 3, "title": "Clarity", "description": "..." } ],
    "ingredient1": { "...ingredient object..." },
    "ingredient2": { "...ingredient object..." },
    "duration": 10.0,
    "description": "...",
    "brewLevel": 2,
    "dice": "1d6"
  }
}
```

**Errors:**
- `400 Bad Request`: plain text `Invalid ingredient selection.` (either ingredient not found in the player's inventory) or `Potion brewing failed.` (brew logic returned no result)
- `500 Internal Server Error`: plain text `Error brewing potion: ...`

---

## Alchemy Game Lifecycle

**Path prefix:** `/api/game`

**No auth enforced.** Per an in-code comment, these endpoints "aren't used very much yet" — treat as low-priority/legacy relative to Holdfast Management.

### POST /api/game/start
Start the (global) game session.

**Response `200`:** plain text `Game started.`  
**Response `500`:** plain text `Error starting game: ...`

---

### POST /api/game/end
End the (global) game session.

**Response `200`:** plain text `Game ended.`  
**Response `500`:** plain text `Error ending game: ...`

---

### GET /api/game/forage/{playerId}
Duplicate of `GET /api/player/forage/{playerId}`, but returns plain text instead of JSON and has no explicit "nothing to forage" check.

**Response `200`:** plain text `Foraged ingredient: <name>`  
**Response `500`:** plain text `Error during foraging: ...`

---

## Error Responses

The shapes below are the dominant pattern (Media, Chunked Upload, Async Download Queue, Playback Position, Push, Notifications, Events, most Playlist/LiveStream error paths), but they are **not universal**. A number of controllers return **plain text** error bodies instead of JSON, notably: Lexicon's `/api/auth/*`, Alchemy's `/api/auth/*`, and nearly everything in the Alchemy server (`/api/holdfast/*` except `build`/`advance`, `/api/player/*`, `/api/potion/*`, `/api/game/*`). Playlist/Message/StreamingMedia mutation endpoints often return a bare plain-text success/failure string on the 200 path too (e.g. `"Item added to playlist"`) rather than a JSON object. When integrating, check `Content-Type` on the response rather than assuming JSON.

### 400 Bad Request
```json
{
  "success": false,
  "message": "Error description"
}
```

### 401 Unauthorized
Empty response or:
```json
{
  "success": false,
  "message": "Authentication required"
}
```

### 403 Forbidden
```json
{
  "success": false,
  "message": "Permission denied"
}
```

### 404 Not Found
Empty response or:
```json
{
  "success": false,
  "message": "Resource not found"
}
```

### 500 Internal Server Error
```json
{
  "success": false,
  "message": "Internal error: details"
}
```

---

## Integration Guidelines for Microservices

### 1. Authentication
```javascript
// Production: Use HTTPS subdomains via Cloudflare tunnel
const loginResponse = await fetch('https://api.alex-dyakin.com/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  credentials: 'include', // CRITICAL: include cookies
  body: JSON.stringify({ username: 'user', password: 'pass' })
});

// Verify session
const meResponse = await fetch('https://api.alex-dyakin.com/api/auth/me', {
  credentials: 'include' // CRITICAL: include cookies
});

// Local development: Use localhost
const localLogin = await fetch('http://localhost:36568/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  credentials: 'include',
  body: JSON.stringify({ username: 'user', password: 'pass' })
});
```

### 2. CORS Configuration
**For Production (HTTPS via Cloudflare):**
Microservices calling from external origins will be allowed if they originate from:
- `https://alex-dyakin.com` (frontend)
- `https://*.alex-dyakin.com` (any subdomain)
- `http://147.185.221.24:*` (PlayIt fallback)

**For Local Development:**
Add your microservice origin to `CORS_ALLOWED_ORIGINS` environment variable:
```bash
CORS_ALLOWED_ORIGINS=http://localhost:3001,http://your-microservice:port
```

Pattern-based CORS can be added to `LexiconSecurityConfig.java`:
```java
allowedOriginPatterns.add("https://your-domain\.com");
```

### 3. Session Management
- Sessions are server-side only (not JWT)
- Session cookie name: `JSESSIONID`
- Include `credentials: 'include'` in all fetch requests
- Session timeout: 30 days

### 4. File Uploads
- Small files (<100MB): Use `/api/media/upload`
- Large files (>100MB): Use chunked upload `/api/media/chunked/*`
- URL downloads: Use async queue `/api/download-queue/start`

### 5. Real-Time Updates
- Use SSE endpoints for live updates:
  - `/api/livestream/updates?channel=video|music` - Full stream updates (per-channel)
  - `/api/media/chunked/progress/{uploadId}` - Chunk upload progress
  - `/api/playlists/import-progress/{importId}` - Playlist import progress
  - `/api/notifications/stream?userId={userId}` - Live in-app notification delivery

### 6. Media Streaming
- Use `/api/media/stream/{id}` for basic streaming
- Use `/api/stream/{mediaFileId}` for enhanced streaming with range support
- Always check `Accept-Ranges` and `Content-Range` headers for seeking

### 7. Push Notifications
- Use `/api/push/vapid-key` to bootstrap browser subscription
- Register device subscription via `/api/push/subscribe`
- Voice/bridge services can trigger push via `/api/push/send` or `/api/push/send-bulk`
- Push payloads are encrypted before delivery

### 8. SSO Handoff to Voice
- Generate handoff token with `/api/auth/sso/generate-token` using active Lexicon session cookie
- Redirect users to `https://voice.alex-dyakin.com?token=...`
- Bridge validates token once via `/api/auth/sso/validate-token`
- Treat tokens as one-time credentials and never store them long-term

### 9. Database Communication
- No direct database access between microservices
- All communication via HTTP REST API
- Use appropriate endpoints for CRUD operations
- Implement retry logic for network failures

### 10. Error Handling
```javascript
const response = await fetch(url, options);
if (!response.ok) {
  const error = await response.json();
  console.error(error.message);
  // Handle error
}
```

### 11. Performance Tips
- Poll `/api/download-queue/status/{jobId}` at reasonable intervals (5-10 seconds)
- Cache media file metadata to reduce API calls
- Use SSE for real-time updates instead of polling

---

## Testing Endpoints

### cURL Examples

**Check API Health (verify it's running):**
```bash
# Production (HTTPS via Cloudflare Tunnel)
curl https://api.alex-dyakin.com/api/health

# Alchemy API health check
curl https://alchemy.alex-dyakin.com/

# Local development
curl http://localhost:36568/api/health
curl http://localhost:8080/  # Alchemy

# Fallback: PlayIt Tunnel (if DNS not yet updated)
curl http://147.185.221.24:15856/api/health
```

**Login (Production - HTTPS):**
```bash
curl -X POST https://api.alex-dyakin.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test"}' \
  -c cookies.txt
```

**Login (Local Development):**
```bash
curl -X POST http://localhost:36568/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test"}' \
  -c cookies.txt
```

**Get VAPID Public Key:**
```bash
curl https://api.alex-dyakin.com/api/push/vapid-key
```

**Register Push Subscription:**
```bash
curl -X POST https://api.alex-dyakin.com/api/push/subscribe \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 7,
    "endpoint": "https://fcm.googleapis.com/fcm/send/example",
    "keys": {"p256dh": "key", "auth": "auth"},
    "userAgent": "Mozilla/5.0"
  }'
```

**Send Push Notification:**
```bash
curl -X POST https://api.alex-dyakin.com/api/push/send \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 7,
    "title": "New DM",
    "body": "You have a new message",
    "url": "https://voice.alex-dyakin.com"
  }'
```

**Generate SSO Token (requires authenticated Lexicon session):**
```bash
curl -X POST https://api.alex-dyakin.com/api/auth/sso/generate-token \
  -b cookies.txt
```

**Validate SSO Token (bridge server-to-server call):**
```bash
curl -X POST https://api.alex-dyakin.com/api/auth/sso/validate-token \
  -H "Content-Type: application/json" \
  -d '{"token":"base64url-token"}'
```

**Get Current User:**
```bash
# Production
curl https://api.alex-dyakin.com/api/auth/me -b cookies.txt

# Local
curl http://localhost:36568/api/auth/me -b cookies.txt
```

**Upload File:**
```bash
# Production
curl -X POST https://api.alex-dyakin.com/api/media/upload \
  -F "file=@song.mp3" \
  -F "userId=1" \
  -F "title=My Song" \
  -F "mediaType=MUSIC" \
  -b cookies.txt

# Local
curl -X POST http://localhost:36568/api/media/upload \
  -F "file=@song.mp3" \
  -F "userId=1" \
  -F "title=My Song" \
  -F "mediaType=MUSIC" \
  -b cookies.txt
```

**Stream Media (with range request for seeking):**
```bash
# Production
curl https://api.alex-dyakin.com/api/media/stream/123 \
  -H "Range: bytes=0-1023" \
  -b cookies.txt

# Local
curl http://localhost:36568/api/media/stream/123 \
  -H "Range: bytes=0-1023" \
  -b cookies.txt
```

**Frontend via HTTPS (once DNS propagates):**
```bash
curl -I https://alex-dyakin.com
# Returns HTTP/2 200 with Cloudflare headers
```

---

## Deployment URLs

### Production (Public - HTTPS via Cloudflare Tunnel)
| Service | URL | Type |
|---------|-----|------|
| **Frontend** | https://alex-dyakin.com | HTTPS ✅ |
| **Lexicon API** | https://api.alex-dyakin.com | HTTPS ✅ |
| **Alchemy API** | https://alchemy.alex-dyakin.com | HTTPS ✅ |
| **Certificate** | Cloudflare CA (auto-renewed) | Valid |
| **Fallback (Legacy)** | http://147.185.221.24:15856 | HTTP |

**IMPORTANT:** Always use HTTPS URLs in production. HTTP fallback is only for systems without DNS resolution.

### Local Development
| Service | URL |
|---------|-----|
| **Frontend** | http://localhost:3001 |
| **Lexicon API** | http://localhost:36568 |
| **Alchemy API** | http://localhost:8080 |
| **Database** | localhost:9002 |

## Microservice Integration Checklist

**Primary (Recommended):**
- [ ] Use `https://api.alex-dyakin.com` for Lexicon API calls
- [ ] Use `https://alchemy.alex-dyakin.com` for Alchemy API calls
- [ ] Verify DNS resolution of alex-dyakin.com (if external)
- [ ] Add your microservice origin to `LexiconSecurityConfig.java` if not matching allowed patterns
- [ ] Implement login to `https://api.alex-dyakin.com/api/auth/login`
- [ ] Store JSESSIONID cookie
- [ ] Include `credentials: 'include'` in all fetch requests
- [ ] Handle 401 responses (session expired)
- [ ] Test CORS with `OPTIONS` preflight request
- [ ] Use `https://api.alex-dyakin.com/api/health` to verify connectivity

**Fallback (if DNS not resolved):**
- [ ] Use `http://147.185.221.24:15856` for Lexicon API (PlayIt tunnel)
- [ ] Use `http://147.185.221.24:15821` for Alchemy API (PlayIt tunnel)
- [ ] Same authentication and CORS requirements apply
- [ ] Update to HTTPS URLs once DNS propagates

## System Architecture

```
Internet (External Devices)
   ↓ HTTPS (Cloudflare SSL/TLS)
https://alex-dyakin.com → Cloudflare Edge Network
   ↓ (routed via Cloudflare Tunnel)
https://api.alex-dyakin.com → localhost:36568 (Lexicon API)
https://alchemy.alex-dyakin.com → localhost:8080 (Alchemy API)
https://alex-dyakin.com → localhost:3001 (React Frontend)
   ↓
Cloudflare Tunnel Connector (this server)
   ↓
Local Services
   ├── localhost:3001 (React Frontend)
   ├── localhost:36568 (Lexicon API, Java/Spring)
   ├── localhost:8080 (Alchemy API, Java/Spring)
   └── localhost:9002 (HSQLDB)

Fallback Path (Legacy PlayIt):
http://147.185.221.24:15856 → localhost:36568 (Lexicon)
http://147.185.221.24:15821 → localhost:8080 (Alchemy)
```

## Security Notes for Microservices

1. **Session Isolation:** Each microservice has its own session. Don't share tokens.
2. **CORS Configuration:**
   - Allowed origins: `https://alex-dyakin.com`, `https://*.alex-dyakin.com`
   - If your microservice origin doesn't match, add it to `LexiconSecurityConfig.java`
   - Use pattern format: `https://your-domain\.com` or `https://.*\.your-domain\.com`
3. **HTTPS Required:** All production API calls must use HTTPS (Cloudflare tunnel routing)
4. **Certificate Validation:** Cloudflare CA certificates are valid and auto-renewed
5. **Cookie Policy:** Cookies are sent only to same domain (Cloudflare subdomain origins)
6. **Authentication:** Always validate user session before processing requests
7. **DNS Resolution:** External devices must resolve alex-dyakin.com correctly
   - Local resolver: `8.8.8.8` (Google) or `1.1.1.1` (Cloudflare)
   - If ISP DNS is stale, manually update resolver
8. **Fallback:** If DNS fails, use PlayIt HTTP URLs as temporary workaround

## DNS Troubleshooting

If microservices can't resolve alex-dyakin.com:

**Check Local Resolution:**
```bash
dig alex-dyakin.com
dig alchemy.alex-dyakin.com
nslookup api.alex-dyakin.com
```

**Should return Cloudflare IPs (e.g., 104.21.42.152, 172.67.163.13):**
If returning old/different IP:
- ISP DNS cache is stale
- Switch to Google (8.8.8.8) or Cloudflare (1.1.1.1)
- On Linux: `sudo resolvectl dns [interface] 8.8.8.8 1.1.1.1`
- On router: Change DNS settings to 8.8.8.8
- Wait 5-10 minutes for propagation

**Temporary Fallback:**
```bash
# Use PlayIt IP directly while DNS updates
curl http://147.185.221.24:15856/api/health
```

## Contact & Support

For questions or issues with this API:
- Check logs: `tail -f /path/to/logs/lexicon.log`
- Verify CORS configuration in `LexiconSecurityConfig.java`
- Ensure session cookies are included in requests
- Check database connectivity: `curl http://localhost:9002`
- Use `/api/health` endpoint to verify API is running
- Test HTTPS tunnel: `curl https://api.alex-dyakin.com/api/health`
- Troubleshoot DNS: `dig alex-dyakin.com` (should return Cloudflare IPs)
- If DNS unresolved, use PlayIt fallback: `curl http://147.185.221.24:15856/api/health`

---

**Last Updated:** December 22, 2026 (Cloudflare HTTPS Deployment v2)  
**API Version:** 1.0  
**For Microservice Integration Team**
