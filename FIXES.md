# Remaining Manual Fixes Required

## ✅ Completed Automatic Fixes

The following have been automatically fixed:
- All capital letter function names in `enhanced_cursor_control.zig` (CUU → cuu, etc.)
- Generic type-returning functions (CommandContext → commandContext, etc.)  
- Functions with underscores (error_ → errorNotification, verbose_log → verboseLog)
- Created `src/shared/globals.zig` template for global state management

## 🔧 Manual Fixes Still Required

### 1. Global Variables Refactoring

The following files contain mutable global variables that need to be refactored to use the new GlobalState pattern:

#### anthropic.zig
```zig
// OLD (current)
var GLOBAL_REFRESH_STATE = RefreshState.init();
var GLOBAL_CONTENT_COLLECTOR: std.ArrayList(u8) = undefined;
var GLOBAL_ALLOCATOR: std.mem.Allocator = undefined;

// NEW (use GlobalState)
const globals = @import("../globals.zig");
// Access via: globals.GlobalState.getInstance().anthropic.*
```

#### advanced_notification.zig
```zig
// OLD (current)
var GLOBAL_ALLOCATOR: ?std.mem.Allocator = null;

// NEW (use GlobalState)
const globals = @import("../../globals.zig");
// Access via: globals.GlobalState.getInstance().smartNotification.allocator
```

#### tools.zig
```zig
// OLD (current)
var G_LIST: ?*std.ArrayList(u8) = null;
var G_ALLOCATOR: ?std.mem.Allocator = null;

// NEW (use GlobalState)
const globals = @import("../globals.zig");
// Access via: globals.GlobalState.getInstance().tools.*
```

### 2. Update Function Call Sites

Search and replace the following function calls throughout the codebase:

```bash
# Find and update calls to renamed functions
rg "\.CUU\(" --type zig    # Change to .cuu(
rg "\.CUD\(" --type zig    # Change to .cud(
rg "\.CUF\(" --type zig    # Change to .cuf(
rg "\.CUB\(" --type zig    # Change to .cub(
# ... etc for all renamed functions

# Update error_ calls
rg "\.error_\(" --type zig    # Change to .errorNotification(

# Update verbose_log calls  
rg "\.verbose_log\(" --type zig    # Change to .verboseLog(
```

### 3. Local Variables with Underscores

Fix variables with underscores in the following key files:

#### build.zig
```bash
rg "const \w+_\w+ =" build.zig | grep -v "^const [A-Z_]"
# Fix any that aren't constants (should be camelCase)
```

#### engine.zig
```bash
rg "(const|var) \w+_\w+" src/core/engine.zig | grep -v "^(const|var) [A-Z_]"
# Convert snake_case to camelCase
```

#### Other files
```bash
# Find all remaining violations
rg "(const|var) [a-z]\w*_\w+" --type zig | grep -v test | head -20
```

### 4. Update Import References

If any modules import the renamed functions directly:
```zig
// OLD
const CUU = @import("enhanced_cursor_control.zig").CUU;

// NEW
const cuu = @import("enhanced_cursor_control.zig").cuu;
```

## Testing After Fixes

1. **Build test**:
   ```bash
   zig build
   ```

2. **Run all tests**:
   ```bash
   zig build test --summary all
   ```

3. **Test specific agents**:
   ```bash
   zig build -Dagent=markdown test
   zig build -Dagent=test-agent test
   ```

## Validation Commands

After completing all manual fixes, validate with:

```bash
# Should return no results (only type definitions allowed)
rg "pub fn [A-Z][A-Z]" --type zig | grep -v "pub fn [A-Z][a-z]"

# Should return no results
rg "pub fn \w+_" --type zig

# Should only show true constants (ALL_CAPS)
rg "^(var|const) [A-Z_]+" --type zig | grep -v "^const [A-Z_]"

# Should return no results (no snake_case variables)
rg "^\s*(var|const) [a-z]\w*_\w+" --type zig
```

## Priority Order

1. **High Priority**: Fix global variables (affects runtime behavior)
2. **Medium Priority**: Update function call sites (compilation errors)
3. **Low Priority**: Fix local variable names (style consistency)