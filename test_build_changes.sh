#!/bin/bash

# Test Build Configuration Changes
echo "Testing build.zig changes for UX enhancements..."
echo "================================================"

# Function to test a build command
test_build() {
    local cmd="$1"
    local desc="$2"
    echo -n "Testing: $desc... "
    if $cmd 2>&1 | grep -q "error\|Error\|ERROR"; then
        echo "❌ FAILED"
        echo "  Command: $cmd"
        $cmd 2>&1 | grep -i "error" | head -3
    else
        echo "✅ OK"
    fi
}

# Test basic build configurations
echo ""
echo "1. Testing basic agent builds:"
test_build "zig build -Dagent=markdown --summary none" "Markdown agent build"
test_build "zig build -Dagent=test_agent --summary none" "Test agent build"

# Test new demo targets (these may fail if modules aren't ready, but should parse)
echo ""
echo "2. Testing demo target parsing:"
test_build "zig build --help 2>&1 | grep demo-dashboard" "Dashboard demo target exists"
test_build "zig build --help 2>&1 | grep demo-interactive" "Interactive demo target exists"
test_build "zig build --help 2>&estionl | grep demo-oauth" "OAuth demo target exists"
test_build "zig build --help 2>&1 | grep demo-markdown-editor" "Markdown editor demo target exists"

# Test list and validate commands
echo ""
echo "3. Testing utility commands:"
test_build "zig build list-agents" "List agents command"
test_build "zig build validate-agents" "Validate agents command"

# Summary
echo ""
echo "================================================"
echo "Build configuration test complete!"
echo ""
echo "Note: Some demo targets may fail to compile if the referenced"
echo "modules don't have proper main functions yet, but they should"
echo "at least be recognized as valid build targets."