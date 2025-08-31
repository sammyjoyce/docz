//! Legacy Network Modules (Deprecated)
//! These shims are provided for transitional compatibility only.
//! They compile only when built with `-Dlegacy`.
//!
//! Migrate to `@import("shared/network/anthropic/mod.zig")` and the split
//! clients (`client.zig`, `models.zig`, `stream.zig`, `oauth.zig`).

// Anthropic monolithic client (deprecated)
pub const anthropic = @import("../anthropic.zig");

// Convenience re-exports for downstream code that referenced legacy paths
pub const curl = @import("../curl.zig");
pub const sse = @import("../sse.zig");
