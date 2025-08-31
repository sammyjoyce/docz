//! Legacy CLI Module (Deprecated)
//! This module provides backward-compatible CLI parsing APIs.
//! Deprecated: enable only with -Dlegacy to include in builds.

pub const Parser = @import("Parser.zig").Parser;
pub const Args = @import("Parser.zig").Args;
pub const extras = @import("Extras.zig");
