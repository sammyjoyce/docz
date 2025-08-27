//! Simple retry policy utilities for Anthropic client

const std = @import("std");

pub const RetryPolicy = struct {
    maxRetries: u8 = 3,
    baseDelayMs: u32 = 200,
    maxDelayMs: u32 = 5_000,

    pub fn backoff(self: RetryPolicy, attempt: u8) u32 {
        const a: u32 = @intCast(attempt);
        const delay = self.baseDelayMs << @min(a, 10);
        return @min(delay, self.maxDelayMs);
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
            if (attempt >= policy.maxRetries) return err;
            const delayMs = policy.backoff(attempt);
            std.time.sleep(@as(u64, delayMs) * std.time.ns_per_ms);
            continue;
        }
    }
}
