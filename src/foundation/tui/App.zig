//! TUI application framework with double buffering support.
//!
//! Provides the main application loop, event handling, and frame management
//! for terminal UI applications.

const std = @import("std");
const ui = @import("../ui.zig");
const render_mod = @import("../render.zig");
const term = @import("../term.zig");

/// Application configuration
pub const Config = struct {
    /// Target frames per second
    fps: u32 = 60,
    /// Enable vsync-like behavior
    vsync: bool = true,
    /// Enable mouse support
    mouse: bool = true,
    /// Enable paste support
    paste: bool = true,
};

/// Application error set
pub const Error = error{
    InitFailed,
    RenderFailed,
    EventQueueFull,
    TerminalError,
    OutOfMemory,
};

/// Double-buffered terminal application
const Self = @This();

allocator: std.mem.Allocator,
front_buffer: *Surface,
back_buffer: *Surface,
frame_budget_ns: u64,
config: Config,
running: bool,
terminal: *term.Terminal,
event_queue: std.ArrayList(ui.Event),
components: std.ArrayList(*ui.Component),
focused_component: ?usize,
frame_scheduler: FrameScheduler,

/// Frame scheduler for managing render timing and performance
pub const FrameScheduler = struct {
    const FSelf = @This();

    /// Performance metrics
    pub const Metrics = struct {
        frame_count: u64,
        dropped_frames: u64,
        average_frame_time_ns: u64,
        peak_frame_time_ns: u64,
        last_frame_time_ns: u64,
    };

    target_fps: u32,
    frame_budget_ns: u64,
    vsync: bool,
    metrics: Metrics,
    timer: std.time.Timer,
    last_frame_ns: u64,
    frame_times: [60]u64, // Rolling buffer for frame times
    frame_time_index: usize,
    adaptive_quality: bool,
    quality_level: u8, // 0-100

    pub fn init(fps: u32, vsync: bool, adaptive: bool) !FSelf {
        const timer = try std.time.Timer.start();
        const frame_budget = if (fps > 0)
            @divFloor(1_000_000_000, fps)
        else
            16_666_667; // Default to 60 FPS

        return .{
            .target_fps = fps,
            .frame_budget_ns = frame_budget,
            .vsync = vsync,
            .metrics = std.mem.zeroes(Metrics),
            .timer = timer,
            .last_frame_ns = timer.read(),
            .frame_times = [_]u64{0} ** 60,
            .frame_time_index = 0,
            .adaptive_quality = adaptive,
            .quality_level = 100,
        };
    }

    /// Check if we should render a new frame
    pub fn shouldRender(self: *FSelf) bool {
        const now = self.timer.read();
        const delta = now - self.last_frame_ns;
        return delta >= self.frame_budget_ns;
    }

    /// Begin a new frame
    pub fn beginFrame(self: *FSelf) void {
        self.last_frame_ns = self.timer.read();
    }

    /// End the current frame and update metrics
    pub fn endFrame(self: *FSelf) void {
        const frame_time = self.timer.read() - self.last_frame_ns;

        // Update metrics
        self.metrics.frame_count += 1;
        self.metrics.last_frame_time_ns = frame_time;
        if (frame_time > self.metrics.peak_frame_time_ns) {
            self.metrics.peak_frame_time_ns = frame_time;
        }

        // Track frame times for average calculation
        self.frame_times[self.frame_time_index] = frame_time;
        self.frame_time_index = (self.frame_time_index + 1) % self.frame_times.len;

        // Calculate average
        var sum: u64 = 0;
        for (self.frame_times) |t| sum += t;
        self.metrics.average_frame_time_ns = sum / self.frame_times.len;

        // Check for dropped frames
        if (frame_time > self.frame_budget_ns * 2) {
            self.metrics.dropped_frames += 1;

            // Adjust quality if adaptive
            if (self.adaptive_quality and self.quality_level > 10) {
                self.quality_level -= 10;
            }
        } else if (self.adaptive_quality and frame_time < self.frame_budget_ns / 2) {
            // Increase quality if we have headroom
            if (self.quality_level < 100) {
                self.quality_level += 1;
            }
        }
    }

    /// Sleep to maintain frame rate
    pub fn sleep(self: *Self) void {
        if (!self.vsync) return;

        const now = self.timer.read();
        const elapsed = now - self.last_frame_ns;
        if (elapsed < self.frame_budget_ns) {
            std.time.sleep(self.frame_budget_ns - elapsed);
        }
    }

    /// Get current quality level for adaptive rendering
    pub fn getQualityLevel(self: *const Self) u8 {
        return self.quality_level;
    }

    /// Get current metrics
    pub fn getMetrics(self: *const Self) Metrics {
        return self.metrics;
    }
};

/// Surface abstraction for double buffering
pub const Surface = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    cells: []Cell,

    pub const Cell = struct {
        char: u21,
        style: render_mod.Style,
    };

    pub fn init(allocator: std.mem.Allocator) !*Surface {
        const self = try allocator.create(Surface);
        self.* = .{
            .allocator = allocator,
            .width = 80,
            .height = 24,
            .cells = try allocator.alloc(Cell, 80 * 24),
        };
        return self;
    }

    pub fn deinit(self: *Surface) void {
        self.allocator.free(self.cells);
        self.allocator.destroy(self);
    }

    pub fn resize(self: *Surface, width: u32, height: u32) !void {
        const new_size = width * height;
        if (new_size != self.cells.len) {
            self.cells = try self.allocator.realloc(self.cells, new_size);
        }
        self.width = width;
        self.height = height;
    }

    pub fn clear(self: *Surface) void {
        for (self.cells) |*cell| {
            cell.* = .{
                .char = ' ',
                .style = .{},
            };
        }
    }
};

/// Initialize a new TUI application
pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
    const front = try Surface.init(allocator);
    errdefer front.deinit();

    const back = try Surface.init(allocator);
    errdefer back.deinit();

    const terminal = try allocator.create(term.Terminal);
    errdefer allocator.destroy(terminal);

    // Calculate frame budget from FPS
    const frame_budget_ns = if (config.fps > 0)
        @divFloor(1_000_000_000, config.fps)
    else
        16_666_667; // Default to 60 FPS

    const frame_scheduler = try FrameScheduler.init(config.fps, config.vsync, true);

    return .{
        .allocator = allocator,
        .front_buffer = front,
        .back_buffer = back,
        .frame_budget_ns = frame_budget_ns,
        .config = config,
        .running = false,
        .terminal = terminal,
        .event_queue = std.ArrayList(ui.Event).init(allocator),
        .components = std.ArrayList(*ui.Component).init(allocator),
        .focused_component = null,
        .frame_scheduler = frame_scheduler,
    };
}

/// Deinitialize the application
pub fn deinit(self: *Self) void {
    self.front_buffer.deinit();
    self.back_buffer.deinit();
    self.event_queue.deinit();
    self.components.deinit();
    self.allocator.destroy(self.terminal);
}

/// Add a component to the application
pub fn addComponent(self: *Self, component: *ui.Component) !void {
    try self.components.append(component);
    if (self.focused_component == null) {
        self.focused_component = 0;
    }
}

/// Main application run loop
pub fn run(self: *Self) Error!void {
    self.running = true;

    // Setup terminal
    try self.terminal.enterRawMode();
    defer self.terminal.exitRawMode() catch {};

    if (self.config.mouse) {
        try self.terminal.enableMouse();
        defer self.terminal.disableMouse() catch {};
    }

    // Get initial terminal size
    const size = try self.terminal.getSize();
    try self.front_buffer.resize(size.width, size.height);
    try self.back_buffer.resize(size.width, size.height);

    while (self.running) {
        // Process events
        try self.processEvents();

        // Check if we should render
        if (self.frame_scheduler.shouldRender()) {
            self.frame_scheduler.beginFrame();

            // Update components with frame time
            const delta_ns = self.frame_scheduler.metrics.last_frame_time_ns;
            try self.update(delta_ns);

            // Render with adaptive quality
            try self.render();
            try self.present();

            self.frame_scheduler.endFrame();
        }

        // Sleep to maintain frame rate
        self.frame_scheduler.sleep();
    }
}

/// Process input events
fn processEvents(self: *Self) Error!void {
    // Poll for terminal events (non-blocking)
    while (self.terminal.pollEvent()) |event| {
        try self.event_queue.append(event);

        // Dispatch to focused component
        if (self.focused_component) |idx| {
            if (idx < self.components.items.len) {
                const component = self.components.items[idx];
                try component.event(event);
            }
        }

        // Handle global events
        switch (event) {
            .key => |key| {
                if (key.ctrl and key.code == 'c') {
                    self.running = false;
                }
            },
            .resize => |size| {
                try self.front_buffer.resize(size.width, size.height);
                try self.back_buffer.resize(size.width, size.height);
            },
            else => {},
        }
    }
}

/// Update application state
fn update(self: *Self, delta_ns: u64) Error!void {
    _ = delta_ns;

    // Update component layouts
    const bounds = ui.Rect{
        .x = 0,
        .y = 0,
        .width = self.back_buffer.width,
        .height = self.back_buffer.height,
    };

    for (self.components.items) |component| {
        _ = try component.layout(bounds, self.allocator);
    }
}

/// Render to back buffer
fn render(self: *Self) Error!void {
    // Clear back buffer
    self.back_buffer.clear();

    // Create render context with adaptive quality
    const quality = if (self.frame_scheduler.adaptive_quality)
        switch (self.frame_scheduler.quality_level) {
            0...33 => render_mod.quality_tiers.QualityTier.minimal,
            34...66 => render_mod.quality_tiers.QualityTier.standard,
            67...90 => render_mod.quality_tiers.QualityTier.rich,
            else => render_mod.quality_tiers.QualityTier.rich,
        }
    else
        render_mod.quality_tiers.QualityTier.rich;

    var ctx = render_mod.RenderContext{
        .surface = self.back_buffer,
        .theme = undefined, // Would be initialized with actual theme
        .caps = .{
            .colors = .truecolor,
            .unicode = true,
            .graphics = .none,
        },
        .quality = quality,
        .frame_budget_ns = self.frame_budget_ns,
        .allocator = self.allocator,
    };

    // Render all components
    for (self.components.items) |component| {
        try component.draw(&ctx);
    }
}

/// Present back buffer to screen (swap and diff)
pub fn present(self: *Self) Error!void {
    try self.diffAndWrite();
    self.swapBuffers();
}

/// Diff buffers and write changes to terminal
fn diffAndWrite(self: *Self) Error!void {
    const front = self.front_buffer;
    const back = self.back_buffer;

    if (front.width != back.width or front.height != back.height) {
        // Full redraw on resize
        try self.terminal.clear();
        for (0..back.height) |y| {
            for (0..back.width) |x| {
                const idx = y * back.width + x;
                const cell = back.cells[idx];
                try self.terminal.writeCell(@intCast(x), @intCast(y), cell.char, cell.style);
            }
        }
    } else {
        // Diff and update only changed cells
        for (0..back.height) |y| {
            for (0..back.width) |x| {
                const idx = y * back.width + x;
                const old = front.cells[idx];
                const new = back.cells[idx];

                if (old.char != new.char or !std.meta.eql(old.style, new.style)) {
                    try self.terminal.writeCell(@intCast(x), @intCast(y), new.char, new.style);
                }
            }
        }
    }

    try self.terminal.flush();
}

/// Swap front and back buffers
fn swapBuffers(self: *Self) void {
    const temp = self.front_buffer;
    self.front_buffer = self.back_buffer;
    self.back_buffer = temp;
}

/// Stop the application
pub fn stop(self: *Self) void {
    self.running = false;
}
