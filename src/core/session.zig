//! Comprehensive session state management for all agent types.
//! Provides session persistence, state management, security, and collaboration features.

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
    readOnly,
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
    /// Allocator for this config
    allocator: Allocator,
    /// Session type
    sessionType: SessionType = .interactive,
    /// Enable persistence
    enablePersistence: bool = true,
    /// Enable encryption
    enableEncryption: bool = false,
    /// Enable compression
    enableCompression: bool = true,
    /// Enable checkpoints
    enableCheckpoints: bool = true,
    /// Checkpoint interval in seconds
    checkpointInterval: u32 = 300,
    /// Maximum session duration in seconds
    maxDuration: u32 = 3600,
    /// Maximum state size in bytes
    maxStateSize: u64 = 10 * 1024 * 1024, // 10MB
    /// Enable audit logging
    enableAudit: bool = true,
    /// Enable collaboration features
    enableCollaboration: bool = false,
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
    pub fn init(allocator: Allocator) anyerror!SessionConfig {
        return SessionConfig{
            .allocator = allocator,
            .acl = try std.ArrayList(ACLEntry).initCapacity(allocator, 0),
            .metadata = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Deinitialize session config
    pub fn deinit(self: *SessionConfig) void {
        self.acl.deinit(self.allocator);
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
    userId: []const u8,
    permissions: []const Permission,
    grantedBy: []const u8,
    grantedAt: i64,
    expiresAt: ?i64 = null,

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
    currentSnapshot: usize = 0,
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
            .snapshots = try std.ArrayList(StateSnapshot).initCapacity(allocator, 0),
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
        self.snapshots.deinit(self.allocator);

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
            // entry.value_ptr.*.deinit(self.allocator); // TODO: fix json.Value deinit
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
        self.currentSnapshot = self.snapshots.items.len - 1;
    }

    /// Undo to previous snapshot
    pub fn undo(self: *SessionState) !bool {
        if (self.currentSnapshot == 0) return false;

        self.currentSnapshot -= 1;
        const snapshot = &self.snapshots.items[self.currentSnapshot];
        try snapshot.restore(self);
        return true;
    }

    /// Redo to next snapshot
    pub fn redo(self: *SessionState) !bool {
        if (self.currentSnapshot >= self.snapshots.items.len - 1) return false;

        self.currentSnapshot += 1;
        const snapshot = &self.snapshots.items[self.currentSnapshot];
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
    stateData: []const u8,

    /// Create snapshot from current state
    pub fn create(allocator: Allocator, state: *SessionState, description: []const u8) !StateSnapshot {
        const descCopy = try allocator.dupe(u8, description);

        // Serialize current state
        const stateJson = .{
            .version = state.version,
            .global = state.global,
            .session = state.session,
            .context = state.context,
            .command = state.command,
            .tool = state.tool,
            .variables = state.variables,
            .metadata = state.metadata,
        };

        const serialized = try json.stringifyAlloc(allocator, stateJson, .{ .whitespace = true });

        return StateSnapshot{
            .allocator = allocator,
            .timestamp = time.timestamp(),
            .description = descCopy,
            .stateData = serialized,
        };
    }

    /// Deinitialize snapshot
    pub fn deinit(self: *StateSnapshot) void {
        self.allocator.free(self.description);
        self.allocator.free(self.stateData);
    }

    /// Restore state from snapshot
    pub fn restore(self: *StateSnapshot, state: *SessionState) !void {
        // Parse serialized state
        const parsed = try json.parseFromSlice(json.Value, self.allocator, self.stateData, .{});
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

/// Session data structure
pub const Session = struct {
    allocator: Allocator,
    /// Unique session identifier
    sessionId: []const u8,
    /// Session configuration
    config: SessionConfig,
    /// Session state
    state: SessionState,
    /// Start time
    startTime: i64,
    /// Last activity time
    lastActivity: i64,
    /// End time (if session ended)
    endTime: ?i64 = null,
    /// Session is active
    isActive: bool = true,
    /// Conversation history
    conversationHistory: std.ArrayList(ConversationEntry),
    /// Command history with search
    commandHistory: std.ArrayList(CommandEntry),
    /// Session statistics
    stats: SessionStats,
    /// Performance metrics
    performance: PerformanceMetrics,
    /// Encryption key (if encrypted)
    encryptionKey: ?[32]u8 = null,
    /// Session lock status
    isLocked: bool = false,
    /// Lock owner
    lockOwner: ?[]const u8 = null,
    /// Collaborators (for shared sessions)
    collaborators: std.ArrayList(Collaborator),
    /// Audit log
    auditLog: std.ArrayList(AuditEntry),

    /// Initialize session data
    pub fn init(allocator: Allocator, sessionId: []const u8, config: SessionConfig) !Session {
        const idCopy = try allocator.dupe(u8, sessionId);
        var sessionConfig = config;
        // Deep copy config to avoid ownership issues
        try sessionConfig.acl.resize(allocator, config.acl.items.len);
        for (config.acl.items, 0..) |entry, i| {
            sessionConfig.acl.items[i] = .{
                .userId = try allocator.dupe(u8, entry.userId),
                .permissions = try allocator.dupe(ACLEntry.Permission, entry.permissions),
                .grantedBy = try allocator.dupe(u8, entry.grantedBy),
                .grantedAt = entry.grantedAt,
                .expiresAt = entry.expiresAt,
            };
        }

        var metadataCopy = std.StringHashMap([]const u8).init(allocator);
        var it = config.metadata.iterator();
        while (it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const value = try allocator.dupe(u8, entry.value_ptr.*);
            try metadataCopy.put(key, value);
        }
        sessionConfig.metadata = metadataCopy;

        const now = time.timestamp();

        return Session{
            .allocator = allocator,
            .sessionId = idCopy,
            .config = sessionConfig,
            .state = try SessionState.init(allocator),
            .startTime = now,
            .lastActivity = now,
            .conversationHistory = try std.ArrayList(ConversationEntry).initCapacity(allocator, 0),
            .commandHistory = try std.ArrayList(CommandEntry).initCapacity(allocator, 0),
            .stats = SessionStats{},
            .performance = PerformanceMetrics{},
            .collaborators = try std.ArrayList(Collaborator).initCapacity(allocator, 0),
            .auditLog = try std.ArrayList(AuditEntry).initCapacity(allocator, 0),
        };
    }

    /// Deinitialize session data
    pub fn deinit(self: *Session) void {
        self.allocator.free(self.sessionId);
        self.config.deinit();
        self.state.deinit();

        for (self.conversationHistory.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.conversationHistory.deinit(self.allocator);

        for (self.commandHistory.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.commandHistory.deinit(self.allocator);

        for (self.collaborators.items) |*collab| {
            collab.deinit(self.allocator);
        }
        self.collaborators.deinit(self.allocator);

        for (self.auditLog.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.auditLog.deinit(self.allocator);

        if (self.lockOwner) |owner| {
            self.allocator.free(owner);
        }
    }

    /// Add conversation entry
    pub fn addConversationEntry(self: *Session, role: anytype, content: []const u8, metadata: ?json.Value) !void {
        const entry = ConversationEntry{
            .timestamp = time.timestamp(),
            .role = role,
            .content = try self.allocator.dupe(u8, content),
            .metadata = metadata,
        };
        try self.conversationHistory.append(entry);
        self.stats.messagesProcessed += 1;
        self.lastActivity = time.timestamp();

        // Audit log
        if (self.config.enableAudit) {
            try self.addAuditEntry(.conversationAdded, "Conversation entry added", null);
        }
    }

    /// Add command entry to history
    pub fn addCommandEntry(self: *Session, command: []const u8, args: ?[]const u8, result: ?[]const u8, success: bool) !void {
        const entry = CommandEntry{
            .timestamp = time.timestamp(),
            .command = try self.allocator.dupe(u8, command),
            .args = if (args) |a| try self.allocator.dupe(u8, a) else null,
            .result = if (result) |r| try self.allocator.dupe(u8, r) else null,
            .success = success,
        };
        try self.commandHistory.append(entry);
        self.stats.commandsExecuted += 1;
        self.lastActivity = time.timestamp();

        // Audit log
        if (self.config.enableAudit) {
            const details = try fmt.allocPrint(self.allocator, "Command: {s}, Success: {}", .{ command, success });
            defer self.allocator.free(details);
            try self.addAuditEntry(.commandExecuted, details, null);
        }
    }

    /// Search command history
    pub fn searchCommandHistory(self: *Session, query: []const u8) ![]const CommandEntry {
        var results = std.ArrayList(CommandEntry).init(self.allocator);
        defer results.deinit();

        for (self.commandHistory.items) |entry| {
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
    pub fn addCollaborator(self: *Session, userId: []const u8, permissions: []const ACLEntry.Permission) !void {
        if (self.config.sessionType != .shared) {
            return SessionError.InvalidSessionType;
        }

        const collab = Collaborator{
            .userId = try self.allocator.dupe(u8, userId),
            .permissions = try self.allocator.dupe(ACLEntry.Permission, permissions),
            .joinedAt = time.timestamp(),
        };
        try self.collaborators.append(collab);

        // Audit log
        if (self.config.enableAudit) {
            const details = try fmt.allocPrint(self.allocator, "Collaborator added: {s}", .{userId});
            defer self.allocator.free(details);
            try self.addAuditEntry(.collaboratorAdded, details, userId);
        }
    }

    /// Remove collaborator
    pub fn removeCollaborator(self: *Session, userId: []const u8) !void {
        for (self.collaborators.items, 0..) |collab, i| {
            if (mem.eql(u8, collab.userId, userId)) {
                var collabToRemove = self.collaborators.orderedRemove(i);
                collabToRemove.deinit();
                break;
            }
        }

        // Audit log
        if (self.config.enableAudit) {
            const details = try fmt.allocPrint(self.allocator, "Collaborator removed: {s}", .{userId});
            defer self.allocator.free(details);
            try self.addAuditEntry(.collaboratorRemoved, details, userId);
        }
    }

    /// Lock session
    pub fn lock(self: *Session, owner: []const u8) !void {
        if (self.isLocked) {
            return SessionError.SessionLocked;
        }

        self.isLocked = true;
        self.lockOwner = try self.allocator.dupe(u8, owner);

        // Audit log
        if (self.config.enableAudit) {
            const details = try fmt.allocPrint(self.allocator, "Session locked by: {s}", .{owner});
            defer self.allocator.free(details);
            try self.addAuditEntry(.sessionLocked, details, owner);
        }
    }

    /// Unlock session
    pub fn unlock(self: *Session, owner: []const u8) !void {
        if (!self.isLocked) return;
        if (self.lockOwner) |lockOwner| {
            if (!mem.eql(u8, lockOwner, owner)) {
                return SessionError.AccessDenied;
            }
        }

        self.isLocked = false;
        self.allocator.free(self.lockOwner.?);
        self.lockOwner = null;

        // Audit log
        if (self.config.enableAudit) {
            const details = try fmt.allocPrint(self.allocator, "Session unlocked by: {s}", .{owner});
            defer self.allocator.free(details);
            try self.addAuditEntry(.sessionUnlocked, details, owner);
        }
    }

    /// Check if user has permission
    pub fn hasPermission(self: *Session, userId: []const u8, permission: ACLEntry.Permission) bool {
        // Owner always has all permissions
        if (mem.eql(u8, self.config.owner, userId)) {
            return true;
        }

        // Check ACL
        for (self.config.acl.items) |entry| {
            if (mem.eql(u8, entry.userId, userId)) {
                // Check if permission is granted and not expired
                for (entry.permissions) |p| {
                    if (p == permission) {
                        if (entry.expiresAt) |expires| {
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
        if (self.config.sessionType == .shared) {
            for (self.collaborators.items) |collab| {
                if (mem.eql(u8, collab.userId, userId)) {
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
    pub fn addAuditEntry(self: *Session, eventType: AuditEventType, details: []const u8, userId: ?[]const u8) !void {
        const entry = AuditEntry{
            .timestamp = time.timestamp(),
            .eventType = eventType,
            .userId = if (userId) |uid| try self.allocator.dupe(u8, uid) else null,
            .details = try self.allocator.dupe(u8, details),
            .ipAddress = null, // Would be populated in real implementation
            .userAgent = null, // Would be populated in real implementation
        };
        try self.auditLog.append(self.allocator, entry);
    }

    /// Get session duration in seconds
    pub fn getDuration(self: *Session) i64 {
        const endTime = self.endTime orelse time.timestamp();
        return endTime - self.startTime;
    }

    /// Check if session is expired
    pub fn isExpired(self: *Session) bool {
        const duration = self.getDuration();
        return @as(u64, @intCast(duration)) > self.config.maxDuration;
    }

    /// End session
    pub fn endSession(self: *Session) void {
        self.isActive = false;
        self.endTime = time.timestamp();
        self.lastActivity = self.endTime.?;

        // Audit log
        if (self.config.enableAudit) {
            self.addAuditEntry(.sessionEnded, "Session ended", null) catch {};
        }
    }

    /// Update performance metrics
    pub fn updatePerformanceMetrics(self: *Session) void {
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
        if (self.metadata) |_| {
            // meta.deinit(); // TODO: fix json.Value deinit
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
    userId: []const u8,
    permissions: []const ACLEntry.Permission,
    joinedAt: i64,

    /// Deinitialize collaborator
    pub fn deinit(self: *Collaborator, allocator: Allocator) void {
        allocator.free(self.userId);
        allocator.free(self.permissions);
    }
};

/// Audit event types
pub const AuditEventType = enum {
    sessionCreated,
    sessionLoaded,
    sessionSaved,
    sessionEnded,
    sessionLocked,
    sessionUnlocked,
    conversationAdded,
    commandExecuted,
    stateModified,
    collaboratorAdded,
    collaboratorRemoved,
    permissionGranted,
    permissionRevoked,
    securityViolation,
};

/// Audit log entry
pub const AuditEntry = struct {
    timestamp: i64,
    eventType: AuditEventType,
    userId: ?[]const u8 = null,
    details: []const u8,
    ipAddress: ?[]const u8 = null,
    userAgent: ?[]const u8 = null,

    /// Deinitialize audit entry
    pub fn deinit(self: *AuditEntry, allocator: Allocator) void {
        if (self.userId) |uid| {
            allocator.free(uid);
        }
        allocator.free(self.details);
        if (self.ipAddress) |ip| {
            allocator.free(ip);
        }
        if (self.userAgent) |ua| {
            allocator.free(ua);
        }
    }
};

/// Session statistics with metrics
pub const SessionStats = struct {
    /// Total messages processed
    messagesProcessed: u64 = 0,
    /// Total commands executed
    commandsExecuted: u64 = 0,
    /// Total tools executed
    toolsExecuted: u64 = 0,
    /// Total tokens used
    totalTokens: u64 = 0,
    /// Input tokens
    inputTokens: u64 = 0,
    /// Output tokens
    outputTokens: u64 = 0,
    /// Authentication attempts
    authAttempts: u64 = 0,
    /// Authentication failures
    authFailures: u64 = 0,
    /// State snapshots created
    snapshotsCreated: u64 = 0,
    /// Undo operations performed
    undoOperations: u64 = 0,
    /// Redo operations performed
    redoOperations: u64 = 0,
    /// Checkpoints created
    checkpointsCreated: u64 = 0,
    /// Recovery operations performed
    recoveryOperations: u64 = 0,
    /// Last activity timestamp
    lastActivity: i64 = 0,
    /// Average response time in nanoseconds
    averageResponseTime: i64 = 0,
    /// Last response time
    lastResponseTime: i64 = 0,
    /// Error count
    errorCount: u64 = 0,
    /// Average session duration
    averageSessionDuration: f64 = 0,
    /// Last session start time
    lastSessionStart: i64 = 0,
    /// Last session end time
    lastSessionEnd: i64 = 0,
    /// Total sessions created
    totalSessions: u64 = 0,

    /// Update statistics with new session data
    pub fn updateWithSession(self: *SessionStats, session: *Session) void {
        self.messagesProcessed = session.conversationHistory.items.len;
        self.commandsExecuted = session.commandHistory.items.len;
        self.lastActivity = session.lastActivity;
    }

    /// Record response time
    pub fn recordResponseTime(self: *SessionStats, responseTimeNs: i64) void {
        self.lastResponseTime = responseTimeNs;
        // Update rolling average
        if (self.averageResponseTime == 0) {
            self.averageResponseTime = responseTimeNs;
        } else {
            self.averageResponseTime = (self.averageResponseTime + responseTimeNs) / 2;
        }
    }

    /// Record token usage
    pub fn recordTokenUsage(self: *SessionStats, inputTokens: u64, outputTokens: u64) void {
        self.inputTokens += inputTokens;
        self.outputTokens += outputTokens;
        self.totalTokens += inputTokens + outputTokens;
    }

    /// Record authentication attempt
    pub fn recordAuthAttempt(self: *SessionStats, success: bool) void {
        self.authAttempts += 1;
        if (!success) {
            self.authFailures += 1;
        }
    }

    /// Record error
    pub fn recordError(self: *SessionStats) void {
        self.errorCount += 1;
    }

    /// Get success rate as percentage
    pub fn getAuthSuccessRate(self: *SessionStats) f64 {
        if (self.authAttempts == 0) return 100.0;
        const successCount = self.authAttempts - self.authFailures;
        return @as(f64, @floatFromInt(successCount)) / @as(f64, @floatFromInt(self.authAttempts)) * 100.0;
    }
};

/// Performance metrics for monitoring agent performance
pub const PerformanceMetrics = struct {
    renderTimeMs: f64 = 0,
    responseTimeMs: f64 = 0,
    memoryUsageMb: f64 = 0,
    cpuUsagePercent: f64 = 0,
    cacheHitRate: f64 = 0,
    lastUpdated: i64 = 0,

    /// Update metrics with current values
    pub fn update(self: *PerformanceMetrics) void {
        self.lastUpdated = time.timestamp();
        // In a real implementation, these would be measured from system
        // For now, we'll set some placeholder values
        self.memoryUsageMb = 50.0; // Placeholder
        self.cpuUsagePercent = 15.0; // Placeholder
        self.cacheHitRate = 85.0; // Placeholder
    }

    /// Record render time
    pub fn recordRenderTime(self: *PerformanceMetrics, renderTimeMs: f64) void {
        self.renderTimeMs = renderTimeMs;
        self.update();
    }

    /// Record response time
    pub fn recordResponseTime(self: *PerformanceMetrics, responseTimeMs: f64) void {
        self.responseTimeMs = responseTimeMs;
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
            self.renderTimeMs,
            self.responseTimeMs,
            self.memoryUsageMb,
            self.cpuUsagePercent,
            self.cacheHitRate,
        });
    }
};

/// Session manager for persistence and lifecycle management
pub const SessionManager = struct {
    allocator: Allocator,
    sessionsDir: []const u8,
    checkpointsDir: []const u8,
    historyDir: []const u8,
    activeSessions: std.StringHashMap(*Session),
    stats: SessionStats,
    /// Encryption key for session encryption
    masterKey: ?[32]u8 = null,
    /// Compression enabled
    compressionEnabled: bool = true,

    /// Initialize session manager
    pub fn init(allocator: Allocator, sessionsDir: []const u8, enableEncryption: bool) !*SessionManager {
        const manager = try allocator.create(SessionManager);
        manager.* = SessionManager{
            .allocator = allocator,
            .sessionsDir = try allocator.dupe(u8, sessionsDir),
            .checkpointsDir = try fmt.allocPrint(allocator, "{s}/checkpoints", .{sessionsDir}),
            .historyDir = try fmt.allocPrint(allocator, "{s}/history", .{sessionsDir}),
            .activeSessions = std.StringHashMap(*Session).init(allocator),
            .stats = SessionStats{},
            .compressionEnabled = true,
        };

        // Generate master key if encryption is enabled
        if (enableEncryption) {
            crypto.random.bytes(&manager.masterKey.?);
        }

        // Create directories
        try fs.cwd().makePath(sessionsDir);
        try fs.cwd().makePath(manager.checkpointsDir);
        try fs.cwd().makePath(manager.historyDir);

        return manager;
    }

    /// Deinitialize session manager
    pub fn deinit(self: *SessionManager) void {
        self.allocator.free(self.sessionsDir);
        self.allocator.free(self.checkpointsDir);
        self.allocator.free(self.historyDir);

        var it = self.activeSessions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.activeSessions.deinit();
    }

    /// Create a new session
    pub fn createSession(self: *SessionManager, sessionId: []const u8, config: SessionConfig) !*Session {
        const session = try self.allocator.create(Session);
        session.* = try Session.init(self.allocator, sessionId, config);

        const key = try self.allocator.dupe(u8, sessionId);
        try self.activeSessions.put(key, session);

        self.stats.updateWithSession(session);

        // Audit log
        if (config.enableAudit) {
            try session.addAuditEntry(.sessionCreated, "Session created", config.owner);
        }

        return session;
    }

    /// Get existing session
    pub fn getSession(self: *SessionManager, sessionId: []const u8) ?*Session {
        return self.activeSessions.get(sessionId);
    }

    /// Save session to disk
    pub fn saveSession(self: *SessionManager, session: *Session) !void {
        if (!session.config.enablePersistence) return;

        const filename = try fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.sessionsDir, session.sessionId });
        defer self.allocator.free(filename);

        // Create session JSON
        const sessionJson = json.Value{
            .object = .{
                .sessionId = json.Value{ .string = session.sessionId },
                .startTime = json.Value{ .integer = session.startTime },
                .lastActivity = json.Value{ .integer = session.lastActivity },
                .isActive = json.Value{ .bool = session.isActive },
            },
        };

        // Serialize to string
        const serialized = try json.stringifyAlloc(self.allocator, sessionJson, .{ .whitespace = true });
        defer self.allocator.free(serialized);

        // Encrypt if needed
        var encryptedData = serialized;
        if (self.masterKey) |key| {
            encryptedData = try self.encryptData(serialized, key);
        }
        defer if (encryptedData.ptr != serialized.ptr) self.allocator.free(encryptedData);

        // Compress if needed
        var compressedData = encryptedData;
        if (self.compressionEnabled) {
            compressedData = try self.compressData(encryptedData);
        }
        defer if (compressedData.ptr != encryptedData.ptr) self.allocator.free(compressedData);

        // Write to file
        const file = try fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(compressedData);

        // Audit log
        if (session.config.enableAudit) {
            try session.addAuditEntry(.sessionSaved, "Session saved to disk", session.config.owner);
        }
    }

    /// Create checkpoint
    pub fn createCheckpoint(self: *SessionManager, session: *Session, description: []const u8) !void {
        if (!session.config.enableCheckpoints) return;

        const timestamp = time.timestamp();
        const checkpointId = try fmt.allocPrint(self.allocator, "{s}_{x}", .{ session.sessionId, timestamp });
        defer self.allocator.free(checkpointId);

        const filename = try fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.checkpointsDir, checkpointId });
        defer self.allocator.free(filename);

        // Create checkpoint data
        const checkpointData = json.Value{
            .object = .{
                .sessionId = json.Value{ .string = session.sessionId },
                .checkpointId = json.Value{ .string = checkpointId },
                .timestamp = json.Value{ .integer = timestamp },
                .description = json.Value{ .string = description },
            },
        };

        const serialized = try json.stringifyAlloc(self.allocator, checkpointData, .{ .whitespace = true });
        defer self.allocator.free(serialized);

        const file = try fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(serialized);

        session.stats.checkpointsCreated += 1;

        // Audit log
        if (session.config.enableAudit) {
            const details = try fmt.allocPrint(self.allocator, "Checkpoint created: {s}", .{description});
            defer self.allocator.free(details);
            try session.addAuditEntry(.stateModified, details, session.config.owner);
        }
    }

    /// End a session
    pub fn endSession(self: *SessionManager, sessionId: []const u8) !void {
        if (self.activeSessions.getEntry(sessionId)) |entry| {
            entry.value_ptr.*.endSession();

            // Save final state
            try self.saveSession(entry.value_ptr.*);

            // Create final checkpoint if enabled
            if (entry.value_ptr.*.config.enableCheckpoints) {
                try self.createCheckpoint(entry.value_ptr.*, "Session ended");
            }
        }
    }

    /// Get session statistics
    pub fn getStats(self: *SessionManager) SessionStats {
        return self.stats;
    }

    /// Clean up old sessions and checkpoints
    pub fn cleanupOldSessions(self: *SessionManager, maxAgeDays: u32) !void {
        const cutoffTime = time.timestamp() - (@as(i64, maxAgeDays) * 24 * 60 * 60);

        // Clean sessions
        try self.cleanupDirectory(self.sessionsDir, cutoffTime);
        // Clean checkpoints
        try self.cleanupDirectory(self.checkpointsDir, cutoffTime);
        // Clean history
        try self.cleanupDirectory(self.historyDir, cutoffTime);
    }

    /// List available sessions
    pub fn listSessions(self: *SessionManager) ![]const []const u8 {
        var sessions = std.array_list.Managed([]const u8).init(self.allocator);
        defer sessions.deinit();

        var dir = try fs.cwd().openDir(self.sessionsDir, .{ .iterate = true });
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and mem.endsWith(u8, entry.name, ".json")) {
                // Remove .json extension
                const nameLen = mem.indexOf(u8, entry.name, ".json") orelse entry.name.len;
                const sessionName = try self.allocator.dupe(u8, entry.name[0..nameLen]);
                try sessions.append(sessionName);
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

    fn createSessionJson(self: *SessionManager, session: *Session) !json.Value {
        _ = self;
        return json.Value{
            .object = .{
                .sessionId = json.Value{ .string = session.sessionId },
                .startTime = json.Value{ .integer = session.startTime },
                .lastActivity = json.Value{ .integer = session.lastActivity },
                .isActive = json.Value{ .bool = session.isActive },
            },
        };
    }

    fn cleanupDirectory(self: *SessionManager, dirPath: []const u8, cutoffTime: i64) !void {
        var dir = fs.cwd().openDir(dirPath, .{ .iterate = true }) catch return;
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and mem.endsWith(u8, entry.name, ".json")) {
                const filepath = try fmt.allocPrint(self.allocator, "{s}/{s}", .{ dirPath, entry.name });
                defer self.allocator.free(filepath);

                const stat = try fs.cwd().statFile(filepath);
                if (stat.mtime < cutoffTime) {
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
    /// Create a session configuration
    pub fn createConfig(allocator: Allocator, title: []const u8, owner: []const u8) anyerror!SessionConfig {
        var config = try SessionConfig.init(allocator);
        config.title = try allocator.dupe(u8, title);
        config.owner = try allocator.dupe(u8, owner);
        config.sessionType = .interactive;
        config.enablePersistence = true;
        config.enableCheckpoints = true;
        config.enableAudit = true;
        return config;
    }

    /// Create a rich session configuration with TUI support
    pub fn createRichConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createConfig(allocator, title, owner);
        config.enableCollaboration = true;
        config.enableEncryption = true;
        config.enableCompression = true;
        return config;
    }

    /// Create a CLI-only session configuration
    pub fn createCliConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createConfig(allocator, title, owner);
        config.enableCollaboration = false;
        config.enableCheckpoints = false;
        return config;
    }

    /// Create a shared session configuration
    pub fn createSharedConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createConfig(allocator, title, owner);
        config.sessionType = .shared;
        config.enableCollaboration = true;
        config.enableEncryption = true;
        return config;
    }

    /// Create a read-only session configuration
    pub fn createReadOnlyConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createConfig(allocator, title, owner);
        config.sessionType = .readOnly;
        config.enablePersistence = false;
        config.enableCheckpoints = false;
        return config;
    }

    /// Create a temporary session configuration
    pub fn createTemporaryConfig(allocator: Allocator, title: []const u8, owner: []const u8) SessionConfig {
        var config = createConfig(allocator, title, owner);
        config.sessionType = .temporary;
        config.enablePersistence = false;
        config.enableCheckpoints = false;
        config.enableAudit = false;
        config.maxDuration = 3600; // 1 hour
        return config;
    }
};
