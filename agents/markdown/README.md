# Markdown Agent

Enterprise-grade markdown systems architect integrated with the foundation framework.

## Overview

The Markdown agent provides comprehensive tools for creating, editing, validating, and managing markdown documents. It's fully integrated with the foundation framework's shared engine and authentication system.

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
