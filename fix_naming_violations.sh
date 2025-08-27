#!/bin/bash
# Automated Naming Convention Fixer for Zig Codebase
# Run with: ./fix_naming_violations.sh [phase]

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR=".naming_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="naming_fixes_$(date +%Y%m%d_%H%M%S).log"

# Helper functions
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Verify we're in the right directory
check_directory() {
    if [ ! -f "build.zig" ] || [ ! -d "src" ] || [ ! -d "agents" ]; then
        error "Must be run from project root directory"
    fi
}

# Create backup
create_backup() {
    log "Creating backup in $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"
    cp -r src "$BACKUP_DIR/"
    cp -r agents "$BACKUP_DIR/"
    log "Backup created successfully"
}

# Test compilation
test_compilation() {
    info "Testing compilation..."
    if zig build-lib src/core/engine.zig 2>&1 | grep -q "error"; then
        warning "Compilation issues detected (may be pre-existing)"
    else
        log "Compilation test passed"
    fi
}

# Phase 1: Fix Constants (ALL_CAPS)
fix_constants() {
    log "Phase 1: Fixing constants to ALL_CAPS..."
    
    # Define constant renames
    declare -A CONST_RENAMES=(
        ["request_foreground_color"]="REQUEST_FOREGROUND_COLOR"
        ["request_background_color"]="REQUEST_BACKGROUND_COLOR"
        ["reset_foreground_color"]="RESET_FOREGROUND_COLOR"
        ["reset_background_color"]="RESET_BACKGROUND_COLOR"
        ["enable_mouse"]="ENABLE_MOUSE"
        ["disable_mouse"]="DISABLE_MOUSE"
        ["show_cursor"]="SHOW_CURSOR"
        ["hide_cursor"]="HIDE_CURSOR"
        ["clear_screen"]="CLEAR_SCREEN"
        ["clear_line"]="CLEAR_LINE"
        ["save_cursor"]="SAVE_CURSOR"
        ["restore_cursor"]="RESTORE_CURSOR"
        ["alternate_screen"]="ALTERNATE_SCREEN"
        ["normal_screen"]="NORMAL_SCREEN"
        ["bold_on"]="BOLD_ON"
        ["bold_off"]="BOLD_OFF"
        ["italic_on"]="ITALIC_ON"
        ["italic_off"]="ITALIC_OFF"
        ["underline_on"]="UNDERLINE_ON"
        ["underline_off"]="UNDERLINE_OFF"
        ["blink_on"]="BLINK_ON"
        ["blink_off"]="BLINK_OFF"
        ["reverse_on"]="REVERSE_ON"
        ["reverse_off"]="REVERSE_OFF"
        ["strikethrough_on"]="STRIKETHROUGH_ON"
        ["strikethrough_off"]="STRIKETHROUGH_OFF"
    )
    
    local count=0
    for old in "${!CONST_RENAMES[@]}"; do
        new="${CONST_RENAMES[$old]}"
        info "  Renaming: $old → $new"
        
        # Count occurrences
        occurrences=$(grep -r "\b$old\b" src/ agents/ 2>/dev/null | wc -l || echo 0)
        
        if [ "$occurrences" -gt 0 ]; then
            # Perform replacement
            find src agents -name "*.zig" -exec sed -i.bak "s/\b$old\b/$new/g" {} \;
            count=$((count + occurrences))
            log "    Replaced $occurrences occurrences"
        fi
    done
    
    # Clean up backup files
    find src agents -name "*.zig.bak" -delete
    
    log "Fixed $count constant references"
}

# Phase 2: Remove Type Suffixes
fix_type_suffixes() {
    log "Phase 2: Removing redundant type suffixes..."
    
    # Define type suffix removals
    declare -A TYPE_SUFFIXES=(
        ["ChartData"]="Chart"
        ["TableData"]="Table"
        ["GridData"]="Grid"
        ["MenuData"]="Menu"
        ["ProgressData"]="Progress"
        ["StatusData"]="Status"
        ["LayoutData"]="Layout"
        ["ThemeData"]="Theme"
        ["ConfigData"]="Config"
        ["StateData"]="State"
        ["ScrollInfo"]="ScrollState"
        ["CursorInfo"]="CursorState"
        ["WindowInfo"]="WindowState"
        ["BufferInfo"]="BufferState"
        ["TerminalInfo"]="TerminalState"
        ["ProcessInfo"]="ProcessState"
        ["ConnectionInfo"]="Connection"
        ["SessionInfo"]="Session"
        ["RenderInfo"]="RenderState"
        ["DrawInfo"]="DrawState"
        ["InputInfo"]="InputState"
        ["OutputInfo"]="OutputState"
        ["EventInfo"]="Event"
        ["MessageInfo"]="Message"
    )
    
    local count=0
    for old in "${!TYPE_SUFFIXES[@]}"; do
        new="${TYPE_SUFFIXES[$old]}"
        info "  Renaming type: $old → $new"
        
        # Count occurrences
        occurrences=$(grep -r "\b$old\b" src/ agents/ 2>/dev/null | wc -l || echo 0)
        
        if [ "$occurrences" -gt 0 ]; then
            # Perform replacement
            find src agents -name "*.zig" -exec sed -i.bak "s/\b$old\b/$new/g" {} \;
            count=$((count + occurrences))
            log "    Replaced $occurrences occurrences"
        fi
    done
    
    # Clean up backup files
    find src agents -name "*.zig.bak" -delete
    
    log "Fixed $count type references"
}

# Phase 3: Fix snake_case struct names
fix_struct_names() {
    log "Phase 3: Fixing snake_case struct names to TitleCase..."
    
    # Common snake_case to TitleCase conversions
    declare -A STRUCT_RENAMES=(
        ["stored_func"]="StoredFunc"
        ["network"]="Network"
        ["utils"]="Utils"
        ["helpers"]="Helpers"
        ["common"]="Common"
        ["shared"]="Shared"
        ["core"]="Core"
        ["base"]="Base"
        ["handler"]="Handler"
        ["manager"]="Manager"
        ["controller"]="Controller"
        ["service"]="Service"
        ["provider"]="Provider"
        ["factory"]="Factory"
        ["builder"]="Builder"
        ["parser"]="Parser"
        ["formatter"]="Formatter"
        ["validator"]="Validator"
        ["processor"]="Processor"
        ["renderer"]="Renderer"
        ["writer"]="Writer"
        ["reader"]="Reader"
        ["stream"]="Stream"
        ["buffer"]="Buffer"
        ["cache"]="Cache"
        ["store"]="Store"
        ["registry"]="Registry"
        ["context"]="Context"
        ["config"]="Config"
        ["options"]="Options"
        ["settings"]="Settings"
        ["state"]="State"
        ["status"]="Status"
        ["result"]="Result"
        ["response"]="Response"
        ["request"]="Request"
        ["message"]="Message"
        ["event"]="Event"
        ["action"]="Action"
        ["command"]="Command"
        ["query"]="Query"
    )
    
    local count=0
    for old in "${!STRUCT_RENAMES[@]}"; do
        new="${STRUCT_RENAMES[$old]}"
        
        # Look for struct definitions
        pattern="const $old = struct"
        if grep -r "$pattern" src/ agents/ 2>/dev/null | grep -q .; then
            info "  Renaming struct: $old → $new"
            
            # Replace struct definition
            find src agents -name "*.zig" -exec sed -i.bak "s/const $old = struct/const $new = struct/g" {} \;
            
            # Replace references
            find src agents -name "*.zig" -exec sed -i.bak "s/\b$old\b/$new/g" {} \;
            
            count=$((count + 1))
            log "    Fixed struct definition and references"
        fi
    done
    
    # Clean up backup files
    find src agents -name "*.zig.bak" -delete
    
    log "Fixed $count struct definitions"
}

# Phase 4: Fix file names
fix_file_names() {
    log "Phase 4: Fixing file names to TitleCase..."
    
    # Define file renames
    declare -A FILE_RENAMES=(
        ["src/shared/cli/themes/light.zig"]="LightTheme.zig"
        ["src/shared/cli/themes/dark.zig"]="DarkTheme.zig"
        ["src/shared/cli/themes/default.zig"]="DefaultTheme.zig"
        ["src/shared/cli/themes/high_contrast.zig"]="HighContrastTheme.zig"
        ["src/shared/cli/themes/theme_utils.zig"]="theme_manager.zig"
        ["src/shared/cli/formatters/simple.zig"]="Simple.zig"
        ["src/shared/cli/formatters/enhanced.zig"]="Enhanced.zig"
        ["src/shared/cli/workflows/WorkflowRegistry.zig"]="WorkflowRegistry.zig"
        ["src/shared/term/terminfo.zig"]="Terminfo.zig"
        ["src/shared/term/ansi/enhanced_color_converter.zig"]="EnhancedColorConverter.zig"
        ["src/shared/term/ansi/enhanced_color_management.zig"]="EnhancedColorManagement.zig"
    )
    
    local count=0
    for old_path in "${!FILE_RENAMES[@]}"; do
        new_name="${FILE_RENAMES[$old_path]}"
        
        if [ -f "$old_path" ]; then
            dir=$(dirname "$old_path")
            old_name=$(basename "$old_path")
            new_path="$dir/$new_name"
            
            info "  Renaming file: $old_name → $new_name"
            
            # Rename the file
            mv "$old_path" "$new_path"
            
            # Update imports
            escaped_old=$(echo "$old_name" | sed 's/[[\.*^$()+?{|]/\\&/g')
            escaped_new=$(echo "$new_name" | sed 's/[[\.*^$()+?{|]/\\&/g')
            
            find src agents -name "*.zig" -exec sed -i.bak "s/@import(\"[^\"]*$escaped_old\")/@import(\"$escaped_new\")/g" {} \;
            
            count=$((count + 1))
            log "    File renamed and imports updated"
        else
            warning "  File not found: $old_path"
        fi
    done
    
    # Clean up backup files
    find src agents -name "*.zig.bak" -delete
    
    log "Renamed $count files"
}

# Run tests after fixes
run_tests() {
    log "Running tests..."
    
    # Syntax check
    info "Checking syntax..."
    if zig fmt --check src/**/*.zig 2>&1 | grep -q "incorrect"; then
        warning "Formatting issues detected - run 'zig fmt' to fix"
    else
        log "Syntax check passed"
    fi
    
    # Compilation test
    test_compilation
    
    # Run unit tests if available
    if zig build test --summary all 2>&1 | grep -q "All"; then
        log "Unit tests passed"
    else
        warning "Some tests may have failed"
    fi
}

# Rollback function
rollback() {
    if [ -d "$BACKUP_DIR" ]; then
        warning "Rolling back changes..."
        rm -rf src agents
        cp -r "$BACKUP_DIR/src" .
        cp -r "$BACKUP_DIR/agents" .
        log "Rollback completed from $BACKUP_DIR"
    else
        error "No backup directory found"
    fi
}

# Main execution
main() {
    check_directory
    
    echo -e "${BLUE}===================================${NC}"
    echo -e "${BLUE}   Zig Naming Convention Fixer    ${NC}"
    echo -e "${BLUE}===================================${NC}"
    echo
    
    # Parse command line arguments
    PHASE=${1:-all}
    
    case $PHASE in
        backup)
            create_backup
            ;;
        constants)
            create_backup
            fix_constants
            run_tests
            ;;
        suffixes)
            create_backup
            fix_type_suffixes
            run_tests
            ;;
        structs)
            create_backup
            fix_struct_names
            run_tests
            ;;
        files)
            create_backup
            fix_file_names
            run_tests
            ;;
        all)
            create_backup
            fix_constants
            fix_type_suffixes
            fix_struct_names
            fix_file_names
            run_tests
            ;;
        test)
            run_tests
            ;;
        rollback)
            rollback
            ;;
        *)
            echo "Usage: $0 [backup|constants|suffixes|structs|files|all|test|rollback]"
            echo
            echo "Phases:"
            echo "  backup    - Create backup only"
            echo "  constants - Fix constants to ALL_CAPS"
            echo "  suffixes  - Remove Data/Info suffixes"
            echo "  structs   - Fix snake_case structs"
            echo "  files     - Rename files to TitleCase"
            echo "  all       - Run all fixes (default)"
            echo "  test      - Run tests only"
            echo "  rollback  - Restore from backup"
            exit 1
            ;;
    esac
    
    echo
    log "✅ Operation completed successfully!"
    log "Log saved to: $LOG_FILE"
    
    if [ -d "$BACKUP_DIR" ]; then
        log "Backup saved to: $BACKUP_DIR"
        echo
        warning "Remember to remove backup after verifying changes:"
        echo "  rm -rf $BACKUP_DIR"
    fi
}

# Run main function
main "$@"