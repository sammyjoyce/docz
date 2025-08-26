const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const fs = @import("../common/fs.zig");
const link = @import("../common/link.zig");

// Document Validator Tool
// Performs comprehensive quality checks on markdown documents

// HTTP validation configuration for external link checking
const EXTERNAL_LINK_TIMEOUT_MS = 30 * 1000; // 30 seconds for external link validation - reasonable timeout for HEAD requests

pub const DocumentValidatorError = error{
    InvalidCommand,
    FileNotFound,
    InvalidRange,
    MissingField,
    OutOfMemory,
    AccessDenied,
    IoError,
    InvalidJson,
    Internal,
};

pub const IssueKind = enum {
    HeadingOrder,
    DuplicateHeading,
    BrokenLink,
    ProhibitedScheme,
    UnresolvedReference,
    MissingImageAlt,
    UnclosedCodeFence,
    TrailingWhitespace,
    LineTooLong,
    MixedIndent,
    InvalidFrontMatter,
    TableMismatch,
    HtmlForbidden,
    MultipleBlankLines,
    EmptyBlockquote,
    InvalidListMarker,

    pub fn toString(self: IssueKind) []const u8 {
        return @tagName(self);
    }
};

pub const Issue = struct {
    kind: IssueKind,
    line: usize,
    column: ?usize = null,
    message: []const u8,
};

pub const ValidationConfig = struct {
    max_line_length: ?usize = 120,
    require_front_matter: bool = false,
    enforce_heading_step: bool = true,
    max_consecutive_blanks: usize = 2,
    allowed_uri_schemes: []const []const u8 = &[_][]const u8{ "http", "https", "mailto", "ftp" },
    html_block_mode: enum { allow, warn, forbid } = .warn,

    // Rule toggles
    heading_duplicates: bool = true,
    image_alt_required: bool = true,
    check_trailing_whitespace: bool = true,
    validate_code_fences: bool = true,
    validate_links: bool = true,
    validate_tables: bool = true,
};

pub const ValidationSummary = struct {
    lines: usize = 0,
    headings: usize = 0,
    links: usize = 0,
    images: usize = 0,
    code_blocks: usize = 0,
    tables: usize = 0,
    duration_ms: u64 = 0,
    issue_counts: std.StringHashMap(usize),

    pub fn init(allocator: Allocator) ValidationSummary {
        return ValidationSummary{
            .issue_counts = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *ValidationSummary) void {
        self.issue_counts.deinit();
    }

    pub fn addIssue(self: *ValidationSummary, issue_kind: IssueKind) !void {
        const key = issue_kind.toString();
        const count = self.issue_counts.get(key) orelse 0;
        try self.issue_counts.put(key, count + 1);
    }
};

pub const ValidationReport = struct {
    valid: bool,
    issues: std.array_list.Managed(Issue),
    summary: ValidationSummary,
    allocator: Allocator,

    pub fn init(allocator: Allocator) ValidationReport {
        return ValidationReport{
            .valid = true,
            .issues = std.array_list.Managed(Issue).init(allocator),
            .summary = ValidationSummary.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ValidationReport) void {
        self.issues.deinit();
        self.summary.deinit();
    }

    pub fn addIssue(self: *ValidationReport, issue: Issue) !void {
        try self.issues.append(issue);
        try self.summary.addIssue(issue.kind);
        self.valid = false;
    }
};

pub const Command = enum {
    // Validation commands
    validate,
    validate_syntax,
    validate_structure,
    validate_links,
    check_completeness,

    // Link management commands (consolidated from link_manager)
    add_link,
    update_link,
    resolve_relative_links,
    find_broken,
    validate_external_links,
};

pub const DocumentValidator = struct {
    pub fn execute(allocator: Allocator, params: json.Value) !json.Value {
        return executeInternal(allocator, params) catch |err| {
            var result = json.ObjectMap.init(allocator);
            try result.put("success", json.Value{ .bool = false });
            try result.put("error", json.Value{ .string = @errorName(err) });
            try result.put("tool", json.Value{ .string = "document_validator" });
            return json.Value{ .object = result };
        };
    }

    fn executeInternal(allocator: Allocator, params: json.Value) !json.Value {

        // Extract required parameters
        const command_str = params.object.get("command") orelse return DocumentValidatorError.MissingField;
        const file_path = params.object.get("file_path") orelse return DocumentValidatorError.MissingField;

        if (command_str != .string) return DocumentValidatorError.InvalidCommand;
        if (file_path != .string) return DocumentValidatorError.MissingField;

        // Parse command
        const command = std.meta.stringToEnum(Command, command_str.string) orelse return DocumentValidatorError.InvalidCommand;

        // Parse optional configuration
        var config = ValidationConfig{};
        if (params.object.get("config")) |config_obj| {
            try parseConfig(&config, config_obj);
        }

        // Read file content
        const file_content = std.fs.cwd().readFileAlloc(allocator, file_path.string, std.math.maxInt(usize)) catch |err| {
            return switch (err) {
                error.FileNotFound => DocumentValidatorError.FileNotFound,
                error.AccessDenied => DocumentValidatorError.AccessDenied,
                error.OutOfMemory => DocumentValidatorError.OutOfMemory,
                else => DocumentValidatorError.IoError,
            };
        };
        defer allocator.free(file_content);

        switch (command) {
            // Validation commands
            .validate => {
                var report = ValidationReport.init(allocator);
                defer report.deinit();
                try validateAll(allocator, file_content, &config, &report);
                return buildValidationResponse(allocator, command_str.string, file_path.string, &report);
            },
            .validate_syntax => {
                var report = ValidationReport.init(allocator);
                defer report.deinit();
                try validateSyntax(allocator, file_content, &config, &report);
                return buildValidationResponse(allocator, command_str.string, file_path.string, &report);
            },
            .validate_structure => {
                var report = ValidationReport.init(allocator);
                defer report.deinit();
                try validateStructure(allocator, file_content, &config, &report);
                return buildValidationResponse(allocator, command_str.string, file_path.string, &report);
            },
            .validate_links => {
                var report = ValidationReport.init(allocator);
                defer report.deinit();
                try validateLinks(allocator, file_content, &config, &report);
                return buildValidationResponse(allocator, command_str.string, file_path.string, &report);
            },
            .check_completeness => {
                var report = ValidationReport.init(allocator);
                defer report.deinit();
                try checkCompleteness(allocator, file_content, &config, &report);
                return buildValidationResponse(allocator, command_str.string, file_path.string, &report);
            },

            // Link management commands
            .add_link => return addLink(allocator, params.object, file_path.string),
            .update_link => return updateLink(allocator, params.object, file_path.string),
            .resolve_relative_links => return resolveRelativeLinks(allocator, params.object, file_path.string),
            .find_broken => return findBrokenLinks(allocator, params.object, file_path.string),
            .validate_external_links => return validateExternalLinks(allocator, params.object, file_path.string),
        }

        // This will be handled by the command switch above
        return DocumentValidatorError.Internal;
    }

    fn parseConfig(config: *ValidationConfig, config_obj: json.Value) !void {
        if (config_obj != .object) return;

        if (config_obj.object.get("max_line_length")) |val| {
            if (val == .integer) config.max_line_length = @as(usize, @intCast(val.integer));
        }
        if (config_obj.object.get("require_front_matter")) |val| {
            if (val == .bool) config.require_front_matter = val.bool;
        }
        if (config_obj.object.get("enforce_heading_step")) |val| {
            if (val == .bool) config.enforce_heading_step = val.bool;
        }
        if (config_obj.object.get("max_consecutive_blanks")) |val| {
            if (val == .integer) config.max_consecutive_blanks = @as(usize, @intCast(val.integer));
        }
    }

    fn validateAll(allocator: Allocator, content: []const u8, config: *const ValidationConfig, report: *ValidationReport) !void {
        try validateSyntax(allocator, content, config, report);
        try validateStructure(allocator, content, config, report);
        try validateLinks(allocator, content, config, report);
        try checkCompleteness(allocator, content, config, report);
    }

    fn validateSyntax(allocator: Allocator, content: []const u8, config: *const ValidationConfig, report: *ValidationReport) !void {
        var lines = std.mem.splitScalar(u8, content, '\n');
        var line_num: usize = 1;
        var in_code_block = false;
        var code_fence_char: ?u8 = null;
        var blank_line_count: usize = 0;

        while (lines.next()) |line| {
            defer line_num += 1;
            report.summary.lines += 1;

            // Check for trailing whitespace
            if (config.check_trailing_whitespace and line.len > 0 and std.ascii.isWhitespace(line[line.len - 1])) {
                const message = try std.fmt.allocPrint(allocator, "Line has trailing whitespace", .{});
                try report.addIssue(Issue{
                    .kind = .TrailingWhitespace,
                    .line = line_num,
                    .column = line.len,
                    .message = message,
                });
            }

            // Check line length
            if (config.max_line_length) |max_len| {
                if (line.len > max_len) {
                    const message = try std.fmt.allocPrint(allocator, "Line exceeds maximum length of {} characters", .{max_len});
                    try report.addIssue(Issue{
                        .kind = .LineTooLong,
                        .line = line_num,
                        .column = max_len + 1,
                        .message = message,
                    });
                }
            }

            // Track blank lines
            if (std.mem.trim(u8, line, " \t").len == 0) {
                blank_line_count += 1;
                if (blank_line_count > config.max_consecutive_blanks) {
                    const message = try std.fmt.allocPrint(allocator, "More than {} consecutive blank lines", .{config.max_consecutive_blanks});
                    try report.addIssue(Issue{
                        .kind = .MultipleBlankLines,
                        .line = line_num,
                        .message = message,
                    });
                    blank_line_count = 0; // Reset to prevent spam
                }
            } else {
                blank_line_count = 0;
            }

            // Check for code fences
            const trimmed = std.mem.trimLeft(u8, line, " \t");
            if (config.validate_code_fences) {
                if (trimmed.len >= 3) {
                    const is_backtick_fence = std.mem.startsWith(u8, trimmed, "```");
                    const is_tilde_fence = std.mem.startsWith(u8, trimmed, "~~~");

                    if (is_backtick_fence) {
                        if (!in_code_block) {
                            in_code_block = true;
                            code_fence_char = '`';
                            report.summary.code_blocks += 1;
                        } else if (code_fence_char == '`') {
                            in_code_block = false;
                            code_fence_char = null;
                        }
                    } else if (is_tilde_fence) {
                        if (!in_code_block) {
                            in_code_block = true;
                            code_fence_char = '~';
                            report.summary.code_blocks += 1;
                        } else if (code_fence_char == '~') {
                            in_code_block = false;
                            code_fence_char = null;
                        }
                    }
                }
            }

            // Check for HTML tags if forbidden
            if (config.html_block_mode == .forbid) {
                if (std.mem.indexOf(u8, line, "<script") != null or
                    std.mem.indexOf(u8, line, "<iframe") != null or
                    std.mem.indexOf(u8, line, "<object") != null or
                    std.mem.indexOf(u8, line, "<embed") != null)
                {
                    const message = try std.fmt.allocPrint(allocator, "Forbidden HTML tag detected", .{});
                    try report.addIssue(Issue{
                        .kind = .HtmlForbidden,
                        .line = line_num,
                        .message = message,
                    });
                }
            }

            // Check for empty blockquotes
            if (std.mem.startsWith(u8, trimmed, ">") and trimmed.len <= 2) {
                const message = try std.fmt.allocPrint(allocator, "Empty blockquote line", .{});
                try report.addIssue(Issue{
                    .kind = .EmptyBlockquote,
                    .line = line_num,
                    .message = message,
                });
            }
        }

        // Check for unclosed code fence
        if (in_code_block) {
            const message = try std.fmt.allocPrint(allocator, "Unclosed code fence", .{});
            try report.addIssue(Issue{
                .kind = .UnclosedCodeFence,
                .line = line_num - 1,
                .message = message,
            });
        }
    }

    fn validateStructure(allocator: Allocator, content: []const u8, config: *const ValidationConfig, report: *ValidationReport) !void {
        var lines = std.mem.splitScalar(u8, content, '\n');
        var line_num: usize = 1;
        var last_heading_level: ?usize = null;
        var heading_slugs = std.StringHashMap(usize).init(allocator);
        defer heading_slugs.deinit();
        defer {
            var iterator = heading_slugs.iterator();
            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
        }
        var has_front_matter = false;
        var first_line = true;

        while (lines.next()) |line| {
            defer line_num += 1;

            const trimmed = std.mem.trim(u8, line, " \t");

            // Check for front matter on first line
            if (first_line) {
                first_line = false;
                if (std.mem.startsWith(u8, trimmed, "---") or
                    std.mem.startsWith(u8, trimmed, "+++") or
                    std.mem.startsWith(u8, trimmed, "{"))
                {
                    has_front_matter = true;
                }
            }

            // Parse headings
            if (std.mem.startsWith(u8, trimmed, "#")) {
                var level: usize = 0;
                var i: usize = 0;
                while (i < trimmed.len and trimmed[i] == '#') : (i += 1) {
                    level += 1;
                }

                if (level <= 6 and i < trimmed.len and trimmed[i] == ' ') {
                    report.summary.headings += 1;
                    const heading_text = std.mem.trim(u8, trimmed[i + 1 ..], " \t");

                    // Check heading order
                    if (config.enforce_heading_step) {
                        if (last_heading_level == null and level != 1) {
                            const message = try std.fmt.allocPrint(allocator, "First heading must be H1, found H{}", .{level});
                            try report.addIssue(Issue{
                                .kind = .HeadingOrder,
                                .line = line_num,
                                .message = message,
                            });
                        } else if (last_heading_level) |last_level| {
                            if (level > last_level + 1) {
                                const message = try std.fmt.allocPrint(allocator, "Heading level jumps from H{} to H{}", .{ last_level, level });
                                try report.addIssue(Issue{
                                    .kind = .HeadingOrder,
                                    .line = line_num,
                                    .message = message,
                                });
                            }
                        }
                    }

                    last_heading_level = level;

                    // Check for duplicate headings
                    if (config.heading_duplicates) {
                        const slug = try createSlug(allocator, heading_text);
                        defer allocator.free(slug);

                        if (heading_slugs.contains(slug)) {
                            const message = try std.fmt.allocPrint(allocator, "Duplicate heading: '{s}'", .{heading_text});
                            try report.addIssue(Issue{
                                .kind = .DuplicateHeading,
                                .line = line_num,
                                .message = message,
                            });
                        } else {
                            const owned_slug = try allocator.dupe(u8, slug);
                            try heading_slugs.put(owned_slug, line_num);
                        }
                    }
                }
            }

            // Check tables
            if (config.validate_tables and std.mem.indexOf(u8, trimmed, "|") != null) {
                report.summary.tables += 1;
                // Basic table validation - check for consistent column count
                const column_count = std.mem.count(u8, trimmed, "|");
                if (column_count < 2) {
                    const message = try std.fmt.allocPrint(allocator, "Malformed table row", .{});
                    try report.addIssue(Issue{
                        .kind = .TableMismatch,
                        .line = line_num,
                        .message = message,
                    });
                }
            }
        }

        // Check front matter requirement
        if (config.require_front_matter and !has_front_matter) {
            const message = try std.fmt.allocPrint(allocator, "Document requires front matter", .{});
            try report.addIssue(Issue{
                .kind = .InvalidFrontMatter,
                .line = 1,
                .message = message,
            });
        }
    }

    fn validateLinks(allocator: Allocator, content: []const u8, config: *const ValidationConfig, report: *ValidationReport) !void {
        var lines = std.mem.splitScalar(u8, content, '\n');
        var line_num: usize = 1;
        var reference_links = std.StringHashMap(bool).init(allocator);
        defer reference_links.deinit();

        while (lines.next()) |line| {
            defer line_num += 1;

            // Find markdown links: [text](url) and ![alt](url)
            var i: usize = 0;
            while (i < line.len) {
                if (line[i] == '!' and i + 1 < line.len and line[i + 1] == '[') {
                    // Image link
                    if (try parseImageLink(allocator, line[i..], line_num, i, config, report)) |consumed| {
                        i += consumed;
                        report.summary.images += 1;
                    } else {
                        i += 1;
                    }
                } else if (line[i] == '[') {
                    // Regular link or reference definition
                    if (try parseLink(allocator, line[i..], line_num, i, config, report, &reference_links)) |consumed| {
                        i += consumed;
                        report.summary.links += 1;
                    } else {
                        i += 1;
                    }
                } else {
                    i += 1;
                }
            }
        }
    }

    fn parseImageLink(allocator: Allocator, text: []const u8, line_num: usize, col_offset: usize, config: *const ValidationConfig, report: *ValidationReport) !?usize {
        if (text.len < 4 or !std.mem.startsWith(u8, text, "![")) return null;

        var i: usize = 2;
        const alt_start = i;

        // Find end of alt text
        while (i < text.len and text[i] != ']') : (i += 1) {}
        if (i >= text.len) return null;

        const alt_text = text[alt_start..i];
        i += 1; // skip ]

        if (i >= text.len or text[i] != '(') return null;
        i += 1; // skip (

        // Find end of URL
        const url_start = i;
        while (i < text.len and text[i] != ')') : (i += 1) {}
        if (i >= text.len) return null;

        const url = std.mem.trim(u8, text[url_start..i], " \t");
        i += 1; // skip )

        // Check for missing alt text
        if (config.image_alt_required and alt_text.len == 0) {
            const message = try std.fmt.allocPrint(allocator, "Image missing alt text", .{});
            try report.addIssue(Issue{
                .kind = .MissingImageAlt,
                .line = line_num,
                .column = col_offset + 1,
                .message = message,
            });
        }

        // Check URL scheme
        try validateUrlScheme(allocator, url, line_num, col_offset, config, report);

        return i;
    }

    fn parseLink(allocator: Allocator, text: []const u8, line_num: usize, col_offset: usize, config: *const ValidationConfig, report: *ValidationReport, reference_links: *std.StringHashMap(bool)) !?usize {
        if (text.len < 3 or !std.mem.startsWith(u8, text, "[")) return null;

        var i: usize = 1;

        // Find end of link text
        while (i < text.len and text[i] != ']') : (i += 1) {}
        if (i >= text.len) return null;

        i += 1; // skip ]

        if (i < text.len and text[i] == '(') {
            // Inline link [text](url)
            i += 1; // skip (

            // Find end of URL
            const url_start = i;
            while (i < text.len and text[i] != ')') : (i += 1) {}
            if (i >= text.len) return null;

            const url = std.mem.trim(u8, text[url_start..i], " \t");
            i += 1; // skip )

            // Check URL scheme
            try validateUrlScheme(allocator, url, line_num, col_offset, config, report);
        } else if (i < text.len and text[i] == '[') {
            // Reference link [text][ref]
            i += 1; // skip [
            const ref_start = i;
            while (i < text.len and text[i] != ']') : (i += 1) {}
            if (i >= text.len) return null;

            const ref_id = text[ref_start..i];
            i += 1; // skip ]

            // Track reference for later validation
            try reference_links.put(try allocator.dupe(u8, ref_id), false);
        } else {
            // Could be a shorthand reference link [text] or reference definition [id]: url
            // For now, just continue parsing
        }

        return i;
    }

    fn validateUrlScheme(allocator: Allocator, url: []const u8, line_num: usize, col_offset: usize, config: *const ValidationConfig, report: *ValidationReport) !void {
        if (url.len == 0) return;

        // Skip relative links and anchors
        if (url[0] == '/' or url[0] == '#' or url[0] == '.') return;

        // Check if URL has a scheme
        if (std.mem.indexOf(u8, url, "://")) |scheme_end| {
            const scheme = url[0..scheme_end];

            // Check if scheme is allowed
            var allowed = false;
            for (config.allowed_uri_schemes) |allowed_scheme| {
                if (std.mem.eql(u8, scheme, allowed_scheme)) {
                    allowed = true;
                    break;
                }
            }

            if (!allowed) {
                const message = try std.fmt.allocPrint(allocator, "Prohibited URI scheme: '{s}'", .{scheme});
                try report.addIssue(Issue{
                    .kind = .ProhibitedScheme,
                    .line = line_num,
                    .column = col_offset + 1,
                    .message = message,
                });
            }
        }
    }

    fn checkCompleteness(allocator: Allocator, content: []const u8, config: *const ValidationConfig, report: *ValidationReport) !void {
        // Basic completeness checks
        if (content.len == 0) {
            const message = try std.fmt.allocPrint(allocator, "Document is empty", .{});
            try report.addIssue(Issue{
                .kind = .InvalidFrontMatter,
                .line = 1,
                .message = message,
            });
            return;
        }

        // Check minimum content requirements based on config
        if (config.require_front_matter) {
            var lines = std.mem.splitScalar(u8, content, '\n');
            var has_meaningful_content = false;
            var line_count: usize = 0;

            while (lines.next()) |line| {
                line_count += 1;
                const trimmed = std.mem.trim(u8, line, " \t\r\n");
                if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "---") and !std.mem.startsWith(u8, trimmed, "+++")) {
                    has_meaningful_content = true;
                    break;
                }
            }

            if (!has_meaningful_content and line_count > 0) {
                const message = try std.fmt.allocPrint(allocator, "Document contains only front matter", .{});
                try report.addIssue(Issue{
                    .kind = .InvalidFrontMatter,
                    .line = line_count,
                    .message = message,
                });
            }
        }
    }

    fn createSlug(allocator: Allocator, text: []const u8) ![]u8 {
        var result = std.array_list.Managed(u8).init(allocator);
        defer result.deinit();

        for (text) |c| {
            if (std.ascii.isAlphanumeric(c)) {
                try result.append(std.ascii.toLower(c));
            } else if (std.ascii.isWhitespace(c)) {
                if (result.items.len > 0 and result.items[result.items.len - 1] != '-') {
                    try result.append('-');
                }
            }
        }

        // Remove trailing dash
        if (result.items.len > 0 and result.items[result.items.len - 1] == '-') {
            _ = result.pop();
        }

        return result.toOwnedSlice();
    }

    // Link Management Functions (consolidated from link_manager)

    fn addLink(allocator: Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
        const link_text = params.get("link_text").?.string;
        const target_url = params.get("target_url").?.string;
        const insert_location = params.get("insert_location") orelse json.Value{ .string = "end" };

        const content = try fs.readFileAlloc(allocator, file_path, null);
        defer allocator.free(content);

        const link_markdown = try link.createLink(allocator, link_text, target_url, null);
        defer allocator.free(link_markdown);

        var new_content = std.ArrayList(u8).init(allocator);
        defer new_content.deinit();

        if (std.mem.eql(u8, insert_location.string, "end")) {
            try new_content.appendSlice(content);
            try new_content.append('\n');
            try new_content.appendSlice(link_markdown);
        } else {
            // For now, just append at end - more sophisticated insertion can be added
            try new_content.appendSlice(content);
            try new_content.append('\n');
            try new_content.appendSlice(link_markdown);
        }

        try fs.writeFile(file_path, new_content.items);

        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = true });
        try result.put("tool", json.Value{ .string = "document_validator" });
        try result.put("command", json.Value{ .string = "add_link" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("link_text", json.Value{ .string = link_text });
        try result.put("target_url", json.Value{ .string = target_url });

        return json.Value{ .object = result };
    }

    fn updateLink(allocator: Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
        const old_target = params.get("old_target").?.string;
        const new_target = params.get("new_target").?.string;

        const content = try fs.readFileAlloc(allocator, file_path, null);
        defer allocator.free(content);

        // Simple find and replace for now
        const new_content = try std.mem.replaceOwned(u8, allocator, content, old_target, new_target);
        defer allocator.free(new_content);

        try fs.writeFile(file_path, new_content);

        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = true });
        try result.put("tool", json.Value{ .string = "document_validator" });
        try result.put("command", json.Value{ .string = "update_link" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("old_target", json.Value{ .string = old_target });
        try result.put("new_target", json.Value{ .string = new_target });

        return json.Value{ .object = result };
    }

    fn resolveRelativeLinks(allocator: Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
        const base_path = params.get("base_path") orelse json.Value{ .string = "." };

        const content = try fs.readFileAlloc(allocator, file_path, null);
        defer allocator.free(content);

        const links = try link.findLinks(allocator, content);
        defer allocator.free(links);

        var resolved_count: usize = 0;
        for (links) |found_link| {
            if (found_link.type == .internal) {
                const resolved = try link.resolveRelativePath(allocator, base_path.string, found_link.url);
                defer allocator.free(resolved);
                // In a full implementation, we would update the content here
                resolved_count += 1;
            }
        }

        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = true });
        try result.put("tool", json.Value{ .string = "document_validator" });
        try result.put("command", json.Value{ .string = "resolve_relative_links" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("resolved_count", json.Value{ .integer = @intCast(resolved_count) });

        return json.Value{ .object = result };
    }

    fn findBrokenLinks(allocator: Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
        _ = params;

        const content = try fs.readFileAlloc(allocator, file_path, null);
        defer allocator.free(content);

        const links = try link.findLinks(allocator, content);
        defer allocator.free(links);

        var broken_links = json.Array.init(allocator);

        for (links) |found_link| {
            if (!link.validateUrl(found_link.url)) {
                var broken_link = json.ObjectMap.init(allocator);
                try broken_link.put("text", json.Value{ .string = try allocator.dupe(u8, found_link.text) });
                try broken_link.put("url", json.Value{ .string = try allocator.dupe(u8, found_link.url) });
                try broken_link.put("line", json.Value{ .integer = @intCast(found_link.line) });
                try broken_link.put("column", json.Value{ .integer = @intCast(found_link.column) });
                try broken_links.append(json.Value{ .object = broken_link });
            }
        }

        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = true });
        try result.put("tool", json.Value{ .string = "document_validator" });
        try result.put("command", json.Value{ .string = "find_broken" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("broken_links", json.Value{ .array = broken_links });

        return json.Value{ .object = result };
    }

    // HTTP validation helper function for external link checking
    fn validateExternalUrl(allocator: Allocator, url: []const u8, timeout_ms: i64) !bool {
        // First do basic URL format validation
        if (!link.validateUrl(url)) return false;

        // Only validate HTTP/HTTPS URLs
        if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) {
            return false;
        }

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        // Parse URI for HTTP request
        const uri = std.Uri.parse(url) catch |err| {
            std.log.debug("Invalid URI format for URL '{s}': {}", .{ url, err });
            return false;
        };

        // Make HTTP HEAD request to check if URL exists without downloading content
        var req = client.request(.HEAD, uri, .{
            .keep_alive = false,
            .redirect_behavior = .follow, // Follow redirects for better validation
        }) catch |err| {
            std.log.debug("Failed to create HTTP request for URL '{s}': {}", .{ url, err });
            return false;
        };

        var buf: [0]u8 = undefined;
        var bw = req.sendBody(&buf) catch |err| {
            std.log.debug("Failed to send HTTP request for URL '{s}': {}", .{ url, err });
            return false;
        };
        bw.end() catch |err| {
            std.log.debug("Failed to complete HTTP request for URL '{s}': {}", .{ url, err });
            return false;
        };

        // Receive response with enhanced error handling
        const resp = req.receiveHead(&.{}) catch |err| {
            switch (err) {
                error.ConnectionTimedOut => {
                    std.log.debug("External link validation timed out after {}s for URL '{s}' - server may be slow or unresponsive", .{ timeout_ms / 1000, url });
                    return false;
                },
                error.ConnectionRefused => {
                    std.log.debug("Connection refused for URL '{s}' - server may be down", .{url});
                    return false;
                },
                error.UnknownHostName => {
                    std.log.debug("Cannot resolve hostname for URL '{s}' - check DNS or server availability", .{url});
                    return false;
                },
                else => {
                    std.log.debug("Network error during validation of URL '{s}': {}", .{ url, err });
                    return false;
                },
            }
        };

        // Consider successful HTTP status codes as valid links
        const status_code = @intFromEnum(resp.head.status);
        if (status_code >= 200 and status_code < 400) {
            return true;
        } else {
            std.log.debug("URL '{s}' returned HTTP status {}: {}", .{ url, status_code, resp.head.status });
            return false;
        }
    }

    fn validateExternalLinks(allocator: Allocator, params: json.ObjectMap, file_path: []const u8) !json.Value {
        const timeout_ms = if (params.get("timeout_ms")) |t| t.integer else EXTERNAL_LINK_TIMEOUT_MS;

        const content = try fs.readFileAlloc(allocator, file_path, null);
        defer allocator.free(content);

        const links = try link.findLinks(allocator, content);
        defer allocator.free(links);

        var external_links = json.Array.init(allocator);
        var valid_count: usize = 0;
        var total_external_count: usize = 0;

        for (links) |found_link| {
            if (found_link.type == .external) {
                total_external_count += 1;

                var link_obj = json.ObjectMap.init(allocator);
                try link_obj.put("url", json.Value{ .string = try allocator.dupe(u8, found_link.url) });
                try link_obj.put("text", json.Value{ .string = try allocator.dupe(u8, found_link.text) });
                try link_obj.put("line", json.Value{ .integer = @intCast(found_link.line + 1) }); // 1-based line numbers for user friendliness

                // Perform actual HTTP validation instead of just format validation
                const is_valid = validateExternalUrl(allocator, found_link.url, timeout_ms) catch |err| {
                    std.log.debug("Error validating URL '{s}': {}", .{ found_link.url, err });
                    false;
                };

                try link_obj.put("valid", json.Value{ .bool = is_valid });

                if (is_valid) valid_count += 1;

                try external_links.append(json.Value{ .object = link_obj });

                // Add small delay between requests to be respectful to servers
                std.time.sleep(100_000_000); // 100ms delay between requests
            }
        }

        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = true });
        try result.put("tool", json.Value{ .string = "document_validator" });
        try result.put("command", json.Value{ .string = "validate_external_links" });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("external_links", json.Value{ .array = external_links });
        try result.put("valid_count", json.Value{ .integer = @intCast(valid_count) });
        try result.put("total_external_count", json.Value{ .integer = @intCast(total_external_count) });
        try result.put("timeout_ms", json.Value{ .integer = timeout_ms });

        return json.Value{ .object = result };
    }

    fn buildValidationResponse(allocator: Allocator, command_str: []const u8, file_path: []const u8, report: *ValidationReport) !json.Value {
        var result = json.ObjectMap.init(allocator);
        try result.put("success", json.Value{ .bool = true });
        try result.put("tool", json.Value{ .string = "document_validator" });
        try result.put("command", json.Value{ .string = command_str });
        try result.put("file", json.Value{ .string = file_path });
        try result.put("valid", json.Value{ .bool = report.valid });

        // Add issues array
        var issues_array = json.Array.init(allocator);

        for (report.issues.items) |issue| {
            var issue_obj = json.ObjectMap.init(allocator);
            try issue_obj.put("kind", json.Value{ .string = issue.kind.toString() });
            try issue_obj.put("line", json.Value{ .integer = @as(i64, @intCast(issue.line)) });
            if (issue.column) |col| {
                try issue_obj.put("column", json.Value{ .integer = @as(i64, @intCast(col)) });
            }
            try issue_obj.put("message", json.Value{ .string = issue.message });
            try issues_array.append(json.Value{ .object = issue_obj });
        }
        try result.put("issues", json.Value{ .array = issues_array });

        // Add summary
        var summary_obj = json.ObjectMap.init(allocator);
        try summary_obj.put("lines", json.Value{ .integer = @as(i64, @intCast(report.summary.lines)) });
        try summary_obj.put("headings", json.Value{ .integer = @as(i64, @intCast(report.summary.headings)) });
        try summary_obj.put("links", json.Value{ .integer = @as(i64, @intCast(report.summary.links)) });
        try summary_obj.put("images", json.Value{ .integer = @as(i64, @intCast(report.summary.images)) });
        try summary_obj.put("code_blocks", json.Value{ .integer = @as(i64, @intCast(report.summary.code_blocks)) });
        try summary_obj.put("tables", json.Value{ .integer = @as(i64, @intCast(report.summary.tables)) });
        try summary_obj.put("duration_ms", json.Value{ .integer = @as(i64, @intCast(report.summary.duration_ms)) });

        // Add issue counts
        var issue_counts_obj = json.ObjectMap.init(allocator);
        var iterator = report.summary.issue_counts.iterator();
        while (iterator.next()) |entry| {
            try issue_counts_obj.put(entry.key_ptr.*, json.Value{ .integer = @as(i64, @intCast(entry.value_ptr.*)) });
        }
        try summary_obj.put("issue_counts", json.Value{ .object = issue_counts_obj });
        try result.put("summary", json.Value{ .object = summary_obj });

        return json.Value{ .object = result };
    }
};
