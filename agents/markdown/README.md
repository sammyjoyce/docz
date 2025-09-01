# Markdown Agent - Foundation-Integrated Agent

A comprehensive markdown document processing agent integrated with the foundation framework. Provides tools for creating, editing, validating, and managing markdown documents.

## 🎯 Purpose

This agent is specifically designed for users who work with:
- **Technical documentation** (API docs, user manuals, specifications)
- **Academic writing** (research papers, dissertations, articles)
- **Content publishing** (blogs, tutorials, guides)
- **Project documentation** (READMEs, wikis, knowledge bases)
- **Long-form content** (books, reports, comprehensive guides)

## 📁 File Structure

```
agents/markdown/
├── main.zig                   # Entry point (delegates to foundation.agent_main)
├── spec.zig                   # Agent spec (system prompt + tool registration)
├── agent.zig                  # Agent implementation
├── config.zon                 # Agent configuration (aligned with foundation.config.AgentConfig)
├── system_prompt.txt          # System prompt template
├── tools/                     # JSON tools (io, content_editor, validate, document, workflow, file)
├── lib/                       # Helper libraries (fs, text, link, meta, template)
└── support/                   # Support modules
```

## 🛠️ Registered Tools

The agent registers 6 JSON tools via foundation.tools.registerJsonTool:
- **io**: Document I/O operations
- **content_editor**: Content editing operations
- **validate**: Validation operations
- **document**: Document operations
- **workflow**: Workflow engine operations
- **file**: File system operations

## 🚀 Getting Started

### Build and Run

```bash
# Build the agent
zig build -Dagent=markdown

# Run the agent
zig build -Dagent=markdown run

# Run with authentication
zig build -Dagent=markdown run auth login
zig build -Dagent=markdown run auth status

# Run with a prompt
zig build -Dagent=markdown run -- "Create a technical guide about Git workflows"
```

## 🎛️ Configuration

Edit `config.zon` and `tools.zon` as needed. Load at runtime via CLI `--config` flag.

## 🤝 Contributing

Follow repo-wide style/conventions. Keep agent-specific logic localized under `agents/markdown/`.
