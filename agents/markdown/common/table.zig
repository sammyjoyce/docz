const std = @import("std");

pub const Error = error{
    InvalidTable,
    OutOfMemory,
    InvalidRowIndex,
    InvalidColumnIndex,
    ValidationFailed,
    RepairFailed,
};

pub const Alignment = enum {
    left,
    center,
    right,
};

pub const Table = struct {
    headers: [][]const u8,
    rows: [][]const []const u8,
    alignments: []Alignment,

    pub fn deinit(self: *Table, allocator: std.mem.Allocator) void {
        for (self.headers) |header| {
            allocator.free(header);
        }
        allocator.free(self.headers);

        for (self.rows) |row| {
            for (row) |cell| {
                allocator.free(cell);
            }
            allocator.free(row);
        }
        allocator.free(self.rows);
        allocator.free(self.alignments);
    }
};

/// Parse a markdown table from text
pub fn parseTable(allocator: std.mem.Allocator, text: []const u8) Error!?Table {
    var lines = std.mem.split(u8, text, "\n");
    var line_list = std.ArrayList([]const u8).init(allocator);
    defer line_list.deinit();

    // Collect lines that might be part of a table
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len > 0 and trimmed[0] == '|') {
            try line_list.append(trimmed);
        }
    }

    if (line_list.items.len < 2) return null; // Need at least header and separator

    // Parse header
    const header_line = line_list.items[0];
    const headers = try parseTableRow(allocator, header_line);

    // Parse separator and alignments
    const separator_line = line_list.items[1];
    const alignments = try parseAlignment(allocator, separator_line, headers.len);

    // Parse data rows
    var rows = std.ArrayList([]const []const u8).init(allocator);
    for (line_list.items[2..]) |line| {
        const row = try parseTableRow(allocator, line);
        if (row.len == headers.len) { // Only include rows with correct column count
            try rows.append(row);
        } else {
            // Free the malformed row
            for (row) |cell| allocator.free(cell);
            allocator.free(row);
        }
    }

    return Table{
        .headers = headers,
        .rows = rows.toOwnedSlice(),
        .alignments = alignments,
    };
}

/// Parse a single table row
fn parseTableRow(allocator: std.mem.Allocator, line: []const u8) Error![][]const u8 {
    var cells = std.ArrayList([]const u8).init(allocator);
    var cell_parts = std.mem.split(u8, line, "|");

    // Skip first empty part (before initial |)
    _ = cell_parts.next();

    while (cell_parts.next()) |cell| {
        const trimmed = std.mem.trim(u8, cell, " \t");
        const cell_content = try allocator.dupe(u8, trimmed);
        try cells.append(cell_content);
    }

    return cells.toOwnedSlice();
}

/// Parse alignment row
fn parseAlignment(allocator: std.mem.Allocator, line: []const u8, expected_columns: usize) Error![]Alignment {
    var alignments = std.ArrayList(Alignment).init(allocator);
    var cell_parts = std.mem.split(u8, line, "|");

    // Skip first empty part
    _ = cell_parts.next();

    while (cell_parts.next()) |cell| {
        const trimmed = std.mem.trim(u8, cell, " \t");

        if (trimmed.len == 0) continue;

        const alignment = blk: {
            const starts_colon = trimmed[0] == ':';
            const ends_colon = trimmed[trimmed.len - 1] == ':';

            if (starts_colon and ends_colon) {
                break :blk Alignment.center;
            } else if (ends_colon) {
                break :blk Alignment.right;
            } else {
                break :blk Alignment.left;
            }
        };

        try alignments.append(alignment);
    }

    // Ensure we have the right number of alignments
    while (alignments.items.len < expected_columns) {
        try alignments.append(Alignment.left);
    }

    return alignments.toOwnedSlice();
}

/// Format a table as markdown
pub fn formatTable(allocator: std.mem.Allocator, table: *const Table) Error![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    // Calculate column widths
    var col_widths = try allocator.alloc(usize, table.headers.len);
    defer allocator.free(col_widths);

    // Initialize with header widths
    for (table.headers, 0..) |header, i| {
        col_widths[i] = header.len;
    }

    // Check data row widths
    for (table.rows) |row| {
        for (row, 0..) |cell, i| {
            if (i < col_widths.len and cell.len > col_widths[i]) {
                col_widths[i] = cell.len;
            }
        }
    }

    // Ensure minimum width for separators
    for (col_widths, 0..) |*width, i| {
        const min_width = switch (table.alignments[i]) {
            .left => 3, // "---"
            .right => 4, // "---:"
            .center => 5, // ":---:"
        };
        if (width.* < min_width) width.* = min_width;
    }

    // Write header
    try result.append('|');
    for (table.headers, 0..) |header, i| {
        try result.append(' ');
        try result.appendSlice(header);
        const padding = col_widths[i] - header.len;
        try result.appendNTimes(' ', padding);
        try result.appendSlice(" |");
    }
    try result.append('\n');

    // Write separator
    try result.append('|');
    for (table.alignments, 0..) |alignment, i| {
        try result.append(' ');

        switch (alignment) {
            .left => {
                try result.appendNTimes('-', col_widths[i]);
            },
            .right => {
                try result.appendNTimes('-', col_widths[i] - 1);
                try result.append(':');
            },
            .center => {
                try result.append(':');
                try result.appendNTimes('-', col_widths[i] - 2);
                try result.append(':');
            },
        }

        try result.appendSlice(" |");
    }
    try result.append('\n');

    // Write data rows
    for (table.rows) |row| {
        try result.append('|');
        for (row, 0..) |cell, i| {
            try result.append(' ');

            const padding = col_widths[i] - cell.len;
            switch (table.alignments[i]) {
                .left => {
                    try result.appendSlice(cell);
                    try result.appendNTimes(' ', padding);
                },
                .right => {
                    try result.appendNTimes(' ', padding);
                    try result.appendSlice(cell);
                },
                .center => {
                    const left_pad = padding / 2;
                    const right_pad = padding - left_pad;
                    try result.appendNTimes(' ', left_pad);
                    try result.appendSlice(cell);
                    try result.appendNTimes(' ', right_pad);
                },
            }

            try result.appendSlice(" |");
        }
        try result.append('\n');
    }

    return result.toOwnedSlice();
}

/// Create a new table
pub fn createTable(allocator: std.mem.Allocator, headers: []const []const u8, rows: []const []const []const u8, alignments: ?[]const Alignment) Error!Table {
    // Copy headers
    var new_headers = try allocator.alloc([]const u8, headers.len);
    for (headers, 0..) |header, i| {
        new_headers[i] = try allocator.dupe(u8, header);
    }

    // Copy rows
    var new_rows = try allocator.alloc([]const []const u8, rows.len);
    for (rows, 0..) |row, i| {
        var new_row = try allocator.alloc([]const u8, row.len);
        for (row, 0..) |cell, j| {
            new_row[j] = try allocator.dupe(u8, cell);
        }
        new_rows[i] = new_row;
    }

    // Set alignments
    var new_alignments = try allocator.alloc(Alignment, headers.len);
    if (alignments) |aligns| {
        const copy_len = @min(aligns.len, headers.len);
        @memcpy(new_alignments[0..copy_len], aligns[0..copy_len]);
        // Fill any remaining with left alignment
        for (new_alignments[copy_len..]) |*alignment| {
            alignment.* = Alignment.left;
        }
    } else {
        // Default to left alignment
        for (new_alignments) |*alignment| {
            alignment.* = Alignment.left;
        }
    }

    return Table{
        .headers = new_headers,
        .rows = new_rows,
        .alignments = new_alignments,
    };
}

/// Add a row to a table
pub fn addRow(allocator: std.mem.Allocator, table: *Table, row_data: []const []const u8) Error!void {
    // Copy the new row
    var new_row = try allocator.alloc([]const u8, row_data.len);
    for (row_data, 0..) |cell, i| {
        new_row[i] = try allocator.dupe(u8, cell);
    }

    // Extend the rows array
    const old_rows = table.rows;
    table.rows = try allocator.alloc([]const []const u8, old_rows.len + 1);
    @memcpy(table.rows[0..old_rows.len], old_rows);
    table.rows[old_rows.len] = new_row;

    allocator.free(old_rows);
}

/// Update a cell in a table
pub fn updateCell(table: *Table, row_index: usize, col_index: usize, new_content: []const u8, allocator: std.mem.Allocator) Error!void {
    if (row_index >= table.rows.len) return Error.InvalidRowIndex;
    if (col_index >= table.rows[row_index].len) return Error.InvalidColumnIndex;

    // Free old content
    allocator.free(table.rows[row_index][col_index]);

    // Set new content
    table.rows[row_index][col_index] = try allocator.dupe(u8, new_content);
}

/// Table validation issue types
pub const ValidationIssueType = enum {
    inconsistent_column_count,
    empty_table,
    malformed_separator,
    invalid_alignment,
    missing_headers,
    excessive_whitespace,
    empty_cells,
};

/// Table validation issue severity
pub const ValidationSeverity = enum {
    err,
    warning,
    info,
};

/// Individual validation issue
pub const ValidationIssue = struct {
    issue_type: ValidationIssueType,
    severity: ValidationSeverity,
    message: []const u8,
    line_number: ?usize = null,
    column_index: ?usize = null,
    row_index: ?usize = null,
};

/// Table validation configuration
pub const ValidationConfig = struct {
    check_column_consistency: bool = true,
    check_empty_cells: bool = true,
    check_alignment_format: bool = true,
    check_separator_format: bool = true,
    allow_empty_table: bool = false,
    max_cell_length: usize = 1000,
    trim_whitespace: bool = true,
};

/// Table validation result
pub const ValidationResult = struct {
    is_valid: bool,
    issues: []ValidationIssue,
    suggestions: [][]const u8,

    pub fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void {
        for (self.issues) |issue| {
            allocator.free(issue.message);
        }
        allocator.free(self.issues);

        for (self.suggestions) |suggestion| {
            allocator.free(suggestion);
        }
        allocator.free(self.suggestions);
    }
};

/// Table repair configuration
pub const RepairConfig = struct {
    fix_column_consistency: bool = true,
    trim_whitespace: bool = true,
    fill_empty_cells: bool = false,
    empty_cell_placeholder: []const u8 = "",
    normalize_alignments: bool = true,
    remove_empty_rows: bool = false,
};

/// Validate a table structure and identify issues (simplified implementation)
pub fn validateTable(allocator: std.mem.Allocator, tbl: *const Table, config: ValidationConfig) Error!ValidationResult {
    var issues = std.array_list.Managed(ValidationIssue).init(allocator);
    var suggestions = std.array_list.Managed([]const u8).init(allocator);

    // Check for empty table
    if (tbl.headers.len == 0 and tbl.rows.len == 0) {
        if (!config.allow_empty_table) {
            try issues.append(ValidationIssue{
                .issue_type = .empty_table,
                .severity = .err,
                .message = try allocator.dupe(u8, "Table is empty - no headers or rows found"),
            });
            try suggestions.append(try allocator.dupe(u8, "Add table headers and at least one data row"));
        }
    }

    // Check column consistency
    if (config.check_column_consistency and tbl.headers.len > 0) {
        const expected_columns = tbl.headers.len;

        // Check alignment array length
        if (tbl.alignments.len != expected_columns) {
            const msg = try std.fmt.allocPrint(allocator, "Alignment count ({}) doesn't match header count ({})", .{ tbl.alignments.len, expected_columns });
            try issues.append(ValidationIssue{
                .issue_type = .invalid_alignment,
                .severity = .err,
                .message = msg,
            });
        }

        // Check each row's column count
        for (tbl.rows, 0..) |row, row_idx| {
            if (row.len != expected_columns) {
                const msg = try std.fmt.allocPrint(allocator, "Row {} has {} columns, expected {}", .{ row_idx, row.len, expected_columns });
                try issues.append(ValidationIssue{
                    .issue_type = .inconsistent_column_count,
                    .severity = .err,
                    .message = msg,
                    .row_index = row_idx,
                });
            }
        }
    }

    const is_valid = blk: {
        for (issues.items) |issue| {
            if (issue.severity == .err) {
                break :blk false;
            }
        }
        break :blk true;
    };

    return ValidationResult{
        .is_valid = is_valid,
        .issues = try issues.toOwnedSlice(),
        .suggestions = try suggestions.toOwnedSlice(),
    };
}

/// Repair common table issues (simplified implementation)
pub fn repairTable(allocator: std.mem.Allocator, tbl: *Table, config: RepairConfig) Error!usize {
    var repairs_made: usize = 0;

    if (tbl.headers.len == 0) {
        return Error.RepairFailed;
    }

    const expected_columns = tbl.headers.len;

    // Fix alignment array length
    if (config.normalize_alignments and tbl.alignments.len != expected_columns) {
        const old_alignments = tbl.alignments;
        tbl.alignments = try allocator.alloc(Alignment, expected_columns);

        const copy_len = @min(old_alignments.len, expected_columns);
        @memcpy(tbl.alignments[0..copy_len], old_alignments[0..copy_len]);

        for (tbl.alignments[copy_len..]) |*alignment| {
            alignment.* = Alignment.left;
        }

        allocator.free(old_alignments);
        repairs_made += 1;
    }

    return repairs_made;
}

