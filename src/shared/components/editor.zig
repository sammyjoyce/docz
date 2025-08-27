/// Editor integration functionality for external editor support
/// Provides functionality for opening files in external editors with various options.
/// Compatible with Zig 0.15.1
const std = @import("std");
const builtin = @import("builtin");

const defaultEditor = "nano";

/// Editor option function type
/// Returns additional arguments and whether the path is included in those args
pub const OptionFunction = fn (editorName: []const u8, filename: []const u8) Result;

pub const Result = struct {
    args: []const []const u8,
    pathInArgs: bool,
};

/// Option for opening file at specific line number
pub const LinePosition = struct {
    line: u32,

    pub fn apply(self: LinePosition) OptionFunction {
        const S = struct {
            fn optionFn(editorName: []const u8, filename: []const u8) Result {
                const line = self.line;
                const lineNumber = if (line < 1) 1 else line;

                // Editors that support +line syntax
                const plusLineEditors = [_][]const u8{ "vi", "vim", "nvim", "nano", "emacs", "kak", "gedit" };

                for (plusLineEditors) |editor| {
                    if (std.mem.eql(u8, editorName, editor)) {
                        const arg = std.fmt.allocPrint(std.heap.page_allocator, "+{d}", .{lineNumber}) catch return Result{
                            .args = &[_][]const u8{},
                            .pathInArgs = false,
                        };
                        return Result{
                            .args = &[_][]const u8{arg},
                            .pathInArgs = false,
                        };
                    }
                }

                // VS Code with --goto
                if (std.mem.eql(u8, editorName, "code")) {
                    const arg = std.fmt.allocPrint(std.heap.page_allocator, "{s}:{d}", .{ filename, lineNumber }) catch return Result{
                        .args = &[_][]const u8{},
                        .pathInArgs = false,
                    };
                    return Result{
                        .args = &[_][]const u8{ "--goto", arg },
                        .pathInArgs = true,
                    };
                }

                return Result{
                    .args = &[_][]const u8{},
                    .pathInArgs = false,
                };
            }
        };

        return S.optionFn;
    }
};

/// Option for opening file at end of line
pub const EndLinePosition = struct {
    pub fn apply(_: EndLinePosition) OptionFunction {
        const S = struct {
            fn optionFn(editorName: []const u8, _: []const u8) Result {
                if (std.mem.eql(u8, editorName, "vim") or std.mem.eql(u8, editorName, "nvim")) {
                    return Result{
                        .args = &[_][]const u8{"+norm! $"},
                        .pathInArgs = false,
                    };
                }

                return Result{
                    .args = &[_][]const u8{},
                    .pathInArgs = false,
                };
            }
        };

        return S.optionFn;
    }
};

/// Editor command builder
pub const Command = struct {
    allocator: std.mem.Allocator,
    appName: []const u8,
    path: []const u8,
    options: std.ArrayListUnmanaged(OptionFunction),

    pub fn init(allocator: std.mem.Allocator, appName: []const u8, path: []const u8) Command {
        return Command{
            .allocator = allocator,
            .appName = appName,
            .path = path,
            .options = std.ArrayListUnmanaged(OptionFunction){},
        };
    }

    pub fn deinit(self: *Command) void {
        self.options.deinit(self.allocator);
    }

    pub fn lineNumber(self: *Command, line: u32) !*Command {
        const option = LinePosition{ .line = line };
        try self.options.append(self.allocator, option.apply());
        return self;
    }

    pub fn endOfLine(self: *Command) !*Command {
        const option = EndLinePosition{};
        try self.options.append(self.allocator, option.apply());
        return self;
    }

    /// Create the child process for the editor
    pub fn spawn(self: *Command) !std.process.Child {
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

        const editorName = std.fs.path.basename(editor);

        var args = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (args.items) |arg| self.allocator.free(arg);
            args.deinit(self.allocator);
        }

        try args.append(self.allocator, try self.allocator.dupe(u8, editor));
        for (base_args) |arg| {
            try args.append(self.allocator, try self.allocator.dupe(u8, arg));
        }

        var needsToAppendPath = true;

        for (self.options.items) |option| {
            const result = option(editorName, self.path);
            if (result.pathInArgs) {
                needsToAppendPath = false;
            }
            for (result.args) |arg| {
                try args.append(self.allocator, try self.allocator.dupe(u8, arg));
            }
        }

        if (needsToAppendPath) {
            try args.append(self.allocator, try self.allocator.dupe(u8, self.path));
        }

        var child = std.process.Child.init(args.items, self.allocator);
        try child.spawn();
        return child;
    }
};

/// Get the editor command and arguments from environment
fn getEditor(allocator: std.mem.Allocator) !struct { []const u8, [][]const u8 } {
    const editorEnvironment = std.posix.getenv("EDITOR") orelse defaultEditor;

    // Split the EDITOR environment variable into command and args
    var parts = std.mem.tokenizeScalar(u8, editorEnvironment, ' ');

    const editor = parts.next() orelse defaultEditor;

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
pub fn openFile(allocator: std.mem.Allocator, appName: []const u8, path: []const u8) !std.process.Child {
    var cmd = Command.init(allocator, appName, path);
    defer cmd.deinit();
    return try cmd.spawn();
}

/// Convenience function to open a file at a specific line
pub fn openFileAtLine(allocator: std.mem.Allocator, appName: []const u8, path: []const u8, line: u32) !std.process.Child {
    var cmd = Command.init(allocator, appName, path);
    defer cmd.deinit();
    _ = try cmd.lineNumber(line);
    return try cmd.spawn();
}

/// Convenience function to open a file at the end of the line
pub fn openFileAtEndOfLine(allocator: std.mem.Allocator, appName: []const u8, path: []const u8) !std.process.Child {
    var cmd = Command.init(allocator, appName, path);
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
    return std.posix.getenv("EDITOR") orelse defaultEditor;
}

// Tests
test "line number option" {
    const option = LinePosition{ .line = 42 };
    const option_fn = option.apply();

    const result = option_fn("vim", "test.txt");
    try std.testing.expect(!result.pathInArgs);
    try std.testing.expect(result.args.len == 1);
    try std.testing.expect(std.mem.startsWith(u8, result.args[0], "+42"));
}

test "VS Code line option" {
    const option = LinePosition{ .line = 10 };
    const option_fn = option.apply();

    const result = option_fn("code", "test.txt");
    try std.testing.expect(result.pathInArgs);
    try std.testing.expect(result.args.len == 2);
    try std.testing.expectEqualStrings("--goto", result.args[0]);
    try std.testing.expect(std.mem.endsWith(u8, result.args[1], ":10"));
}

test "unsupported editor line option" {
    const option = LinePosition{ .line = 5 };
    const option_fn = option.apply();

    const result = option_fn("unknown_editor", "test.txt");
    try std.testing.expect(!result.pathInArgs);
    try std.testing.expect(result.args.len == 0);
}

test "end of line option" {
    const option = EndLinePosition{};
    const option_fn = option.apply();

    const result = option_fn("vim", "test.txt");
    try std.testing.expect(!result.pathInArgs);
    try std.testing.expect(result.args.len == 1);
    try std.testing.expectEqualStrings("+norm! $", result.args[0]);
}
