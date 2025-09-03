---
id: amp.analysis.request_intent
title: Request Intent Analysis Prompt
kind: user
source:
  path: ./lib/node_modules/@sourcegraph/amp/dist/main.js
  lines: ''
  sha256: ''
  handlebars: true
version: '1'
last_updated: '2025-08-16 00:00:00 Z'
---

Analyze the following user request and determine its intent and classification.

Your task is to understand what the user is asking for and classify the request into appropriate categories to help route it to the right tools and capabilities.

Consider the following aspects:
- Is this a coding request (writing, reviewing, debugging, refactoring)?
- Is this a question about existing code or systems?
- Is this a request for explanation or documentation?
- Is this a request for file operations (reading, writing, searching)?
- Is this a request for system operations (running commands, managing processes)?
- Is this a research or web search request?
- Is this a planning or architectural discussion?

User Request: {{USER_REQUEST}}

Analyze the request and provide:
1. Primary intent category
2. Secondary categories (if applicable)  
3. Key entities mentioned (files, technologies, concepts)
4. Suggested approach or tools needed
5. Any clarification questions that might be helpful

Format your response as a structured analysis that can guide the system's response strategy.