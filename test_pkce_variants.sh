#!/bin/bash

echo "Testing different PKCE challenge formats"
echo "========================================="
echo ""

# Method 1: Our current approach (64 char verifier with special chars)
echo "Method 1: 64-char verifier with unreserved chars (RFC 7636)"
VERIFIER1=$(openssl rand -base64 64 | tr -d "=+/\n" | cut -c 1-64)
CHALLENGE1=$(echo -n "$VERIFIER1" | openssl dgst -sha256 -binary | openssl enc -base64 | tr '+/' '-_' | tr -d '=')
echo "Verifier:  $VERIFIER1"
echo "Challenge: $CHALLENGE1"
echo "Verifier length: ${#VERIFIER1}, Challenge length: ${#CHALLENGE1}"
echo ""

# Method 2: Only alphanumeric and dash/underscore (no tilde)
echo "Method 2: 64-char verifier, only [A-Za-z0-9-_]"
VERIFIER2=$(openssl rand -base64 128 | tr -cd 'A-Za-z0-9' | cut -c 1-64)
CHALLENGE2=$(echo -n "$VERIFIER2" | openssl dgst -sha256 -binary | openssl enc -base64 | tr '+/' '-_' | tr -d '=')
echo "Verifier:  $VERIFIER2"
echo "Challenge: $CHALLENGE2"
echo "Verifier length: ${#VERIFIER2}, Challenge length: ${#CHALLENGE2}"
echo ""

# Method 3: Shorter verifier (43 chars, minimum required)
echo "Method 3: 43-char verifier (minimum per RFC)"
VERIFIER3=$(openssl rand -base64 64 | tr -cd 'A-Za-z0-9' | cut -c 1-43)
CHALLENGE3=$(echo -n "$VERIFIER3" | openssl dgst -sha256 -binary | openssl enc -base64 | tr '+/' '-_' | tr -d '=')
echo "Verifier:  $VERIFIER3"
echo "Challenge: $CHALLENGE3"
echo "Verifier length: ${#VERIFIER3}, Challenge length: ${#CHALLENGE3}"
echo ""

# Method 4: Exactly like the successful example (43 char result)
echo "Method 4: Standard base64url encoding (no special chars in verifier)"
VERIFIER4=$(openssl rand 32 | openssl enc -base64 | tr '+/' '-_' | tr -d '=')
CHALLENGE4=$(echo -n "$VERIFIER4" | openssl dgst -sha256 -binary | openssl enc -base64 | tr '+/' '-_' | tr -d '=')
echo "Verifier:  $VERIFIER4"
echo "Challenge: $CHALLENGE4"
echo "Verifier length: ${#VERIFIER4}, Challenge length: ${#CHALLENGE4}"
echo ""

echo "Select which method to test (1-4):"
read METHOD

case $METHOD in
    1) VERIFIER=$VERIFIER1; CHALLENGE=$CHALLENGE1 ;;
    2) VERIFIER=$VERIFIER2; CHALLENGE=$CHALLENGE2 ;;
    3) VERIFIER=$VERIFIER3; CHALLENGE=$CHALLENGE3 ;;
    4) VERIFIER=$VERIFIER4; CHALLENGE=$CHALLENGE4 ;;
    *) echo "Invalid selection"; exit 1 ;;
esac

STATE=$(openssl rand -hex 16)
PORT=52591

URL="https://claude.ai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=http%3A%2F%2Flocalhost%3A${PORT}%2Fcallback&scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference&code_challenge=${CHALLENGE}&code_challenge_method=S256&state=${STATE}"

echo ""
echo "Testing Method $METHOD"
echo "Authorization URL:"
echo "$URL"
echo ""
echo "Please open this URL and report if you get:"
echo "  - Success: redirected with ?code=..."
echo "  - Failure: redirected with ?error=invalid_request"
echo ""
echo "Saving PKCE parameters for token exchange..."
echo "$VERIFIER" > /tmp/pkce_verifier.txt
echo "$STATE" > /tmp/pkce_state.txt
echo "$PORT" > /tmp/pkce_port.txt
echo ""
echo "After authorization, run: ./test_token_exchange.sh <CODE>"