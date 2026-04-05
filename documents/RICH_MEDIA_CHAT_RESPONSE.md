# Rich Media Chat — Implementation Complete (Lexicon Backend)

**Date:** June 2025  
**From:** Lexicon Team  
**To:** Mumble Bridge Team  

---

## Summary

We have implemented all requested backend features for rich media chat support. The Lexicon backend now supports image/GIF uploads for chat, file serving with thumbnails, and extended message responses with inline attachment metadata.

---

## What Was Implemented

### 1. Chat File Upload Endpoint

```
POST /api/chat/upload
Content-Type: multipart/form-data
```

**Fields:** `file` (image), `userId` (int), `channelId` (int)

- Accepts: `image/jpeg`, `image/png`, `image/gif`, `image/webp`
- Max file size: **8 MB**
- Automatically generates thumbnails (max 400px wide, JPEG)
- GIFs are preserved as-is (no static conversion)
- Returns dimensions (`width`, `height`) for frontend sizing
- Files stored on disk under `chat-uploads/` with generated filenames

**Response:**
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

### 2. Chat File Serving Endpoints

```
GET /api/chat/files/{fileId}       → Original file (correct Content-Type)
GET /api/chat/files/{fileId}/thumb → Thumbnail (JPEG, max 400px wide)
```

- `Cache-Control: public, max-age=31536000` (immutable once uploaded)
- Returns `404` if file doesn't exist

### 3. Extended Message Types

The existing `POST /api/messages` endpoint now supports these additional message types:

| Type | Description |
|---|---|
| `IMAGE` | Message with uploaded image attachment |
| `GIF` | Message with uploaded GIF attachment |
| `MIXED` | Text + attachment(s) |

When `messageType` is `IMAGE`, `GIF`, or `MIXED`, set `mediaFileId` to the ID returned from `POST /api/chat/upload`.

### 4. Attachment Data in Message Responses

When fetching messages via `GET /api/messages/channel/{channelId}` (or `GET /api/messages/{id}`, or search), messages with image/GIF types now include an `attachment` object:

```json
{
  "id": 501,
  "channelId": 1,
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
  "createdAt": "2026-04-03T12:00:00"
}
```

For plain `TEXT` messages, `attachment` is `null`.

### 5. Database Schema

Added `chat_files` table in HSQLDB to persist uploaded file metadata (original filename, stored filename, MIME type, dimensions, thumbnail reference, uploader, channel, timestamps).

---

## What the Bridge Team Needs To Do

### 1. Add `uploadChatFile()` to `lexicon-client.js`

Upload images to Lexicon via multipart POST:

```javascript
async uploadChatFile(fileBuffer, filename, mimeType, userId, channelId) {
  const FormData = require('form-data');
  const form = new FormData();
  form.append('file', fileBuffer, { filename, contentType: mimeType });
  form.append('userId', String(userId));
  form.append('channelId', String(channelId));

  const res = await fetch(`${this.baseUrl}/api/chat/upload`, {
    method: 'POST',
    body: form,
    headers: form.getHeaders(),
  });
  return res.json();
}
```

**Dependency:** `npm install form-data`

### 2. Add Upload Proxy Endpoint (if needed)

If the browser cannot reach Lexicon directly, proxy uploads through the bridge's HTTP server:

```
POST /api/chat/upload  →  forward to Lexicon's POST /api/chat/upload
```

### 3. Handle `image` Message Type in WebSocket

When a user sends an image via the bridge UI:
1. Upload to `POST /api/chat/upload` → get file ID and URLs
2. Store message to `POST /api/messages` with `messageType: "IMAGE"` (or `"GIF"`) and `mediaFileId` set
3. Broadcast to channel with file metadata for inline rendering
4. Send text fallback to Mumble (Mumble doesn't render images)

### 4. Render Attachments in Chat History

Messages returned by `GET /api/messages/channel/{channelId}` now include `attachment` data. Render `<img>` tags using `attachment.thumbnailUrl` for inline preview and `attachment.url` for full-size on click.

### 5. Frontend Upload UI

Add a file attachment button to the chat input. Validate on client side:
- Max 8 MB
- Only `image/jpeg`, `image/png`, `image/gif`, `image/webp`

---

## API Base URL

- **Local:** `http://localhost:36568`
- **Production:** `https://api.alex-dyakin.com`

Full API documentation updated in `documents/API_DOCUMENTATION.md`.

---

## Questions?

If you need any changes to the response format, additional endpoints, or different constraints, let us know.
