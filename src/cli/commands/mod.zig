//! CLI commands module
//! Organized command implementations

// For now, re-export existing command types
pub const AuthSubcommand = @import("../core/types.zig").AuthSubcommand;
pub const Command = @import("../core/types.zig").Command;

// Future command implementations would go here:
// pub const auth = @import("auth.zig");
// pub const chat = @import("chat.zig");
// pub const help = @import("help.zig");
