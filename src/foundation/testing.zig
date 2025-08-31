//! Testing Framework Module
//!
//! Barrel for testing utilities. Import via this barrel from tests; do not
//! deep-import subfiles.

pub const snapshot = @import("testing/snapshot.zig");

// Re-export main types for convenience
pub const SnapshotTester = snapshot.SnapshotTester;
pub const SnapshotConfig = snapshot.SnapshotConfig;
pub const SnapshotResult = snapshot.SnapshotResult;
pub const SnapshotError = snapshot.SnapshotError;
pub const TestTerminal = snapshot.TestTerminal;

// Re-export main functions for convenience
pub const expectSnapshot = snapshot.expectSnapshot;
pub const updateSnapshot = snapshot.updateSnapshot;
pub const createTester = snapshot.createTester;
pub const captureOutput = snapshot.captureOutput;
pub const withTestTerminal = snapshot.withTestTerminal;
pub const expectSnapshotPass = snapshot.expectSnapshotPass;
