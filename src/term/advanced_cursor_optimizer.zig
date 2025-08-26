/// Advanced cursor movement optimizer inspired by charmbracelet/x cellbuf
/// Implements sophisticated cursor movement algorithms to minimize terminal escape sequences
/// Compatible with Zig 0.15.1 and follows proper error handling patterns

const std = @import("std");
const ansi = @import("ansi/mod.zig");

/// Tab stop manager for optimizing horizontal cursor movement
pub const TabStops = struct {
    stops: []bool,
    width: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize with default tab stops every 8 columns
    pub fn init(allocator: std.mem.Allocator, width: usize) !Self {
        const stops = try allocator.alloc(bool, width);
        // Standard tab stops every 8 columns
        for (stops, 0..) |*stop, i| {
            stop.* = (i % 8) == 0;
        }
        
        return Self{
            .stops = stops,
            .width = width,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.stops);
    }

    /// Resize tab stops array
    pub fn resize(self: *Self, new_width: usize) !void {
        const new_stops = try self.allocator.alloc(bool, new_width);
        const copy_width = @min(self.width, new_width);
        
        // Copy existing stops
        @memcpy(new_stops[0..copy_width], self.stops[0..copy_width]);
        
        // Initialize new stops with standard 8-column pattern
        for (copy_width..new_width) |i| {
            new_stops[i] = (i % 8) == 0;
        }
        
        self.allocator.free(self.stops);
        self.stops = new_stops;
        self.width = new_width;
    }

    /// Find next tab stop at or after the given column
    pub fn next(self: Self, col: usize) usize {
        for (col..self.width) |i| {
            if (self.stops[i]) return i;
        }
        return self.width - 1;
    }

    /// Find previous tab stop at or before the given column
    pub fn prev(self: Self, col: usize) usize {
        var i = @min(col, self.width - 1);
        while (true) {
            if (self.stops[i]) return i;
            if (i == 0) break;
            i -= 1;
        }
        return 0;
    }

    /// Set tab stop at column
    pub fn set(self: *Self, col: usize) void {
        if (col < self.width) {
            self.stops[col] = true;
        }
    }

    /// Clear tab stop at column
    pub fn clear(self: *Self, col: usize) void {
        if (col < self.width) {
            self.stops[col] = false;
        }
    }

    /// Clear all tab stops
    pub fn clearAll(self: *Self) void {
        @memset(self.stops, false);
    }
};

/// Terminal capabilities for optimization decisions
pub const Capabilities = struct {
    /// Vertical Position Absolute (VPA)
    vpa: bool = true,
    /// Horizontal Position Absolute (HPA) 
    hpa: bool = true,
    /// Cursor Horizontal Tab (CHT)
    cht: bool = true,
    /// Cursor Backward Tab (CBT)
    cbt: bool = true,
    /// Repeat Previous Character (REP)
    rep: bool = true,
    /// Erase Character (ECH)
    ech: bool = true,
    /// Insert Character (ICH)
    ich: bool = true,
    /// Scroll Down (SD)
    sd: bool = true,
    /// Scroll Up (SU)
    su: bool = true,

    /// Initialize capabilities for known terminal types
    pub fn forTerminal(term_type: []const u8) Capabilities {
        // Extract base terminal name
        const term_base = blk: {
            if (std.mem.indexOf(u8, term_type, "-")) |dash_pos| {
                break :blk term_type[0..dash_pos];
            }
            break :blk term_type;
        };

        return switch (std.hash_map.hashString(term_base)) {
            std.hash_map.hashString("xterm"),
            std.hash_map.hashString("tmux"),
            std.hash_map.hashString("foot"),
            std.hash_map.hashString("kitty"),
            std.hash_map.hashString("wezterm"),
            std.hash_map.hashString("contour"),
            std.hash_map.hashString("ghostty"),
            std.hash_map.hashString("rio"),
            std.hash_map.hashString("st") => Capabilities{}, // All supported
            
            std.hash_map.hashString("alacritty") => Capabilities{
                // Alacritty doesn't support CHT reliably in older versions
                .cht = false,
            },
            
            std.hash_map.hashString("screen") => Capabilities{
                // Screen doesn't support REP
                .rep = false,
            },
            
            std.hash_map.hashString("linux") => Capabilities{
                // Linux console has limited support
                .cht = false,
                .cbt = false,
                .rep = false,
                .sd = false,
                .su = false,
            },
            
            else => Capabilities{
                // Conservative defaults for unknown terminals
                .cht = false,
                .cbt = false,
                .rep = false,
            },
        };
    }
};

/// Cursor movement optimizer options
pub const OptimizerOptions = struct {
    /// Use relative cursor movements when possible
    relative_cursor: bool = true,
    /// Use hard tabs for optimization
    hard_tabs: bool = true,
    /// Use backspace characters for movement
    backspace: bool = true,
    /// Map newlines to CR+LF (ONLCR mode)
    map_nl: bool = false,
    /// Use alternate screen buffer
    alt_screen: bool = false,
};

/// Advanced cursor movement optimizer
pub const CursorOptimizer = struct {
    capabilities: Capabilities,
    tab_stops: TabStops,
    options: OptimizerOptions,
    screen_width: usize,
    screen_height: usize,
    
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, term_type: []const u8, width: usize, height: usize, options: OptimizerOptions) !Self {
        return Self{
            .capabilities = Capabilities.forTerminal(term_type),
            .tab_stops = try TabStops.init(allocator, width),
            .options = options,
            .screen_width = width,
            .screen_height = height,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tab_stops.deinit();
    }

    pub fn resize(self: *Self, width: usize, height: usize) !void {
        try self.tab_stops.resize(width);
        self.screen_width = width;
        self.screen_height = height;
    }

    /// Check if movement is considered "local" (worth optimizing)
    fn isLocal(self: Self, from_x: usize, from_y: usize, to_x: usize, to_y: usize) bool {
        const long_dist = 8; // Threshold for "long distance" movement
        
        return !(to_x > long_dist and 
                to_x < self.screen_width - 1 - long_dist and
                (absDiff(to_y, from_y) + absDiff(to_x, from_x)) > long_dist);
    }

    /// Generate relative cursor movement sequence
    fn relativeMove(self: Self, allocator: std.mem.Allocator, from_x: usize, from_y: usize, to_x: usize, to_y: usize, use_tabs: bool, use_backspace: bool) ![]u8 {
        var seq = std.ArrayList(u8).init(allocator);
        errdefer seq.deinit();

        // Vertical movement
        if (to_y != from_y) {
            var y_seq: []const u8 = "";
            
            if (self.capabilities.vpa and !self.options.relative_cursor) {
                y_seq = try std.fmt.allocPrint(allocator, "\x1b[{d}d", .{to_y + 1});
            } else if (to_y > from_y) {
                const down_count = to_y - from_y;
                if (down_count == 1) {
                    y_seq = "\n";
                } else {
                    y_seq = try std.fmt.allocPrint(allocator, "\x1b[{d}B", .{down_count});
                }
            } else if (to_y < from_y) {
                const up_count = from_y - to_y;
                if (up_count == 1) {
                    y_seq = "\x1b[A";
                } else {
                    y_seq = try std.fmt.allocPrint(allocator, "\x1b[{d}A", .{up_count});
                }
            }
            
            try seq.appendSlice(y_seq);
        }

        // Horizontal movement  
        if (to_x != from_x) {
            var x_seq: []const u8 = "";
            
            if (self.capabilities.hpa and !self.options.relative_cursor) {
                x_seq = try std.fmt.allocPrint(allocator, "\x1b[{d}G", .{to_x + 1});
            } else if (to_x > from_x) {
                var distance = to_x - from_x;
                var current_x = from_x;
                
                // Try using tabs if enabled
                if (use_tabs) {
                    var tab_count: usize = 0;
                    while (self.tab_stops.next(current_x) <= to_x and current_x < self.screen_width - 1) {
                        const next_tab = self.tab_stops.next(current_x);
                        if (next_tab == current_x) break; // No progress
                        current_x = next_tab;
                        tab_count += 1;
                    }
                    
                    if (tab_count > 0) {
                        const tab_seq = try std.fmt.allocPrint(allocator, "{s}", .{"\t" ** @min(tab_count, 10)});
                        try seq.appendSlice(tab_seq);
                        distance = to_x - current_x;
                    }
                }
                
                if (distance > 0) {
                    if (distance == 1) {
                        x_seq = "\x1b[C";
                    } else {
                        x_seq = try std.fmt.allocPrint(allocator, "\x1b[{d}C", .{distance});
                    }
                }
            } else if (to_x < from_x) {
                var distance = from_x - to_x;
                var current_x = from_x;
                
                // Try backward tabs if supported
                if (use_tabs and self.capabilities.cbt) {
                    var tab_count: usize = 0;
                    while (self.tab_stops.prev(current_x) >= to_x and current_x > 0) {
                        const prev_tab = self.tab_stops.prev(current_x);
                        if (prev_tab == current_x) break; // No progress
                        current_x = prev_tab;
                        tab_count += 1;
                    }
                    
                    if (tab_count > 0) {
                        const cbt_seq = try std.fmt.allocPrint(allocator, "\x1b[{d}Z", .{tab_count});
                        try seq.appendSlice(cbt_seq);
                        distance = current_x - to_x;
                    }
                }
                
                if (distance > 0) {
                    if (use_backspace and distance <= 4) {
                        // Use backspace for short distances
                        const bs_seq = try std.fmt.allocPrint(allocator, "{s}", .{"\x08" ** distance});
                        x_seq = bs_seq;
                    } else if (distance == 1) {
                        x_seq = "\x1b[D";
                    } else {
                        x_seq = try std.fmt.allocPrint(allocator, "\x1b[{d}D", .{distance});
                    }
                }
            }
            
            try seq.appendSlice(x_seq);
        }

        return seq.toOwnedSlice();
    }

    /// Generate optimized cursor movement sequence
    pub fn moveCursor(self: Self, allocator: std.mem.Allocator, from_x: usize, from_y: usize, to_x: usize, to_y: usize) ![]u8 {
        // Clamp coordinates to screen bounds
        const safe_from_x = @min(from_x, self.screen_width - 1);
        const safe_from_y = @min(from_y, self.screen_height - 1);
        const safe_to_x = @min(to_x, self.screen_width - 1);
        const safe_to_y = @min(to_y, self.screen_height - 1);
        
        // No movement needed
        if (safe_from_x == safe_to_x and safe_from_y == safe_to_y) {
            return try allocator.dupe(u8, "");
        }

        // Try direct positioning first for long distances
        if (!self.options.relative_cursor or !self.isLocal(safe_from_x, safe_from_y, safe_to_x, safe_to_y)) {
            return try std.fmt.allocPrint(allocator, "\x1b[{d};{d}H", .{safe_to_y + 1, safe_to_x + 1});
        }

        // Try different optimization combinations
        var best_seq: []u8 = try std.fmt.allocPrint(allocator, "\x1b[{d};{d}H", .{safe_to_y + 1, safe_to_x + 1});
        
        // Method 1: Pure relative movement
        const rel_seq = self.relativeMove(allocator, safe_from_x, safe_from_y, safe_to_x, safe_to_y, false, false) catch best_seq;
        if (rel_seq.len < best_seq.len) {
            allocator.free(best_seq);
            best_seq = rel_seq;
        }
        
        // Method 2: Relative with tabs
        if (self.options.hard_tabs) {
            const tab_seq = self.relativeMove(allocator, safe_from_x, safe_from_y, safe_to_x, safe_to_y, true, false) catch best_seq;
            if (tab_seq.len < best_seq.len) {
                if (tab_seq.ptr != best_seq.ptr) allocator.free(best_seq);
                best_seq = tab_seq;
            }
        }
        
        // Method 3: Relative with backspace
        if (self.options.backspace) {
            const bs_seq = self.relativeMove(allocator, safe_from_x, safe_from_y, safe_to_x, safe_to_y, false, true) catch best_seq;
            if (bs_seq.len < best_seq.len) {
                if (bs_seq.ptr != best_seq.ptr) allocator.free(best_seq);
                best_seq = bs_seq;
            }
        }
        
        // Method 4: Carriage return + relative movement  
        const cr_seq = blk: {
            var cr_buf = std.ArrayList(u8).init(allocator);
            try cr_buf.append('\r');
            const rel_part = self.relativeMove(allocator, 0, safe_from_y, safe_to_x, safe_to_y, self.options.hard_tabs, self.options.backspace) catch break :blk best_seq;
            defer if (rel_part.ptr != best_seq.ptr) allocator.free(rel_part);
            try cr_buf.appendSlice(rel_part);
            break :blk try cr_buf.toOwnedSlice();
        };
        
        if (cr_seq.len < best_seq.len) {
            if (cr_seq.ptr != best_seq.ptr) allocator.free(best_seq);
            best_seq = cr_seq;
        }
        
        return best_seq;
    }
    
    /// Generate sequence to move to home position (0, 0)
    pub fn moveToHome(_: Self, allocator: std.mem.Allocator) ![]u8 {
        return try allocator.dupe(u8, "\x1b[H");
    }
    
    /// Generate sequence to save cursor position  
    pub fn saveCursor(_: Self, allocator: std.mem.Allocator) ![]u8 {
        return try allocator.dupe(u8, "\x1b[s");
    }
    
    /// Generate sequence to restore cursor position
    pub fn restoreCursor(_: Self, allocator: std.mem.Allocator) ![]u8 {
        return try allocator.dupe(u8, "\x1b[u");
    }
};

/// Helper function to compute absolute difference between two usize values
fn absDiff(a: usize, b: usize) usize {
    return if (a >= b) a - b else b - a;
}

// Tests
test "tab stops basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var tabs = try TabStops.init(allocator, 40);
    defer tabs.deinit();
    
    try testing.expect(tabs.next(0) == 0);
    try testing.expect(tabs.next(1) == 8);
    try testing.expect(tabs.next(8) == 8);
    try testing.expect(tabs.next(9) == 16);
    
    try testing.expect(tabs.prev(16) == 16);
    try testing.expect(tabs.prev(15) == 8);
    try testing.expect(tabs.prev(7) == 0);
}

test "capabilities for different terminals" {
    const testing = std.testing;
    
    const xterm_caps = Capabilities.forTerminal("xterm-256color");
    try testing.expect(xterm_caps.vpa);
    try testing.expect(xterm_caps.hpa);
    
    const linux_caps = Capabilities.forTerminal("linux");
    try testing.expect(!linux_caps.cht);
    try testing.expect(!linux_caps.cbt);
    
    const alacritty_caps = Capabilities.forTerminal("alacritty");
    try testing.expect(!alacritty_caps.cht);
}

test "cursor movement optimization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var optimizer = try CursorOptimizer.init(allocator, "xterm", 80, 24, .{});
    defer optimizer.deinit();
    
    // Test simple movement
    const seq = try optimizer.moveCursor(allocator, 0, 0, 5, 0);
    defer allocator.free(seq);
    
    try testing.expect(seq.len > 0);
}

test "local vs long distance detection" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var optimizer = try CursorOptimizer.init(allocator, "xterm", 80, 24, .{});
    defer optimizer.deinit();
    
    // Short distance should be local
    try testing.expect(optimizer.isLocal(0, 0, 5, 0));
    
    // Long distance should not be local
    try testing.expect(!optimizer.isLocal(0, 0, 40, 10));
}

test "tab optimization" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var optimizer = try CursorOptimizer.init(allocator, "xterm", 80, 24, .{ .hard_tabs = true });
    defer optimizer.deinit();
    
    // Moving to a tab stop should be shorter than individual moves
    const seq = try optimizer.moveCursor(allocator, 0, 0, 16, 0);
    defer allocator.free(seq);
    
    try testing.expect(seq.len > 0);
    try testing.expect(seq.len <= 3); // Should be very short with tabs
}