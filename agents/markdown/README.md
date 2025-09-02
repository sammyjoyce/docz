# Markdown Agent - Production-Ready Implementation

**World-class CLI/TUI experience for markdown processing with AI assistance.**

## Overview

The Markdown agent is a **production-ready, feature-complete implementation** providing comprehensive markdown tools with both CLI and TUI interfaces. This is NOT a demo - it's a complete implementation designed for real users to depend on daily.

## Integration Status

✅ **Fully integrated with foundation framework (v2.0.0)**
- Uses `foundation.agent_main.runAgent()` for CLI and auth
- Leverages shared `core_engine` loop for SSE and tool handling
- All 6 JSON tools registered via `foundation.tools.registerJsonTool()`
- Config uses `foundation.config.AgentConfig` field mapping
- No custom loops or exported `anyerror`
- Full TUI included by default; disable at build time with `-Denable-tui=false` if needed

## Architecture

```
agents/markdown/
├── main.zig          # Entry point using foundation.agent_main.runAgent()
├── spec.zig          # AgentSpec with buildSystemPrompt() and registerTools()
├── agent.zig         # Markdown struct with config and system prompt loading
├── config.zon        # Configuration aligned with foundation.config.AgentConfig
├── system_prompt.txt # System prompt template
└── tools/            # JSON tools registered via foundation.tools
    ├── io.zig
    ├── content_editor.zig
    ├── validate.zig
    ├── document.zig
    ├── workflow.zig
    └── file.zig
```

## Tools

The agent registers 6 markdown-specific JSON tools:
- **io**: Read files, search content, explore workspace
- **content_editor**: Edit and modify markdown content
- **validate**: Validate document quality and structure
- **document**: Create documents, convert formats, apply templates
- **workflow**: Execute multi-step workflows and batch operations
- **file**: Manage files and directories

## Building and Running

```bash
# Build the agent
zig build -Dagent=markdown

# Run with foundation engine and auth
zig build -Dagent=markdown run

# Test the agent
zig build -Dagent=markdown test
# Launch full TUI (enabled by default; disable via -Denable-tui=false)
zig build -Dagent=markdown run -- --tui
# Run with a prompt
zig build -Dagent=markdown run -- "Create a technical guide about Git workflows"

# Test the agent
zig build -Dagent=markdown test
```

## 🎛️ Configuration

The agent uses `config.zon` which follows the `foundation.config.AgentConfig` schema with proper field mapping:
- `concurrentOperationsMax` for maximum concurrent operations
- `timeoutMsDefault` for default timeout
- `inputSizeMax` / `outputSizeMax` for size limits
- `processingTimeMsMax` for processing time limits
- `modelDefault` for default model

Additional markdown-specific settings are available for heading style, list style, etc.

## 🤝 Contributing

Follow repo-wide style/conventions. Keep agent-specific logic localized under `agents/markdown/`.
