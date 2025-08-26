//! Root entry delegates to the selected agent entry via a build-registered module.
pub const main = @import("agent_entry").main;
