---
id: amp.tool.create_agent_md
title: Create Agent Documentation Template
kind: tool
source:
  path: ./lib/node_modules/@sourcegraph/amp/dist/main.js
  lines: ''
  sha256: ''
  handlebars: true
tool_details:
  origin: ''
  entrypoint: ''
  inputs: 'Codebase context and {{oZ}} variable for filename'
  outputs: 'Agent documentation file with build commands, architecture, and style guidelines'
  behavior: 'Analyzes codebase to generate comprehensive agent documentation including build/test commands, architecture overview, and coding conventions'
  constraints: 'Requires access to project files and existing rule files'
version: '1'
last_updated: '2025-01-16 00:00:00 Z'
---

Please analyze this codebase and create an {{oZ}} file containing:
1. Build/lint/test commands - especially for running a single test
2. Architecture and codebase structure information, including important subprojects, internal APIs, databases, etc.
3. Code style guidelines, including imports, conventions, formatting, types, naming conventions, error handling, etc.

The file you create will be given to agentic coding tools (such as yourself) that operate in this repository. Make it about 20 lines long.

If there are Cursor rules (in .cursor/rules/ or .cursorrules), Claude rules (CLAUDE.md), Windsurf rules (.windsurfrules), Cline rules (.clinerules), Goose rules (.goosehints), or Copilot rules (in .github/copilot-instructions.md), make sure to include them. Also, first check if there is a {{oZ}} file, and if so, update it instead of overwriting it.