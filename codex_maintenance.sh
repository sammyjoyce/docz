#!/usr/bin/env bash
# Codex cloud maintenance script for docz project
# Run when containers are resumed from cache to update dependencies
# This script runs after setup script when using cached containers
set -euo pipefail

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[MAINT]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[MAINT]${NC} $1"; }

PROJECT_ROOT="$(pwd)"

log_info "Running maintenance tasks for cached container..."

# Export PATH for current session (in case shell was reset)
if [ -d "/usr/local/zig-0.15.1" ]; then
  export PATH="/usr/local/zig-0.15.1:$PATH"
fi

# Pull latest changes if in a git repository
if [ -d ".git" ]; then
  log_info "Checking for repository updates..."
  # Note: Codex handles git operations, but we can verify state
  CURRENT_BRANCH=$(git branch --show-current 2> /dev/null || echo "unknown")
  log_info "Current branch: $CURRENT_BRANCH"
fi

# Clean any stale build artifacts
if [ -d "zig-cache" ]; then
  log_info "Cleaning build cache..."
  rm -rf zig-cache
fi

if [ -d "zig-out" ]; then
  log_info "Cleaning build outputs..."
  rm -rf zig-out
fi

# Verify tools are still available
log_info "Verifying tools..."
command -v zig > /dev/null 2>&1 && log_info "  ✓ Zig $(zig version)" || log_warn "  ✗ Zig not found"
command -v rg > /dev/null 2>&1 && log_info "  ✓ ripgrep installed" || log_warn "  ✗ ripgrep not found"
command -v git > /dev/null 2>&1 && log_info "  ✓ git installed" || log_warn "  ✗ git not found"

# Quick validation of project structure
if [ -f "build.zig" ]; then
  log_info "Project structure verified"

  # Re-validate agents in case of changes
  if zig build validate-agents 2> /dev/null; then
    log_info "Agent validation passed"
  else
    log_warn "Agent validation failed - checking for new agents..."
    # List agents to see what's available
    zig build list-agents 2> /dev/null || true
  fi
else
  log_warn "build.zig not found - may need to switch branches"
fi

# Update timestamp for tracking
echo "Last maintenance: $(date)" > ~/.docz_last_maintenance

log_info "Maintenance complete"

# Quick status report
echo ""
echo "Container Status:"
echo "  Branch: $(git branch --show-current 2> /dev/null || echo 'unknown')"
echo "  Last commit: $(git log -1 --format='%h %s' 2> /dev/null || echo 'unknown')"
echo "  Zig version: $(zig version 2> /dev/null || echo 'not available')"
echo ""

exit 0
