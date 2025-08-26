# AGENTS Guide

## Build / Run
• Build: `zig build`
• Run: `zig build run -- <args>`

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

## Zig 0.15.1 Migration Checklist (contributors)

When editing Zig code, watch for these breaking changes introduced in 0.15.1:

### Language
• `usingnamespace` removed – replace with explicit namespaces or const declarations.
• `async`, `await`, and `@frameSize` removed – refactor coroutines to new std.Io async APIs.
• Non-exhaustive `enum` switch rules changed – audit `switch` arms that mix `_` and `else`.

### Standard Library (“Writergate”)
• Old `std.io` readers/writers deprecated; use `std.Io.Reader` / `std.Io.Writer` with caller-owned buffers.
• Deleted helpers: `BufferedWriter`, `CountingWriter`, `GenericReader/Writer`, `SeekableStream`, `LimitedReader`, `fifo`, etc.
• Adapt legacy streams only via `.adaptToNewApi()` as a temporary bridge.

### Printing / Formatting
• `{}` no longer calls `format` implicitly. Use `{f}` to invoke `format`, `{any}` to bypass.
• `FormatOptions` removed; new signature: `fn format(self, writer: *std.Io.Writer) !void`.
• New specifiers `{t}`, `{b64}`, integer `{d}` for custom types.

### Containers & Memory
• `std.ArrayList` is now unmanaged; managed version lives at `std.array_list.Managed`.
• `BoundedArray` deleted – migrate to `ArrayListUnmanaged.initBuffer` or fixed-slice buffers.

### Files & FS
• `fs.File.reader()` / `writer()` renamed to `.deprecatedReader` / `.deprecatedWriter`; use `File.Reader`/`File.Writer`.
• `fs.Dir.copyFile` can’t fail with `error.OutOfMemory`; `Dir.atomicFile` now needs `write_buffer`.

### Build System
• `root_source_file` et al. removed; use `root_module` in `build.zig`.
• UBSan mode now enum (`.full`, `.trap`, `.off`); update `sanitize_c` field.

### Tooling Tips
• Run `zig fmt` to auto-upgrade inline assembly clobbers and other minor syntax.
• Use `-freference-trace` to locate ambiguous `{}` format strings.
• Compile with `-fllvm` if self-hosted backend blocks you.

Always run `zig build test --summary all` before submitting PRs to catch migration regressions.