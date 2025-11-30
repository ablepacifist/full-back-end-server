#!/bin/bash
# Import YouTube Music playlist to Lexicon
# Usage: ./import-youtube-playlist.sh <playlist_url>

set -e

# Configuration
LEXICON_API="http://localhost:36568"
ALCHEMY_API="http://localhost:8080"
USERNAME="zx"
PASSWORD="zx"
PLAYLIST_URL="$1"
COOKIES_FILE="/home/alex/Documents/lexicon/Lexicon/full-back-end-server/lexiconServer/cookies.txt"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$PLAYLIST_URL" ]; then
    echo -e "${RED}Error: Please provide a playlist URL${NC}"
    echo "Usage: $0 <youtube_playlist_url>"
    exit 1
fi

echo -e "${BLUE}=== YouTube Music Playlist Importer ===${NC}\n"

# Step 1: Login and get session cookie
echo -e "${BLUE}Step 1: Logging in as $USERNAME...${NC}"
LOGIN_RESPONSE=$(curl -s -c /tmp/lexicon_cookies.txt -X POST "$ALCHEMY_API/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

if [ $? -ne 0 ]; then
    echo -e "${RED}Login failed!${NC}"
    exit 1
fi

# Extract user ID from response
USER_ID=$(echo "$LOGIN_RESPONSE" | jq -r '.playerId // .id')
if [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ]; then
    echo -e "${RED}Could not extract user ID from login response${NC}"
    echo "Response: $LOGIN_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ Logged in successfully (User ID: $USER_ID)${NC}\n"

# Step 2: Get playlist information
echo -e "${BLUE}Step 2: Fetching playlist information...${NC}"
PLAYLIST_INFO=$(yt-dlp --cookies "$COOKIES_FILE" --dump-json --flat-playlist "$PLAYLIST_URL" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to fetch playlist information${NC}"
    exit 1
fi

# Get playlist title (from first entry)
PLAYLIST_TITLE=$(echo "$PLAYLIST_INFO" | head -1 | jq -r '.playlist_title // .playlist' | sed 's/null/Imported Playlist/')
PLAYLIST_COUNT=$(echo "$PLAYLIST_INFO" | wc -l)

echo -e "${GREEN}✓ Found playlist: ${PLAYLIST_TITLE}${NC}"
echo -e "${GREEN}✓ Number of tracks: ${PLAYLIST_COUNT}${NC}\n"

# Step 3: Create playlist in Lexicon
echo -e "${BLUE}Step 3: Creating playlist in Lexicon...${NC}"
CREATE_PLAYLIST_RESPONSE=$(curl -s -b /tmp/lexicon_cookies.txt -X POST "$LEXICON_API/api/playlists?userId=$USER_ID" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$PLAYLIST_TITLE\",\"description\":\"Imported from YouTube Music\",\"mediaType\":\"MUSIC\",\"isPublic\":true}")

PLAYLIST_ID=$(echo "$CREATE_PLAYLIST_RESPONSE" | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1)

if [ -z "$PLAYLIST_ID" ]; then
    echo -e "${RED}Failed to create playlist${NC}"
    echo "$CREATE_PLAYLIST_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ Playlist created (ID: $PLAYLIST_ID)${NC}\n"

# Step 4: Download and upload each track
echo -e "${BLUE}Step 4: Downloading and uploading tracks...${NC}"
TRACK_NUM=0
SUCCESSFUL=0
FAILED=0

while IFS= read -r entry; do
    TRACK_NUM=$((TRACK_NUM + 1))
    
    VIDEO_ID=$(echo "$entry" | jq -r '.id')
    TRACK_TITLE=$(echo "$entry" | jq -r '.title')
    VIDEO_URL="https://music.youtube.com/watch?v=$VIDEO_ID"
    
    echo -e "${YELLOW}[$TRACK_NUM/$PLAYLIST_COUNT] Processing: $TRACK_TITLE${NC}"
    
    # Upload via URL (let server handle download with yt-dlp)
    UPLOAD_RESPONSE=$(curl -s -b /tmp/lexicon_cookies.txt -X POST "$LEXICON_API/api/media/upload-from-url" \
        -F "url=$VIDEO_URL" \
        -F "userId=$USER_ID" \
        -F "title=$TRACK_TITLE" \
        -F "description=From playlist: $PLAYLIST_TITLE" \
        -F "isPublic=true" \
        -F "mediaType=MUSIC" \
        -F "downloadType=AUDIO_ONLY")
    
    if echo "$UPLOAD_RESPONSE" | grep -q '"id"'; then
        MEDIA_ID=$(echo "$UPLOAD_RESPONSE" | grep -o '"id":[0-9]*' | grep -o '[0-9]*' | head -1)
        
        # Add to playlist
        ADD_RESPONSE=$(curl -s -b /tmp/lexicon_cookies.txt -X POST "$LEXICON_API/api/playlists/$PLAYLIST_ID/items?userId=$USER_ID" \
            -H "Content-Type: application/json" \
            -d "{\"mediaFileId\":$MEDIA_ID}")
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✓ Uploaded and added to playlist${NC}"
            SUCCESSFUL=$((SUCCESSFUL + 1))
        else
            echo -e "${RED}  ✗ Failed to add to playlist${NC}"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "${RED}  ✗ Upload failed: $UPLOAD_RESPONSE${NC}"
        FAILED=$((FAILED + 1))
    fi
    
    # Small delay to avoid overwhelming the server
    sleep 2
    
done <<< "$PLAYLIST_INFO"

# Cleanup
rm -f /tmp/lexicon_cookies.txt

# Summary
echo -e "\n${BLUE}=== Import Complete ===${NC}"
echo -e "${GREEN}Successful: $SUCCESSFUL${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${BLUE}Playlist ID: $PLAYLIST_ID${NC}"
echo -e "${BLUE}Playlist URL: $LEXICON_API/playlist/$PLAYLIST_ID${NC}"
