//! Network Module
//! Network and API communication utilities
//!
//! This module provides a unified interface for network functionality,
//! including HTTP clients, API integrations, and streaming protocols.

const std = @import("std");

// Core HTTP client functionality
pub const curl = @import("curl.zig");

// Anthropic API client (legacy + split)
pub const anthropic = @import("anthropic.zig");
pub const anthropic_sub = @import("anthropic/mod.zig");

// Server-Sent Events (SSE) parsing
pub const sse = @import("sse.zig");

// Re-export commonly used types for convenience

// HTTP client types
pub const HTTPError = curl.HTTPError;
pub const HTTPMethod = curl.HTTPMethod;
pub const Header = curl.Header;
pub const HTTPRequest = curl.HTTPRequest;
pub const HTTPResponse = curl.HTTPResponse;

// Anthropic API types (prefer new split module models; legacy remains available)
pub const MessageRole = anthropic_sub.models.MessageRole;
pub const Message = anthropic_sub.models.Message;

// OAuth types
pub const OAuthCredentials = anthropic_sub.models.OAuthCredentials;
pub const Pkce = anthropic_sub.models.Pkce;

// SSE types
pub const SSEError = sse.SSEError;
pub const SSEField = sse.SSEField;
pub const SSEEvent = sse.SSEEvent;
pub const SSEEventFinal = sse.SSEEventFinal;
pub const SSEProcessing = sse.SSEProcessing;

/// Initialize the network module
pub fn init() void {
    std.log.debug("Network module initialized", .{});
}
