//! Network operations with integrated authentication support.
//! Layer: network (standalone, no UI dependencies)

const std = @import("std");
const deps = @import("internal/deps.zig");
comptime {
    deps.assertLayer(.network);
}

// Provider-agnostic HTTP interface
pub const Http = @import("network/Http.zig");
pub const HttpCurl = @import("network/HttpCurl.zig");
pub const SSE = @import("network/SSE.zig");

// Legacy compatibility - will be deprecated
pub const curl = @import("network/curl.zig");

// Unified error handling
pub const Error = Http.Error;
pub const asNetworkError = @import("network/auth/Errors.zig").asNetwork;

// Authentication namespace - headless only
pub const Auth = struct {
    pub const Core = @import("network/auth/Core.zig");
    pub const OAuth = @import("network/auth/OAuth.zig"); // NOT Oauth
    pub const Callback = @import("network/auth/Callback.zig");
    pub const Service = @import("network/auth/Service.zig");
    pub const Errors = @import("network/auth/Errors.zig");

    // Convenience re-exports
    pub const AuthMethod = Core.AuthMethod;
    pub const Credentials = Core.Credentials;
    pub const AuthError = Errors.AuthError;
    pub const setupOAuth = OAuth.setupOAuth;
    pub const refreshTokens = OAuth.refreshTokens;

    // NOTE: Auth TUI components are in tui.Auth namespace
};

// Provider-specific implementations (TitleCase namespace)
pub const Anthropic = struct {
    pub const Client = @import("network/providers/anthropic/Client.zig");
    pub const Models = @import("network/providers/anthropic/Models.zig");
    pub const Stream = @import("network/providers/anthropic/Stream.zig");
    pub const Retry = @import("network/providers/anthropic/Retry.zig");
    // Auth moved to avoid module conflicts - use AnthropicAuth separately if needed

    // Convenience re-exports
    pub const Message = Models.Message;
    pub const MessageRole = Models.MessageRole;
    pub const StreamParams = Models.StreamParams;
};

// Anthropic OAuth is separate to avoid module conflicts
pub const AnthropicAuth = @import("network/providers/anthropic/Auth.zig");

// Legacy compatibility exports (will be removed after migration)
pub const HTTPError = curl.HTTPError;
pub const HTTPMethod = curl.HTTPMethod;
pub const Header = curl.Header;
pub const HTTPRequest = curl.HTTPRequest;
pub const HTTPResponse = curl.HTTPResponse;

// SSE types
pub const ServerSentEventError = SSE.ServerSentEventError;
pub const ServerSentEventField = SSE.ServerSentEventField;
pub const ServerSentEvent = SSE.ServerSentEvent;
pub const SSEEventBuilder = SSE.SSEEventBuilder;
pub const ServerSentEventConfig = SSE.ServerSentEventConfig;

/// Initialize the network module
pub fn init() void {
    std.log.debug("Network module initialized", .{});
}
