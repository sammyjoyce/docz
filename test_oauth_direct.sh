#!/bin/bash

# Test OAuth token exchange with claude.ai endpoint
# Using the org_id from the successful request dump

ORG_ID="ced3da9c-e42d-4d9e-a213-4a5ca5090f9f"
ENDPOINT="https://claude.ai/v1/oauth/${ORG_ID}/authorize"

echo "Testing OAuth token exchange at: $ENDPOINT"
echo ""
echo "Enter authorization code (or 'test' for a test request):"
read CODE

# Create JSON payload matching the successful request format
JSON_PAYLOAD=$(cat <<EOF
{
  "response_type": "code",
  "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  "redirect_uri": "http://localhost:8080/callback",
  "scope": "org:create_api_key user:profile user:inference",
  "code_challenge": "test_challenge",
  "code_challenge_method": "S256",
  "state": "test_state",
  "code": "$CODE",
  "code_verifier": "test_verifier"
}
EOF
)

echo "Sending request to: $ENDPOINT"
echo "Payload:"
echo "$JSON_PAYLOAD" | jq .
echo ""

# Make the request with browser-like headers
curl -X POST "$ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" \
  -H "Origin: https://claude.ai" \
  -H "Referer: https://claude.ai/" \
  -H "Accept-Language: en-US,en;q=0.9" \
  -d "$JSON_PAYLOAD" \
  -v