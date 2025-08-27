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
        // Search for terminfo file in standard locations
        const term = self.term_name;
        const term_first_char = if (term.len > 0) term[0] else return false;

        // Standard terminfo search paths
        const search_paths = [_][]const u8{
            "/usr/share/terminfo",
            "/etc/terminfo",
            "/usr/local/share/terminfo",
            "/lib/terminfo",
            "/usr/lib/terminfo",
        };

        // Also check user's home directory
        var home_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        var home_terminfo_path: ?[]const u8 = null;
        if (std.process.getEnvVarOwned(self.allocator, "HOME")) |home| {
            defer self.allocator.free(home);
            home_terminfo_path = std.fmt.bufPrint(&home_path_buf, "{s}/.terminfo", .{home}) catch null;
        } else |_| {}

        // Try each search path
        for (search_paths) |base_path| {
            if (self.tryLoadTerminfoFile(base_path, term_first_char, term)) |_| {
                return true;
            } else |_| {}
        }

        // Try home directory if available
        if (home_terminfo_path) |path| {
            if (self.tryLoadTerminfoFile(path, term_first_char, term)) |_| {
                return true;
            } else |_| {}
        }

        // Try $TERMINFO environment variable
        if (std.process.getEnvVarOwned(self.allocator, "TERMINFO")) |terminfo_path| {
            defer self.allocator.free(terminfo_path);
            if (self.tryLoadTerminfoFile(terminfo_path, term_first_char, term)) |_| {
                return true;
            } else |_| {}
        } else |_| {}

        return false;
    }

    /// Try to load a terminfo file from a specific path
    fn tryLoadTerminfoFile(self: *Database, base_path: []const u8, first_char: u8, term_name: []const u8) !void {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        // Try both single-char and hex directory structures
        const paths_to_try = [_][]const u8{
            try std.fmt.bufPrint(&path_buf, "{s}/{c}/{s}", .{ base_path, first_char, term_name }),
            try std.fmt.bufPrint(&path_buf, "{s}/{x:0>2}/{s}", .{ base_path, first_char, term_name }),
        };

        for (paths_to_try) |path| {
            const file = std.fs.openFileAbsolute(path, .{}) catch continue;
            defer file.close();

            // Parse the terminfo file
            try self.parseTerminfoFile(file);
            return;
        }

        return error.FileNotFound;
    }

    /// Parse a binary terminfo file
    fn parseTerminfoFile(self: *Database, file: std.fs.File) !void {
        const allocator = self.allocator;

        // Read the entire file into memory
        const file_size = try file.getEndPos();
        if (file_size > 32768) { // Sanity check - terminfo files should be small
            return error.FileTooLarge;
        }

        const data = try allocator.alloc(u8, file_size);
        defer allocator.free(data);

        _ = try file.read(data);

        // Parse the terminfo binary format
        var parser = TerminfoParser{
            .data = data,
            .pos = 0,
            .allocator = allocator,
        };

        try parser.parse(self);
    }

    /// Load fallback capabilities for common terminals
    fn loadFallbackCapabilities(self: *Database) !void {
        const term = self.term_name;

        // Common key sequences for xterm and compatible terminals
        const common_keys = [_]struct { name: []const u8, value: []const u8 }{
            // Arrow keys
            .{ .name = "kcuu1", .value = "\x1b[A" }, // Up arrow
            .{ .name = "kcud1", .value = "\x1b[B" }, // Down arrow
            .{ .name = "kcuf1", .value = "\x1b[C" }, // Right arrow
            .{ .name = "kcub1", .value = "\x1b[D" }, // Left arrow

            // Function keys
            .{ .name = "kf1", .value = "\x1bOP" },
            .{ .name = "kf2", .value = "\x1bOQ" },
            .{ .name = "kf3", .value = "\x1bOR" },
            .{ .name = "kf4", .value = "\x1bOS" },
            .{ .name = "kf5", .value = "\x1b[15~" },
            .{ .name = "kf6", .value = "\x1b[17~" },
            .{ .name = "kf7", .value = "\x1b[18~" },
            .{ .name = "kf8", .value = "\x1b[19~" },
            .{ .name = "kf9", .value = "\x1b[20~" },
            .{ .name = "kf10", .value = "\x1b[21~" },
            .{ .name = "kf11", .value = "\x1b[22~" },
            .{ .name = "kf12", .value = "\x1b[23~" },

            // Navigation keys
            .{ .name = "khome", .value = "\x1b[H" },
            .{ .name = "kend", .value = "\x1b[F" },
            .{ .name = "kpp", .value = "\x1b[5~" }, // Page up
            .{ .name = "knp", .value = "\x1b[6~" }, // Page down
            .{ .name = "kich1", .value = "\x1b[2~" }, // Insert
            .{ .name = "kdch1", .value = "\x1b[3~" }, // Delete

            // Keypad keys
            .{ .name = "ka1", .value = "\x1b[H" }, // Keypad home (same as home)
            .{ .name = "ka3", .value = "\x1b[5~" }, // Keypad page up
            .{ .name = "kb2", .value = "\x1b[2~" }, // Keypad center (insert)
            .{ .name = "kbeg", .value = "\x1b[H" }, // Keypad begin (home)
            .{ .name = "kc1", .value = "\x1b[F" }, // Keypad end
            .{ .name = "kc3", .value = "\x1b[6~" }, // Keypad page down
        };

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
            for (common_keys) |key| {
                try self.addCapability(key.name, key.value);
            }
        }
    }

    fn addCapability(self: *Database, name: []const u8, value: []const u8) !void {
        const name_dup = try self.allocator.dupe(u8, name);
        const value_dup = try self.allocator.dupe(u8, value);
        try self.capabilities.put(name_dup, value_dup);
    }
};

/// Terminfo binary format parser
const TerminfoParser = struct {
    data: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    // Terminfo format constants
    const MAGIC_NUMBER_OLD: u16 = 0o432; // Octal 432 (legacy format)
    const MAGIC_NUMBER_NEW: u16 = 0o542; // Octal 542 (extended format)

    /// Parse the terminfo binary data
    fn parse(self: *TerminfoParser, db: *Database) !void {
        // Parse header (12 bytes)
        const header = try self.parseHeader();

        // Skip terminal names section
        const names_size = header.names_size;
        if (self.pos + names_size > self.data.len) return error.InvalidFormat;
        self.pos += names_size;

        // Parse boolean capabilities
        const bool_count = header.bool_count;
        if (self.pos + bool_count > self.data.len) return error.InvalidFormat;
        const bools = self.data[self.pos .. self.pos + bool_count];
        self.pos += bool_count;

        // Align to even byte boundary for numbers
        if (self.pos % 2 != 0) {
            self.pos += 1;
        }

        // Parse numeric capabilities
        const num_count = header.num_count;
        const num_bytes = num_count * 2; // Each number is 2 bytes
        if (self.pos + num_bytes > self.data.len) return error.InvalidFormat;
        const numbers = self.data[self.pos .. self.pos + num_bytes];
        self.pos += num_bytes;

        // Parse string capabilities offsets
        const string_count = header.string_count;
        const string_offset_bytes = string_count * 2; // Each offset is 2 bytes
        if (self.pos + string_offset_bytes > self.data.len) return error.InvalidFormat;
        const string_offsets = self.data[self.pos .. self.pos + string_offset_bytes];
        self.pos += string_offset_bytes;

        // Parse string table
        const string_table_size = header.string_table_size;
        if (self.pos + string_table_size > self.data.len) return error.InvalidFormat;
        const string_table = self.data[self.pos .. self.pos + string_table_size];

        // Map string capabilities to the database
        try self.mapStringCapabilities(db, string_offsets, string_table, string_count);

        // Map boolean capabilities
        try self.mapBooleanCapabilities(db, bools, bool_count);

        // Map numeric capabilities
        try self.mapNumericCapabilities(db, numbers, num_count);
    }

    /// Terminfo header structure (12 bytes)
    const Header = struct {
        magic: u16, // Magic number (0432 or 0542)
        names_size: u16, // Size of terminal names section
        bool_count: u16, // Number of boolean capabilities
        num_count: u16, // Number of numeric capabilities
        string_count: u16, // Number of string capabilities
        string_table_size: u16, // Size of string table
    };

    /// Parse the terminfo header
    fn parseHeader(self: *TerminfoParser) !Header {
        if (self.data.len < 12) return error.InvalidFormat;

        const magic = self.readU16();
        if (magic != MAGIC_NUMBER_OLD and magic != MAGIC_NUMBER_NEW) {
            return error.InvalidMagicNumber;
        }

        return Header{
            .magic = magic,
            .names_size = self.readU16(),
            .bool_count = self.readU16(),
            .num_count = self.readU16(),
            .string_count = self.readU16(),
            .string_table_size = self.readU16(),
        };
    }

    /// Read a 16-bit little-endian value
    fn readU16(self: *TerminfoParser) u16 {
        const value = std.mem.readInt(u16, self.data[self.pos..][0..2], .little);
        self.pos += 2;
        return value;
    }

    /// Map string capabilities to the database
    fn mapStringCapabilities(_: *TerminfoParser, db: *Database, offsets: []const u8, table: []const u8, count: u16) !void {
        // Important string capability indices (from ncurses term.h)
        // String capabilities are indexed starting from 0 in their own section
        const CapIndices = struct {
            const kcuu1 = 66; // key_up
            const kcud1 = 65; // key_down
            const kcub1 = 64; // key_left
            const kcuf1 = 67; // key_right
            const khome = 70; // key_home
            const kend = 69; // key_end
            const kpp = 71; // key_ppage
            const knp = 72; // key_npage
            const kich1 = 73; // key_ic
            const kdch1 = 74; // key_dc
            const kf1 = 76; // key_f1
            const kf2 = 77; // key_f2
            const kf3 = 78; // key_f3
            const kf4 = 79; // key_f4
            const kf5 = 80; // key_f5
            const kf6 = 81; // key_f6
            const kf7 = 82; // key_f7
            const kf8 = 83; // key_f8
            const kf9 = 84; // key_f9
            const kf10 = 75; // key_f0 (F10)
            const kf11 = 85; // key_f11
            const kf12 = 86; // key_f12
        };

        // Map of capability name to index
        const capabilities = [_]struct { name: []const u8, index: u16 }{
            .{ .name = "kcuu1", .index = CapIndices.kcuu1 },
            .{ .name = "kcud1", .index = CapIndices.kcud1 },
            .{ .name = "kcub1", .index = CapIndices.kcub1 },
            .{ .name = "kcuf1", .index = CapIndices.kcuf1 },
            .{ .name = "khome", .index = CapIndices.khome },
            .{ .name = "kend", .index = CapIndices.kend },
            .{ .name = "kpp", .index = CapIndices.kpp },
            .{ .name = "knp", .index = CapIndices.knp },
            .{ .name = "kich1", .index = CapIndices.kich1 },
            .{ .name = "kdch1", .index = CapIndices.kdch1 },
            .{ .name = "kf1", .index = CapIndices.kf1 },
            .{ .name = "kf2", .index = CapIndices.kf2 },
            .{ .name = "kf3", .index = CapIndices.kf3 },
            .{ .name = "kf4", .index = CapIndices.kf4 },
            .{ .name = "kf5", .index = CapIndices.kf5 },
            .{ .name = "kf6", .index = CapIndices.kf6 },
            .{ .name = "kf7", .index = CapIndices.kf7 },
            .{ .name = "kf8", .index = CapIndices.kf8 },
            .{ .name = "kf9", .index = CapIndices.kf9 },
            .{ .name = "kf10", .index = CapIndices.kf10 },
            .{ .name = "kf11", .index = CapIndices.kf11 },
            .{ .name = "kf12", .index = CapIndices.kf12 },
        };

        // Process each capability
        for (capabilities) |cap| {
            const name = cap.name;
            const index = cap.index;

            // Check if this capability index is within our string count
            if (index >= count) continue;

            // Read the offset from the offsets table
            const offset_pos = index * 2;
            if (offset_pos + 2 > offsets.len) continue;

            const offset = std.mem.readInt(u16, offsets[offset_pos..][0..2], .little);

            // Skip if offset is 0xFFFF (not present)
            if (offset == 0xFFFF) continue;

            // Extract the string from the string table
            if (offset >= table.len) continue;

            // Find the null terminator
            var end = offset;
            while (end < table.len and table[end] != 0) : (end += 1) {}

            if (end > offset) {
                const value = table[offset..end];
                try db.addCapability(name, value);
            }
        }
    }

    /// Map boolean capabilities to the database
    fn mapBooleanCapabilities(_: *TerminfoParser, db: *Database, bools: []const u8, _: u16) !void {

        // Boolean capability indices (from term.h)
        const BoolIndices = struct {
            const has_meta_key = 37; // km - Has a meta key
            const auto_right_margin = 0; // am - Terminal has automatic margins
            const can_change = 16; // ccc - Terminal can re-define existing colors
        };

        // Map important boolean capabilities
        if (BoolIndices.has_meta_key < bools.len and bools[BoolIndices.has_meta_key] != 0) {
            try db.addCapability("km", "true");
        }
        if (BoolIndices.auto_right_margin < bools.len and bools[BoolIndices.auto_right_margin] != 0) {
            try db.addCapability("am", "true");
        }
        if (BoolIndices.can_change < bools.len and bools[BoolIndices.can_change] != 0) {
            try db.addCapability("ccc", "true");
        }
    }

    /// Map numeric capabilities to the database
    fn mapNumericCapabilities(_: *TerminfoParser, db: *Database, numbers: []const u8, _: u16) !void {

        // Numeric capability indices (from term.h)
        const NumIndices = struct {
            const columns = 0; // cols - Number of columns
            const lines = 2; // lines - Number of lines
            const colors = 13; // colors - Number of colors
            const pairs = 14; // pairs - Number of color pairs
        };

        // Helper to read numeric value
        const ReadNum = struct {
            fn read(data: []const u8, index: u16) ?u16 {
                const pos = index * 2;
                if (pos + 2 > data.len) return null;
                const value = std.mem.readInt(u16, data[pos..][0..2], .little);
                if (value == 0xFFFF) return null; // Not present
                return value;
            }
        }.read;

        // Map numeric capabilities
        if (ReadNum(numbers, NumIndices.columns)) |cols| {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{}", .{cols}) catch return;
            try db.addCapability("cols", str);
        }
        if (ReadNum(numbers, NumIndices.lines)) |lines| {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{}", .{lines}) catch return;
            try db.addCapability("lines", str);
        }
        if (ReadNum(numbers, NumIndices.colors)) |colors| {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{}", .{colors}) catch return;
            try db.addCapability("colors", str);
        }
        if (ReadNum(numbers, NumIndices.pairs)) |pairs| {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{}", .{pairs}) catch return;
            try db.addCapability("pairs", str);
        }
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
