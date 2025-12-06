#!/bin/bash
# Restart all services - stops and starts everything

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Restarting Full Back-End Server...${NC}\n"

# Get base directory
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Set CORS origins for production (PlayIt tunnel URLs)
# Include all possible origins: hostnames, IPs, with/without ports
export CORS_ALLOWED_ORIGINS="http://lexicon.playit.pub:58938,https://lexicon.playit.pub:58938,http://147.185.221.211:58938,https://147.185.221.211:58938,http://gets-nintendo.gl.at.ply.gg:9675,https://gets-nintendo.gl.at.ply.gg:9675,http://147.185.221.224:9675,http://award-kirk.gl.at.ply.gg:9686,https://award-kirk.gl.at.ply.gg:9686,http://localhost:3001,http://localhost:3000"

# Stop all services first
echo -e "${RED}Stopping all services...${NC}"
pkill -f "org.hsqldb.server.Server"
pkill -f "gradlew.*bootRun"
pkill -f "serve.*build"
sleep 3

# Create logs directory
mkdir -p "$BASE_DIR/logs"

# Start HSQLDB
echo -e "\n${BLUE}Starting HSQLDB...${NC}"
cd "$BASE_DIR/hsqldb"
nohup java -cp hsqldb.jar org.hsqldb.server.Server \
    --database.0 file:mydb \
    --dbname.0 mydb \
    --port 9002 > "$BASE_DIR/logs/database.log" 2>&1 &
DB_PID=$!
echo -e "${GREEN}Database started (PID: $DB_PID)${NC}"

# Wait for database to be ready
echo "Waiting for database..."
sleep 3

# Start AlchemyServer
echo -e "\n${BLUE}Starting AlchemyServer...${NC}"
cd "$BASE_DIR/alchemyServer"
nohup ./gradlew bootRun > "$BASE_DIR/logs/alchemy.log" 2>&1 &
ALCHEMY_PID=$!
echo -e "${GREEN}AlchemyServer started (PID: $ALCHEMY_PID)${NC}"

# Wait for alchemy to start
sleep 5

# Start LexiconServer with increased heap memory for large file uploads
echo -e "\n${BLUE}Starting LexiconServer...${NC}"
cd "$BASE_DIR/lexiconServer"
nohup ./gradlew bootRun -Dorg.gradle.jvmargs="-Xmx2g -Xms512m" > "$BASE_DIR/logs/lexicon.log" 2>&1 &
LEXICON_PID=$!
echo -e "${GREEN}LexiconServer started (PID: $LEXICON_PID)${NC}"

# Wait for lexicon to start
sleep 5

# Start Frontend
echo -e "\n${BLUE}Starting Frontend...${NC}"
cd "$BASE_DIR/Lexicon"
if [ ! -d "build" ]; then
    echo "Building React app..."
    npm run build
fi

nohup npx serve -s build -l 3001 > "$BASE_DIR/logs/frontend.log" 2>&1 &
FRONTEND_PID=$!
echo -e "${GREEN}Frontend started (PID: $FRONTEND_PID)${NC}"

sleep 3

echo -e "\n${GREEN}=== All services started! ===${NC}"
echo -e "\n${BLUE}Local URLs:${NC}"
echo "  Frontend:       http://localhost:3001"
echo "  AlchemyServer:  http://localhost:8080"
echo "  LexiconServer:  http://localhost:36568"
echo "  Database:       localhost:9002"

echo -e "\n${BLUE}PlayIt.gg Tunnel URLs:${NC}"
echo "  Frontend:       http://lexicon.playit.pub:58938"
echo "  AlchemyServer:  http://gets-nintendo.gl.at.ply.gg:9675"
echo "  LexiconServer:  http://award-kirk.gl.at.ply.gg:9686"

echo -e "\n${BLUE}Check logs:${NC}"
echo "  tail -f logs/database.log"
echo "  tail -f logs/alchemy.log"
echo "  tail -f logs/lexicon.log"
echo "  tail -f logs/frontend.log"

# Save PIDs for stop script
echo "DB_PID=$DB_PID" > "$BASE_DIR/.pids"
echo "ALCHEMY_PID=$ALCHEMY_PID" >> "$BASE_DIR/.pids"
echo "LEXICON_PID=$LEXICON_PID" >> "$BASE_DIR/.pids"
echo "FRONTEND_PID=$FRONTEND_PID" >> "$BASE_DIR/.pids"
