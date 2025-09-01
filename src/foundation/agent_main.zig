//! Agent main entry point with CLI parsing and agent orchestration.
//! Provides common CLI parsing, argument handling, and engine delegation.
//!
//! This module focuses on core agent functionality without forcing UI dependencies.
//! Theme and UX framework integration is available through optional imports.

const std = @import("std");

/// Main function for agents with CLI parsing and engine execution.
/// Agents should call this from their main.zig with their specific spec.
pub fn runAgent(comptime Engine: type, allocator: std.mem.Allocator, spec: anytype) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cliArgs = if (args.len > 1) args[1..] else args[0..0];

    const cliArgsConst = try allocator.alloc([]const u8, cliArgs.len);
    defer allocator.free(cliArgsConst);
    for (cliArgs, 0..) |arg, i| {
        cliArgsConst[i] = std.mem.sliceTo(arg, 0);
    }

    // Handle auth subcommands
    if (cliArgsConst.len > 0 and std.mem.eql(u8, cliArgsConst[0], "auth")) {
        try handleAuthCommand(allocator, cliArgsConst[1..]);
        return;
    }

    // Handle run command (default)
    if (cliArgsConst.len == 0 or (cliArgsConst.len > 0 and std.mem.eql(u8, cliArgsConst[0], "run"))) {
        const runArgs = if (cliArgsConst.len > 0) cliArgsConst[1..] else cliArgsConst[0..0];
        try runAgentLoop(Engine, allocator, spec, runArgs);
        return;
    }

    // Unknown command
    std.log.err("Unknown command: {s}", .{cliArgsConst[0]});
    std.log.info("Available commands: auth, run", .{});
    return error.InvalidCommand;
}

/// Handle auth subcommands
fn handleAuthCommand(allocator: std.mem.Allocator, subArgs: [][]const u8) !void {
    if (subArgs.len == 0) {
        std.log.err("Auth subcommand required. Available: login, status, whoami, logout, test-call", .{});
        return error.MissingSubcommand;
    }

    const subcommand = subArgs[0];
    const auth = @import("cli/auth.zig");

    if (std.mem.eql(u8, subcommand, "login")) {
        const manual = hasFlag(subArgs, "--manual");
        const port = getPortArg(subArgs) orelse 54545;
        const host = getStringArg(subArgs, "--host") orelse "localhost";

        try auth.Commands.login(allocator, .{
            .port = port,
            .host = host,
            .manual = manual,
        });
    } else if (std.mem.eql(u8, subcommand, "status")) {
        try auth.Commands.status(allocator);
    } else if (std.mem.eql(u8, subcommand, "whoami")) {
        try auth.Commands.whoami(allocator);
    } else if (std.mem.eql(u8, subcommand, "logout")) {
        try auth.Commands.logout(allocator);
    } else if (std.mem.eql(u8, subcommand, "test-call")) {
        const stream = hasFlag(subArgs, "--stream");
        try auth.Commands.testCall(allocator, .{ .stream = stream });
    } else {
        std.log.err("Unknown auth subcommand: {s}", .{subcommand});
        std.log.info("Available: login, status, whoami, logout, test-call", .{});
        return error.InvalidSubcommand;
    }
}

/// Run the main agent loop (engine-agnostic).
/// The engine type is provided by the caller to avoid module cycles.
pub fn runAgentLoop(comptime Engine: type, allocator: std.mem.Allocator, spec: anytype, runArgs: [][]const u8) !void {
    // Parse CLI options for the run command
    const options = try parseRunOptions(Engine, allocator, runArgs);
    defer cleanupRunOptions(Engine, allocator, &options);

    // Delegate to the provided Engine module
    try Engine.runWithOptions(allocator, options, spec, ".");
}

/// Parse CLI options for the run command
fn parseRunOptions(comptime Engine: type, allocator: std.mem.Allocator, args: [][]const u8) !Engine.CliOptions {
    var options = Engine.CliOptions{
        .model = "claude-3-5-sonnet-20241022",
        .max_tokens = 4096,
        .temperature = 0.7,
        .stream = true,
        .verbose = false,
    };

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--model") or std.mem.eql(u8, arg, "-m")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.model = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--max-tokens")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.max_tokens = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--temperature") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.temperature = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, arg, "--no-stream")) {
            options.stream = false;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--input") or std.mem.eql(u8, arg, "-i")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.input = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.output = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--history")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            options.history = try allocator.dupe(u8, args[i]);
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // Positional argument (input text)
            options.input = try allocator.dupe(u8, arg);
        }
    }

    return options;
}

/// Clean up allocated strings in run options
fn cleanupRunOptions(comptime _: type, allocator: std.mem.Allocator, options: anytype) void {
    // Check if model was allocated (not the default constant)
    const default_model = "claude-3-5-sonnet-20241022";
    if (options.model.ptr != default_model.ptr and options.model.len > 0) {
        allocator.free(options.model);
    }
    if (options.input) |input| allocator.free(input);
    if (options.output) |output| allocator.free(output);
    if (options.history) |history| allocator.free(history);
}

/// Helper functions for parsing arguments
fn hasFlag(args: [][]const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

fn getPortArg(args: [][]const u8) ?u16 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--port")) {
            if (i + 1 < args.len) {
                const port_str = args[i + 1];
                if (std.fmt.parseInt(u16, port_str, 10)) |port| {
                    return port;
                } else |_| {
                    return null; // Invalid port number
                }
            }
            return null; // No port value provided
        }
    }
    return null;
}

fn getStringArg(args: [][]const u8, flag: []const u8) ?[]const u8 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, flag)) {
            if (i + 1 < args.len) {
                return args[i + 1];
            }
            return null; // No value provided
        }
    }
    return null;
}
