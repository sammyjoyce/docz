const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Template Processing Tool - Handles ${variable} interpolation with escape sequences
pub const TemplateProcessingTool = struct {
    const Self = @This();

    /// Configuration options for template processing
    pub const ProcessOptions = struct {
        /// Enable escape sequence processing (\n, \t, \\, \$, \{, \}, \`)
        process_escapes: bool = true,

        /// Trim whitespace around variable names
        trim_whitespace: bool = true,

        /// Preserve missing variables as ${var} instead of empty string
        preserve_missing: bool = false,

        /// Remove leading/trailing whitespace from final result
        trim_result: bool = false,

        pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
            return field_name;
        }
    };

    /// Request structure for template processing
    pub const TemplateRequest = struct {
        /// The template string containing ${variable} placeholders
        template: []const u8,

        /// Variables for substitution (JSON object map)
        variables: ?std.json.ObjectMap = null,

        /// Processing options
        options: ?ProcessOptions = null,

        pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
            return field_name;
        }
    };

    /// Response structure for template processing
    pub const TemplateResponse = struct {
        success: bool,
        result: []const u8 = "",
        error_message: ?[]const u8 = null,
        variables_used: std.ArrayList([]const u8),
        variables_missing: std.ArrayList([]const u8),

        pub fn jsonFieldName(comptime field_name: []const u8) []const u8 {
            return field_name;
        }

        pub fn deinit(self: *TemplateResponse, allocator: std.mem.Allocator) void {
            self.variables_used.deinit(allocator);
            self.variables_missing.deinit(allocator);
            if (self.result.len > 0) {
                allocator.free(self.result);
            }
            if (self.error_message) |msg| {
                allocator.free(msg);
            }
        }
    };

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Process template with ${variable} interpolation
    pub fn processTemplate(self: Self, request: TemplateRequest) !TemplateResponse {
        const options = request.options orelse ProcessOptions{};

        var result = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer result.deinit(self.allocator);

        var variables_used = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        var variables_missing = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);

        var i: usize = 0;
        while (i < request.template.len) {
            if (i + 1 < request.template.len and request.template[i] == '$' and request.template[i + 1] == '{') {
                try self.processVariable(&result, request.template, &i, request.variables, options, &variables_used, &variables_missing);
            } else if (request.template[i] == '\\') {
                try self.processEscape(&result, request.template, &i, options);
            } else {
                try result.append(self.allocator, request.template[i]);
                i += 1;
            }
        }

        var final_result = try result.toOwnedSlice(self.allocator);

        // Trim final result if requested
        if (options.trim_result) {
            const trimmed = std.mem.trim(u8, final_result, " \t\n\r");
            if (trimmed.len != final_result.len) {
                const new_result = try self.allocator.dupe(u8, trimmed);
                self.allocator.free(final_result);
                final_result = new_result;
            }
        }

        return TemplateResponse{
            .success = true,
            .result = final_result,
            .error_message = null,
            .variables_used = variables_used,
            .variables_missing = variables_missing,
        };
    }

    /// Process ${variable} interpolation
    fn processVariable(self: Self, result: *std.ArrayList(u8), template: []const u8, i: *usize, variables: ?std.json.ObjectMap, options: ProcessOptions, variables_used: *std.ArrayList([]const u8), variables_missing: *std.ArrayList([]const u8)) !void {
        i.* += 2; // Skip ${
        const start = i.*;

        // Find closing }
        while (i.* < template.len and template[i.*] != '}') {
            i.* += 1;
        }

        if (i.* >= template.len) {
            // No closing } found - treat as literal
            try result.appendSlice(self.allocator, "${");
            return;
        }

        var var_name = template[start..i.*];
        if (options.trim_whitespace) {
            var_name = std.mem.trim(u8, var_name, " \t\n\r");
        }

        if (variables) |vars| {
            if (vars.get(var_name)) |value| {
                // Record that we used this variable
                const var_copy = try self.allocator.dupe(u8, var_name);
                try variables_used.append(self.allocator, var_copy);

                // Convert value to string and append
                switch (value) {
                    .string => |s| try result.appendSlice(self.allocator, s),
                    .integer => |n| {
                        var buf: [32]u8 = undefined;
                        const str = std.fmt.bufPrint(&buf, "{}", .{n}) catch "[integer]";
                        try result.appendSlice(self.allocator, str);
                    },
                    .float => |n| {
                        var buf: [32]u8 = undefined;
                        const str = std.fmt.bufPrint(&buf, "{d}", .{n}) catch "[float]";
                        try result.appendSlice(self.allocator, str);
                    },
                    .number_string => |s| try result.appendSlice(self.allocator, s),
                    .bool => |b| try result.appendSlice(self.allocator, if (b) "true" else "false"),
                    .null => {}, // append nothing for null
                    else => try result.appendSlice(self.allocator, "[object]"),
                }
            } else {
                // Variable not found
                const var_copy = try self.allocator.dupe(u8, var_name);
                try variables_missing.append(self.allocator, var_copy);

                if (options.preserve_missing) {
                    try result.appendSlice(self.allocator, "${");
                    try result.appendSlice(self.allocator, var_name);
                    try result.append(self.allocator, '}');
                }
                // else append nothing (empty substitution)
            }
        } else {
            // No variables provided
            const var_copy = try self.allocator.dupe(u8, var_name);
            try variables_missing.append(self.allocator, var_copy);

            if (options.preserve_missing) {
                try result.appendSlice(self.allocator, "${");
                try result.appendSlice(self.allocator, var_name);
                try result.append(self.allocator, '}');
            }
        }

        i.* += 1; // Skip }
    }

    /// Process escape sequences
    fn processEscape(self: Self, result: *std.ArrayList(u8), template: []const u8, i: *usize, options: ProcessOptions) !void {
        if (!options.process_escapes) {
            try result.append(self.allocator, template[i.*]);
            i.* += 1;
            return;
        }

        i.* += 1; // Skip \
        if (i.* >= template.len) {
            try result.append(self.allocator, '\\');
            return;
        }

        switch (template[i.*]) {
            'n' => try result.append(self.allocator, '\n'),
            't' => try result.append(self.allocator, '\t'),
            'r' => try result.append(self.allocator, '\r'),
            '\\' => try result.append(self.allocator, '\\'),
            '$' => try result.append(self.allocator, '$'),
            '{' => try result.append(self.allocator, '{'),
            '}' => try result.append(self.allocator, '}'),
            '`' => try result.append(self.allocator, '`'),
            else => {
                // Unrecognized escape, keep the backslash and character
                try result.append(self.allocator, '\\');
                try result.append(self.allocator, template[i.*]);
            },
        }
        i.* += 1;
    }

    /// Main tool execution function
    pub fn execute(self: Self, json_input: std.json.Value) !std.json.Value {
        // Parse request
        const RequestMapper = toolsMod.JsonReflector.mapper(TemplateRequest);
        const request_parsed = RequestMapper.fromJson(self.allocator, json_input) catch |err| {
            var error_response = TemplateResponse{
                .success = false,
                .result = "",
                .error_message = try std.fmt.allocPrint(self.allocator, "Invalid request format: {}", .{err}),
                .variables_used = std.ArrayList([]const u8){},
                .variables_missing = std.ArrayList([]const u8){},
            };
            defer error_response.deinit(self.allocator);
            return toolsMod.JsonReflector.mapper(TemplateResponse).toJsonValue(self.allocator, error_response);
        };
        defer request_parsed.deinit();

        // Process template
        var response = self.processTemplate(request_parsed.value) catch |err| {
            var error_response = TemplateResponse{
                .success = false,
                .result = "",
                .error_message = try std.fmt.allocPrint(self.allocator, "Template processing failed: {}", .{err}),
                .variables_used = std.ArrayList([]const u8){},
                .variables_missing = std.ArrayList([]const u8){},
            };
            defer error_response.deinit(self.allocator);
            return toolsMod.JsonReflector.mapper(TemplateResponse).toJsonValue(self.allocator, error_response);
        };

        defer response.deinit(self.allocator);
        return toolsMod.JsonReflector.mapper(TemplateResponse).toJsonValue(self.allocator, response);
    }
};

/// Create and execute template processing tool
pub fn executeTemplateProcessing(allocator: std.mem.Allocator, json_input: std.json.Value) toolsMod.ToolError!std.json.Value {
    var tool = TemplateProcessingTool.init(allocator);
    return tool.execute(json_input) catch |err| switch (err) {
        error.OutOfMemory => toolsMod.ToolError.OutOfMemory,
        else => toolsMod.ToolError.ExecutionFailed,
    };
}
