//! Terminal Query Module
//!
//! This module provides functionality for querying terminal capabilities
//! and state, including device attributes, cursor position, and terminal identification.

const std = @import("std");

// Core query modules
pub const system = @import("../query.zig");
pub const queries = @import("../ansi/queries.zig");

// ============================================================================
// TYPE EXPORTS
// ============================================================================

pub const QuerySystem = system.QuerySystem;
pub const DeviceAttributes = queries.DeviceAttributes;
pub const CursorPosition = queries.CursorPosition;

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Query device attributes
pub fn queryDeviceAttributes() !DeviceAttributes {
    return queries.queryDeviceAttributes();
}

/// Query cursor position
pub fn queryCursorPosition() !CursorPosition {
    return queries.queryCursorPosition();
}

/// Query terminal identification
pub fn queryTerminalId() ![]const u8 {
    return queries.queryTerminalId();
}

// ============================================================================
// TESTS
// ============================================================================

test "query module exports" {
    std.testing.refAllDecls(system);
    std.testing.refAllDecls(queries);
}
