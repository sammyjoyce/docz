const std = @import("std");
const builtin = @import("builtin");

/// Terminfo database integration for terminal capability detection
/// Provides access to terminal-specific key sequences and capabilities
pub const Database = struct {
    allocator: std.mem.Allocator,
    term_name: []const u8,
    capabilities: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, term_name: ?[]const u8) !Database {
        var db = Database{
            .allocator = allocator,
            .term_name = term_name orelse std.process.getEnvVarOwned(allocator, "TERM") catch "xterm",
            .capabilities = std.StringHashMap([]const u8).init(allocator),
        };

        // Try to load terminfo database
        try db.loadCapabilities();

        return db;
    }

    pub fn deinit(self: *Database) void {
        self.allocator.free(self.term_name);
        var it = self.capabilities.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.capabilities.deinit();
    }

    /// Get a capability value by name
    pub fn getCapability(self: *const Database, name: []const u8) ?[]const u8 {
        return self.capabilities.get(name);
    }

    /// Check if a capability exists
    pub fn hasCapability(self: *const Database, name: []const u8) bool {
        return self.capabilities.contains(name);
    }

    /// Load capabilities from terminfo database or use fallbacks
    fn loadCapabilities(self: *Database) !void {
        // Try system terminfo first
        if (try self.loadFromSystemTerminfo()) {
            return;
        }

        // Fallback to hardcoded capabilities for common terminals
        try self.loadFallbackCapabilities();
    }

    /// Load capabilities from system terminfo database
    fn loadFromSystemTerminfo(self: *Database) !bool {
        // This is a simplified implementation
        // In a real implementation, you would parse the actual terminfo database
        // For now, we'll return false to use fallbacks
        _ = self;
        return false;
    }

    /// Load fallback capabilities for common terminals
    fn loadFallbackCapabilities(self: *Database) !void {
        const term = self.term_name;

        // Common key sequences for xterm and compatible terminals
        const common_keys = std.ComptimeStringMap([]const u8, .{
            // Arrow keys
            .{ "kcuu1", "\x1b[A" }, // Up arrow
            .{ "kcud1", "\x1b[B" }, // Down arrow
            .{ "kcuf1", "\x1b[C" }, // Right arrow
            .{ "kcub1", "\x1b[D" }, // Left arrow

            // Function keys
            .{ "kf1", "\x1bOP" },
            .{ "kf2", "\x1bOQ" },
            .{ "kf3", "\x1bOR" },
            .{ "kf4", "\x1bOS" },
            .{ "kf5", "\x1b[15~" },
            .{ "kf6", "\x1b[17~" },
            .{ "kf7", "\x1b[18~" },
            .{ "kf8", "\x1b[19~" },
            .{ "kf9", "\x1b[20~" },
            .{ "kf10", "\x1b[21~" },
            .{ "kf11", "\x1b[22~" },
            .{ "kf12", "\x1b[23~" },

            // Navigation keys
            .{ "khome", "\x1b[H" },
            .{ "kend", "\x1b[F" },
            .{ "kpp", "\x1b[5~" }, // Page up
            .{ "knp", "\x1b[6~" }, // Page down
            .{ "kich1", "\x1b[2~" }, // Insert
            .{ "kdch1", "\x1b[3~" }, // Delete

            // Keypad keys
            .{ "ka1", "\x1b[H" }, // Keypad home (same as home)
            .{ "ka3", "\x1b[5~" }, // Keypad page up
            .{ "kb2", "\x1b[2~" }, // Keypad center (insert)
            .{ "kbeg", "\x1b[H" }, // Keypad begin (home)
            .{ "kc1", "\x1b[F" }, // Keypad end
            .{ "kc3", "\x1b[6~" }, // Keypad page down
        });

        // Terminal-specific overrides
        if (std.mem.eql(u8, term, "linux")) {
            // Linux console specific keys
            try self.addCapability("kcuu1", "\x1b[A");
            try self.addCapability("kcud1", "\x1b[B");
            try self.addCapability("kcuf1", "\x1b[C");
            try self.addCapability("kcub1", "\x1b[D");
            try self.addCapability("khome", "\x1b[1~");
            try self.addCapability("kend", "\x1b[4~");
        } else if (std.mem.eql(u8, term, "screen") or std.mem.startsWith(u8, term, "screen")) {
            // GNU screen specific keys
            try self.addCapability("kcuu1", "\x1bOA");
            try self.addCapability("kcud1", "\x1bOB");
            try self.addCapability("kcuf1", "\x1bOC");
            try self.addCapability("kcub1", "\x1bOD");
        } else if (std.mem.eql(u8, term, "tmux") or std.mem.startsWith(u8, term, "tmux")) {
            // tmux specific keys (may be overridden by underlying terminal)
            try self.addCapability("kcuu1", "\x1bOA");
            try self.addCapability("kcud1", "\x1bOB");
            try self.addCapability("kcuf1", "\x1bOC");
            try self.addCapability("kcub1", "\x1bOD");
        } else {
            // Default to xterm-compatible
            var it = common_keys.iterator();
            while (it.next()) |entry| {
                try self.addCapability(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }

    fn addCapability(self: *Database, name: []const u8, value: []const u8) !void {
        const name_dup = try self.allocator.dupe(u8, name);
        const value_dup = try self.allocator.dupe(u8, value);
        try self.capabilities.put(name_dup, value_dup);
    }
};

/// Terminfo capability names for key sequences
pub const KeyCapability = enum {
    // Arrow keys
    up,
    down,
    left,
    right,

    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,

    // Navigation keys
    home,
    end,
    page_up,
    page_down,
    insert,
    delete,

    // Keypad keys
    kp_home,
    kp_up,
    kp_page_up,
    kp_left,
    kp_center,
    kp_right,
    kp_end,
    kp_down,
    kp_page_down,
    kp_insert,
    kp_delete,

    pub fn terminfoName(self: KeyCapability) []const u8 {
        return switch (self) {
            .up => "kcuu1",
            .down => "kcud1",
            .left => "kcub1",
            .right => "kcuf1",
            .f1 => "kf1",
            .f2 => "kf2",
            .f3 => "kf3",
            .f4 => "kf4",
            .f5 => "kf5",
            .f6 => "kf6",
            .f7 => "kf7",
            .f8 => "kf8",
            .f9 => "kf9",
            .f10 => "kf10",
            .f11 => "kf11",
            .f12 => "kf12",
            .home => "khome",
            .end => "kend",
            .page_up => "kpp",
            .page_down => "knp",
            .insert => "kich1",
            .delete => "kdch1",
            .kp_home => "ka1",
            .kp_up => "ka2",
            .kp_page_up => "ka3",
            .kp_left => "kb1",
            .kp_center => "kb2",
            .kp_right => "kb3",
            .kp_end => "kc1",
            .kp_down => "kc2",
            .kp_page_down => "kc3",
            .kp_insert => "kp0",
            .kp_delete => "kp1",
        };
    }
};

test "terminfo database initialization" {
    const allocator = std.testing.allocator;
    var db = try Database.init(allocator, "xterm");
    defer db.deinit();

    try std.testing.expect(db.term_name.len > 0);
    try std.testing.expect(db.capabilities.count() > 0);
}

test "capability lookup" {
    const allocator = std.testing.allocator;
    var db = try Database.init(allocator, "xterm");
    defer db.deinit();

    // Should have up arrow capability
    const up_seq = db.getCapability("kcuu1");
    try std.testing.expect(up_seq != null);
    try std.testing.expectEqualStrings("\x1b[A", up_seq.?);
}
