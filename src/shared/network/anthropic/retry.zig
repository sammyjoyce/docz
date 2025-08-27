//! Simple retry policy utilities for Anthropic client

const std = @import("std");

pub const RetryPolicy = struct {
    max_retries: u8 = 3,
    base_delay_ms: u32 = 200,
    max_delay_ms: u32 = 5_000,

    pub fn backoff(self: RetryPolicy, attempt: u8) u32 {
        const a: u32 = @intCast(attempt);
        const delay = self.base_delay_ms << @min(a, 10);
        return @min(delay, self.max_delay_ms);
    }
};

pub fn withRetry(
    allocator: std.mem.Allocator,
    policy: RetryPolicy,
    op: *const fn () anyerror!void,
) anyerror!void {
    _ = allocator; // reserved for future jitter seed
    var attempt: u8 = 0;
    while (true) : (attempt += 1) {
        const result = op();
        if (result) |_| {
            return;
        } else |err| {
            if (attempt >= policy.max_retries) return err;
            const delay_ms = policy.backoff(attempt);
            std.time.sleep(@as(u64, delay_ms) * std.time.ns_per_ms);
            continue;
        }
    }
}
