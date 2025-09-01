//! Build-time configuration options for DocZ
//! These options control feature compilation and runtime behavior

/// OAuth authentication support
pub const oauth_enabled = true;

/// Include anthropic-beta header for OAuth requests
pub const oauth_beta_header = true;

/// SSE streaming support for Anthropic Messages API
pub const streaming_enabled = true;

/// Use OS keychain for credential storage (macOS Keychain, Windows Credential Manager, Linux Secret Service)
pub const keychain_enabled = false;

/// Require localhost in OAuth redirect URIs (security requirement)
pub const oauth_allow_localhost = true;

/// HTTP verbose logging for debugging
pub const http_verbose_default = false;

/// Anthropic beta header value for OAuth
pub const anthropic_beta_oauth = "oauth-2025-04-20";
