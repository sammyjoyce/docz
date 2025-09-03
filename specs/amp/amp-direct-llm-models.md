---
id: amp.system.direct_llm_models
title: Direct LLM Models Template
kind: system
source:
  path: ./lib/node_modules/@sourcegraph/amp/dist/main.js
  lines: ''
  sha256: ''
  handlebars: true
version: '1'
last_updated: '2025-08-16 12:00:00 Z'
---

## Available Models

{{#each models}}
- **{{id}}** ({{provider}}): {{description}}
{{/each}}