const std = @import("std");
const pkce = @import("src/foundation/network/auth/pkce.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generate PKCE params
    const params = try pkce.generate(allocator, 64);
    defer params.deinit(allocator);

    std.debug.print("Verifier: {s}\n", .{params.verifier});
    std.debug.print("Challenge: {s}\n", .{params.challenge});
    std.debug.print("State: {s}\n", .{params.state});

    // Check lengths
    std.debug.print("\nLengths:\n", .{});
    std.debug.print("Verifier length: {d}\n", .{params.verifier.len});
    std.debug.print("Challenge length: {d}\n", .{params.challenge.len});
    std.debug.print("State length: {d}\n", .{params.state.len});

    // Check if challenge contains only valid base64url characters
    std.debug.print("\nChallenge character check:\n", .{});
    for (params.challenge) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') {
            std.debug.print("Invalid character in challenge: {c} (0x{x})\n", .{ c, c });
        }
    }

    // Generate a test case like in the successful request
    std.debug.print("\nExample URL query param:\n", .{});
    std.debug.print("code_challenge={s}&code_challenge_method=S256\n", .{params.challenge});
}
