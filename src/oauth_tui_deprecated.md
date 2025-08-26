# OAuth TUI Deprecation Notice

The `oauth_tui.zig` file has been deprecated and replaced with a new modular authentication system.

## New Location

Authentication functionality has been moved to:

- **Core authentication logic**: `src/auth/core/mod.zig`
- **OAuth implementation**: `src/auth/oauth/mod.zig` 
- **TUI components**: `src/auth/tui/mod.zig`
- **CLI commands**: `src/auth/cli/mod.zig`
- **Main auth module**: `src/auth/mod.zig`

## Migration

Instead of directly importing `oauth_tui.zig`, use:

```zig
const auth = @import("auth/mod.zig");

// For OAuth setup with TUI
try auth.runAuthTUI(allocator, .oauth_setup);

// For status display with TUI
try auth.runAuthTUI(allocator, .status);

// For token refresh with TUI  
try auth.runAuthTUI(allocator, .refresh);
```

## Benefits

The new modular system provides:

1. **Better separation of concerns** - OAuth logic separated from TUI presentation
2. **Reusable components** - Auth logic can be used in different contexts
3. **CLI integration** - Proper integration with the CLI framework
4. **TUI framework usage** - Uses the modular TUI components
5. **Better error handling** - More structured error types and handling
6. **Easier testing** - Modular design makes unit testing easier

## Files

- `oauth_tui.zig.deprecated` - Original implementation (kept for reference)
- This file serves as documentation for the migration