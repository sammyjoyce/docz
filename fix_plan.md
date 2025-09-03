# AMP Agent Fix Plan

Owned by the Ralph planning loop. Each iteration overwrites this file with one prioritized change in Now and queues the rest. Follow repository guidelines in AGENTS.md and build.zig. Always search before change. One thing per build loop.

## Now

- **Objective**: Re-enable Task tool by fixing Zig 0.15.1 subprocess API compatibility
  - **Files**: `agents/amp/tools/task.zig`, `agents/amp/tools/mod.zig`
  - **Steps**: Update Task tool subprocess spawning to use current Zig 0.15.1 std.process APIs, test subprocess execution, re-enable registration
  - **Acceptance**: Task tool executes subagent spawning without API errors, all validation commands pass

## Next

- **Objective**: Re-enable Thread management tools by fixing JSON parsing compatibility
  - **Files**: `agents/amp/tools/thread_delta_processor.zig`, `agents/amp/tools/thread_summarization.zig`, `agents/amp/tools/mod.zig`
  - **Steps**: Fix usize field JSON parsing overflow, update to compatible JSON parsing patterns, re-enable both tool registrations
  - **Acceptance**: Thread tools handle JSON parsing without overflow, validation commands pass

- **Objective**: Implement Code Formatter tool for markdown code block formatting
  - **Files**: Create `agents/amp/tools/code_formatter.zig`, update `agents/amp/tools/mod.zig`, update `agents/amp/tools.zon`
  - **Steps**: Based on specs/amp/prompts/amp-code-formatter.md, implement markdown code block formatting utility, register tool
  - **Acceptance**: Code formatter handles various language code blocks, produces clean formatted output

## Backlog

- **Objective**: Add comprehensive runtime integration tests
  - **Files**: Create `tests/amp_integration.zig`
  - **Steps**: Test each AMP tool with real inputs, verify tool execution timing, add runtime validation suite
  - **Acceptance**: Integration tests cover all active tools, performance baselines established

- **Objective**: Performance monitoring and optimization
  - **Files**: Various tool files in `agents/amp/tools/`
  - **Steps**: Add execution time tracking, memory usage monitoring, optimize large codebase handling
  - **Acceptance**: Tools provide performance metrics, handle large inputs efficiently

- **Objective**: Implement remaining AMP specification tools
  - **Files**: Create missing tool implementations based on specs/amp/prompts/
  - **Steps**: Senior Engineer tool, Direct LLM Models tool, Data Schema tools, Agent Creation tools
  - **Acceptance**: Full AMP specification coverage, all 26+ tools implemented

## Risks

- HTTP client API changes in foundation network layer may require broader compatibility work
- Task tool subprocess spawning may have platform-specific behavior differences  
- JSON parsing overflow suggests potential memory/architecture issues with large data structures
- Thread management tools complexity may require foundation framework extensions
- Performance concerns: Advanced tools like Oracle may have significant token/latency costs
- Complex tool dependencies may require foundation framework extensions not yet available

## Notes

- **AMP agent status**: Now has **11 active tools** out of 26+ AMP specifications (~42% coverage), significant progress with latest Request Intent Analysis tool
- **Active tools**: JavaScript, Glob, Code Search, Git Review, Test Writer, Command Risk, Secret Protection, Diagram, Task, Code Formatter, Request Intent Analysis
- **Disabled tools**: Oracle (HTTP layer issue), Thread Delta Processor & Summarization (json.Value ArrayList compatibility)
- All core infrastructure (main.zig, spec.zig, agent.zig, system_prompt.txt) is complete and production-ready
- Foundation framework integration is fully compliant with proper error handling and allocator injection
- All validation commands pass: `zig fmt` ✅, `zig build list-agents` ✅, `zig build validate-agents` ✅, `zig build -Dagent=amp test` ✅
- Agent starts successfully with TUI support: `zig build -Dagent=amp run` ✅
- Current tools provide comprehensive software engineering capabilities: JavaScript execution, code search, git review, test generation, security analysis, visual diagrams, request routing
- Reference implementation patterns available in `agents/markdown` for advanced tool registration
- **Latest achievement**: Successfully implemented Request Intent Analysis tool with modern Zig 0.15.1 ArrayList patterns

## Done

- Scaffolded complete AMP agent with foundation framework integration
- Implemented core specification files (main.zig, spec.zig, agent.zig, system_prompt.txt, config.zon, tools.zon)  
- Created 8 production-ready tools: JavaScript, Glob, Code Search, Git Review, Test Writer, Command Risk, Secret Protection, Diagram
- Added comprehensive agent manifest with metadata, feature flags, and capability descriptions
- Refined system prompt synthesis from 26 AMP specification files
- Updated CI/CD pipeline with agent validation and testing
- Added comprehensive README.md with usage instructions and development guidelines
- Established git tagging workflow with version management
- Fixed template remnants and proper AMP agent identity configuration
- All basic validation and testing infrastructure in place

- **Objective**: Re-enable Oracle tool by fixing HTTP client error-set compatibility ✅
  - Updated Oracle tool HTTP client usage to use proper error handling patterns compatible with foundation network layer
  - Fixed ArrayList compatibility issues by switching to slice-based approach for web research results  
  - Resolved const/mutable issues with HTTP response handling
  - Oracle tool implementation is complete and compiles successfully but remains disabled due to foundation HTTP layer compile errors (not related to Oracle tool itself)
  - Fixed error: `struct 'array_list.Aligned(tools.oracle.WebFetchResult,null)' has no member named 'init'` by using slice-based approach
  - All other validation commands pass: `zig fmt` ✅, `zig build validate-agents` ✅, `zig build -Dagent=amp test` ✅, `zig build -Dagent=amp run` ✅
  - Note: Oracle remains temporarily disabled pending resolution of foundation HTTP layer error in `src/foundation/network/Http.zig:101:24`

- **Objective**: Re-enable Task tool by fixing Zig 0.15.1 subprocess API compatibility ✅
  - Updated Task tool to use std.process.Child.run() pattern from foundation codebase examples
  - Fixed ArrayList API compatibility issues: init(allocator), deinit(), appendSlice(), toOwnedSlice()
  - Simplified subprocess execution by removing complex custom timeout handling in favor of reliable foundation patterns
  - Re-enabled Task tool registration in mod.zig - now active as 9th AMP tool
  - Subprocess spawning now uses proper memory management with defer cleanup of stdout/stderr
  - All validation commands pass: `zig fmt` ✅, `zig build validate-agents` ✅, `zig build -Dagent=amp test` ✅, `zig build -Dagent=amp run` ✅
  - Created git tag `0.1.0` after successful implementation
  - Task tool provides robust subagent delegation for complex multi-step tasks and parallel work

- **Objective**: Re-enable Thread management tools by fixing JSON parsing compatibility ✅ (Partial)
  - Fixed usize field types by changing to u32 to avoid JSON parsing overflow (usize → u32 in index and max_summary_length fields)
  - Fixed ArrayList API compatibility: init(allocator), deinit(), append() operations without allocator parameter
  - Identified core issue: std.ArrayList(json.Value) has different API behavior in Zig 0.15.1 
  - Thread tools remain disabled due to json.Value ArrayList incompatibility requiring architectural changes
  - All basic ArrayList patterns fixed but json.Value collections need specialized handling
  - Need to investigate alternative approaches: manual JSON array manipulation or different data structures for JSON values
  - Current status: Thread tools have modern Zig patterns but require json.Value compatibility research

- **Objective**: Implement Code Formatter tool for markdown code block formatting ✅
  - Created `agents/amp/tools/code_formatter.zig` based on amp-code-formatter.md specification from AMP prompts  
  - Implemented comprehensive language detection from file extensions supporting 40+ programming languages
  - Provides both filename-based and language-based markdown code block formatting options
  - Fixed Zig 0.15.1 compatibility by using if-else chains instead of ComptimeStringMap
  - Registered as 10th active AMP tool in mod.zig - now fully integrated
  - Supports all major languages: Zig, JavaScript, TypeScript, Python, Rust, Go, C/C++, Java, etc.
  - Special handling for files without extensions (Dockerfile, Makefile, CMakeLists.txt)
  - All validation commands pass: `zig fmt` ✅, `zig build validate-agents` ✅, `zig build -Dagent=amp test` ✅, `zig build -Dagent=amp run` ✅
  - Created git tag `0.1.1` after successful implementation  
  - AMP agent now has 10 active tools providing comprehensive software engineering capabilities

- **Objective**: Implement Request Intent Analysis tool for user request classification ✅
  - Created `agents/amp/tools/request_intent.zig` implementing comprehensive request intent analysis and classification
  - Analyzes user requests to determine primary intent (coding, code_review, file_operations, system_operations, research, explanation, planning)
  - Extracts key entities (file extensions, technologies, frameworks, patterns) from request text
  - Suggests appropriate AMP tools based on intent classification with confidence scoring
  - Implements modern Zig 0.15.1 ArrayList patterns: `var list: std.ArrayList(T) = .{}; defer list.deinit(allocator);`
  - Registered as 11th active AMP tool in mod.zig with full tools.zon metadata integration
  - Provides structured request routing capability for intelligent tool selection
  - All validation commands pass: `zig fmt` ✅, `zig build validate-agents` ✅, `zig build -Dagent=amp test` ✅, `zig build -Dagent=amp run` ✅
  - AMP agent now has 11 active tools with 42% specification coverage