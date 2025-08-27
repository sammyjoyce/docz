//! Testing Framework Module
//!
//! This module provides comprehensive testing utilities for the project,
//! including snapshot testing for TUI components.

pub const snapshot = @import("snapshot.zig");

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
