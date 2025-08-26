/// Editor integration functionality inspired by charmbracelet/x editor module
/// Provides functionality for opening files in external editors with various options.
/// Compatible with Zig 0.15.1
const std = @import("std");
const builtin = @import("builtin");

const default_editor = "nano";

/// Editor option function type
/// Returns additional arguments and whether the path is included in those args
pub const OptionFn = fn (editor_name: []const u8, filename: []const u8) OptionResult;

pub const OptionResult = struct {
    args: []const []const u8,
    path_in_args: bool,
};

/// Option for opening file at specific line number
pub const LineNumberOption = struct {
    line: u32,

    pub fn apply(self: LineNumberOption) OptionFn {
        const S = struct {
            fn optionFn(editor_name: []const u8, filename: []const u8) OptionResult {
                const line = self.line;
                const line_num = if (line < 1) 1 else line;
                
                // Editors that support +line syntax
                const plus_line_editors = [_][]const u8{
                    "vi", "vim", "nvim", "nano", "emacs", "kak", "gedit"
                };
                
                for (plus_line_editors) |editor| {
                    if (std.mem.eql(u8, editor_name, editor)) {
                        const arg = std.fmt.allocPrint(std.heap.page_allocator, "+{d}", .{line_num}) catch return OptionResult{
                            .args = &[_][]const u8{},
                            .path_in_args = false,
                        };
                        return OptionResult{
                            .args = &[_][]const u8{arg},
                            .path_in_args = false,
                        };
                    }
                }
                
                // VS Code with --goto
                if (std.mem.eql(u8, editor_name, "code")) {
                    const arg = std.fmt.allocPrint(std.heap.page_allocator, "{s}:{d}", .{ filename, line_num }) catch return OptionResult{
                        .args = &[_][]const u8{},
                        .path_in_args = false,
                    };
                    return OptionResult{
                        .args = &[_][]const u8{ "--goto", arg },
                        .path_in_args = true,
                    };
                }
                
                return OptionResult{
                    .args = &[_][]const u8{},
                    .path_in_args = false,
                };
            }
        };
        
        return S.optionFn;
    }
};

/// Option for opening file at end of line
pub const EndOfLineOption = struct {
    pub fn apply(_: EndOfLineOption) OptionFn {
        const S = struct {
            fn optionFn(editor_name: []const u8, _: []const u8) OptionResult {
                if (std.mem.eql(u8, editor_name, "vim") or std.mem.eql(u8, editor_name, "nvim")) {
                    return OptionResult{
                        .args = &[_][]const u8{"+norm! $"},
                        .path_in_args = false,
                    };
                }
                
                return OptionResult{
                    .args = &[_][]const u8{},
                    .path_in_args = false,
                };
            }
        };
        
        return S.optionFn;
    }
};

/// Editor command builder
pub const EditorCommand = struct {
    allocator: std.mem.Allocator,
    app_name: []const u8,
    path: []const u8,
    options: std.ArrayListUnmanaged(OptionFn),
    
    pub fn init(allocator: std.mem.Allocator, app_name: []const u8, path: []const u8) EditorCommand {
        return EditorCommand{
            .allocator = allocator,
            .app_name = app_name,
            .path = path,
            .options = std.ArrayListUnmanaged(OptionFn){},
        };
    }
    
    pub fn deinit(self: *EditorCommand) void {
        self.options.deinit(self.allocator);
    }
    
    pub fn lineNumber(self: *EditorCommand, line: u32) !*EditorCommand {
        const option = LineNumberOption{ .line = line };
        try self.options.append(self.allocator, option.apply());
        return self;
    }
    
    pub fn endOfLine(self: *EditorCommand) !*EditorCommand {
        const option = EndOfLineOption{};
        try self.options.append(self.allocator, option.apply());
        return self;
    }
    
    /// Create the child process for the editor
    pub fn spawn(self: *EditorCommand) !std.process.Child {
        // Check for Snap environment restriction
        if (std.posix.getenv("SNAP_REVISION")) |_| {
            return error.SnapRestriction;
        }
        
        const editor, const base_args = getEditor(self.allocator) catch |err| switch (err) {
            error.OutOfMemory => return err,
        };
        defer self.allocator.free(editor);
        defer {
            for (base_args) |arg| self.allocator.free(arg);
            self.allocator.free(base_args);
        }
        
        const editor_name = std.fs.path.basename(editor);
        
        var args = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (args.items) |arg| self.allocator.free(arg);
            args.deinit(self.allocator);
        }
        
        try args.append(self.allocator, try self.allocator.dupe(u8, editor));
        for (base_args) |arg| {
            try args.append(self.allocator, try self.allocator.dupe(u8, arg));
        }
        
        var needs_to_append_path = true;
        
        for (self.options.items) |option| {
            const result = option(editor_name, self.path);
            if (result.path_in_args) {
                needs_to_append_path = false;
            }
            for (result.args) |arg| {
                try args.append(self.allocator, try self.allocator.dupe(u8, arg));
            }
        }
        
        if (needs_to_append_path) {
            try args.append(self.allocator, try self.allocator.dupe(u8, self.path));
        }
        
        var child = std.process.Child.init(args.items, self.allocator);
        try child.spawn();
        return child;
    }
};

/// Get the editor command and arguments from environment
fn getEditor(allocator: std.mem.Allocator) !struct { []const u8, [][]const u8 } {
    const editor_env = std.posix.getenv("EDITOR") orelse default_editor;
    
    // Split the EDITOR environment variable into command and args
    var parts = std.mem.tokenizeScalar(u8, editor_env, ' ');
    
    const editor = parts.next() orelse default_editor;
    
    var args = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (args.items) |arg| allocator.free(arg);
        args.deinit(allocator);
    }
    
    while (parts.next()) |arg| {
        try args.append(allocator, try allocator.dupe(u8, arg));
    }
    
    return .{
        try allocator.dupe(u8, editor),
        try args.toOwnedSlice(allocator),
    };
}

/// Convenience function to open a file with default editor
pub fn openFile(allocator: std.mem.Allocator, app_name: []const u8, path: []const u8) !std.process.Child {
    var cmd = EditorCommand.init(allocator, app_name, path);
    defer cmd.deinit();
    return try cmd.spawn();
}

/// Convenience function to open a file at a specific line
pub fn openFileAtLine(allocator: std.mem.Allocator, app_name: []const u8, path: []const u8, line: u32) !std.process.Child {
    var cmd = EditorCommand.init(allocator, app_name, path);
    defer cmd.deinit();
    _ = try cmd.lineNumber(line);
    return try cmd.spawn();
}

/// Convenience function to open a file at the end of the line
pub fn openFileAtEndOfLine(allocator: std.mem.Allocator, app_name: []const u8, path: []const u8) !std.process.Child {
    var cmd = EditorCommand.init(allocator, app_name, path);
    defer cmd.deinit();
    _ = try cmd.endOfLine();
    return try cmd.spawn();
}

/// Check if we're running in a Snap environment
pub fn isSnapEnvironment() bool {
    return std.posix.getenv("SNAP_REVISION") != null;
}

/// Get the default editor name
pub fn getDefaultEditor() []const u8 {
    return std.posix.getenv("EDITOR") orelse default_editor;
}

// Tests
test "line number option" {
    const option = LineNumberOption{ .line = 42 };
    const option_fn = option.apply();
    
    const result = option_fn("vim", "test.txt");
    try std.testing.expect(!result.path_in_args);
    try std.testing.expect(result.args.len == 1);
    try std.testing.expect(std.mem.startsWith(u8, result.args[0], "+42"));
}

test "VS Code line number option" {
    const option = LineNumberOption{ .line = 10 };
    const option_fn = option.apply();
    
    const result = option_fn("code", "test.txt");
    try std.testing.expect(result.path_in_args);
    try std.testing.expect(result.args.len == 2);
    try std.testing.expectEqualStrings("--goto", result.args[0]);
    try std.testing.expect(std.mem.endsWith(u8, result.args[1], ":10"));
}

test "end of line option" {
    const option = EndOfLineOption{};
    const option_fn = option.apply();
    
    const result = option_fn("vim", "test.txt");
    try std.testing.expect(!result.path_in_args);
    try std.testing.expect(result.args.len == 1);
    try std.testing.expectEqualStrings("+norm! $", result.args[0]);
}

test "unsupported editor" {
    const option = LineNumberOption{ .line = 5 };
    const option_fn = option.apply();
    
    const result = option_fn("unknown_editor", "test.txt");
    try std.testing.expect(!result.path_in_args);
    try std.testing.expect(result.args.len == 0);
}