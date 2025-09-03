//! Product Summary tool for AMP agent.
//!
//! Generates structured product summaries with 10 key sections based on
//! amp-product-summary.md specification. Provides comprehensive product analysis
//! template system.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Product summary request structure
const ProductSummaryRequest = struct {
    /// Product name or description to analyze
    product_name: []const u8,
    /// Product information, documentation, or context
    product_info: []const u8,
    /// Optional additional context or specific focus areas
    context: ?[]const u8 = null,
    /// Include template sections even if information is missing
    include_all_sections: bool = true,
};

/// Product summary response structure
const ProductSummaryResponse = struct {
    success: bool,
    tool: []const u8 = "product_summary",
    summary: ?[]const u8 = null,
    sections_included: ?[]const []const u8 = null,
    missing_info: ?[]const []const u8 = null,
    error_message: ?[]const u8 = null,
};

/// Product summary section structure
const SummarySection = struct {
    title: []const u8,
    content: []const u8,
    has_info: bool,
};

/// Execute product summary generation
pub fn execute(allocator: std.mem.Allocator, params: std.json.Value) toolsMod.ToolError!std.json.Value {
    return executeInternal(allocator, params) catch |err| {
        const ResponseMapper = toolsMod.JsonReflector.mapper(ProductSummaryResponse);
        const response = ProductSummaryResponse{
            .success = false,
            .error_message = @errorName(err),
        };
        return ResponseMapper.toJsonValue(allocator, response);
    };
}

fn executeInternal(allocator: std.mem.Allocator, params: std.json.Value) !std.json.Value {
    // Parse request
    const RequestMapper = toolsMod.JsonReflector.mapper(ProductSummaryRequest);
    const request = try RequestMapper.fromJson(allocator, params);
    defer request.deinit();

    const req = request.value;

    // Validate required fields
    if (req.product_name.len == 0) {
        return toolsMod.ToolError.InvalidInput;
    }
    if (req.product_info.len == 0) {
        return toolsMod.ToolError.InvalidInput;
    }

    // Generate structured product summary
    const summary = try generateProductSummary(allocator, req);
    defer allocator.free(summary.content);

    // Prepare response
    var sections_list: std.ArrayList([]const u8) = .{};
    defer sections_list.deinit(allocator);
    var missing_list: std.ArrayList([]const u8) = .{};
    defer missing_list.deinit(allocator);

    // Track which sections have information and which are missing
    const section_names = [_][]const u8{
        "Product Name",
        "Primary Purpose",
        "Key Features",
        "Target Audience",
        "Main Benefits",
        "Technology Stack",
        "Integration Capabilities",
        "Pricing Model",
        "Unique Selling Points",
        "Current Status",
    };

    // Basic analysis - mark sections as included or missing based on content analysis
    for (section_names) |section_name| {
        const section_lower = try allocator.alloc(u8, section_name.len);
        defer allocator.free(section_lower);
        for (section_name, 0..) |c, i| {
            section_lower[i] = std.ascii.toLower(c);
        }

        // Simple heuristic: check if section keywords appear in product info
        const has_info = containsKeywords(req.product_info, section_lower);

        if (has_info) {
            const owned_name = try allocator.dupe(u8, section_name);
            try sections_list.append(allocator, owned_name);
        } else if (req.include_all_sections) {
            const owned_name = try allocator.dupe(u8, section_name);
            try missing_list.append(allocator, owned_name);
        }
    }

    const ResponseMapper = toolsMod.JsonReflector.mapper(ProductSummaryResponse);
    const response = ProductSummaryResponse{
        .success = true,
        .summary = try allocator.dupe(u8, summary.content),
        .sections_included = if (sections_list.items.len > 0) try sections_list.toOwnedSlice(allocator) else null,
        .missing_info = if (missing_list.items.len > 0) try missing_list.toOwnedSlice(allocator) else null,
    };

    return ResponseMapper.toJsonValue(allocator, response);
}

const SummaryResult = struct {
    content: []const u8,
};

/// Generate structured product summary based on the 10-section template
fn generateProductSummary(allocator: std.mem.Allocator, req: ProductSummaryRequest) !SummaryResult {
    // Build content using string concatenation approach
    var content_parts: std.ArrayList([]const u8) = .{};
    defer {
        for (content_parts.items) |part| {
            allocator.free(part);
        }
        content_parts.deinit(allocator);
    }

    // Header
    const header = try std.fmt.allocPrint(allocator, "# Product Summary: {s}\n\n", .{req.product_name});
    try content_parts.append(allocator, header);

    if (req.context) |context| {
        const context_section = try std.fmt.allocPrint(allocator, "**Analysis Context:** {s}\n\n", .{context});
        try content_parts.append(allocator, context_section);
    }

    // Generate all 10 sections as defined in amp-product-summary.md
    const sections = [_]struct {
        title: []const u8,
        description: []const u8,
        keywords: []const []const u8,
    }{
        .{
            .title = "Product Name",
            .description = "The official name of the product",
            .keywords = &[_][]const u8{ "name", "title", "called" },
        },
        .{
            .title = "Primary Purpose",
            .description = "What is the main problem this product solves?",
            .keywords = &[_][]const u8{ "problem", "solves", "purpose", "goal", "objective" },
        },
        .{
            .title = "Key Features",
            .description = "List the most important features that distinguish this product from competitors",
            .keywords = &[_][]const u8{ "features", "capabilities", "functionality", "tools", "options" },
        },
        .{
            .title = "Target Audience",
            .description = "Who is this product designed for?",
            .keywords = &[_][]const u8{ "audience", "users", "customers", "developers", "teams", "for" },
        },
        .{
            .title = "Main Benefits",
            .description = "What are the primary value propositions for users?",
            .keywords = &[_][]const u8{ "benefits", "value", "advantages", "helps", "improves" },
        },
        .{
            .title = "Technology Stack",
            .description = "What technologies or platforms does this product use?",
            .keywords = &[_][]const u8{ "technology", "tech", "platform", "built", "uses", "stack", "framework" },
        },
        .{
            .title = "Integration Capabilities",
            .description = "What other tools or services can this product work with?",
            .keywords = &[_][]const u8{ "integration", "api", "connects", "works with", "compatible" },
        },
        .{
            .title = "Pricing Model",
            .description = "How is the product priced (if applicable)?",
            .keywords = &[_][]const u8{ "pricing", "cost", "price", "free", "paid", "subscription", "license" },
        },
        .{
            .title = "Unique Selling Points",
            .description = "What makes this product stand out in the market?",
            .keywords = &[_][]const u8{ "unique", "different", "stands out", "special", "distinctive" },
        },
        .{
            .title = "Current Status",
            .description = "Is this product in development, beta, or generally available?",
            .keywords = &[_][]const u8{ "status", "development", "beta", "available", "release", "version" },
        },
    };

    for (sections) |section| {
        const section_header = try std.fmt.allocPrint(allocator, "## {s}\n\n", .{section.title});
        try content_parts.append(allocator, section_header);

        // Extract relevant information for this section
        const section_info = extractSectionInfo(req.product_info, section.keywords);

        if (section_info.len > 0) {
            const section_content = try std.fmt.allocPrint(allocator, "{s}\n\n", .{section_info});
            try content_parts.append(allocator, section_content);
        } else if (req.include_all_sections) {
            const missing_info = try std.fmt.allocPrint(allocator, "*Information about {s} not available in provided context.*\n\n", .{section.description});
            try content_parts.append(allocator, missing_info);
        }
    }

    // Additional analysis notes
    const footer = try allocator.dupe(u8, "---\n\n**Note:** This summary was generated based on the provided product information. Sections marked with 'not available' indicate where additional information would be needed for a complete product analysis.\n");
    try content_parts.append(allocator, footer);

    // Calculate total length and concatenate all parts
    var total_len: usize = 0;
    for (content_parts.items) |part| {
        total_len += part.len;
    }

    const final_content = try allocator.alloc(u8, total_len);
    var pos: usize = 0;
    for (content_parts.items) |part| {
        @memcpy(final_content[pos .. pos + part.len], part);
        pos += part.len;
    }

    return SummaryResult{ .content = final_content };
}

/// Extract information relevant to a specific section based on keywords
fn extractSectionInfo(product_info: []const u8, keywords: []const []const u8) []const u8 {
    // Simple implementation: look for sentences containing section keywords
    // In a more sophisticated implementation, this would use NLP or semantic analysis

    for (keywords) |keyword| {
        if (std.mem.indexOf(u8, product_info, keyword) != null) {
            // Found relevant keyword - for now, return the first relevant sentence
            // This is a simplified implementation
            const context_start = std.mem.indexOf(u8, product_info, keyword) orelse 0;
            const context_end = if (context_start + 200 < product_info.len) context_start + 200 else product_info.len;

            // Find sentence boundaries
            var start = context_start;
            while (start > 0 and product_info[start] != '.' and product_info[start] != '\n') {
                start -= 1;
            }
            if (start > 0) start += 1; // Skip the delimiter

            var end = context_end;
            while (end < product_info.len and product_info[end] != '.' and product_info[end] != '\n') {
                end += 1;
            }

            // Skip whitespace at start
            while (start < end and std.ascii.isWhitespace(product_info[start])) {
                start += 1;
            }

            if (end > start) {
                return product_info[start..end];
            }
        }
    }

    return "";
}

/// Check if the text contains keywords relevant to a section
fn containsKeywords(text: []const u8, section_lower: []const u8) bool {
    // Convert to lowercase for comparison
    var text_lower: std.ArrayList(u8) = .{};
    defer text_lower.deinit(std.heap.page_allocator);

    text_lower.resize(std.heap.page_allocator, text.len) catch return false;
    for (text, 0..) |c, i| {
        text_lower.items[i] = std.ascii.toLower(c);
    }

    return std.mem.indexOf(u8, text_lower.items, section_lower) != null;
}
