#!/bin/bash

# Generate PKCE like our Zig code does
VERIFIER=$(head -c 48 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=' | head -c 64)
CHALLENGE=$(echo -n "$VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')
STATE=$(head -c 24 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=' | head -c 32)

echo "PKCE Parameters:"
echo "Verifier: $VERIFIER"
echo "Challenge: $CHALLENGE"
echo "Challenge length: ${#CHALLENGE}"
echo "State: $STATE"
echo ""

# Build URL without URL encoding the challenge (it's already base64url)
URL="https://claude.ai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=http%3A%2F%2Flocalhost%3A52591%2Fcallback&scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference&code_challenge=${CHALLENGE}&code_challenge_method=S256&state=${STATE}"

echo "Authorization URL:"
echo "$URL"
echo ""
echo "Open this URL in your browser to test if the code_challenge is accepted."
