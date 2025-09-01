#!/bin/bash

echo "Testing OAuth flow..."
echo ""

# Generate PKCE parameters
VERIFIER=$(openssl rand -base64 32 | tr -d "=+/" | cut -c 1-43)
CHALLENGE=$(echo -n "$VERIFIER" | openssl dgst -sha256 -binary | openssl enc -base64 | tr -d "=+/" | cut -c 1-43)
STATE=$(openssl rand -hex 16)
PORT=52591
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"

echo "Generated PKCE parameters:"
echo "  Verifier: $VERIFIER"
echo "  Challenge: $CHALLENGE"
echo "  State: $STATE"
echo "  Port: $PORT"
echo ""

# Build authorization URL with code=true
AUTH_URL="https://claude.ai/oauth/authorize?code=true&client_id=${CLIENT_ID}&response_type=code&redirect_uri=http%3A%2F%2Flocalhost%3A${PORT}%2Fcallback&scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference&code_challenge=${CHALLENGE}&code_challenge_method=S256&state=${STATE}"

echo "Authorization URL:"
echo "$AUTH_URL"
echo ""
echo "Open this URL in your browser and approve the request."
echo "After approval, check what URL you're redirected to."
echo ""
echo "The redirect URL should contain a 'code' parameter."
echo "Enter the authorization code from the redirect URL:"
read CODE

echo ""
echo "Testing token exchange with received code..."
echo ""

# Test token exchange
RESPONSE=$(curl -X POST https://console.anthropic.com/v1/oauth/token \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" \
  -H "Origin: https://claude.ai" \
  -H "Referer: https://claude.ai/" \
  -d "{
    \"grant_type\": \"authorization_code\",
    \"code\": \"$CODE\",
    \"redirect_uri\": \"http://localhost:${PORT}/callback\",
    \"code_verifier\": \"$VERIFIER\",
    \"client_id\": \"$CLIENT_ID\"
  }" \
  -w "\nHTTP_STATUS:%{http_code}" \
  2>/dev/null)

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS:/d')

echo "Response status: $HTTP_STATUS"
echo "Response body:"
echo "$BODY" | jq . 2>/dev/null || echo "$BODY"