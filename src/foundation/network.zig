//! Network Module
//! Network and API communication utilities
//!
//! Import via this barrel; feature-gate in consumers with
//! `@import("../shared/mod.zig").options.feature_network_anthropic` (or your
//! own flags) and override default behavior via root `shared_options`.
//!
//! This module provides a common interface for network functionality,
//! including HTTP clients, API integrations, and streaming protocols.

const std = @import("std");

// Core HTTP client functionality
pub const curl = @import("network/curl.zig");

// Anthropic API client
pub const anthropic = @import("network/anthropic.zig");

// Legacy network module (if needed)
pub const legacy = @import("network/legacy.zig");

// Server-Sent Events (SSE) parsing
pub const sse = @import("network/sse.zig");

// Network client interface for abstraction and testing
pub const client = @import("network/client.zig");
pub const use = client.use; // expose duck-typed client adapter at barrel

// Re-export commonly used types for convenience

// HTTP client types
pub const HTTPError = curl.HTTPError;
pub const HTTPMethod = curl.HTTPMethod;
pub const Header = curl.Header;
pub const HTTPRequest = curl.HTTPRequest;
pub const HTTPResponse = curl.HTTPResponse;

// Anthropic API types (prefer new split module models; legacy remains available)
pub const MessageRole = anthropic.models.MessageRole;
pub const Message = anthropic.models.Message;
pub const MessageParameters = anthropic.MessageParameters;
pub const MessageResult = anthropic.MessageResult;
pub const StreamParams = anthropic.StreamParams;

// OAuth types
pub const Credentials = anthropic.models.Credentials;
pub const Pkce = anthropic.models.Pkce;

// SSE types
pub const ServerSentEventError = sse.ServerSentEventError;
pub const ServerSentEventField = sse.ServerSentEventField;
pub const ServerSentEvent = sse.ServerSentEvent;
pub const SSEEventBuilder = sse.SSEEventBuilder;
pub const ServerSentEventConfig = sse.ServerSentEventConfig;

// Client types
pub const Service = client.Service;
pub const ClientError = client.Error;
pub const Request = client.NetworkRequest;
pub const Response = client.NetworkResponse;
pub const Event = client.NetworkEvent;

/// Initialize the network module
pub fn init() void {
    std.log.debug("Network module initialized", .{});
}
