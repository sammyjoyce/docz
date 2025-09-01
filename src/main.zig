//! Main entry point for the Docz CLI application
//! Handles OAuth authentication and agent REPL functionality

const std = @import("std");
const foundation = @import("foundation.zig");
const cli = foundation.cli;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "auth")) {
        if (args.len < 3) {
            try printAuthUsage();
            return;
        }

        const auth_cmd = args[2];

        if (std.mem.eql(u8, auth_cmd, "login")) {
            // Parse login flags
            var port: u16 = 8080;
            var host: []const u8 = "localhost";
            var manual = false;

            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
                    port = try std.fmt.parseInt(u16, args[i + 1], 10);
                    i += 1;
                } else if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
                    host = args[i + 1];
                    i += 1;
                } else if (std.mem.eql(u8, args[i], "--manual")) {
                    manual = true;
                }
            }

            try cli.Auth.Commands.login(allocator, .{
                .port = port,
                .host = host,
                .manual = manual,
            });
        } else if (std.mem.eql(u8, auth_cmd, "status")) {
            try cli.Auth.Commands.status(allocator);
        } else if (std.mem.eql(u8, auth_cmd, "whoami")) {
            try cli.Auth.Commands.whoami(allocator);
        } else if (std.mem.eql(u8, auth_cmd, "logout")) {
            try cli.Auth.Commands.logout(allocator);
        } else if (std.mem.eql(u8, auth_cmd, "test-call")) {
            var stream = false;

            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (std.mem.eql(u8, args[i], "--stream")) {
                    stream = true;
                }
            }

            try cli.Auth.Commands.testCall(allocator, .{ .stream = stream });
        } else {
            try printAuthUsage();
        }
    } else if (std.mem.eql(u8, command, "run")) {
        // Parse run flags
        var config = cli.Run.RunConfig{};

        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--model") and i + 1 < args.len) {
                config.model = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--max-tokens") and i + 1 < args.len) {
                config.max_tokens = try std.fmt.parseInt(u32, args[i + 1], 10);
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--temperature") and i + 1 < args.len) {
                config.temperature = try std.fmt.parseFloat(f32, args[i + 1]);
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--no-stream")) {
                config.stream = false;
            } else if (std.mem.eql(u8, args[i], "--system") and i + 1 < args.len) {
                config.system_prompt = args[i + 1];
                i += 1;
            }
        }

        try cli.Run.handleRunCommand(allocator, config);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help")) {
        try printUsage();
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version")) {
        try printVersion();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Docz - AI Agent CLI with OAuth Authentication
        \\
        \\Usage: docz <command> [options]
        \\
        \\Commands:
        \\  auth login [--port 8080] [--host localhost] [--manual]
        \\                    Authenticate with Claude Pro/Max via OAuth
        \\  auth status       Show authentication status
        \\  auth whoami       Display authenticated user information
        \\  auth logout       Remove stored credentials
        \\  auth test-call [--stream]
        \\                    Test API connection with a simple call
        \\
        \\  run [options]     Start the agent REPL
        \\    --model <name>      Model to use (default: claude-3-5-sonnet-20241022)
        \\    --max-tokens <n>    Maximum tokens (default: 4096)
        \\    --temperature <f>   Temperature (default: 0.7)
        \\    --no-stream         Disable streaming responses
        \\    --system <prompt>   System prompt
        \\
        \\  help              Show this help message
        \\  version           Show version information
        \\
    , .{});
}

fn printAuthUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Auth commands:
        \\  docz auth login [--port 8080] [--host localhost] [--manual]
        \\  docz auth status
        \\  docz auth whoami
        \\  docz auth logout
        \\  docz auth test-call [--stream]
        \\
    , .{});
}

fn printVersion() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Docz version 1.0.0\n", .{});
    try stdout.print("Zig version: 0.15.1\n", .{});
}
