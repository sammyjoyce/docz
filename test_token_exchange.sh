#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: $0 <authorization_code>"
    exit 1
fi

CODE=$1
VERIFIER=$(cat /tmp/pkce_verifier.txt)
STATE=$(cat /tmp/pkce_state.txt)
PORT=$(cat /tmp/pkce_port.txt)

echo "Testing token exchange..."
echo "Code: $CODE"
echo "Verifier: $VERIFIER"
echo "State: $STATE"
echo ""

curl -X POST https://console.anthropic.com/v1/oauth/token \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" \
  -H "Origin: https://claude.ai" \
  -H "Referer: https://claude.ai/" \
  -d "{
    \"grant_type\": \"authorization_code\",
    \"code\": \"$CODE\",
    \"state\": \"$STATE\",
    \"client_id\": \"9d1c250a-e61b-44d9-88ed-5944d1962f5e\",
    \"redirect_uri\": \"http://localhost:${PORT}/callback\",
    \"code_verifier\": \"$VERIFIER\"
  }" -v 2>&1 | grep -E "HTTP/|{" | tail -10