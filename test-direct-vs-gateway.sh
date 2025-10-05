#!/bin/bash

echo "Testing Gateway vs Direct Access..."

echo "1. Testing registration DIRECTLY to Lexicon server:"
DIRECT_RESPONSE=$(curl -s -X POST http://localhost:36568/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "directtest_'$(date +%s)'",
    "password": "password123",
    "email": "direct@test.com",
    "displayName": "Direct Test"
  }')
echo "$DIRECT_RESPONSE" | jq .

echo -e "\n2. Testing registration THROUGH GATEWAY:"
GATEWAY_RESPONSE=$(curl -s -X POST http://localhost:8080/api/lexicon/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "gatewaytest_'$(date +%s)'",
    "password": "password123", 
    "email": "gateway@test.com",
    "displayName": "Gateway Test"
  }')
echo "$GATEWAY_RESPONSE" | jq .

echo -e "\n3. Testing login DIRECTLY:"
DIRECT_LOGIN=$(curl -s -X POST http://localhost:36568/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser123",
    "password": "password123"
  }')
echo "$DIRECT_LOGIN" | jq .

echo -e "\n4. Testing login THROUGH GATEWAY:"
GATEWAY_LOGIN=$(curl -s -X POST http://localhost:8080/api/lexicon/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser123",
    "password": "password123"
  }')
echo "$GATEWAY_LOGIN" | jq .

echo -e "\n5. Comparison:"
if echo "$DIRECT_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    echo "✅ Direct registration: SUCCESS"
else
    echo "❌ Direct registration: FAILED"
fi

if echo "$GATEWAY_RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    echo "✅ Gateway registration: SUCCESS"
else
    echo "❌ Gateway registration: FAILED"
fi
