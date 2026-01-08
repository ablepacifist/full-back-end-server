#!/bin/bash

echo "=========================================="
echo "DATABASE RESET SCRIPT"
echo "This will DELETE ALL DATA including:"
echo "  - All users"
echo "  - All media files"
echo "  - All playlists"
echo "  - All game data"
echo "=========================================="
echo ""
read -p "Are you sure you want to continue? Type 'YES' to confirm: " confirmation

if [ "$confirmation" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Stopping all servers..."
pkill -9 -f "java.*alchemy.Main" 2>/dev/null
pkill -9 -f "java.*lexicon.LexiconApplication" 2>/dev/null
pkill -f "npx serve.*3001" 2>/dev/null
sleep 3

echo "Removing old database files..."
cd /home/alexpdyak32/Documents/lexicon/full-back-end-server/alchemyServer

# Backup just in case
if [ -f alchemydb.script ]; then
    echo "Creating backup..."
    mkdir -p ../database-backups
    timestamp=$(date +%Y%m%d_%H%M%S)
    cp alchemydb.script ../database-backups/alchemydb.script.$timestamp
    cp alchemydb.properties ../database-backups/alchemydb.properties.$timestamp
    echo "Backup saved to ../database-backups/"
fi

# Remove all database files
rm -f alchemydb.lck
rm -f alchemydb.log
rm -f alchemydb.script
rm -f alchemydb.properties
echo "Deleting 49GB lobs file (this may take a moment)..."
rm -f alchemydb.lobs
rm -rf alchemydb.tmp

echo ""
echo "Database files removed successfully!"
echo ""
echo "Restarting all servers..."
cd /home/alexpdyak32/Documents/lexicon/full-back-end-server
bash restart-all.sh

echo ""
echo "=========================================="
echo "Database has been reset!"
echo "You can now register new users and upload fresh media."
echo "=========================================="
