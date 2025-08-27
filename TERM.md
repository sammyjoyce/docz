### **Project Goal**

The primary objective is to refactor the `docz/src/shared/term` module by organizing its numerous files into a clean, hierarchical namespace using nested structs. This will improve code organization, discoverability, and maintainability, making the module's API more intuitive and scalable.

### **Phase 1: Analysis and Planning**

This phase involves analyzing the existing file structure to identify logical groups that will form the new namespaces.

1.  **Identify Core Namespaces**: The current file structure in `docz/src/shared/term` and its subdirectories can be logically grouped into the following primary namespaces:
    *   **`ansi`**: Low-level ANSI sequence constants and generators.
    *   **`buffer`**: Cell and screen buffer management (`cellbuf.zig`, `cellbuf_extended.zig`).
    *   **`color`**: All color-related functionality, including types, conversions, palettes, and control sequences.
    *   **`control`**: Cursor and screen manipulation (moving, clearing, scrolling).
    *   **`core`**: Foundational elements like error definitions, PTY management, and terminal state.
    *   **`graphics`**: Terminal graphics protocols (Sixel, Kitty, iTerm2) and rendering logic.
    *   **`input`**: Keyboard and mouse event definitions, parsers, and protocols.
    *   **`query`**: Functions for querying terminal attributes and state.
    *   **`shell`**: Shell integration protocols (FinalTerm, iTerm2).
    *   **`unicode`**: Grapheme analysis, character width (`wcwidth`), and Unicode-based rendering.
    *   **`io`**: Low-level terminal readers and writers.

2.  **File Consolidation Strategy**: Many files have overlapping responsibilities, especially concerning color. The plan is to merge these into a smaller, more cohesive set of files within their new namespaces.
    *   **Merge Color Files**: Consolidate the numerous files from `term/ansi/` (e.g., `color.zig`, `colors.zig`, `color_control.zig`, `adaptive_colors.zig`) and `term/color/` into a unified `term/color/` module.
    *   **Merge Input Files**: Integrate files from `term/input/` and relevant files from `term/ansi/` (e.g., `keys.zig`, `kitty_keyboard.zig`) into a single `term/input/` module.
    *   **Merge Control Files**: Combine files from `term/control/` with related files from `term/ansi/` (e.g., `screen_control.zig`) into a new `term/control/` module.
    *   **Integrate New Features**: The functionalities described in `TERMINAL_IMPLEMENTATION.md` (like `ansi/cellbuf_extended.zig` and a potential `input_extra.zig`) will be merged into their respective new modules (`buffer` and `input`) rather than being kept separate.

### **Phase 2: Directory Restructuring**

This phase involves creating a new directory structure that reflects the planned namespaces and moving the existing files accordingly. This should be done in a new `src/shared/term_refactored` directory to allow for incremental changes without breaking the existing module.

**New Directory Structure:**

```txt
docz/src/shared/term_refactored/
├── mod.zig
├── term.zig
├── ansi/
│   ├── mod.zig
│   └── ... (Passthrough logic, constants)
├── buffer/
│   ├── mod.zig
│   └── ... (Cell, Buffer implementations)
├── color/
│   ├── mod.zig
│   └── ... (Types, conversions, palettes, control)
├── control/
│   ├── mod.zig
│   └── ... (Cursor, screen, mode)
├── core/
│   ├── mod.zig
│   └── ... (Error, capabilities, pty, state, termios)
├── graphics/
│   ├── mod.zig
│   └── ... (Protocols: kitty, sixel, iterm2; renderers)
├── input/
│   ├── mod.zig
│   └── ... (Events, keyboard, mouse, parser, paste)
├── io/
│   ├── mod.zig
│   └── ... (Reader, writer)
├── query/
│   ├── mod.zig
│   └── ... (Device attributes, status reports)
├── shell/
│   ├── mod.zig
│   └── ... (Protocols: finalterm, iterm2; integration)
└── unicode/
    ├── mod.zig
    └── ... (Grapheme, width, bidi, charset)
```

**File Migration Plan:**

A detailed mapping of old files to their new locations will be executed. For example:
*   `docz/src/shared/term/cellbuf.zig` -> `docz/src/shared/term_refactored/buffer/cell.zig`
*   `docz/src/shared/term/ansi/color.zig` -> `docz/src/shared/term_refactored/color/ansi.zig`
*   `docz/src/shared/term/input/parser.zig` -> `docz/src/shared/term_refactored/input/parser.zig`
*   `docz/src/shared/term/pty.zig` -> `docz/src/shared/term_refactored/core/pty.zig`

### **Phase 3: Code Implementation & Refactoring**

This is the core coding phase where the hierarchical namespaces are implemented.

1.  **Create Namespace Structs**: Each new subdirectory will get a `mod.zig` file that defines and exposes its public API through a nested struct.

    *Example for `docz/src/shared/term_refactored/color/mod.zig`:*
    ```zig
    pub const color = struct {
        pub const AnsiPalette = @import("ansi_palette.zig");
        pub const Conversions = @import("conversions.zig");
        pub const Distance = @import("distance.zig");
        pub const Types = @import("types.zig");
        pub const Control = @import("control.zig");
    };
    ```

2.  **Update Imports**: All `@import` statements across all moved files must be updated to point to the new, hierarchical paths. The use of a root import file can simplify this process.

    *Old Import:*
    ```zig
    const caps_mod = @import("../capabilities.zig");
    ```

    *New Import:*
    ```zig
    const core = @import("../core/mod.zig");
    const caps_mod = core.capabilities;
    ```

3.  **Build the Top-Level `term` Module**: The main `mod.zig` in `term_refactored` will assemble all the namespaces into the final, public `term` struct.

    *Example for `docz/src/shared/term_refactored/mod.zig`:*
    ```zig
    pub const term = struct {
        // Core Functionality
        pub const core = @import("core/mod.zig");
        pub const io = @import("io/mod.zig");
        pub const buffer = @import("buffer/mod.zig");

        // Feature Modules
        pub const ansi = @import("ansi/mod.zig");
        pub const color = @import("color/mod.zig");
        pub const control = @import("control/mod.zig");
        pub const input = @import("input/mod.zig");
        pub const graphics = @import("graphics/mod.zig");
        pub const shell = @import("shell/mod.zig");
        pub const unicode = @import("unicode/mod.zig");
        pub const query = @import("query/mod.zig");

        // Expose the main Terminal interface at the top level
        pub const Terminal = @import("term.zig").Terminal;
    };
    ```

4.  **Refine and Consolidate**: Review the newly organized modules to identify and remove any remaining redundancies. Ensure a consistent API design across all namespaces. For example, ensure all modules that generate ANSI sequences do so through a consistent mechanism.

### **Phase 4: Verification and Cleanup**

The final phase ensures the refactor is successful and the old code is cleanly removed.

1.  **Compile and Test**: Compile the entire `docz` project with the new `term_refactored` module. Run all existing tests and add new ones to verify the refactored structure.
2.  **Integration Testing**: Manually test the TUI/CLI applications within the `docz` project to ensure that all terminal interactions function as expected.
3.  **Code Swap**: Once all tests pass and verification is complete:
    a. Delete the old `docz/src/shared/term` directory.
    b. Rename `docz/src/shared/term_refactored` to `docz/src/shared/term`.
4.  **Update Documentation**: Update `TERMINAL_IMPLEMENTATION.md` and any other relevant documentation to reflect the new module structure, API, and usage examples. For instance, examples should now use the new namespaced access pattern (e.g., `term.input.Key`, `term.color.rgb(...)`).
