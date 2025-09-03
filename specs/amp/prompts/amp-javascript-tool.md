---
id: amp.tool.javascript
title: JavaScript Tool Documentation
kind: tool
source:
  path: ./lib/node_modules/@sourcegraph/amp/dist/main.js
  lines: ''
  sha256: ''
  handlebars: false
tool_details:
  origin: '@sourcegraph/amp'
  entrypoint: 'javascript'
  inputs: 'code: string | codePath: string'
  outputs: 'JSON serializable return value'
  behavior: 'Executes JavaScript in sandboxed Node.js CommonJS environment with async support'
  constraints: 'No external npm packages, no file imports, absolute paths required'
version: '1'
last_updated: '2025-01-16 00:00:00 Z'
---

Execute a JavaScript script using Node.js.

This tool allows you to run JavaScript code directly in a sandboxed Node.js environment.

Use this tool when:
- You want to perform complex calculations
- You want to process large files
- You want to process many files
- You want a large amount of fine-grained parallelism (this tool supports async)
- You want to pre-process data before passing it to another tool
- You want to chain tools together
- You want to ensure that you process every item in a large list
- You want to handle codebase-wide operations in a deterministic manner

## Important notes

1. Execution Environment:
    - The code runs in a sandboxed Node.js CommonJS environment
       - That means you should always use require() instead of import
    - All Node.js built-in modules are available (node:fs, node:path, node:crypto, etc.)
    - There is no working directory during execution, so always use absolute paths
    - You can generate the script to run directly with the `code` argument, or if the script is already written to a file, you prefer to use the `codePath` argument instead.
    - <important>The script is run inside an `(async () => { ... })()` block. This means you can use `await` at the top level inside your script, and you MUST `await` all promises before returning. Additionally, you MUST end your script with a return statement</important>

2. Available APIs:
    - All Node.js built-in modules (import with 'node:' prefix)
    - You also have access to the `Task` tool, which is importable from the 'amp/tools'. The Task tool returns an object with the type `{result: string}`
    - No external npm packages are available
    - No other files can be imported
    - Console output is shown to the user as progress updates

3. Output:
    - The return value of the script is returned to you in the tool call result. It must be serializable as JSON. Attempt to minimize the size of this output to avoid consuming a large portion of your context window. Do not include any irrelevant information.
    - All console.log, console.warn, and console.error messages are streamed back to the user as the script is executing. They will not be visible to you, so include any important debugging information in the return value. They are displayed as a list, not in a terminal.
    - Errors are caught and reported. Include any useful debugging information in the thrown error. No need to catch and log errors specifically.

## Examples

<example>
<user>What is 5 + 3?</user>
<code>return 5 + 3</code>
<rationale>Simple calculation example showing basic JavaScript execution</rationale>
</example>

<example>
<user>Please replace every 'a' with a 'b' in /path/to/file.txt</user>
<code>
async function main() {
     const fs = require('node:fs');
     const content = await fs.readFile('/path/to/file.txt', 'utf8');
     const modifiedContent = content.replaceAll('a', 'b');
     await fs.writeFile('/path/to/file.txt', modifiedContent, 'utf8');
}
return main()
</code>
<rationale>It is much more efficient to write a small script to apply large scale edits than it is to make those edits individually.</rationale>
<rationale>The promise returned by main is awaited before returning.</rationale>
</example>

<example>
<user>What are the unique values of "username" found in actions.csv?</user>
<code>
const csvContent = fs.readFileSync('./actions.csv', 'utf8');

 // Split into lines and remove empty lines
 const lines = csvContent.split('\\n').filter(line => line.trim());
 if (lines.length === 0) {
     return [];
 }

 // Parse header to find username column index
 const headers = lines[0].split(',').map(h => h.trim().toLowerCase());
 const usernameIndex = headers.findIndex(h => h === 'username' || h === 'user' || h === 'user_name');
 if (usernameIndex === -1) {
     throw new Error('Username column not found. Expected columns: username, user, or user_name');
 }

 const usernames = new Set();
 for (let i = 1; i < lines.length; i++) {
     const columns = lines[i].split(',');
     if (columns.length > usernameIndex) {
         const username = columns[usernameIndex].trim().replace(/^["']|["']$/g, '');
         if (username) {
             usernames.add(username);
         }
     }
 }
 return Array.from(usernames).sort();
</code>
<rationale>Do not attempt to read large files like CSVs directly into your context window. Instead, prefer to pre-process them with javascript.</rationale>
</example>

<example>
<user>Use github_pr_review.js to review https://github.com/sourcegraph/amp/pull/501</user>
<codePath>github_pr_review.js</codePath>
<rationale>When running a script already written to disk, use the codePath parameter to specify the path to the script.</rationale>
</example>