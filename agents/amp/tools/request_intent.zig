const std = @import("std");
const core = @import("core");
const tools = @import("foundation").tools;

const RequestIntentInput = struct {
    user_request: []const u8,
    context: ?[]const u8 = null,
};

const RequestIntentResult = struct {
    success: bool = true,
    tool: []const u8 = "request_intent_analysis",
    primary_intent: []const u8,
    secondary_intents: ?[][]const u8 = null,
    key_entities: [][]const u8,
    suggested_tools: [][]const u8,
    suggested_approach: []const u8,
    clarification_questions: ?[][]const u8 = null,
    confidence_score: f32,
};

const IntentClassifier = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn analyze(self: Self, request: []const u8, context: ?[]const u8) !RequestIntentResult {
        _ = context; // Context unused for now, reserved for future enhancement

        // Normalize request for analysis
        const lower_request = try std.ascii.allocLowerString(self.allocator, request);
        defer self.allocator.free(lower_request);

        // Classify primary intent
        const primary_intent = try self.classifyPrimaryIntent(lower_request);

        // Extract key entities
        const key_entities = try self.extractKeyEntities(lower_request);

        // Suggest appropriate tools
        const suggested_tools = try self.suggestTools(primary_intent, lower_request);

        // Generate approach suggestion
        const suggested_approach = try self.generateApproach(primary_intent, lower_request);

        // Calculate confidence based on keyword matches
        const confidence = self.calculateConfidence(lower_request, primary_intent);

        return RequestIntentResult{
            .primary_intent = primary_intent,
            .key_entities = key_entities,
            .suggested_tools = suggested_tools,
            .suggested_approach = suggested_approach,
            .confidence_score = confidence,
        };
    }

    fn classifyPrimaryIntent(self: Self, request: []const u8) ![]const u8 {
        // Coding request patterns
        if (self.containsAny(request, &.{ "write", "code", "implement", "create function", "refactor", "debug", "fix bug", "add feature" })) {
            return try self.allocator.dupe(u8, "coding");
        }

        // Code review/analysis patterns
        if (self.containsAny(request, &.{ "review", "analyze code", "check", "lint", "quality", "best practices" })) {
            return try self.allocator.dupe(u8, "code_review");
        }

        // File operations
        if (self.containsAny(request, &.{ "read file", "find file", "search in", "list files", "show contents" })) {
            return try self.allocator.dupe(u8, "file_operations");
        }

        // System operations
        if (self.containsAny(request, &.{ "run command", "execute", "build", "test", "deploy", "install" })) {
            return try self.allocator.dupe(u8, "system_operations");
        }

        // Research/web search
        if (self.containsAny(request, &.{ "research", "look up", "find information", "search web", "documentation" })) {
            return try self.allocator.dupe(u8, "research");
        }

        // Questions about code
        if (self.containsAny(request, &.{ "what does", "how does", "explain", "why", "what is", "how to" })) {
            return try self.allocator.dupe(u8, "explanation");
        }

        // Planning/architecture
        if (self.containsAny(request, &.{ "design", "architecture", "plan", "approach", "structure", "organize" })) {
            return try self.allocator.dupe(u8, "planning");
        }

        // Default to general query
        return try self.allocator.dupe(u8, "general_query");
    }

    fn extractKeyEntities(self: Self, request: []const u8) ![][]const u8 {
        var entities: std.ArrayList([]const u8) = .{};
        defer entities.deinit(self.allocator);

        // File extensions
        const extensions = [_][]const u8{ ".zig", ".js", ".ts", ".py", ".rs", ".go", ".c", ".cpp", ".java", ".md", ".json", ".yml", ".yaml", ".toml" };
        for (extensions) |ext| {
            if (std.mem.indexOf(u8, request, ext) != null) {
                try entities.append(self.allocator, try self.allocator.dupe(u8, ext));
            }
        }

        // Technologies/frameworks
        const technologies = [_][]const u8{ "zig", "javascript", "typescript", "python", "rust", "go", "react", "node", "npm", "git", "docker", "kubernetes" };
        for (technologies) |tech| {
            if (std.mem.indexOf(u8, request, tech) != null) {
                try entities.append(self.allocator, try self.allocator.dupe(u8, tech));
            }
        }

        // Common file patterns
        const patterns = [_][]const u8{ "config", "test", "spec", "src/", "lib/", "build", "package.json", "makefile", "dockerfile" };
        for (patterns) |pattern| {
            if (std.mem.indexOf(u8, request, pattern) != null) {
                try entities.append(self.allocator, try self.allocator.dupe(u8, pattern));
            }
        }

        return entities.toOwnedSlice(self.allocator);
    }

    fn suggestTools(self: Self, intent: []const u8, request: []const u8) ![][]const u8 {
        var tools_list: std.ArrayList([]const u8) = .{};
        defer tools_list.deinit(self.allocator);

        if (std.mem.eql(u8, intent, "coding")) {
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "code_search"));
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "test_writer"));
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "code_formatter"));
        } else if (std.mem.eql(u8, intent, "code_review")) {
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "git_review"));
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "code_search"));
        } else if (std.mem.eql(u8, intent, "file_operations")) {
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "glob"));
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "code_search"));
        } else if (std.mem.eql(u8, intent, "system_operations")) {
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "command_risk"));
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "task"));
        } else if (std.mem.eql(u8, intent, "research")) {
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "oracle"));
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "code_search"));
        } else if (std.mem.eql(u8, intent, "planning")) {
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "diagram"));
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "task"));
        }

        // Always suggest JavaScript execution for complex analysis
        if (self.containsAny(request, &.{ "calculate", "process", "transform", "parse" })) {
            try tools_list.append(self.allocator, try self.allocator.dupe(u8, "javascript"));
        }

        return tools_list.toOwnedSlice(self.allocator);
    }

    fn generateApproach(self: Self, intent: []const u8, request: []const u8) ![]const u8 {
        if (std.mem.eql(u8, intent, "coding")) {
            if (self.containsAny(request, &.{ "test", "spec" })) {
                return try self.allocator.dupe(u8, "First search for existing patterns, then implement with comprehensive tests");
            }
            return try self.allocator.dupe(u8, "Search codebase for patterns, implement following existing conventions");
        } else if (std.mem.eql(u8, intent, "code_review")) {
            return try self.allocator.dupe(u8, "Analyze code quality, security, and best practices systematically");
        } else if (std.mem.eql(u8, intent, "file_operations")) {
            return try self.allocator.dupe(u8, "Use glob patterns to locate files, then read/analyze as needed");
        } else if (std.mem.eql(u8, intent, "system_operations")) {
            return try self.allocator.dupe(u8, "Assess command safety first, then execute with proper error handling");
        } else if (std.mem.eql(u8, intent, "research")) {
            return try self.allocator.dupe(u8, "Search internal codebase first, then consult external sources if needed");
        } else if (std.mem.eql(u8, intent, "explanation")) {
            return try self.allocator.dupe(u8, "Locate relevant code/documentation, then provide clear explanation with examples");
        } else if (std.mem.eql(u8, intent, "planning")) {
            return try self.allocator.dupe(u8, "Break down into phases, create visual diagrams, delegate complex subtasks");
        }

        return try self.allocator.dupe(u8, "Analyze request context and select appropriate tools for systematic handling");
    }

    fn calculateConfidence(self: Self, request: []const u8, intent: []const u8) f32 {
        _ = self;
        var confidence: f32 = 0.5; // Base confidence

        // High confidence patterns
        const high_confidence_patterns = [_][]const u8{ "write code", "implement", "create function", "fix bug", "review code", "analyze", "check quality", "run command", "execute", "build project", "search for", "find file", "list files" };

        for (high_confidence_patterns) |pattern| {
            if (std.mem.indexOf(u8, request, pattern) != null) {
                confidence += 0.3;
                break;
            }
        }

        // Boost confidence for specific intent matches
        if (std.mem.eql(u8, intent, "coding") and std.mem.indexOf(u8, request, "function") != null) {
            confidence += 0.2;
        }

        if (std.mem.eql(u8, intent, "file_operations") and std.mem.indexOf(u8, request, "file") != null) {
            confidence += 0.2;
        }

        // Clamp to valid range
        return @min(1.0, @max(0.1, confidence));
    }

    fn containsAny(self: Self, haystack: []const u8, needles: []const []const u8) bool {
        _ = self;
        for (needles) |needle| {
            if (std.mem.indexOf(u8, haystack, needle) != null) {
                return true;
            }
        }
        return false;
    }
};

pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) tools.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = tools.JsonReflector.mapper(RequestIntentResult);
        const response = RequestIntentResult{
            .success = false,
            .primary_intent = @errorName(err),
            .key_entities = &.{},
            .suggested_tools = &.{},
            .suggested_approach = "Error occurred during analysis",
            .confidence_score = 0.0,
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    // Parse input
    const RequestMapper = tools.JsonReflector.mapper(RequestIntentInput);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    const input = request.value;

    // Create classifier and analyze
    const classifier = IntentClassifier.init(allocator);
    const result = try classifier.analyze(input.user_request, input.context);

    // Serialize result
    const ResponseMapper = tools.JsonReflector.mapper(RequestIntentResult);
    return try ResponseMapper.toJsonValue(allocator, result);
}
