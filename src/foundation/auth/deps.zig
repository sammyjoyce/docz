//! Dependencies module for auth submodules
//! This file provides access to external dependencies that are added to the auth module
//! by the build system.

// Re-export curl_shared for use by auth submodules
pub const curl = @import("curl_shared");
