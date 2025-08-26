const std = @import("std");

pub const Error = error{
    FileNotFound,
    AccessDenied,
    IoError,
    OutOfMemory,
    InvalidPath,
    FileTooLarge,
};

/// Read file content with error handling
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_size: ?usize) Error![]u8 {
    const actual_max = max_size orelse 1024 * 1024 * 10; // 10MB default

    return std.fs.cwd().readFileAlloc(allocator, path, actual_max) catch |err| switch (err) {
        error.FileNotFound => Error.FileNotFound,
        error.AccessDenied => Error.AccessDenied,
        error.OutOfMemory => Error.OutOfMemory,
        error.FileBusy, error.SystemResources, error.NotOpenForReading => Error.IoError,
        else => Error.IoError,
    };
}

/// Write file content with error handling
pub fn writeFile(path: []const u8, content: []const u8) Error!void {
    std.fs.cwd().writeFile(path, content) catch |err| switch (err) {
        error.AccessDenied => return Error.AccessDenied,
        error.OutOfMemory => return Error.OutOfMemory,
        error.NoSpaceLeft, error.FileTooBig, error.Unexpected => return Error.IoError,
        else => return Error.IoError,
    };
}

/// Check if file exists
pub fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Get file metadata
pub const FileInfo = struct {
    size: u64,
    modified: i64,
    is_file: bool,
    is_dir: bool,
};

pub fn getFileInfo(path: []const u8) Error!FileInfo {
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return Error.FileNotFound,
        error.AccessDenied => return Error.AccessDenied,
        else => return Error.IoError,
    };

    return FileInfo{
        .size = stat.size,
        .modified = stat.mtime,
        .is_file = stat.kind == .file,
        .is_dir = stat.kind == .directory,
    };
}

/// List directory contents
pub fn listDir(allocator: std.mem.Allocator, path: []const u8, max_entries: ?usize) Error![][]const u8 {
    const actual_max = max_entries orelse 1000;

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return Error.FileNotFound,
        error.AccessDenied => return Error.AccessDenied,
        else => return Error.IoError,
    };
    defer dir.close();

    var entries = std.ArrayList([]const u8).init(allocator);
    var iterator = dir.iterate();
    var count: usize = 0;

    while (count < actual_max) {
        if (try iterator.next()) |entry| {
            const name = try allocator.dupe(u8, entry.name);
            try entries.append(name);
            count += 1;
        } else break;
    }

    return entries.toOwnedSlice();
}

/// Create directory with optional recursive creation
pub fn createDir(path: []const u8, recursive: bool) Error!void {
    if (recursive) {
        std.fs.cwd().makePath(path) catch |err| switch (err) {
            error.AccessDenied => return Error.AccessDenied,
            error.OutOfMemory => return Error.OutOfMemory,
            error.NoSpaceLeft => return Error.IoError,
            error.PathAlreadyExists => return, // Success if already exists
            else => return Error.IoError,
        };
    } else {
        std.fs.cwd().makeDir(path) catch |err| switch (err) {
            error.AccessDenied => return Error.AccessDenied,
            error.OutOfMemory => return Error.OutOfMemory,
            error.FileNotFound => return Error.InvalidPath, // Parent directory doesn't exist
            error.PathAlreadyExists => return, // Success if already exists
            error.NoSpaceLeft => return Error.IoError,
            else => return Error.IoError,
        };
    }
}

/// Copy file from source to destination
pub fn copyFile(allocator: std.mem.Allocator, src_path: []const u8, dest_path: []const u8) Error!void {
    // Validate source file exists
    _ = getFileInfo(src_path) catch |err| return err;

    // Read source file content
    const content = readFileAlloc(allocator, src_path, null) catch |err| return err;
    defer allocator.free(content);

    // Write to destination
    writeFile(dest_path, content) catch |err| return err;
}

/// Move/rename file from source to destination
pub fn moveFile(src_path: []const u8, dest_path: []const u8) Error!void {
    std.fs.cwd().rename(src_path, dest_path) catch |err| switch (err) {
        error.FileNotFound => return Error.FileNotFound,
        error.AccessDenied => return Error.AccessDenied,
        error.OutOfMemory => return Error.OutOfMemory,
        error.InvalidName => return Error.InvalidPath,
        error.NoSpaceLeft => return Error.IoError,
        error.NotSameFileSystem => {
            // Try copy and delete as fallback for cross-filesystem moves
            // This requires an allocator, so we return an error for now
            return Error.IoError;
        },
        else => return Error.IoError,
    };
}

/// Delete a file
pub fn deleteFile(path: []const u8) Error!void {
    std.fs.cwd().deleteFile(path) catch |err| switch (err) {
        error.FileNotFound => return Error.FileNotFound,
        error.AccessDenied => return Error.AccessDenied,
        error.FileBusy => return Error.IoError,
        error.IsDir => return Error.InvalidPath, // Use deleteDir for directories
        else => return Error.IoError,
    };
}

/// Delete directory with optional recursive deletion
pub fn deleteDir(path: []const u8, recursive: bool) Error!void {
    if (recursive) {
        std.fs.cwd().deleteTree(path) catch |err| switch (err) {
            error.FileNotFound => return Error.FileNotFound,
            error.AccessDenied => return Error.AccessDenied,
            error.OutOfMemory => return Error.OutOfMemory,
            error.FileBusy => return Error.IoError,
            else => return Error.IoError,
        };
    } else {
        std.fs.cwd().deleteDir(path) catch |err| switch (err) {
            error.FileNotFound => return Error.FileNotFound,
            error.AccessDenied => return Error.AccessDenied,
            error.DirNotEmpty => return Error.IoError, // Directory not empty
            error.FileBusy => return Error.IoError,
            else => return Error.IoError,
        };
    }
}
