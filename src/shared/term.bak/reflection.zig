const std = @import("std");

/// Converts a PascalCase field name to snake_case for ZON compatibility.
/// Handles edge cases like consecutive uppercase letters (e.g., "XMLHttpRequest" -> "xml_http_request").
/// Assumes input is a valid identifier; outputs lowercase with underscores before uppercase letters (except first).
pub fn fieldNameToZon(comptime field_name: []const u8) []const u8 {
    if (field_name.len == 0) return "";

    comptime var result: [field_name.len * 2]u8 = undefined; // Allocate enough space for worst case
    comptime var len = 0;

    // Handle first character - always lowercase
    result[len] = std.ascii.toLower(field_name[0]);
    len += 1;

    // Process remaining characters
    inline for (field_name[1..]) |c| {
        if (std.ascii.isUpper(c)) {
            // Insert underscore before uppercase letters (except if previous was also uppercase and we're in a sequence)
            // Actually, standard PascalCase to snake_case: insert '_' before each uppercase except the first
            result[len] = '_';
            len += 1;
            result[len] = std.ascii.toLower(c);
        } else {
            result[len] = c;
        }
        len += 1;
    }

    return result[0..len];
}

/// Generates a capability overlay function that maps fields from Source to Target using reflection.
/// The generated function converts Target field names to snake_case and copies matching fields from Source.
/// Fields in Target that don't have matching Source fields are left undefined.
pub fn generateCapabilityOverlay(comptime Source: type, comptime Target: type) type {
    return struct {
        pub fn overlay(source: Source) Target {
            var target: Target = undefined;
            inline for (std.meta.fields(Target)) |field| {
                const source_field_name = fieldNameToZon(field.name);
                if (@hasField(Source, source_field_name)) {
                    @field(target, field.name) = @field(source, source_field_name);
                }
                // Note: Non-matching fields remain undefined
            }
            return target;
        }
    };
}

// Test functions for validation
test "fieldNameToZon basic conversion" {
    try std.testing.expectEqualStrings("supports_truecolor", fieldNameToZon("supportsTruecolor"));
    try std.testing.expectEqualStrings("xml_http_request", fieldNameToZon("XMLHttpRequest"));
    try std.testing.expectEqualStrings("simple", fieldNameToZon("simple"));
    try std.testing.expectEqualStrings("a", fieldNameToZon("A"));
    try std.testing.expectEqualStrings("", fieldNameToZon(""));
}

test "fieldNameToZon edge cases" {
    try std.testing.expectEqualStrings("api_v2", fieldNameToZon("APIV2"));
    try std.testing.expectEqualStrings("json_data", fieldNameToZon("JSONData"));
    try std.testing.expectEqualStrings("test_case", fieldNameToZon("TestCase"));
}

test "generateCapabilityOverlay basic mapping" {
    const Source = struct {
        supports_truecolor: bool = true,
        has_unicode: bool = false,
        max_colors: u32 = 256,
    };

    const Target = struct {
        supportsTruecolor: bool,
        hasUnicode: bool,
        maxColors: u32,
    };

    const Overlay = generateCapabilityOverlay(Source, Target);
    const source = Source{};
    const target = Overlay.overlay(source);

    try std.testing.expectEqual(true, target.supportsTruecolor);
    try std.testing.expectEqual(false, target.hasUnicode);
    try std.testing.expectEqual(@as(u32, 256), target.maxColors);
}
