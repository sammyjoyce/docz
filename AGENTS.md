# AGENTS Guide

## Project Structure (multi-agent)

This project houses multiple independent terminal-based AI agent implementations. Each agent is built separately and shares common infrastructure through the core engine.

### Directory Structure

- **`agents/`** - Individual terminal agents (built independently)
  - **`agents/<name>/main.zig`** - Agent CLI entry point (required)
  - **`agents/<name>/spec.zig`** - Agent specification (required)
  - **`agents/<name>/agent.zig`** - Main agent implementation (required, standardized name)
  - **`agents/<name>/config.zon`** - Agent configuration (optional)
  - **`agents/<name>/system_prompt.txt`** - System prompt template (optional)
  - **`agents/<name>/tools.zon`** - Tool definitions (optional)
  - **`agents/<name>/README.md`** - Agent documentation (recommended)
  - **`agents/<name>/tools/`** - Agent-specific tools (optional)
    - `tools/mod.zig` - Tools module export (if tools/ exists)
    - `tools/*.zig` - Individual tool implementations
  - **`agents/<name>/common/`** - Agent-specific shared utilities (optional)
  - **`agents/<name>/examples/`** - Usage examples (optional)
- **`src/core/`** - Shared engine and configuration utilities
  - `src/core/engine.zig` - Main engine used by all agents
  - `src/core/config.zig` - Standardized configuration management
- **`src/`** - Shared modules (HTTP/Anthropic client, tools registry, CLI, TUI)

### Key Architecture Principles

- **Independence**: Agents are built individually, only the selected agent is compiled
- **Shared Infrastructure**: Common functionality is provided by the engine
- **Standardized Structure**: All agents follow the same directory conventions
- **Flexible Tools**: Each agent can register its own tools while inheriting built-ins
- **Configuration-Driven**: Agents use `.zon` files for structured configuration

## Build / Run
• Build default agent: `zig build`
• Run default agent: `zig build run -- <args>`
• Choose agent: `zig build -Dagent=markdown run -- <args>`
• Install only agent binary: `zig build -Dagent=markdown install-agent`
• Direct agent run (bypasses root shim): `zig build -Dagent=markdown run-agent -- <args>`
• Agent entry (markdown): `agents/markdown/main.zig` (wired via `-Dagent`)

## Tests
• All: `zig build test --summary all`
• Single file: `zig test src/<file>.zig`
• Filter: `zig test src/<file>.zig --test-filter <regex>`

## Lint / Format
• Check: `zig build fmt`
• Fix: `zig fmt src/**/*.zig build.zig build.zig.zon`

## Style
• Imports alphabetical; std first; no Cursor/Copilot overrides.
• camelCase fn/vars, PascalCase types, ALL_CAPS consts.
• Return `!Error`; wrap calls with `try`; avoid panics.
• 4-space indent; run `zig fmt` before commit.

## Data Organization
• Keep data separated in `.zon` files (use like JSON files in Node ecosystem).
• Use `.zon` files for configuration, static data, templates, and environment-specific settings.
• Co-locate `.zon` files with relevant modules (e.g., `config.zon`, `tools.zon`).
• Load `.zon` data at comptime with `@embedFile` + `std.zig.parseFromSlice`.

## Creating a New Agent

### Quick Start

1. **Copy the template**: 
   ```bash
   cp -r agents/_template agents/my-agent
   ```

2. **Customize the agent implementation** (`agents/my-agent/agent.zig`):
   - Define your agent's configuration structure
   - Implement the `loadSystemPrompt()` method
   - Add any agent-specific logic

3. **Update the spec** (`agents/my-agent/spec.zig`):
   - Register your agent-specific tools
   - The template already wires everything up correctly

4. **Configure your agent** (`agents/my-agent/config.zon`):
   - Set default values for your agent's configuration
   - Add any agent-specific settings

5. **Build and test**:
   ```bash
   zig build -Dagent=my-agent run -- "Hello from my new agent!"
   ```

### Standardized Agent Structure

Each agent **must** have these files:
- **`main.zig`** - CLI entry point (parses arguments, calls engine)
- **`spec.zig`** - Agent specification (system prompt + tools registration) 
- **`agent.zig`** - Main implementation (standardized name, replaces `<name>_agent.zig`)

Each agent **may** have these files/directories:
- **`config.zon`** - Structured configuration in ZON format
- **`system_prompt.txt`** - System prompt template with variable substitution
- **`tools.zon`** - Tool definitions and metadata  
- **`README.md`** - Agent-specific documentation
- **`tools/`** - Agent-specific tool implementations
- **`common/`** - Agent-specific shared utilities
- **`examples/`** - Usage examples and test cases

### Tool Registration

Agents can register custom tools in two ways:

**Option 1: Tools Module** (recommended for multiple tools)
```zig
// In spec.zig
fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    const tools = @import("tools/mod.zig");
    try tools.registerAll(registry);
}
```

**Option 2: Direct Registration** (simple cases)
```zig
// In spec.zig
fn registerToolsImpl(registry: *tools_mod.Registry) !void {
    try registry.register("my_tool", myToolFunction);
}
```

### Configuration Management

Use the standardized configuration system:

```zig
// In agent.zig
pub const Config = struct {
    max_operations: u32 = 100,
    enable_feature: bool = true,
    
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) Config {
        const config_utils = @import("../../src/core/config.zig");
        return config_utils.loadWithDefaults(Config, allocator, path, Config{});
    }
};
```

## Zig 0.15.1 Migration Checklist (contributors)

When editing Zig code, watch for these breaking changes introduced in 0.15.1:

### Language
• `usingnamespace` removed – replace with explicit namespaces or const declarations.
• `async`, `await`, and `@frameSize` removed – refactor coroutines to new std.Io async APIs.
• Non-exhaustive `enum` switch rules changed – audit `switch` arms that mix `_` and `else`.

### Standard Library ("Writergate")
The 0.15.1 release completely overhauls I/O streams in what's being called "Writergate" - all existing std.io readers and writers are deprecated in favor of new **non-generic** `std.Io.Reader` and `std.Io.Writer` interfaces.

#### Key Changes & Motivation:
• **Buffer is now in the interface, not the implementation** - buffers are caller-owned ring buffers
• **Concrete types instead of generics** - eliminates `anytype` poisoning throughout your codebase
• **Defined error sets** - precise, actionable errors instead of `anyerror`
• **High-level concepts** - supports vectors, splatting, direct file-to-file transfer
• **Peek functionality** - buffer awareness for convenience and performance
• **Optimizer friendly** - particularly for debug mode with buffer in interface

#### New std.Io.Writer and std.Io.Reader API:
These are **ring buffers** with new convenient APIs:

```zig
// Reading until delimiter
while (reader.takeDelimiterExclusive('\n')) |line| {
    // do something with line...
} else |err| switch (err) {
    error.EndOfStream,     // stream ended not on a line break
    error.StreamTooLong,   // line could not fit in buffer
    error.ReadFailed,      // caller can check reader implementation
    => |e| return e,
}
```

#### std.fs.File.Reader and std.fs.File.Writer:
These concrete types memoize key file information:
• File size from stat (or the error that occurred therein)
• Current seek position and seek errors
• Whether reading should be done positionally or streaming
• Whether reading should be done via fd-to-fd syscalls (e.g. `sendfile`)

This API is super handy - having a concrete type to pass around that memoizes file size is really convenient. Most code that previously called seek functions on a file handle should be updated to operate on this API instead, causing those seeks to become no-ops thanks to positional reads, while still supporting a fallback to streaming reading.

#### Migration Examples:

**Old stdout printing:**
```zig
const stdout_file = std.fs.File.stdout().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();
try stdout.print("Hello\n", .{});
try bw.flush(); // Don't forget to flush!
```

**New stdout printing:**
```zig
var stdout_buffer: [4096]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;
try stdout.print("Hello\n", .{});
try stdout.flush(); // Don't forget to flush!
```

**Server/Client streams (HTTP example):**
```zig
// Old way with generics
var server = std.http.Server.init(connection, &read_buffer);

// New way with concrete streams
var recv_buffer: [4000]u8 = undefined;
var send_buffer: [4000]u8 = undefined;
var conn_reader = connection.stream.reader(&recv_buffer);
var conn_writer = connection.stream.writer(&send_buffer);
var server = std.http.Server.init(conn_reader.interface(), &conn_writer.interface);
```

**Adapter for legacy code:**
```zig
fn foo(old_writer: anytype) !void {
    var adapter = old_writer.adaptToNewApi(&.{});
    const w: *std.Io.Writer = &adapter.new_interface;
    try w.print("{s}", .{"example"});
}
```

**Compression/Decompression:**
```zig
// Old way
var decompress = try std.compress.flate.decompressStream(allocator, reader);

// New way with ring buffer
var decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
var decompress: std.compress.flate.Decompress = .init(reader, .zlib, &decompress_buffer);
const decompress_reader: *std.Io.Reader = &decompress.reader;

// Or if piping entirely to a writer, use empty buffer:
var decompress: std.compress.flate.Decompress = .init(reader, .zlib, &.{});
const n = try decompress.streamRemaining(writer);
```

#### New Stream Concepts:
• **Discarding** when reading - allows efficiently ignoring data. A decompression stream, when asked to discard a large amount of data, can skip decompression of entire frames
• **Splatting** when writing - logical "memset" operation passes through I/O pipelines without memory copying, turning O(M*N) into O(M) operation. Can be even more efficient (e.g., splatting zero to file becomes seek forward)
• **File sending** when writing - allows I/O pipeline to do direct fd-to-fd copying when OS supports it (e.g., sendfile)
• **User-provided buffers** - stream user provides the buffer, but stream implementation decides minimum buffer size. Moves state from stream implementation into user's buffer

#### Deleted APIs & Replacements:
• `BufferedWriter` - replaced by caller-owned buffers in new interface
• `CountingWriter` - use `std.Io.Writer.Discarding` (has count) or `std.Io.Writer.fixed` (check end position) 
• `GenericReader/Writer`, `AnyReader/Writer` - replaced by concrete `std.Io.Reader/Writer`
• `SeekableStream` - use `*std.fs.File.Reader/*std.fs.File.Writer` or `std.ArrayListUnmanaged` concrete types
• `LimitedReader`, `BitReader/Writer` - deleted (bit reading should not be abstracted at this layer)
• `std.fifo.LinearFifo`, `std.RingBuffer` - removed (most use cases subsumed by new ring buffer streams)
• `BoundedArray` - migrate to `ArrayListUnmanaged.initBuffer` or fixed-slice buffers
• `std.fs.File.reader()/.writer()` → `.deprecatedReader/.deprecatedWriter`

#### Usage Notes:
• **Use buffering and don't forget to flush!** - crucial for performance
• Consider making your stdout buffer global for reuse
• Most code should migrate from file handles to `std.fs.File.Reader/Writer` APIs
• For servers/clients: HTTP Server/Client no longer depend on `std.net` - operate only on streams
• Legacy streams can use `.adaptToNewApi()` as temporary bridge
• New interface supports high-level concepts like vectors that reduce syscall overhead
• Ring buffers are more optimizer-friendly, particularly in debug mode

### Printing / Formatting
• `{}` no longer calls `format` implicitly. Use `{f}` to invoke `format`, `{any}` to bypass.
• `FormatOptions` removed; new signature: `fn format(self, writer: *std.Io.Writer) !void`.
• New specifiers `{t}`, `{b64}`, integer `{d}` for custom types.

### Containers & Memory
• `std.ArrayList` is now unmanaged; managed version lives at `std.array_list.Managed`.
• `BoundedArray` deleted – migrate to `ArrayListUnmanaged.initBuffer` or fixed-slice buffers.

### Files & FS
• `fs.File.reader()` / `writer()` renamed to `.deprecatedReader` / `.deprecatedWriter`; use `File.Reader`/`File.Writer`.
• `fs.Dir.copyFile` can't fail with `error.OutOfMemory`; `Dir.atomicFile` now needs `write_buffer`.

### Build System
• `root_source_file` et al. removed; use `root_module` in `build.zig`.
• UBSan mode now enum (`.full`, `.trap`, `.off`); update `sanitize_c` field.

### Tooling Tips
• Run `zig fmt` to auto-upgrade inline assembly clobbers and other minor syntax.
• Use `-freference-trace` to locate ambiguous `{}` format strings.
• Compile with `-fllvm` if self-hosted backend blocks you.

Always run `zig build test --summary all` before submitting PRs to catch migration regressions.