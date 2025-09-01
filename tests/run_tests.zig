//! Test runner for OAuth and engine tests

const std = @import("std");

pub fn main() !void {
    std.testing.log_level = .warn;
    
    // Run OAuth tests
    _ = @import("oauth.zig");
    
    // Run engine integration tests
    _ = @import("engine_integration.zig");
}

test {
    // Include all test files
    _ = @import("oauth.zig");
    _ = @import("engine_integration.zig");
}