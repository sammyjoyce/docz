//! Dashboard widget - Main container for data visualization components
//! Provides layout management, progressive enhancement, and coordination
//! between charts, tables, and other dashboard widgets.

const std = @import("std");
const renderer_mod = @import("../../core/renderer.zig");
const bounds_mod = @import("../../core/bounds.zig");
const layout_mod = @import("../../core/layout.zig");
const events_mod = @import("../../core/events.zig");
const terminal_mod = @import("../../../term/unified.zig");
const graphics_manager = @import("../../../term/graphics_manager.zig");

const Renderer = renderer_mod.Renderer;
const RenderContext = renderer_mod.RenderContext;
const Bounds = bounds_mod.Bounds;
const Point = bounds_mod.Point;
const Layout = layout_mod.Layout;
const MouseEvent = events_mod.MouseEvent;
const KeyEvent = events_mod.KeyEvent;

pub const Dashboard = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    layout: GridLayout,
    widgets: WidgetRegistry,
    data_sources: DataSourceRegistry,
    update_interval_ms: u32,
    responsive: bool,
    min_terminal_size: bounds_mod.TerminalSize,

    // Terminal integration
    terminal_caps: ?terminal_mod.TermCaps,
    render_mode: RenderMode,

    pub const Config = struct {
        grid_rows: u32 = 3,
        grid_cols: u32 = 3,
        update_interval_ms: u32 = 1000,
        responsive: bool = true,
        min_terminal_width: u32 = 80,
        min_terminal_height: u32 = 24,
    };

    pub const GridLayout = struct {
        rows: u32,
        cols: u32,
        cells: []Cell,
        bounds: Bounds,

        pub const Cell = struct {
            bounds: Bounds,
            widget_id: ?u32 = null,
            span_rows: u32 = 1,
            span_cols: u32 = 1,
        };

        pub fn init(allocator: std.mem.Allocator, rows: u32, cols: u32) !GridLayout {
            const total_cells = rows * cols;
            const cells = try allocator.alloc(Cell, total_cells);

            return GridLayout{
                .rows = rows,
                .cols = cols,
                .cells = cells,
                .bounds = Bounds.init(0, 0, 0, 0),
            };
        }

        pub fn deinit(self: *GridLayout, allocator: std.mem.Allocator) void {
            allocator.free(self.cells);
        }

        pub fn calculateLayout(self: *GridLayout, terminal_bounds: Bounds) void {
            self.bounds = terminal_bounds;

            const cell_width = terminal_bounds.width / self.cols;
            const cell_height = terminal_bounds.height / self.rows;

            for (0..self.rows) |row| {
                for (0..self.cols) |col| {
                    const index = row * self.cols + col;
                    self.cells[index].bounds = Bounds.init(
                        @intCast(col * cell_width + terminal_bounds.x),
                        @intCast(row * cell_height + terminal_bounds.y),
                        @intCast(cell_width),
                        @intCast(cell_height),
                    );
                }
            }
        }

        pub fn getCellBounds(self: *GridLayout, row: u32, col: u32, span_rows: u32, span_cols: u32) ?Bounds {
            if (row >= self.rows or col >= self.cols) return null;
            if (row + span_rows > self.rows or col + span_cols > self.cols) return null;

            const start_cell = &self.cells[row * self.cols + col];
            const end_row = row + span_rows - 1;
            const end_col = col + span_cols - 1;
            const end_cell = &self.cells[end_row * self.cols + end_col];

            return Bounds.init(
                start_cell.bounds.x,
                start_cell.bounds.y,
                end_cell.bounds.x + end_cell.bounds.width - start_cell.bounds.x,
                end_cell.bounds.y + end_cell.bounds.height - start_cell.bounds.y,
            );
        }
    };

    pub const WidgetRegistry = struct {
        widgets: std.ArrayList(*DashboardWidget),
        next_id: u32,

        pub fn init(allocator: std.mem.Allocator) WidgetRegistry {
            return WidgetRegistry{
                .widgets = std.ArrayList(*DashboardWidget).init(allocator),
                .next_id = 1,
            };
        }

        pub fn deinit(self: *WidgetRegistry) void {
            for (self.widgets.items) |widget| {
                widget.deinit();
            }
            self.widgets.deinit();
        }

        pub fn register(self: *WidgetRegistry, widget: *DashboardWidget) !u32 {
            const id = self.next_id;
            self.next_id += 1;
            widget.id = id;
            try self.widgets.append(widget);
            return id;
        }

        pub fn getWidget(self: *WidgetRegistry, id: u32) ?*DashboardWidget {
            for (self.widgets.items) |widget| {
                if (widget.id == id) return widget;
            }
            return null;
        }
    };

    pub const DataSourceRegistry = struct {
        sources: std.HashMap([]const u8, *DataSource, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

        pub fn init(allocator: std.mem.Allocator) DataSourceRegistry {
            return DataSourceRegistry{
                .sources = std.HashMap([]const u8, *DataSource, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            };
        }

        pub fn deinit(self: *DataSourceRegistry) void {
            var iterator = self.sources.iterator();
            while (iterator.next()) |entry| {
                entry.value_ptr.*.deinit();
            }
            self.sources.deinit();
        }

        pub fn register(self: *DataSourceRegistry, name: []const u8, source: *DataSource) !void {
            try self.sources.put(name, source);
        }

        pub fn getSource(self: *DataSourceRegistry, name: []const u8) ?*DataSource {
            return self.sources.get(name);
        }
    };

    pub const DashboardWidget = struct {
        id: u32 = 0,
        position: GridPosition,
        bounds: Bounds = Bounds.init(0, 0, 0, 0),
        visible: bool = true,

        // Widget interface
        vtable: *const VTable,
        impl: *anyopaque,

        pub const GridPosition = struct {
            row: u32,
            col: u32,
            span_rows: u32 = 1,
            span_cols: u32 = 1,
        };

        pub const VTable = struct {
            render: *const fn (*anyopaque, *Renderer, RenderContext) anyerror!void,
            handleInput: *const fn (*anyopaque, InputEvent) anyerror!void,
            deinit: *const fn (*anyopaque) void,
        };

        pub fn init(impl: anytype, position: GridPosition) DashboardWidget {
            const T = @TypeOf(impl);
            const vtable = &VTable{
                .render = struct {
                    fn render(ptr: *anyopaque, renderer: *Renderer, ctx: RenderContext) anyerror!void {
                        const self: *T = @ptrCast(@alignCast(ptr));
                        return self.render(renderer, ctx);
                    }
                }.render,
                .handleInput = struct {
                    fn handleInput(ptr: *anyopaque, event: InputEvent) anyerror!void {
                        const self: *T = @ptrCast(@alignCast(ptr));
                        return self.handleInput(event);
                    }
                }.handleInput,
                .deinit = struct {
                    fn deinit(ptr: *anyopaque) void {
                        const self: *T = @ptrCast(@alignCast(ptr));
                        return self.deinit();
                    }
                }.deinit,
            };

            return DashboardWidget{
                .position = position,
                .vtable = vtable,
                .impl = impl,
            };
        }

        pub fn render(self: *DashboardWidget, renderer: *Renderer, ctx: RenderContext) !void {
            if (!self.visible) return;
            var widget_ctx = ctx;
            widget_ctx.bounds = self.bounds;
            return self.vtable.render(self.impl, renderer, widget_ctx);
        }

        pub fn handleInput(self: *DashboardWidget, event: InputEvent) !void {
            if (!self.visible) return;
            return self.vtable.handleInput(self.impl, event);
        }

        pub fn deinit(self: *DashboardWidget) void {
            self.vtable.deinit(self.impl);
        }
    };

    pub const DataSource = struct {
        update_fn: *const fn (*DataSource) anyerror!void,
        data: *anyopaque,
        last_update: i64 = 0,

        pub fn update(self: *DataSource) !void {
            self.last_update = std.time.timestamp();
            return self.update_fn(self);
        }
    };

    pub const RenderMode = struct {
        graphics: GraphicsMode,
        colors: ColorMode,
        clipboard: bool,
        notifications: bool,
        hyperlinks: bool,
        mouse: bool,

        pub const GraphicsMode = enum {
            kitty,
            sixel,
            unicode,
            ascii,
            none,
        };

        pub const ColorMode = enum {
            truecolor,
            indexed256,
            ansi16,
            monochrome,
        };
    };

    pub const InputEvent = union(enum) {
        key: KeyEvent,
        mouse: MouseEvent,
        resize: bounds_mod.TerminalSize,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        const layout = try GridLayout.init(allocator, config.grid_rows, config.grid_cols);

        return Self{
            .allocator = allocator,
            .layout = layout,
            .widgets = WidgetRegistry.init(allocator),
            .data_sources = DataSourceRegistry.init(allocator),
            .update_interval_ms = config.update_interval_ms,
            .responsive = config.responsive,
            .min_terminal_size = bounds_mod.TerminalSize{
                .width = config.min_terminal_width,
                .height = config.min_terminal_height,
            },
            .terminal_caps = null,
            .render_mode = RenderMode{
                .graphics = .ascii,
                .colors = .ansi16,
                .clipboard = false,
                .notifications = false,
                .hyperlinks = false,
                .mouse = false,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.widgets.deinit();
        self.data_sources.deinit();
        self.layout.deinit(self.allocator);
    }

    pub fn detectCapabilities(self: *Self, renderer: *Renderer) !void {
        // Try to get terminal capabilities from renderer
        if (renderer.getTermCaps()) |caps| {
            self.terminal_caps = caps;
            self.render_mode = self.selectRenderMode(caps);
        }
    }

    fn selectRenderMode(_: *Self, caps: terminal_mod.TermCaps) RenderMode {
        return RenderMode{
            .graphics = if (caps.supportsKittyGraphics) .kitty else if (caps.supportsSixel) .sixel else if (caps.supportsUnicode) .unicode else .ascii,
            .colors = if (caps.supportsTrueColor) .truecolor else if (caps.supports256Color) .indexed256 else .ansi16,
            .clipboard = caps.supportsClipboardOsc52,
            .notifications = caps.supportsNotifyOsc9,
            .hyperlinks = caps.supportsHyperlinkOsc8,
            .mouse = caps.supportsMouse,
        };
    }

    pub fn addWidget(self: *Self, widget: *DashboardWidget) !u32 {
        const id = try self.widgets.register(widget);

        // Calculate widget bounds based on grid position
        if (self.layout.getCellBounds(widget.position.row, widget.position.col, widget.position.span_rows, widget.position.span_cols)) |bounds| {
            widget.bounds = bounds;
        }

        return id;
    }

    pub fn removeWidget(self: *Self, id: u32) bool {
        for (self.widgets.widgets.items, 0..) |widget, i| {
            if (widget.id == id) {
                _ = self.widgets.widgets.swapRemove(i);
                widget.deinit();
                return true;
            }
        }
        return false;
    }

    pub fn addDataSource(self: *Self, name: []const u8, source: *DataSource) !void {
        try self.data_sources.register(name, source);
    }

    pub fn updateData(self: *Self) !void {
        var iterator = self.data_sources.sources.iterator();
        while (iterator.next()) |entry| {
            try entry.value_ptr.*.update();
        }
    }

    pub fn render(self: *Self, renderer: *Renderer, ctx: RenderContext) !void {
        // Update layout for current terminal size
        self.layout.calculateLayout(ctx.bounds);

        // Update widget bounds
        for (self.widgets.widgets.items) |widget| {
            if (self.layout.getCellBounds(widget.position.row, widget.position.col, widget.position.span_rows, widget.position.span_cols)) |bounds| {
                widget.bounds = bounds;
            }
        }

        // Render all widgets
        for (self.widgets.widgets.items) |widget| {
            try widget.render(renderer, ctx);
        }
    }

    pub fn handleInput(self: *Self, event: InputEvent) !void {
        // Handle dashboard-level inputs first
        switch (event) {
            .resize => |size| {
                // Recalculate layout on terminal resize
                const new_bounds = Bounds.init(0, 0, size.width, size.height);
                self.layout.calculateLayout(new_bounds);
            },
            else => {},
        }

        // Forward input to appropriate widgets
        for (self.widgets.widgets.items) |widget| {
            // Check if input is within widget bounds for mouse events
            switch (event) {
                .mouse => |mouse| {
                    if (widget.bounds.contains(Point.init(mouse.x, mouse.y))) {
                        try widget.handleInput(event);
                    }
                },
                else => {
                    try widget.handleInput(event);
                },
            }
        }
    }

    pub fn runInteractive(self: *Self, renderer: *Renderer) !void {
        // Try to detect terminal capabilities
        try self.detectCapabilities(renderer);

        // Main render loop
        var update_timer: i64 = 0;
        const update_interval = @as(i64, @intCast(self.update_interval_ms));

        while (true) {
            const now = std.time.timestamp() * 1000; // Convert to milliseconds

            // Update data sources if interval has passed
            if (now - update_timer >= update_interval) {
                try self.updateData();
                update_timer = now;
            }

            // Get terminal size
            const terminal_size = bounds_mod.getTerminalSize() catch |err| switch (err) {
                error.NotATTY => bounds_mod.TerminalSize{ .width = 80, .height = 24 },
                else => return err,
            };

            // Check minimum size requirements
            if (self.responsive and
                (terminal_size.width < self.min_terminal_size.width or
                    terminal_size.height < self.min_terminal_size.height))
            {
                // Display size warning
                try renderer.setForeground(.red);
                try renderer.writeText("Terminal too small. Minimum size: {}x{}", .{ self.min_terminal_size.width, self.min_terminal_size.height });
                try renderer.resetStyle();
                std.time.sleep(100 * std.time.ns_per_ms);
                continue;
            }

            // Render dashboard
            const ctx = RenderContext{
                .bounds = Bounds.init(0, 0, terminal_size.width, terminal_size.height),
            };
            try self.render(renderer, ctx);

            // Handle input (non-blocking)
            // This would need to be implemented based on the input system
            // For now, we'll add a small delay to prevent tight loop
            std.time.sleep(16 * std.time.ns_per_ms); // ~60 FPS
        }
    }
};
