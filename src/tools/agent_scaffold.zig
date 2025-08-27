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

/// ScaffoldAgent contains configuration for agent scaffolding
pub const ScaffoldAgent = struct {
    agentName: []const u8,
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
/// - options: ScaffoldAgent containing agent details and allocator
///
/// Returns: void on success, error on failure
pub fn scaffoldAgent(options: ScaffoldAgent) anyerror!void {
    const allocator = options.allocator;
    const agentName = options.agentName;
    const description = options.description;
    const author = options.author;

    // Validate agent name
    if (!isValidAgentName(agentName)) {
        return ScaffoldAgentError.InvalidAgentName;
    }

    // Check if agent already exists
    const agentPath = try std.fs.path.join(allocator, &.{ "agents", agentName });
    defer allocator.free(agentPath);

    // Check if agent already exists
    if (std.fs.cwd().openDir(agentPath, .{})) |_| {
        return ScaffoldAgentError.AgentAlreadyExists;
    } else |_| {
        // Directory doesn't exist, which is what we want
    }

    // Check if template exists
    const templatePath = "agents/_template";
    if (std.fs.cwd().openDir(templatePath, .{})) |_| {
        // Template exists
    } else |_| {
        return ScaffoldAgentError.TemplateNotFound;
    }

    // Create agent directory
    std.fs.cwd().makeDir(agentPath) catch |err| switch (err) {
        error.PathAlreadyExists => {
            // Directory already exists, which we already checked for
            return ScaffoldAgentError.AgentAlreadyExists;
        },
        else => return ScaffoldAgentError.DirectoryCreationFailed,
    };

    // Create subdirectories
    const subDirectories = [_][]const u8{ "tools", "common", "examples" };
    for (subDirectories) |subDirectory| {
        const subDirectoryPath = try std.fs.path.join(allocator, &.{ agentPath, subDirectory });
        defer allocator.free(subDirectoryPath);
        std.fs.cwd().makeDir(subDirectoryPath) catch |err| switch (err) {
            error.PathAlreadyExists => {
                // Subdirectory already exists, continue
            },
            else => return ScaffoldAgentError.DirectoryCreationFailed,
        };
    }

    // Copy and process template files
    try copyTemplateFiles(allocator, templatePath, agentPath, agentName, description, author);

    // Generate agent-specific files
    try generateConfigZon(allocator, agentPath, agentName, description, author);
    try generateAgentManifestZon(allocator, agentPath, agentName, description, author);

    std.debug.print("Successfully created agent '{s}' at {s}/\n", .{ agentName, agentPath });
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
    const reservedNames = [_][]const u8{ "_template", "core", "shared", "tools" };
    for (reservedNames) |reserved_name| {
        if (std.mem.eql(u8, name, reserved_name)) return false;
    }

    return true;
}

/// copyTemplateFiles copies template files with placeholder replacement
fn copyTemplateFiles(
    allocator: std.mem.Allocator,
    templatePath: []const u8,
    agentPath: []const u8,
    agentName: []const u8,
    description: []const u8,
    author: []const u8,
) anyerror!void {
    const templateFiles = [_][]const u8{
        "main.zig",
        "agent.zig",
        "spec.zig",
        "system_prompt.txt",
        "README.md",
        "tools/mod.zig",
        "tools/ExampleTool.zig",
    };

    for (templateFiles) |templateFile| {
        const srcPath = try std.fs.path.join(allocator, &.{ templatePath, templateFile });
        defer allocator.free(srcPath);

        const dstPath = try std.fs.path.join(allocator, &.{ agentPath, templateFile });
        defer allocator.free(dstPath);

        // Read template file
        const srcFile = try std.fs.cwd().openFile(srcPath, .{});
        defer srcFile.close();
        const templateContent = try srcFile.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(templateContent);

        // Process template variables
        const processedContent = try processTemplateVariables(
            allocator,
            templateContent,
            agentName,
            description,
            author,
        );
        defer allocator.free(processedContent);

        // Write processed content to destination
        const file = try std.fs.cwd().createFile(dstPath, .{});
        defer file.close();
        try file.writeAll(processedContent);
    }
}

/// processTemplateVariables replaces template placeholders in file content
fn processTemplateVariables(
    allocator: std.mem.Allocator,
    content: []const u8,
    agentName: []const u8,
    description: []const u8,
    author: []const u8,
) anyerror![]const u8 {
    var result = std.array_list.Managed(u8).initCapacity(allocator, content.len) catch return ScaffoldAgentError.OutOfMemory;
    defer result.deinit();

    // Convert agent name to different cases
    const agentNameUpper = try toUpperCase(allocator, agentName);
    defer allocator.free(agentNameUpper);

    const agentNameLower = try toLowerCase(allocator, agentName);
    defer allocator.free(agentNameLower);

    var i: usize = 0;
    while (i < content.len) {
        if (std.mem.indexOf(u8, content[i..], "{{")) |start| {
            // Copy everything before {{
            try result.appendSlice(allocator, content[i .. i + start]);
            i += start;

            if (std.mem.indexOf(u8, content[i..], "}}")) |end| {
                const varName = content[i + 2 .. i + end];
                const replacement = try getTemplateReplacement(
                    allocator,
                    varName,
                    agentName,
                    description,
                    author,
                    agentNameUpper,
                    agentNameLower,
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
            try result.appendSlice(allocator, agentName);
            i += start + "_template".len;
        } else if (std.mem.indexOf(u8, content[i..], "Template Agent")) |start| {
            // Replace "Template Agent" with actual agent name
            try result.appendSlice(allocator, content[i .. i + start]);
            try result.appendSlice(allocator, agentName);
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
    varName: []const u8,
    agentName: []const u8,
    description: []const u8,
    author: []const u8,
    agentNameUpper: []const u8,
    agentNameLower: []const u8,
) anyerror![]const u8 {
    if (std.mem.eql(u8, varName, "AGENT_NAME")) {
        return allocator.dupe(u8, agentName);
    } else if (std.mem.eql(u8, varName, "AGENT_DESCRIPTION")) {
        return allocator.dupe(u8, description);
    } else if (std.mem.eql(u8, varName, "AGENT_AUTHOR")) {
        return allocator.dupe(u8, author);
    } else if (std.mem.eql(u8, varName, "AGENT_NAME_UPPER")) {
        return allocator.dupe(u8, agentNameUpper);
    } else if (std.mem.eql(u8, varName, "AGENT_NAME_LOWER")) {
        return allocator.dupe(u8, agentNameLower);
    } else {
        // Unknown variable, return as-is with braces
        return std.fmt.allocPrint(allocator, "{{{{{s}}}}}", .{varName});
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
    agentPath: []const u8,
    agentName: []const u8,
    description: []const u8,
    author: []const u8,
) anyerror!void {
    const configPath = try std.fs.path.join(allocator, &.{ agentPath, "config.zon" });
    defer allocator.free(configPath);

    const configContent = try std.fmt.allocPrint(
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
        .{ agentName, description, author },
    );
    defer allocator.free(configContent);

    const configFile = try std.fs.cwd().createFile(configPath, .{});
    defer configFile.close();
    try configFile.writeAll(configContent);
}

/// generateAgentManifestZon creates an agent.manifest.zon file with agent-specific metadata
fn generateAgentManifestZon(
    allocator: std.mem.Allocator,
    agentPath: []const u8,
    agentName: []const u8,
    description: []const u8,
    author: []const u8,
) anyerror!void {
    const manifestPath = try std.fs.path.join(allocator, &.{ agentPath, "agent.manifest.zon" });
    defer allocator.free(manifestPath);

    // Convert agent name to kebab-case for ID
    const agentId = try toKebabCase(allocator, agentName);
    defer allocator.free(agentId);

    // Build the manifest content manually to avoid formatting issues
    var manifestBuf = std.array_list.Managed(u8).initCapacity(allocator, 4096) catch return error.OutOfMemory;
    defer manifestBuf.deinit();

    try manifestBuf.appendSlice(allocator, ".{\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // AGENT MANIFEST - Standardized Metadata Format\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // This manifest provides comprehensive metadata for terminal AI agents.\n");
    try manifestBuf.appendSlice(allocator, "    // All fields are optional but recommended for proper agent discovery and management.\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // AGENT IDENTIFICATION\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    .agent = .{\n");
    try manifestBuf.appendSlice(allocator, "        // Unique identifier for the agent (lowercase, no spaces)\n");
    try manifestBuf.appendSlice(allocator, "        .id = \"");
    try manifestBuf.appendSlice(allocator, agentId);
    try manifestBuf.appendSlice(allocator, "\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Human-readable name\n");
    try manifestBuf.appendSlice(allocator, "        .name = \"");
    try manifestBuf.appendSlice(allocator, agentName);
    try manifestBuf.appendSlice(allocator, "\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Semantic version (e.g., \"1.0.0\", \"2.1.3-alpha\")\n");
    try manifestBuf.appendSlice(allocator, "        .version = \"1.0.0\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Brief description of what the agent does\n");
    try manifestBuf.appendSlice(allocator, "        .description = \"");
    try manifestBuf.appendSlice(allocator, description);
    try manifestBuf.appendSlice(allocator, "\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Author information\n");
    try manifestBuf.appendSlice(allocator, "        .author = .{\n");
    try manifestBuf.appendSlice(allocator, "            .name = \"");
    try manifestBuf.appendSlice(allocator, author);
    try manifestBuf.appendSlice(allocator, "\",\n");
    try manifestBuf.appendSlice(allocator, "            .email = \"your.email@example.com\",\n");
    try manifestBuf.appendSlice(allocator, "            .organization = \"Optional Organization\",\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Optional: License information\n");
    try manifestBuf.appendSlice(allocator, "        .license = \"MIT\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Optional: Homepage or repository URL\n");
    try manifestBuf.appendSlice(allocator, "        .homepage = \"https://github.com/your-org/your-repo\",\n");
    try manifestBuf.appendSlice(allocator, "    },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // CAPABILITIES & FEATURES\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    .capabilities = .{\n");
    try manifestBuf.appendSlice(allocator, "        // Core capabilities this agent provides\n");
    try manifestBuf.appendSlice(allocator, "        .core_features = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Whether agent can process files\n");
    try manifestBuf.appendSlice(allocator, "            .file_processing = true,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Whether agent can execute system commands\n");
    try manifestBuf.appendSlice(allocator, "            .system_commands = false,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Whether agent can make network requests\n");
    try manifestBuf.appendSlice(allocator, "            .network_access = true,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Whether agent supports interactive terminal UI\n");
    try manifestBuf.appendSlice(allocator, "            .terminal_ui = true,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Whether agent can process images/media\n");
    try manifestBuf.appendSlice(allocator, "            .media_processing = false,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Whether agent supports real-time streaming\n");
    try manifestBuf.appendSlice(allocator, "            .streaming_responses = true,\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Specialized features (agent-specific)\n");
    try manifestBuf.appendSlice(allocator, "        .specialized_features = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Example: custom functionality\n");
    try manifestBuf.appendSlice(allocator, "            .custom_processing = true,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Example: code generation\n");
    try manifestBuf.appendSlice(allocator, "            .code_generation = false,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Example: data analysis\n");
    try manifestBuf.appendSlice(allocator, "            .data_analysis = false,\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Performance characteristics\n");
    try manifestBuf.appendSlice(allocator, "        .performance = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Expected memory usage (low, medium, high)\n");
    try manifestBuf.appendSlice(allocator, "            .memory_usage = \"low\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // CPU intensity (low, medium, high)\n");
    try manifestBuf.appendSlice(allocator, "            .cpu_intensity = \"low\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Network bandwidth requirements (low, medium, high)\n");
    try manifestBuf.appendSlice(allocator, "            .network_bandwidth = \"low\",\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "    },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // CATEGORIZATION & DISCOVERY\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    .categorization = .{\n");
    try manifestBuf.appendSlice(allocator, "        // Primary category\n");
    try manifestBuf.appendSlice(allocator, "        .primary_category = \"development\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Secondary categories (array of strings)\n");
    try manifestBuf.appendSlice(allocator, "        .secondary_categories = .{\n");
    try manifestBuf.appendSlice(allocator, "            \"documentation\",\n");
    try manifestBuf.appendSlice(allocator, "            \"automation\",\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Tags for search and filtering\n");
    try manifestBuf.appendSlice(allocator, "        .tags = .{\n");
    try manifestBuf.appendSlice(allocator, "            \"");
    try manifestBuf.appendSlice(allocator, agentName);
    try manifestBuf.appendSlice(allocator, "\",\n");
    try manifestBuf.appendSlice(allocator, "            \"cli\",\n");
    try manifestBuf.appendSlice(allocator, "            \"terminal\",\n");
    try manifestBuf.appendSlice(allocator, "            \"ai-agent\",\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Intended use cases\n");
    try manifestBuf.appendSlice(allocator, "        .use_cases = .{\n");
    try manifestBuf.appendSlice(allocator, "            \"Custom AI agent functionality\",\n");
    try manifestBuf.appendSlice(allocator, "            \"Terminal-based automation\",\n");
    try manifestBuf.appendSlice(allocator, "            \"Specialized task processing\",\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "    },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // DEPENDENCIES\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    .dependencies = .{\n");
    try manifestBuf.appendSlice(allocator, "        // Required Zig version (minimum)\n");
    try manifestBuf.appendSlice(allocator, "        .zig_version = \"0.15.1\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // External dependencies\n");
    try manifestBuf.appendSlice(allocator, "        .external = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Array of required system packages/libraries\n");
    try manifestBuf.appendSlice(allocator, "            .system_packages = .{\n");
    try manifestBuf.appendSlice(allocator, "                // \"curl\",\n");
    try manifestBuf.appendSlice(allocator, "                // \"openssl\",\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Zig packages (from build.zig.zon)\n");
    try manifestBuf.appendSlice(allocator, "            .zig_packages = .{\n");
    try manifestBuf.appendSlice(allocator, "                // .{ .name = \"http-client\", .version = \"1.0.0\" },\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Optional dependencies\n");
    try manifestBuf.appendSlice(allocator, "        .optional = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Features that can work without these\n");
    try manifestBuf.appendSlice(allocator, "            .features = .{\n");
    try manifestBuf.appendSlice(allocator, "                // .{ .name = \"network\", .requires = \"curl\" },\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "    },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // BUILD CONFIGURATION\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    .build = .{\n");
    try manifestBuf.appendSlice(allocator, "        // Build targets supported\n");
    try manifestBuf.appendSlice(allocator, "        .targets = .{\n");
    try manifestBuf.appendSlice(allocator, "            \"x86_64-linux\",\n");
    try manifestBuf.appendSlice(allocator, "            \"aarch64-linux\",\n");
    try manifestBuf.appendSlice(allocator, "            \"x86_64-macos\",\n");
    try manifestBuf.appendSlice(allocator, "            \"aarch64-macos\",\n");
    try manifestBuf.appendSlice(allocator, "            \"x86_64-windows\",\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Build options\n");
    try manifestBuf.appendSlice(allocator, "        .options = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Whether agent supports debug builds\n");
    try manifestBuf.appendSlice(allocator, "            .debug_build = true,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Whether agent supports release builds\n");
    try manifestBuf.appendSlice(allocator, "            .release_build = true,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Whether agent can be built as library\n");
    try manifestBuf.appendSlice(allocator, "            .library_build = false,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Custom build flags (array of strings)\n");
    try manifestBuf.appendSlice(allocator, "            .custom_flags = .{\n");
    try manifestBuf.appendSlice(allocator, "                // \"-Doptimize=ReleaseFast\",\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Build artifacts\n");
    try manifestBuf.appendSlice(allocator, "        .artifacts = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Binary name\n");
    try manifestBuf.appendSlice(allocator, "            .binary_name = \"");
    try manifestBuf.appendSlice(allocator, agentName);
    try manifestBuf.appendSlice(allocator, "\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Additional files to include in distribution\n");
    try manifestBuf.appendSlice(allocator, "            .include_files = .{\n");
    try manifestBuf.appendSlice(allocator, "                // \"README.md\",\n");
    try manifestBuf.appendSlice(allocator, "                // \"config.zon\",\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "    },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // TOOL CATEGORIES\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    .tools = .{\n");
    try manifestBuf.appendSlice(allocator, "        // Categories of tools this agent provides\n");
    try manifestBuf.appendSlice(allocator, "        .categories = .{\n");
    try manifestBuf.appendSlice(allocator, "            \"file_operations\",\n");
    try manifestBuf.appendSlice(allocator, "            \"text_processing\",\n");
    try manifestBuf.appendSlice(allocator, "            \"system_integration\",\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Specific tools provided (for documentation)\n");
    try manifestBuf.appendSlice(allocator, "        .provided_tools = .{\n");
    try manifestBuf.appendSlice(allocator, "            .{\n");
    try manifestBuf.appendSlice(allocator, "                .name = \"example_tool\",\n");
    try manifestBuf.appendSlice(allocator, "                .description = \"Example tool for ");
    try manifestBuf.appendSlice(allocator, agentName);
    try manifestBuf.appendSlice(allocator, " agent\",\n");
    try manifestBuf.appendSlice(allocator, "                .category = \"file_operations\",\n");
    try manifestBuf.appendSlice(allocator, "                .parameters = \"file_path:string\",\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Tool integration\n");
    try manifestBuf.appendSlice(allocator, "        .integration = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Whether tools support JSON input/output\n");
    try manifestBuf.appendSlice(allocator, "            .json_tools = true,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Whether tools support streaming\n");
    try manifestBuf.appendSlice(allocator, "            .streaming_tools = false,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Whether tools can be chained together\n");
    try manifestBuf.appendSlice(allocator, "            .chainable_tools = true,\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "    },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // RUNTIME REQUIREMENTS\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    .runtime = .{\n");
    try manifestBuf.appendSlice(allocator, "        // Minimum system requirements\n");
    try manifestBuf.appendSlice(allocator, "        .system_requirements = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Minimum RAM in MB\n");
    try manifestBuf.appendSlice(allocator, "            .min_ram_mb = 256,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Minimum disk space in MB\n");
    try manifestBuf.appendSlice(allocator, "            .min_disk_mb = 50,\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Supported operating systems\n");
    try manifestBuf.appendSlice(allocator, "            .supported_os = .{\n");
    try manifestBuf.appendSlice(allocator, "                \"linux\",\n");
    try manifestBuf.appendSlice(allocator, "                \"macos\",\n");
    try manifestBuf.appendSlice(allocator, "                \"windows\",\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Environment variables required\n");
    try manifestBuf.appendSlice(allocator, "        .environment_variables = .{\n");
    try manifestBuf.appendSlice(allocator, "            // .{ .name = \"API_KEY\", .description = \"Required API key for service\", .required = true },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Configuration files required\n");
    try manifestBuf.appendSlice(allocator, "        .config_files = .{\n");
    try manifestBuf.appendSlice(allocator, "            // .{ .name = \"config.zon\", .description = \"Agent configuration file\", .required = true },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Network requirements\n");
    try manifestBuf.appendSlice(allocator, "        .network = .{\n");
    try manifestBuf.appendSlice(allocator, "            // Required ports\n");
    try manifestBuf.appendSlice(allocator, "            .ports = .{\n");
    try manifestBuf.appendSlice(allocator, "                // .{ .port = 8080, .protocol = \"tcp\", .description = \"Web server port\" },\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "            // Required endpoints\n");
    try manifestBuf.appendSlice(allocator, "            .endpoints = .{\n");
    try manifestBuf.appendSlice(allocator, "                // .{ .url = \"https://api.example.com\", .description = \"External API endpoint\" },\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "    },\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    // METADATA\n");
    try manifestBuf.appendSlice(allocator, "    // ============================================================================\n");
    try manifestBuf.appendSlice(allocator, "    .metadata = .{\n");
    try manifestBuf.appendSlice(allocator, "        // When this manifest was created/updated\n");
    try manifestBuf.appendSlice(allocator, "        .created_at = \"2025-01-27\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Template version this manifest conforms to\n");
    try manifestBuf.appendSlice(allocator, "        .template_version = \"1.0\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Additional notes or comments\n");
    try manifestBuf.appendSlice(allocator, "        .notes = \"Generated agent manifest for ");
    try manifestBuf.appendSlice(allocator, agentName);
    try manifestBuf.appendSlice(allocator, "\",\n");
    try manifestBuf.appendSlice(allocator, "\n");
    try manifestBuf.appendSlice(allocator, "        // Changelog for this version\n");
    try manifestBuf.appendSlice(allocator, "        .changelog = .{\n");
    try manifestBuf.appendSlice(allocator, "            .{\n");
    try manifestBuf.appendSlice(allocator, "                .version = \"1.0.0\",\n");
    try manifestBuf.appendSlice(allocator, "                .changes = \"Initial agent creation with standardized structure\",\n");
    try manifestBuf.appendSlice(allocator, "            },\n");
    try manifestBuf.appendSlice(allocator, "        },\n");
    try manifestBuf.appendSlice(allocator, "    },\n");
    try manifestBuf.appendSlice(allocator, "}\n");

    const manifestContent = try manifestBuf.toOwnedSlice(allocator);
    defer allocator.free(manifestContent);

    const manifestFile = try std.fs.cwd().createFile(manifestPath, .{});
    defer manifestFile.close();
    try manifestFile.writeAll(manifestContent);
}

/// toKebabCase converts a string to kebab-case
fn toKebabCase(allocator: std.mem.Allocator, input: []const u8) anyerror![]const u8 {
    var result = std.array_list.Managed(u8).initCapacity(allocator, input.len * 2) catch return ScaffoldAgentError.OutOfMemory;
    defer result.deinit();

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
    var gpaState: std.heap.DebugAllocator(.{}) = .init;
    const generalPurposeAllocator = gpaState.allocator();
    defer if (gpaState.deinit() == .leak) {
        std.log.err("Memory leak detected", .{});
    };

    const arguments = try std.process.argsAlloc(generalPurposeAllocator);
    defer std.process.argsFree(generalPurposeAllocator, arguments);

    // Check for help flag
    if (arguments.len >= 2 and std.mem.eql(u8, arguments[1], "--help")) {
        printUsage();
        return;
    }

    if (arguments.len < 4) {
        printUsage();
        return;
    }

    const agentName = arguments[1];
    const description = arguments[2];
    const author = arguments[3];

    const options = ScaffoldAgent{
        .agentName = agentName,
        .description = description,
        .author = author,
        .allocator = generalPurposeAllocator,
    };

    scaffoldAgent(options) catch |err| {
        switch (err) {
            ScaffoldAgentError.AgentAlreadyExists => {
                std.debug.print("Error: Agent '{s}' already exists!\n", .{agentName});
                std.process.exit(1);
            },
            ScaffoldAgentError.TemplateNotFound => {
                std.debug.print("Error: Template directory 'agents/_template' not found!\n", .{});
                std.process.exit(1);
            },
            ScaffoldAgentError.InvalidAgentName => {
                std.debug.print("Error: Invalid agent name '{s}'. Agent names must:\n", .{agentName});
                std.debug.print("  - Be 1-50 characters long\n", .{});
                std.debug.print("  - Start with a letter or underscore\n", .{});
                std.debug.print("  - Contain only letters, numbers, underscores, and hyphens\n", .{});
                std.debug.print("  - Not be reserved names (_template, core, shared, tools)\n", .{});
                std.process.exit(1);
            },
            else => {
                std.debug.print("Error: Failed to create agent '{s}': {any}\n", .{ agentName, err });
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
