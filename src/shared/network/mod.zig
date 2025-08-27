//! Network Module
//! Network and API communication utilities
//!
//! This module provides a unified interface for network functionality,
//! including HTTP clients, API integrations, and streaming protocols.

const std = @import("std");

// Core HTTP client functionality
pub const curl = @import("curl.zig");

// Anthropic API client (prefer split; legacy kept as alias)
pub const anthropic = @import("anthropic/mod.zig");
pub const anthropic_legacy = @import("anthropic.zig");

// Server-Sent Events (SSE) parsing
pub const sse = @import("sse.zig");

// Network service interface for abstraction and testing
pub const service = @import("service.zig");

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

// OAuth types
pub const Credentials = anthropic.models.Credentials;
pub const Pkce = anthropic.models.Pkce;

// SSE types
pub const SSEError = sse.SSEError;
pub const SSEField = sse.SSEField;
pub const SSEEvent = sse.SSEEvent;
pub const SSEEventFinal = sse.SSEEventFinal;
pub const SSEProcessing = sse.SSEProcessing;

// Service types
pub const NetworkService = service.Service;
pub const NetworkError = service.NetworkError;

/// Initialize the network module
pub fn init() void {
    std.log.debug("Network module initialized", .{});
}
