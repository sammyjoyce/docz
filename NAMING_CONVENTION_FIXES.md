# Naming Convention Fixes

This document outlines all the naming convention violations found and their fixes according to `docs/STYLE.md`.

## 1. Functions with Capital Letters

### enhanced_cursor_control.zig
These ANSI escape code shorthand functions should be renamed from CAPS to camelCase:

| Current Name | New Name | Description |
|-------------|----------|-------------|
| `CUU` | `cuu` | Cursor Up shorthand |
| `CUD` | `cud` | Cursor Down shorthand |
| `CUF` | `cuf` | Cursor Forward shorthand |
| `CUB` | `cub` | Cursor Backward shorthand |
| `CNL` | `cnl` | Cursor Next Line shorthand |
| `CPL` | `cpl` | Cursor Previous Line shorthand |
| `CHA` | `cha` | Cursor Horizontal Absolute shorthand |
| `CUP` | `cup` | Cursor Position shorthand |
| `VPA` | `vpa` | Vertical Position Absolute shorthand |
| `VPR` | `vpr` | Vertical Position Relative shorthand |
| `HVP` | `hvp` | Horizontal and Vertical Position shorthand |
| `CHT` | `cht` | Cursor Horizontal Tab shorthand |
| `CBT` | `cbt` | Cursor Backward Tab shorthand |
| `ECH` | `ech` | Erase Characters shorthand |
| `DECSCUSR` | `decscusr` | DEC Set Cursor Style shorthand |
| `HPA` | `hpa` | Horizontal Position Absolute shorthand |
| `HPR` | `hpr` | Horizontal Position Relative shorthand |

### Type-Returning Functions (Generics)
These functions return types and should follow camelCase convention:

| File | Current Name | New Name | Type |
|------|-------------|----------|------|
| `finalterm.zig` | `CommandContext` | `commandContext` | Generic type function |
| `finalterm.zig` | `CliIntegration` | `cliIntegration` | Generic type function |
| `pty.zig` | `NewPty` | `newPty` | Constructor function |
| `dashboard/builder.zig` | `ChartBuilder` | `chartBuilder` | Generic type function |
| `pointer.zig` | `PointerShapeGuard` | `pointerShapeGuard` | Generic type function |

## 2. Functions with Underscores

| File | Current Name | New Name | Description |
|------|-------------|----------|-------------|
| `smart_notification.zig` | `error_` | `errorNotification` | Error notification method |
| `notification.zig` | `error_` | `errorNotification` | Error notification method |
| `context.zig` | `verbose_log` | `verboseLog` | Verbose logging method |
| `unified_simple.zig` | `verbose_log` | `verboseLog` | Verbose logging method |

## 3. Global Variables

These mutable global variables violate the naming convention and should be refactored:

### Current Global Variables
```zig
// smart_notification.zig
var GLOBAL_ALLOCATOR: ?std.mem.Allocator = null;

// anthropic.zig  
var GLOBAL_REFRESH_STATE = RefreshState.init();
var GLOBAL_CONTENT_COLLECTOR: std.ArrayList(u8) = undefined;
var GLOBAL_ALLOCATOR: std.mem.Allocator = undefined;

// tools.zig
var G_LIST: ?*std.ArrayList(u8) = null;
var G_ALLOCATOR: ?std.mem.Allocator = null;
```

### Recommended Refactoring Pattern

Instead of scattered global variables, use a singleton pattern with proper encapsulation:

```zig
// In src/shared/globals.zig
pub const GlobalState = struct {
    anthropic: AnthropicState,
    smartNotification: NotificationState,
    tools: ToolsState,
    
    var instance: ?GlobalState = null;
    var mutex = std.Thread.Mutex{};
    
    pub fn getInstance() *GlobalState {
        // Thread-safe singleton access
    }
};
```

## 4. Variables with Underscores

Local variables with underscores should be converted to camelCase. Common patterns found:

| Pattern | Example | Fix |
|---------|---------|-----|
| `agent_name` | `const agent_name = "test"` | `const agentName = "test"` |
| `config_path` | `var config_path: []const u8` | `var configPath: []const u8` |
| `tool_list` | `const tool_list = ArrayList()` | `const toolList = ArrayList()` |
| `error_msg` | `const error_msg = "failed"` | `const errorMsg = "failed"` |

## 5. Constants (Correctly Named)

The following are correctly named as ALL_CAPS constants and should NOT be changed:

- `BUILD_CONFIG` struct with its fields in build.zig
- `DEFAULT_AGENT`, `BINARY_NAME`, `SOURCE_DIRS`, etc. (build configuration constants)
- ANSI escape code constants like `CUU1`, `CUD1`, `CUF1`, `CUB1` (string constants)
- `SAVE_CURSOR`, `RESTORE_CURSOR`, `DECSC`, `DECRC` (ANSI constants)

## Implementation Steps

1. **Run the automated fix script**:
   ```bash
   ./fix_naming_violations.sh
   ```

2. **Manually refactor global variables**:
   - Create `src/shared/globals.zig` with the GlobalState pattern
   - Update references in `anthropic.zig`, `smart_notification.zig`, and `tools.zig`
   - Use `GlobalState.getInstance()` to access shared state

3. **Fix local variables with underscores**:
   - Search for variables: `rg "^\s*(const|var)\s+\w+_\w+" --type zig`
   - Manually rename each to camelCase
   - Update all references

4. **Update function calls**:
   - Search for old function names and update calls
   - Example: `CUU(` → `cuu(`
   - Example: `.error_(` → `.errorNotification(`
   - Example: `.verbose_log(` → `.verboseLog(`

5. **Test the changes**:
   ```bash
   zig build test --summary all
   ```

## Validation

After making these changes, validate the naming conventions:

```bash
# Check for remaining violations
rg "pub fn [A-Z][A-Z]" --type zig  # Should only show constants
rg "pub fn \w+_\w+" --type zig     # Should be empty
rg "^var [A-Z_]+" --type zig       # Should only show proper constants
```

## Notes

- The `build.zig` constants with underscores are correctly named as they are compile-time constants
- ANSI escape code constants (CUU1, CUD1, etc.) are correctly ALL_CAPS
- Focus on fixing functions and mutable variables first
- The global variable refactoring requires careful testing as it affects shared state