---
id: amp.code.formatter
title: Code Block Formatter Function
kind: tool
source:
  path: ./lib/node_modules/@sourcegraph/amp/dist/main.js
  lines: '31-33'
  sha256: ''
  handlebars: false
tool_details:
  origin: '@sourcegraph/amp/dist/main.js'
  entrypoint: yK1
  inputs: 'filePath: string, content: string'
  outputs: 'string (markdown code block)'
  behavior: 'Formats code content into markdown code block with filename header extracted from path'
  constraints: 'Internal utility function, not directly exposed as user tool'
version: '1'
last_updated: '2025-01-16 00:00:00 Z'
---

function yK1(A,Q){return`\`\`\`${b6.basename(v9(A))}
${Q}
\`\`\``}