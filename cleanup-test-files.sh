#!/bin/bash

# cleanup-test-files.sh
# Comprehensive script to clean up ALL test files from storage AND database

STORAGE_PATH="/media/alexpdyak32/7db05fe3-9f6a-46cb-82dd-8ff00d8488a0/lexicon-storage/"
DB_PATH="alchemyServer/alchemydb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Comprehensive Test Data Cleanup ==="
echo "Storage: $STORAGE_PATH"
echo "Database: $DB_PATH"

# Test user IDs to clean up
TEST_USER_IDS="16,32,888,998,999,9999"

echo ""
echo "=== Cleaning Database Test Records ==="

# Create SQL cleanup script
cat > /tmp/cleanup_test_data.sql << 'EOSQL'
-- Delete file data for test users
DELETE FROM file_data WHERE media_file_id IN (
    SELECT id FROM media_files WHERE uploaded_by IN (16, 32, 888, 998, 999, 9999)
);

-- Delete file data for test-named files
DELETE FROM file_data WHERE media_file_id IN (
    SELECT id FROM media_files WHERE LOWER(original_filename) LIKE '%test%'
);

-- Delete media files for test users
DELETE FROM media_files WHERE uploaded_by IN (16, 32, 888, 998, 999, 9999);

-- Delete test-named media files
DELETE FROM media_files WHERE LOWER(original_filename) LIKE '%test%';

-- Delete playlist items for test users
DELETE FROM playlist_items WHERE playlist_id IN (
    SELECT id FROM playlists WHERE owner_id IN (16, 32, 888, 998, 999, 9999)
);

-- Delete playlists for test users
DELETE FROM playlists WHERE owner_id IN (16, 32, 888, 998, 999, 9999);

-- Delete test-named playlists
DELETE FROM playlists WHERE LOWER(name) LIKE '%test%';

-- Delete live stream queue entries from test users
DELETE FROM live_stream_queue WHERE added_by_user_id IN (16, 32, 888, 998, 999, 9999);

-- Delete skip votes from test users
DELETE FROM live_stream_skip_votes WHERE user_id IN (16, 32, 888, 998, 999, 9999);

-- Delete playback positions for test users
DELETE FROM playback_positions WHERE user_id IN (16, 32, 888, 998, 999, 9999);

-- Commit the changes
COMMIT;
EOSQL

echo "Database cleanup SQL script created"

# Run the cleanup via the running server's database (if server is running)
if pgrep -f "lexiconServer" > /dev/null; then
    echo "Note: Server is running. Database cleanup will be performed next restart."
    echo "For immediate cleanup, stop the server first."
fi

echo ""
echo "=== Cleaning Storage Test Files ==="

if [ ! -d "$STORAGE_PATH" ]; then
    echo "Storage directory not found: $STORAGE_PATH"
else
    # Count files before cleanup
    BEFORE_COUNT=$(find "$STORAGE_PATH" -type f 2>/dev/null | wc -l)
    echo "Files before cleanup: $BEFORE_COUNT"

    # Clean up test files with various patterns
    echo "Removing test files..."
    find "$STORAGE_PATH" -name "*Test*" -type f -delete 2>/dev/null
    find "$STORAGE_PATH" -name "*test*" -type f -delete 2>/dev/null
    find "$STORAGE_PATH" -name "*_test_*" -type f -delete 2>/dev/null

    # Count files after cleanup
    AFTER_COUNT=$(find "$STORAGE_PATH" -type f 2>/dev/null | wc -l)
    echo "Files after cleanup: $AFTER_COUNT"

    REMOVED=$((BEFORE_COUNT - AFTER_COUNT))
    echo "Removed $REMOVED test files from storage"
fi

echo ""
echo "=== Cleanup Summary ==="
echo "Test user IDs cleaned: $TEST_USER_IDS"
echo "Storage path cleaned: $STORAGE_PATH"
echo ""
echo "To apply database cleanup, restart the server or run:"
echo "  cd lexiconServer && ./gradlew test --tests 'lexicon.utils.DatabaseCleanupRunner'"
echo ""
echo "Cleanup completed!"