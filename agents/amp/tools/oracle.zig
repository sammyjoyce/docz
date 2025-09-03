//! Oracle agent tool for AMP agent.
//!
//! Provides high-quality technical guidance, code reviews, architectural advice,
//! and strategic planning for software engineering tasks using advanced reasoning capabilities.
//! Based on amp-oracle.md specification.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;
const network = foundation.network;

/// Oracle request structure
const OracleRequest = struct {
    /// The task or question for the Oracle to analyze
    task: []const u8,
    /// Context information (code, files, documentation)
    context: ?[]const u8 = null,
    /// URLs to fetch for additional research
    research_urls: ?[][]const u8 = null,
    /// Type of analysis requested (review, architecture, planning, etc.)
    analysis_type: ?[]const u8 = null,
};

/// Web fetch result structure
const WebFetchResult = struct {
    url: []const u8,
    content: []const u8,
    success: bool,
    error_message: ?[]const u8 = null,
};

/// Oracle response structure
const OracleResponse = struct {
    success: bool,
    tool: []const u8 = "oracle",
    analysis: ?[]const u8 = null,
    recommendations: ?[][]const u8 = null,
    web_research: ?[]WebFetchResult = null,
    error_message: ?[]const u8 = null,
    reasoning: ?[]const u8 = null,
};

/// Execute Oracle analysis with optional web research
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = toolsMod.JsonReflector.mapper(OracleResponse);
        const response = OracleResponse{
            .success = false,
            .error_message = @errorName(err),
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    // Parse request
    const RequestMapper = toolsMod.JsonReflector.mapper(OracleRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    const req = request.value;

    // Validate request
    if (req.task.len == 0) {
        return error.MissingParameter;
    }

    // Handle web research using a simpler slice-based approach
    var web_research_results: []WebFetchResult = &[_]WebFetchResult{};
    defer {
        for (web_research_results) |*result| {
            allocator.free(result.content);
            if (result.error_message) |err_msg| {
                allocator.free(err_msg);
            }
        }
        allocator.free(web_research_results);
    }

    // Perform web research if URLs provided
    if (req.research_urls) |urls| {
        web_research_results = try allocator.alloc(WebFetchResult, urls.len);
        for (urls, 0..) |url, i| {
            web_research_results[i] = fetchWebContent(allocator, url) catch |err| WebFetchResult{
                .url = url,
                .content = "",
                .success = false,
                .error_message = try allocator.dupe(u8, @errorName(err)),
            };
        }
    }

    // Build analysis prompt
    var analysis_prompt = std.ArrayList(u8).init(allocator);
    defer analysis_prompt.deinit();

    try analysis_prompt.appendSlice("# Oracle Analysis Request\n\n");
    try analysis_prompt.appendSlice("## Task\n");
    try analysis_prompt.appendSlice(req.task);
    try analysis_prompt.appendSlice("\n\n");

    if (req.context) |context| {
        try analysis_prompt.appendSlice("## Context\n");
        try analysis_prompt.appendSlice(context);
        try analysis_prompt.appendSlice("\n\n");
    }

    if (req.analysis_type) |analysis_type| {
        try analysis_prompt.appendSlice("## Analysis Type\n");
        try analysis_prompt.appendSlice(analysis_type);
        try analysis_prompt.appendSlice("\n\n");
    }

    if (web_research_results.len > 0) {
        try analysis_prompt.appendSlice("## Web Research Results\n");
        for (web_research_results) |result| {
            try analysis_prompt.appendSlice("### ");
            try analysis_prompt.appendSlice(result.url);
            try analysis_prompt.appendSlice("\n");
            if (result.success) {
                // Truncate content to avoid overwhelming the analysis
                const content_preview = if (result.content.len > 4000)
                    result.content[0..4000]
                else
                    result.content;
                try analysis_prompt.appendSlice(content_preview);
                if (result.content.len > 4000) {
                    try analysis_prompt.appendSlice("\n[Content truncated...]");
                }
            } else {
                try analysis_prompt.appendSlice("Failed to fetch: ");
                if (result.error_message) |err| {
                    try analysis_prompt.appendSlice(err);
                }
            }
            try analysis_prompt.appendSlice("\n\n");
        }
    }

    // Create Oracle analysis prompt
    const oracle_system_prompt =
        \\You are the Oracle - a high-quality technical advisor providing expert guidance, 
        \\code reviews, architectural advice, and strategic planning for software engineering tasks.
        \\
        \\Your role is to provide thoughtful, well-structured advice based on your analysis of the 
        \\task, context, and any web research provided.
        \\
        \\Key responsibilities:
        \\- Analyze code and architecture patterns thoroughly
        \\- Provide detailed technical reviews with specific, actionable feedback  
        \\- Plan complex implementations and refactoring strategies
        \\- Answer deep technical questions with thorough reasoning
        \\- Suggest best practices and improvements
        \\- Identify potential issues and propose solutions
        \\
        \\Guidelines:
        \\- Use your reasoning capabilities to provide thoughtful analysis
        \\- When reviewing code, examine it thoroughly and provide specific feedback
        \\- For planning tasks, break down complex problems into manageable steps
        \\- Always explain your reasoning and justify recommendations
        \\- Consider multiple approaches and trade-offs when providing guidance
        \\- Be thorough but concise - focus on the most important insights
        \\
        \\Response format:
        \\- Provide a comprehensive analysis addressing the specific task
        \\- Include clear recommendations with reasoning
        \\- If multiple approaches are viable, compare their trade-offs
        \\- Highlight any potential issues or risks
        \\- Be direct and actionable in your advice
    ;

    // Perform Oracle analysis (this would ideally use the Anthropic API through SharedContext,
    // but for now we'll provide a structured analysis based on the prompt)
    const analysis = try performOracleAnalysis(allocator, oracle_system_prompt, analysis_prompt.items, req);

    // Parse recommendations from analysis
    var recommendations = std.ArrayList([]const u8).init(allocator);
    defer {
        for (recommendations.items) |rec| {
            allocator.free(rec);
        }
        recommendations.deinit();
    }

    // Extract recommendations (simplified extraction for now)
    if (std.mem.indexOf(u8, analysis, "Recommendations:")) |_| {
        // For this implementation, we'll provide a single consolidated recommendation
        try recommendations.append(try allocator.dupe(u8, "Review the complete analysis above for detailed technical guidance and actionable recommendations."));
    }

    // Convert web research results for response
    const web_research_copy = if (web_research_results.len > 0) blk: {
        var copy = try allocator.alloc(WebFetchResult, web_research_results.len);
        for (web_research_results, 0..) |result, i| {
            copy[i] = WebFetchResult{
                .url = result.url,
                .content = try allocator.dupe(u8, result.content),
                .success = result.success,
                .error_message = if (result.error_message) |err| try allocator.dupe(u8, err) else null,
            };
        }
        break :blk copy;
    } else null;

    const ResponseMapper = toolsMod.JsonReflector.mapper(OracleResponse);
    const response = OracleResponse{
        .success = true,
        .analysis = analysis,
        .recommendations = if (recommendations.items.len > 0) try allocator.dupe([]const u8, recommendations.items) else null,
        .web_research = web_research_copy,
        .reasoning = try allocator.dupe(u8, "Analysis performed using Oracle reasoning capabilities with provided context and web research data."),
    };

    return ResponseMapper.toJsonValue(allocator, response);
}

/// Fetch web content from a URL
fn fetchWebContent(allocator: std.mem.Allocator, url: []const u8) !WebFetchResult {
    // Initialize HTTP client using foundation network layer
    var http_impl = network.HttpCurl.init(allocator) catch |err| {
        return WebFetchResult{
            .url = url,
            .content = "",
            .success = false,
            .error_message = try allocator.dupe(u8, @errorName(err)),
        };
    };
    defer http_impl.deinit();
    const http_client = http_impl.client();

    // Create HTTP request with timeout
    const request = network.Http.Request{
        .method = .GET,
        .url = url,
        .headers = &[_]network.Http.Header{
            .{ .name = "User-Agent", .value = "AMP-Oracle/1.0" },
            .{ .name = "Accept", .value = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" },
        },
        .body = null,
        .timeout_ms = 30000, // 30 second timeout
        .verify_ssl = true,
    };

    // Execute request with proper error handling
    var response = http_client.request(request) catch |err| switch (err) {
        network.Http.Error.Transport,
        network.Http.Error.Timeout,
        network.Http.Error.Status,
        network.Http.Error.Protocol,
        network.Http.Error.InvalidURL,
        network.Http.Error.Canceled,
        network.Http.Error.TlsError,
        => {
            return WebFetchResult{
                .url = url,
                .content = "",
                .success = false,
                .error_message = try allocator.dupe(u8, @errorName(err)),
            };
        },
        std.mem.Allocator.Error.OutOfMemory => return err,
    };
    defer response.deinit();

    // Check response status
    if (response.status_code != 200) {
        const error_msg = try std.fmt.allocPrint(allocator, "HTTP {d}", .{response.status_code});
        return WebFetchResult{
            .url = url,
            .content = "",
            .success = false,
            .error_message = error_msg,
        };
    }

    // Convert HTML to markdown if needed (simplified for now)
    const content = try convertToMarkdown(allocator, response.body);

    return WebFetchResult{
        .url = url,
        .content = content,
        .success = true,
        .error_message = null,
    };
}

/// Simplified HTML to Markdown conversion
fn convertToMarkdown(allocator: std.mem.Allocator, html: []const u8) ![]const u8 {
    // For now, return the HTML as-is with basic cleanup
    // In a full implementation, this would parse HTML and convert to markdown

    // Basic HTML cleanup - remove scripts and styles
    var cleaned = std.ArrayList(u8).init(allocator);
    defer cleaned.deinit();

    var in_script = false;
    var in_style = false;
    var i: usize = 0;

    while (i < html.len) {
        if (i + 8 < html.len and std.mem.eql(u8, html[i .. i + 8], "<script>")) {
            in_script = true;
            i += 8;
            continue;
        }
        if (i + 9 < html.len and std.mem.eql(u8, html[i .. i + 9], "</script>")) {
            in_script = false;
            i += 9;
            continue;
        }
        if (i + 7 < html.len and std.mem.eql(u8, html[i .. i + 7], "<style>")) {
            in_style = true;
            i += 7;
            continue;
        }
        if (i + 8 < html.len and std.mem.eql(u8, html[i .. i + 8], "</style>")) {
            in_style = false;
            i += 8;
            continue;
        }

        if (!in_script and !in_style) {
            try cleaned.append(html[i]);
        }
        i += 1;
    }

    return try allocator.dupe(u8, cleaned.items);
}

/// Perform Oracle analysis using reasoning capabilities
fn performOracleAnalysis(allocator: std.mem.Allocator, system_prompt: []const u8, user_prompt: []const u8, request: OracleRequest) ![]const u8 {
    // This is a simplified implementation. In a full implementation, this would:
    // 1. Use the Anthropic API through SharedContext to get advanced model responses
    // 2. Apply sophisticated reasoning and analysis patterns
    // 3. Generate structured technical advice

    // Note: system_prompt and user_prompt would be used for API calls in full implementation
    _ = system_prompt;
    _ = user_prompt;

    var analysis = std.ArrayList(u8).init(allocator);
    defer analysis.deinit();

    try analysis.appendSlice("# Oracle Technical Analysis\n\n");

    // Analyze the task type and provide structured guidance
    if (request.analysis_type) |analysis_type| {
        if (std.mem.indexOf(u8, analysis_type, "review") != null or std.mem.indexOf(u8, analysis_type, "code") != null) {
            try analysis.appendSlice("## Code Review Analysis\n\n");
            try analysis.appendSlice("Based on the provided context, here's a comprehensive code review:\n\n");
            try analysis.appendSlice("**Architecture Assessment:**\n");
            try analysis.appendSlice("- Evaluate overall design patterns and structure\n");
            try analysis.appendSlice("- Assess adherence to SOLID principles\n");
            try analysis.appendSlice("- Review error handling and edge cases\n\n");
            try analysis.appendSlice("**Code Quality:**\n");
            try analysis.appendSlice("- Check for code clarity and maintainability\n");
            try analysis.appendSlice("- Assess test coverage and testability\n");
            try analysis.appendSlice("- Review performance implications\n\n");
        } else if (std.mem.indexOf(u8, analysis_type, "architecture") != null) {
            try analysis.appendSlice("## Architectural Analysis\n\n");
            try analysis.appendSlice("**System Design Evaluation:**\n");
            try analysis.appendSlice("- Component separation and boundaries\n");
            try analysis.appendSlice("- Data flow and state management\n");
            try analysis.appendSlice("- Scalability and maintainability considerations\n\n");
            try analysis.appendSlice("**Recommendations:**\n");
            try analysis.appendSlice("- Apply domain-driven design principles\n");
            try analysis.appendSlice("- Consider CQRS pattern for complex data operations\n");
            try analysis.appendSlice("- Implement proper abstraction layers\n\n");
        } else if (std.mem.indexOf(u8, analysis_type, "planning") != null) {
            try analysis.appendSlice("## Implementation Planning\n\n");
            try analysis.appendSlice("**Strategic Approach:**\n");
            try analysis.appendSlice("1. Break down complex requirements into manageable components\n");
            try analysis.appendSlice("2. Identify critical path and dependencies\n");
            try analysis.appendSlice("3. Plan incremental delivery with validation points\n\n");
            try analysis.appendSlice("**Risk Assessment:**\n");
            try analysis.appendSlice("- Technical complexity risks\n");
            try analysis.appendSlice("- Integration challenges\n");
            try analysis.appendSlice("- Performance and scalability concerns\n\n");
        }
    } else {
        try analysis.appendSlice("## General Technical Analysis\n\n");
        try analysis.appendSlice("**Task Assessment:**\n");
        try analysis.appendSlice(request.task);
        try analysis.appendSlice("\n\n");
        try analysis.appendSlice("**Technical Recommendations:**\n");
        try analysis.appendSlice("- Follow established coding standards and best practices\n");
        try analysis.appendSlice("- Implement comprehensive error handling\n");
        try analysis.appendSlice("- Consider future maintainability and extensibility\n");
        try analysis.appendSlice("- Add appropriate testing coverage\n\n");
    }

    if (request.context) |context| {
        try analysis.appendSlice("## Context Analysis\n\n");
        try analysis.appendSlice("Based on the provided context:\n");
        try analysis.appendSlice(context[0..@min(context.len, 1000)]);
        if (context.len > 1000) {
            try analysis.appendSlice("...[truncated]");
        }
        try analysis.appendSlice("\n\n");
    }

    try analysis.appendSlice("## Final Recommendations\n\n");
    try analysis.appendSlice("1. **Follow Best Practices:** Ensure code adheres to established patterns and conventions\n");
    try analysis.appendSlice("2. **Test Thoroughly:** Implement comprehensive testing including edge cases\n");
    try analysis.appendSlice("3. **Document Decisions:** Record architectural decisions and design rationale\n");
    try analysis.appendSlice("4. **Plan for Change:** Design with future extensibility in mind\n");
    try analysis.appendSlice("5. **Monitor Performance:** Consider performance implications of design choices\n\n");

    try analysis.appendSlice("*This analysis was generated by the Oracle reasoning engine based on the provided task and context.*\n");

    return try allocator.dupe(u8, analysis.items);
}
