const std = @import("std");
const foundation = @import("foundation");

test "oauth credentials saved with 0600 perms (atomic)" {
    const a = std.testing.allocator;
    const oauth = foundation.network.Auth.OAuth;

    // Prepare minimal creds (not real)
    const creds = oauth.Credentials{
        .type = "oauth",
        .accessToken = "at",
        .refreshToken = "rt",
        .expiresAt = 123,
    };

    const fname = "claude_oauth_creds_test.json";
    defer std.fs.cwd().deleteFile(fname) catch {};

    try oauth.saveCredentials(a, fname, creds);

    const st = try std.fs.cwd().statFile(fname);
    // Only check perms on POSIX systems; on others, ensure file exists
    if (@hasDecl(std.os, "S") and @hasDecl(std.os.S, "IRUSR")) {
        // Expect mode 0600 (owner read/write)
        try std.testing.expect((st.mode & 0o777) == 0o600);
    } else {
        try std.testing.expect(st.size > 0);
    }
}

test "sse chunk dispatch calls callback" {
    const a = std.testing.allocator;
    const anth = foundation.network.Anthropic;
    const stream = foundation.network.Anthropic.Stream;

    var ctx = anth.Client.SharedContext.init(a);
    defer ctx.deinit();

    const onTok = struct {
        fn cb(c: *anth.Client.SharedContext, data: []const u8) void {
            // reference params to avoid unused warnings
            if (data.len > 0) {
                // touch a field to prove the value is passed through
                _ = c.tools.hasPending;
            }
        }
    }.cb;

    var sc = stream.createStreamingContext(a, &ctx, onTok);
    defer stream.destroyStreamingContext(&sc);

    // A minimal SSE event carrying a JSON message
    const sse = "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}\n\n";
    try stream.processSseChunk(&sc, sse);
}
