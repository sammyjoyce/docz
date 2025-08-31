#!/bin/bash

# Test script for validating different build feature combinations
# This script tests the build system with various profiles and feature flags

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test directory for build artifacts
TEST_DIR="zig-out/feature_tests"
LOG_FILE="feature_test_results.log"
SUMMARY_FILE="feature_test_summary.md"

# Initialize logs
echo "Feature Combination Test Results - $(date)" > "$LOG_FILE"
echo "================================================" >> "$LOG_FILE"

cat > "$SUMMARY_FILE" << 'EOF'
# Feature Combination Test Summary

## Test Results

| Configuration | Status | Build Time | Binary Size | Notes |
|--------------|--------|------------|-------------|-------|
EOF

# Track statistics
SUCCESS_COUNT=0
FAILURE_COUNT=0
declare -a BUILD_TIMES
declare -a BINARY_SIZES

# Function to test a build configuration
test_config() {
    local desc="$1"
    local args="$2"
    local test_type="${3:-build}"
    
    echo -e "\n${BLUE}Testing: ${desc}${NC}"
    echo -e "  Command: zig build list-agents ${args}"
    
    # Log to file
    echo -e "\n### Test: ${desc}" >> "$LOG_FILE"
    echo "Command: zig build list-agents ${args}" >> "$LOG_FILE"
    
    # Time the build
    local start_time=$(date +%s%N)
    
    # Run with error capture
    set +e
    output=$(zig build list-agents $args 2>&1)
    result=$?
    set -e
    
    local end_time=$(date +%s%N)
    local build_time=$((($end_time - $start_time) / 1000000))
    BUILD_TIMES+=($build_time)
    
    if [ $result -eq 0 ]; then
        echo -e "  ${GREEN}✓ Build succeeded${NC} (${build_time}ms)"
        echo "Result: SUCCESS (${build_time}ms)" >> "$LOG_FILE"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        
        # Extract feature configuration from output
        echo "$output" | grep -E "Features:|Profile:|├─|└─" | head -10 | tee -a "$LOG_FILE" || true
        
        local size_str="N/A"
        local size_bytes="N/A"
        
        # Try to get binary size if we build the actual binary
        if [ "$test_type" = "size" ]; then
            # Build the actual binary
            zig build -Dagent=test_agent $args > /dev/null 2>&1 || true
            if [ -f "zig-out/bin/docz" ]; then
                size_str=$(ls -lh zig-out/bin/docz 2>/dev/null | awk '{print $5}')
                size_bytes=$(stat -f%z zig-out/bin/docz 2>/dev/null || stat -c%s zig-out/bin/docz 2>/dev/null || echo "N/A")
                echo -e "  Binary size: ${size_str} (${size_bytes} bytes)"
                echo "Binary size: ${size_str} (${size_bytes} bytes)" >> "$LOG_FILE"
                if [ "$size_bytes" != "N/A" ]; then
                    BINARY_SIZES+=($size_bytes)
                fi
            fi
        fi
        
        # Add to summary
        echo "| $desc | ✓ | ${build_time}ms | $size_str | |" >> "$SUMMARY_FILE"
        
        return 0
    else
        echo -e "  ${RED}✗ Build failed${NC}"
        echo "Result: FAILED" >> "$LOG_FILE"
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        
        # Extract first error
        local error_msg=$(echo "$output" | grep -E "error:" | head -1 | sed 's/.*error: //')
        echo "Error output:" >> "$LOG_FILE"
        echo "$output" | grep -E "error:|note:" | head -10 | tee -a "$LOG_FILE" || true
        
        # Add to summary
        echo "| $desc | ✗ | N/A | N/A | $error_msg |" >> "$SUMMARY_FILE"
        
        return 1
    fi
}

###############################
# Profile matrix (feature logs)
###############################
echo "### PROFILE TESTS ###"
echo ""
test_config "Minimal Profile" "-Dprofile=minimal"
test_config "Standard Profile" "-Dprofile=standard"
test_config "Full Profile" "-Dprofile=full"

#################################
# Individual features (smoke log)
#################################
echo "### INDIVIDUAL FEATURE TESTS ###"
echo ""
test_config "CLI Only" "-Dfeatures=cli"
test_config "TUI Only" "-Dfeatures=tui"
test_config "Network Only" "-Dfeatures=network"
test_config "Sixel Graphics" "-Dfeatures=sixel"

#################################
# Common combinations (smoke log)
#################################
echo "### FEATURE COMBINATION TESTS ###"
echo ""
test_config "CLI + Network" "-Dfeatures=cli,network"
test_config "TUI + Network" "-Dfeatures=tui,network"
test_config "CLI + TUI" "-Dfeatures=cli,tui"
test_config "Network + Auth" "-Dfeatures=network,auth"
test_config "Network + Anthropic" "-Dfeatures=network,anthropic"

#################################
# Dependency resolution (smoke log)
#################################
echo "### DEPENDENCY RESOLUTION TESTS ###"
echo ""
test_config "Auth (should enable network)" "-Dfeatures=auth"
test_config "Anthropic (should enable network)" "-Dfeatures=anthropic"
test_config "Auth + Anthropic" "-Dfeatures=auth,anthropic"

#################################
# Profile overrides (smoke log)
#################################
echo "### PROFILE OVERRIDE TESTS ###"
echo ""
test_config "Minimal + TUI override" "-Dprofile=minimal -Denable-tui=true"
test_config "Minimal + Network override" "-Dprofile=minimal -Denable-network=true"
test_config "Full - TUI override" "-Dprofile=full -Denable-tui=false"
test_config "Standard + Sixel override" "-Dprofile=standard -Denable-sixel=true"

########################
# Edge cases (smoke log)
########################
echo "### EDGE CASE TESTS ###"
echo ""
test_config "Empty features" "-Dfeatures="
test_config "All features" "-Dfeatures=all"
test_config "Mixed case profile + features" "-Dprofile=minimal -Dfeatures=cli,tui,network"

########################################
# Binary size measurements (build size)
########################################
echo "### BINARY SIZE TESTS ###"
echo "(Building docz with agents/test_agent for size)"
echo ""

# Ensure zig-out/bin exists
mkdir -p zig-out/bin || true

test_config "SIZE: Minimal Profile" "-Dprofile=minimal" size
test_config "SIZE: Standard Profile" "-Dprofile=standard" size
test_config "SIZE: Full Profile" "-Dprofile=full" size

# Representative combinations
test_config "SIZE: CLI Only" "-Dfeatures=cli" size
test_config "SIZE: TUI Only" "-Dfeatures=tui" size
test_config "SIZE: Network + Auth" "-Dfeatures=network,auth" size
test_config "SIZE: Network + Anthropic" "-Dfeatures=network,anthropic" size

echo ""
echo "========================================="
echo "Testing Complete"
echo "========================================="
echo ""

# Generate statistics summary
echo "" >> "$SUMMARY_FILE"
echo "## Statistics" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "- **Total Tests**: $((SUCCESS_COUNT + FAILURE_COUNT))" >> "$SUMMARY_FILE"
echo "- **Passed**: $SUCCESS_COUNT" >> "$SUMMARY_FILE"
echo "- **Failed**: $FAILURE_COUNT" >> "$SUMMARY_FILE"

if [ ${#BUILD_TIMES[@]} -gt 0 ]; then
    # Calculate build time statistics
    min_time=${BUILD_TIMES[0]}
    max_time=${BUILD_TIMES[0]}
    sum_time=0
    
    for time in "${BUILD_TIMES[@]}"; do
        sum_time=$((sum_time + time))
        [ $time -lt $min_time ] && min_time=$time
        [ $time -gt $max_time ] && max_time=$time
    done
    
    avg_time=$((sum_time / ${#BUILD_TIMES[@]}))
    
    echo "- **Avg Build Time**: ${avg_time}ms" >> "$SUMMARY_FILE"
    echo "- **Min Build Time**: ${min_time}ms" >> "$SUMMARY_FILE"
    echo "- **Max Build Time**: ${max_time}ms" >> "$SUMMARY_FILE"
fi

if [ ${#BINARY_SIZES[@]} -gt 0 ]; then
    # Calculate binary size statistics
    min_size=${BINARY_SIZES[0]}
    max_size=${BINARY_SIZES[0]}
    
    for size in "${BINARY_SIZES[@]}"; do
        [ $size -lt $min_size ] && min_size=$size
        [ $size -gt $max_size ] && max_size=$size
    done
    
    min_size_mb=$(echo "scale=2; $min_size / 1048576" | bc)
    max_size_mb=$(echo "scale=2; $max_size / 1048576" | bc)
    
    echo "- **Min Binary Size**: ${min_size_mb}MB (${min_size} bytes)" >> "$SUMMARY_FILE"
    echo "- **Max Binary Size**: ${max_size_mb}MB (${max_size} bytes)" >> "$SUMMARY_FILE"
fi

echo ""
echo "Results saved to:"
echo "  - $LOG_FILE (detailed logs)"
echo "  - $SUMMARY_FILE (summary table)"
echo ""
