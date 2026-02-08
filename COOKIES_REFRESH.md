# YouTube Cookies Refresh Guide

## When Do Cookies Expire?

YouTube cookies typically expire after **a few days to a few weeks**. When they expire, any YouTube-related features (downloading from YouTube, importing playlists) will fail with authentication errors.

### Signs That Cookies Have Expired

- YouTube downloads fail with `ERROR: Sign in to confirm you're not a bot`
- yt-dlp returns HTTP 403 errors
- YouTube playlist imports fail
- Server logs show: `Unable to extract...` or `Login required` errors

---

## How to Refresh Cookies

### Step 1: Export Fresh Cookies from Your Browser

1. Open **Firefox** (or Chrome)
2. Go to [youtube.com](https://www.youtube.com) and make sure you are **logged in**
3. Use a cookies export extension:
   - **Firefox**: [cookies.txt](https://addons.mozilla.org/en-US/firefox/addon/cookies-txt/) extension
   - **Chrome**: [Get cookies.txt LOCALLY](https://chrome.google.com/webstore/detail/get-cookiestxt-locally/) extension
4. Navigate to YouTube, then click the extension and export cookies for `youtube.com`
5. Save the file as `cookies.txt`

### Step 2: Replace the Cookies File

```bash
# Copy the new cookies file to the LexiconServer directory
cp ~/Downloads/cookies.txt ~/Documents/lexicon/full-back-end-server/lexiconServer/cookies.txt
```

### Step 3: Verify It Works

```bash
# Test with yt-dlp directly
cd ~/Documents/lexicon/full-back-end-server/lexiconServer
yt-dlp --cookies cookies.txt --skip-download "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

If the test prints video info without errors, the cookies are working.

### Step 4: Restart the Server (if needed)

No restart needed — the server reads cookies.txt fresh on each download request.

---

## Automating / Reducing Cookie Expiry Issues

- **Use a dedicated Google account** for cookie extraction (not your main account)
- **Don't log out of YouTube** in the browser you exported from — logging out invalidates the session cookies
- **Set a calendar reminder** to refresh cookies every 1-2 weeks
- If cookies expire very quickly, YouTube may be flagging the account — try a different account

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Sign in to confirm you're not a bot` | Cookies expired — follow steps above |
| `Unable to extract uploader id` | Update yt-dlp: `pip install -U yt-dlp` |
| `HTTP Error 403: Forbidden` | Cookies expired OR IP is rate-limited — wait and try again |
| `cookies.txt` not found | Check the file path in `lexiconServer/cookies.txt` |
| Downloads work in browser but not yt-dlp | Re-export cookies — make sure you export for `youtube.com` domain |

---

## Quick Reference Command

```bash
# One-liner: copy cookies and test
cp ~/Downloads/cookies.txt ~/Documents/lexicon/full-back-end-server/lexiconServer/cookies.txt && \
cd ~/Documents/lexicon/full-back-end-server/lexiconServer && \
yt-dlp --cookies cookies.txt --skip-download "https://www.youtube.com/watch?v=dQw4w9WgXcQ" && \
echo "✅ Cookies are working!" || echo "❌ Cookies are NOT working"
```
