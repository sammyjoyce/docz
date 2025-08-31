const std = @import("std");
const Allocator = std.mem.Allocator;

/// Supported programming languages for syntax highlighting
pub const Language = enum {
    // Programming languages
    zig,
    javascript,
    typescript,
    python,
    rust,
    go,

    // Data formats
    json,
    yaml,
    toml,
    markdown,

    // Shell and SQL
    shell,
    bash,
    sql,

    // Web technologies
    html,
    css,
    xml,

    // Unknown/plain text
    unknown,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".mjs")) return .javascript;
        if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx")) return .typescript;
        if (std.mem.eql(u8, ext, ".py")) return .python;
        if (std.mem.eql(u8, ext, ".rs")) return .rust;
        if (std.mem.eql(u8, ext, ".go")) return .go;
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return .yaml;
        if (std.mem.eql(u8, ext, ".toml")) return .toml;
        if (std.mem.eql(u8, ext, ".md") or std.mem.eql(u8, ext, ".markdown")) return .markdown;
        if (std.mem.eql(u8, ext, ".sh") or std.mem.eql(u8, ext, ".bash")) return .shell;
        if (std.mem.eql(u8, ext, ".sql")) return .sql;
        if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .html;
        if (std.mem.eql(u8, ext, ".css")) return .css;
        if (std.mem.eql(u8, ext, ".xml")) return .xml;
        return .unknown;
    }

    pub fn fromName(name: []const u8) ?Language {
        inline for (@typeInfo(Language).@"enum".fields) |field| {
            if (std.ascii.eqlIgnoreCase(name, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }
};

/// Token types for syntax highlighting
pub const TokenType = enum {
    // Literals and identifiers
    keyword,
    string,
    number,
    comment,

    // Code structure
    function,
    type_name,
    variable,
    constant,

    // Operators and punctuation
    operator,
    punctuation,
    bracket,

    // Special
    decorator,
    attribute,
    builtin,

    // Default
    text,
};

/// Quality tiers for rendering
pub const QualityTier = enum {
    rich, // Rich truecolor themes
    standard, // 256-color themes
    compatible, // 16-color themes
    minimal, // No highlighting
};

/// Color scheme for syntax highlighting
pub const ColorScheme = struct {
    keyword: []const u8,
    string: []const u8,
    number: []const u8,
    comment: []const u8,
    function: []const u8,
    type_name: []const u8,
    variable: []const u8,
    constant: []const u8,
    operator: []const u8,
    punctuation: []const u8,
    bracket: []const u8,
    decorator: []const u8,
    attribute: []const u8,
    builtin: []const u8,
    text: []const u8,
    line_number: []const u8,

    pub fn getColor(self: ColorScheme, token_type: TokenType) []const u8 {
        return switch (token_type) {
            .keyword => self.keyword,
            .string => self.string,
            .number => self.number,
            .comment => self.comment,
            .function => self.function,
            .type_name => self.type_name,
            .variable => self.variable,
            .constant => self.constant,
            .operator => self.operator,
            .punctuation => self.punctuation,
            .bracket => self.bracket,
            .decorator => self.decorator,
            .attribute => self.attribute,
            .builtin => self.builtin,
            .text => self.text,
        };
    }
};

/// Get color scheme for quality tier
pub fn getColorScheme(quality: QualityTier) ColorScheme {
    return switch (quality) {
        .rich => ColorScheme{
            // Rich truecolor theme (One Dark inspired)
            .keyword = "\x1b[38;2;198;120;221m", // Purple
            .string = "\x1b[38;2;152;195;121m", // Green
            .number = "\x1b[38;2;209;154;102m", // Orange
            .comment = "\x1b[38;2;92;99;112m", // Gray
            .function = "\x1b[38;2;97;175;239m", // Blue
            .type_name = "\x1b[38;2;229;192;123m", // Yellow
            .variable = "\x1b[38;2;224;108;117m", // Red
            .constant = "\x1b[38;2;209;154;102m", // Orange
            .operator = "\x1b[38;2;86;182;194m", // Cyan
            .punctuation = "\x1b[38;2;171;178;191m", // Light gray
            .bracket = "\x1b[38;2;171;178;191m", // Light gray
            .decorator = "\x1b[38;2;198;120;221m", // Purple
            .attribute = "\x1b[38;2;229;192;123m", // Yellow
            .builtin = "\x1b[38;2;86;182;194m", // Cyan
            .text = "\x1b[0m", // Reset
            .line_number = "\x1b[38;2;92;99;112m", // Gray
        },
        .standard => ColorScheme{
            // 256-color theme
            .keyword = "\x1b[38;5;135m", // Purple
            .string = "\x1b[38;5;114m", // Green
            .number = "\x1b[38;5;180m", // Orange
            .comment = "\x1b[38;5;242m", // Gray
            .function = "\x1b[38;5;75m", // Blue
            .type_name = "\x1b[38;5;222m", // Yellow
            .variable = "\x1b[38;5;210m", // Red
            .constant = "\x1b[38;5;180m", // Orange
            .operator = "\x1b[38;5;80m", // Cyan
            .punctuation = "\x1b[38;5;250m", // Light gray
            .bracket = "\x1b[38;5;250m", // Light gray
            .decorator = "\x1b[38;5;135m", // Purple
            .attribute = "\x1b[38;5;222m", // Yellow
            .builtin = "\x1b[38;5;80m", // Cyan
            .text = "\x1b[0m", // Reset
            .line_number = "\x1b[38;5;242m", // Gray
        },
        .compatible => ColorScheme{
            // 16-color theme
            .keyword = "\x1b[35m", // Magenta
            .string = "\x1b[32m", // Green
            .number = "\x1b[33m", // Yellow
            .comment = "\x1b[90m", // Bright black (gray)
            .function = "\x1b[34m", // Blue
            .type_name = "\x1b[93m", // Bright yellow
            .variable = "\x1b[91m", // Bright red
            .constant = "\x1b[33m", // Yellow
            .operator = "\x1b[36m", // Cyan
            .punctuation = "\x1b[37m", // White
            .bracket = "\x1b[37m", // White
            .decorator = "\x1b[95m", // Bright magenta
            .attribute = "\x1b[93m", // Bright yellow
            .builtin = "\x1b[96m", // Bright cyan
            .text = "\x1b[0m", // Reset
            .line_number = "\x1b[90m", // Bright black
        },
        .minimal => ColorScheme{
            // No highlighting
            .keyword = "",
            .string = "",
            .number = "",
            .comment = "",
            .function = "",
            .type_name = "",
            .variable = "",
            .constant = "",
            .operator = "",
            .punctuation = "",
            .bracket = "",
            .decorator = "",
            .attribute = "",
            .builtin = "",
            .text = "",
            .line_number = "",
        },
    };
}

/// Token represents a highlighted piece of code
pub const Token = struct {
    type: TokenType,
    text: []const u8,
};

/// Options for syntax highlighting
pub const HighlightOptions = struct {
    theme: ?ColorScheme = null,
    quality_tier: QualityTier = .standard,
    show_line_numbers: bool = false,
    starting_line: usize = 1,
    tab_width: usize = 4,
};

/// Lexer state for tokenization
const LexerState = struct {
    code: []const u8,
    pos: usize = 0,
    tokens: std.ArrayList(Token),

    fn init(allocator: Allocator, code: []const u8) LexerState {
        return .{
            .code = code,
            .pos = 0,
            .tokens = std.ArrayList(Token).init(allocator),
        };
    }

    fn deinit(self: *LexerState) void {
        self.tokens.deinit();
    }

    fn current(self: *const LexerState) ?u8 {
        if (self.pos >= self.code.len) return null;
        return self.code[self.pos];
    }

    fn peek(self: *const LexerState, offset: usize) ?u8 {
        const idx = self.pos + offset;
        if (idx >= self.code.len) return null;
        return self.code[idx];
    }

    fn advance(self: *LexerState) ?u8 {
        if (self.pos >= self.code.len) return null;
        const ch = self.code[self.pos];
        self.pos += 1;
        return ch;
    }

    fn skipWhitespace(self: *LexerState) void {
        while (self.current()) |ch| {
            if (!std.ascii.isWhitespace(ch)) break;
            _ = self.advance();
        }
    }

    fn readWhile(self: *LexerState, predicate: fn (u8) bool) []const u8 {
        const start = self.pos;
        while (self.current()) |ch| {
            if (!predicate(ch)) break;
            _ = self.advance();
        }
        return self.code[start..self.pos];
    }

    fn readUntil(self: *LexerState, delimiter: u8) []const u8 {
        const start = self.pos;
        while (self.current()) |ch| {
            if (ch == delimiter) break;
            _ = self.advance();
        }
        return self.code[start..self.pos];
    }

    fn readString(self: *LexerState, quote: u8) []const u8 {
        const start = self.pos - 1; // Include opening quote
        var escaped = false;
        while (self.current()) |ch| {
            _ = self.advance();
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if (ch == quote) {
                break;
            }
        }
        return self.code[start..self.pos];
    }

    fn addToken(self: *LexerState, token_type: TokenType, text: []const u8) !void {
        try self.tokens.append(.{ .type = token_type, .text = text });
    }
};

/// Tokenize Zig code
fn tokenizeZig(allocator: Allocator, code: []const u8) ![]Token {
    var state = LexerState.init(allocator, code);
    defer state.deinit();

    const keywords = [_][]const u8{
        "const",   "var",    "fn",       "pub",         "if",       "else",      "while",       "for",    "switch",
        "return",  "break",  "continue", "defer",       "errdefer", "try",       "catch",       "struct", "enum",
        "union",   "error",  "comptime", "inline",      "export",   "extern",    "test",        "and",    "or",
        "orelse",  "async",  "await",    "suspend",     "resume",   "nosuspend", "threadlocal", "align",  "allowzero",
        "noalias", "packed", "volatile", "linksection", "callconv",
    };

    const builtins = [_][]const u8{
        "true",   "false",  "null",    "undefined",  "void",        "anytype",  "type",
        "bool",   "i8",     "u8",      "i16",        "u16",         "i32",      "u32",
        "i64",    "u64",    "i128",    "u128",       "isize",       "usize",    "f16",
        "f32",    "f64",    "f80",     "f128",       "c_short",     "c_ushort", "c_int",
        "c_uint", "c_long", "c_ulong", "c_longlong", "c_ulonglong", "c_void",
    };

    while (state.pos < state.code.len) {
        const start_pos = state.pos;
        const ch = state.current() orelse break;

        // Comments
        if (ch == '/' and state.peek(1) == '/') {
            const comment_text = state.readUntil('\n');
            try state.addToken(.comment, comment_text);
            if (state.current() == '\n') _ = state.advance();
            continue;
        }

        // Strings
        if (ch == '"' or ch == '\'') {
            _ = state.advance();
            const str = state.readString(ch);
            try state.addToken(.string, str);
            continue;
        }

        // Multiline strings
        if (ch == '\\' and state.peek(1) == '\\') {
            const start = state.pos;
            _ = state.advance();
            _ = state.advance();
            while (state.pos < state.code.len) {
                if (state.current() == '\n') {
                    _ = state.advance();
                    state.skipWhitespace();
                    if (state.current() != '\\' or state.peek(1) != '\\') break;
                    _ = state.advance();
                    _ = state.advance();
                } else {
                    _ = state.advance();
                }
            }
            try state.addToken(.string, state.code[start..state.pos]);
            continue;
        }

        // Numbers
        if (std.ascii.isDigit(ch) or (ch == '.' and state.peek(1) != null and std.ascii.isDigit(state.peek(1).?))) {
            const num = state.readWhile(isNumberChar);
            try state.addToken(.number, num);
            continue;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(ch) or ch == '_' or ch == '@') {
            const ident = state.readWhile(isIdentChar);

            // Check if it's a keyword
            var is_keyword = false;
            for (keywords) |kw| {
                if (std.mem.eql(u8, ident, kw)) {
                    try state.addToken(.keyword, ident);
                    is_keyword = true;
                    break;
                }
            }

            if (!is_keyword) {
                // Check if it's a builtin type
                var is_builtin = false;
                for (builtins) |builtin| {
                    if (std.mem.eql(u8, ident, builtin)) {
                        try state.addToken(.builtin, ident);
                        is_builtin = true;
                        break;
                    }
                }

                if (!is_builtin) {
                    // Check if it's a type (starts with uppercase)
                    if (ident.len > 0 and std.ascii.isUpper(ident[0])) {
                        try state.addToken(.type_name, ident);
                    } else if (ident[0] == '@') {
                        try state.addToken(.builtin, ident);
                    } else {
                        // Check if followed by '(' to identify functions
                        const saved_pos = state.pos;
                        state.skipWhitespace();
                        if (state.current() == '(') {
                            try state.addToken(.function, ident);
                        } else {
                            try state.addToken(.variable, ident);
                        }
                        state.pos = saved_pos;
                    }
                }
            }
            continue;
        }

        // Operators and punctuation
        if (ch == '+' or ch == '-' or ch == '*' or ch == '/' or ch == '%' or
            ch == '=' or ch == '!' or ch == '<' or ch == '>' or ch == '&' or
            ch == '|' or ch == '^' or ch == '~' or ch == '?')
        {
            const op_start = state.pos;
            _ = state.advance();
            // Handle multi-character operators
            if (state.current()) |next| {
                if ((ch == '=' and next == '=') or
                    (ch == '!' and next == '=') or
                    (ch == '<' and (next == '=' or next == '<')) or
                    (ch == '>' and (next == '=' or next == '>')) or
                    (ch == '&' and next == '&') or
                    (ch == '|' and next == '|') or
                    (ch == '+' and (next == '=' or next == '+')) or
                    (ch == '-' and (next == '=' or next == '-' or next == '>')) or
                    (ch == '*' and (next == '=' or next == '*')) or
                    (ch == '/' and next == '=') or
                    (ch == '%' and next == '=') or
                    (ch == '^' and next == '=') or
                    (ch == '&' and next == '=') or
                    (ch == '|' and next == '='))
                {
                    _ = state.advance();
                }
            }
            try state.addToken(.operator, state.code[op_start..state.pos]);
            continue;
        }

        // Brackets
        if (ch == '(' or ch == ')' or ch == '[' or ch == ']' or ch == '{' or ch == '}') {
            _ = state.advance();
            try state.addToken(.bracket, state.code[start_pos..state.pos]);
            continue;
        }

        // Punctuation
        if (ch == '.' or ch == ',' or ch == ';' or ch == ':') {
            _ = state.advance();
            try state.addToken(.punctuation, state.code[start_pos..state.pos]);
            continue;
        }

        // Everything else as text
        _ = state.advance();
        try state.addToken(.text, state.code[start_pos..state.pos]);
    }

    return try state.tokens.toOwnedSlice();
}

fn isNumberChar(ch: u8) bool {
    return std.ascii.isDigit(ch) or ch == '.' or ch == '_' or
        ch == 'x' or ch == 'X' or ch == 'b' or ch == 'B' or
        ch == 'o' or ch == 'O' or ch == 'e' or ch == 'E' or
        (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
}

fn isIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

/// Tokenize JavaScript/TypeScript code
fn tokenizeJavaScript(allocator: Allocator, code: []const u8) ![]Token {
    var state = LexerState.init(allocator, code);
    defer state.deinit();

    const keywords = [_][]const u8{
        "async",    "await",    "break",      "case",      "catch",  "class",      "const",    "continue",
        "debugger", "default",  "delete",     "do",        "else",   "export",     "extends",  "finally",
        "for",      "function", "if",         "import",    "in",     "instanceof", "let",      "new",
        "of",       "return",   "static",     "super",     "switch", "this",       "throw",    "try",
        "typeof",   "var",      "void",       "while",     "with",   "yield",
        // TypeScript
             "abstract", "as",
        "declare",  "enum",     "implements", "interface", "module", "namespace",  "private",  "protected",
        "public",   "readonly", "type",       "from",      "get",    "set",
    };

    const builtins = [_][]const u8{
        "true",    "false",   "null",      "undefined",  "NaN",    "Infinity",
        "console", "window",  "document",  "process",    "global", "module",
        "require", "exports", "__dirname", "__filename",
        // Types
        "string", "number",
        "boolean", "object",  "any",       "unknown",    "never",  "void",
        "symbol",  "bigint",
    };

    while (state.pos < state.code.len) {
        const start_pos = state.pos;
        const ch = state.current() orelse break;

        // Single-line comments
        if (ch == '/' and state.peek(1) == '/') {
            const comment_text = state.readUntil('\n');
            try state.addToken(.comment, comment_text);
            if (state.current() == '\n') _ = state.advance();
            continue;
        }

        // Multi-line comments
        if (ch == '/' and state.peek(1) == '*') {
            const comment_start = state.pos;
            _ = state.advance();
            _ = state.advance();
            while (state.pos < state.code.len - 1) {
                if (state.current() == '*' and state.peek(1) == '/') {
                    _ = state.advance();
                    _ = state.advance();
                    break;
                }
                _ = state.advance();
            }
            try state.addToken(.comment, state.code[comment_start..state.pos]);
            continue;
        }

        // Strings (single, double, template)
        if (ch == '"' or ch == '\'' or ch == '`') {
            _ = state.advance();
            if (ch == '`') {
                // Template literal - handle ${} expressions
                const template_start = state.pos - 1;
                var depth: usize = 0;
                while (state.current()) |c| {
                    if (c == '\\') {
                        _ = state.advance();
                        _ = state.advance();
                        continue;
                    }
                    if (c == '$' and state.peek(1) == '{') {
                        depth += 1;
                        _ = state.advance();
                        _ = state.advance();
                        continue;
                    }
                    if (c == '}' and depth > 0) {
                        depth -= 1;
                        _ = state.advance();
                        continue;
                    }
                    if (c == '`' and depth == 0) {
                        _ = state.advance();
                        break;
                    }
                    _ = state.advance();
                }
                try state.addToken(.string, state.code[template_start..state.pos]);
            } else {
                const str = state.readString(ch);
                try state.addToken(.string, str);
            }
            continue;
        }

        // Numbers
        if (std.ascii.isDigit(ch) or (ch == '.' and state.peek(1) != null and std.ascii.isDigit(state.peek(1).?))) {
            const num = state.readWhile(isJsNumberChar);
            try state.addToken(.number, num);
            continue;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$') {
            const ident = state.readWhile(isJsIdentChar);

            // Check if it's a keyword
            var is_keyword = false;
            for (keywords) |kw| {
                if (std.mem.eql(u8, ident, kw)) {
                    try state.addToken(.keyword, ident);
                    is_keyword = true;
                    break;
                }
            }

            if (!is_keyword) {
                // Check if it's a builtin
                var is_builtin = false;
                for (builtins) |builtin| {
                    if (std.mem.eql(u8, ident, builtin)) {
                        try state.addToken(.builtin, ident);
                        is_builtin = true;
                        break;
                    }
                }

                if (!is_builtin) {
                    // Check if it's a type/class (starts with uppercase)
                    if (ident.len > 0 and std.ascii.isUpper(ident[0])) {
                        try state.addToken(.type_name, ident);
                    } else {
                        // Check if followed by '(' to identify functions
                        const saved_pos = state.pos;
                        state.skipWhitespace();
                        if (state.current() == '(') {
                            try state.addToken(.function, ident);
                        } else {
                            try state.addToken(.variable, ident);
                        }
                        state.pos = saved_pos;
                    }
                }
            }
            continue;
        }

        // Operators
        if (ch == '+' or ch == '-' or ch == '*' or ch == '/' or ch == '%' or
            ch == '=' or ch == '!' or ch == '<' or ch == '>' or ch == '&' or
            ch == '|' or ch == '^' or ch == '~' or ch == '?')
        {
            const op_start = state.pos;
            _ = state.advance();
            // Handle multi-character operators
            if (state.current()) |next| {
                if ((ch == '=' and (next == '=' or next == '>')) or
                    (ch == '!' and next == '=') or
                    (ch == '<' and next == '=') or
                    (ch == '>' and next == '=') or
                    (ch == '&' and next == '&') or
                    (ch == '|' and next == '|') or
                    (ch == '+' and (next == '=' or next == '+')) or
                    (ch == '-' and (next == '=' or next == '-')) or
                    (ch == '*' and (next == '=' or next == '*')) or
                    (ch == '/' and next == '=') or
                    (ch == '%' and next == '=') or
                    (ch == '?' and next == '?'))
                {
                    _ = state.advance();
                    // Handle === and !==
                    if ((ch == '=' or ch == '!') and state.current() == '=') {
                        _ = state.advance();
                    }
                }
            }
            try state.addToken(.operator, state.code[op_start..state.pos]);
            continue;
        }

        // Brackets
        if (ch == '(' or ch == ')' or ch == '[' or ch == ']' or ch == '{' or ch == '}') {
            _ = state.advance();
            try state.addToken(.bracket, state.code[start_pos..state.pos]);
            continue;
        }

        // Punctuation
        if (ch == '.' or ch == ',' or ch == ';' or ch == ':') {
            _ = state.advance();
            // Handle spread operator
            if (ch == '.' and state.current() == '.' and state.peek(1) == '.') {
                _ = state.advance();
                _ = state.advance();
                try state.addToken(.operator, state.code[start_pos..state.pos]);
            } else {
                try state.addToken(.punctuation, state.code[start_pos..state.pos]);
            }
            continue;
        }

        // Everything else as text
        _ = state.advance();
        try state.addToken(.text, state.code[start_pos..state.pos]);
    }

    return try state.tokens.toOwnedSlice();
}

fn isJsNumberChar(ch: u8) bool {
    return std.ascii.isDigit(ch) or ch == '.' or ch == '_' or
        ch == 'e' or ch == 'E' or ch == 'n' or // BigInt suffix
        ch == 'x' or ch == 'X' or ch == 'b' or ch == 'B' or ch == 'o' or ch == 'O' or
        (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
}

fn isJsIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '$';
}

/// Tokenize Python code
fn tokenizePython(allocator: Allocator, code: []const u8) ![]Token {
    var state = LexerState.init(allocator, code);
    defer state.deinit();

    const keywords = [_][]const u8{
        "and",    "as",   "assert", "async",  "await",  "break",   "class",    "continue",
        "def",    "del",  "elif",   "else",   "except", "finally", "for",      "from",
        "global", "if",   "import", "in",     "is",     "lambda",  "nonlocal", "not",
        "or",     "pass", "raise",  "return", "try",    "while",   "with",     "yield",
    };

    const builtins = [_][]const u8{
        "True",     "False",     "None",     "self",       "cls",
        "int",      "float",     "str",      "bool",       "list",
        "dict",     "tuple",     "set",      "print",      "len",
        "range",    "enumerate", "zip",      "map",        "filter",
        "open",     "input",     "type",     "isinstance", "hasattr",
        "getattr",  "__init__",  "__name__", "__main__",   "__file__",
        "__dict__",
    };

    while (state.pos < state.code.len) {
        const start_pos = state.pos;
        const ch = state.current() orelse break;

        // Comments
        if (ch == '#') {
            const comment_text = state.readUntil('\n');
            try state.addToken(.comment, comment_text);
            if (state.current() == '\n') _ = state.advance();
            continue;
        }

        // Triple-quoted strings (docstrings)
        if ((ch == '"' and state.peek(1) == '"' and state.peek(2) == '"') or
            (ch == '\'' and state.peek(1) == '\'' and state.peek(2) == '\''))
        {
            const quote = ch;
            const string_start = state.pos;
            _ = state.advance();
            _ = state.advance();
            _ = state.advance();
            while (state.pos < state.code.len - 2) {
                if (state.current() == quote and state.peek(1) == quote and state.peek(2) == quote) {
                    _ = state.advance();
                    _ = state.advance();
                    _ = state.advance();
                    break;
                }
                _ = state.advance();
            }
            try state.addToken(.string, state.code[string_start..state.pos]);
            continue;
        }

        // Regular strings
        if (ch == '"' or ch == '\'') {
            _ = state.advance();
            const str = state.readString(ch);
            try state.addToken(.string, str);
            continue;
        }

        // f-strings
        if (ch == 'f' and (state.peek(1) == '"' or state.peek(1) == '\'')) {
            const string_start = state.pos;
            _ = state.advance(); // Skip 'f'
            const quote = state.advance().?;
            while (state.current()) |c| {
                if (c == '\\') {
                    _ = state.advance();
                    _ = state.advance();
                    continue;
                }
                if (c == quote) {
                    _ = state.advance();
                    break;
                }
                _ = state.advance();
            }
            try state.addToken(.string, state.code[string_start..state.pos]);
            continue;
        }

        // Decorators
        if (ch == '@' and state.peek(1) != null and std.ascii.isAlphabetic(state.peek(1).?)) {
            const decorator_start = state.pos;
            _ = state.advance();
            _ = state.readWhile(isPythonIdentChar);
            try state.addToken(.decorator, state.code[decorator_start..state.pos]);
            continue;
        }

        // Numbers
        if (std.ascii.isDigit(ch) or (ch == '.' and state.peek(1) != null and std.ascii.isDigit(state.peek(1).?))) {
            const num = state.readWhile(isPythonNumberChar);
            try state.addToken(.number, num);
            continue;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(ch) or ch == '_') {
            const ident = state.readWhile(isPythonIdentChar);

            // Check if it's a keyword
            var is_keyword = false;
            for (keywords) |kw| {
                if (std.mem.eql(u8, ident, kw)) {
                    try state.addToken(.keyword, ident);
                    is_keyword = true;
                    break;
                }
            }

            if (!is_keyword) {
                // Check if it's a builtin
                var is_builtin = false;
                for (builtins) |builtin| {
                    if (std.mem.eql(u8, ident, builtin)) {
                        try state.addToken(.builtin, ident);
                        is_builtin = true;
                        break;
                    }
                }

                if (!is_builtin) {
                    // Check if it's a class/type (starts with uppercase)
                    if (ident.len > 0 and std.ascii.isUpper(ident[0])) {
                        try state.addToken(.type_name, ident);
                    } else {
                        // Check if followed by '(' to identify functions
                        const saved_pos = state.pos;
                        state.skipWhitespace();
                        if (state.current() == '(') {
                            try state.addToken(.function, ident);
                        } else {
                            try state.addToken(.variable, ident);
                        }
                        state.pos = saved_pos;
                    }
                }
            }
            continue;
        }

        // Operators
        if (ch == '+' or ch == '-' or ch == '*' or ch == '/' or ch == '%' or
            ch == '=' or ch == '!' or ch == '<' or ch == '>' or ch == '&' or
            ch == '|' or ch == '^' or ch == '~')
        {
            const op_start = state.pos;
            _ = state.advance();
            // Handle multi-character operators
            if (state.current()) |next| {
                if ((ch == '=' and next == '=') or
                    (ch == '!' and next == '=') or
                    (ch == '<' and (next == '=' or next == '<')) or
                    (ch == '>' and (next == '=' or next == '>')) or
                    (ch == '*' and next == '*') or
                    (ch == '/' and next == '/') or
                    (ch == '+' and next == '=') or
                    (ch == '-' and next == '=') or
                    (ch == '*' and next == '=') or
                    (ch == '/' and next == '=') or
                    (ch == '%' and next == '=') or
                    (ch == '&' and next == '=') or
                    (ch == '|' and next == '=') or
                    (ch == '^' and next == '='))
                {
                    _ = state.advance();
                }
            }
            try state.addToken(.operator, state.code[op_start..state.pos]);
            continue;
        }

        // Brackets
        if (ch == '(' or ch == ')' or ch == '[' or ch == ']' or ch == '{' or ch == '}') {
            _ = state.advance();
            try state.addToken(.bracket, state.code[start_pos..state.pos]);
            continue;
        }

        // Punctuation
        if (ch == '.' or ch == ',' or ch == ':' or ch == ';') {
            _ = state.advance();
            try state.addToken(.punctuation, state.code[start_pos..state.pos]);
            continue;
        }

        // Everything else as text
        _ = state.advance();
        try state.addToken(.text, state.code[start_pos..state.pos]);
    }

    return try state.tokens.toOwnedSlice();
}

fn isPythonIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

fn isPythonNumberChar(ch: u8) bool {
    return std.ascii.isDigit(ch) or ch == '.' or ch == '_' or
        ch == 'e' or ch == 'E' or ch == 'j' or ch == 'J' or // Complex numbers
        ch == 'x' or ch == 'X' or ch == 'b' or ch == 'B' or ch == 'o' or ch == 'O' or
        (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
}

/// Generic tokenizer for unsupported languages
fn tokenizeGeneric(allocator: Allocator, code: []const u8) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    // For now, just return the whole code as text
    // This could be rich with pattern matching
    try tokens.append(.{ .type = .text, .text = code });

    return try tokens.toOwnedSlice();
}

/// Tokenize code based on language
fn tokenize(allocator: Allocator, code: []const u8, language: Language) ![]Token {
    return switch (language) {
        .zig => tokenizeZig(allocator, code),
        .javascript, .typescript => tokenizeJavaScript(allocator, code),
        .python => tokenizePython(allocator, code),
        // TODO: Implement other language tokenizers
        .rust, .go, .json, .yaml, .toml, .markdown, .shell, .bash, .sql, .html, .css, .xml, .unknown => tokenizeGeneric(allocator, code),
    };
}

/// Detect language from code content
pub fn detectLanguage(code: []const u8) ?Language {
    // Check for shebang
    if (std.mem.startsWith(u8, code, "#!/")) {
        const line_end = std.mem.indexOfScalar(u8, code, '\n') orelse code.len;
        const shebang = code[2..line_end];

        if (std.mem.indexOf(u8, shebang, "python") != null) return .python;
        if (std.mem.indexOf(u8, shebang, "node") != null) return .javascript;
        if (std.mem.indexOf(u8, shebang, "bash") != null) return .bash;
        if (std.mem.indexOf(u8, shebang, "sh") != null) return .shell;
    }

    // Check for language-specific patterns
    if (std.mem.indexOf(u8, code, "const std = @import(\"std\");") != null) return .zig;
    if (std.mem.indexOf(u8, code, "pub fn main()") != null) return .zig;

    if (std.mem.indexOf(u8, code, "function ") != null or
        std.mem.indexOf(u8, code, "const ") != null or
        std.mem.indexOf(u8, code, "let ") != null or
        std.mem.indexOf(u8, code, "var ") != null)
    {
        if (std.mem.indexOf(u8, code, "interface ") != null or
            std.mem.indexOf(u8, code, ": string") != null or
            std.mem.indexOf(u8, code, ": number") != null)
        {
            return .typescript;
        }
        return .javascript;
    }

    if (std.mem.indexOf(u8, code, "def ") != null or
        std.mem.indexOf(u8, code, "import ") != null or
        std.mem.indexOf(u8, code, "from ") != null) return .python;

    if (std.mem.indexOf(u8, code, "fn main()") != null or
        std.mem.indexOf(u8, code, "let mut ") != null) return .rust;

    if (std.mem.indexOf(u8, code, "func main()") != null or
        std.mem.indexOf(u8, code, "package ") != null) return .go;

    if (std.mem.startsWith(u8, std.mem.trimLeft(u8, code, " \t\n"), "{") and
        (std.mem.indexOf(u8, code, "\":") != null or std.mem.indexOf(u8, code, "\": ") != null)) return .json;

    if (std.mem.indexOf(u8, code, "<!DOCTYPE") != null or
        std.mem.indexOf(u8, code, "<html") != null) return .html;

    if (std.mem.indexOf(u8, code, "<?xml") != null) return .xml;

    if (std.mem.indexOf(u8, code, "SELECT ") != null or
        std.mem.indexOf(u8, code, "FROM ") != null or
        std.mem.indexOf(u8, code, "INSERT ") != null) return .sql;

    return null;
}

/// Apply highlighting to tokens
fn applyHighlighting(
    allocator: Allocator,
    tokens: []const Token,
    scheme: ColorScheme,
    options: HighlightOptions,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    // Process tokens and apply colors
    for (tokens) |token| {
        const color = scheme.getColor(token.type);

        if (options.quality_tier != .minimal and color.len > 0) {
            try result.appendSlice(color);
        }

        // Handle tabs
        if (options.tab_width > 0) {
            for (token.text) |ch| {
                if (ch == '\t') {
                    var i: usize = 0;
                    while (i < options.tab_width) : (i += 1) {
                        try result.append(' ');
                    }
                } else {
                    try result.append(ch);
                }
            }
        } else {
            try result.appendSlice(token.text);
        }

        if (options.quality_tier != .minimal and color.len > 0) {
            try result.appendSlice("\x1b[0m");
        }
    }

    return try result.toOwnedSlice();
}

/// Main API: Highlight code with syntax colors
pub fn highlightCode(
    allocator: Allocator,
    code: []const u8,
    language: Language,
    options: HighlightOptions,
) ![]u8 {
    // Skip highlighting for minimal quality
    if (options.quality_tier == .minimal) {
        return try allocator.dupe(u8, code);
    }

    // Get color scheme
    const scheme = options.theme orelse getColorScheme(options.quality_tier);

    // Tokenize the code
    const tokens = try tokenize(allocator, code, language);
    defer allocator.free(tokens);

    // Apply line numbers if requested
    if (options.show_line_numbers) {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var line_iter = std.mem.tokenizeScalar(u8, code, '\n');
        var line_num = options.starting_line;

        while (line_iter.next()) |line| {
            // Add line number
            try result.appendSlice(scheme.line_number);
            try result.writer().print("{d:4} ", .{line_num});
            if (scheme.line_number.len > 0) {
                try result.appendSlice("\x1b[0m");
            }

            // Tokenize and highlight this line
            const line_tokens = try tokenize(allocator, line, language);
            defer allocator.free(line_tokens);

            const highlighted = try applyHighlighting(allocator, line_tokens, scheme, options);
            defer allocator.free(highlighted);

            try result.appendSlice(highlighted);
            try result.append('\n');
            line_num += 1;
        }

        return try result.toOwnedSlice();
    }

    // Apply highlighting to all tokens
    return try applyHighlighting(allocator, tokens, scheme, options);
}

// Tests
test "detect language from shebang" {
    const allocator = std.testing.allocator;
    _ = allocator;

    try std.testing.expect(detectLanguage("#!/usr/bin/env python\n") == .python);
    try std.testing.expect(detectLanguage("#!/usr/bin/node\n") == .javascript);
    try std.testing.expect(detectLanguage("#!/bin/bash\n") == .bash);
}

test "detect language from content" {
    const allocator = std.testing.allocator;
    _ = allocator;

    try std.testing.expect(detectLanguage("const std = @import(\"std\");") == .zig);
    try std.testing.expect(detectLanguage("function hello() { }") == .javascript);
    try std.testing.expect(detectLanguage("def hello():") == .python);
    try std.testing.expect(detectLanguage("fn main() {") == .rust);
}

test "tokenize Zig code" {
    const allocator = std.testing.allocator;
    const code = "const x = 42; // comment";
    const tokens = try tokenize(allocator, code, .zig);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len > 0);
    try std.testing.expect(tokens[0].type == .keyword);
    try std.testing.expect(std.mem.eql(u8, tokens[0].text, "const"));
}

test "highlight code with line numbers" {
    const allocator = std.testing.allocator;
    const code = "const x = 42;\nvar y = true;";
    const result = try highlightCode(allocator, code, .zig, .{
        .quality_tier = .standard,
        .show_line_numbers = true,
    });
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "   1 ") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "   2 ") != null);
}
