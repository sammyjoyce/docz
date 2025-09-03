const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;
const json = std.json;

const ThreadSummarization = @This();

const ConversationMessage = struct {
    role: []const u8,
    content: []const u8,
    timestamp: ?i64 = null,
    tool_calls: ?[]ToolCall = null,
};

const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    arguments: []const u8,
    result: ?[]const u8 = null,
};

const SummaryRequest = struct {
    messages: []ConversationMessage,
    current_task: ?[]const u8 = null,
    context: ?[]const u8 = null,
    include_technical_details: bool = true,
    max_summary_length: ?u32 = null,
};

const SummaryResponse = struct {
    summary: []const u8,
    title: []const u8,
    key_files: [][]const u8,
    key_functions: [][]const u8,
    key_commands: [][]const u8,
    next_steps: [][]const u8,
    technical_context: [][]const u8,
};

pub const ToolSpec = foundation.tools.ToolSpec{
    .name = "thread_summarization",
    .description = "Generates detailed conversation summaries with enough information for handoff to another person",
    .parameters = .{
        .type = .object,
        .properties = .{
            .messages = .{
                .type = .array,
                .description = "Array of conversation messages to summarize",
                .items = .{
                    .type = .object,
                    .properties = .{
                        .role = .{ .type = .string, .description = "Role of the message sender (user, assistant, system)" },
                        .content = .{ .type = .string, .description = "Content of the message" },
                        .timestamp = .{ .type = .integer, .description = "Unix timestamp of the message" },
                        .tool_calls = .{
                            .type = .array,
                            .description = "Tool calls made in this message",
                            .items = .{
                                .type = .object,
                                .properties = .{
                                    .id = .{ .type = .string, .description = "Unique identifier for the tool call" },
                                    .name = .{ .type = .string, .description = "Name of the tool called" },
                                    .arguments = .{ .type = .string, .description = "JSON string of tool arguments" },
                                    .result = .{ .type = .string, .description = "Result of the tool call" },
                                },
                                .required = &.{ "id", "name", "arguments" },
                            },
                        },
                    },
                    .required = &.{ "role", "content" },
                },
            },
            .current_task = .{
                .type = .string,
                .description = "Description of the current task being worked on",
            },
            .context = .{
                .type = .string,
                .description = "Additional context about the conversation or project",
            },
            .include_technical_details = .{
                .type = .boolean,
                .description = "Whether to include file paths, function names, and commands in the summary",
                .default = true,
            },
            .max_summary_length = .{
                .type = .integer,
                .description = "Maximum length of the summary in words (optional)",
            },
        },
        .required = &.{"messages"},
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
    const messages_value = obj.get("messages") orelse {
        return std.json.Value{ .string = "Missing required 'messages' parameter" };
    };

    const current_task = if (obj.get("current_task")) |t| t.string else null;
    const context = if (obj.get("context")) |c| c.string else null;
    const include_technical_details = if (obj.get("include_technical_details")) |b| b.bool else true;
    const max_summary_length = if (obj.get("max_summary_length")) |l| @as(u32, @intCast(l.integer)) else null;

    // Parse messages
    var messages = std.ArrayList(ConversationMessage){};
    defer messages.deinit(allocator);

    if (messages_value != .array) {
        return std.json.Value{ .string = "Messages parameter must be an array" };
    }

    for (messages_value.array.items) |msg_value| {
        const msg = parseConversationMessage(allocator, msg_value) catch |err| {
            const error_msg = try std.fmt.allocPrint(allocator, "Failed to parse message: {}", .{err});
            return std.json.Value{ .string = error_msg };
        };
        try messages.append(allocator, msg);
    }

    // Generate summary
    const summary_response = try generateSummary(allocator, messages.items, current_task, context, include_technical_details, max_summary_length);

    // Use JsonReflector to serialize response
    const ResponseMapper = toolsMod.JsonReflector.mapper(SummaryResponse);
    return try ResponseMapper.toJsonValue(allocator, summary_response);
}

fn parseConversationMessage(allocator: std.mem.Allocator, value: json.Value) !ConversationMessage {
    if (value != .object) {
        return error.InvalidMessage;
    }

    const obj = value.object;

    const role = if (obj.get("role")) |r| r.string else return error.MissingRole;
    const content = if (obj.get("content")) |c| c.string else return error.MissingContent;
    const timestamp = if (obj.get("timestamp")) |t| t.integer else null;

    var tool_calls: ?[]ToolCall = null;
    if (obj.get("tool_calls")) |tc| {
        if (tc == .array) {
            var calls = std.ArrayList(ToolCall){};
            defer calls.deinit(allocator);

            for (tc.array.items) |call_value| {
                if (call_value == .object) {
                    const call_obj = call_value.object;
                    const call = ToolCall{
                        .id = if (call_obj.get("id")) |id| id.string else "",
                        .name = if (call_obj.get("name")) |name| name.string else "",
                        .arguments = if (call_obj.get("arguments")) |args| args.string else "",
                        .result = if (call_obj.get("result")) |res| res.string else null,
                    };
                    try calls.append(allocator, call);
                }
            }

            if (calls.items.len > 0) {
                tool_calls = try allocator.dupe(ToolCall, calls.items);
            }
        }
    }

    return ConversationMessage{
        .role = try allocator.dupe(u8, role),
        .content = try allocator.dupe(u8, content),
        .timestamp = timestamp,
        .tool_calls = tool_calls,
    };
}

fn generateSummary(
    allocator: std.mem.Allocator,
    messages: []ConversationMessage,
    current_task: ?[]const u8,
    context: ?[]const u8,
    include_technical_details: bool,
    max_summary_length: ?u32,
) !SummaryResponse {
    _ = context; // Context parameter for future use
    // Analyze conversation to extract key information
    var user_goals = std.ArrayList([]const u8){};
    defer user_goals.deinit(allocator);

    var accomplishments = std.ArrayList([]const u8){};
    defer accomplishments.deinit(allocator);

    var key_files = std.ArrayList([]const u8){};
    defer key_files.deinit(allocator);

    var key_functions = std.ArrayList([]const u8){};
    defer key_functions.deinit(allocator);

    var key_commands = std.ArrayList([]const u8){};
    defer key_commands.deinit(allocator);

    var technical_context = std.ArrayList([]const u8){};
    defer technical_context.deinit(allocator);

    // Extract information from messages
    for (messages) |msg| {
        if (std.mem.eql(u8, msg.role, "user")) {
            // Extract user requests and goals
            if (containsRequestKeywords(msg.content)) {
                try user_goals.append(allocator, try allocator.dupe(u8, msg.content));
            }
        }

        if (include_technical_details) {
            // Extract file paths
            try extractFilePaths(allocator, msg.content, &key_files);

            // Extract function names
            try extractFunctionNames(allocator, msg.content, &key_functions);

            // Extract commands
            try extractCommands(allocator, msg.content, &key_commands);
        }

        // Extract tool call information
        if (msg.tool_calls) |calls| {
            for (calls) |call| {
                const tech_info = try std.fmt.allocPrint(allocator, "Tool: {s} - {s}", .{ call.name, call.arguments });
                try technical_context.append(allocator, tech_info);
            }
        }
    }

    // Generate summary text
    var summary_parts = std.ArrayList([]const u8){};
    defer summary_parts.deinit(allocator);

    // What the user wanted
    if (user_goals.items.len > 0) {
        try summary_parts.append(allocator, "What you wanted:");
        for (user_goals.items, 0..) |goal, i| {
            const numbered_goal = try std.fmt.allocPrint(allocator, "{}. {s}", .{ i + 1, goal });
            try summary_parts.append(allocator, numbered_goal);
        }
        try summary_parts.append(allocator, "");
    }

    // What was accomplished
    if (accomplishments.items.len > 0) {
        try summary_parts.append(allocator, "What we accomplished:");
        for (accomplishments.items, 0..) |acc, i| {
            const numbered_acc = try std.fmt.allocPrint(allocator, "{}. {s}", .{ i + 1, acc });
            try summary_parts.append(allocator, numbered_acc);
        }
        try summary_parts.append(allocator, "");
    }

    // Current task
    if (current_task) |task| {
        const current_text = try std.fmt.allocPrint(allocator, "Current task: {s}", .{task});
        try summary_parts.append(allocator, current_text);
        try summary_parts.append(allocator, "");
    }

    // Technical details
    if (include_technical_details and (key_files.items.len > 0 or key_functions.items.len > 0 or key_commands.items.len > 0)) {
        try summary_parts.append(allocator, "Important technical details:");

        if (key_files.items.len > 0) {
            try summary_parts.append(allocator, "Key files:");
            for (key_files.items) |file| {
                const file_entry = try std.fmt.allocPrint(allocator, "- {s}", .{file});
                try summary_parts.append(allocator, file_entry);
            }
        }

        if (key_functions.items.len > 0) {
            try summary_parts.append(allocator, "Key functions:");
            for (key_functions.items) |func| {
                const func_entry = try std.fmt.allocPrint(allocator, "- {s}", .{func});
                try summary_parts.append(allocator, func_entry);
            }
        }

        if (key_commands.items.len > 0) {
            try summary_parts.append(allocator, "Key commands:");
            for (key_commands.items) |cmd| {
                const cmd_entry = try std.fmt.allocPrint(allocator, "- {s}", .{cmd});
                try summary_parts.append(allocator, cmd_entry);
            }
        }
    }

    // Join summary parts
    const summary = try std.mem.join(allocator, "\n", summary_parts.items);

    // Truncate if necessary
    const final_summary = if (max_summary_length) |max_len|
        try truncateToWordLimit(allocator, summary, max_len)
    else
        summary;

    // Generate title (max 7 words)
    const title = try generateTitle(allocator, user_goals.items, current_task);

    // Prepare next steps
    var next_steps = std.ArrayList([]const u8){};
    defer next_steps.deinit(allocator);

    if (current_task) |task| {
        const continue_task = try std.fmt.allocPrint(allocator, "Continue working on: {s}", .{task});
        try next_steps.append(allocator, continue_task);
    }

    return SummaryResponse{
        .summary = final_summary,
        .title = title,
        .key_files = try allocator.dupe([]const u8, key_files.items),
        .key_functions = try allocator.dupe([]const u8, key_functions.items),
        .key_commands = try allocator.dupe([]const u8, key_commands.items),
        .next_steps = try allocator.dupe([]const u8, next_steps.items),
        .technical_context = try allocator.dupe([]const u8, technical_context.items),
    };
}

fn containsRequestKeywords(content: []const u8) bool {
    const keywords = [_][]const u8{ "can you", "please", "help me", "I want", "I need", "implement", "create", "fix", "add" };
    for (keywords) |keyword| {
        if (std.mem.indexOf(u8, content, keyword) != null) {
            return true;
        }
    }
    return false;
}

fn extractFilePaths(allocator: std.mem.Allocator, content: []const u8, files: *std.ArrayList([]const u8)) !void {
    // Look for common file path patterns
    var i: usize = 0;
    while (i < content.len) {
        // Look for file extensions
        const extensions = [_][]const u8{ ".zig", ".js", ".ts", ".py", ".go", ".rs", ".c", ".cpp", ".h", ".md", ".json", ".yaml", ".yml" };

        for (extensions) |ext| {
            if (i + ext.len < content.len and std.mem.eql(u8, content[i .. i + ext.len], ext)) {
                // Find the start of the path
                var start = i;
                while (start > 0 and (std.ascii.isAlphanumeric(content[start - 1]) or
                    content[start - 1] == '/' or content[start - 1] == '.' or
                    content[start - 1] == '_' or content[start - 1] == '-'))
                {
                    start -= 1;
                }

                // Extract the file path
                const path = content[start .. i + ext.len];
                if (path.len > ext.len and path.len < 200) { // Reasonable path length
                    try files.append(allocator, try allocator.dupe(u8, path));
                }
                break;
            }
        }
        i += 1;
    }
}

fn extractFunctionNames(allocator: std.mem.Allocator, content: []const u8, functions: *std.ArrayList([]const u8)) !void {
    // Look for function patterns like "function_name()", "fn function_name", etc.
    var i: usize = 0;
    while (i < content.len) {
        // Look for patterns like "fn name" or "function name" or "name("
        if (i + 3 < content.len and std.mem.eql(u8, content[i .. i + 3], "fn ")) {
            i += 3;
            const start = i;
            while (i < content.len and (std.ascii.isAlphanumeric(content[i]) or content[i] == '_')) {
                i += 1;
            }
            if (i > start) {
                const func_name = content[start..i];
                if (func_name.len > 0 and func_name.len < 50) {
                    try functions.append(allocator, try allocator.dupe(u8, func_name));
                }
            }
        } else if (i + 1 < content.len and content[i] == '(' and i > 0) {
            // Look backwards for function name before '('
            var start = i - 1;
            while (start > 0 and (std.ascii.isAlphanumeric(content[start]) or content[start] == '_')) {
                start -= 1;
            }
            start += 1;
            if (start < i) {
                const func_name = content[start..i];
                if (func_name.len > 0 and func_name.len < 50 and std.ascii.isAlphabetic(func_name[0])) {
                    try functions.append(allocator, try allocator.dupe(u8, func_name));
                }
            }
        }
        i += 1;
    }
}

fn extractCommands(allocator: std.mem.Allocator, content: []const u8, commands: *std.ArrayList([]const u8)) !void {
    // Look for command patterns like "zig build", "npm install", etc.
    const common_commands = [_][]const u8{ "zig build", "npm install", "git commit", "git add", "docker run", "make", "cargo build" };

    for (common_commands) |cmd| {
        if (std.mem.indexOf(u8, content, cmd)) |pos| {
            // Extract the full command line
            var end = pos + cmd.len;
            while (end < content.len and content[end] != '\n' and content[end] != '\r') {
                end += 1;
            }

            const full_cmd = std.mem.trim(u8, content[pos..end], " \t");
            if (full_cmd.len > 0 and full_cmd.len < 200) {
                try commands.append(allocator, try allocator.dupe(u8, full_cmd));
            }
        }
    }
}

fn truncateToWordLimit(allocator: std.mem.Allocator, text: []const u8, word_limit: usize) ![]const u8 {
    var words: usize = 0;
    var i: usize = 0;
    var in_word = false;

    while (i < text.len and words < word_limit) {
        const is_word_char = std.ascii.isAlphanumeric(text[i]);
        if (is_word_char and !in_word) {
            words += 1;
            in_word = true;
        } else if (!is_word_char) {
            in_word = false;
        }
        i += 1;
    }

    if (words >= word_limit and i < text.len) {
        return try allocator.dupe(u8, text[0..i]);
    }
    return try allocator.dupe(u8, text);
}

fn generateTitle(allocator: std.mem.Allocator, goals: [][]const u8, current_task: ?[]const u8) ![]const u8 {
    if (current_task) |task| {
        // Use current task for title, limit to 7 words
        const words = std.mem.splitSequence(u8, task, " ");
        var word_count: usize = 0;
        var title_words = std.ArrayList([]const u8){};
        defer title_words.deinit(allocator);

        var iter = words;
        while (iter.next()) |word| {
            if (word_count >= 7) break;
            try title_words.append(allocator, word);
            word_count += 1;
        }

        return try std.mem.join(allocator, " ", title_words.items);
    }

    if (goals.len > 0) {
        // Use first goal for title
        const first_goal = goals[0];
        const words = std.mem.splitSequence(u8, first_goal, " ");
        var word_count: usize = 0;
        var title_words = std.ArrayList([]const u8){};
        defer title_words.deinit(allocator);

        var iter = words;
        while (iter.next()) |word| {
            if (word_count >= 7) break;
            try title_words.append(allocator, word);
            word_count += 1;
        }

        return try std.mem.join(allocator, " ", title_words.items);
    }

    return try allocator.dupe(u8, "Conversation summary");
}
