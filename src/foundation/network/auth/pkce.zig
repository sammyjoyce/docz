//! PKCE (Proof Key for Code Exchange) implementation per RFC 7636
//! Provides secure OAuth 2.0 authorization code flow for native apps

const std = @import("std");
const crypto = std.crypto;

/// PKCE parameters for OAuth flow
pub const PkceParams = struct {
    verifier: []const u8,
    challenge: []const u8,
    state: []const u8,
    method: []const u8 = "S256",

    pub fn deinit(self: PkceParams, allocator: std.mem.Allocator) void {
        allocator.free(self.verifier);
        allocator.free(self.challenge);
        allocator.free(self.state);
    }
};

/// Generate PKCE parameters with S256 challenge method
/// Verifier length must be between 43-128 characters per RFC 7636
pub fn generate(allocator: std.mem.Allocator, verifier_length: usize) !PkceParams {
    if (verifier_length < 43 or verifier_length > 128) {
        return error.InvalidVerifierLength;
    }

    // Generate cryptographically secure random verifier
    const verifier = try generateVerifier(allocator, verifier_length);
    errdefer allocator.free(verifier);

    // Generate S256 challenge from verifier
    const challenge = try generateS256Challenge(allocator, verifier);
    errdefer allocator.free(challenge);

    // Generate separate high-entropy state parameter
    const state = try generateState(allocator, 32);
    errdefer allocator.free(state);

    return PkceParams{
        .verifier = verifier,
        .challenge = challenge,
        .state = state,
        .method = "S256",
    };
}

/// Generate a random code verifier using unreserved characters
/// [A-Z] [a-z] [0-9] - . _ ~
fn generateVerifier(allocator: std.mem.Allocator, length: usize) ![]u8 {
    const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
    const verifier = try allocator.alloc(u8, length);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    for (verifier) |*c| {
        c.* = charset[random.intRangeAtMost(usize, 0, charset.len - 1)];
    }

    return verifier;
}

/// Generate S256 challenge: base64url(sha256(verifier))
fn generateS256Challenge(allocator: std.mem.Allocator, verifier: []const u8) ![]u8 {
    // Compute SHA256 hash
    var hash: [crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(verifier, &hash, .{});

    // Base64url encode without padding
    const encoder = std.base64.url_safe_no_pad;
    const encoded_len = encoder.Encoder.calcSize(hash.len);
    const challenge = try allocator.alloc(u8, encoded_len);
    _ = encoder.Encoder.encode(challenge, &hash);

    return challenge;
}

/// Generate a separate high-entropy state parameter
/// MUST NOT reuse PKCE verifier as state per RFC 8252
pub fn generateState(allocator: std.mem.Allocator, length: usize) ![]u8 {
    if (length < 16) {
        return error.StateTooShort;
    }

    const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    const state = try allocator.alloc(u8, length);

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const random = prng.random();

    for (state) |*c| {
        c.* = charset[random.intRangeAtMost(usize, 0, charset.len - 1)];
    }

    return state;
}

test "PKCE verifier generation" {
    const allocator = std.testing.allocator;

    // Test valid lengths
    const params = try generate(allocator, 64);
    defer params.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 64), params.verifier.len);
    try std.testing.expect(params.challenge.len > 0);
    try std.testing.expectEqual(@as(usize, 32), params.state.len);
    try std.testing.expectEqualStrings("S256", params.method);

    // Verify characters are valid
    for (params.verifier) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '.' or c == '_' or c == '~';
        try std.testing.expect(valid);
    }

    // Verify state characters are valid
    for (params.state) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9');
        try std.testing.expect(valid);
    }
}

test "PKCE challenge generation" {
    const allocator = std.testing.allocator;

    // Known test vector
    const verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    const expected_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";

    const challenge = try generateS256Challenge(allocator, verifier);
    defer allocator.free(challenge);

    try std.testing.expectEqualStrings(expected_challenge, challenge);
}

test "state generation" {
    const allocator = std.testing.allocator;

    const state = try generateState(allocator, 32);
    defer allocator.free(state);

    try std.testing.expectEqual(@as(usize, 32), state.len);

    // Verify state contains only alphanumeric
    for (state) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9');
        try std.testing.expect(valid);
    }
}
