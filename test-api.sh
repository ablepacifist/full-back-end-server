#!/bin/bash

# Comprehensive API test script
echo "Testing Full Lexicon API Functionality..."
echo "=================================================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "\n${BLUE}1. Testing Gateway Info${NC}"
curl -s http://localhost:8080/api/gateway/health | jq .

echo -e "\n${BLUE}2. Testing Lexicon Service Info${NC}"
curl -s http://localhost:8080/api/lexicon/info | jq .

echo -e "\n${BLUE}3. Testing User Registration${NC}"
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:8080/api/lexicon/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser_'$(date +%s)'",
    "password": "password123",
    "email": "test'$(date +%s)'@example.com",
    "displayName": "Test User"
  }')
echo "$REGISTER_RESPONSE" | jq .

# Extract user ID for further tests
USER_ID=$(echo "$REGISTER_RESPONSE" | jq -r '.id // empty')

if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
    echo -e "\n${GREEN}✅ User registered successfully with ID: $USER_ID${NC}"
    
    echo -e "\n${BLUE}4. Testing User Login${NC}"
    USERNAME=$(echo "$REGISTER_RESPONSE" | jq -r '.username')
    LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8080/api/lexicon/auth/login \
      -H "Content-Type: application/json" \
      -d '{
        "username": "'$USERNAME'",
        "password": "password123"
      }')
    echo "$LOGIN_RESPONSE" | jq .
    
    echo -e "\n${BLUE}5. Testing Get All Players${NC}"
    curl -s http://localhost:8080/api/lexicon/players | jq '. | length' | xargs echo "Total players:"
    
    echo -e "\n${BLUE}6. Testing Get Player by ID${NC}"
    curl -s http://localhost:8080/api/lexicon/players/$USER_ID | jq .
    
    echo -e "\n${BLUE}7. Testing Get Public Media Files${NC}"
    curl -s http://localhost:8080/api/lexicon/media/public | jq '. | length' | xargs echo "Public media files:"
    
    echo -e "\n${BLUE}8. Testing Get User's Media Files${NC}"
    curl -s http://localhost:8080/api/lexicon/media/user/$USER_ID | jq '. | length' | xargs echo "User's media files:"
    
    echo -e "\n${BLUE}9. Testing Media Search${NC}"
    curl -s "http://localhost:8080/api/lexicon/media/search?q=test" | jq '. | length' | xargs echo "Search results:"
    
    echo -e "\n${BLUE}10. Testing Recent Media${NC}"
    curl -s "http://localhost:8080/api/lexicon/media/recent?limit=5" | jq '. | length' | xargs echo "Recent media files:"
    
else
    echo -e "\n${YELLOW}WARNING: User registration failed, skipping user-specific tests${NC}"
fi

echo -e "\n${BLUE}11. Testing Alchemy API through Gateway${NC}"
echo "Getting alchemy players through gateway:"
curl -s http://localhost:8080/api/alchemy/players | jq '. | length' | xargs echo "Alchemy players:"

echo -e "\n${GREEN}COMPLETED: Comprehensive API test completed!${NC}"
echo ""
echo -e "${YELLOW}INFO: Next steps to test:${NC}"
echo "- File upload: Use a REST client to POST a file to /api/lexicon/media/upload"
echo "- Frontend integration: Connect your React app to http://localhost:8080"
echo "- Cross-service auth: Use the same login for both Alchemy and Lexicon"
