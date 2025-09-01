//! Secure credential storage with file permissions and atomic writes

const std = @import("std");
const fs = std.fs;
const json = std.json;
const builtin = @import("builtin");

const log = std.log.scoped(.auth_store);

/// OAuth credentials to persist
pub const StoredCredentials = struct {
    type: []const u8,
    access_token: []const u8,
    refresh_token: []const u8,
    expires_at: i64, // Unix timestamp

    pub fn isExpired(self: StoredCredentials) bool {
        const now = std.time.timestamp();
        return now >= self.expires_at;
    }

    pub fn willExpireSoon(self: StoredCredentials, leeway_seconds: i64) bool {
        const now = std.time.timestamp();
        return now + leeway_seconds >= self.expires_at;
    }
};

/// Token store configuration
pub const StoreConfig = struct {
    /// Path to credentials file
    path: []const u8 = "claude_oauth_creds.json",
    /// Agent name for credential path construction
    agent_name: ?[]const u8 = null,
    /// Use OS keychain if available (future feature)
    use_keychain: bool = false,
};

/// Secure token storage
pub const TokenStore = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: StoreConfig,

    pub fn init(allocator: std.mem.Allocator, config: StoreConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Get the full path for credential storage
    pub fn getCredentialPath(self: Self) ![]const u8 {
        if (self.config.agent_name) |agent_name| {
            // Build path: ~/.local/share/{agent_name}/auth.json
            const home = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;
            const path = try std.fmt.allocPrint(self.allocator, "{s}/.local/share/{s}/auth.json", .{ home, agent_name });
            
            // Ensure directory exists
            const dir_path = try std.fmt.allocPrint(self.allocator, "{s}/.local/share/{s}", .{ home, agent_name });
            defer self.allocator.free(dir_path);
            std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
            
            return path;
        }
        return self.allocator.dupe(u8, self.config.path);
    }

    /// Save credentials to file with mode 0600
    pub fn save(self: Self, creds: StoredCredentials) !void {
        const path = try self.getCredentialPath();
        defer self.allocator.free(path);

        // Serialize to JSON (Zig 0.15)
        const json_str = try std.fmt.allocPrint(self.allocator, "{f}", .{json.fmt(creds, .{ .whitespace = .indent_2 })});
        defer self.allocator.free(json_str);

        // Write atomically with temp file
        const temp_path = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{path});
        defer self.allocator.free(temp_path);

        // Create temp file with restricted permissions
        const file = try fs.cwd().createFile(temp_path, .{
            .mode = if (builtin.os.tag == .windows) 0o666 else 0o600,
        });
        defer file.close();

        try file.writeAll(json_str);
        try file.sync();

        // Atomic rename
        try fs.cwd().rename(temp_path, path);

        log.info("Credentials saved to {s} with mode 0600", .{path});
    }

    /// Load credentials from file
    pub fn load(self: Self) !StoredCredentials {
        const path = try self.getCredentialPath();
        defer self.allocator.free(path);

        const file = try fs.cwd().openFile(path, .{});
        defer file.close();

        // Check file permissions
        const stat = try file.stat();
        if (builtin.os.tag != .windows) {
            const mode = stat.mode & 0o777;
            if (mode != 0o600) {
                log.warn("Credentials file has mode {o}, expected 0600", .{mode});
                // Fix permissions
                try std.posix.fchmod(file.handle, 0o600);
            }
        }

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        const parsed = try json.parseFromSlice(StoredCredentials, self.allocator, content, .{});
        defer parsed.deinit();

        // Duplicate strings for caller ownership
        return StoredCredentials{
            .type = try self.allocator.dupe(u8, parsed.value.type),
            .access_token = try self.allocator.dupe(u8, parsed.value.access_token),
            .refresh_token = try self.allocator.dupe(u8, parsed.value.refresh_token),
            .expires_at = parsed.value.expires_at,
        };
    }

    /// Check if credentials exist
    pub fn exists(self: Self) bool {
        const path = self.getCredentialPath() catch return false;
        defer self.allocator.free(path);
        
        fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Remove credentials file
    pub fn remove(self: Self) !void {
        const path = try self.getCredentialPath();
        defer self.allocator.free(path);
        
        try fs.cwd().deleteFile(path);
        log.info("Credentials removed", .{});
    }
};

test "token store save and load" {
    const allocator = std.testing.allocator;

    const test_path = "test_oauth_creds.json";
    defer fs.cwd().deleteFile(test_path) catch {};

    const store = TokenStore.init(allocator, .{ .path = test_path });

    const creds = StoredCredentials{
        .type = "oauth",
        .access_token = "test_access_token",
        .refresh_token = "test_refresh_token",
        .expires_at = std.time.timestamp() + 3600,
    };

    try store.save(creds);
    try std.testing.expect(store.exists());

    const loaded = try store.load();
    defer allocator.free(loaded.type);
    defer allocator.free(loaded.access_token);
    defer allocator.free(loaded.refresh_token);

    try std.testing.expectEqualStrings("oauth", loaded.type);
    try std.testing.expectEqualStrings("test_access_token", loaded.access_token);
    try std.testing.expectEqualStrings("test_refresh_token", loaded.refresh_token);
    try std.testing.expect(!loaded.isExpired());

    // Check file permissions (Unix only)
    if (builtin.os.tag != .windows) {
        const file = try fs.cwd().openFile(test_path, .{});
        defer file.close();
        const stat = try file.stat();
        const mode = stat.mode & 0o777;
        try std.testing.expectEqual(@as(u32, 0o600), mode);
    }
}

test "token expiration" {
    const past = StoredCredentials{
        .type = "oauth",
        .access_token = "token",
        .refresh_token = "refresh",
        .expires_at = std.time.timestamp() - 100,
    };
    try std.testing.expect(past.isExpired());

    const future = StoredCredentials{
        .type = "oauth",
        .access_token = "token",
        .refresh_token = "refresh",
        .expires_at = std.time.timestamp() + 3600,
    };
    try std.testing.expect(!future.isExpired());
    try std.testing.expect(!future.willExpireSoon(60));
    try std.testing.expect(future.willExpireSoon(3700));
}
