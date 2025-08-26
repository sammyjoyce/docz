# docz

Terminal AI agents in Zig. The repo now supports multiple independent agents with shared core runtime. The existing Markdown agent is the first implementation.

## ✨ Features

- **5 Specialized Tools** for comprehensive markdown document management
- **ZON Configuration** with native Zig configuration format  
- **Template System** for consistent document creation
- **Multi-Format Export** (HTML, PDF, DOCX, LaTeX)
- **Quality Validation** with multiple rulesets
- **Large Document Support** optimized for 10k+ line documents

## 🚀 Quick Start

### Build and Run (multi-agent)

```bash
# Clone and build
git clone https://github.com/sammyjoyce/docz.git
cd docz/
zig build                         # builds default agent (markdown)
zig build run -- "Create a technical guide about Git workflows"

# Choose an agent explicitly (default is markdown)
zig build -Dagent=markdown run -- "Generate a README"

# Install only the selected agent binary
zig build -Dagent=markdown install-agent

# Run agent entry directly (bypasses root shim)
zig build -Dagent=markdown run-agent -- "Explain usage"
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
agents/
  markdown/               # Markdown agent (entry + spec + impl)
    ├── main.zig          # Agent entry point (CLI + engine)
    ├── spec.zig          # Agent-specific prompts/tools hook
    ├── markdown_agent.zig# Agent implementation API
    ├── config.zon, tools.zon, system_prompt.txt, ...

src/
  core/
    └── engine.zig        # Shared engine (auth, loop, streaming)
  markdown_agent/         # Compatibility bridge for imports (kept)
    └── markdown_agent.zig
  cli.zig                 # Shared CLI parsing
  tools.zig               # Shared tools registry (generic)
  anthropic.zig           # Anthropic HTTP client
  main.zig                # Delegates to active agent selected via -Dagent
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
// Use the shared engine and provide an AgentSpec
const engine = @import("core_engine");
const my_spec: engine.AgentSpec = .{
    .buildSystemPrompt = (struct {
        fn f(a: std.mem.Allocator, o: engine.CliOptions) ![]const u8 { _ = o; return a.dupe(u8, "My agent"); }
    }).f,
    .registerTools = (struct { fn f(reg: *@import("tools_shared").Registry) !void { _ = reg; } }).f,
};
try engine.runWithOptions(allocator, options, my_spec);
```

## 📖 Documentation

- **[PROJECT.md](PROJECT.md)** - Complete project documentation and architecture
- **[agents/markdown/README.md](agents/markdown/README.md)** - Markdown agent guide
- **[agents/markdown/examples.md](agents/markdown/examples.md)** - Usage examples and workflows
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
