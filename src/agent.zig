//! Backward-compatible facade over the new core engine + selected agent spec.
//! This keeps existing imports (`@import("agent.zig")`) working while allowing
//! different agents to be selected at build time.

const engine = @import("core_engine");
const selected_spec = @import("agent_spec");

pub const CliOptions = engine.CliOptions;

pub const setupOAuth = engine.setupOAuth;
pub const showAuthStatus = engine.showAuthStatus;
pub const refreshAuth = engine.refreshAuth;

pub fn run(allocator: std.mem.Allocator) !void {
    const default_options = CliOptions{
        .options = .{
            .model = "claude-3-sonnet-20240229",
            .output = null,
            .input = null,
            .system = null,
            .config = null,
            .max_tokens = 4096,
            .temperature = 0.7,
        },
        .flags = .{
            .verbose = false,
            .help = false,
            .version = false,
            .stream = true,
            .pretty = false,
            .debug = false,
            .interactive = false,
        },
        .positionals = null,
    };
    try runWithOptions(allocator, default_options);
}

pub fn runWithOptions(allocator: std.mem.Allocator, options: CliOptions) !void {
    try engine.runWithOptions(allocator, options, selected_spec.SPEC);
}
