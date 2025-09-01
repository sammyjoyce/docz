#!/bin/bash

echo "Testing token exchange with console.anthropic.com redirect URI"
echo "================================================"
echo ""

# You'll need to provide these from a successful authorization
echo "Enter the authorization code from browser callback:"
read CODE

echo "Enter the PKCE verifier used for this authorization:"
read VERIFIER

echo ""
echo "Testing token exchange with correct redirect URI..."
echo ""

# Test with the console redirect URI instead of localhost
curl -X POST https://console.anthropic.com/v1/oauth/token \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" \
  -H "Origin: https://claude.ai" \
  -H "Referer: https://claude.ai/" \
  -d "{
    \"code\": \"$CODE\",
    \"grant_type\": \"authorization_code\",
    \"client_id\": \"9d1c250a-e61b-44d9-88ed-5944d1962f5e\",
    \"redirect_uri\": \"https://console.anthropic.com/oauth/code/callback\",
    \"code_verifier\": \"$VERIFIER\"
  }" -v 2>&1 | grep -E "< HTTP|{" | tail -20
