//! AMP agent tools module.
//!
//! This provides AMP-specific tools based on the specifications in specs/amp/prompts/
//! and follows the foundation framework patterns for tool registration.

const std = @import("std");
const foundation = @import("foundation");
const toolsMod = foundation.tools;

/// Register all AMP-specific tools with the shared registry.
pub fn registerAll(registry: *toolsMod.Registry) !void {
    // JavaScript execution tool - executes JavaScript code in sandboxed Node.js environment
    try toolsMod.registerJsonTool(
        registry,
        "javascript",
        "Execute JavaScript code in a sandboxed Node.js environment with async support",
        @import("javascript.zig").execute,
        "amp",
    );

    // Glob tool - fast file pattern matching with sorting by modification time
    try toolsMod.registerJsonTool(
        registry,
        "glob",
        "Match files by glob pattern (supports **, *, ?, {a,b}, [a-z]) and return paths sorted by mtime desc",
        @import("glob.zig").run,
        "amp",
    );

    // Code Search tool - intelligent codebase exploration with semantic search capabilities
    try toolsMod.registerJsonTool(
        registry,
        "code_search",
        "Intelligently search codebase for code based on functionality or concepts. Uses ripgrep for fast search with fallback to manual search.",
        @import("code_search.zig").run,
        "amp",
    );

    // Git Review tool - comprehensive code review automation and suggestions
    try toolsMod.registerJsonTool(
        registry,
        "git_review",
        "Perform comprehensive code review analysis of git changes. Provides file-by-file analysis, security/performance concerns, and quality suggestions.",
        @import("git_review.zig").execute,
        "amp",
    );

    // Test Writer tool - automated test generation for code analysis
    try toolsMod.registerJsonTool(
        registry,
        "test_writer",
        "Analyze code for bugs, performance, and security issues, then generate comprehensive test suites covering existing issues and regression prevention.",
        @import("test_writer.zig").execute,
        "amp",
    );

    // Command Risk Assessment tool - analyzes commands for security risks
    try toolsMod.registerJsonTool(
        registry,
        "command_risk",
        "Analyze commands for security risks and determine if they require user approval. Detects destructive operations, inline code execution, and unknown commands.",
        @import("command_risk.zig").execute,
        "amp",
    );

    // Secret File Protection tool - detects and prevents access to secret files
    try toolsMod.registerJsonTool(
        registry,
        "secret_protection",
        "Detect and prevent access to secret files and sensitive information. Analyzes file paths and content for secret patterns and provides security recommendations.",
        @import("secret_protection.zig").execute,
        "amp",
    );

    // Diagram Generation tool - creates visual diagrams using Mermaid syntax
    try toolsMod.registerJsonTool(
        registry,
        "diagram",
        "Generate visual diagrams proactively for system architecture, workflows, data flows, algorithms, class hierarchies, and state transitions. Creates Mermaid-based diagrams with dark theme styling.",
        @import("diagram.zig").execute,
        "amp",
    );

    // Code Formatter tool - formats code into markdown code blocks with language detection
    try toolsMod.registerJsonTool(
        registry,
        "code_formatter",
        "Format code content into markdown code blocks with proper language detection and filename headers. Supports extensive language mapping from file extensions.",
        @import("code_formatter.zig").execute,
        "amp",
    );

    // Request Intent Analysis tool - analyzes user requests to classify intent and suggest appropriate tools
    try toolsMod.registerJsonTool(
        registry,
        "request_intent_analysis",
        "Analyze user requests to determine intent and classification. Identifies primary purpose, extracts key entities, suggests tools, and provides confidence scoring.",
        @import("request_intent.zig").execute,
        "amp",
    );

    // Thread management tools - re-enabled with JsonReflector pattern for Zig 0.15.1 compatibility
    try toolsMod.registerJsonTool(
        registry,
        "thread_delta_processor",
        "Process thread state changes including messages, cancellations, summaries, forks, and tool interactions. Modifies thread state objects based on delta operations.",
        @import("thread_delta_processor.zig").execute,
        "amp",
    );

    try toolsMod.registerJsonTool(
        registry,
        "thread_summarization",
        "Generate detailed conversation summaries with technical context for handoff to another person. Extracts key files, functions, commands, and next steps.",
        @import("thread_summarization.zig").execute,
        "amp",
    );

    // Task tool - subagent spawning for parallel work delegation
    try toolsMod.registerJsonTool(
        registry,
        "task",
        "Launch a new agent to handle complex, multi-step tasks autonomously. Use for parallel work delegation and complex analysis tasks.",
        @import("task.zig").execute,
        "amp",
    );

    // Note: Oracle tool disabled due to foundation HTTP layer compatibility issues
    // try toolsMod.registerJsonTool(
    //     registry,
    //     "oracle",
    //     "Provide high-quality technical guidance, code reviews, architectural advice, and strategic planning with optional web research",
    //     @import("oracle.zig").execute,
    //     "amp",
    // );
}
