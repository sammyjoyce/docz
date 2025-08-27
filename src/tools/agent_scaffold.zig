//! Agent scaffolding tool for creating new agents from template.
//!
//! This tool provides functionality to create new agent directories with
//! proper structure, configuration files, and template variable replacement.

const std = @import("std");
const fs = std.fs;

/// ScaffoldAgentError represents errors that can occur during agent scaffolding
pub const ScaffoldAgentError = error{
    AgentAlreadyExists,
    TemplateNotFound,
    DirectoryCreationFailed,
    FileCopyFailed,
    TemplateReplacementFailed,
    InvalidAgentName,
    OutOfMemory,
} || std.fs.File.OpenError || std.fs.File.WriteError;

/// ScaffoldAgentOptions contains configuration for agent scaffolding
pub const ScaffoldAgentOptions = struct {
    agent_name: []const u8,
    description: []const u8,
    author: []const u8,
    allocator: std.mem.Allocator,
};

/// scaffoldAgent creates a new agent directory structure from the template
///
/// This function:
/// 1. Validates the agent name and checks for existing directories
/// 2. Creates the agent directory structure
/// 3. Copies template files with placeholder replacement
/// 4. Generates agent-specific configuration files
/// 5. Creates subdirectories (tools/, common/, examples/)
///
/// Parameters:
/// - options: ScaffoldAgentOptions containing agent details and allocator
///
/// Returns: void on success, error on failure
pub fn scaffoldAgent(options: ScaffoldAgentOptions) anyerror!void {
    const allocator = options.allocator;
    const agent_name = options.agent_name;
    const description = options.description;
    const author = options.author;

    // Validate agent name
    if (!isValidAgentName(agent_name)) {
        return ScaffoldAgentError.InvalidAgentName;
    }

    // Check if agent already exists
    const agent_path = try std.fs.path.join(allocator, &.{ "agents", agent_name });
    defer allocator.free(agent_path);

    // Check if agent already exists
    if (std.fs.cwd().openDir(agent_path, .{})) |_| {
        return ScaffoldAgentError.AgentAlreadyExists;
    } else |_| {
        // Directory doesn't exist, which is what we want
    }

    // Check if template exists
    const template_path = "agents/_template";
    if (std.fs.cwd().openDir(template_path, .{})) |_| {
        // Template exists
    } else |_| {
        return ScaffoldAgentError.TemplateNotFound;
    }

    // Create agent directory
    std.fs.cwd().makeDir(agent_path) catch |err| switch (err) {
        error.PathAlreadyExists => {
            // Directory already exists, which we already checked for
            return ScaffoldAgentError.AgentAlreadyExists;
        },
        else => return ScaffoldAgentError.DirectoryCreationFailed,
    };

    // Create subdirectories
    const subdirs = [_][]const u8{ "tools", "common", "examples" };
    for (subdirs) |subdir| {
        const subdir_path = try std.fs.path.join(allocator, &.{ agent_path, subdir });
        defer allocator.free(subdir_path);
        std.fs.cwd().makeDir(subdir_path) catch |err| switch (err) {
            error.PathAlreadyExists => {
                // Subdirectory already exists, continue
            },
            else => return ScaffoldAgentError.DirectoryCreationFailed,
        };
    }

    // Copy and process template files
    try copyTemplateFiles(allocator, template_path, agent_path, agent_name, description, author);

    // Generate agent-specific files
    try generateConfigZon(allocator, agent_path, agent_name, description, author);
    try generateAgentManifestZon(allocator, agent_path, agent_name, description, author);

    std.debug.print("Successfully created agent '{s}' at {s}/\n", .{ agent_name, agent_path });
}

/// isValidAgentName validates that the agent name follows naming conventions
fn isValidAgentName(name: []const u8) bool {
    if (name.len == 0 or name.len > 50) return false;

    // Must start with letter or underscore
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;

    // Can contain letters, numbers, underscores, and hyphens
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') return false;
    }

    // Cannot be reserved names
    const reserved = [_][]const u8{ "_template", "core", "shared", "tools" };
    for (reserved) |reserved_name| {
        if (std.mem.eql(u8, name, reserved_name)) return false;
    }

    return true;
}

/// copyTemplateFiles copies template files with placeholder replacement
fn copyTemplateFiles(
    allocator: std.mem.Allocator,
    template_path: []const u8,
    agent_path: []const u8,
    agent_name: []const u8,
    description: []const u8,
    author: []const u8,
) anyerror!void {
    const template_files = [_][]const u8{
        "main.zig",
        "agent.zig",
        "spec.zig",
        "system_prompt.txt",
        "README.md",
        "tools/mod.zig",
        "tools/example_tool.zig",
    };

    for (template_files) |template_file| {
        const src_path = try std.fs.path.join(allocator, &.{ template_path, template_file });
        defer allocator.free(src_path);

        const dst_path = try std.fs.path.join(allocator, &.{ agent_path, template_file });
        defer allocator.free(dst_path);

        // Read template file
        const src_file = try std.fs.cwd().openFile(src_path, .{});
        defer src_file.close();
        const template_content = try src_file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(template_content);

        // Process template variables
        const processed_content = try processTemplateVariables(
            allocator,
            template_content,
            agent_name,
            description,
            author,
        );
        defer allocator.free(processed_content);

        // Write processed content to destination
        const file = try std.fs.cwd().createFile(dst_path, .{});
        defer file.close();
        try file.writeAll(processed_content);
    }
}

/// processTemplateVariables replaces template placeholders in file content
fn processTemplateVariables(
    allocator: std.mem.Allocator,
    content: []const u8,
    agent_name: []const u8,
    description: []const u8,
    author: []const u8,
) anyerror![]const u8 {
    var result = std.ArrayList(u8).initCapacity(allocator, content.len) catch return ScaffoldAgentError.OutOfMemory;
    defer result.deinit(allocator);

    // Convert agent name to different cases
    const agent_name_upper = try toUpperCase(allocator, agent_name);
    defer allocator.free(agent_name_upper);

    const agent_name_lower = try toLowerCase(allocator, agent_name);
    defer allocator.free(agent_name_lower);

    var i: usize = 0;
    while (i < content.len) {
        if (std.mem.indexOf(u8, content[i..], "{{")) |start| {
            // Copy everything before {{
            try result.appendSlice(allocator, content[i .. i + start]);
            i += start;

            if (std.mem.indexOf(u8, content[i..], "}}")) |end| {
                const var_name = content[i + 2 .. i + end];
                const replacement = try getTemplateReplacement(
                    allocator,
                    var_name,
                    agent_name,
                    description,
                    author,
                    agent_name_upper,
                    agent_name_lower,
                );
                defer allocator.free(replacement);
                try result.appendSlice(allocator, replacement);
                i += end + 2;
            } else {
                // No closing }}, copy the {{ as-is
                try result.appendSlice(allocator, content[i .. i + 2]);
                i += 2;
            }
        } else if (std.mem.indexOf(u8, content[i..], "_template")) |start| {
            // Replace hardcoded "_template" strings
            try result.appendSlice(allocator, content[i .. i + start]);
            try result.appendSlice(allocator, agent_name);
            i += start + "_template".len;
        } else if (std.mem.indexOf(u8, content[i..], "Template Agent")) |start| {
            // Replace "Template Agent" with actual agent name
            try result.appendSlice(allocator, content[i .. i + start]);
            try result.appendSlice(allocator, agent_name);
            i += start + "Template Agent".len;
        } else if (std.mem.indexOf(u8, content[i..], "A template for creating new agents")) |start| {
            // Replace template description
            try result.appendSlice(allocator, content[i .. i + start]);
            try result.appendSlice(allocator, description);
            i += start + "A template for creating new agents".len;
        } else if (std.mem.indexOf(u8, content[i..], "Your Name")) |start| {
            // Replace template author
            try result.appendSlice(allocator, content[i .. i + start]);
            try result.appendSlice(allocator, author);
            i += start + "Your Name".len;
        } else {
            // No more replacements, copy the rest
            try result.appendSlice(allocator, content[i..]);
            break;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// getTemplateReplacement returns the replacement for a template variable
fn getTemplateReplacement(
    allocator: std.mem.Allocator,
    var_name: []const u8,
    agent_name: []const u8,
    description: []const u8,
    author: []const u8,
    agent_name_upper: []const u8,
    agent_name_lower: []const u8,
) anyerror![]const u8 {
    if (std.mem.eql(u8, var_name, "AGENT_NAME")) {
        return allocator.dupe(u8, agent_name);
    } else if (std.mem.eql(u8, var_name, "AGENT_DESCRIPTION")) {
        return allocator.dupe(u8, description);
    } else if (std.mem.eql(u8, var_name, "AGENT_AUTHOR")) {
        return allocator.dupe(u8, author);
    } else if (std.mem.eql(u8, var_name, "AGENT_NAME_UPPER")) {
        return allocator.dupe(u8, agent_name_upper);
    } else if (std.mem.eql(u8, var_name, "AGENT_NAME_LOWER")) {
        return allocator.dupe(u8, agent_name_lower);
    } else {
        // Unknown variable, return as-is with braces
        return std.fmt.allocPrint(allocator, "{{{{{s}}}}}", .{var_name});
    }
}

/// toUpperCase converts a string to uppercase
fn toUpperCase(allocator: std.mem.Allocator, input: []const u8) anyerror![]const u8 {
    var result = try allocator.alloc(u8, input.len);
    for (input, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

/// toLowerCase converts a string to lowercase
fn toLowerCase(allocator: std.mem.Allocator, input: []const u8) anyerror![]const u8 {
    var result = try allocator.alloc(u8, input.len);
    for (input, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

/// generateConfigZon creates a config.zon file with agent-specific values
fn generateConfigZon(
    allocator: std.mem.Allocator,
    agent_path: []const u8,
    agent_name: []const u8,
    description: []const u8,
    author: []const u8,
) anyerror!void {
    const config_path = try std.fs.path.join(allocator, &.{ agent_path, "config.zon" });
    defer allocator.free(config_path);

    const config_content = try std.fmt.allocPrint(
        allocator,
        \\.{{
        \\    // Standard agent configuration - customize for your specific agent
        \\    .agent_config = .{{
        \\        .agent_info = .{{
        \\            .name = "{s}",
        \\            .version = "1.0.0",
        \\            .description = "{s}",
        \\            .author = "{s}",
        \\        }},
        \\
        \\        .defaults = .{{
        \\            .max_concurrent_operations = 10,
        \\            .default_timeout_ms = 30000,
        \\            .enable_debug_logging = false,
        \\            .enable_verbose_output = false,
        \\        }},
        \\
        \\        .features = .{{
        \\            .enable_custom_tools = true,
        \\            .enable_file_operations = true,
        \\            .enable_network_access = false,
        \\            .enable_system_commands = false,
        \\        }},
        \\
        \\        .limits = .{{
        \\            .max_input_size = 1048576, // 1MB
        \\            .max_output_size = 1048576, // 1MB
        \\            .max_processing_time_ms = 60000,
        \\        }},
        \\
        \\        .model = .{{
        \\            .default_model = "claude-3-sonnet-20240229",
        \\            .max_tokens = 4096,
        \\            .temperature = 0.7,
        \\            .stream_responses = true,
        \\        }},
        \\    }},
        \\
        \\    // Agent-specific configuration fields
        \\    .custom_feature_enabled = false,
        \\    .max_custom_operations = 50,
        \\}}
        \\
    ,
        .{ agent_name, description, author },
    );
    defer allocator.free(config_content);

    const config_file = try std.fs.cwd().createFile(config_path, .{});
    defer config_file.close();
    try config_file.writeAll(config_content);
}

/// generateAgentManifestZon creates an agent.manifest.zon file with agent-specific metadata
fn generateAgentManifestZon(
    allocator: std.mem.Allocator,
    agent_path: []const u8,
    agent_name: []const u8,
    description: []const u8,
    author: []const u8,
) anyerror!void {
    const manifest_path = try std.fs.path.join(allocator, &.{ agent_path, "agent.manifest.zon" });
    defer allocator.free(manifest_path);

    // Convert agent name to kebab-case for ID
    const agent_id = try toKebabCase(allocator, agent_name);
    defer allocator.free(agent_id);

    // Build the manifest content manually to avoid formatting issues
    var manifest_buf = std.ArrayList(u8).initCapacity(allocator, 4096) catch return error.OutOfMemory;
    defer manifest_buf.deinit(allocator);

    try manifest_buf.appendSlice(allocator, ".{\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // AGENT MANIFEST - Standardized Metadata Format\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // This manifest provides comprehensive metadata for terminal AI agents.\n");
    try manifest_buf.appendSlice(allocator, "    // All fields are optional but recommended for proper agent discovery and management.\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // AGENT IDENTIFICATION\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    .agent = .{\n");
    try manifest_buf.appendSlice(allocator, "        // Unique identifier for the agent (lowercase, no spaces)\n");
    try manifest_buf.appendSlice(allocator, "        .id = \"");
    try manifest_buf.appendSlice(allocator, agent_id);
    try manifest_buf.appendSlice(allocator, "\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Human-readable name\n");
    try manifest_buf.appendSlice(allocator, "        .name = \"");
    try manifest_buf.appendSlice(allocator, agent_name);
    try manifest_buf.appendSlice(allocator, "\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Semantic version (e.g., \"1.0.0\", \"2.1.3-alpha\")\n");
    try manifest_buf.appendSlice(allocator, "        .version = \"1.0.0\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Brief description of what the agent does\n");
    try manifest_buf.appendSlice(allocator, "        .description = \"");
    try manifest_buf.appendSlice(allocator, description);
    try manifest_buf.appendSlice(allocator, "\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Author information\n");
    try manifest_buf.appendSlice(allocator, "        .author = .{\n");
    try manifest_buf.appendSlice(allocator, "            .name = \"");
    try manifest_buf.appendSlice(allocator, author);
    try manifest_buf.appendSlice(allocator, "\",\n");
    try manifest_buf.appendSlice(allocator, "            .email = \"your.email@example.com\",\n");
    try manifest_buf.appendSlice(allocator, "            .organization = \"Optional Organization\",\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Optional: License information\n");
    try manifest_buf.appendSlice(allocator, "        .license = \"MIT\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Optional: Homepage or repository URL\n");
    try manifest_buf.appendSlice(allocator, "        .homepage = \"https://github.com/your-org/your-repo\",\n");
    try manifest_buf.appendSlice(allocator, "    },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // CAPABILITIES & FEATURES\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    .capabilities = .{\n");
    try manifest_buf.appendSlice(allocator, "        // Core capabilities this agent provides\n");
    try manifest_buf.appendSlice(allocator, "        .core_features = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Whether agent can process files\n");
    try manifest_buf.appendSlice(allocator, "            .file_processing = true,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Whether agent can execute system commands\n");
    try manifest_buf.appendSlice(allocator, "            .system_commands = false,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Whether agent can make network requests\n");
    try manifest_buf.appendSlice(allocator, "            .network_access = true,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Whether agent supports interactive terminal UI\n");
    try manifest_buf.appendSlice(allocator, "            .terminal_ui = true,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Whether agent can process images/media\n");
    try manifest_buf.appendSlice(allocator, "            .media_processing = false,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Whether agent supports real-time streaming\n");
    try manifest_buf.appendSlice(allocator, "            .streaming_responses = true,\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Specialized features (agent-specific)\n");
    try manifest_buf.appendSlice(allocator, "        .specialized_features = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Example: custom functionality\n");
    try manifest_buf.appendSlice(allocator, "            .custom_processing = true,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Example: code generation\n");
    try manifest_buf.appendSlice(allocator, "            .code_generation = false,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Example: data analysis\n");
    try manifest_buf.appendSlice(allocator, "            .data_analysis = false,\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Performance characteristics\n");
    try manifest_buf.appendSlice(allocator, "        .performance = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Expected memory usage (low, medium, high)\n");
    try manifest_buf.appendSlice(allocator, "            .memory_usage = \"low\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // CPU intensity (low, medium, high)\n");
    try manifest_buf.appendSlice(allocator, "            .cpu_intensity = \"low\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Network bandwidth requirements (low, medium, high)\n");
    try manifest_buf.appendSlice(allocator, "            .network_bandwidth = \"low\",\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "    },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // CATEGORIZATION & DISCOVERY\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    .categorization = .{\n");
    try manifest_buf.appendSlice(allocator, "        // Primary category\n");
    try manifest_buf.appendSlice(allocator, "        .primary_category = \"development\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Secondary categories (array of strings)\n");
    try manifest_buf.appendSlice(allocator, "        .secondary_categories = .{\n");
    try manifest_buf.appendSlice(allocator, "            \"documentation\",\n");
    try manifest_buf.appendSlice(allocator, "            \"automation\",\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Tags for search and filtering\n");
    try manifest_buf.appendSlice(allocator, "        .tags = .{\n");
    try manifest_buf.appendSlice(allocator, "            \"");
    try manifest_buf.appendSlice(allocator, agent_name);
    try manifest_buf.appendSlice(allocator, "\",\n");
    try manifest_buf.appendSlice(allocator, "            \"cli\",\n");
    try manifest_buf.appendSlice(allocator, "            \"terminal\",\n");
    try manifest_buf.appendSlice(allocator, "            \"ai-agent\",\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Intended use cases\n");
    try manifest_buf.appendSlice(allocator, "        .use_cases = .{\n");
    try manifest_buf.appendSlice(allocator, "            \"Custom AI agent functionality\",\n");
    try manifest_buf.appendSlice(allocator, "            \"Terminal-based automation\",\n");
    try manifest_buf.appendSlice(allocator, "            \"Specialized task processing\",\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "    },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // DEPENDENCIES\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    .dependencies = .{\n");
    try manifest_buf.appendSlice(allocator, "        // Required Zig version (minimum)\n");
    try manifest_buf.appendSlice(allocator, "        .zig_version = \"0.15.1\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // External dependencies\n");
    try manifest_buf.appendSlice(allocator, "        .external = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Array of required system packages/libraries\n");
    try manifest_buf.appendSlice(allocator, "            .system_packages = .{\n");
    try manifest_buf.appendSlice(allocator, "                // \"curl\",\n");
    try manifest_buf.appendSlice(allocator, "                // \"openssl\",\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Zig packages (from build.zig.zon)\n");
    try manifest_buf.appendSlice(allocator, "            .zig_packages = .{\n");
    try manifest_buf.appendSlice(allocator, "                // .{ .name = \"http-client\", .version = \"1.0.0\" },\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Optional dependencies\n");
    try manifest_buf.appendSlice(allocator, "        .optional = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Features that can work without these\n");
    try manifest_buf.appendSlice(allocator, "            .features = .{\n");
    try manifest_buf.appendSlice(allocator, "                // .{ .name = \"network\", .requires = \"curl\" },\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "    },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // BUILD CONFIGURATION\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    .build = .{\n");
    try manifest_buf.appendSlice(allocator, "        // Build targets supported\n");
    try manifest_buf.appendSlice(allocator, "        .targets = .{\n");
    try manifest_buf.appendSlice(allocator, "            \"x86_64-linux\",\n");
    try manifest_buf.appendSlice(allocator, "            \"aarch64-linux\",\n");
    try manifest_buf.appendSlice(allocator, "            \"x86_64-macos\",\n");
    try manifest_buf.appendSlice(allocator, "            \"aarch64-macos\",\n");
    try manifest_buf.appendSlice(allocator, "            \"x86_64-windows\",\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Build options\n");
    try manifest_buf.appendSlice(allocator, "        .options = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Whether agent supports debug builds\n");
    try manifest_buf.appendSlice(allocator, "            .debug_build = true,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Whether agent supports release builds\n");
    try manifest_buf.appendSlice(allocator, "            .release_build = true,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Whether agent can be built as library\n");
    try manifest_buf.appendSlice(allocator, "            .library_build = false,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Custom build flags (array of strings)\n");
    try manifest_buf.appendSlice(allocator, "            .custom_flags = .{\n");
    try manifest_buf.appendSlice(allocator, "                // \"-Doptimize=ReleaseFast\",\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Build artifacts\n");
    try manifest_buf.appendSlice(allocator, "        .artifacts = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Binary name\n");
    try manifest_buf.appendSlice(allocator, "            .binary_name = \"");
    try manifest_buf.appendSlice(allocator, agent_name);
    try manifest_buf.appendSlice(allocator, "\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Additional files to include in distribution\n");
    try manifest_buf.appendSlice(allocator, "            .include_files = .{\n");
    try manifest_buf.appendSlice(allocator, "                // \"README.md\",\n");
    try manifest_buf.appendSlice(allocator, "                // \"config.zon\",\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "    },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // TOOL CATEGORIES\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    .tools = .{\n");
    try manifest_buf.appendSlice(allocator, "        // Categories of tools this agent provides\n");
    try manifest_buf.appendSlice(allocator, "        .categories = .{\n");
    try manifest_buf.appendSlice(allocator, "            \"file_operations\",\n");
    try manifest_buf.appendSlice(allocator, "            \"text_processing\",\n");
    try manifest_buf.appendSlice(allocator, "            \"system_integration\",\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Specific tools provided (for documentation)\n");
    try manifest_buf.appendSlice(allocator, "        .provided_tools = .{\n");
    try manifest_buf.appendSlice(allocator, "            .{\n");
    try manifest_buf.appendSlice(allocator, "                .name = \"example_tool\",\n");
    try manifest_buf.appendSlice(allocator, "                .description = \"Example tool for ");
    try manifest_buf.appendSlice(allocator, agent_name);
    try manifest_buf.appendSlice(allocator, " agent\",\n");
    try manifest_buf.appendSlice(allocator, "                .category = \"file_operations\",\n");
    try manifest_buf.appendSlice(allocator, "                .parameters = \"file_path:string\",\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Tool integration\n");
    try manifest_buf.appendSlice(allocator, "        .integration = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Whether tools support JSON input/output\n");
    try manifest_buf.appendSlice(allocator, "            .json_tools = true,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Whether tools support streaming\n");
    try manifest_buf.appendSlice(allocator, "            .streaming_tools = false,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Whether tools can be chained together\n");
    try manifest_buf.appendSlice(allocator, "            .chainable_tools = true,\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "    },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // RUNTIME REQUIREMENTS\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    .runtime = .{\n");
    try manifest_buf.appendSlice(allocator, "        // Minimum system requirements\n");
    try manifest_buf.appendSlice(allocator, "        .system_requirements = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Minimum RAM in MB\n");
    try manifest_buf.appendSlice(allocator, "            .min_ram_mb = 256,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Minimum disk space in MB\n");
    try manifest_buf.appendSlice(allocator, "            .min_disk_mb = 50,\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Supported operating systems\n");
    try manifest_buf.appendSlice(allocator, "            .supported_os = .{\n");
    try manifest_buf.appendSlice(allocator, "                \"linux\",\n");
    try manifest_buf.appendSlice(allocator, "                \"macos\",\n");
    try manifest_buf.appendSlice(allocator, "                \"windows\",\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Environment variables required\n");
    try manifest_buf.appendSlice(allocator, "        .environment_variables = .{\n");
    try manifest_buf.appendSlice(allocator, "            // .{ .name = \"API_KEY\", .description = \"Required API key for service\", .required = true },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Configuration files required\n");
    try manifest_buf.appendSlice(allocator, "        .config_files = .{\n");
    try manifest_buf.appendSlice(allocator, "            // .{ .name = \"config.zon\", .description = \"Agent configuration file\", .required = true },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Network requirements\n");
    try manifest_buf.appendSlice(allocator, "        .network = .{\n");
    try manifest_buf.appendSlice(allocator, "            // Required ports\n");
    try manifest_buf.appendSlice(allocator, "            .ports = .{\n");
    try manifest_buf.appendSlice(allocator, "                // .{ .port = 8080, .protocol = \"tcp\", .description = \"Web server port\" },\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "            // Required endpoints\n");
    try manifest_buf.appendSlice(allocator, "            .endpoints = .{\n");
    try manifest_buf.appendSlice(allocator, "                // .{ .url = \"https://api.example.com\", .description = \"External API endpoint\" },\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "    },\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    // METADATA\n");
    try manifest_buf.appendSlice(allocator, "    // ============================================================================\n");
    try manifest_buf.appendSlice(allocator, "    .metadata = .{\n");
    try manifest_buf.appendSlice(allocator, "        // When this manifest was created/updated\n");
    try manifest_buf.appendSlice(allocator, "        .created_at = \"2025-01-27\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Template version this manifest conforms to\n");
    try manifest_buf.appendSlice(allocator, "        .template_version = \"1.0\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Additional notes or comments\n");
    try manifest_buf.appendSlice(allocator, "        .notes = \"Generated agent manifest for ");
    try manifest_buf.appendSlice(allocator, agent_name);
    try manifest_buf.appendSlice(allocator, "\",\n");
    try manifest_buf.appendSlice(allocator, "\n");
    try manifest_buf.appendSlice(allocator, "        // Changelog for this version\n");
    try manifest_buf.appendSlice(allocator, "        .changelog = .{\n");
    try manifest_buf.appendSlice(allocator, "            .{\n");
    try manifest_buf.appendSlice(allocator, "                .version = \"1.0.0\",\n");
    try manifest_buf.appendSlice(allocator, "                .changes = \"Initial agent creation with standardized structure\",\n");
    try manifest_buf.appendSlice(allocator, "            },\n");
    try manifest_buf.appendSlice(allocator, "        },\n");
    try manifest_buf.appendSlice(allocator, "    },\n");
    try manifest_buf.appendSlice(allocator, "}\n");

    const manifest_content = try manifest_buf.toOwnedSlice(allocator);
    defer allocator.free(manifest_content);

    const manifest_file = try std.fs.cwd().createFile(manifest_path, .{});
    defer manifest_file.close();
    try manifest_file.writeAll(manifest_content);
}

/// toKebabCase converts a string to kebab-case
fn toKebabCase(allocator: std.mem.Allocator, input: []const u8) anyerror![]const u8 {
    var result = std.ArrayList(u8).initCapacity(allocator, input.len * 2) catch return ScaffoldAgentError.OutOfMemory;
    defer result.deinit(allocator);

    for (input, 0..) |c, i| {
        if (std.ascii.isUpper(c) and i > 0) {
            try result.append(allocator, '-');
        }
        try result.append(allocator, std.ascii.toLower(c));
    }

    return result.toOwnedSlice(allocator);
}

/// Command-line interface for the agent scaffold tool
pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    const gpa = gpa_state.allocator();
    defer if (gpa_state.deinit() == .leak) {
        @panic("Memory leak detected");
    };

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    // Check for help flag
    if (args.len >= 2 and std.mem.eql(u8, args[1], "--help")) {
        printUsage();
        return;
    }

    if (args.len < 4) {
        printUsage();
        return;
    }

    const agent_name = args[1];
    const description = args[2];
    const author = args[3];

    const options = ScaffoldAgentOptions{
        .agent_name = agent_name,
        .description = description,
        .author = author,
        .allocator = gpa,
    };

    scaffoldAgent(options) catch |err| {
        switch (err) {
            ScaffoldAgentError.AgentAlreadyExists => {
                std.debug.print("Error: Agent '{s}' already exists!\n", .{agent_name});
                std.process.exit(1);
            },
            ScaffoldAgentError.TemplateNotFound => {
                std.debug.print("Error: Template directory 'agents/_template' not found!\n", .{});
                std.process.exit(1);
            },
            ScaffoldAgentError.InvalidAgentName => {
                std.debug.print("Error: Invalid agent name '{s}'. Agent names must:\n", .{agent_name});
                std.debug.print("  - Be 1-50 characters long\n", .{});
                std.debug.print("  - Start with a letter or underscore\n", .{});
                std.debug.print("  - Contain only letters, numbers, underscores, and hyphens\n", .{});
                std.debug.print("  - Not be reserved names (_template, core, shared, tools)\n", .{});
                std.process.exit(1);
            },
            else => {
                std.debug.print("Error: Failed to create agent '{s}': {}\n", .{ agent_name, err });
                std.process.exit(1);
            },
        }
    };
}

/// printUsage displays command-line usage information
fn printUsage() void {
    std.debug.print(
        \\Agent Scaffold Tool
        \\
        \\Creates a new agent directory structure from the template with proper configuration.
        \\
        \\Usage: zig run src/tools/agent_scaffold.zig <agent_name> <description> <author>
        \\
        \\Arguments:
        \\  agent_name    Name of the new agent (lowercase, no spaces)
        \\  description   Brief description of the agent's purpose
        \\  author        Author name for the agent
        \\
        \\Example:
        \\  zig run src/tools/agent_scaffold.zig my-agent "A custom AI agent" "John Doe"
        \\
        \\This will create:
        \\  - agents/my-agent/ directory structure
        \\  - Template files with placeholders replaced
        \\  - Agent-specific config.zon and agent.manifest.zon files
        \\  - Subdirectories: tools/, common/, examples/
        \\
        \\Naming Rules:
        \\  - 1-50 characters long
        \\  - Start with letter or underscore
        \\  - Letters, numbers, underscores, hyphens only
        \\  - Cannot use reserved names (_template, core, shared, tools)
        \\
    , .{});
}
