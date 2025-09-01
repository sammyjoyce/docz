#!/bin/bash

echo "Complete OAuth Flow Test"
echo "========================"
echo ""

# Generate PKCE parameters
VERIFIER=$(openssl rand -base64 64 | tr -d "=+/\n" | cut -c 1-64)
CHALLENGE=$(echo -n "$VERIFIER" | openssl dgst -sha256 -binary | openssl enc -base64 | tr -d "=+/\n")
STATE=$(openssl rand -hex 32)
PORT=52591
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"

echo "Step 1: Generated PKCE parameters"
echo "----------------------------------"
echo "Verifier: $VERIFIER"
echo "Challenge: $CHALLENGE"
echo "State: $STATE"
echo "Port: $PORT"
echo ""

# URL encode the redirect URI
REDIRECT_URI="http://localhost:${PORT}/callback"
REDIRECT_URI_ENCODED=$(echo -n "$REDIRECT_URI" | sed 's/:/%3A/g' | sed 's/\//%2F/g')

# Build authorization URL with code=true
AUTH_URL="https://claude.ai/oauth/authorize?code=true&client_id=${CLIENT_ID}&response_type=code&redirect_uri=${REDIRECT_URI_ENCODED}&scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference&code_challenge=${CHALLENGE}&code_challenge_method=S256&state=${STATE}"

echo "Step 2: Authorization URL"
echo "-------------------------"
echo "$AUTH_URL"
echo ""
echo "Please:"
echo "1. Open this URL in your browser"
echo "2. Log in to Claude if needed"
echo "3. Approve the authorization request"
echo "4. Copy the FULL redirect URL from your browser"
echo ""
echo "Paste the redirect URL here (e.g., http://localhost:52591/callback?code=...&state=...):"
read REDIRECT_URL

# Extract code from redirect URL
CODE=$(echo "$REDIRECT_URL" | grep -oE 'code=[^&]+' | cut -d= -f2)
RETURNED_STATE=$(echo "$REDIRECT_URL" | grep -oE 'state=[^&]+' | cut -d= -f2)

echo ""
echo "Step 3: Extracted parameters"
echo "----------------------------"
echo "Authorization code: $CODE"
echo "Returned state: $RETURNED_STATE"
echo ""

# Verify state matches
if [ "$STATE" != "$RETURNED_STATE" ]; then
    echo "WARNING: State mismatch! This could be a security issue."
    echo "Expected: $STATE"
    echo "Received: $RETURNED_STATE"
    echo ""
fi

echo "Step 4: Token Exchange"
echo "----------------------"
echo "Exchanging authorization code for tokens..."
echo ""

# Prepare JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "grant_type": "authorization_code",
  "code": "$CODE",
  "redirect_uri": "$REDIRECT_URI",
  "code_verifier": "$VERIFIER",
  "client_id": "$CLIENT_ID"
}
EOF
)

echo "Request payload:"
echo "$JSON_PAYLOAD" | jq .
echo ""

# Make token exchange request
RESPONSE=$(curl -X POST https://console.anthropic.com/v1/oauth/token \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" \
  -H "Origin: https://claude.ai" \
  -H "Referer: https://claude.ai/" \
  -H "Accept-Language: en-US,en;q=0.9" \
  -d "$JSON_PAYLOAD" \
  -w "\nHTTP_STATUS:%{http_code}" \
  2>/dev/null)

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS:/d')

echo "Response status: $HTTP_STATUS"
echo "Response body:"
echo "$BODY" | jq . 2>/dev/null || echo "$BODY"

if [ "$HTTP_STATUS" = "200" ]; then
    echo ""
    echo "✅ SUCCESS! OAuth token exchange completed."
    
    # Extract tokens
    ACCESS_TOKEN=$(echo "$BODY" | jq -r '.access_token' 2>/dev/null)
    if [ ! -z "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
        echo ""
        echo "Access token (first 20 chars): ${ACCESS_TOKEN:0:20}..."
    fi
else
    echo ""
    echo "❌ Token exchange failed with status $HTTP_STATUS"
fi