//! Shared tools registry and utilities.
//! Provides common tools that all agents can use.

pub const Registry = @import("tools.zig").Registry;
pub const registerBuiltIns = @import("tools.zig").registerBuiltIns;
pub const ToolError = @import("tools.zig").ToolError;
pub const registerJsonTool = @import("tools.zig").registerJsonTool;
