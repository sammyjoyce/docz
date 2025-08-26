// Reset the terminal to its initial state (RIS).
// See: https://vt100.net/docs/vt510-rm/RIS.html

pub const ResetInitialState: []const u8 = "\x1bc";
pub const RIS = ResetInitialState;
