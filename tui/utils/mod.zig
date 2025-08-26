//! TUI Utils Module
//!
//! Utility functions and helpers for TUI components

const std = @import("std");

// Command history functionality (placeholder - would extract from src/tui.zig)
pub const CommandHistory = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayList([]const u8),
    
    pub fn init(allocator: std.mem.Allocator) !CommandHistory {
        return .{
            .allocator = allocator,
            .history = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *CommandHistory) void {
        for (self.history.items) |item| {
            self.allocator.free(item);
        }
        self.history.deinit();
    }
    
    pub fn add(self: *CommandHistory, command: []const u8) !void {
        const owned = try self.allocator.dupe(u8, command);
        try self.history.append(owned);
    }
    
    pub fn get(self: *CommandHistory, index: usize) ?[]const u8 {
        if (index >= self.history.items.len) return null;
        return self.history.items[index];
    }
};