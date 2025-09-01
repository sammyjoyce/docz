const std = @import("std");
const json = std.json;
const fs = @import("../lib/fs.zig");

pub const Error = fs.Error || error{
    UnknownCommand,
    InvalidParameters,
    InvalidPath,
    FileExists,
    DirectoryExists,
    DirectoryNotEmpty,
    SourceNotFound,
    OperationNotPermitted,
};

pub const Command = enum {
    create_file,
    create_directory,
    copy_file,
    move_file,
    delete_file,
    delete_directory,

    pub fn fromString(str: []const u8) ?Command {
        return std.meta.stringToEnum(Command, str);
    }
};

/// Main entry point for file operations
pub fn execute(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    return executeInternal(allocator, params) catch |err| {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = false });
        try result.put("error", json.Value{ .string = @errorName(err) });
        try result.put("tool", json.Value{ .string = "file" });
        return json.Value{ .object = result };
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: json.Value) !json.Value {
    const params_obj = params.object;

    const command_val = params_obj.get("command") orelse return Error.UnknownCommand;
    if (command_val != .string) return Error.InvalidParameters;
    const command_str = command_val.string;
    const command = Command.fromString(command_str) orelse return Error.UnknownCommand;

    return switch (command) {
        .create_file => createFile(allocator, params_obj),
        .create_directory => createDirectory(allocator, params_obj),
        .copy_file => copyFile(allocator, params_obj),
        .move_file => moveFile(allocator, params_obj),
        .delete_file => deleteFile(allocator, params_obj),
        .delete_directory => deleteDirectory(allocator, params_obj),
    };
}

/// Create a new file
fn createFile(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const file_path = params.get("file_path").?.string;
    const template_content_json = params.get("template_content") orelse json.Value{ .string = "" };
    const if_exists_json = params.get("if_exists") orelse json.Value{ .string = "error" };

    // Validate path
    if (!isValidPath(file_path)) {
        return Error.InvalidPath;
    }

    const template_content = template_content_json.string;
    const if_exists = if_exists_json.string;

    // Check if file already exists
    const file_exists = fs.fileExists(file_path);

    if (file_exists) {
        if (std.mem.eql(u8, if_exists, "error")) {
            return Error.FileExists;
        } else if (std.mem.eql(u8, if_exists, "skip")) {
            var result = json.ObjectMap.init(allocator);
            try result.put("success", json.Value{ .bool = true });
            try result.put("tool", json.Value{ .string = "file" });
            try result.put("command", json.Value{ .string = "create_file" });
            try result.put("file_path", json.Value{ .string = file_path });
            try result.put("skipped", json.Value{ .bool = true });
            try result.put("reason", json.Value{ .string = "file_already_exists" });
            return json.Value{ .object = result };
        }
        // if_exists == "overwrite" continues to write
    }

    // Create parent directory if it doesn't exist
    if (std.fs.path.dirname(file_path)) |dir_path| {
        try fs.createDir(dir_path, true);
    }

    // Write file content
    try fs.writeFile(file_path, template_content);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "file" });
    try result.put("command", json.Value{ .string = "create_file" });
    try result.put("file_path", json.Value{ .string = file_path });
    try result.put("size", json.Value{ .integer = @as(i64, @intCast(@min(template_content.len, std.math.maxInt(i64)))) });
    try result.put("overwritten", json.Value{ .bool = file_exists });

    return json.Value{ .object = result };
}

/// Create a new directory
fn createDirectory(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const directory_path = params.get("directory_path").?.string;
    const recursive_json = params.get("recursive") orelse json.Value{ .bool = true };

    // Validate path
    if (!isValidPath(directory_path)) {
        return Error.InvalidPath;
    }

    const recursive = recursive_json.bool;

    // Check if directory already exists
    const file_metadata = fs.getFileInfo(directory_path) catch |err| switch (err) {
        fs.Error.FileNotFound => null,
        else => return err,
    };

    if (file_metadata) |info| {
        if (info.is_dir) {
            var result = json.ObjectMap.init(allocator);
            try result.put("success", json.Value{ .bool = true });
            try result.put("tool", json.Value{ .string = "file" });
            try result.put("command", json.Value{ .string = "create_directory" });
            try result.put("directory_path", json.Value{ .string = directory_path });
            try result.put("already_existed", json.Value{ .bool = true });
            return json.Value{ .object = result };
        } else {
            return Error.FileExists;
        }
    }

    // Create directory
    try fs.createDir(directory_path, recursive);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "file" });
    try result.put("command", json.Value{ .string = "create_directory" });
    try result.put("directory_path", json.Value{ .string = directory_path });
    try result.put("recursive", json.Value{ .bool = recursive });

    return json.Value{ .object = result };
}

/// Copy a file
fn copyFile(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const source_path = params.get("source_path").?.string;
    const destination_path = params.get("destination_path").?.string;
    const overwrite_json = params.get("overwrite") orelse json.Value{ .bool = false };

    // Validate paths
    if (!isValidPath(source_path) or !isValidPath(destination_path)) {
        return Error.InvalidPath;
    }

    const overwrite = overwrite_json.bool;

    // Check if source exists
    const source_metadata = try fs.getFileInfo(source_path);
    if (!source_metadata.is_file) {
        return Error.SourceNotFound;
    }

    // Check if destination exists
    const dest_exists = fs.fileExists(destination_path);
    if (dest_exists and !overwrite) {
        return Error.FileExists;
    }

    // Create destination directory if needed
    if (std.fs.path.dirname(destination_path)) |dir_path| {
        try fs.createDir(dir_path, true);
    }

    // Copy file using extended fs function
    try fs.copyFile(allocator, source_path, destination_path);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "file" });
    try result.put("command", json.Value{ .string = "copy_file" });
    try result.put("source_path", json.Value{ .string = source_path });
    try result.put("destination_path", json.Value{ .string = destination_path });
    try result.put("overwritten", json.Value{ .bool = dest_exists });
    try result.put("size", json.Value{ .integer = @as(i64, @intCast(@min(source_metadata.size, std.math.maxInt(i64)))) });

    return json.Value{ .object = result };
}

/// Move/rename a file
fn moveFile(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const source_path = params.get("source_path").?.string;
    const destination_path = params.get("destination_path").?.string;
    const overwrite_json = params.get("overwrite") orelse json.Value{ .bool = false };

    // Validate paths
    if (!isValidPath(source_path) or !isValidPath(destination_path)) {
        return Error.InvalidPath;
    }

    const overwrite = overwrite_json.bool;

    // Check if source exists
    const source_metadata = try fs.getFileInfo(source_path);
    if (!source_metadata.is_file) {
        return Error.SourceNotFound;
    }

    // Check if destination exists
    const dest_exists = fs.fileExists(destination_path);
    if (dest_exists and !overwrite) {
        return Error.FileExists;
    }

    // Create destination directory if needed
    if (std.fs.path.dirname(destination_path)) |dir_path| {
        try fs.createDir(dir_path, true);
    }

    // Move file using extended fs function
    try fs.moveFile(source_path, destination_path);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "file" });
    try result.put("command", json.Value{ .string = "move_file" });
    try result.put("source_path", json.Value{ .string = source_path });
    try result.put("destination_path", json.Value{ .string = destination_path });
    try result.put("overwritten", json.Value{ .bool = dest_exists });
    try result.put("size", json.Value{ .integer = @as(i64, @intCast(@min(source_metadata.size, std.math.maxInt(i64)))) });

    return json.Value{ .object = result };
}

/// Delete a file
fn deleteFile(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const file_path = params.get("file_path").?.string;

    // Validate path
    if (!isValidPath(file_path)) {
        return Error.InvalidPath;
    }

    // Check if file exists and is a file
    const file_metadata = try fs.getFileInfo(file_path);
    if (!file_metadata.is_file) {
        return Error.SourceNotFound;
    }

    // Delete file using extended fs function
    try fs.deleteFile(file_path);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "file" });
    try result.put("command", json.Value{ .string = "delete_file" });
    try result.put("file_path", json.Value{ .string = file_path });
    try result.put("deleted_size", json.Value{ .integer = @as(i64, @intCast(@min(file_metadata.size, std.math.maxInt(i64)))) });

    return json.Value{ .object = result };
}

/// Delete a directory
fn deleteDirectory(allocator: std.mem.Allocator, params: json.ObjectMap) !json.Value {
    const directory_path = params.get("directory_path").?.string;
    const recursive_json = params.get("recursive") orelse json.Value{ .bool = false };

    // Validate path
    if (!isValidPath(directory_path)) {
        return Error.InvalidPath;
    }

    const recursive = recursive_json.bool;

    // Check if directory exists and is a directory
    const file_metadata = try fs.getFileInfo(directory_path);
    if (!file_metadata.is_dir) {
        return Error.SourceNotFound;
    }

    // Check if directory is empty (if not recursive)
    if (!recursive) {
        const entries = fs.listDir(allocator, directory_path, 1) catch |err| switch (err) {
            fs.Error.FileNotFound => return Error.SourceNotFound,
            else => return err,
        };
        defer {
            for (entries) |entry| allocator.free(entry);
            allocator.free(entries);
        }

        if (entries.len > 0) {
            return Error.DirectoryNotEmpty;
        }
    }

    // Delete directory using extended fs function
    try fs.deleteDir(directory_path, recursive);

    var result = json.ObjectMap.init(allocator);
    try result.put("success", json.Value{ .bool = true });
    try result.put("tool", json.Value{ .string = "file" });
    try result.put("command", json.Value{ .string = "delete_directory" });
    try result.put("directory_path", json.Value{ .string = directory_path });
    try result.put("recursive", json.Value{ .bool = recursive });

    return json.Value{ .object = result };
}

// Helper Functions

/// Validate path to prevent directory traversal attacks
fn isValidPath(path: []const u8) bool {
    if (path.len == 0) return false;

    // Check for directory traversal patterns
    if (std.mem.indexOf(u8, path, "..") != null) return false;

    // Check for absolute paths starting from root (may be too restrictive)
    // Allow relative and absolute paths but prevent traversal
    if (std.mem.startsWith(u8, path, "/..") or
        std.mem.startsWith(u8, path, "../") or
        std.mem.indexOf(u8, path, "/../") != null or
        std.mem.endsWith(u8, path, "/.."))
    {
        return false;
    }

    return true;
}
