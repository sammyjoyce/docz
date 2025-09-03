---
id: amp.user.thread_summarization
title: Thread Summarization Prompt
kind: user
source:
  path: ./lib/node_modules/@sourcegraph/amp/dist/main.js
  lines: ''
  sha256: ''
  handlebars: false
version: '1'
last_updated: '2025-08-16 00:00:00 Z'
---

Provide a detailed but concise summary of our conversation above.

Provide enough information so that someone else can continue the conversation in your place.

Your summary should contain:
- what I wanted (include any specific requirements the user mentioned)
- what we did
- what we're currently doing, in case there are tasks we're in the middle of
- optional: the next steps that you would take that are related to the recent work
- important file paths, function names, code snippets, and commands that are helpful for someone else to continue where we left off. Explain _why_ they are important.

When summarizing the user's interactions:
- mention any links, examples, or references the user provided
- note any preferences or specific approaches the user requested, especially when the user corrected the agent's behavior

Address the user in the second person.

Structure your response like this:

<example>
<summary>
[Your summary of the conversation]
</summary>
<title>
[Your max-7-words sentence-case title for the conversation]
</title>
</example>