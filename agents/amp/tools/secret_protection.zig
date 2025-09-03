//! Secret File Protection Tool
//!
//! Detects and prevents access to secret files and sensitive information.
//! Based on specs/amp/prompts/amp-secret-file-protection.md specification.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Input parameters for secret file protection check
const SecretProtectionInput = struct {
    file_path: ?[]const u8 = null,
    content: ?[]const u8 = null,
    operation: []const u8, // "read", "write", "modify", "delete"
};

/// Secret protection result
const SecretProtectionResult = struct {
    success: bool = true,
    tool: []const u8 = "secret_protection",
    is_secret_file: bool,
    risk_level: []const u8, // "low", "medium", "high", "critical"
    detected_patterns: [][]const u8,
    recommendation: []const u8,
    allow_operation: bool,
};

/// Execute secret file protection check
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch {
        const ResponseMapper = toolsMod.JsonReflector.mapper(SecretProtectionResult);
        const response = SecretProtectionResult{
            .success = false,
            .is_secret_file = true,
            .risk_level = "critical",
            .detected_patterns = &[0][]const u8{},
            .recommendation = "Error during analysis - assume file contains secrets",
            .allow_operation = false,
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    // Parse request
    const RequestMapper = toolsMod.JsonReflector.mapper(SecretProtectionInput);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    const input = request.value;
    var detected_patterns = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer detected_patterns.deinit(allocator);

    var is_secret_file = false;
    var risk_level: []const u8 = "low";
    var allow_operation = true;

    // Check file path patterns
    if (input.file_path) |file_path| {
        const secret_file_patterns = [_][]const u8{ ".env", ".env.", "secrets.", "secret.", "password", "passwd", "credentials", "creds", "token", "key", "cert", "pem", "p12", "keystore", "keychain", "wallet", "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".ssh/", ".gnupg/", ".gpg", "config/auth", "auth.json", "auth.yaml", "auth.yml", ".netrc", ".htpasswd", "shadow", "master.key", "database.yml", "database.yaml" };

        const file_path_lower = try std.ascii.allocLowerString(allocator, file_path);
        defer allocator.free(file_path_lower);

        for (secret_file_patterns) |pattern| {
            if (std.mem.indexOf(u8, file_path_lower, pattern) != null) {
                is_secret_file = true;
                try detected_patterns.append(allocator, try std.fmt.allocPrint(allocator, "secret file pattern: {s}", .{pattern}));
                risk_level = "critical";
                allow_operation = false;
                break;
            }
        }

        // Check for backup or temporary files containing secrets
        const temp_secret_patterns = [_][]const u8{ ".bak", ".backup", ".tmp", ".temp", "~", ".orig", ".save" };

        if (is_secret_file) {
            for (temp_secret_patterns) |temp_pattern| {
                if (std.mem.endsWith(u8, file_path_lower, temp_pattern)) {
                    try detected_patterns.append(allocator, try std.fmt.allocPrint(allocator, "temporary secret file: {s}", .{temp_pattern}));
                    break;
                }
            }
        }
    }

    // Check content patterns
    if (input.content) |content| {
        const secret_content_patterns = [_][]const u8{ "password", "passwd", "secret", "token", "api_key", "apikey", "access_key", "secret_key", "private_key", "cert", "certificate", "auth", "oauth", "bearer", "basic", "credential", "cred", "ssh-rsa", "ssh-dss", "-----BEGIN", "-----END", "PRIVATE KEY", "CLIENT_SECRET", "CLIENT_ID", "AWS_SECRET", "GITHUB_TOKEN", "DATABASE_URL", "MONGODB_URI", "REDIS_URL", "JWT_SECRET", "ENCRYPTION_KEY", "MASTER_KEY", "SALT", "HASH", "MD5", "SHA" };

        const content_lower = try std.ascii.allocLowerString(allocator, content);
        defer allocator.free(content_lower);

        for (secret_content_patterns) |pattern| {
            if (std.mem.indexOf(u8, content_lower, pattern) != null) {
                is_secret_file = true;
                try detected_patterns.append(allocator, try std.fmt.allocPrint(allocator, "secret content pattern: {s}", .{pattern}));
                if (std.mem.eql(u8, risk_level, "low")) {
                    risk_level = "high";
                }
                allow_operation = false;
            }
        }

        // Check for structured secret formats
        const structured_patterns = [_][]const u8{ "\"password\":", "\"token\":", "\"secret\":", "\"key\":", "password=", "token=", "secret=", "key=", "auth=", "Bearer ", "Basic ", "pk_", "sk_", "rsa_", "ecdsa_" };

        for (structured_patterns) |pattern| {
            if (std.mem.indexOf(u8, content, pattern) != null) {
                is_secret_file = true;
                try detected_patterns.append(allocator, try std.fmt.allocPrint(allocator, "structured secret: {s}", .{pattern}));
                risk_level = "critical";
                allow_operation = false;
            }
        }

        // Check for base64 encoded potential secrets (heuristic)
        var lines = std.mem.splitSequence(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len > 32 and isLikelyBase64(trimmed)) {
                is_secret_file = true;
                try detected_patterns.append(allocator, "potential base64 encoded secret");
                if (std.mem.eql(u8, risk_level, "low") or std.mem.eql(u8, risk_level, "medium")) {
                    risk_level = "high";
                }
                allow_operation = false;
                break;
            }
        }
    }

    // Generate recommendation based on operation and risk level
    var recommendation: []const u8 = undefined;

    if (!is_secret_file) {
        recommendation = "File appears safe for the requested operation.";
        allow_operation = true;
    } else {
        const operation = input.operation;
        if (std.mem.eql(u8, operation, "read")) {
            recommendation = "BLOCKED: Never read secret files directly. Ask the user to provide the information needed or manually edit the file.";
        } else if (std.mem.eql(u8, operation, "write") or std.mem.eql(u8, operation, "modify")) {
            recommendation = "BLOCKED: Never modify secret files directly. Ask the user to manually edit the file with appropriate security measures.";
        } else if (std.mem.eql(u8, operation, "delete")) {
            recommendation = "BLOCKED: Never delete secret files automatically. Confirm with the user before any deletion operations.";
        } else {
            recommendation = "BLOCKED: Operation on secret file requires manual user intervention for security.";
        }
    }

    const patterns_slice = try detected_patterns.toOwnedSlice(allocator);

    const result = SecretProtectionResult{
        .is_secret_file = is_secret_file,
        .risk_level = risk_level,
        .detected_patterns = patterns_slice,
        .recommendation = recommendation,
        .allow_operation = allow_operation,
    };

    const ResponseMapper = toolsMod.JsonReflector.mapper(SecretProtectionResult);
    return ResponseMapper.toJsonValue(allocator, result);
}

/// Check if a string is likely base64 encoded
fn isLikelyBase64(s: []const u8) bool {
    if (s.len < 16) return false; // Too short to be meaningful
    if (s.len % 4 != 0) return false; // Base64 should be multiple of 4

    var valid_chars: u32 = 0;
    var padding_count: u32 = 0;

    for (s) |c| {
        if ((c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '+' or c == '/')
        {
            valid_chars += 1;
        } else if (c == '=') {
            padding_count += 1;
        } else {
            return false; // Invalid base64 character
        }
    }

    // High ratio of valid base64 characters and reasonable padding
    const valid_ratio = @as(f32, @floatFromInt(valid_chars)) / @as(f32, @floatFromInt(s.len));
    return valid_ratio > 0.8 and padding_count <= 2;
}
