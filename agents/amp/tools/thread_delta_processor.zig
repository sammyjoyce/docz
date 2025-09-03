const std = @import("std");
const foundation = @import("foundation");
const json = std.json;

const ThreadDeltaProcessor = @This();

const DeltaType = enum {
    cancelled,
    @"summary:created",
    @"fork:created",
    @"thread:truncate",
    @"user:message",
    @"user:message-queue:dequeue",
    @"user:tool-input",
    @"tool:data",
};

const DeltaObject = struct {
    type: DeltaType,
    payload: json.Value = .null,
    index: ?u32 = null,
    message_id: ?[]const u8 = null,
    tool_id: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    external_thread_id: ?[]const u8 = null,
    content: ?[]const u8 = null,
    input: ?json.Value = null,
    data: ?json.Value = null,
};

const ThreadState = struct {
    version: u32 = 0,
    messages: std.ArrayList(json.Value),
    summaries: std.ArrayList(json.Value),
    forks: std.ArrayList(json.Value),
    tools: std.ArrayList(json.Value),
    queue: std.ArrayList(json.Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ThreadState {
        return ThreadState{
            .messages = std.ArrayList(json.Value).init(allocator),
            .summaries = std.ArrayList(json.Value).init(allocator),
            .forks = std.ArrayList(json.Value).init(allocator),
            .tools = std.ArrayList(json.Value).init(allocator),
            .queue = std.ArrayList(json.Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ThreadState) void {
        self.messages.deinit();
        self.summaries.deinit();
        self.forks.deinit();
        self.tools.deinit();
        self.queue.deinit();
    }
};

pub const ToolSpec = foundation.tools.ToolSpec{
    .name = "thread_delta_processor",
    .description = "Processes thread state changes including messages, cancellations, summaries, forks, and tool interactions",
    .parameters = .{
        .type = .object,
        .properties = .{
            .delta = .{
                .type = .object,
                .description = "Delta object containing operation type and associated payload data",
                .properties = .{
                    .type = .{ .type = .string, .description = "Type of delta operation to perform" },
                    .payload = .{ .type = .object, .description = "Associated payload data for the operation" },
                    .index = .{ .type = .integer, .description = "Message index for operations that target specific messages" },
                    .message_id = .{ .type = .string, .description = "Unique identifier for message operations" },
                    .tool_id = .{ .type = .string, .description = "Tool identifier for tool-related operations" },
                    .summary = .{ .type = .string, .description = "Summary content for summary operations" },
                    .external_thread_id = .{ .type = .string, .description = "External thread reference for fork operations" },
                    .content = .{ .type = .string, .description = "Message content for user message operations" },
                    .input = .{ .type = .object, .description = "Tool input data for tool input operations" },
                    .data = .{ .type = .object, .description = "Tool execution data for tool data operations" },
                },
                .required = &.{"type"},
            },
            .thread_state = .{
                .type = .object,
                .description = "Current thread state object to be modified",
                .properties = .{
                    .version = .{ .type = .integer, .description = "Current version of the thread state" },
                    .messages = .{ .type = .array, .description = "Array of messages in the thread" },
                    .summaries = .{ .type = .array, .description = "Array of summaries for the thread" },
                    .forks = .{ .type = .array, .description = "Array of thread forks" },
                    .tools = .{ .type = .array, .description = "Array of tool interactions" },
                    .queue = .{ .type = .array, .description = "Queue of pending messages" },
                },
            },
        },
        .required = &.{ "delta", "thread_state" },
    },
};

pub fn execute(
    allocator: std.mem.Allocator,
    params: std.json.Value,
) !std.json.Value {
    if (params != .object) {
        return std.json.Value{ .string = "Parameters must be a JSON object" };
    }

    const obj = params.object;
    const delta_value = obj.get("delta") orelse {
        return std.json.Value{ .string = "Missing required 'delta' parameter" };
    };

    const thread_state_value = obj.get("thread_state") orelse {
        return std.json.Value{ .string = "Missing required 'thread_state' parameter" };
    };

    // Parse delta object
    var delta_obj = std.json.parseFromValue(DeltaObject, allocator, delta_value, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to parse delta object: {}", .{err});
        return std.json.Value{ .string = error_msg };
    };
    defer delta_obj.deinit();

    // Parse thread state
    var thread_state = parseThreadState(allocator, thread_state_value) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to parse thread state: {}", .{err});
        return std.json.Value{ .string = error_msg };
    };
    defer thread_state.deinit();

    // Process delta based on type
    try processDelta(allocator, &thread_state, delta_obj.value);

    // Serialize updated thread state and return as JSON
    const result_str = try serializeThreadState(allocator, &thread_state);
    defer allocator.free(result_str);

    var parsed_result = std.json.parseFromSlice(std.json.Value, allocator, result_str, .{}) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to parse result JSON: {}", .{err});
        return std.json.Value{ .string = error_msg };
    };
    defer parsed_result.deinit();

    return parsed_result.value;
}

fn parseThreadState(allocator: std.mem.Allocator, value: json.Value) !ThreadState {
    var thread_state = ThreadState.init(allocator);

    if (value != .object) {
        return error.InvalidThreadState;
    }

    const obj = value.object;

    if (obj.get("version")) |v| {
        if (v == .integer) {
            thread_state.version = @intCast(v.integer);
        }
    }

    if (obj.get("messages")) |msgs| {
        if (msgs == .array) {
            for (msgs.array.items) |msg| {
                try thread_state.messages.append(msg);
            }
        }
    }

    if (obj.get("summaries")) |summs| {
        if (summs == .array) {
            for (summs.array.items) |summ| {
                try thread_state.summaries.append(summ);
            }
        }
    }

    if (obj.get("forks")) |forks| {
        if (forks == .array) {
            for (forks.array.items) |fork| {
                try thread_state.forks.append(fork);
            }
        }
    }

    if (obj.get("tools")) |tools| {
        if (tools == .array) {
            for (tools.array.items) |tool| {
                try thread_state.tools.append(tool);
            }
        }
    }

    if (obj.get("queue")) |queue| {
        if (queue == .array) {
            for (queue.array.items) |item| {
                try thread_state.queue.append(item);
            }
        }
    }

    return thread_state;
}

fn processDelta(allocator: std.mem.Allocator, thread_state: *ThreadState, delta: DeltaObject) !void {
    // Increment version counter for each operation
    thread_state.version += 1;

    switch (delta.type) {
        .cancelled => {
            // Mark operations as cancelled - for tool results find and mark as cancelled
            if (delta.tool_id) |tool_id| {
                for (thread_state.tools.items) |*tool| {
                    if (tool.* == .object) {
                        if (tool.object.get("id")) |id| {
                            if (id == .string and std.mem.eql(u8, id.string, tool_id)) {
                                try tool.object.put("status", json.Value{ .string = "cancelled" });
                                break;
                            }
                        }
                    }
                }
            }
        },

        .@"summary:created" => {
            // Add summary information
            var summary_obj = json.ObjectMap.init(allocator);
            try summary_obj.put("content", json.Value{ .string = delta.summary orelse "" });
            try summary_obj.put("created_at", json.Value{ .integer = std.time.timestamp() });

            if (delta.external_thread_id) |ext_id| {
                try summary_obj.put("external_thread_id", json.Value{ .string = ext_id });
                try summary_obj.put("type", json.Value{ .string = "external" });
            } else {
                try summary_obj.put("type", json.Value{ .string = "internal" });
            }

            try thread_state.summaries.append(json.Value{ .object = summary_obj });
        },

        .@"fork:created" => {
            // Create thread fork from specific message index
            var fork_obj = json.ObjectMap.init(allocator);
            try fork_obj.put("index", json.Value{ .integer = @intCast(delta.index orelse 0) });
            try fork_obj.put("created_at", json.Value{ .integer = std.time.timestamp() });

            if (delta.external_thread_id) |ext_id| {
                try fork_obj.put("external_thread_id", json.Value{ .string = ext_id });
            }

            try thread_state.forks.append(json.Value{ .object = fork_obj });
        },

        .@"thread:truncate" => {
            // Remove messages from specified index onward
            const truncate_index = delta.index orelse thread_state.messages.items.len;
            if (truncate_index < thread_state.messages.items.len) {
                thread_state.messages.shrinkAndFree(allocator, truncate_index);
            }
        },

        .@"user:message" => {
            // Add or replace user message
            var msg_obj = json.ObjectMap.init(allocator);
            try msg_obj.put("role", json.Value{ .string = "user" });
            try msg_obj.put("content", json.Value{ .string = delta.content orelse "" });
            try msg_obj.put("timestamp", json.Value{ .integer = std.time.timestamp() });

            if (delta.message_id) |msg_id| {
                try msg_obj.put("id", json.Value{ .string = msg_id });

                // Look for existing message with this ID and replace it
                var replaced = false;
                for (thread_state.messages.items, 0..) |*msg, i| {
                    if (msg.* == .object) {
                        if (msg.object.get("id")) |id| {
                            if (id == .string and std.mem.eql(u8, id.string, msg_id)) {
                                thread_state.messages.items[i] = json.Value{ .object = msg_obj };
                                replaced = true;
                                break;
                            }
                        }
                    }
                }

                if (!replaced) {
                    try thread_state.messages.append(json.Value{ .object = msg_obj });
                }
            } else {
                try thread_state.messages.append(json.Value{ .object = msg_obj });
            }
        },

        .@"user:message-queue:dequeue" => {
            // Process queued messages - move from queue to messages
            if (thread_state.queue.items.len > 0) {
                const queued_msg = thread_state.queue.swapRemove(0);
                try thread_state.messages.append(queued_msg);
            }
        },

        .@"user:tool-input" => {
            // Update tool input values
            if (delta.tool_id) |tool_id| {
                for (thread_state.tools.items) |*tool| {
                    if (tool.* == .object) {
                        if (tool.object.get("id")) |id| {
                            if (id == .string and std.mem.eql(u8, id.string, tool_id)) {
                                if (delta.input) |input| {
                                    try tool.object.put("input", input);
                                }
                                break;
                            }
                        }
                    }
                }
            }
        },

        .@"tool:data" => {
            // Handle tool execution data
            if (delta.tool_id) |tool_id| {
                var tool_obj = json.ObjectMap.init(allocator);
                try tool_obj.put("id", json.Value{ .string = tool_id });
                try tool_obj.put("status", json.Value{ .string = "executing" });
                try tool_obj.put("timestamp", json.Value{ .integer = std.time.timestamp() });

                if (delta.data) |data| {
                    try tool_obj.put("data", data);
                }

                try thread_state.tools.append(json.Value{ .object = tool_obj });
            }
        },
    }
}

fn serializeThreadState(allocator: std.mem.Allocator, thread_state: *ThreadState) ![]const u8 {
    var result_obj = json.ObjectMap.init(allocator);

    try result_obj.put("version", json.Value{ .integer = @intCast(thread_state.version) });

    // Convert ArrayLists to JSON arrays
    var messages_array = json.Array.init(allocator);
    for (thread_state.messages.items) |msg| {
        try messages_array.append(msg);
    }
    try result_obj.put("messages", json.Value{ .array = messages_array });

    var summaries_array = json.Array.init(allocator);
    for (thread_state.summaries.items) |summary| {
        try summaries_array.append(summary);
    }
    try result_obj.put("summaries", json.Value{ .array = summaries_array });

    var forks_array = json.Array.init(allocator);
    for (thread_state.forks.items) |fork| {
        try forks_array.append(fork);
    }
    try result_obj.put("forks", json.Value{ .array = forks_array });

    var tools_array = json.Array.init(allocator);
    for (thread_state.tools.items) |tool| {
        try tools_array.append(tool);
    }
    try result_obj.put("tools", json.Value{ .array = tools_array });

    var queue_array = json.Array.init(allocator);
    for (thread_state.queue.items) |item| {
        try queue_array.append(item);
    }
    try result_obj.put("queue", json.Value{ .array = queue_array });

    const result_value = json.Value{ .object = result_obj };

    // Stringify the result
    var string_buffer = std.ArrayList(u8){};
    defer string_buffer.deinit(allocator);

    try json.stringify(result_value, .{}, string_buffer.writer());
    return try allocator.dupe(u8, string_buffer.items);
}
