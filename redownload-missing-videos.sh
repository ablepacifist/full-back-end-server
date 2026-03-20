#!/bin/bash
# Re-download missing videos from YouTube and update database
# These videos have metadata in the DB but no file data (empty filePath, no blob)

set -euo pipefail

STORAGE_DIR="/media/alex/lexicon-hdd/lexicon-storage/videos/original"
HSQLDB_JAR="/home/alex/Documents/full-back-end-server/lexiconServer/lib/hsqldb.jar"
DB_URL="jdbc:hsqldb:hsql://localhost:9002/mydb"
COOKIES_FILE="/home/alex/Documents/full-back-end-server/cookies.txt"
MISSING_LIST="/tmp/missing_videos.txt"
LOG_FILE="/tmp/redownload-videos.log"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$STORAGE_DIR"

# Generate missing videos list from database
echo -e "${BLUE}Generating list of missing videos from database...${NC}"
cat > /tmp/GetMissingVideos.java << 'JAVAEOF'
import java.sql.*;
public class GetMissingVideos {
    public static void main(String[] args) throws Exception {
        Connection conn = DriverManager.getConnection(args[0], "SA", "");
        Statement stmt = conn.createStatement();
        ResultSet rs = stmt.executeQuery(
            "SELECT mf.id, mf.source_url, mf.title FROM media_files mf " +
            "WHERE mf.media_type = 'VIDEO' AND (mf.file_path IS NULL OR mf.file_path = '') " +
            "AND mf.id NOT IN (SELECT media_file_id FROM file_data) " +
            "ORDER BY mf.id");
        while (rs.next()) {
            System.out.println(rs.getInt(1) + "|" + rs.getString(2) + "|" + rs.getString(3));
        }
        conn.close();
    }
}
JAVAEOF
javac -cp "$HSQLDB_JAR" /tmp/GetMissingVideos.java -d /tmp
java -cp "/tmp:$HSQLDB_JAR" GetMissingVideos "$DB_URL" > "$MISSING_LIST"

TOTAL=$(wc -l < "$MISSING_LIST")
echo -e "${BLUE}Found ${TOTAL} videos to re-download${NC}"
echo ""

# Update DB filePath helper
cat > /tmp/UpdateFilePath.java << 'JAVAEOF'
import java.sql.*;
public class UpdateFilePath {
    public static void main(String[] args) throws Exception {
        int id = Integer.parseInt(args[1]);
        String filePath = args[2];
        long fileSize = Long.parseLong(args[3]);
        Connection conn = DriverManager.getConnection(args[0], "SA", "");
        PreparedStatement stmt = conn.prepareStatement(
            "UPDATE media_files SET file_path = ?, file_size = ? WHERE id = ?");
        stmt.setString(1, filePath);
        stmt.setLong(2, fileSize);
        stmt.setInt(3, id);
        int rows = stmt.executeUpdate();
        System.out.println("Updated " + rows + " row(s)");
        conn.close();
    }
}
JAVAEOF
javac -cp "$HSQLDB_JAR" /tmp/UpdateFilePath.java -d /tmp

SUCCESSFUL=0
FAILED=0
SKIPPED=0
COUNT=0

# Build yt-dlp cookie args
COOKIE_ARGS=""
if [ -f "$COOKIES_FILE" ]; then
    COOKIE_ARGS="--cookies $COOKIES_FILE"
fi

while IFS='|' read -r ID URL TITLE; do
    COUNT=$((COUNT + 1))
    
    # Skip if file already exists for this ID
    EXISTING=$(find "$STORAGE_DIR" -name "*_id${ID}_*" -o -name "*_id${ID}.*" 2>/dev/null | head -1)
    if [ -n "$EXISTING" ]; then
        echo -e "${YELLOW}[$COUNT/$TOTAL] SKIP (already exists): $TITLE${NC}"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    echo -e "${BLUE}[$COUNT/$TOTAL] Downloading: $TITLE${NC}"
    echo -e "  URL: $URL"
    
    # Download with yt-dlp
    OUTPUT_TEMPLATE="${STORAGE_DIR}/%(id)s_id${ID}.%(ext)s"
    
    if yt-dlp \
        $COOKIE_ARGS \
        -f "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080][ext=mp4]/best" \
        --merge-output-format mp4 \
        --no-playlist \
        -o "$OUTPUT_TEMPLATE" \
        "$URL" >> "$LOG_FILE" 2>&1; then
        
        # Find the downloaded file
        DOWNLOADED=$(find "$STORAGE_DIR" -name "*_id${ID}.*" -newer "$MISSING_LIST" 2>/dev/null | head -1)
        
        if [ -n "$DOWNLOADED" ] && [ -f "$DOWNLOADED" ]; then
            FILENAME=$(basename "$DOWNLOADED")
            FILESIZE=$(stat -c%s "$DOWNLOADED")
            RELPATH="videos/original/$FILENAME"
            
            # Update database
            if java -cp "/tmp:$HSQLDB_JAR" UpdateFilePath "$DB_URL" "$ID" "$RELPATH" "$FILESIZE" >> "$LOG_FILE" 2>&1; then
                echo -e "${GREEN}  ✓ Downloaded ($(( FILESIZE / 1024 / 1024 ))MB) → $RELPATH${NC}"
                SUCCESSFUL=$((SUCCESSFUL + 1))
            else
                echo -e "${RED}  ✗ Downloaded but DB update failed${NC}"
                FAILED=$((FAILED + 1))
            fi
        else
            echo -e "${RED}  ✗ Download completed but file not found${NC}"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "${RED}  ✗ Download failed (check $LOG_FILE)${NC}"
        FAILED=$((FAILED + 1))
    fi
    
    # Brief pause between downloads
    sleep 1
    
done < "$MISSING_LIST"

echo ""
echo -e "${BLUE}=== Re-download Complete ===${NC}"
echo -e "${GREEN}Successful: $SUCCESSFUL${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Skipped: $SKIPPED${NC}"
echo -e "${BLUE}Total: $TOTAL${NC}"
echo -e "${BLUE}Log file: $LOG_FILE${NC}"
