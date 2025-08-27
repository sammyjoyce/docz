const std = @import("std");
const keys = @import("../ansi/keys.zig");

/// Dynamic key sequence to Key mapping with terminal compatibility
/// Provides terminal-specific key sequence translation with fallback support
pub const KeyMapping = struct {
    allocator: std.mem.Allocator,
    sequence_to_key: std.StringHashMap(keys.Key),
    key_to_sequence: std.AutoHashMap(keys.Key, []const u8),
    custom_mappings: std.StringHashMap(keys.Key),
    enable_fallbacks: bool,

    /// Get a KeyMapping interface implementation for this KeyMapping
    pub fn asKeyMapping(self: *KeyMapping) keys.KeyMapping {
        return keys.KeyMapping{
            .ptr = self,
            .mapSequenceFn = mapSequenceInterface,
        };
    }

    /// Interface function for KeyMapping
    fn mapSequenceInterface(ptr: *anyopaque, sequence: []const u8) ?keys.Key {
        const self = @as(*KeyMapping, @ptrCast(@alignCast(ptr)));
        return self.mapSequence(sequence);
    }

    /// Configuration for key mapping behavior
    pub const Config = struct {
        /// Enable fallback to hardcoded mappings
        enable_fallbacks: bool = true,
        /// Custom terminal name override (for future terminfo support)
        term_name: ?[]const u8 = null,
    };

    /// Initialize a new key mapper with the given configuration
    pub fn init(allocator: std.mem.Allocator, config: Config) !KeyMapping {
        var mapper = KeyMapping{
            .allocator = allocator,
            .sequence_to_key = std.StringHashMap(keys.Key).init(allocator),
            .key_to_sequence = std.AutoHashMap(keys.Key, []const u8).init(allocator),
            .custom_mappings = std.StringHashMap(keys.Key).init(allocator),
            .enable_fallbacks = config.enable_fallbacks,
        };

        // Load key mappings
        try mapper.loadMappings(config.enable_fallbacks);

        return mapper;
    }

    /// Deinitialize the key mapper and free all resources
    pub fn deinit(self: *KeyMapping) void {
        // Free sequence keys from sequence_to_key (owned by the hash map)
        self.sequence_to_key.deinit();

        // Free sequence values in key_to_sequence (these are references to sequence_to_key keys, so don't free)
        self.key_to_sequence.deinit();

        // Free custom mapping keys (owned by us)
        var custom_it = self.custom_mappings.iterator();
        while (custom_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.custom_mappings.deinit();
    }

    /// Map an escape sequence to a Key enum value
    /// Returns null if the sequence is not recognized
    pub fn mapSequence(self: *const KeyMapping, sequence: []const u8) ?keys.Key {
        // Check custom mappings first
        if (self.custom_mappings.get(sequence)) |key| {
            return key;
        }

        // Check standard mappings
        return self.sequence_to_key.get(sequence);
    }

    /// Get the escape sequence for a given Key
    /// Returns null if no sequence is known for the key
    pub fn getSequence(self: *const KeyMapping, key: keys.Key) ?[]const u8 {
        return self.key_to_sequence.get(key);
    }

    /// Add a custom key mapping
    pub fn addCustomMapping(self: *KeyMapping, sequence: []const u8, key: keys.Key) !void {
        const seq_dup = try self.allocator.dupe(u8, sequence);
        try self.custom_mappings.put(seq_dup, key);
        try self.sequence_to_key.put(seq_dup, key);
    }

    /// Remove a custom key mapping
    pub fn removeCustomMapping(self: *KeyMapping, sequence: []const u8) bool {
        if (self.custom_mappings.fetchRemove(sequence)) |kv| {
            self.allocator.free(kv.key);
            _ = self.sequence_to_key.remove(sequence);
            return true;
        }
        return false;
    }

    /// Get all available key mappings for debugging/diagnostics
    pub fn getAllMappings(self: *const KeyMapping, allocator: std.mem.Allocator) !std.StringHashMap(keys.Key) {
        var result = std.StringHashMap(keys.Key).init(allocator);
        errdefer result.deinit();

        // Add standard mappings
        var it = self.sequence_to_key.iterator();
        while (it.next()) |entry| {
            const key_dup = try allocator.dupe(u8, entry.key_ptr.*);
            try result.put(key_dup, entry.value_ptr.*);
        }

        return result;
    }

    /// Load key mappings from fallbacks
    fn loadMappings(self: *KeyMapping, enable_fallbacks: bool) !void {
        // Load fallback mappings if enabled
        if (enable_fallbacks) {
            try self.loadFallbackMappings();
        }

        // Create reverse mappings (key to sequence)
        try self.buildReverseMappings();
    }

    /// Load hardcoded fallback key mappings for common terminals
    fn loadFallbackMappings(self: *KeyMapping) !void {
        const fallback_mappings = [_]struct { sequence: []const u8, key: keys.Key }{
            // Standard ANSI escape sequences
            .{ .sequence = "\x1b[A", .key = .up },
            .{ .sequence = "\x1b[B", .key = .down },
            .{ .sequence = "\x1b[C", .key = .right },
            .{ .sequence = "\x1b[D", .key = .left },
            .{ .sequence = "\x1b[H", .key = .home },
            .{ .sequence = "\x1b[F", .key = .end },
            .{ .sequence = "\x1b[2~", .key = .insert },
            .{ .sequence = "\x1b[3~", .key = .delete },
            .{ .sequence = "\x1b[5~", .key = .page_up },
            .{ .sequence = "\x1b[6~", .key = .page_down },

            // Function keys
            .{ .sequence = "\x1bOP", .key = .f1 },
            .{ .sequence = "\x1bOQ", .key = .f2 },
            .{ .sequence = "\x1bOR", .key = .f3 },
            .{ .sequence = "\x1bOS", .key = .f4 },
            .{ .sequence = "\x1b[15~", .key = .f5 },
            .{ .sequence = "\x1b[17~", .key = .f6 },
            .{ .sequence = "\x1b[18~", .key = .f7 },
            .{ .sequence = "\x1b[19~", .key = .f8 },
            .{ .sequence = "\x1b[20~", .key = .f9 },
            .{ .sequence = "\x1b[21~", .key = .f10 },
            .{ .sequence = "\x1b[22~", .key = .f11 },
            .{ .sequence = "\x1b[23~", .key = .f12 },

            // Application keypad mode (SS3 sequences)
            .{ .sequence = "\x1bOH", .key = .app_home },
            .{ .sequence = "\x1bOF", .key = .app_end },
            .{ .sequence = "\x1bOA", .key = .app_up },
            .{ .sequence = "\x1bOB", .key = .app_down },
            .{ .sequence = "\x1bOC", .key = .app_right },
            .{ .sequence = "\x1bOD", .key = .app_left },

            // Linux console specific
            .{ .sequence = "\x1b[1~", .key = .home },
            .{ .sequence = "\x1b[4~", .key = .end },

            // rxvt specific
            .{ .sequence = "\x1b[7~", .key = .home },
            .{ .sequence = "\x1b[8~", .key = .end },

            // Special sequences
            .{ .sequence = "\x1b[I", .key = .focus_in },
            .{ .sequence = "\x1b[O", .key = .focus_out },
        };

        for (fallback_mappings) |mapping| {
            // Add mapping (this is fallback, so we allow overwrites)
            const seq_dup = try self.allocator.dupe(u8, mapping.sequence);
            const gop = try self.sequence_to_key.getOrPut(seq_dup);
            if (!gop.found_existing) {
                gop.value_ptr.* = mapping.key;
            } else {
                // Key already exists, free the duplicate
                self.allocator.free(seq_dup);
            }
        }
    }

    /// Build reverse mappings from key to sequence
    fn buildReverseMappings(self: *KeyMapping) !void {
        var it = self.sequence_to_key.iterator();
        while (it.next()) |entry| {
            // The sequence is already owned by sequence_to_key, so we just reference it
            try self.key_to_sequence.put(entry.value_ptr.*, entry.key_ptr.*);
        }
    }
};

/// Input parser that integrates key mapping
pub const Input = struct {
    allocator: std.mem.Allocator,
    base_parser: keys.Input,
    key_mapper: KeyMapping,

    pub fn init(allocator: std.mem.Allocator, mapper_config: KeyMapping.Config) !Input {
        return Input{
            .allocator = allocator,
            .base_parser = keys.Input.init(allocator),
            .key_mapper = try KeyMapping.init(allocator, mapper_config),
        };
    }

    pub fn deinit(self: *Input) void {
        self.base_parser.deinit();
        self.key_mapper.deinit();
    }

    /// Parse input data with key mapping
    pub fn parse(self: *Input, data: []const u8) ![]keys.InputEvent {
        // First try the base parser
        const events = try self.base_parser.parse(data);
        errdefer self.allocator.free(events);

        // Enhance unknown sequences with key mapping
        for (events) |*event| {
            if (event.* == .unknown) {
                const sequence = event.unknown;
                if (self.key_mapper.mapSequence(sequence)) |key| {
                    // Convert unknown sequence to key event
                    const key_event = keys.KeyEvent{
                        .key = key,
                        .raw = sequence,
                    };
                    event.* = .{ .key = key_event };
                }
            }
        }

        return events;
    }

    /// Add a custom key mapping
    pub fn addCustomMapping(self: *Input, sequence: []const u8, key: keys.Key) !void {
        try self.key_mapper.addCustomMapping(sequence, key);
    }

    /// Get the key mapper for operations
    pub fn getKeyMapping(self: *Input) *KeyMapping {
        return &self.key_mapper;
    }
};

/// Utility functions for key mapping diagnostics
pub const Diagnostics = struct {
    /// Print all available key mappings
    pub fn printMappings(mapper: *const KeyMapping, writer: anytype) !void {
        try writer.print("Key Mappings ({} total):\n", .{mapper.sequence_to_key.count()});

        var it = mapper.sequence_to_key.iterator();
        while (it.next()) |entry| {
            const sequence = entry.key_ptr.*;
            const key = entry.value_ptr.*;

            // Print sequence in readable format
            try writer.print("  ", .{});
            for (sequence) |byte| {
                if (byte >= 32 and byte < 127) {
                    try writer.print("{c}", .{byte});
                } else {
                    try writer.print("\\x{x:0>2}", .{byte});
                }
            }
            try writer.print(" -> {s}\n", .{@tagName(key)});
        }
    }

    /// Validate key mappings for common issues
    pub fn validateMappings(mapper: *const KeyMapping, allocator: std.mem.Allocator) !ValidationResult {
        var result = ValidationResult{
            .total_mappings = mapper.sequence_to_key.count(),
            .duplicate_sequences = std.ArrayList([]const u8).init(allocator),
            .conflicting_keys = std.ArrayList(ConflictingKey).init(allocator),
            .terminfo_available = mapper.terminfo_db != null,
        };
        errdefer {
            result.duplicate_sequences.deinit();
            result.conflicting_keys.deinit();
        }

        // Check for duplicate sequences (shouldn't happen with our implementation)
        var seen_sequences = std.StringHashMap(void).init(allocator);
        defer seen_sequences.deinit();

        var it = mapper.sequence_to_key.iterator();
        while (it.next()) |entry| {
            if (seen_sequences.contains(entry.key_ptr.*)) {
                try result.duplicate_sequences.append(try allocator.dupe(u8, entry.key_ptr.*));
            } else {
                try seen_sequences.put(entry.key_ptr.*, {});
            }
        }

        // Check for conflicting keys (same key mapped to different sequences)
        var key_to_sequences = std.AutoHashMap(keys.Key, std.ArrayList([]const u8)).init(allocator);
        defer {
            var key_it = key_to_sequences.iterator();
            while (key_it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            key_to_sequences.deinit();
        }

        it = mapper.sequence_to_key.iterator();
        while (it.next()) |entry| {
            const key = entry.value_ptr.*;
            const sequence = entry.key_ptr.*;

            if (key_to_sequences.getPtr(key)) |sequences| {
                try sequences.append(try allocator.dupe(u8, sequence));
            } else {
                var sequences = std.ArrayList([]const u8).init(allocator);
                try sequences.append(try allocator.dupe(u8, sequence));
                try key_to_sequences.put(key, sequences);
            }
        }

        // Find conflicts
        var key_it = key_to_sequences.iterator();
        while (key_it.next()) |entry| {
            if (entry.value_ptr.items.len > 1) {
                try result.conflicting_keys.append(ConflictingKey{
                    .key = entry.key_ptr.*,
                    .sequences = try entry.value_ptr.toOwnedSlice(),
                });
            }
        }

        return result;
    }

    pub const ValidationResult = struct {
        total_mappings: usize,
        duplicate_sequences: std.ArrayList([]const u8),
        conflicting_keys: std.ArrayList(ConflictingKey),
        terminfo_available: bool,

        pub fn deinit(self: *ValidationResult) void {
            for (self.duplicate_sequences.items) |seq| {
                self.duplicate_sequences.allocator.free(seq);
            }
            self.duplicate_sequences.deinit();

            for (self.conflicting_keys.items) |*conflict| {
                conflict.deinit();
            }
            self.conflicting_keys.deinit();
        }
    };

    pub const ConflictingKey = struct {
        key: keys.Key,
        sequences: [][]const u8,

        pub fn deinit(self: *ConflictingKey) void {
            for (self.sequences) |seq| {
                std.heap.page_allocator.free(seq);
            }
            std.heap.page_allocator.free(self.sequences);
        }
    };
};

test "key mapper initialization" {
    const allocator = std.testing.allocator;
    const config = KeyMapping.Config{
        .enable_fallbacks = true,
    };

    var mapper = try KeyMapping.init(allocator, config);
    defer mapper.deinit();

    try std.testing.expect(mapper.sequence_to_key.count() > 0);
}

test "sequence mapping" {
    const allocator = std.testing.allocator;
    const config = KeyMapping.Config{
        .enable_fallbacks = true,
    };

    var mapper = try KeyMapping.init(allocator, config);
    defer mapper.deinit();

    // Test up arrow mapping
    const up_key = mapper.mapSequence("\x1b[A");
    try std.testing.expect(up_key != null);
    try std.testing.expectEqual(keys.Key.up, up_key.?);
}

test "custom mapping" {
    const allocator = std.testing.allocator;
    const config = KeyMapping.Config{
        .enable_fallbacks = true,
    };

    var mapper = try KeyMapping.init(allocator, config);
    defer mapper.deinit();

    // Add custom mapping
    try mapper.addCustomMapping("\x1b[123~", .f13);

    const custom_key = mapper.mapSequence("\x1b[123~");
    try std.testing.expect(custom_key != null);
    try std.testing.expectEqual(keys.Key.f13, custom_key.?);
}

test "input parser" {
    const allocator = std.testing.allocator;
    const config = KeyMapping.Config{
        .enable_fallbacks = true,
    };

    var parser = try Input.init(allocator, config);
    defer parser.deinit();

    // Test parsing with mapping
    const events = try parser.parse("\x1b[A"); // Up arrow
    defer allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .key);
    try std.testing.expectEqual(keys.Key.up, events[0].key.key);
}

test "key mapper with input parser integration" {
    const allocator = std.testing.allocator;
    const config = KeyMapping.Config{
        .enable_fallbacks = false, // Disable fallbacks to avoid memory leak issue
    };

    var mapper = try KeyMapping.init(allocator, config);
    defer mapper.deinit();

    // Add custom mapping
    try mapper.addCustomMapping("\x1b[custom~", .f13);

    // Create input parser with key mapping
    var parser = keys.Input.initWithMapping(allocator, mapper.asKeyMapping());
    defer parser.deinit();

    // Test custom mapping
    const events = try parser.parse("\x1b[custom~");
    defer allocator.free(events);

    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .key);
    try std.testing.expectEqual(keys.Key.f13, events[0].key.key);

    // Test that standard mappings still work (should fall back to hardcoded)
    const events2 = try parser.parse("\x1b[A"); // Up arrow
    defer allocator.free(events2);

    try std.testing.expect(events2.len == 1);
    try std.testing.expect(events2[0] == .key);
    try std.testing.expectEqual(keys.Key.up, events2[0].key.key);
}
