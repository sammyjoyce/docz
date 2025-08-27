//! Re-export for auth Service (PascalCase filename for single-type module)
//! Maintains compatibility while aligning with naming conventions.

pub const AuthError = @import("service.zig").AuthError;
pub const Credentials = @import("service.zig").Credentials;
pub const Status = @import("service.zig").Status;
pub const Service = @import("service.zig").Service;

