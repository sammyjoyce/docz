// Shell integration namespace

const std = @import("std");

/// Shell types
pub const ShellType = enum {
    bash,
    zsh,
    fish,
    powershell,
    cmd,
    unknown,
};

/// Detect current shell
pub fn detectShell() ShellType {
    // Check SHELL environment variable
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "SHELL")) |shell| {
        defer std.heap.page_allocator.free(shell);
        
        if (std.mem.indexOf(u8, shell, "bash") != null) return .bash;
        if (std.mem.indexOf(u8, shell, "zsh") != null) return .zsh;
        if (std.mem.indexOf(u8, shell, "fish") != null) return .fish;
        if (std.mem.indexOf(u8, shell, "pwsh") != null) return .powershell;
    } else |_| {}
    
    // Check for Windows
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "COMSPEC")) |comspec| {
        defer std.heap.page_allocator.free(comspec);
        if (std.mem.indexOf(u8, comspec, "cmd.exe") != null) return .cmd;
        if (std.mem.indexOf(u8, comspec, "powershell") != null) return .powershell;
    } else |_| {}
    
    return .unknown;
}

/// Shell integration for command history
pub const History = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    entries: std.ArrayList([]u8),
    current: usize = 0,
    
    /// Initialize history
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList([]u8).init(allocator),
        };
    }
    
    /// Deinitialize history
    pub fn deinit(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry);
        }
        self.entries.deinit();
    }
    
    /// Add entry to history
    pub fn add(self: *Self, entry: []const u8) !void {
        const copy = try self.allocator.dupe(u8, entry);
        try self.entries.append(copy);
        self.current = self.entries.items.len;
    }
    
    /// Get previous entry
    pub fn previous(self: *Self) ?[]const u8 {
        if (self.current > 0) {
            self.current -= 1;
            return self.entries.items[self.current];
        }
        return null;
    }
    
    /// Get next entry
    pub fn next(self: *Self) ?[]const u8 {
        if (self.current < self.entries.items.len - 1) {
            self.current += 1;
            return self.entries.items[self.current];
        }
        return null;
    }
};

/// OSC (Operating System Command) sequences
pub fn setTitle(writer: anytype, title: []const u8) !void {
    try writer.print("\x1b]0;{s}\x07", .{title});
}

/// Set current working directory (for terminal tabs)
pub fn setCwd(writer: anytype, path: []const u8) !void {
    try writer.print("\x1b]7;file://{s}\x07", .{path});
}

/// Mark prompt start/end for shell integration
pub fn markPromptStart(writer: anytype) !void {
    try writer.writeAll("\x1b]133;A\x07");
}

pub fn markPromptEnd(writer: anytype) !void {
    try writer.writeAll("\x1b]133;B\x07");
}

/// Mark command start/end
pub fn markCommandStart(writer: anytype) !void {
    try writer.writeAll("\x1b]133;C\x07");
}

pub fn markCommandEnd(writer: anytype, exit_code: u8) !void {
    try writer.print("\x1b]133;D;{}\x07", .{exit_code});
}
