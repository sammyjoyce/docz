#!/usr/bin/env bash
# Codex cloud setup script for docz multi-agent terminal AI system
# Installs Zig compiler, ripgrep, and supporting tools for development.
# Optimized for Codex cloud environment startup.
set -euo pipefail

# Configuration
ZIG_VERSION="0.15.1"
INSTALL_PREFIX="/usr/local"
ARCH="$(uname -m)"
PLATFORM="${ARCH}-linux"
ZIG_DIR="$INSTALL_PREFIX/zig-$ZIG_VERSION"
ZIG_BIN_LINK="$INSTALL_PREFIX/bin/zig"
PROJECT_ROOT="$(pwd)"

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Update package list and install base tools
log_info "Installing base dependencies..."
apt-get update && apt-get install -y \
  curl \
  xz-utils \
  git \
  build-essential \
  wget \
  jq

# Install Zig if not already present or wrong version
if ! command -v zig > /dev/null 2>&1 || [ "$(zig version 2> /dev/null || echo '')" != "$ZIG_VERSION" ]; then
  log_info "Installing Zig $ZIG_VERSION..."
  rm -rf "$ZIG_DIR"
  TARBALL="zig-${PLATFORM}-${ZIG_VERSION}.tar.xz"
  curl -L "https://ziglang.org/download/$ZIG_VERSION/$TARBALL" \
    | tar -xJf - -C "$INSTALL_PREFIX"
  mv "$INSTALL_PREFIX/zig-${PLATFORM}-$ZIG_VERSION" "$ZIG_DIR"
  ln -sfn "$ZIG_DIR/zig" "$ZIG_BIN_LINK"
  log_info "Zig $ZIG_VERSION installed successfully"
else
  log_info "Zig $ZIG_VERSION is already installed"
fi

# Install ripgrep for code analysis (required by check_imports.sh)
if ! command -v rg > /dev/null 2>&1; then
  log_info "Installing ripgrep..."
  RIPGREP_VERSION="14.1.0"
  RIPGREP_DEB="ripgrep_${RIPGREP_VERSION}-1_amd64.deb"
  wget -q "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/${RIPGREP_DEB}"
  dpkg -i "$RIPGREP_DEB" || apt-get install -f -y
  rm -f "$RIPGREP_DEB"
  log_info "ripgrep installed successfully"
else
  log_info "ripgrep is already installed"
fi

# Persist zig in PATH for interactive shells
if ! grep -q "zig-$ZIG_VERSION" ~/.bashrc 2> /dev/null; then
  echo "export PATH=\"$ZIG_DIR:\$PATH\"" >> ~/.bashrc
  log_info "Added Zig to PATH in ~/.bashrc"
fi

# Export for current session
export PATH="$ZIG_DIR:$PATH"

# Optional: Install additional development tools
log_info "Installing additional development tools..."
apt-get install -y \
  tmux \
  htop \
  tree \
  fd-find \
  bat || log_warn "Some optional tools failed to install"

# Create useful aliases for development
if ! grep -q "# docz aliases" ~/.bashrc 2> /dev/null; then
  cat >> ~/.bashrc << 'EOF'

# docz aliases
alias agents='zig build list-agents'
alias validate='zig build validate-agents'
alias build-agent='zig build -Dagent='
alias check-imports='scripts/check_imports.sh'
alias zb='zig build'
alias zfmt='zig fmt src/**/*.zig build.zig build.zig.zon'

# Helper function to build and run an agent
run-agent() {
  if [ -z "$1" ]; then
    echo "Usage: run-agent <agent-name>"
    return 1
  fi
  zig build -Dagent="$1" run
}

# Helper function to test an agent
test-agent() {
  if [ -z "$1" ]; then
    echo "Usage: test-agent <agent-name>"
    return 1
  fi
  zig build -Dagent="$1" test
}
EOF
  log_info "Added helpful aliases to ~/.bashrc"
fi

# Verify project structure
log_info "Verifying project structure..."
cd "$PROJECT_ROOT"

# Make scripts executable
if [ -d "scripts" ]; then
  chmod +x scripts/*.sh 2> /dev/null || true
  log_info "Made scripts executable"
fi

# Run initial validation
log_info "Running initial project validation..."
if zig build validate-agents 2> /dev/null; then
  log_info "Agent validation passed"
else
  log_warn "Agent validation failed - some agents may need configuration"
fi

# List available agents
if zig build list-agents 2> /dev/null; then
  log_info "Available agents listed successfully"
else
  log_warn "Could not list agents - build system may need initialization"
fi

# Check if we can run import checks
if [ -x "scripts/check_imports.sh" ]; then
  log_info "Running import boundary checks..."
  if scripts/check_imports.sh; then
    log_info "Import checks passed"
  else
    log_warn "Import violations detected - review for cleanup"
  fi
else
  log_warn "Import check script not found or not executable"
fi

# Cache commonly used build artifacts
log_info "Pre-building common dependencies..."
zig build --help > /dev/null 2>&1 || log_warn "Build system initialization incomplete"

# Set up environment variables for the project
export DOCZ_PROJECT_ROOT="$PROJECT_ROOT"
export ZIG_VERSION="$ZIG_VERSION"

# Create a project info file for reference
cat > ~/.docz_info << EOF
DOCZ Project Information
========================
Project Root: $PROJECT_ROOT
Zig Version: $ZIG_VERSION
Setup Date: $(date)
Platform: $PLATFORM

Quick Commands:
- List agents: zig build list-agents
- Validate agents: zig build validate-agents
- Build agent: zig build -Dagent=<name> run
- Run tests: zig build -Dagent=<name> test
- Check imports: scripts/check_imports.sh
- Format code: zig fmt src/**/*.zig

Aliases available (source ~/.bashrc):
- agents: List all available agents
- validate: Validate agent structure
- build-agent: Build a specific agent
- run-agent <name>: Build and run an agent
- test-agent <name>: Test a specific agent
EOF

log_info "Setup complete! Project info saved to ~/.docz_info"
log_info "To see available commands, run: cat ~/.docz_info"
log_info "To use aliases, run: source ~/.bashrc"

# Final verification
echo ""
log_info "Environment Summary:"
echo "  Zig version: $(zig version 2> /dev/null || echo 'NOT INSTALLED')"
echo "  ripgrep: $(command -v rg > /dev/null 2>&1 && echo 'installed' || echo 'NOT INSTALLED')"
echo "  Project root: $PROJECT_ROOT"
echo "  Platform: $PLATFORM"
echo ""

# Return success
exit 0
