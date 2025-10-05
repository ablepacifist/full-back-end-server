#!/bin/bash

# Full Lexicon Development Startup Script
# This script starts the database, alchemy server, lexicon server, and gateway

echo "🚀 Starting Full Lexicon Development Environment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if a port is in use
check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null ; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_attempts=30
    local attempt=1
    
    echo -e "${YELLOW}Waiting for $service_name to be ready...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "$url" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ $service_name is ready!${NC}"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            echo -e "${RED}❌ $service_name failed to start after $max_attempts attempts${NC}"
            return 1
        fi
        
        echo -e "${YELLOW}⏳ Attempt $attempt/$max_attempts - $service_name not ready yet...${NC}"
        sleep 2
        ((attempt++))
    done
}

# Kill any existing processes on our ports
echo -e "${BLUE}🧹 Cleaning up any existing processes...${NC}"
for port in 9002 36567 36568 8080; do
    if check_port $port; then
        echo -e "${YELLOW}Killing process on port $port${NC}"
        lsof -ti:$port | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
done

# Step 1: Start HSQLDB Database Server using make
echo -e "${BLUE}📊 Starting HSQLDB Database Server on port 9002...${NC}"
cd alchemyServer
make start-server
sleep 5  # Give the database time to start
cd ..

if check_port 9002; then
    echo -e "${GREEN}✅ Database server started successfully${NC}"
else
    echo -e "${RED}❌ Failed to start database server${NC}"
    exit 1
fi

echo -e "${YELLOW}🎯 Database is ready! Now you can start the backend services manually.${NC}"
echo ""
echo -e "${GREEN}� Next Steps:${NC}"
echo -e "1. ${BLUE}Start Alchemy Server:${NC}"
echo -e "   cd alchemyServer && ./gradlew bootRun"
echo ""
echo -e "2. ${BLUE}Start Lexicon Server (in new terminal):${NC}"
echo -e "   cd lexiconServer && ./gradlew bootRun"
echo ""
echo -e "3. ${BLUE}Start Gateway (in new terminal):${NC}"
echo -e "   cd gateway && ./gradlew bootRun"
echo ""
echo -e "4. ${BLUE}Test everything (in new terminal):${NC}"
echo -e "   ./test-services.sh"
echo ""
echo -e "${YELLOW}� The database will keep running in the background.${NC}"
echo -e "${YELLOW}INFO: To stop the database: cd alchemyServer && make stop-server${NC}"

# Create a cleanup script
cat > stop-all.sh << 'EOF'
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
EOF

chmod +x stop-all.sh

echo -e "${GREEN}📝 Created stop-all.sh script to stop all services when needed.${NC}"
