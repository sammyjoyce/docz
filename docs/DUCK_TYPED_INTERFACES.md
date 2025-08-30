# Duck-Typed Interfaces (Comptime Contracts)

This repository favors duck-typed polymorphism checked at comptime over formal interfaces. Modules expose small factories that validate a backend type using `@hasDecl`, keeping implementations decoupled and testable.

The pattern already exists in `ui/component`; this document explains how it now applies to `network` and `render` as well.

## Network Client

`src/shared/network/client.zig` exposes a generic adapter:

```zig
const net = @import("src/shared/network/mod.zig");
const Allocator = @import("std").mem.Allocator;

// Define any backend that provides the required decls
const MockBackend = struct {
    pub fn request(alloc: Allocator, req: net.Request) net.ClientError!net.Response {
        _ = alloc; _ = req;
        return .{ .status = 200, .body = "ok" };
    }
    pub fn stream(alloc: Allocator, req: net.Request, on_chunk: *const fn([]const u8) void) net.ClientError!void {
        _ = alloc; _ = req; on_chunk("chunk");
    }
    pub fn sse(alloc: Allocator, req: net.Request, on_event: *const fn(net.Event) void) net.ClientError!void {
        _ = alloc; _ = req; on_event(.{ .event = "message", .data = "hi" });
    }
};

// Bind at comptime; compile fails if decls are missing
const Client = net.use(MockBackend);

// Usage
// const resp = try Client.request(allocator, .{ .url = "https://example.com" });
```

Required declarations on the backend:
- `request(allocator, Request) -> ClientError!Response`
- `stream(allocator, Request, *const fn([]const u8) void) -> ClientError!void`
- `sse(allocator, Request, *const fn(Event) void) -> ClientError!void`

The adapter also provides a convenience `download` that calls the backend’s `request` and writes to a file.

## Renderer Backend

`src/shared/render/mod.zig` now exposes a comptime factory for renderer backends:

```zig
const render = @import("src/shared/render/mod.zig");

const MyBackend = struct {
    pub fn beginFrame(self: *MyBackend, width: u16, height: u16) !void { _ = self; _ = width; _ = height; }
    pub fn endFrame(self: *MyBackend) !void { _ = self; }
    pub fn drawText(self: *MyBackend, x: i16, y: i16, text: []const u8, style: render.Style) !void {
        _ = self; _ = x; _ = y; _ = text; _ = style;
    }
    pub fn measureText(self: *MyBackend, text: []const u8, style: render.Style) !render.Point {
        _ = self; _ = style; return .{ .x = @intCast(text.len), .y = 1 };
    }
    pub fn moveCursor(self: *MyBackend, x: u16, y: u16) !void { _ = self; _ = x; _ = y; }
    pub fn fillRect(self: *MyBackend, ctx: render.Render, color: render.Style.Color) !void { _ = self; _ = ctx; _ = color; }
    pub fn flush(self: *MyBackend) !void { _ = self; }

    // Optional extras:
    // pub fn drawBox(self: *MyBackend, ctx: render.Render, box: render.BoxStyle) !void { ... }
    // pub fn drawLine(self: *MyBackend, ctx: render.Render, from: render.Point, to: render.Point) !void { ... }
};

const API = render.useBackend(MyBackend); // comptime checks via @hasDecl
var backend = MyBackend{};
try API.beginFrame(&backend, 80, 24);
try API.drawText(&backend, 1, 1, "hello", .{});
try API.endFrame(&backend);
try API.flush(&backend);
```

Required backend declarations:
- `beginFrame(*Backend, u16, u16) !void`
- `endFrame(*Backend) !void`
- `drawText(*Backend, i16, i16, []const u8, Style) !void`
- `measureText(*Backend, []const u8, Style) !Point`
- `moveCursor(*Backend, u16, u16) !void`
- `fillRect(*Backend, Render, Style.Color) !void`
- `flush(*Backend) !void`

Optional declarations (re-exported if present): `drawBox`, `drawLine`.

## Why This Pattern
- No inheritance or global trait tables; zero runtime cost.
- Backends remain independent; tests can inject mocks/fakes.
- Clear error surfaces: your backends return the same typed errors defined by the module, not `anyerror`.

## Notes
- Zig 0.15.1: Avoid `usingnamespace`; these factories re-export symbols explicitly.
- Compile-time checks use `@hasDecl` only; signatures are validated naturally where you call the functions.
- Keep backends small and focused; gate inclusion with feature flags to avoid leaking code into unrelated agents.
