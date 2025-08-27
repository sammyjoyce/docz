# Comprehensive Naming Convention Fix Strategy

## Executive Summary
This document outlines a systematic approach to fix 102+ naming violations across the codebase while minimizing breakage and ensuring safe rollback capabilities.

## Violations Overview
- **File Naming**: 11 files (snake_case → TitleCase)
- **Type Naming**: 42 structs (snake_case → TitleCase)
- **Constants**: 25+ variables (camelCase → ALL_CAPS)
- **Redundant Suffixes**: 24 types (remove "Data"/"Info" suffixes)

## Phase 1: Preparation (Day 1)

### 1.1 Create Feature Branch
```bash
# Create dedicated branch for naming fixes
git checkout -b fix/naming-conventions
git push -u origin fix/naming-conventions
```

### 1.2 Document Current State
```bash
# Generate dependency graph
zig build-exe src/core/engine.zig --show-builtin 2>&1 | grep import > imports_before.txt

# Create file manifest
find src agents -name "*.zig" -exec md5sum {} \; > checksums_before.txt

# Run existing tests to establish baseline
zig build test --summary all > test_baseline.txt 2>&1
```

### 1.3 Create Migration Helpers
```zig
// tools/naming_migration.zig
const std = @import("std");

pub fn createAlias(comptime old_name: []const u8, comptime new_type: type) type {
    return struct {
        pub const @"type" = new_type;
        
        // Deprecation warning
        pub const __deprecated = "Use " ++ @typeName(new_type) ++ " instead of " ++ old_name;
    };
}

pub fn createConstAlias(comptime old_name: []const u8, comptime new_name: []const u8, value: anytype) @TypeOf(value) {
    @compileLog("Warning: " ++ old_name ++ " is deprecated, use " ++ new_name);
    return value;
}
```

## Phase 2: Order of Operations

### 2.1 Constants First (Lowest Risk)
**Why first**: Constants have no dependencies and are leaf nodes in the dependency graph.

```bash
# Step 1: Add new ALL_CAPS constants alongside old ones
# In src/shared/term/ansi/color.zig:
pub const REQUEST_FOREGROUND_COLOR = "\x1b]10;?\x1b\\";
pub const request_foreground_color = REQUEST_FOREGROUND_COLOR; // Temporary alias

# Step 2: Update all references to use ALL_CAPS
rg "request_foreground_color" --files-with-matches | xargs sed -i 's/request_foreground_color/REQUEST_FOREGROUND_COLOR/g'

# Step 3: Remove old aliases after verification
```

**Commit Strategy**:
```bash
git add -p  # Review each change
git commit -m "refactor: migrate terminal color constants to ALL_CAPS naming

- Add ALL_CAPS versions of all color constants
- Maintain backward compatibility with aliases
- Updates references across 15 files"
```

### 2.2 Redundant Suffix Removal (Medium Risk)
**Why second**: Type changes affect more files but can use type aliases for migration.

```zig
// Step 1: Create new types without suffixes
pub const Chart = struct { ... };  // Was ChartData
pub const ScrollState = struct { ... };  // Was ScrollInfo

// Step 2: Add deprecation aliases
pub const ChartData = Chart;  // @deprecated
pub const ScrollInfo = ScrollState;  // @deprecated

// Step 3: Gradually migrate usage
```

**Migration Script**:
```bash
#!/bin/bash
# fix_type_suffixes.sh

declare -A TYPE_RENAMES=(
    ["ChartData"]="Chart"
    ["ScrollInfo"]="ScrollState"
    ["ConnectionInfo"]="Connection"
    ["StateInfo"]="State"
    # ... add all 24 types
)

for old in "${!TYPE_RENAMES[@]}"; do
    new="${TYPE_RENAMES[$old]}"
    echo "Renaming $old to $new..."
    
    # Find and replace in all .zig files
    find src agents -name "*.zig" -exec sed -i "s/\b$old\b/$new/g" {} \;
    
    # Verify changes
    echo "Files affected:"
    rg "$new" --files-with-matches | wc -l
done
```

### 2.3 Type Naming (snake_case → TitleCase)
**Why third**: Struct renames have wider impact but can be handled systematically.

```zig
// Step 1: Rename anonymous structs
// Before:
const stored_func = struct { ... };

// After:
const StoredFunc = struct { ... };
const stored_func = StoredFunc; // Temporary alias for compatibility

// Step 2: Update module namespace structs
// Before:
pub const network = struct { ... };

// After:
pub const Network = struct { ... };
pub const network = Network; // Compatibility alias
```

**Batch Processing**:
```bash
# Generate rename mapping
cat << 'EOF' > type_renames.txt
stored_func:StoredFunc
network:Network
utils:Utils
# ... rest of 42 types
EOF

# Apply renames with verification
while IFS=: read -r old new; do
    echo "Processing: $old → $new"
    
    # Count occurrences before
    before_count=$(rg "\b$old\b" --count-matches | awk -F: '{sum+=$2} END {print sum}')
    
    # Perform rename
    find src agents -name "*.zig" -exec sed -i "s/\b$old\b/$new/g" {} \;
    
    # Count occurrences after
    after_count=$(rg "\b$new\b" --count-matches | awk -F: '{sum+=$2} END {print sum}')
    
    echo "  Replaced $before_count occurrences"
    
    # Test compile after each major change
    zig build-lib src/core/engine.zig 2>&1 | grep -q error && echo "  ⚠️  Compilation issues detected"
done < type_renames.txt
```

### 2.4 File Naming (Highest Risk)
**Why last**: File renames affect imports across entire codebase.

```bash
# Step 1: Create mapping of file renames
cat << 'EOF' > file_renames.txt
src/shared/cli/themes/light.zig:LightTheme.zig
src/shared/cli/themes/dark.zig:DarkTheme.zig
src/shared/cli/themes/default.zig:DefaultTheme.zig
src/shared/cli/themes/high_contrast.zig:HighContrastTheme.zig
src/shared/cli/themes/theme_utils.zig:theme_manager.zig
src/shared/cli/formatters/simple.zig:Simple.zig
src/shared/cli/formatters/enhanced.zig:Enhanced.zig
src/shared/cli/workflows/WorkflowRegistry.zig:WorkflowRegistry.zig
src/shared/term/terminfo.zig:Terminfo.zig
src/shared/term/ansi/enhanced_color_converter.zig:EnhancedColorConverter.zig
src/shared/term/ansi/enhanced_color_management.zig:EnhancedColorManagement.zig
EOF

# Step 2: Rename files and update imports atomically
while IFS=: read -r old_path new_name; do
    dir=$(dirname "$old_path")
    old_name=$(basename "$old_path")
    new_path="$dir/$new_name"
    
    echo "Renaming: $old_path → $new_path"
    
    # Rename the file
    git mv "$old_path" "$new_path"
    
    # Update all imports
    old_import=${old_path#src/}
    new_import=${new_path#src/}
    
    find src agents -name "*.zig" -exec sed -i "s|@import(\".*$old_name\")|@import(\"$new_name\")|g" {} \;
    
    # Handle relative imports
    find src agents -name "*.zig" -exec sed -i "s|@import(\"\.\./.*$old_name\")|@import(\"../$new_name\")|g" {} \;
    
done < file_renames.txt
```

## Phase 3: Import/Reference Handling

### 3.1 Smart Import Updates
```zig
// Create compatibility layer in mod.zig files
// src/shared/cli/themes/mod.zig

// New imports (TitleCase)
pub const Light = @import("Light.zig");
pub const Dark = @import("Dark.zig");
pub const Default = @import("Default.zig");

// Compatibility aliases (temporary)
pub const light = Light;
pub const dark = Dark;
pub const default_theme = Default;  // Note: 'default' is keyword
```

### 3.2 Gradual Migration Pattern
```zig
// Phase 1: Add new names alongside old
pub const MyStruct = struct { ... };
pub const my_struct = MyStruct; // Deprecated alias

// Phase 2: Update imports to use new names
const themes = @import("shared/cli/themes/mod.zig");
const Light = themes.Light;  // New
// const light = themes.light;  // Old (commented out)

// Phase 3: Remove aliases after full migration
```

## Phase 4: Git Commit Strategy

### 4.1 Atomic Commits by Category
```bash
# Commit 1: Constants
git add src/shared/term/ansi/*.zig
git commit -m "refactor(term): migrate ANSI constants to ALL_CAPS convention

- Convert 25+ terminal color constants to ALL_CAPS
- Maintain backward compatibility with lowercase aliases
- No functional changes"

# Commit 2: Remove type suffixes
git add src/shared/tui/widgets/*.zig src/shared/render/components/*.zig
git commit -m "refactor(types): remove redundant Data/Info suffixes from type names

- ChartData → Chart (10 types)
- ScrollInfo → ScrollState (14 types)
- Add compatibility aliases for gradual migration"

# Commit 3: Fix struct naming
git add src/shared/**/*.zig
git commit -m "refactor(types): convert snake_case structs to TitleCase

- Fix 42 struct definitions to follow Zig conventions
- Update all references and imports
- Maintain compatibility layer"

# Commit 4: File renames
git add -A
git commit -m "refactor(files): rename snake_case files to TitleCase

- Rename 11 files to follow single-type naming convention
- Update all import statements
- Verify build and tests pass"
```

### 4.2 Verification Between Commits
```bash
# Run after each commit
zig build test --summary all
zig fmt --check src/**/*.zig
git diff --name-status HEAD~1
```

## Phase 5: Testing Strategy

### 5.1 Progressive Testing
```bash
#!/bin/bash
# test_naming_migration.sh

echo "=== Testing Naming Migration ==="

# Level 1: Syntax check
echo "1. Checking syntax..."
zig fmt --check src/**/*.zig agents/**/*.zig || exit 1

# Level 2: Compilation test
echo "2. Testing compilation..."
zig build-lib src/core/engine.zig || exit 1

# Level 3: Unit tests
echo "3. Running unit tests..."
zig build test --summary all || exit 1

# Level 4: Agent tests
echo "4. Testing agents..."
for agent in markdown test-agent; do
    echo "  Testing $agent..."
    zig build -Dagent=$agent test || exit 1
done

# Level 5: Integration test
echo "5. Running integration tests..."
zig build -Dagent=markdown run -- "test message" || exit 1

echo "✅ All tests passed!"
```

### 5.2 Regression Testing
```zig
// tests/naming_migration_test.zig
const std = @import("std");
const testing = std.testing;

test "verify type aliases work" {
    const themes = @import("shared/cli/themes/mod.zig");
    
    // Both should work during migration
    try testing.expect(themes.Light == themes.light);
    try testing.expect(@TypeOf(themes.Light) == @TypeOf(themes.light));
}

test "verify constant aliases" {
    const colors = @import("shared/term/ansi/color.zig");
    
    // Both old and new should be equal
    try testing.expectEqualStrings(
        colors.REQUEST_FOREGROUND_COLOR,
        colors.request_foreground_color
    );
}
```

## Phase 6: Rollback Plan

### 6.1 Git Rollback Strategy
```bash
# Tag before starting
git tag pre-naming-fix
git push origin pre-naming-fix

# If issues arise, rollback options:

# Option 1: Revert specific commit
git revert <commit-hash>

# Option 2: Reset to tag
git reset --hard pre-naming-fix

# Option 3: Create fix branch
git checkout -b fix/naming-issues
git cherry-pick <good-commits>
```

### 6.2 Incremental Rollback
```bash
# Rollback specific file types only
git checkout HEAD~1 -- 'src/**/*Data.zig' 'src/**/*Info.zig'

# Rollback specific directory
git checkout HEAD~1 -- src/shared/cli/themes/

# Keep some changes, revert others
git revert --no-commit <commit>
git reset HEAD
git add -p  # Selectively stage
```

### 6.3 Emergency Recovery
```bash
#!/bin/bash
# emergency_rollback.sh

echo "⚠️  Emergency rollback initiated"

# Stash any uncommitted changes
git stash save "Emergency rollback stash"

# Reset to known good state
git fetch origin
git reset --hard origin/main

# Restore from backup if available
if [ -f checksums_before.txt ]; then
    echo "Verifying file integrity..."
    md5sum -c checksums_before.txt
fi

echo "✅ Rollback complete"
echo "Stashed changes available via: git stash list"
```

## Phase 7: Post-Migration Cleanup

### 7.1 Remove Compatibility Layer (After 2 weeks)
```zig
// Remove all deprecated aliases
// Step 1: Search for usage
rg "stored_func|my_struct" --files-with-matches

// Step 2: Remove aliases if no usage found
// Remove lines like:
pub const stored_func = StoredFunc; // DELETE THIS
pub const my_struct = MyStruct;     // DELETE THIS
```

### 7.2 Documentation Updates
```markdown
# Update STYLE.md with examples
- ✅ File naming: `Parser.zig` for single type, `utils.zig` for namespace
- ✅ Type naming: `TitleCase` for all structs/unions/enums
- ✅ Constants: `ALL_CAPS_WITH_UNDERSCORES`
- ✅ No redundant suffixes: `Chart` not `ChartData`
```

### 7.3 CI/CD Integration
```yaml
# .github/workflows/naming-check.yaml
name: Naming Convention Check
on: [push, pull_request]

jobs:
  check-naming:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: goto-bus-stop/setup-zig@v2
      
      - name: Check naming conventions
        run: |
          # Check for snake_case files that should be TitleCase
          ! find src -name "*_*.zig" -path "*/cli/themes/*" -o -path "*/formatters/*"
          
          # Check for snake_case structs
          ! rg "const [a-z_]+ = struct" src/
          
          # Check for non-ALL_CAPS constants in color files
          ! rg "const [a-z_]+.*color" src/shared/term/ansi/
```

## Timeline Estimate
- **Phase 1-2**: 1 day (Prep + Constants/Suffixes)
- **Phase 3-4**: 1 day (Types + Files)
- **Phase 5**: 0.5 day (Testing)
- **Phase 6**: Reserved for issues
- **Phase 7**: 2 weeks later

## Success Metrics
- ✅ All tests pass after migration
- ✅ No runtime errors in production
- ✅ Build time remains consistent (±5%)
- ✅ Zero naming convention warnings from linter
- ✅ Clean `zig fmt` output
- ✅ Successful deployment of all agents

## Risk Mitigation
1. **Test on separate branch first**
2. **Run migration during low-activity period**
3. **Have team members review changes**
4. **Keep compatibility layer for 2+ weeks**
5. **Monitor error logs after deployment**
6. **Maintain rollback capability for 30 days**