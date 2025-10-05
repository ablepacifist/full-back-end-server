#!/bin/bash
echo "🛑 Stopping all Full Lexicon services..."

# Kill processes on our ports
for port in 9002 36567 36568 8080; do
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        echo "Stopping process on port $port"
        lsof -ti:$port | xargs kill -9 2>/dev/null || true
    fi
done

# Also try make stop-server for database
cd alchemyServer 2>/dev/null && make stop-server 2>/dev/null || true
cd ..

echo "✅ All services stopped"
