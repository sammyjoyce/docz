#!/bin/bash

# Fix naming convention violations in the codebase

echo "Fixing naming convention violations..."

# 1. Fix functions with capital letters in enhanced_cursor_control.zig
echo "Fixing enhanced_cursor_control.zig..."

# VPR function
sed -i '' 's/pub fn VPR(/pub fn vpr(/g' src/shared/term/ansi/enhanced_cursor_control.zig

# HVP function
sed -i '' 's/pub fn HVP(/pub fn hvp(/g' src/shared/term/ansi/enhanced_cursor_control.zig

# CHT function
sed -i '' 's/pub fn CHT(/pub fn cht(/g' src/shared/term/ansi/enhanced_cursor_control.zig

# CBT function
sed -i '' 's/pub fn CBT(/pub fn cbt(/g' src/shared/term/ansi/enhanced_cursor_control.zig

# ECH function
sed -i '' 's/pub fn ECH(/pub fn ech(/g' src/shared/term/ansi/enhanced_cursor_control.zig

# DECSCUSR function
sed -i '' 's/pub fn DECSCUSR(/pub fn decscusr(/g' src/shared/term/ansi/enhanced_cursor_control.zig

# HPA function
sed -i '' 's/pub fn HPA(/pub fn hpa(/g' src/shared/term/ansi/enhanced_cursor_control.zig

# HPR function
sed -i '' 's/pub fn HPR(/pub fn hpr(/g' src/shared/term/ansi/enhanced_cursor_control.zig

# 2. Fix type-returning functions (generics) - these should be lowercase
echo "Fixing type-returning functions..."

# CommandContext in finalterm.zig
sed -i '' 's/pub fn CommandContext(/pub fn commandContext(/g' src/shared/term/ansi/finalterm.zig

# CliIntegration in finalterm.zig  
sed -i '' 's/pub fn CliIntegration(/pub fn cliIntegration(/g' src/shared/term/ansi/finalterm.zig

# NewPty in pty.zig (if it exists)
find . -name "pty.zig" -exec sed -i '' 's/pub fn NewPty(/pub fn newPty(/g' {} \;

# ChartBuilder in dashboard/builder.zig
find . -path "*/dashboard/builder.zig" -exec sed -i '' 's/pub fn ChartBuilder(/pub fn chartBuilder(/g' {} \;

# PointerShapeGuard in pointer.zig
find . -name "pointer.zig" -exec sed -i '' 's/pub fn PointerShapeGuard(/pub fn pointerShapeGuard(/g' {} \;

# 3. Fix functions with underscores
echo "Fixing functions with underscores..."

# error_ functions - rename to errorNotification
find . -name "smart_notification.zig" -exec sed -i '' 's/pub fn error_(/pub fn errorNotification(/g' {} \;
find . -name "notification.zig" -exec sed -i '' 's/pub fn error_(/pub fn errorNotification(/g' {} \;

# Update calls to error_
find . -name "smart_notification.zig" -exec sed -i '' 's/\.error_(/.errorNotification(/g' {} \;
find . -name "notification.zig" -exec sed -i '' 's/\.error_(/.errorNotification(/g' {} \;

# verbose_log functions - rename to verboseLog
find . -name "context.zig" -exec sed -i '' 's/pub fn verbose_log(/pub fn verboseLog(/g' {} \;
find . -name "unified_simple.zig" -exec sed -i '' 's/pub fn verbose_log(/pub fn verboseLog(/g' {} \;

# Update calls to verbose_log
find . -name "*.zig" -exec sed -i '' 's/\.verbose_log(/.verboseLog(/g' {} \;

# 4. Fix mutable global variables (these need refactoring)
echo "Fixing global variables..."

# Create a globals module for proper encapsulation
cat > src/shared/globals.zig << 'EOF'
const std = @import("std");

/// Global state manager for shared mutable state
/// This encapsulates global state that was previously scattered across files
pub const GlobalState = struct {
    // Anthropic module globals
    anthropic: struct {
        refreshState: RefreshState,
        contentCollector: std.ArrayList(u8),
        allocator: std.mem.Allocator,
        initialized: bool = false,
    },
    
    // Smart notification module globals
    smartNotification: struct {
        allocator: ?std.mem.Allocator = null,
    },
    
    // Tools module globals
    tools: struct {
        list: ?*std.ArrayList(u8) = null,
        allocator: ?std.mem.Allocator = null,
    },
    
    const RefreshState = struct {
        needsRefresh: bool = false,
        
        pub fn init() RefreshState {
            return .{};
        }
    };
    
    var instance: ?GlobalState = null;
    var mutex = std.Thread.Mutex{};
    
    pub fn getInstance() *GlobalState {
        mutex.lock();
        defer mutex.unlock();
        
        if (instance == null) {
            instance = GlobalState{
                .anthropic = .{
                    .refreshState = RefreshState.init(),
                    .contentCollector = undefined,
                    .allocator = undefined,
                    .initialized = false,
                },
                .smartNotification = .{},
                .tools = .{},
            };
        }
        return &instance.?;
    }
    
    pub fn initAnthropicGlobals(allocator: std.mem.Allocator) void {
        const self = getInstance();
        if (!self.anthropic.initialized) {
            self.anthropic.allocator = allocator;
            self.anthropic.contentCollector = std.ArrayList(u8).init(allocator);
            self.anthropic.initialized = true;
        }
    }
    
    pub fn deinitAnthropicGlobals() void {
        const self = getInstance();
        if (self.anthropic.initialized) {
            self.anthropic.contentCollector.deinit();
            self.anthropic.initialized = false;
        }
    }
};
EOF

echo "Script complete! Please review the changes and update any references to the renamed functions."
echo ""
echo "Important notes:"
echo "1. Functions starting with capital letters have been changed to camelCase"
echo "2. Functions with underscores have been renamed to camelCase"
echo "3. Global variables need manual refactoring - see src/shared/globals.zig for suggested approach"
echo "4. Variables with underscores within functions should be manually reviewed and fixed"
echo ""
echo "You may need to:"
echo "- Update any imports or references to the renamed functions"
echo "- Refactor global variables to use the new GlobalState pattern"
echo "- Fix any local variables with underscores manually"