const std = @import("std");
const toolsMod = @import("foundation").tools;
const core_engine = @import("core_engine");

const DirectLLMRequest = struct {
    template: []const u8,
    variables: ?std.json.ObjectMap = null,
    model_preference: ?[]const u8 = null,

    pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
        return field_name;
    }
};

const ModelInfo = struct {
    id: []const u8,
    provider: []const u8,
    description: []const u8,
    available: bool,
    capabilities: []const []const u8,

    pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
        return field_name;
    }
};

const DirectLLMResponse = struct {
    success: bool,
    tool: []const u8 = "direct_llm_models",
    available_models: []ModelInfo = &.{},
    processed_template: []const u8 = "",
    recommended_model: []const u8 = "",
    error_message: ?[]const u8 = null,

    pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
        return field_name;
    }
};

pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = toolsMod.JsonReflector.mapper(DirectLLMResponse);
        const response = DirectLLMResponse{
            .success = false,
            .error_message = @errorName(err),
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    const RequestMapper = toolsMod.JsonReflector.mapper(DirectLLMRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    // Get available models
    const models = try getAvailableModels(allocator);

    // Process the template with variables
    const processed_template = if (request.value.variables != null)
        try processTemplate(allocator, request.value.template, request.value.variables.?)
    else
        try allocator.dupe(u8, request.value.template);

    // Recommend best model for the task
    const recommended_model = try recommendModel(allocator, request.value, processed_template);

    const response = DirectLLMResponse{
        .success = true,
        .available_models = models,
        .processed_template = processed_template,
        .recommended_model = recommended_model,
    };

    const ResponseMapper = toolsMod.JsonReflector.mapper(DirectLLMResponse);
    return ResponseMapper.toJsonValue(allocator, response);
}

fn getAvailableModels(allocator: std.mem.Allocator) ![]ModelInfo {
    var models = try std.ArrayList(ModelInfo).initCapacity(allocator, 0);
    defer models.deinit(allocator);

    // Anthropic models
    try models.append(allocator, .{
        .id = "claude-3-5-sonnet-20241022",
        .provider = "anthropic",
        .description = "Most capable model for complex reasoning and coding",
        .available = true,
        .capabilities = &[_][]const u8{ "coding", "analysis", "reasoning", "writing" },
    });

    try models.append(allocator, .{
        .id = "claude-3-5-haiku-20241022",
        .provider = "anthropic",
        .description = "Fast and efficient for quick tasks",
        .available = true,
        .capabilities = &[_][]const u8{ "coding", "analysis", "writing" },
    });

    try models.append(allocator, .{
        .id = "claude-3-opus-20240229",
        .provider = "anthropic",
        .description = "Highest capability for most complex tasks",
        .available = true,
        .capabilities = &[_][]const u8{ "coding", "analysis", "reasoning", "writing", "research" },
    });

    // OpenAI models
    try models.append(allocator, .{
        .id = "gpt-4o",
        .provider = "openai",
        .description = "Advanced multimodal model with vision capabilities",
        .available = true,
        .capabilities = &[_][]const u8{ "coding", "analysis", "vision", "writing" },
    });

    try models.append(allocator, .{
        .id = "gpt-4o-mini",
        .provider = "openai",
        .description = "Cost-effective model for simple tasks",
        .available = true,
        .capabilities = &[_][]const u8{ "coding", "analysis", "writing" },
    });

    try models.append(allocator, .{
        .id = "o1-preview",
        .provider = "openai",
        .description = "Advanced reasoning model for complex problems",
        .available = true,
        .capabilities = &[_][]const u8{ "reasoning", "analysis", "problem-solving" },
    });

    // Google models
    try models.append(allocator, .{
        .id = "gemini-2.0-flash-exp",
        .provider = "google",
        .description = "Fast experimental model with multimodal capabilities",
        .available = true,
        .capabilities = &[_][]const u8{ "coding", "analysis", "multimodal" },
    });

    try models.append(allocator, .{
        .id = "gemini-1.5-pro",
        .provider = "google",
        .description = "Advanced model with large context window",
        .available = true,
        .capabilities = &[_][]const u8{ "coding", "analysis", "long-context" },
    });

    return try models.toOwnedSlice(allocator);
}

fn processTemplate(allocator: std.mem.Allocator, template: []const u8, variables: std.json.ObjectMap) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < template.len) {
        if (i < template.len - 1 and template[i] == '{' and template[i + 1] == '{') {
            // Find the end of the variable placeholder
            var end: usize = i + 2;
            while (end < template.len - 1) {
                if (template[end] == '}' and template[end + 1] == '}') {
                    break;
                }
                end += 1;
            }

            if (end < template.len - 1) {
                // Extract variable name
                const var_name = template[i + 2 .. end];
                const trimmed_name = std.mem.trim(u8, var_name, " \t\n\r");

                // Look for variable value
                if (variables.get(trimmed_name)) |value| {
                    switch (value) {
                        .string => |str| try result.appendSlice(allocator, str),
                        .integer => |int| {
                            const int_str = try std.fmt.allocPrint(allocator, "{d}", .{int});
                            try result.appendSlice(allocator, int_str);
                        },
                        .bool => |b| try result.appendSlice(allocator, if (b) "true" else "false"),
                        else => {
                            const formatted = try std.fmt.allocPrint(allocator, "{{{{{s}}}}}", .{trimmed_name});
                            defer allocator.free(formatted);
                            try result.appendSlice(allocator, formatted);
                        },
                    }
                } else {
                    // Variable not found, keep the placeholder
                    const formatted = try std.fmt.allocPrint(allocator, "{{{{{s}}}}}", .{trimmed_name});
                    defer allocator.free(formatted);
                    try result.appendSlice(allocator, formatted);
                }

                i = end + 2;
            } else {
                try result.append(allocator, template[i]);
                i += 1;
            }
        } else {
            try result.append(allocator, template[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice(allocator);
}

fn recommendModel(allocator: std.mem.Allocator, request: DirectLLMRequest, processed_template: []const u8) ![]const u8 {
    _ = processed_template; // Could analyze template complexity for better recommendations

    // If user specified a preference, use it
    if (request.model_preference) |pref| {
        return try allocator.dupe(u8, pref);
    }

    // Analyze the template/task to recommend best model
    const template_lower = try std.ascii.allocLowerString(allocator, request.template);
    defer allocator.free(template_lower);

    // Complex reasoning tasks
    if (std.mem.containsAtLeast(u8, template_lower, 1, "analyze") or
        std.mem.containsAtLeast(u8, template_lower, 1, "reasoning") or
        std.mem.containsAtLeast(u8, template_lower, 1, "complex"))
    {
        return try allocator.dupe(u8, "claude-3-opus-20240229");
    }

    // Coding tasks
    if (std.mem.containsAtLeast(u8, template_lower, 1, "code") or
        std.mem.containsAtLeast(u8, template_lower, 1, "implement") or
        std.mem.containsAtLeast(u8, template_lower, 1, "debug"))
    {
        return try allocator.dupe(u8, "claude-3-5-sonnet-20241022");
    }

    // Quick/simple tasks
    if (std.mem.containsAtLeast(u8, template_lower, 1, "quick") or
        std.mem.containsAtLeast(u8, template_lower, 1, "simple") or
        std.mem.containsAtLeast(u8, template_lower, 1, "summary"))
    {
        return try allocator.dupe(u8, "claude-3-5-haiku-20241022");
    }

    // Default to balanced option
    return try allocator.dupe(u8, "claude-3-5-sonnet-20241022");
}
