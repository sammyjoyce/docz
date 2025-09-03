#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
GRAMMAR_DIR="$DIR/zig-ts-grammar"

echo "Generating parser..."
pushd "$GRAMMAR_DIR" >/dev/null
bunx -y tree-sitter-cli@0.22.6 generate

echo "Building WASM (via docker)..."
bunx -y tree-sitter-cli@0.22.6 build --wasm
popd >/dev/null

mkdir -p "$DIR/../wasm"
cp "$GRAMMAR_DIR/tree-sitter-zig.wasm" "$DIR/../wasm/tree-sitter-zig.wasm"
echo "WASM written to wasm/tree-sitter-zig.wasm"
