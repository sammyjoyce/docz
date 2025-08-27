//! Comprehensive session state management for all agent types.
//! Provides advanced session persistence, state management, security, and collaboration features.

const std = @import("std");
const Allocator = std.mem.Allocator;
const crypto = std.crypto;
const json = std.json;
const fs = std.fs;
const time = std.time;
const mem = std.mem;
const fmt = std.fmt;

/// Session management errors
pub const SessionError = error{
    SessionNotFound,
    SessionCorrupted,
    SessionLocked,
    SessionExpired,
    InvalidSessionType,
    StateVersionMismatch,
    EncryptionFailed,
    DecryptionFailed,
    AccessDenied,
    StorageFull,
    CompressionFailed,
    DecompressionFailed,
    TransactionFailed,
    CheckpointFailed,
    RecoveryFailed,
    AuditLogFailed,
};

/// Session types with different capabilities and persistence levels
pub const SessionType = enum {
    /// Full interactive session with complete state persistence
    interactive,
    /// Batch processing session with limited state
    batch,
    /// Temporary session without persistence
    temporary,
    /// Shared session with collaboration support
    shared,
    /// Read-only session for review and analysis
    read_only,
};

/// Session state hierarchy levels
pub const StateLevel = enum {
    global, // Global agent state
    session, // Session-specific state
    context, // Current context state
    command, // Command execution state
    tool, // Tool execution state
};

/// Session configuration with comprehensive options
pub const SessionConfig = struct {
    /// Session type
    session_type: SessionType = .interactive,
    /// Enable persistence
    enable_persistence: bool = true,
    /// Enable encryption
    enable_encryption: bool = false,
    /// Enable compression
    enable_compression: bool = true,
    /// Enable checkpoints
    enable_checkpoints: bool = true,
    /// Checkpoint interval in seconds
    checkpoint_interval: u32 = 300,
    /// Maximum session duration in seconds
    max_duration: u32 = 3600,
    /// Maximum state size in bytes
    max_state_size: u64 = 10 * 1024 * 1024, // 10MB
    /// Enable audit logging
    enable_audit: bool = true,
    /// Enable collaboration features
    enable_collaboration: bool = false,
    /// Session title
    title: []const u8 = "AI Agent Session",
    /// Session description
    description: []const u8 = "",
    /// Owner/creator identifier
    owner: []const u8 = "",
    /// Access control list
    acl: std.ArrayList(ACLEntry) = undefined,
    /// Custom metadata
    metadata: std.StringHashMap([]const u8) = undefined,

    /// Initialize session config
    pub fn init(allocator: Allocator) SessionConfig {
        return SessionConfig{
            .acl = std.ArrayList(ACLEntry).init(allocator),
            .metadata = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Deinitialize session config
    pub fn deinit(self: *SessionConfig) void {
        self.acl.deinit();
        var it = self.metadata.iterator();
        while (it.next()) |entry| {
            self.metadata.allocator.free(entry.key_ptr.*);
            self.metadata.allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }
};

/// Access Control List entry
pub const ACLEntry = struct {
    user_id: []const u8,
    permissions: []const Permission,
    granted_by: []const u8,
    granted_at: i64,
    expires_at: ?i64 = null,

    pub const Permission = enum {
        read,
        write,
        delete,
        share,
        admin,
    };
};

/// Session state with hierarchical organization
pub const SessionState = struct {
    allocator: Allocator,
    /// State version for migration support
    version: u32 = 1,
    /// Global state data
    global: std.StringHashMap(json.Value),
    /// Session-level state
    session: std.StringHashMap(json.Value),
    /// Context state
    context: std.StringHashMap(json.Value),
    /// Command execution state
    command: std.StringHashMap(json.Value),
    /// Tool execution state
    tool: std.StringHashMap(json.Value),
    /// State snapshots for undo/redo
    snapshots: std.ArrayList(StateSnapshot),
    /// Current snapshot index
    current_snapshot: usize = 0,
    /// State variables
    variables: std.StringHashMap([]const u8),
    /// State metadata
    metadata: std.StringHashMap([]const u8),

    /// Initialize session state
    pub fn init(allocator: Allocator) !SessionState {
        return SessionState{
            .allocator = allocator,
            .global = std.StringHashMap(json.Value).init(allocator),
            .session = std.StringHashMap(json.Value).init(allocator),
            .context = std.StringHashMap(json.Value).init(allocator),
            .command = std.StringHashMap(json.Value).init(allocator),
            .tool = std.StringHashMap(json.Value).init(allocator),
            .snapshots = std.ArrayList(StateSnapshot).init(allocator),
            .variables = std.StringHashMap([]const u8).init(allocator),
            .metadata = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Deinitialize session state
    pub fn deinit(self: *SessionState) void {
        self.deinitHashMap(&self.global);
        self.deinitHashMap(&self.session);
        self.deinitHashMap(&self.context);
        self.deinitHashMap(&self.command);
        self.deinitHashMap(&self.tool);

        for (self.snapshots.items) |*snapshot| {
            snapshot.deinit();
        }
        self.snapshots.deinit();

        var var_it = self.variables.iterator();
        while (var_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.variables.deinit();

        var meta_it = self.metadata.iterator();
        while (meta_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }

    /// Helper to deinitialize hashmap with json values
    fn deinitHashMap(self: *SessionState, map: *std.StringHashMap(json.Value)) void {
        var it = map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }
        map.deinit();
    }

    /// Set state value at specific level
    pub fn set(self: *SessionState, level: StateLevel, key: []const u8, value: json.Value) !void {
        const map = switch (level) {
            .global => &self.global,
            .session => &self.session,
            .context => &self.context,
            .command => &self.command,
            .tool => &self.tool,
        };

        const key_copy = try self.allocator.dupe(u8, key);
        if (map.get(key_copy)) |old_value| {
            old_value.deinit();
        }
        try map.put(key_copy, value);
    }

    /// Get state value from specific level
    pub fn get(self: *SessionState, level: StateLevel, key: []const u8) ?json.Value {
        const map = switch (level) {
            .global => &self.global,
            .session => &self.session,
            .context => &self.context,
            .command => &self.command,
            .tool => &self.tool,
        };
        return map.get(key);
    }

    /// Create state snapshot for undo/redo
    pub fn createSnapshot(self: *SessionState, description: []const u8) !void {
        const snapshot = try StateSnapshot.create(self.allocator, self, description);
        try self.snapshots.append(snapshot);
        self.current_snapshot = self.snapshots.items.len - 1;
    }

    /// Undo to previous snapshot
    pub fn undo(self: *SessionState) !bool {
        if (self.current_snapshot == 0) return false;

        self.current_snapshot -= 1;
        const snapshot = &self.snapshots.items[self.current_snapshot];
        try snapshot.restore(self);
        return true;
    }

    /// Redo to next snapshot
    pub fn redo(self: *SessionState) !bool {
        if (self.current_snapshot >= self.snapshots.items.len - 1) return false;

        self.current_snapshot += 1;
        const snapshot = &self.snapshots.items[self.current_snapshot];
        try snapshot.restore(self);
        return true;
    }

    /// Set variable
    pub fn setVariable(self: *SessionState, name: []const u8, value: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        const value_copy = try self.allocator.dupe(u8, value);

        if (self.variables.get(name_copy)) |old_value| {
            self.allocator.free(old_value);
        }
        try self.variables.put(name_copy, value_copy);
    }

    /// Get variable
    pub fn getVariable(self: *SessionState, name: []const u8) ?[]const u8 {
        return self.variables.get(name);
    }

    /// Set metadata
    pub fn setMetadata(self: *SessionState, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);

        if (self.metadata.get(key_copy)) |old_value| {
            self.allocator.free(old_value);
        }
        try self.metadata.put(key_copy, value_copy);
    }

    /// Get metadata
    pub fn getMetadata(self: *SessionState, key: []const u8) ?[]const u8 {
        return self.metadata.get(key);
    }
};

/// State snapshot for undo/redo functionality
pub const StateSnapshot = struct {
    allocator: Allocator,
    timestamp: i64,
    description: []const u8,
    /// Serialized state data
    state_data: []const u8,

    /// Create snapshot from current state
    pub fn create(allocator: Allocator, state: *SessionState, description: []const u8) !StateSnapshot {
        const desc_copy = try allocator.dupe(u8, description);

        // Serialize current state
        const state_json = .{
            .version = state.version,
            .global = state.global,
            .session = state.session,
            .context = state.context,
            .command = state.command,
            .tool = state.tool,
            .variables = state.variables,
            .metadata = state.metadata,
        };

        const serialized = try json.stringifyAlloc(allocator, state_json, .{ .whitespace = true });

        return StateSnapshot{
            .allocator = allocator,
            .timestamp = time.timestamp(),
            .description = desc_copy,
            .state_data = serialized,
        };
    }

    /// Deinitialize snapshot
    pub fn deinit(self: *StateSnapshot) void {
        self.allocator.free(self.description);
        self.allocator.free(self.state_data);
    }

    /// Restore state from snapshot
    pub fn restore(self: *StateSnapshot, state: *SessionState) !void {
        // Parse serialized state
        const parsed = try json.parseFromSlice(json.Value, self.allocator, self.state_data, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Clear current state
        state.deinitHashMap(&state.global);
        state.deinitHashMap(&state.session);
        state.deinitHashMap(&state.context);
        state.deinitHashMap(&state.command);
        state.deinitHashMap(&state.tool);

        // Reinitialize hashmaps
        state.global = std.StringHashMap(json.Value).init(state.allocator);
        state.session = std.StringHashMap(json.Value).init(state.allocator);
        state.context = std.StringHashMap(json.Value).init(state.allocator);
        state.command = std.StringHashMap(json.Value).init(state.allocator);
        state.tool = std.StringHashMap(json.Value).init(state.allocator);

        // Restore from snapshot
        if (root.get("version")) |version| {
            state.version = @intCast(version.integer);
        }

        try self.restoreHashMap(&state.global, root.get("global"));
        try self.restoreHashMap(&state.session, root.get("session"));
        try self.restoreHashMap(&state.context, root.get("context"));
        try self.restoreHashMap(&state.command, root.get("command"));
        try self.restoreHashMap(&state.tool, root.get("tool"));

        // Restore variables
        if (root.get("variables")) |vars| {
            var var_it = vars.object.iterator();
            while (var_it.next()) |entry| {
                const key = try state.allocator.dupe(u8, entry.key_ptr.*);
                const value = try state.allocator.dupe(u8, entry.value_ptr.*.string);
                try state.variables.put(key, value);
            }
        }

        // Restore metadata
        if (root.get("metadata")) |meta| {
            var meta_it = meta.object.iterator();
            while (meta_it.next()) |entry| {
                const key = try state.allocator.dupe(u8, entry.key_ptr.*);
                const value = try state.allocator.dupe(u8, entry.value_ptr.*.string);
                try state.metadata.put(key, value);
            }
        }
    }

    /// Helper to restore hashmap from JSON
    fn restoreHashMap(self: *StateSnapshot, map: *std.StringHashMap(json.Value), json_map: ?json.Value) !void {
        if (json_map) |jm| {
            var it = jm.object.iterator();
            while (it.next()) |entry| {
                const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                // Deep clone the JSON value
                const value = try self.deepCloneJsonValue(self.allocator, entry.value_ptr.*);
                try map.put(key, value);
            }
        }
    }

    /// Deep clone JSON value
    fn deepCloneJsonValue(self: *StateSnapshot, allocator: Allocator, value: json.Value) !json.Value {
        return switch (value) {
            .null => json.Value{ .null = {} },
            .bool => |b| json.Value{ .bool = b },
            .integer => |i| json.Value{ .integer = i },
            .float => |f| json.Value{ .float = f },
            .number_string => |s| json.Value{ .number_string = try allocator.dupe(u8, s) },
            .string => |s| json.Value{ .string = try allocator.dupe(u8, s) },
            .array => |arr| blk: {
                var new_arr = std.ArrayList(json.Value).init(allocator);
                for (arr.items) |item| {
                    const cloned = try self.deepCloneJsonValue(allocator, item);
                    try new_arr.append(cloned);
                }
                break :blk json.Value{ .array = new_arr };
            },
            .object => |obj| blk: {
                var new_obj = std.StringHashMap(json.Value).init(allocator);
                var it = obj.iterator();
                while (it.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    const cloned = try self.deepCloneJsonValue(allocator, entry.value_ptr.*);
                    try new_obj.put(key, cloned);
                }
                break :blk json.Value{ .object = new_obj };
            },
        };
    }
};

/// Session data structure with enhanced features
pub const SessionData = struct {
    allocator: Allocator,
    /// Unique session identifier
    session_id: []const u8,
    /// Session configuration
    config: SessionConfig,
    /// Session state
    state: SessionState,
    /// Start time
    start_time: i64,
    /// Last activity time
    last_activity: i64,
    /// End time (if session ended)
    end_time: ?i64 = null,
    /// Session is active
    is_active: bool = true,
    /// Conversation history
    conversation_history: std.ArrayList(ConversationEntry),
    /// Command history with search
    command_history: std.ArrayList(CommandEntry),
    /// Session statistics
    stats: SessionStats,
    /// Performance metrics
    performance: PerformanceMetrics,
    /// Encryption key (if encrypted)
    encryption_key: ?[32]u8 = null,
    /// Session lock status
    is_locked: bool = false,
    /// Lock owner
    lock_owner: ?[]const u8 = null,
    /// Collaborators (for shared sessions)
    collaborators: std.ArrayList(Collaborator),
    /// Audit log
    audit_log: std.ArrayList(AuditEntry),

    /// Initialize session data
    pub fn init(allocator: Allocator, session_id: []const u8, config: SessionConfig) !SessionData {
        const id_copy = try allocator.dupe(u8, session_id);
        var session_config = config;
        // Deep copy config to avoid ownership issues
        session_config.acl = try allocator.alloc(ACLEntry, config.acl.items.len);
        for (config.acl.items, 0..) |entry, i| {
            session_config.acl.items[i] = .{
                .user_id = try allocator.dupe(u8, entry.user_id),
                .permissions = try allocator.dupe(ACLEntry.Permission, entry.permissions),
                .granted_by = try allocator.dupe(u8, entry.granted_by),
                .granted_at = entry.granted_at,
                .expires_at = entry.expires_at,
            };
        }

        var metadata_copy = std.StringHashMap([]const u8).init(allocator);
        var it = config.metadata.iterator();
        while (it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const value = try allocator.dupe(u8, entry.value_ptr.*);
            try metadata_copy.put(key, value);
        }
        session_config.metadata = metadata_copy;

        const now = time.timestamp();

        return SessionData{
            .allocator = allocator,
            .session_id = id_copy,
            .config = session_config,
            .state = try SessionState.init(allocator),
            .start_time = now,
            .last_activity = now,
            .conversation_history = std.ArrayList(ConversationEntry).init(allocator),
            .command_history = std.ArrayList(CommandEntry).init(allocator),
            .stats = SessionStats{},
            .performance = PerformanceMetrics{},
            .collaborators = std.ArrayList(Collaborator).init(allocator),
            .audit_log = std.ArrayList(AuditEntry).init(allocator),
        };
    }

    /// Deinitialize session data
    pub fn deinit(self: *SessionData) void {
        self.allocator.free(self.session_id);
        self.config.deinit();
        self.state.deinit();

        for (self.conversation_history.items) |*entry| {
            entry.deinit();
        }
        self.conversation_history.deinit();

        for (self.command_history.items) |*entry| {
            entry.deinit();
        }
        self.command_history.deinit();

        for (self.collaborators.items) |*collab| {
            collab.deinit();
        }
        self.collaborators.deinit();

        for (self.audit_log.items) |*entry| {
            entry.deinit();
        }
        self.audit_log.deinit();

        if (self.lock_owner) |owner| {
            self.allocator.free(owner);
        }
    }

    /// Add conversation entry
    pub fn addConversationEntry(self: *SessionData, role: anytype, content: []const u8, metadata: ?json.Value) !void {
        const entry = ConversationEntry{
            .timestamp = time.timestamp(),
            .role = role,
            .content = try self.allocator.dupe(u8, content),
            .metadata = metadata,
        };
        try self.conversation_history.append(entry);
        self.stats.messages_processed += 1;
        self.last_activity = time.timestamp();

        // Audit log
        if (self.config.enable_audit) {
            try self.addAuditEntry(.conversation_added, "Conversation entry added", null);
        }
    }

    /// Add command entry to history
    pub fn addCommandEntry(self: *SessionData, command: []const u8, args: ?[]const u8, result: ?[]const u8, success: bool) !void {
        const entry = CommandEntry{
            .timestamp = time.timestamp(),
            .command = try self.allocator.dupe(u8, command),
            .args = if (args) |a| try self.allocator.dupe(u8, a) else null,
            .result = if (result) |r| try self.allocator.dupe(u8, r) else null,
            .success = success,
        };
        try self.command_history.append(entry);
        self.stats.commands_executed += 1;
        self.last_activity = time.timestamp();

        // Audit log
        if (self.config.enable_audit) {
            const details = try fmt.allocPrint(self.allocator, "Command: {s}, Success: {}", .{ command, success });
            defer self.allocator.free(details);
            try self.addAuditEntry(.command_executed, details, null);
        }
    }

    /// Search command history
    pub fn searchCommandHistory(self: *SessionData, query: []const u8) ![]const CommandEntry {
        var results = std.ArrayList(CommandEntry).init(self.allocator);
        defer results.deinit();

        for (self.command_history.items) |entry| {
            if (mem.indexOf(u8, entry.command, query) != null) {
                try results.append(entry);
            } else if (entry.args) |args| {
                if (mem.indexOf(u8, args, query) != null) {
                    try results.append(entry);
                }
            }
        }

        return results.toOwnedSlice();
    }

    /// Add collaborator (for shared sessions)
    pub fn addCollaborator(self: *SessionData, user_id: []const u8, permissions: []const ACLEntry.Permission) !void {
        if (self.config.session_type != .shared) {
            return SessionError.InvalidSessionType;
        }

        const collab = Collaborator{
            .user_id = try self.allocator.dupe(u8, user_id),
            .permissions = try self.allocator.dupe(ACLEntry.Permission, permissions),
            .joined_at = time.timestamp(),
        };
        try self.collaborators.append(collab);

        // Audit log
        if (self.config.enable_audit) {
            const details = try fmt.allocPrint(self.allocator, "Collaborator added: {s}", .{user_id});
            defer self.allocator.free(details);
            try self.addAuditEntry(.collaborator_added, details, user_id);
        }
    }

    /// Remove collaborator
    pub fn removeCollaborator(self: *SessionData, user_id: []const u8) !void {
        for (self.collaborators.items, 0..) |collab, i| {
            if (mem.eql(u8, collab.user_id, user_id)) {
                var collab_to_remove = self.collaborators.orderedRemove(i);
                collab_to_remove.deinit();
                break;
            }
        }

        // Audit log
        if (self.config.enable_audit) {
            const details = try fmt.allocPrint(self.allocator, "Collaborator removed: {s}", .{user_id});
            defer self.allocator.free(details);
            try self.addAuditEntry(.collaborator_removed, details, user_id);
        }
    }

    /// Lock session
    pub fn lock(self: *SessionData, owner: []const u8) !void {
        if (self.is_locked) {
            return SessionError.SessionLocked;
        }

        self.is_locked = true;
        self.lock_owner = try self.allocator.dupe(u8, owner);

        // Audit log
        if (self.config.enable_audit) {
            const details = try fmt.allocPrint(self.allocator, "Session locked by: {s}", .{owner});
            defer self.allocator.free(details);
            try self.addAuditEntry(.session_locked, details, owner);
        }
    }

    /// Unlock session
    pub fn unlock(self: *SessionData, owner: []const u8) !void {
        if (!self.is_locked) return;
        if (self.lock_owner) |lock_owner| {
            if (!mem.eql(u8, lock_owner, owner)) {
                return SessionError.AccessDenied;
            }
        }

        self.is_locked = false;
        self.allocator.free(self.lock_owner.?);
        self.lock_owner = null;

        // Audit log
        if (self.config.enable_audit) {
            const details = try fmt.allocPrint(self.allocator, "Session unlocked by: {s}", .{owner});
            defer self.allocator.free(details);
            try self.addAuditEntry(.session_unlocked, details, owner);
        }
    }

    /// Check if user has permission
    pub fn hasPermission(self: *SessionData, user_id: []const u8, permission: ACLEntry.Permission) bool {
        // Owner always has all permissions
        if (mem.eql(u8, self.config.owner, user_id)) {
            return true;
        }

        // Check ACL
        for (self.config.acl.items) |entry| {
            if (mem.eql(u8, entry.user_id, user_id)) {
                // Check if permission is granted and not expired
                for (entry.permissions) |p| {
                    if (p == permission) {
                        if (entry.expires_at) |expires| {
                            if (time.timestamp() > expires) {
                                return false; // Permission expired
                            }
                        }
                        return true;
                    }
                }
            }
        }

        // Check collaborator permissions for shared sessions
        if (self.config.session_type == .shared) {
            for (self.collaborators.items) |collab| {
                if (mem.eql(u8, collab.user_id, user_id)) {
                    for (collab.permissions) |p| {
                        if (p == permission) {
                            return true;
                        }
                    }
                }
            }
        }

        return false;
    }

    /// Add audit entry
    pub fn addAuditEntry(self: *SessionData, event_type: AuditEventType, details: []const u8, user_id: ?[]const u8) !void {
        const entry = AuditEntry{
            .timestamp = time.timestamp(),
            .event_type = event_type,
            .user_id = if (user_id) |uid| try self.allocator.dupe(u8, uid) else null,
            .details = try self.allocator.dupe(u8, details),
            .ip_address = null, // Would be populated in real implementation
            .user_agent = null, // Would be populated in real implementation
        };
        try self.audit_log.append(entry);
    }

    /// Get session duration in seconds
    pub fn getDuration(self: *SessionData) i64 {
        const end_time = self.end_time orelse time.timestamp();
        return end_time - self.start_time;
    }

    /// Check if session is expired
    pub fn isExpired(self: *SessionData) bool {
        const duration = self.getDuration();
        return @as(u64, @intCast(duration)) > self.config.max_duration;
    }

    /// End session
    pub fn endSession(self: *SessionData) void {
        self.is_active = false;
        self.end_time = time.timestamp();
        self.last_activity = self.end_time.?;

        // Audit log
        if (self.config.enable_audit) {
            self.addAuditEntry(.session_ended, "Session ended", null) catch {};
        }
    }

    /// Update performance metrics
    pub fn updatePerformanceMetrics(self: *SessionData) void {
        self.performance.update();
    }
};

/// Conversation entry for session history
pub const ConversationEntry = struct {
    timestamp: i64,
    role: enum { user, assistant, system, tool },
    content: []const u8,
    metadata: ?json.Value = null,

    /// Deinitialize conversation entry
    pub fn deinit(self: *ConversationEntry, allocator: Allocator) void {
        allocator.free(self.content);
        if (self.metadata) |meta| {
            meta.deinit();
        }
    }
};

/// Command entry for command history
pub const CommandEntry = struct {
    timestamp: i64,
    command: []const u8,
    args: ?[]const u8 = null,
    result: ?[]const u8 = null,
    success: bool,

    /// Deinitialize command entry
    pub fn deinit(self: *CommandEntry, allocator: Allocator) void {
        allocator.free(self.command);
        if (self.args) |args| {
            allocator.free(args);
        }
        if (self.result) |result| {
            allocator.free(result);
        }
    }
};

/// Collaborator information for shared sessions
pub const Collaborator = struct {
    user_id: []const u8,
    permissions: []const ACLEntry.Permission,
    joined_at: i64,

    /// Deinitialize collaborator
    pub fn deinit(self: *Collaborator, allocator: Allocator) void {
        allocator.free(self.user_id);
        allocator.free(self.permissions);
    }
};

/// Audit event types
pub const AuditEventType = enum {
    session_created,
    session_loaded,
    session_saved,
    session_ended,
    session_locked,
    session_unlocked,
    conversation_added,
    command_executed,
    state_modified,
    collaborator_added,
    collaborator_removed,
    permission_granted,
    permission_revoked,
    security_violation,
};

/// Audit log entry
pub const AuditEntry = struct {
    timestamp: i64,
    event_type: AuditEventType,
    user_id: ?[]const u8 = null,
    details: []const u8,
    ip_address: ?[]const u8 = null,
    user_agent: ?[]const u8 = null,

    /// Deinitialize audit entry
    pub fn deinit(self: *AuditEntry, allocator: Allocator) void {
        if (self.user_id) |uid| {
            allocator.free(uid);
        }
        allocator.free(self.details);
        if (self.ip_address) |ip| {
            allocator.free(ip);
        }
        if (self.user_agent) |ua| {
            allocator.free(ua);
        }
    }
};

/// Session statistics with enhanced metrics
pub const SessionStats = struct {
    /// Total messages processed
    messages_processed: u64 = 0,
    /// Total commands executed
    commands_executed: u64 = 0,
    /// Total tools executed
    tools_executed: u64 = 0,
    /// Total tokens used
    total_tokens: u64 = 0,
    /// Input tokens
    input_tokens: u64 = 0,
    /// Output tokens
    output_tokens: u64 = 0,
    /// Authentication attempts
    auth_attempts: u64 = 0,
    /// Authentication failures
    auth_failures: u64 = 0,
    /// State snapshots created
    snapshots_created: u64 = 0,
    /// Undo operations performed
    undo_operations: u64 = 0,
    /// Redo operations performed
    redo_operations: u64 = 0,
    /// Checkpoints created
    checkpoints_created: u64 = 0,
    /// Recovery operations performed
    recovery_operations: u64 = 0,
    /// Last activity timestamp
    last_activity: i64 = 0,
    /// Average response time in nanoseconds
    average_response_time: i64 = 0,
    /// Last response time
    last_response_time: i64 = 0,
    /// Error count
    error_count: u64 = 0,
    /// Average session duration
    average_session_duration: f64 = 0,

    /// Update statistics with new session data
    pub fn updateWithSession(self: *SessionStats, session: *SessionData) void {
        self.messages_processed = session.conversation_history.items.len;
        self.commands_executed = session.command_history.items.len;
        self.last_activity = session.last_activity;
    }

    /// Record response time
    pub fn recordResponseTime(self: *SessionStats, response_time_ns: i64) void {
        self.last_response_time = response_time_ns;
        // Update rolling average
        if (self.average_response_time == 0) {
            self.average_response_time = response_time_ns;
        } else {
            self.average_response_time = (self.average_response_time + response_time_ns) / 2;
        }
    }

    /// Record token usage
    pub fn recordTokenUsage(self: *SessionStats, input_tokens: u64, output_tokens: u64) void {
        self.input_tokens += input_tokens;
        self.output_tokens += output_tokens;
        self.total_tokens += input_tokens + output_tokens;
    }

    /// Record authentication attempt
    pub fn recordAuthAttempt(self: *SessionStats, success: bool) void {
        self.auth_attempts += 1;
        if (!success) {
            self.auth_failures += 1;
        }
    }

    /// Record error
    pub fn recordError(self: *SessionStats) void {
        self.error_count += 1;
    }

    /// Get success rate as percentage
    pub fn getAuthSuccessRate(self: *SessionStats) f64 {
        if (self.auth_attempts == 0) return 100.0;
        const success_count = self.auth_attempts - self.auth_failures;
        return @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(self.auth_attempts)) * 100.0;
    }
};

/// Performance metrics for monitoring agent performance
pub const PerformanceMetrics = struct {
    render_time_ms: f64 = 0,
    response_time_ms: f64 = 0,
    memory_usage_mb: f64 = 0,
    cpu_usage_percent: f64 = 0,
    cache_hit_rate: f64 = 0,
    last_updated: i64 = 0,

    /// Update metrics with current values
    pub fn update(self: *PerformanceMetrics) void {
        self.last_updated = time.timestamp();
        // In a real implementation, these would be measured from system
        // For now, we'll set some placeholder values
        self.memory_usage_mb = 50.0; // Placeholder
        self.cpu_usage_percent = 15.0; // Placeholder
        self.cache_hit_rate = 85.0; // Placeholder
    }

    /// Record render time
    pub fn recordRenderTime(self: *PerformanceMetrics, render_time_ms: f64) void {
        self.render_time_ms = render_time_ms;
        self.update();
    }

    /// Record response time
    pub fn recordResponseTime(self: *PerformanceMetrics, response_time_ms: f64) void {
        self.response_time_ms = response_time_ms;
        self.update();
    }

    /// Get formatted metrics summary
    pub fn getSummary(self: *PerformanceMetrics, allocator: Allocator) ![]const u8 {
        return try fmt.allocPrint(allocator,
            \\Performance Metrics:
            \\  Render Time: {d:.2}ms
            \\  Response Time: {d:.2}ms
            \\  Memory Usage: {d:.1}MB
            \\  CPU Usage: {d:.1}%
            \\  Cache Hit Rate: {d:.1}%
        , .{
            self.render_time_ms,
            self.response_time_ms,
            self.memory_usage_mb,
            self.cpu_usage_percent,
            self.cache_hit_rate,
        });
    }
};

/// Session manager for persistence and lifecycle management
pub const SessionManager = struct {
    allocator: Allocator,
    sessions_dir: []const u8,
    checkpoints_dir: []const u8,
    history_dir: []const u8,
    active_sessions: std.StringHashMap(*SessionData),
    stats: SessionStats,
    /// Encryption key for session encryption
    master_key: ?[32]u8 = null,
    /// Compression enabled
    compression_enabled: bool = true,

    /// Initialize session manager
    pub fn init(allocator: Allocator, sessions_dir: []const u8, enable_encryption: bool) !*SessionManager {
        const manager = try allocator.create(SessionManager);
        manager.* = SessionManager{
            .allocator = allocator,
            .sessions_dir = try allocator.dupe(u8, sessions_dir),
            .checkpoints_dir = try fmt.allocPrint(allocator, "{s}/checkpoints", .{sessions_dir}),
            .history_dir = try fmt.allocPrint(allocator, "{s}/history", .{sessions_dir}),
            .active_sessions = std.StringHashMap(*SessionData).init(allocator),
            .stats = SessionStats{},
            .compression_enabled = true,
        };

        // Generate master key if encryption is enabled
        if (enable_encryption) {
            crypto.random.bytes(&manager.master_key.?);
        }

        // Create directories
        try fs.cwd().makePath(sessions_dir);
        try fs.cwd().makePath(manager.checkpoints_dir);
        try fs.cwd().makePath(manager.history_dir);

        return manager;
    }

    /// Deinitialize session manager
    pub fn deinit(self: *SessionManager) void {
        self.allocator.free(self.sessions_dir);
        self.allocator.free(self.checkpoints_dir);
        self.allocator.free(self.history_dir);

        var it = self.active_sessions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.active_sessions.deinit();
    }

    /// Create a new session
    pub fn createSession(self: *SessionManager, session_id: []const u8, config: SessionConfig) !*SessionData {
        const session = try self.allocator.create(SessionData);
        session.* = try SessionData.init(self.allocator, session_id, config);

        const key = try self.allocator.dupe(u8, session_id);
        try self.active_sessions.put(key, session);

        self.stats.updateWithSession(session);

        // Audit log
        if (config.enable_audit) {
            try session.addAuditEntry(.session_created, "Session created", config.owner);
        }

        return session;
    }

    /// Get existing session
    pub fn getSession(self: *SessionManager, session_id: []const u8) ?*SessionData {
        return self.active_sessions.get(session_id);
    }

    /// Save session to disk
    pub fn saveSession(self: *SessionManager, session: *SessionData) !void {
        if (!session.config.enable_persistence) return;

        const filename = try fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.sessions_dir, session.session_id });
        defer self.allocator.free(filename);

        // Create basic session JSON
        const session_json = json.Value{
            .object = .{
                .session_id = json.Value{ .string = session.session_id },
                .start_time = json.Value{ .integer = session.start_time },
                .last_activity = json.Value{ .integer = session.last_activity },
                .is_active = json.Value{ .bool = session.is_active },
            },
        };

        // Serialize to string
        const serialized = try json.stringifyAlloc(self.allocator, session_json, .{ .whitespace = true });
        defer self.allocator.free(serialized);

        // Encrypt if needed
        var encrypted_data = serialized;
        if (self.master_key) |key| {
            encrypted_data = try self.encryptData(serialized, key);
        }
        defer if (encrypted_data.ptr != serialized.ptr) self.allocator.free(encrypted_data);

        // Compress if needed
        var compressed_data = encrypted_data;
        if (self.compression_enabled) {
            compressed_data = try self.compressData(encrypted_data);
        }
        defer if (compressed_data.ptr != encrypted_data.ptr) self.allocator.free(compressed_data);

        // Write to file
        const file = try fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(compressed_data);

        // Audit log
        if (session.config.enable_audit) {
            try session.addAuditEntry(.session_saved, "Session saved to disk", session.config.owner);
        }
    }

    /// Create checkpoint
    pub fn createCheckpoint(self: *SessionManager, session: *SessionData, description: []const u8) !void {
        if (!session.config.enable_checkpoints) return;

        const timestamp = time.timestamp();
        const checkpoint_id = try fmt.allocPrint(self.allocator, "{s}_{x}", .{ session.session_id, timestamp });
        defer self.allocator.free(checkpoint_id);

        const filename = try fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.checkpoints_dir, checkpoint_id });
        defer self.allocator.free(filename);

        // Create basic checkpoint data
        const checkpoint_data = json.Value{
            .object = .{
                .session_id = json.Value{ .string = session.session_id },
                .checkpoint_id = json.Value{ .string = checkpoint_id },
                .timestamp = json.Value{ .integer = timestamp },
                .description = json.Value{ .string = description },
            },
        };

        const serialized = try json.stringifyAlloc(self.allocator, checkpoint_data, .{ .whitespace = true });
        defer self.allocator.free(serialized);

        const file = try fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(serialized);

        session.stats.checkpoints_created += 1;

        // Audit log
        if (session.config.enable_audit) {
            const details = try fmt.allocPrint(self.allocator, "Checkpoint created: {s}", .{description});
            defer self.allocator.free(details);
            try session.addAuditEntry(.state_modified, details, session.config.owner);
        }
    }

    /// End a session
    pub fn endSession(self: *SessionManager, session_id: []const u8) !void {
        if (self.active_sessions.getEntry(session_id)) |entry| {
            entry.value_ptr.*.endSession();

            // Save final state
            try self.saveSession(entry.value_ptr.*);

            // Create final checkpoint if enabled
            if (entry.value_ptr.*.config.enable_checkpoints) {
                try self.createCheckpoint(entry.value_ptr.*, "Session ended");
            }
        }
    }

    /// Get session statistics
    pub fn getStats(self: *SessionManager) SessionStats {
        return self.stats;
    }

    /// Clean up old sessions and checkpoints
    pub fn cleanupOldSessions(self: *SessionManager, max_age_days: u32) !void {
        const cutoff_time = time.timestamp() - (@as(i64, max_age_days) * 24 * 60 * 60);

        // Clean sessions
        try self.cleanupDirectory(self.sessions_dir, cutoff_time);
        // Clean checkpoints
        try self.cleanupDirectory(self.checkpoints_dir, cutoff_time);
        // Clean history
        try self.cleanupDirectory(self.history_dir, cutoff_time);
    }

    /// List available sessions
    pub fn listSessions(self: *SessionManager) ![]const []const u8 {
        var sessions = std.ArrayList([]const u8).init(self.allocator);
        defer sessions.deinit();

        var dir = try fs.cwd().openDir(self.sessions_dir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and mem.endsWith(u8, entry.name, ".json")) {
                // Remove .json extension
                const name_len = mem.indexOf(u8, entry.name, ".json") orelse entry.name.len;
                const session_name = try self.allocator.dupe(u8, entry.name[0..name_len]);
                try sessions.append(session_name);
            }
        }

        return sessions.toOwnedSlice();
    }

    /// Helper functions for data processing
    fn compressData(self: *SessionManager, data: []const u8) ![]const u8 {
        // Simple RLE compression for demonstration
        // In a real implementation, you'd use a proper compression library
        var compressed = std.ArrayList(u8).init(self.allocator);
        defer compressed.deinit();

        var i: usize = 0;
        while (i < data.len) {
            var count: u8 = 1;
            const current = data[i];

            // Count consecutive identical bytes
            while (i + count < data.len and data[i + count] == current and count < 255) {
                count += 1;
            }

            try compressed.append(count);
            try compressed.append(current);
            i += count;
        }

        return compressed.toOwnedSlice();
    }

    fn decompressData(self: *SessionManager, data: []const u8) ![]const u8 {
        var decompressed = std.ArrayList(u8).init(self.allocator);
        defer decompressed.deinit();

        var i: usize = 0;
        while (i < data.len) {
            if (i + 1 >= data.len) break;
            const count = data[i];
            const value = data[i + 1];

            var j: u8 = 0;
            while (j < count) : (j += 1) {
                try decompressed.append(value);
            }
            i += 2;
        }

        return decompressed.toOwnedSlice();
    }

    fn encryptData(self: *SessionManager, data: []const u8, key: [32]u8) ![]const u8 {
        // Simple XOR encryption for demonstration
        // In a real implementation, you'd use proper encryption
        var encrypted = try self.allocator.alloc(u8, data.len);
        for (data, 0..) |byte, i| {
            encrypted[i] = byte ^ key[i % key.len];
        }
        return encrypted;
    }

    fn decryptData(self: *SessionManager, data: []const u8, key: [32]u8) ![]const u8 {
        // XOR is symmetric
        return self.encryptData(data, key);
    }

    fn createSessionJson(self: *SessionManager, session: *SessionData) !json.Value {
        return json.Value{
            .object = .{
                .session_id = json.Value{ .string = session.session_id },
                .start_time = json.Value{ .integer = session.start_time },
                .last_activity = json.Value{ .integer = session.last_activity },
                .is_active = json.Value{ .bool = session.is_active },
            },
        };
    }

    fn cleanupDirectory(self: *SessionManager, dir_path: []const u8, cutoff_time: i64) !void {
        var dir = fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and mem.endsWith(u8, entry.name, ".json")) {
                const filepath = try fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer self.allocator.free(filepath);

                const stat = try fs.cwd().statFile(filepath);
                if (stat.mtime < cutoff_time) {
                    try fs.cwd().deleteFile(filepath);
                }
            }
        }
    }
};

/// Generate a unique session ID
pub fn generateSessionId(allocator: Allocator) ![]const u8 {
    const timestamp = time.timestamp();
    const random = crypto.random.int(u32);
    return try fmt.allocPrint(allocator, "session_{x}_{x}", .{ timestamp, random });
}

/// Helper functions for session management
pub const SessionHelpers = struct {
    /// Create a basic session configuration
    pub fn createBasicConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = SessionConfig.init(allocator);
        config.title = try allocator.dupe(u8, title);
        config.owner = try allocator.dupe(u8, owner);
        config.session_type = .interactive;
        config.enable_persistence = true;
        config.enable_checkpoints = true;
        config.enable_audit = true;
        return config;
    }

    /// Create a rich session configuration with TUI support
    pub fn createRichConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createBasicConfig(allocator, title, owner);
        config.enable_collaboration = true;
        config.enable_encryption = true;
        config.enable_compression = true;
        return config;
    }

    /// Create a CLI-only session configuration
    pub fn createCliConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createBasicConfig(allocator, title, owner);
        config.enable_collaboration = false;
        config.enable_checkpoints = false;
        return config;
    }

    /// Create a shared session configuration
    pub fn createSharedConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createBasicConfig(allocator, title, owner);
        config.session_type = .shared;
        config.enable_collaboration = true;
        config.enable_encryption = true;
        return config;
    }

    /// Create a read-only session configuration
    pub fn createReadOnlyConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createBasicConfig(allocator, title, owner);
        config.session_type = .read_only;
        config.enable_persistence = false;
        config.enable_checkpoints = false;
        return config;
    }

    /// Create a temporary session configuration
    pub fn createTemporaryConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createBasicConfig(allocator, title, owner);
        config.session_type = .temporary;
        config.enable_persistence = false;
        config.enable_checkpoints = false;
        config.enable_audit = false;
        config.max_duration = 3600; // 1 hour
        return config;
    }
};
