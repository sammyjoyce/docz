//! CLI Demo
//! Demonstrates the key architectural improvements without external dependencies

const std = @import("std");
const term_mod = @import("../term/mod.zig");

// =============================================================================
// Core Types (simplified versions)
// =============================================================================

pub const CliError = error{
    UnknownOption,
    UnknownCommand,
    InitializationError,
    CommandExecutionError,
    OutOfMemory,
};

pub const CommandResult = struct {
    success: bool,
    output: ?[]const u8 = null,
    error_msg: ?[]const u8 = null,
    exit_code: u8 = 0,

    pub fn ok(output: ?[]const u8) CommandResult {
        return CommandResult{
            .success = true,
            .output = output,
        };
    }

    pub fn err(msg: []const u8, exit_code: u8) CommandResult {
        return CommandResult{
            .success = false,
            .error_msg = msg,
            .exit_code = exit_code,
        };
    }
};

// =============================================================================
// Terminal Capabilities (simplified detection)
// =============================================================================

pub const CapabilitySet = struct {
    hyperlinks: bool = false,
    clipboard: bool = false,
    notifications: bool = false,
    graphics: bool = false,
    truecolor: bool = false,
    mouse: bool = false,

    pub fn detect() CapabilitySet {
        // Simplified capability detection based on common terminal support
        const term_program = std.process.getEnvVarOwned(std.heap.page_allocator, "TERM_PROGRAM") catch null;
        defer if (term_program) |tp| std.heap.page_allocator.free(tp);

        const colorterm = std.process.getEnvVarOwned(std.heap.page_allocator, "COLORTERM") catch null;
        defer if (colorterm) |ct| std.heap.page_allocator.free(ct);

        // Basic detection logic
        const has_modern_term = if (term_program) |tp|
            std.mem.eql(u8, tp, "iTerm.app") or
                std.mem.eql(u8, tp, "WezTerm") or
                std.mem.eql(u8, tp, "kitty")
        else
            false;

        const has_truecolor = if (colorterm) |ct|
            std.mem.eql(u8, ct, "truecolor") or std.mem.eql(u8, ct, "24bit")
        else
            false;

        return CapabilitySet{
            .hyperlinks = true, // OSC 8 widely supported
            .clipboard = true, // OSC 52 widely supported
            .notifications = has_modern_term,
            .graphics = has_modern_term,
            .truecolor = has_truecolor or has_modern_term,
            .mouse = true, // Standard in most terminals
        };
    }
};

// =============================================================================
// Smart Components (simplified versions)
// =============================================================================

pub const NotificationHandler = struct {
    enabled: bool = true,

    pub fn init(capabilities: CapabilitySet) NotificationHandler {
        _ = capabilities; // Not used anymore, capabilities detected from term module
        return NotificationHandler{};
    }

    pub fn send(self: *NotificationHandler, title: []const u8, message: ?[]const u8) !void {
        if (!self.enabled) return;

        const caps = term_mod.capabilities.getTermCaps();
        const stdout = std.fs.File.stdout().writer();

        if (caps.supportsNotifyOsc9) {
            // Use system notification (OSC 9) via term module
            const notification_text = if (message) |msg|
                try std.fmt.allocPrint(std.heap.page_allocator, "{s}: {s}", .{ title, msg })
            else
                try std.fmt.allocPrint(std.heap.page_allocator, "{s}", .{title});
            defer std.heap.page_allocator.free(notification_text);

            try term_mod.ansi.notification.writeNotification(stdout, std.heap.page_allocator, caps, notification_text);
        } else {
            // Fallback to console output with proper formatting
            if (message) |msg| {
                try stdout.print("ℹ {s}: {s}\n", .{ title, msg });
            } else {
                try stdout.print("ℹ {s}\n", .{title});
            }
        }
    }
};

pub const Clipboard = struct {
    pub fn init(capabilities: CapabilitySet) Clipboard {
        _ = capabilities; // Not used anymore, capabilities detected from term module
        return Clipboard{};
    }

    pub fn copy(data: []const u8) !void {
        const caps = term_mod.capabilities.getTermCaps();
        const stdout = std.fs.File.stdout().writer();

        if (caps.supportsClipboardOsc52) {
            // Use OSC 52 to copy to clipboard via term module
            try term_mod.ansi.clipboard.setSystemClipboard(stdout, caps, std.heap.page_allocator, data);
            // Show confirmation
            try stdout.print("📋 Copied to clipboard: {s}\n", .{data[0..@min(50, data.len)]});
        } else {
            try stdout.print("📄 Copy manually: {s}\n", .{data});
        }
    }
};

pub const Hyperlink = struct {
    pub fn init(capabilities: CapabilitySet) Hyperlink {
        _ = capabilities; // Not used anymore, capabilities detected from term module
        return Hyperlink{};
    }

    pub fn writeLink(writer: anytype, url: []const u8, text: []const u8) !void {
        const caps = term_mod.capabilities.getTermCaps();

        if (caps.supportsHyperlinkOsc8) {
            // Use OSC 8 for actual hyperlinks via term module
            try term_mod.ansi.hyperlink.writeHyperlink(writer, std.heap.page_allocator, caps, url, text);
        } else {
            try writer.print("{s} ({s})", .{ text, url });
        }
    }
};

// =============================================================================
// CLI Context - Central coordination
// =============================================================================

pub const Cli = struct {
    allocator: std.mem.Allocator,
    capabilities: CapabilitySet,
    notification: NotificationHandler,
    clipboard: Clipboard,
    hyperlink: Hyperlink,
    verbose: bool = false,

    pub fn init(allocator: std.mem.Allocator) Cli {
        const capabilities = CapabilitySet.detect();

        return Cli{
            .allocator = allocator,
            .capabilities = capabilities,
            .notification = NotificationHandler.init(capabilities),
            .clipboard = Clipboard.init(capabilities),
            .hyperlink = Hyperlink.init(capabilities),
        };
    }

    pub fn hasFeature(self: *Cli, feature: enum { hyperlinks, clipboard, notifications, graphics, truecolor, mouse }) bool {
        return switch (feature) {
            .hyperlinks => self.capabilities.hyperlinks,
            .clipboard => self.capabilities.clipboard,
            .notifications => self.capabilities.notifications,
            .graphics => self.capabilities.graphics,
            .truecolor => self.capabilities.truecolor,
            .mouse => self.capabilities.mouse,
        };
    }

    pub fn capabilitySummary(self: *Cli) []const u8 {
        if (self.capabilities.hyperlinks and self.capabilities.clipboard and self.capabilities.graphics) {
            return "Full Enhanced Terminal";
        } else if (self.capabilities.hyperlinks or self.capabilities.clipboard) {
            return "Enhanced Terminal";
        } else {
            return "Basic Terminal";
        }
    }

    pub fn enableVerbose(self: *Cli) void {
        self.verbose = true;
    }

    pub fn verboseLog(self: *Cli, comptime fmt: []const u8, args: anytype) void {
        if (self.verbose) {
            const stdout = std.fs.File.stdout().writer();
            stdout.print("[VERBOSE] " ++ fmt ++ "\n", args) catch {};
        }
    }
};

// =============================================================================
// Command Router with Pipeline Support
// =============================================================================

pub const CommandRouter = struct {
    allocator: std.mem.Allocator,
    context: *Cli,

    pub fn init(allocator: std.mem.Allocator, ctx: *Cli) CommandRouter {
        return CommandRouter{
            .allocator = allocator,
            .context = ctx,
        };
    }

    pub fn execute(self: *CommandRouter, args: []const []const u8) !CommandResult {
        if (args.len == 0) {
            return self.executeHelp();
        }

        const command = args[0];

        // Check for pipeline syntax
        const full_command = try std.mem.join(self.allocator, " ", args);
        defer self.allocator.free(full_command);

        if (std.mem.indexOf(u8, full_command, "|")) |_| {
            return self.executePipeline(full_command);
        }

        // Route to command handlers
        if (std.mem.eql(u8, command, "help")) {
            return self.executeHelp();
        } else if (std.mem.eql(u8, command, "version")) {
            return self.executeVersion();
        } else if (std.mem.eql(u8, command, "auth")) {
            return self.executeAuth(args[1..]);
        } else if (std.mem.eql(u8, command, "interactive")) {
            return self.executeInteractive();
        } else if (std.mem.eql(u8, command, "workflow")) {
            return self.executeWorkflow(args[1..]);
        } else {
            // Default to chat
            return self.executeChat(args);
        }
    }

    fn executePipeline(self: *CommandRouter, pipeline: []const u8) !CommandResult {
        if (self.context.verbose) {
            self.context.verboseLog("Executing pipeline: {s}", .{pipeline});
        }

        var stages = std.mem.splitScalar(u8, pipeline, '|');
        var current_output: ?[]const u8 = null;

        while (stages.next()) |stage| {
            const trimmed_stage = std.mem.trim(u8, stage, " \t");

            if (std.mem.eql(u8, trimmed_stage, "clipboard")) {
                if (current_output) |output| {
                    try self.context.clipboard.copy(output);
                    try self.context.notification.send("Pipeline", "Output copied to clipboard");
                }
            } else if (std.mem.eql(u8, trimmed_stage, "format json")) {
                if (current_output) |output| {
                    const json_output = try std.fmt.allocPrint(self.allocator, "{{\"result\": \"{s}\"}}", .{output});
                    if (current_output) |curr_out| {
                        if (curr_out.ptr != pipeline.ptr) {
                            self.allocator.free(curr_out);
                        }
                    }
                    current_output = json_output;
                }
            } else {
                // Execute as simple command (avoid recursion)
                if (std.mem.startsWith(u8, trimmed_stage, "auth status")) {
                    if (current_output) |curr_out| {
                        if (curr_out.ptr != pipeline.ptr) {
                            self.allocator.free(curr_out);
                        }
                    }
                    current_output = try self.allocator.dupe(u8, "✓ Authenticated");
                } else {
                    // Default passthrough
                    if (current_output) |curr_out| {
                        if (curr_out.ptr != pipeline.ptr) {
                            self.allocator.free(curr_out);
                        }
                    }
                    current_output = try self.allocator.dupe(u8, trimmed_stage);
                }
            }
        }

        return CommandResult.ok(current_output);
    }

    fn executeHelp(self: *CommandRouter) !CommandResult {
        const help_text =
            \\Unified CLI with Smart Terminal Integration
            \\
            \\Commands:
            \\  help              Show this help
            \\  version           Show version
            \\  auth <subcommand> Authentication commands
            \\    status          Show auth status
            \\    login           Authenticate
            \\  interactive       Interactive mode
            \\  workflow <name>   Execute workflows
            \\    auth-setup      Setup authentication
            \\
            \\Pipeline Examples:
            \\  auth status | clipboard
            \\  auth status | format json | clipboard
            \\
            \\Terminal Features:
        ;

        // Build capabilities list
        var capabilities_text: [256]u8 = undefined;
        var len: usize = 0;

        if (self.context.hasFeature(.hyperlinks)) {
            const addition = "  ✓ Hyperlinks supported\n";
            @memcpy(capabilities_text[len .. len + addition.len], addition);
            len += addition.len;
        }
        if (self.context.hasFeature(.clipboard)) {
            const addition = "  ✓ Clipboard integration\n";
            @memcpy(capabilities_text[len .. len + addition.len], addition);
            len += addition.len;
        }
        if (self.context.hasFeature(.notifications)) {
            const addition = "  ✓ System notifications\n";
            @memcpy(capabilities_text[len .. len + addition.len], addition);
            len += addition.len;
        }

        const full_text = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ help_text, capabilities_text[0..len] });

        return CommandResult.ok(full_text);
    }

    fn executeVersion(self: *CommandRouter) !CommandResult {
        const version_text = try std.fmt.allocPrint(self.allocator, "CLI v1.0.0\nTerminal: {s}\nCapabilities: hyperlinks={}, clipboard={}, notifications={}", .{
            self.context.capabilitySummary(),
            self.context.capabilities.hyperlinks,
            self.context.capabilities.clipboard,
            self.context.capabilities.notifications,
        });

        return CommandResult.ok(version_text);
    }

    fn executeAuth(self: *CommandRouter, args: []const []const u8) !CommandResult {
        if (args.len == 0) {
            return CommandResult.err("Auth command requires subcommand (status|login)", 1);
        }

        const subcommand = args[0];

        if (std.mem.eql(u8, subcommand, "status")) {
            try self.context.notification.send("Auth Check", "Checking authentication status");

            const status = if (self.context.hasFeature(.hyperlinks))
                "✓ Authenticated (terminal features available)"
            else
                "✓ Authenticated";

            const output = try self.allocator.dupe(u8, status);
            return CommandResult.ok(output);
        } else if (std.mem.eql(u8, subcommand, "login")) {
            try self.context.notification.send("Authentication", "Starting login process");

            const output = try self.allocator.dupe(u8, "✓ Login successful");
            return CommandResult.ok(output);
        } else {
            return CommandResult.err("Unknown auth subcommand", 1);
        }
    }

    fn executeInteractive(self: *CommandRouter) !CommandResult {
        if (self.context.hasFeature(.hyperlinks)) {
            try self.context.notification.send("Interactive Mode", "Features available");
        }

        const message = if (self.context.hasFeature(.hyperlinks) or self.context.hasFeature(.mouse))
            "🚀 Interactive mode with terminal features"
        else
            "📟 Interactive mode (basic terminal)";

        const output = try self.allocator.dupe(u8, message);
        return CommandResult.ok(output);
    }

    fn executeWorkflow(self: *CommandRouter, args: []const []const u8) !CommandResult {
        if (args.len == 0) {
            const workflows_list = "Available workflows:\n  • auth-setup - Authentication setup\n  • config-check - Configuration validation";
            const output = try self.allocator.dupe(u8, workflows_list);
            return CommandResult.ok(output);
        }

        const workflow_name = args[0];

        try self.context.notification.send("Workflow", "Starting workflow execution");

        if (std.mem.eql(u8, workflow_name, "auth-setup")) {
            // Simulate workflow steps
            if (self.context.verbose) {
                self.context.verboseLog("Step 1/3: Checking network connectivity", .{});
                self.context.verboseLog("Step 2/3: Validating API key", .{});
                self.context.verboseLog("Step 3/3: Testing authentication", .{});
            }

            try self.context.notification.send("Workflow Complete", "Authentication setup finished");
            const output = try self.allocator.dupe(u8, "✅ Auth setup workflow completed successfully");
            return CommandResult.ok(output);
        } else {
            return CommandResult.err("Unknown workflow", 1);
        }
    }

    fn executeChat(self: *CommandRouter, args: []const []const u8) !CommandResult {
        const message = try std.mem.join(self.allocator, " ", args);
        defer self.allocator.free(message);

        try self.context.notification.send("Chat", "Processing message with AI");

        const response = try std.fmt.allocPrint(self.allocator, "🤖 AI Response to: \"{s}\"\n(This would be the actual AI response in a real implementation)", .{message});

        return CommandResult.ok(response);
    }
};

// =============================================================================
// Main CLI Application
// =============================================================================

pub const CliApp = struct {
    allocator: std.mem.Allocator,
    context: Cli,
    router: CommandRouter,

    pub fn init(allocator: std.mem.Allocator) CliApp {
        var context = Cli.init(allocator);
        const router = CommandRouter.init(allocator, &context);

        return CliApp{
            .allocator = allocator,
            .context = context,
            .router = router,
        };
    }

    pub fn run(self: *CliApp, args: []const []const u8) !u8 {
        // Check for global flags
        for (args) |arg| {
            if (std.mem.eql(u8, arg, "--verbose")) {
                self.context.enableVerbose();
            }
        }

        if (self.context.verbose) {
            self.context.verboseLog("Terminal capabilities: {s}", .{self.context.capabilitySummary()});
        }

        // Execute command
        const result = try self.router.execute(args);

        // Handle result
        const stdout = std.fs.File.stdout().writer();
        const stderr = std.fs.File.stderr().writer();

        if (result.success) {
            if (result.output) |output| {
                stdout.print("{s}\n", .{output}) catch {};
                self.allocator.free(output);
            }
            return result.exit_code;
        } else {
            if (result.error_msg) |msg| {
                stderr.print("Error: {s}\n", .{msg}) catch {};
            }
            return result.exit_code;
        }
    }
};

// =============================================================================
// Demo Main Function
// =============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File.stdout().writer();
    try stdout.print("=== Unified CLI Architecture Demo ===\n\n", .{});

    var app = CliApp.init(allocator);

    // Demo 1: Show capabilities and help
    try stdout.print("1. Capability Detection and Help:\n", .{});
    try stdout.print("Terminal Type: {s}\n", .{app.context.capabilitySummary()});
    _ = try app.run(&[_][]const u8{"help"});

    try stdout.print("\n==================================================\n", .{});

    // Demo 2: Basic commands
    try stdout.print("2. Basic Commands:\n", .{});
    _ = try app.run(&[_][]const u8{"version"});
    try stdout.print("\n", .{});
    _ = try app.run(&[_][]const u8{ "auth", "status" });

    try stdout.print("\n==================================================\n", .{});

    // Demo 3: Pipeline commands
    try stdout.print("3. Pipeline Commands:\n", .{});
    _ = try app.run(&[_][]const u8{"auth status | clipboard"});
    try stdout.print("\n", .{});
    _ = try app.run(&[_][]const u8{"auth status | format json"});

    try stdout.print("\n==================================================\n", .{});

    // Demo 4: Workflow execution
    try stdout.print("4. Workflow Execution:\n", .{});
    _ = try app.run(&[_][]const u8{ "workflow", "auth-setup", "--verbose" });

    try stdout.print("\n==================================================\n", .{});

    // Demo 5: Smart components showcase
    try stdout.print("5. Smart Components:\n", .{});
    demoSmartComponents(&app.context);

    try stdout.print("\n=== Demo Complete ===\n", .{});
    try stdout.print("✅ Successfully demonstrated CLI architecture\n", .{});
}

fn demoSmartComponents(ctx: *Cli) void {
    const stdout = std.fs.File.stdout().writer();
    stdout.print("Smart Component Examples:\n\n", .{}) catch {};

    // Hyperlink example
    stdout.print("Hyperlink Component:\n", .{}) catch {};
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout_interface = &stdout_writer.interface;
    Hyperlink.writeLink(stdout_interface, "https://docs.example.com", "Documentation") catch {};
    stdout_interface.flush() catch {};
    stdout.print("\n", .{}) catch {};
    Hyperlink.writeLink(stdout_interface, "https://api.example.com", "API Reference") catch {};
    stdout_interface.flush() catch {};
    stdout.print("\n\n", .{}) catch {};

    // Notification example
    stdout.print("Notification Component:\n", .{}) catch {};
    ctx.notification.send("Demo Notification", "This shows how notifications work") catch {};

    // Clipboard example
    stdout.print("Clipboard Component:\n", .{}) catch {};
    Clipboard.copy("Sample text for clipboard") catch {};
}
