# DOCZ - Markdown-Focused CLI Agent

A specialized CLI agent built in Zig for creating, editing, and managing markdown documents with sophisticated tooling for long-form, complex documents.

## 🏗️ Project Structure

```
docz/
├── src/
│   ├── main.zig              # Entry point
│   ├── docz.zig              # Core API module
│   ├── cli.zig               # CLI handling
│   ├── cli.zon               # CLI configuration
│   ├── agent.zig             # Agent orchestration
│   ├── anthropic.zig         # Anthropic API integration
│   ├── tools.zig             # General tools framework
│   └── markdown_agent/       # ✨ Markdown Agent Module
│       ├── markdown_agent.zig    # Main agent implementation
│       ├── config.zon            # Agent configuration
│       ├── tools.zon             # Tool definitions (ZON format)
│       ├── system_prompt.txt     # Agent system prompt
│       ├── examples.md           # Usage examples
│       ├── README.md             # Module documentation
│       └── tools/                # Tool implementations
│           ├── mod.zig               # Tools module
│           ├── document_io.zig
│           ├── content_editor.zig
│           ├── document_validator.zig
│           ├── document_transformer.zig
│           └── workflow_processor.zig
├── specs/                    # Specifications
├── build.zig                 # Build configuration
├── build.zig.zon            # Project metadata
└── README.md                # Main project README
```

## 🚀 Quick Start

### Build & Run

```bash
# Build the project
zig build

# Run with markdown mode
./zig-out/bin/docz "Create a technical guide about Git workflows"

# Run with specific configuration
./zig-out/bin/docz --config src/markdown_agent/config.zon "Edit README.md structure"
```

### Development

```bash
# Format code
zig fmt src/**/*.zig build.zig build.zig.zon

# Run tests
zig build test --summary all

# Check formatting
zig build fmt

# Clean build
rm -rf .zig-cache zig-out
```

## 🛠️ Markdown Agent Features

### Core Tools (5 specialized tools)

1. **document_io** - Document I/O operations and workspace navigation
2. **content_editor** - Content modification, structural changes, table operations, metadata management, and formatting
3. **document_validator** - Quality assurance, link checking, and compliance validation
4. **document_transformer** - Document creation, template operations, and format conversion
5. **workflow_processor** - Complex workflows, batch operations, and automation

### Configuration System

- **ZON-based configuration** (src/markdown_agent/config.zon)
- **Multiple validation rulesets** (default, strict, academic, technical)
- **Document templates** (article, blog, tutorial, documentation, etc.)
- **Customizable formatting options**

### System Architecture

```zig
// Integration example
const markdown_agent = @import("markdown_agent");

const agent = markdown_agent.MarkdownAgent.init(allocator, config);
const tools = try agent.getAvailableTools();
const result = try agent.executeCommand("document_transformer", params);
```

## 🎯 Design Principles

### Sustainability
- **Modular architecture** - Each tool is independently maintainable
- **ZON configuration** - Native Zig configuration format
- **Comprehensive tests** - Each tool has dedicated test coverage
- **Clear separation** - Agent logic separate from CLI framework
- **Extensible design** - Easy to add new tools and capabilities

### Performance
- **Streaming operations** - Handle large documents efficiently
- **Memory management** - Proper allocation and cleanup
- **Incremental processing** - Work with document sections
- **Caching** - Smart caching of parsed structures

### Quality
- **Validation-first** - All operations validate before executing
- **Transaction-like** - Atomic operations with rollback capability
- **Error handling** - Comprehensive error reporting
- **Format compliance** - Strict markdown standard adherence

## 🔧 Integration Guide

### Adding New Tools

1. Create tool implementation in `src/markdown_agent/tools/`
2. Add to `tools/mod.zig` registry
3. Define schema in `tools.zon`
4. Add tests and documentation
5. Update system prompt if needed

### Configuration Updates

Edit `src/markdown_agent/config.zon`:
```zig
.default_settings = .{
    .text_wrap_width = 80,
    .heading_style = "atx",
    // ... other settings
},
```

### Custom Validation Rules

```zig
.validation_rules = .{
    .custom = .{
        .require_h1 = true,
        .max_heading_depth = 4,
        .enforce_front_matter = true,
        // ... custom rules
    },
},
```

## 📈 Roadmap

### Phase 1: Core Implementation (Current)
- [x] Basic tool framework
- [x] ZON configuration system  
- [x] 5 core tools (placeholder implementations)
- [x] Build system integration
- [x] Project structure

### Phase 2: Tool Implementation
- [ ] Document structure parser and manipulator
- [ ] Content block precise editing
- [ ] Markdown formatter with style rules
- [ ] Link validator and updater
- [ ] Table editor with alignment
- [ ] Metadata manager with schemas
- [ ] Document validator with multiple rulesets
- [ ] Template system with variables
- [ ] Multi-format converter

### Phase 3: Advanced Features  
- [ ] Real-time document analysis
- [ ] Cross-document reference management
- [ ] Collaborative editing support
- [ ] Plugin system for custom tools
- [ ] Web interface for document management

### Phase 4: Optimization
- [ ] Performance tuning for large documents
- [ ] Memory usage optimization
- [ ] Parallel processing capabilities
- [ ] Smart caching strategies

## 🤝 Contributing

### Code Style
- Follow Zig 0.15.1 conventions
- Use `zig fmt` before commits
- Maintain ZON format for configuration
- Add comprehensive tests for new features

### Pull Request Process
1. Create feature branch from `main`
2. Implement changes with tests
3. Update documentation
4. Ensure `zig build` passes
5. Submit PR with clear description

### Issues & Bug Reports
- Use GitHub issues for bug reports
- Include minimal reproduction case
- Specify Zig version and OS
- Provide relevant log output

## 📄 License

This project is built for educational and development purposes. Adapt the licensing as needed for your specific use case.

---

**Built with Zig 0.15.1** - A systems programming language focused on performance, safety, and maintainability.