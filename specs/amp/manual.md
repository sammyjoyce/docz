## Congratulations on installing Amp. This manual helps you get the most out of it.

## Introduction

### What is Amp?

Amp is an agentic coding tool built by [Sourcegraph](https://sourcegraph.com/). It runs in [VS Code](https://marketplace.visualstudio.com/items?itemName=sourcegraph.amp) (and compatible forks like Cursor, Windsurf, and VSCodium) and as a [command-line tool](https://www.npmjs.com/package/@sourcegraph/amp). It's also multiplayer — you can share threads and collaborate with your team.

### Principles

1. Amp is unconstrained in token usage (and therefore cost). Our sole incentive is to make it valuable, not to match the cost of a subscription.
2. No model selector, always the best models. You don't pick models, we do. Instead of offering selectors and checkboxes and building for the lowest common denominator, Amp is built to use the full capabilities of the best models.
3. We assume that you want to access the raw power these models have to offer. In a sense, when you're using Amp, you aren't using Amp — you're talking directly to a model and Amp is the shell around your conversation with the model.
4. Built to evolve. Products that lock themselves into specific model behaviors become obsolete in months. We stay current with the best, not tied to the past.

## Getting Started

### Install

Sign in to [ampcode.com](https://ampcode.com/settings) and follow the instructions for VS Code, Cursor, and Windsurf to install the extension and authenticate. You can also use the Install button at the bottom of the Amp dashboard for quick access to installation instructions for all platforms.

### Command Line Interface

Install globally:

```
npm install -g @sourcegraph/amp
```

Run interactively (will prompt for login on first run):

```
amp
```

You can start a new interactive thread by sending command output via stdin:

```
echo "What is today's date?" | amp
```

Run in non-interactive mode:

```
echo 'what animal is the most disagreeable because it says neigh?' > riddle.txt
cat riddle.txt | amp -x "solve this riddle"
```

For non-interactive environments (e.g. scripts, CI/CD pipelines), you'll need to export your [API key](https://ampcode.com/settings) as an environment variable:

```
export AMP_API_KEY=your-api-key-here
```

## Using Amp

### How to Prompt

Amp currently uses Claude Sonnet 4 for most tasks, with up to 432,000 tokens of context. For the best results, follow these guidelines:

- Be explicit with what you want. Instead of "can you do X?", try "do X."
- Keep it short, keep it focused. Break very large tasks up into smaller sub-tasks, one per thread. Do not ask the agent to write database migrations in the same thread as it previously changed CSS for a documentation page.
- Don't try to make the model guess. If you know something about how to achieve what you want the agent to do — which files to look at, which commands to run — put it in your prompt.
- If you want the model to not write any code, but only to research and plan, say so: "Only plan how to implement this. Do NOT write any code."
- Use [`AGENTS.md` files](https://ampcode.com/#AGENTS.md) to guide Amp on how to run your tests and build steps and to avoid common mistakes.
- Abandon threads if they accumulated too much noise. Sometimes things go wrong and failed attempts with error messages clutter up the context window. In those cases, it's often best to start with a new thread and a clean context window.
- Tell the agent how to best review its work: what command or test to run, what URL to open, which logs to read. Feedback helps agents as much as it helps us.

The first prompt in the thread carries a lot of weight. It sets the direction for the rest of the conversation. We encourage you to be deliberate with it. That's why we use Cmd/Ctrl+Enter to submit a message in Amp — it's a reminder to put effort into a prompt.

Here are some examples of prompts we've used with Amp:

- "Make `observeThreadGuidanceFiles` return `Omit<ResolvedGuidanceFile, 'content'>[]` and remove that field from its return value, and update the tests. Note that it is omitted because this is used in places that do not need the file contents, and this saves on data transferred over the view API." ([See Thread](https://ampcode.com/threads/T-9219191b-346b-418a-b521-7dc54fcf7f56))
- "Run `<build command>` and fix all the errors"
- "Look at `<local development server url>` to see this UI component. Then change it so that it looks more minimal. Frequently check your work by screenshotting the URL"
- "Run git blame on the file I have open and figure out who added that new title"
- "Convert these 5 files to use Tailwind, use one subagent per file"
- "Take a look at `git diff` — someone helped me build a debug tool to edit a Thread directly in JSON. Please analyze the code and see how it works and how it can be improved. \[…\]" ([See Thread](https://ampcode.com/threads/T-39dc399d-08cc-4b10-ab17-e6bac8badea7))
- "Check `git diff --staged` and remove the debug statements someone added" ([See Thread](https://ampcode.com/threads/T-66beb0de-7f02-4241-a25e-50c0dc811788))
- "Find the commit that added this using git log, look at the whole commit, then help me change this feature"
- "Explain the relationship between class AutoScroller and ViewUpdater using a diagram"
- "Run `psql` and rewire all the `threads` in the databaser to my user (email starts with thorsten)" ([See Thread](https://ampcode.com/threads/T-f810ef79-ba0e-4338-87c6-dbbb9085400a))

Also see Thorsten Ball's [How I Use Amp](https://ampcode.com/how-i-use-amp).

If you're in a workspace, use Amp's [thread sharing](https://ampcode.com/#workspaces) to learn from each other.

### AGENTS.md

Amp looks in `AGENTS.md` files for guidance on codebase structure, build/test commands, and conventions.

| File | Examples |
| --- | --- |
| `AGENTS.md`   in cwd, parent dirs, & subtrees | Architecture, build/test commands, overview of internal APIs, review and release steps |
| `$HOME/.config/AGENTS.md` | Personal preferences, device-specific commands, and guidance that you're testing locally before committing to your repository |

Amp includes `AGENTS.md` files automatically:

- `AGENTS.md` files in the current working directory (or editor workspace roots) *and* parent directories (up to `$HOME`) are always included.
- Subtree `AGENTS.md` files are included when the agent reads a file in the subtree.
- `$HOME/.config/AGENTS.md` is always included.

If a file named `AGENT.md` (without an `S`) exists in any of those locations, and no `AGENTS.md` exists, the `AGENT.md` file will be used for backward compatibility.

In a large repository with multiple subprojects, we recommend keeping the top-level `AGENTS.md` general and creating more specific `AGENTS.md` files in subtrees for each subproject.

To see the agent files that Amp is using in the editor extension, hover the X% of 168k indicator in the reply area after you've sent the first message in a thread.

#### Writing AGENTS.md Files

Amp offers to generate an `AGENTS.md` file for you if none exists. You can create or update any `AGENTS.md` files manually or by asking Amp (*"Update AGENTS.md based on what I told you in this thread"*).

To include other files as context, @-mention them in agent files. For example:

```
See @doc/style.md and @rules/internal-api-conventions.md.

When making commits, see @doc/git-commit-instructions.md.
```
- Relative paths are interpreted relative to the agent file containing the mention.
- Absolute paths and `@~/some/path` are also supported.
- @-mentions in code blocks are ignored, to avoid false positives.
- Globs are not supported.

#### Migrating to AGENTS.md

- From Claude Code: `mv CLAUDE.md AGENTS.md && ln -s AGENTS.md CLAUDE.md`, and repeat for subtree `CLAUDE.md` files
- From Cursor: `mv .cursorrules AGENTS.md && ln -s AGENTS.md .cursorrules` and then add @-mentions of each `.cursor/rules/*.mdc` file to `AGENTS.md`. (Amp does not yet support [selective inclusion of Cursor rules](https://docs.cursor.com/context/rules#rule-type).)
- From existing AGENT.md: `mv AGENT.md AGENTS.md` (optional - both filenames continue to work)

Amp supports image uploads, allowing you to share screenshots, diagrams, and visual references with the AI. Images can provide important context for debugging visual issues or understanding UI layouts.

**In the editor extension**, you can:

- Paste images directly into the input
- Hold Shift and drag images over the input
- Mention images by file path

**In the CLI**, you can:

- Drag images into the terminal (and paste them if the image is copied from a file)
- Mention images by file path

### Thinking Hard

If Extended Thinking is enabled (it is by default), Amp can dynamically adjust the thinking budget given to Claude Sonnet 4. The higher the budget, the more tokens it uses to "think".

If you tell the model to "think hard" (or "think a lot" and variations) the thinking budget will be more than doubled.

If you tell the model to "think really hard" (or "think very hard") it will be increased even more.

### Mentioning Files

You can mention files directly in your prompts by typing @ followed by a pattern to fuzzy-search. It can help speed up responses by avoiding the need to search the codebase.

### Queueing messages

You can queue messages to be sent to the agent once it ends its turn.

That way you can already send a message to, for example, ask the agent to perform a follow-up task without interrupting what it's currently doing.

**In the editor extension**:

- Press Cmd-Shift-Enter (macOS) or Ctrl-Shift-Enter (Windows/Linux) to queue your input instead of sending it.
- Queued messages appear below the thread. Click a queued message to restore it to the editor, or use the × button to remove it.
- Up to 5 messages can be queued per thread.

**In the CLI**, you can use the `/queue [message]` command to enqueue a message and `/dequeue` to dequeue all enqueued messages.

### CLI

After [installing](https://ampcode.com/#getting-started-command-line-interface) and logging in, run `amp` to start the Amp CLI.

Without any arguments, it runs in interactive mode:

```
$ amp
```

If you pipe input to the CLI, it uses the input as the first user message in interactive mode:

```
$ echo "commit all my changes" | amp
```

Use `-x` or `--execute` to start the CLI in execute mode. In this mode, it sends the message provided to `-x` to the agent, waits until the agent ended its turn, prints its final message, and exits:

```
$ amp -x "what files in this folder are markdown files? Print only the filenames."
README.md
AGENTS.md
```

You can also pipe input when using `-x`:

```
$ echo "what package manager is used here?" | amp -x
cargo
```

If you want to use `-x` with the agent using tools that might require approval, make sure to either use `--dangerously-allow-all` or [configure Amp to allow them](https://ampcode.com/#permissions):

```
$ amp --dangerously-allow-all -x "Run \`sed\` to replace 2024 with 2025 in README."
Done. Replaced 8 occurrences of 2024 in README.md
```

Execute mode is automatically turned on when you redirect stdout:

```
$ echo "what is 2+2?" | amp > response.txt
```

When you pipe input and provide a prompt with `-x`, the agent can see both:

```
$ cat ~/.vimrc | amp -x "which colorscheme is used?"
The colorscheme used is **gruvbox** with dark background and hard contrast.

\`\`\`vim
set background=dark
let g:gruvbox_contrast_dark = "hard"
colorscheme gruvbox
\`\`\`
```

You can use the `--mcp-config` flag with `-x` commands to specify an MCP server without modifying your configuration file.

```
$ amp --mcp-config '{"everything": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-everything"]}}' -x "What tools are available to you?"
```

To see more of what the CLI can do, run `amp --help`.

#### Slash Commands

The Amp CLI supports slash commands. Type `/` followed by the name of a command to execute it.

- `/help` - Show help and hotkeys
- `/new` - Start a new thread
- `/continue` - Continue an existing thread
- `/queue [message]` - Queue a message to send when inference completes
- `/dequeue` - Dequeue all messages and restore them to the prompt editor
- `/agent` - Generate an AGENTS.md file in the current workspace
- `/compact` - Compact the thread to reduce context usage
- `/editor` - Open your $EDITOR to write a prompt
- `/permissions` - Edit permission rules in $EDITOR
- `/quit` - Exit Amp

#### Shell Mode

Execute shell commands directly in the CLI by starting your message with `$`. The command and its output will be included in the context window for the next message to the agent.

Use `$$` to activate incognito shell mode, where commands execute but aren't included in the context. This is useful for noisy commands or quick checks you'd normally run in a separate terminal.

#### Writing Prompts in the CLI

In modern terminal emulators, such as Ghostty, Wezterm, Kitty, or iTerm2, you can use shift-enter to insert a newline in your prompts.

Additionally you can also use type `\` followed by return to insert a newline.

If you have the environment variable `$EDITOR` set, you can use the `/editor` slash command to open your editor to write a prompt.

### Keyboard Shortcuts

Operating System

Editor

| Command | Shortcut |
| --- | --- |
| New Thread | Cmd L |
| Focus/Hide Amp Sidebar | Cmd I |
| Switch to Thread | Cmd K |
| Go to Next Thread | Cmd Shift\] |
| Go to Previous Thread | Cmd Shift \[ |

### Customize Layout in Cursor

Third party extensions are automatically placed in the primary sidebar in Cursor. To customize the position of Amp in Cursor please follow these steps:

- Open the Command Pallete using `Ctrl/⌘ + Shift + P`
- Search for `View: Move View`
- Select `Amp` from the drop down list
- Choose your desired location (`New Panel Entry` and `New Secondary Side Bar Entry` are the most common)

## Threads

Threads are conversations with the agent, containing all your messages, context, and tool calls. Your threads are synced to ampcode.com. If you're in a workspace, your threads are also shared with your workspace by default, just like Git branches on a shared remote repository.

Including links to Amp threads with your changes when submitting for code review helps provide context. Reading and searching your workspace's threads can help you see what's going on and how other people are using Amp.

### Privacy & Permissions

Threads can be public (visible to anyone on the internet with the link), workspace-shared (visible to your workspace members), or private (visible only to you).

If you're in a workspace, your threads are [shared by default](https://ampcode.com/#workspaces) with your workspace members.

If you are not in a workspace, your threads are only visible to you by default.

You can change a thread's visibility at any time through the sharing menu at the top of the thread.

### Managing Context

As you work with Amp, your thread accumulates context within the model's context window. Amp shows your context window usage and warns when approaching limits.

When approaching the thread context limit, you can hover over the context window indicator and use the following:

- Compact Thread — Summarizes the existing conversation to reduce context usage while preserving important information
- New Thread with Summary — Creates a new thread that starts with a summary of the current conversation

### File Changes

Amp tracks changes that the agent makes to files during your conversation, which you can track and revert:

- Hover over the files changed indicator (located just above the message input) to see which files were modified and by how much
- Revert individual file changes, or all changes made by the agent

Editing a message in a thread automatically reverts any changes the agent made after that message

## Amp Tab

Amp Tab is our in-editor completion engine, designed to anticipate your next actions and reduce the time spent manually writing code.

It uses a custom model that was trained to understand what you are trying to do next, based on your recent changes, your language server's diagnostics, and what we call semantic context.

Amp Tab can suggest regular single or multi-line edits to change entire code blocks, next to your cursor, further away in the document or even in other files.

### Enabling

Enable Amp Tab by setting `"amp.tab.enabled": true` in your editor settings.

### How to Use

- Begin typing in your editor. Amp Tab automatically presents relevant suggestions.
- Press the Tab key to accept and apply the suggested edits.
- Press the Tab key again to instantly jump to additional edits further from your cursor.
- If you get a suggestion to jump to another file, press the Tab key to preview the file and then press Tab again to jump to it.
- To ignore suggestions, simply continue typing or press Esc.

If you're using Vim extensions in VS Code and need to press Esc twice to dismiss suggestions and enter normal mode, configure `amp.tab.dismissCommandIds` to specify which commands should run on Esc. Defaults cover popular extensions like VSCodeVim and vscode-neovim.

Currently, Amp Tab is free to use as a research preview for all Amp users.

## Workspaces

Workspaces provide collaborative environments where knowledge can be shared across your organization. Create a workspace from the [settings page](https://ampcode.com/settings).

To join a workspace, you need an invitation from an existing workspace member. [Enterprise](https://ampcode.com/#enterprise) workspaces can also enable SSO to automatically include workspace members.

### Sharing

Workspace threads are visible to all workspace members by default, making it easy to learn from others and build on their work.

See [Privacy & Permissions](https://ampcode.com/#privacy-and-permissions) for all thread visibility options. Note that [Enterprise](https://ampcode.com/#enterprise) workspaces can disable public thread sharing in the workspace settings page.

### Workspace Usage

Workspaces provide pooled billing of usage, making it easier to manage costs across your organization. If a member of your workspace joins with free personal usage available, their free usage will be used before the paid workspace usage.

To learn more, refer to the [pricing](https://ampcode.com/#pricing) section.

### Leaderboard

Each workspace includes a leaderboard that tracks thread activity and contributions from workspace members, encouraging engagement and highlighting active participants.

## Tools

Tools are what the underlying model uses to assist with tasks. For the highest quality results we recommend you use a curated set of tools, with prompts adjusted to fit the underlying model.

### Built-in Tools

Amp comes with a curated set of built-in tools specifically designed for coding. You can find the list of built-in tools inside Amp's extension settings.

### Custom Tools (MCP)

You can add additional tools using [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) servers, which can be either local or remote. These can be configured in `amp.mcpServers` in your [configuration file](https://ampcode.com/#configuration). You can also press \+ Add MCP Server under Settings.

Configuration options for local (STDIO) MCP servers:

- `command` - executable
- `args` - command arguments (optional)
- `env` - environment variables (optional)

Configuration options for remote (Streamble/SSE) MCP servers:

- `url` - server endpoint

If the remote MCP server requires authorization with OAuth, you can use [`mcp-remote`](https://www.npmjs.com/package/mcp-remote).

Example configuration:

```json
"amp.mcpServers": {
    "playwright": {
        "command": "npx",
        "args": ["-y", "@playwright/mcp@latest", "--headless", "--isolated"]
    },
    "semgrep": {
        "url": "https://mcp.semgrep.ai/mcp"
    },
    "linear": {
        "command": "npx",
        "args": [
            "mcp-remote",
            "https://mcp.linear.app/sse"
        ]
    }
}
```

Too many available tools can reduce model performance, so for best results, be selective:

- Use MCP servers that expose a small number of high-level tools with high-quality descriptions.
- Disable MCP tools that you aren't using, by hovering over a tool name in the extension's Settings interface and clicking so it's shown as ~~tool\_name~~, or by adding them to `amp.tools.disable` in your [configuration file](https://ampcode.com/#configuration).
- Consider using CLI tools instead of MCP servers.

Amp also supports MCP [prompts](https://modelcontextprotocol.io/specification/2025-06-18/server/prompts) and [resources](https://modelcontextprotocol.io/specification/2025-06-18/server/resources), both available under the `@` mentions menu.

### Toolboxes

Toolboxes allow you to extend Amp with simple scripts instead of needing to provide an MCP server.

When Amp starts it invokes each executable in the directory indicated by `AMP_TOOLBOX`, with the environment variable `TOOLBOX_ACTION` set to `describe`.

The tool is expected to write its description to `stdout` as a list of key-value pairs, one per line.

```javascript
#!/usr/bin/env bun

const action = process.env.TOOLBOX_ACTION

if (action === 'describe') showDescription()
else if (action === 'execute') runTests()

function showDescription() {
    process.stdout.write(
        [
            'name: run-tests',
            'description: use this tool instead of Bash to run tests in a workspace',
            'dir: string the workspace directory',
        ].join('\n'),
    )
}
```

When Amp decides to use your tool it runs the executable again, setting `TOOLBOX_ACTION` to `execute`.

The tool receives parameters in the same format on `stdin` and then performs its work:

```javascript
function runTests() {
    let dir = require('fs')
        .readFileSync(0, 'utf-8')
        .split('\n')
        .filter((line) => line.startsWith('dir: '))

    dir = dir.length > 0 ? dir[0].replace('dir: ', '') : '.'

    require('child_process').spawnSync('pnpm', ['-C', dir, 'run', 'test', '--no-color', '--run'], {
        stdio: 'inherit',
    })
}
```

If your tool needs object or array parameters, the executable can write its [tool schema](https://modelcontextprotocol.io/specification/2025-06-18/server/tools#tool) as JSON instead to `stdout`. In this case it'll also receive inputs as JSON.

We recommend using tools to express specific, deterministic and project-local behavior, like:

- querying a development database,
- running test and build actions in the project,
- exposing CLIs tools in a controlled manner.

### Permissions

Before invoking a tool, Amp checks the user's list of permissions for the first matching entry to decide whether to run the tool.

If no match is found, Amp scans through its built-in permission list, rejecting the tool use in case no match is found there either.

The matched entry tells Amp to either *allow* the tool use without asking, *reject* the tool use outright, *ask* the operator, or *delegate* the decision to another program.

Permissions are configured in your [configuration file](https://ampcode.com/#configuration) under the entry `amp.permissions`:

```json
"amp.permissions": [
  // Ask before running command line containing git commit
  { "tool": "Bash", "matches": { "cmd": "*git commit*" }, "action": "ask"},
  // Reject command line containing python or python3
  { "tool": "Bash", "matches": { "cmd": ["*python *", "*python3 *"] }, "action": "reject"},
  // Allow all playwright MCP tools
  { "tool": "mcp__playwright_*", "action": "allow"},
  // Ask before running any other MCP tool
  { "tool": "mcp__*", "action": "ask"},
  // Delegate everything else to a permission helper (must be on $PATH)
  { "tool": "*", "action": "delegate", "to": "my-permission-helper"}
]
```

#### Using in VS Code

Complex objects must be configured in VS Code's Settings JSON.

A JSON schema for permissions is integrated into VS Code to offer guidance when editing permissions.

Rules with action `ask` only work for the `Bash` tool in VS Code.

#### Using in the CLI

Using `amp permissions edit` you can edit your permissions rules programmatically and interactively using `$EDITOR`.

The `amp permissions test` command evaluates permission rules without actually running any tools, providing a safe way for verifying that your rules work as intended.

```bash
$ amp permissions edit <<'EOF'
allow Bash --cmd 'git status' --cmd 'git diff*'
ask Bash --cmd '*'
EOF
$ amp permission test Bash --cmd 'git diff --name-only'
tool: Bash
arguments: {"cmd":"git diff --name-only"}
action: allow
matched-rule: 0
source: user
$ amp permission test Bash --cmd 'git push'
tool: Bash
arguments: {"cmd":"push"}
action: ask
matched-rule: 1
source: user
```

Running `amp permissions list` displays known permissions rules in the same format understood by `amp permissions edit`:

```bash
$ amp permissions list
allow Bash --cmd 'git status' --cmd 'git diff*'
ask Bash --cmd '*'
```

Refer to the output of `amp permissions --help` for the full set of available operations.

#### Delegating the decision to an external program

For full control, you can tell Amp to consult another program before invoking a tool:

```json
{ "action": "delegate", "to": "amp-permission-helper", "tool": "Bash" }
```

Now every time Amp wants to run a shell command, it will invoke `amp-permission-helper`:

```python
#!/usr/bin/env python3
import json, sys, os

tool_name = os.environ.get("AGENT_TOOL_NAME")
tool_arguments = json.loads(sys.stdin.read())

# allow all other tools
if tool_name != "Bash":
    sys.exit(0)

# reject git push outright - stderr is passed to the model
if 'git push' in tool_arguments.get('cmd', ''):
    print("Output the correct command line for pushing changes instead", file=sys.stderr)
    sys.exit(2)

# ask in any other case
sys.exit(1)
```

The error code and stderr are used to tell Amp how to proceed.

See the [Appendix](https://ampcode.com/manual/appendix#permissions-reference) for the full technical reference.

### Subagents

Amp can spawn subagents (via the Task tool) for complex tasks that benefit from independent execution. Each subagent has its own context window and access to tools like file editing and terminal commands.

Subagents are most useful for multi-step tasks that can be broken into independent parts, operations producing extensive output not needed after completion, parallel work across different code areas, and keeping the main thread's context clean while coordinating complex work.

However, subagents work in isolation — they can't communicate with each other, you can't guide them mid-task, they start fresh without your conversation's accumulated context, and the main agent only receives their final summary rather than monitoring their step-by-step work.

Amp may use subagents automatically for suitable tasks, or you can encourage their use by mentioning subagents or suggesting parallel work.

### Oracle

Amp has access to a more powerful model that's better suited for complex reasoning or analysis tasks, at the cost of being slightly slower, slightly more expensive, and less suited to day-to-day code editing tasks than the main agent's model. Currently that more powerful model is OpenAI's o3.

This model is available to Amp's main agent through a tool called `oracle`.

The main agent can autonomously decide to ask the oracle for help when debugging or reviewing a complex piece of code. We consciously haven't pushed the main agent to constantly use the more powerful model yet, due to higher costs and slower inference speed.

We recommend explicitly asking Amp's main agent to use the oracle when you think it will be helpful. Here are some examples from our own usage of Amp:

- "Use the oracle to review the last commit's changes. I want to make sure that the actual logic for when an idle or requires-user-input notification sound plays has not changed."
- "Ask the oracle whether there isn't a better solution."
- "I have a bug in these files: … It shows up when I run this command: … Help me fix this bug. Use the oracle as much as possible, since it's smart."
- "Analyze how the functions `foobar` and `barfoo` are used. Then I want you to work a lot with the oracle to figure out how we can refactor the duplication between them while keeping changes backwards compatible."

### JetBrains

After upgrading the Amp CLI to the latest version, execute `amp --jetbrains` in the root of your JetBrains project. Upon restarting your IDE, you can launch Amp by clicking on the Amp logo in your JetBrains toolbar, or by going to Tools > Start Amp. The `--jetbrains` flag is active by default in the IDE terminal.

This integration supports:

- All JetBrains IDEs (IntelliJ, WebStorm, GoLand, etc.)
- Message Context — Amp includes the current file and selection in every message.
- JetBrains diagnostics for build errors and code insights.
- Soon: File Edits — Amp edits files through the IDE so you can undo changes inside the editor.

Requirements:

- Node.js 21+

## Configuration Settings

Amp can be configured through settings in your editor extension (e.g. `.vscode/settings.json`) and the CLI configuration file.

The CLI configuration file location varies by operating system:

- Windows: `%APPDATA%\amp\settings.json`
- macOS: `~/.config/amp/settings.json`
- Linux: `~/.config/amp/settings.json`

All settings use the `amp.` prefix.

### Settings

#### Editor Extension and CLI

- **`amp.anthropic.thinking.enabled`**
	**Type:**`boolean`, **Default:**`true`
	Enable Claude's extended thinking capabilities
- **`amp.permissions`**
	**Type:**`array`, **Default:**`[]`
	Configures which tool uses are allowed, rejected or ask for approval. See [Permissions](https://ampcode.com/#permissions).
- **`amp.git.commit.ampThread.enabled`**
	**Type:**`boolean`, **Default:**`true`
	Enable adding Amp-Thread trailer in git commits. When disabled, commits made with the commit tool will not include the `Amp-Thread: <thread-url>` trailer.
- **`amp.git.commit.coauthor.enabled`**
	**Type:**`boolean`, **Default:**`true`
	Enable adding Amp as co-author in git commits. When disabled, commits made with the commit tool will not include the `Co-authored-by: Amp <amp@ampcode.com>` trailer.
- **`amp.mcpServers`**
	**Type:**`object`
	Model Context Protocol servers that expose tools. See [Custom Tools (MCP) documentation](https://ampcode.com/#mcp).
- **`amp.terminal.commands.nodeSpawn.loadProfile`**
	**Type:**`string`, **Default:**`"always"`, **Options:**`"always"` | `"never"` | `"daily"`
	Before running commands (including MCP servers), whether to load environment variables from the user's profile (`.bashrc`, `.zshrc`, `.envrc`) as visible from the workspace root directory
- **`amp.todos.enabled`**
	**Type:**`boolean`, **Default:**`true`
	Enable TODOs tracking for managing tasks
- **`amp.tools.disable`**
	**Type:**`array`, **Default:**`[]`
	Disable specific tools by name. Use 'builtin:toolname' to disable only the builtin tool with that name (allowing an MCP server to provide a tool by that name). Glob patterns using `*` are supported.
- **`amp.tools.stopTimeout`**
	**Type:**`number`, **Default:**`300`
	How many seconds to wait before canceling a running tool

#### Editor Extension Only

- **`amp.debugLogs`**
	**Type:**`boolean`, **Default:**`false`
	Enable debug logging in the Amp output channel
- **`amp.notifications.enabled`**
	**Type:**`boolean`, **Default:**`true`
	Play notification sound when done or blocked
- **`amp.notifications.system.enabled`**
	**Type:**`boolean`, **Default:**`true`
	Show system notifications when CLI terminal is not focused
- **`amp.tab.enabled`**
	**Type:**`boolean`, **Default:**`false`
	Enable Amp Tab completion engine
- **`amp.terminal.commands.hide`**
	**Type:**`boolean`, **Default:**`true`
	Whether to hide the integrated VS Code terminal by default when starting commands
- **`amp.ui.zoomLevel`**
	**Type:**`number`, **Default:**`1`
	Zoom level for the Amp user interface

### Proxies and Certificates

When using the Amp CLI in corporate networks with proxy servers or custom certificates, set these standard Node.js environment variables in your shell profile or CI environment as needed:

```
export HTTP_PROXY=your-proxy-url
export HTTPS_PROXY=your-proxy-url
export NODE_EXTRA_CA_CERTS=/path/to/your/certificates.pem
```