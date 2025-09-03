//! Default agent specification
//! Minimal agent for basic REPL functionality with OAuth

const std = @import("std");
const engine = @import("core_engine");
const foundation = @import("foundation");
const tools = foundation.tools;

fn buildSystemPrompt(allocator: std.mem.Allocator, opts: engine.CliOptions) ![]const u8 {
    _ = opts;

    // Read anthropic_spoof.txt content per spec requirements
    const spoofContent = blk: {
        const spoofFile = std.fs.cwd().openFile("prompt/anthropic_spoof.txt", .{}) catch {
            break :blk "";
        };
        defer spoofFile.close();
        break :blk spoofFile.readToEndAlloc(allocator, 1024) catch "";
    };
    defer if (spoofContent.len > 0) allocator.free(spoofContent);

    if (spoofContent.len > 0) {
        return std.fmt.allocPrint(allocator, "{s}\n\nYou are a helpful AI assistant powered by Claude. Be concise and helpful.", .{spoofContent});
    } else {
        return allocator.dupe(u8, "You are a helpful AI assistant powered by Claude. Be concise and helpful.");
    }
}

fn registerTools(registry: *tools.Registry) !void {
    // Register built-in tools
    try tools.registerBuiltins(registry);
}

pub const SPEC: engine.AgentSpec = .{
    .buildSystemPrompt = buildSystemPrompt,
    .registerTools = registerTools,
};
