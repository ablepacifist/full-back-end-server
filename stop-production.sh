#!/bin/bash
# Stop all production services

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Stopping all services...${NC}\n"

# Read PIDs from file
if [ -f ".pids" ]; then
    source .pids
    
    # Stop each service
    if [ ! -z "$FRONTEND_PID" ]; then
        echo -e "Stopping Frontend (PID: $FRONTEND_PID)..."
        kill $FRONTEND_PID 2>/dev/null && echo -e "${GREEN}✓ Frontend stopped${NC}" || echo -e "${RED}Frontend already stopped${NC}"
    fi
    
    if [ ! -z "$LEXICON_PID" ]; then
        echo -e "Stopping LexiconServer (PID: $LEXICON_PID)..."
        kill $LEXICON_PID 2>/dev/null && echo -e "${GREEN}✓ LexiconServer stopped${NC}" || echo -e "${RED}LexiconServer already stopped${NC}"
    fi
    
    if [ ! -z "$ALCHEMY_PID" ]; then
        echo -e "Stopping AlchemyServer (PID: $ALCHEMY_PID)..."
        kill $ALCHEMY_PID 2>/dev/null && echo -e "${GREEN}✓ AlchemyServer stopped${NC}" || echo -e "${RED}AlchemyServer already stopped${NC}"
    fi
    
    if [ ! -z "$DB_PID" ]; then
        echo -e "Stopping Database (PID: $DB_PID)..."
        kill $DB_PID 2>/dev/null && echo -e "${GREEN}✓ Database stopped${NC}" || echo -e "${RED}Database already stopped${NC}"
    fi
    
    # Remove PID file
    rm .pids
    
    echo -e "\n${GREEN}All services stopped${NC}"
else
    echo -e "${RED}No .pids file found${NC}"
    echo "Attempting to stop services by port..."
    
    # Kill processes on known ports
    for PORT in 3000 8080 36568 9002; do
        PID=$(lsof -ti:$PORT)
        if [ ! -z "$PID" ]; then
            echo "Killing process on port $PORT (PID: $PID)"
            kill $PID 2>/dev/null
        fi
    done
    
    echo -e "${GREEN}Done${NC}"
fi
