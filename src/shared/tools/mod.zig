//! Shared tools registry and utilities.
//! Provides common tools that all agents can use.

pub const Registry = @import("tools.zig").Registry;
pub const registerBuiltins = @import("tools.zig").registerBuiltins;
pub const ToolError = @import("tools.zig").ToolError;
pub const ToolMetadata = @import("tools.zig").ToolMetadata;
pub const JSONToolFunction = @import("tools.zig").JSONToolFunction;
pub const registerJsonTool = @import("tools.zig").registerJsonTool;
