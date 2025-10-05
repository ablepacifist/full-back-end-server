#!/bin/bash

# Quick test script to verify all services are working
echo "Testing Full Lexicon Services..."

echo "Testing Gateway health..."
curl -s http://localhost:8080/api/gateway/health | jq . || echo "Gateway not responding"

echo -e "\nTesting Alchemy through gateway..."
curl -s http://localhost:8080/api/alchemy/health | jq . || echo "Alchemy not responding"

echo -e "\nTesting Lexicon through gateway..."
curl -s http://localhost:8080/api/lexicon/health | jq . || echo "Lexicon not responding"

echo -e "\nTesting direct Alchemy service..."
curl -s http://localhost:36567/api/health | jq . || echo "Direct Alchemy not responding"

echo -e "\nTesting direct Lexicon service..."
curl -s http://localhost:36568/api/health | jq . || echo "Direct Lexicon not responding"

echo -e "\nCOMPLETED: Service test completed!"
