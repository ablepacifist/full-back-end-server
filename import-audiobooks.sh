#!/bin/bash

# Audiobook Import Script for Lexicon
# This script monitors a directory for new audiobook files and uploads them to Lexicon
# Also creates playlists for detected series

WATCH_DIR="$HOME/audiobooks-import"
LEXICON_API="http://localhost:36568/api/media"
PLAYLIST_API="http://localhost:36568/api/playlists"
USER_ID=1  # Change this to your user ID

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Array to track uploaded files and series
declare -A UPLOADED_FILES
declare -A SERIES_MAP

echo -e "${GREEN}=== Lexicon Audiobook Importer ===${NC}"
echo "Watching directory: $WATCH_DIR"
echo "Lexicon API: $LEXICON_API"
echo ""

# Create watch directory if it doesn't exist
mkdir -p "$WATCH_DIR"

# Function to detect series name and book number
detect_series() {
    local filename="$1"
    local series_name=""
    local book_number=""
    
    # Common patterns: "Series Name, Book 1", "Series Name 1", "Series Name - Book 1"
    if [[ "$filename" =~ ([^,:-]+)[,:-]?[[:space:]]*(Book|Vol|Volume|Part|Episode)?[[:space:]]*([0-9]+) ]]; then
        series_name="${BASH_REMATCH[1]}"
        book_number="${BASH_REMATCH[3]}"
    fi
    
    # Clean up series name
    series_name=$(echo "$series_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    echo "${series_name}|${book_number}"
}

# Function to upload a file
upload_audiobook() {
    local file="$1"
    local filename=$(basename "$file")
    local title="${filename%.*}"  # Remove extension
    
    echo -e "${YELLOW}Uploading: $filename${NC}"
    
    # Detect series info
    local series_info=$(detect_series "$title")
    local series_name=$(echo "$series_info" | cut -d'|' -f1)
    local book_number=$(echo "$series_info" | cut -d'|' -f2)
    
    if [ -n "$series_name" ] && [ -n "$book_number" ]; then
        echo -e "  Detected series: ${BLUE}$series_name #$book_number${NC}"
    fi
    
    # Upload the file (with 20 minute timeout for very large files)
    response=$(curl --max-time 1200 -s -X POST "$LEXICON_API/upload" \
        -F "file=@$file" \
        -F "userId=$USER_ID" \
        -F "title=$title" \
        -F "description=Audiobook imported from OpenAudible" \
        -F "isPublic=true" \
        -F "mediaType=AUDIOBOOK")
    
    if echo "$response" | grep -q "\"success\":true"; then
        # Extract media file ID from response
        local media_id=$(echo "$response" | grep -oP '"id":\K[0-9]+' | head -1)
        
        echo -e "${GREEN}✓ Successfully uploaded: $title (ID: $media_id)${NC}"
        
        # Store in our tracking
        UPLOADED_FILES["$title"]=$media_id
        
        # Track series
        if [ -n "$series_name" ] && [ -n "$book_number" ]; then
            local series_key="${series_name}"
            SERIES_MAP["$series_key"]+="${media_id}:${book_number},"
        fi
        
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

# Function to create playlist for a series
create_series_playlist() {
    local series_name="$1"
    local media_ids="$2"
    
    echo -e "${BLUE}Creating playlist for series: $series_name${NC}"
    
    # Sort by book number and extract IDs
    local sorted_ids=$(echo "$media_ids" | tr ',' '\n' | grep -v '^$' | sort -t':' -k2 -n | cut -d':' -f1 | tr '\n' ',' | sed 's/,$//')
    
    # Create playlist
    local response=$(curl -s -X POST "$PLAYLIST_API" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$series_name\",
            \"description\": \"Audiobook series - auto-generated\",
            \"createdBy\": $USER_ID,
            \"isPublic\": true,
            \"mediaType\": \"AUDIOBOOK\",
            \"mediaFileIds\": [$sorted_ids]
        }")
    
    if echo "$response" | grep -q "\"success\":true"; then
        echo -e "${GREEN}✓ Created playlist: $series_name${NC}"
    else
        echo -e "${RED}✗ Failed to create playlist: $series_name${NC}"
        echo "  Response: $response"
    fi
    
    echo ""
}

# Check for existing files
echo "Checking for existing audiobook files..."
shopt -s nullglob
for ext in mp3 m4b m4a; do
    for file in "$WATCH_DIR"/*."$ext"; do
        if [ -f "$file" ]; then
            upload_audiobook "$file"
        fi
    done
done
shopt -u nullglob

echo -e "${GREEN}Initial scan complete!${NC}"
echo ""

# Create playlists for detected series
if [ ${#SERIES_MAP[@]} -gt 0 ]; then
    echo -e "${BLUE}=== Creating Series Playlists ===${NC}"
    for series in "${!SERIES_MAP[@]}"; do
        create_series_playlist "$series" "${SERIES_MAP[$series]}"
    done
fi

echo -e "${GREEN}=== Import Complete! ===${NC}"
echo "Uploaded: ${#UPLOADED_FILES[@]} audiobooks"
echo "Series detected: ${#SERIES_MAP[@]}"
echo ""
echo "You can:"
echo "  1. Copy more audiobook files to: $WATCH_DIR"
echo "  2. Configure OpenAudible to output to: $WATCH_DIR"
echo "  3. Run this script again to process new files"
echo ""
echo "To watch continuously, run:"
echo "  watch -n 30 $0"
