#!/bin/bash
# Start all services in production mode

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Full Back-End Server - Production Mode${NC}\n"

# Check if required environment variables are set
if [ -z "$CORS_ALLOWED_ORIGINS" ]; then
    echo -e "${RED}ERROR: CORS_ALLOWED_ORIGINS not set${NC}"
    echo "Please export your playit.gg frontend URL:"
    echo "export CORS_ALLOWED_ORIGINS=https://your-frontend.playit.gg"
    exit 1
fi

echo -e "${GREEN}CORS Origins: $CORS_ALLOWED_ORIGINS${NC}\n"

# Function to check if port is in use
check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null ; then
        echo -e "${RED}Port $1 is already in use${NC}"
        return 1
    fi
    return 0
}

# Check ports
echo "Checking ports..."
check_port 9002 || exit 1
check_port 8080 || exit 1
check_port 36568 || exit 1
check_port 3000 || exit 1

echo -e "${GREEN}All ports available${NC}\n"

# Create logs directory
mkdir -p logs

# Start HSQLDB
echo -e "${BLUE}Starting HSQLDB...${NC}"
cd "$(dirname "$0")"
if [ ! -d "hsqldb" ]; then
    echo -e "${RED}HSQLDB directory not found${NC}"
    echo "Please ensure HSQLDB is installed"
    exit 1
fi

# Start database in background
cd hsqldb
nohup java -cp hsqldb.jar org.hsqldb.server.Server \
    --database.0 file:mydb \
    --dbname.0 mydb \
    --port 9002 > ../logs/database.log 2>&1 &
DB_PID=$!
echo -e "${GREEN}Database started (PID: $DB_PID)${NC}"
cd ..

# Wait for database to be ready
echo "Waiting for database..."
sleep 3

# Start alchemyServer
echo -e "\n${BLUE}Starting AlchemyServer...${NC}"
cd alchemyServer
nohup ./gradlew bootRun --args='--spring.profiles.active=production' \
    > ../logs/alchemy.log 2>&1 &
ALCHEMY_PID=$!
echo -e "${GREEN}AlchemyServer started (PID: $ALCHEMY_PID)${NC}"
cd ..

# Wait for alchemy to start
sleep 5

# Start lexiconServer
echo -e "\n${BLUE}Starting LexiconServer...${NC}"
cd lexiconServer
nohup ./gradlew bootRun --args='--spring.profiles.active=production' \
    > ../logs/lexicon.log 2>&1 &
LEXICON_PID=$!
echo -e "${GREEN}LexiconServer started (PID: $LEXICON_PID)${NC}"
cd ..

# Wait for lexicon to start
sleep 5

# Start frontend
echo -e "\n${BLUE}Starting Frontend...${NC}"
cd Lexicon
if [ ! -d "build" ]; then
    echo "Building React app..."
    npm run build
fi

nohup npx serve -s build -l 3000 > ../logs/frontend.log 2>&1 &
FRONTEND_PID=$!
echo -e "${GREEN}Frontend started (PID: $FRONTEND_PID)${NC}"
cd ..

# Save PIDs to file for easy stopping
cat > .pids << EOF
DB_PID=$DB_PID
ALCHEMY_PID=$ALCHEMY_PID
LEXICON_PID=$LEXICON_PID
FRONTEND_PID=$FRONTEND_PID
EOF

echo -e "\n${GREEN}✓ All services started!${NC}\n"
echo "Service URLs:"
echo "  Frontend:  http://localhost:3000"
echo "  Alchemy:   http://localhost:8080"
echo "  Lexicon:   http://localhost:36568"
echo "  Database:  localhost:9002"
echo ""
echo "Logs are in: ./logs/"
echo ""
echo "To stop all services, run: ./stop-production.sh"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Start playit.gg tunnels for ports 3000, 8080, and 36568"
echo "2. Access your app via the playit.gg frontend tunnel URL"
