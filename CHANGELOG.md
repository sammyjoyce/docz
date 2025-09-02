# Changelog

## Unreleased

- feat(engine): include per-tool `input_schema` in Anthropic tools payload when available via registry
- feat(tools): add `registerJsonToolWithRequestStruct` to auto-generate minimal JSON Schemas from request structs
- feat(sessions): build-gated demo crypto/compression (`session_demo_crypto`, `security_strict`)
- refactor(foundation): remove `foundation.agent` legacy export; mark `src/agent_loop.zig` as deprecated
- fix(tui): add `Screen.drawBox`, `Screen.writeAt`, cursor/style helpers used by markdown TUI
- docs(architecture): clarify canonical engine path and schema emission
- chore(ci): add `scripts/check_legacy_agent.sh` to fail on `foundation.agent` imports

### Notes
- The markdown TUI now compiles further, but remaining issues exist in `render/markdown.zig` with legacy APIs. Consider migrating it to the new `std.Io` patterns and `std.mem.split` variants.
