//! Anthropic submodule barrel export (transitional)
//! Provides new submodule locations while maintaining legacy API.

// New split submodules (incremental adoption)
pub const models = @import("models.zig");
pub const oauth = @import("oauth.zig");
pub const client = @import("client.zig");
pub const stream = @import("stream.zig");
pub const retry = @import("retry.zig");

// Stable API re-exports to enable gradual migration away from the legacy file
// without forcing downstream callers to change their imports immediately.
pub const AnthropicClient = client.AnthropicClient;
pub const Error = models.Error;
pub const Message = models.Message;
pub const MessageRole = models.MessageRole;
pub const Stream = models.Stream;
pub const Complete = models.Complete;
pub const CompletionResponse = models.CompletionResponse;
pub const Usage = models.Usage;
pub const OAuthCredentials = models.OAuthCredentials;
pub const Pkce = models.Pkce;

// Legacy full implementation remains in ../anthropic.zig during transition
pub const legacy = @import("../anthropic.zig");

// Note: explicit re-exports should be added incrementally as the split progresses.
