# MarkDown Master - Specialized CLI Agent

A comprehensive CLI agent framework designed exclusively for creating, editing, and managing markdown documents. Built for handling long, complex documents with sophisticated structure, extensive cross-references, and detailed content.

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
├── main.zig                   # Agent entry point
├── spec.zig                   # Agent spec (prompts + tools registration)
├── markdown_agent.zig         # Agent implementation (public API)
├── tools.zon                  # Tool definitions/config (ZON)
├── config.zon                 # Agent configuration (ZON)
├── system_prompt.txt          # System prompt template
├── examples.md                # Usage examples and workflows
└── common/, tools/            # Internal modules
```

## 🛠️ Core Tools

See tools in `tools/` and schemas in `tools.zon`.

## 🚀 Getting Started

Use the root CLI with the markdown agent selected (default):

```bash
zig build run -- "Create a technical guide about Git workflows"
zig build -Dagent=markdown run -- --config agents/markdown/config.zon "Edit document structure"
```

## 🎛️ Configuration

Edit `config.zon` and `tools.zon` as needed. Load at runtime via CLI `--config` flag.

## 🤝 Contributing

Follow repo-wide style/conventions. Keep agent-specific logic localized under `agents/markdown/`.
