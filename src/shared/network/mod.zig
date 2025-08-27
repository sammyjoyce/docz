//! Network Module
//! Network and API communication utilities
//!
//! This module provides a unified interface for network functionality,
//! including HTTP clients, API integrations, and streaming protocols.

const std = @import("std");

// Core HTTP client functionality
pub const curl = @import("curl.zig");

// Anthropic API client
pub const anthropic = @import("anthropic.zig");

// Server-Sent Events (SSE) parsing
pub const sse = @import("sse.zig");

// Re-export commonly used types for convenience

// HTTP client types
pub const HTTPError = curl.HTTPError;
pub const HTTPMethod = curl.HTTPMethod;
pub const Header = curl.Header;
pub const HTTPRequest = curl.HTTPRequest;
pub const HTTPResponse = curl.HTTPResponse;

// Anthropic API types
pub const MessageRole = anthropic.MessageRole;
pub const Message = anthropic.Message;

// OAuth types (defined in anthropic module to avoid circular dependencies)
pub const OAuthCredentials = anthropic.OAuthCredentials;
pub const PkceParams = anthropic.PkceParams;

// SSE types
pub const SSEError = sse.SSEError;
pub const SSEField = sse.SSEField;
pub const SSEEvent = sse.SSEEvent;
pub const SSEParser = sse.SSEParser;

/// Initialize the network module
pub fn init() void {
    std.log.debug("Network module initialized", .{});
}
