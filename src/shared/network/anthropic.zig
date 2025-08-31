//! Anthropic submodule barrel export (transitional)
//! Provides new submodule locations while maintaining legacy API.

// New split submodules (incremental adoption)
pub const models = @import("anthropic/models.zig");
pub const oauth = @import("anthropic/oauth.zig");
pub const client = @import("anthropic/client.zig");
pub const stream = @import("anthropic/stream.zig");
pub const retry = @import("anthropic/retry.zig");

// Stable API re-exports to enable gradual migration away from the legacy file
// without forcing downstream callers to change their imports immediately.
pub const Client = client.Client;
pub const Error = models.Error;
pub const Message = models.Message;
pub const MessageRole = models.MessageRole;
pub const Stream = models.Stream;
pub const Complete = models.Complete;
pub const CompletionResult = models.CompletionResult;
pub const Usage = models.Usage;
pub const Credentials = models.Credentials;
pub const Pkce = models.Pkce;
pub const MessageParameters = client.MessageParameters;
pub const MessageResult = client.MessageResult;
pub const StreamParams = client.StreamParams;

// Note: explicit re-exports should be added incrementally as the split progresses.

// Re-export curl for dependent modules
pub const curl = @import("curl_shared");
