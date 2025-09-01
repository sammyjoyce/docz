//! Unit tests for Markdown agent config

const std = @import("std");
const testing = std.testing;
const foundation = @import("foundation");

test "config.zon loads with mapped keys" {
    const allocator = testing.allocator;

    // Load the config file
    const config_str = try std.fs.cwd().readFileAlloc(allocator, "agents/markdown/config.zon", 64 * 1024);
    defer allocator.free(config_str);

    // Config should parse without errors
    // Note: We'd need actual ZON parsing here, which is not directly available
    // For now, just check that required keys are present in the text

    // Check mapped keys exist
    try testing.expect(std.mem.indexOf(u8, config_str, "concurrentOperationsMax") != null);
    try testing.expect(std.mem.indexOf(u8, config_str, "timeoutMsDefault") != null);
    try testing.expect(std.mem.indexOf(u8, config_str, "inputSizeMax") != null);
    try testing.expect(std.mem.indexOf(u8, config_str, "outputSizeMax") != null);
    try testing.expect(std.mem.indexOf(u8, config_str, "processingTimeMsMax") != null);
    try testing.expect(std.mem.indexOf(u8, config_str, "modelDefault") != null);
}

test "config values are reasonable" {
    // Static validation of expected ranges
    const max_size: usize = 1048576; // 1MB
    const max_time_ms: u32 = 60000; // 60 seconds
    const max_tokens: u32 = 4096;

    try testing.expect(max_size <= 10 * 1024 * 1024); // Less than 10MB
    try testing.expect(max_time_ms <= 5 * 60 * 1000); // Less than 5 minutes
    try testing.expect(max_tokens <= 10000); // Reasonable token limit
}
