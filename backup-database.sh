#!/bin/bash
# Backup HSQLDB database files to GTW (remote PC on local network)
# Backs up metadata only - no media files (songs/videos)
#
# Usage: bash backup-database.sh
# Can be added to cron for scheduled backups:
#   0 3 * * * /home/alex/Documents/full-back-end-server/backup-database.sh

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_DIR="$BASE_DIR/alchemyServer"
REMOTE_USER="alex"
REMOTE_HOST="192.168.4.87"
REMOTE_DIR="/home/alex/lexicon-backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="lexicon_db_$TIMESTAMP"

echo "=== Lexicon Database Backup ==="
echo "Date: $(date)"
echo ""

# Issue a CHECKPOINT to flush the .log into .script for a consistent snapshot
echo "Flushing database to disk (CHECKPOINT)..."
java -cp /tmp:"$DB_DIR/../lexiconServer/lib/hsqldb.jar" Checkpoint 2>/dev/null \
    && echo "  CHECKPOINT OK" \
    || echo "  (CHECKPOINT skipped - DB may already be consistent)"

# Create a local temp directory for the backup
LOCAL_TMP="$BASE_DIR/.backup_tmp"
mkdir -p "$LOCAL_TMP/$BACKUP_NAME"

# Copy the essential DB files (skip .lck which is just a lock file)
echo "Copying database files..."
for ext in script properties log; do
    src="$DB_DIR/alchemydb.$ext"
    if [ -f "$src" ]; then
        cp "$src" "$LOCAL_TMP/$BACKUP_NAME/"
        echo "  alchemydb.$ext ($(du -sh "$src" | cut -f1))"
    fi
done

# Compress the backup
echo "Compressing..."
tar -czf "$LOCAL_TMP/$BACKUP_NAME.tar.gz" -C "$LOCAL_TMP" "$BACKUP_NAME"
BACKUP_SIZE=$(du -sh "$LOCAL_TMP/$BACKUP_NAME.tar.gz" | cut -f1)
echo "  Compressed size: $BACKUP_SIZE"

# Transfer to remote
echo "Transferring to $REMOTE_HOST..."
scp -q "$LOCAL_TMP/$BACKUP_NAME.tar.gz" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"
echo "  Saved to $REMOTE_HOST:$REMOTE_DIR/$BACKUP_NAME.tar.gz"

# Clean up local temp
rm -rf "$LOCAL_TMP"

# Clean up old backups on remote (keep last 30)
echo "Cleaning up old backups (keeping last 30)..."
ssh "$REMOTE_USER@$REMOTE_HOST" "cd $REMOTE_DIR && ls -1t lexicon_db_*.tar.gz 2>/dev/null | tail -n +31 | xargs -r rm --"

# Show remote backups
echo ""
echo "=== Backups on GTW ==="
ssh "$REMOTE_USER@$REMOTE_HOST" "ls -lh $REMOTE_DIR/lexicon_db_*.tar.gz 2>/dev/null | tail -5"

echo ""
echo "Backup complete!"
