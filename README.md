# docz

**Markdown-Focused CLI Agent** - A specialized AI assistant built in Zig for creating, editing, and managing complex markdown documents with sophisticated tooling.

## ✨ Features

- **5 Specialized Tools** for comprehensive markdown document management
- **ZON Configuration** with native Zig configuration format  
- **Template System** for consistent document creation
- **Multi-Format Export** (HTML, PDF, DOCX, LaTeX)
- **Quality Validation** with multiple rulesets
- **Large Document Support** optimized for 10k+ line documents

## 🚀 Quick Start

### Build and Run

```bash
# Clone and build
git clone https://github.com/sammyjoyce/docz.git
cd docz/
zig build

# Run the markdown agent
zig build run -- "Create a technical guide about Git workflows"

# Run with specific configuration
zig build run -- --config src/markdown_agent/config.zon "Edit document structure"
```

### Download Release

```bash
# Download latest release
wget https://github.com/sammyjoyce/docz/releases/latest/download/<archive>
tar -xf <archive>    # Unix
unzip <archive>      # Windows
./<binary> -h
```

## 🛠️ Markdown Agent Tools

The specialized markdown agent includes these tools:

| Tool | Purpose | Key Features |
|------|---------|--------------|
| `document_io` | Document I/O operations | File reading, content search, workspace navigation |
| `content_editor` | Content modification | Text editing, structure changes, table operations, metadata management, formatting |
| `document_validator` | Quality assurance | Structure validation, link checking, spell checking, compliance |
| `document_transformer` | Document creation & conversion | Template operations, format conversion, document generation |
| `workflow_processor` | Complex workflows | Sequential workflows, batch operations, multi-step processing, automation |

## 📁 Project Structure

```
src/markdown_agent/        # Specialized markdown agent
├── markdown_agent.zig     # Core agent implementation  
├── config.zon            # Configuration (validation rules, templates)
├── tools.zon             # Tool definitions and schemas
├── system_prompt.txt     # Agent system prompt
├── examples.md           # Usage examples and workflows
├── README.md             # Module documentation
└── tools/                # Tool implementations (5 tools)
    ├── document_io.zig
    ├── content_editor.zig
    ├── document_validator.zig
    ├── document_transformer.zig
    └── workflow_processor.zig
```

## 🎯 Use Cases

- **Technical Documentation** - API docs, user manuals, specifications
- **Academic Writing** - Research papers, articles, dissertations  
- **Content Publishing** - Blogs, tutorials, guides
- **Project Documentation** - READMEs, wikis, knowledge bases
- **Long-Form Content** - Books, reports, comprehensive guides

## 🔧 Integration as Module

1. Add `docz` dependency to `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/sammyjoyce/docz.git
```

2. Use `docz` dependency in `build.zig`:

```zig
const docz_dep = b.dependency("docz", .{
    .target = target,
    .optimize = optimize,
});
const docz_mod = docz_dep.module("docz");
exe.root_module.addImport("docz", docz_mod);
```

3. Use in your code:

```zig
const docz = @import("docz");
const markdown_agent = docz.markdown_agent;

// Initialize the agent
const agent = markdown_agent.MarkdownAgent.init(allocator, config);
const result = try agent.executeCommand("document_transformer", params);
```

## 📖 Documentation

- **[PROJECT.md](PROJECT.md)** - Complete project documentation and architecture
- **[src/markdown_agent/README.md](src/markdown_agent/README.md)** - Markdown agent module guide
- **[src/markdown_agent/examples.md](src/markdown_agent/examples.md)** - Usage examples and workflows
- **[AGENTS.md](AGENTS.md)** - General agent development guide

## 🏗️ Development

```bash
# Format code
zig fmt src/**/*.zig build.zig build.zig.zon

# Run tests
zig build test --summary all

# Check formatting
zig build fmt

# Create release builds
zig build release
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Ensure `zig build` passes
5. Submit a pull request

See [PROJECT.md](PROJECT.md) for detailed contribution guidelines.

## 📄 License

Educational and development purposes. See individual files for specific licensing.

---

**Built with Zig 0.15.1** - Performance, safety, and maintainability focused.