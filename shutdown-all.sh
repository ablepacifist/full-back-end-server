#!/bin/bash

echo "Shutting down all Lexicon services..."

# Kill Lexicon server
echo "  - Stopping Lexicon server..."
pkill -9 -f "java.*lexicon.LexiconApplication" 2>/dev/null

# Kill Alchemy server
echo "  - Stopping Alchemy server..."
pkill -9 -f "java.*alchemy.Main" 2>/dev/null

# Kill Gradle daemons for this project
echo "  - Stopping Gradle processes..."
pkill -9 -f "gradle.*lexiconServer" 2>/dev/null
pkill -9 -f "gradle.*alchemyServer" 2>/dev/null

# Kill frontend server
echo "  - Stopping Frontend server..."
pkill -9 -f "npx serve.*3001" 2>/dev/null
pkill -9 -f "npm exec serve.*3001" 2>/dev/null
pkill -9 -f "node.*serve.*3001" 2>/dev/null
pkill -9 -f "serve -s build -l 3001" 2>/dev/null

# Kill HSQLDB server if running
echo "  - Stopping HSQLDB server..."
pkill -9 -f "org.hsqldb.server.Server" 2>/dev/null

sleep 1

echo ""
echo "All services stopped!"
echo ""
echo "Checking for any remaining processes..."
remaining=$(ps aux | grep -E "lexicon|alchemy|serve.*3001" | grep -v grep | grep -v shutdown)

if [ -z "$remaining" ]; then
    echo "✓ All services successfully stopped"
else
    echo "⚠ Some processes may still be running:"
    echo "$remaining"
fi
