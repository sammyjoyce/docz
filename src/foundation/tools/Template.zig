//! Shared string template engine for variable interpolation.
//! Supports both `${var}` and `{var}` styles with configurable options
//! and optional escape processing.

const std = @import("std");

pub const ProcessOptions = struct {
    process_escapes: bool = true,
    trim_whitespace: bool = true,
    preserve_missing: bool = false,
    trim_result: bool = false,
    allow_dollar_curly: bool = true,
    allow_single_curly: bool = true,
};

pub const TemplateResult = struct {
    result: []u8,
    variables_used: [][]const u8,
    variables_missing: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TemplateResult) void {
        for (self.variables_used) |v| self.allocator.free(v);
        for (self.variables_missing) |v| self.allocator.free(v);
        self.allocator.free(self.variables_used);
        self.allocator.free(self.variables_missing);
        self.allocator.free(self.result);
    }
};

/// Resolver interface for dynamic variable sources
pub const VarResolver = struct {
    ctx: ?*anyopaque = null,
    get: *const fn (ctx: ?*anyopaque, name: []const u8, allocator: std.mem.Allocator) ?[]u8,
};

/// Process a template using a JSON ObjectMap of variables.
/// Values may be string, integer, float, bool, or null.
pub fn processWithMap(
    allocator: std.mem.Allocator,
    template: []const u8,
    variables: ?std.json.ObjectMap,
    options: ProcessOptions,
) !TemplateResult {
    const resolver = VarResolver{
        .ctx = @ptrFromInt(0),
        .get = struct {
            fn f(ctx: ?*anyopaque, name: []const u8, a: std.mem.Allocator) ?[]u8 {
                _ = ctx;
                // When no variables provided, return null
                const vars = @as(?*std.json.ObjectMap, @ptrFromInt(0));
                _ = vars;
                return null;
            }
        }.f,
    };
    // Delegate to the generic implementation with a map-aware getter
    return processInternal(allocator, template, variables, resolver, options);
}

/// Process a template using a callback resolver for variable names.
pub fn processWithResolver(
    allocator: std.mem.Allocator,
    template: []const u8,
    resolver: VarResolver,
    options: ProcessOptions,
) !TemplateResult {
    return processInternal(allocator, template, null, resolver, options);
}

fn processInternal(
    allocator: std.mem.Allocator,
    template: []const u8,
    variables: ?std.json.ObjectMap,
    resolver: VarResolver,
    options: ProcessOptions,
) !TemplateResult {
    var out = std.ArrayList(u8).init(allocator);
    var used = std.ArrayList([]const u8).init(allocator);
    var missing = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (used.items) |v| allocator.free(v);
        for (missing.items) |v| allocator.free(v);
        used.deinit();
        missing.deinit();
        out.deinit();
    }

    var i: usize = 0;
    while (i < template.len) {
        const c = template[i];

        // Escapes
        if (c == '\\' and options.process_escapes) {
            if (i + 1 >= template.len) {
                try out.append('\\');
                break;
            }
            const n = template[i + 1];
            switch (n) {
                'n' => try out.append('\n'),
                't' => try out.append('\t'),
                'r' => try out.append('\r'),
                '\\' => try out.append('\\'),
                '$' => try out.append('$'),
                '{' => try out.append('{'),
                '}' => try out.append('}'),
                '`' => try out.append('`'),
                else => {
                    // Keep sequence as-is if unknown
                    try out.append('\\');
                    try out.append(n);
                },
            }
            i += 2;
            continue;
        }

        // ${var}
        if (options.allow_dollar_curly and c == '$' and i + 1 < template.len and template[i + 1] == '{') {
            i += 2; // skip ${
            const name = parseVarName(template, &i, options);
            try handleVar(allocator, name, variables, resolver, options, &out, &used, &missing);
            i += 1; // skip }
            continue;
        }

        // {var}
        if (options.allow_single_curly and c == '{') {
            i += 1; // skip {
            const name = parseVarName(template, &i, options);
            try handleVar(allocator, name, variables, resolver, options, &out, &used, &missing);
            i += 1; // skip }
            continue;
        }

        try out.append(c);
        i += 1;
    }

    var result = try out.toOwnedSlice();
    if (options.trim_result) {
        const t = std.mem.trim(u8, result, " \t\n\r");
        if (t.len != result.len) {
            const dup = try allocator.dupe(u8, t);
            allocator.free(result);
            result = dup;
        }
    }

    return TemplateResult{
        .result = result,
        .variables_used = try used.toOwnedSlice(),
        .variables_missing = try missing.toOwnedSlice(),
        .allocator = allocator,
    };
}

fn parseVarName(template: []const u8, i: *usize, options: ProcessOptions) []const u8 {
    const start = i.*;
    var j = start;
    while (j < template.len and template[j] != '}') : (j += 1) {}
    const raw = template[start..@min(j, template.len)];
    if (options.trim_whitespace) return std.mem.trim(u8, raw, " \t\n\r");
    return raw;
}

fn handleVar(
    allocator: std.mem.Allocator,
    name: []const u8,
    variables: ?std.json.ObjectMap,
    resolver: VarResolver,
    options: ProcessOptions,
    out: *std.ArrayList(u8),
    used: *std.ArrayList([]const u8),
    missing: *std.ArrayList([]const u8),
) !void {
    if (name.len == 0) return;

    // Map-based resolution first when provided
    if (variables) |vars| {
        if (vars.get(name)) |val| {
            try used.append(try allocator.dupe(u8, name));
            try appendJsonValue(allocator, out, val);
            return;
        }
    }

    // Fallback to resolver
    if (resolver.get != undefined) {
        if (resolver.get(resolver.ctx, name, allocator)) |owned| {
            defer allocator.free(owned);
            try used.append(try allocator.dupe(u8, name));
            try out.appendSlice(owned);
            return;
        }
    }

    // Missing
    try missing.append(try allocator.dupe(u8, name));
    if (options.preserve_missing) {
        try out.appendSlice("${");
        try out.appendSlice(name);
        try out.append('}');
    }
}

fn appendJsonValue(allocator: std.mem.Allocator, out: *std.ArrayList(u8), v: std.json.Value) !void {
    switch (v) {
        .string => |s| try out.appendSlice(s),
        .integer => |n| {
            var buf: [64]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{d}", .{n});
            try out.appendSlice(s);
        },
        .float => |n| {
            var buf: [64]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{d}", .{n});
            try out.appendSlice(s);
        },
        .number_string => |s| try out.appendSlice(s),
        .bool => |b| try out.appendSlice(if (b) "true" else "false"),
        .null => {},
        else => try out.appendSlice("[object]"),
    }
}
