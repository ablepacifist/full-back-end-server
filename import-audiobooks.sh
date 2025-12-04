#!/bin/bash

# Audiobook Import Script for Lexicon
# This script monitors a directory for new audiobook files and uploads them to Lexicon

WATCH_DIR="$HOME/audiobooks-import"
LEXICON_API="http://localhost:36568/api/media"
USER_ID=1  # Change this to your user ID

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Lexicon Audiobook Importer ===${NC}"
echo "Watching directory: $WATCH_DIR"
echo "Lexicon API: $LEXICON_API"
echo ""

# Create watch directory if it doesn't exist
mkdir -p "$WATCH_DIR"

# Function to upload a file
upload_audiobook() {
    local file="$1"
    local filename=$(basename "$file")
    local title="${filename%.*}"  # Remove extension
    
    echo -e "${YELLOW}Uploading: $filename${NC}"
    
    # Upload the file
    response=$(curl -s -X POST "$LEXICON_API/upload" \
        -F "file=@$file" \
        -F "uploadedBy=$USER_ID" \
        -F "title=$title" \
        -F "description=Audiobook imported from OpenAudible" \
        -F "isPublic=false" \
        -F "mediaType=MUSIC")
    
    if echo "$response" | grep -q "\"success\":true"; then
        echo -e "${GREEN}✓ Successfully uploaded: $title${NC}"
        
        # Move to processed folder
        mkdir -p "$WATCH_DIR/processed"
        mv "$file" "$WATCH_DIR/processed/"
        echo -e "  Moved to processed folder"
    else
        echo -e "${RED}✗ Failed to upload: $title${NC}"
        echo "  Response: $response"
        
        # Move to failed folder
        mkdir -p "$WATCH_DIR/failed"
        mv "$file" "$WATCH_DIR/failed/"
    fi
    
    echo ""
}

# Check for existing files
echo "Checking for existing audiobook files..."
for file in "$WATCH_DIR"/*.{mp3,m4b,m4a} 2>/dev/null; do
    if [ -f "$file" ]; then
        upload_audiobook "$file"
    fi
done

echo -e "${GREEN}Initial scan complete!${NC}"
echo ""
echo "You can:"
echo "  1. Copy audiobook files to: $WATCH_DIR"
echo "  2. Configure OpenAudible to output to: $WATCH_DIR"
echo "  3. Run this script again to process new files"
echo ""
echo "To watch continuously, run:"
echo "  watch -n 30 $0"
