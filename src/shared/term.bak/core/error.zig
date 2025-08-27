//! Unified Error Sets for Terminal Module

/// Primary terminal error set covering all terminal operations
pub const TermError = error{
    Unsupported,
    InvalidState,
    SizeDetectionFailed,
    TerminalNotAvailable,
    Timeout,
    InvalidParameter,
    OutOfMemory,
    IoError,
    NotImplemented,
    Disconnected,
};
