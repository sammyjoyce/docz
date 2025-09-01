## 0) Preconditions

* You already have `access_token` (and can refresh it).
* For API calls, **use Bearer auth** (not `x-api-key`) and always send `anthropic-version: 2023-06-01`. ([Anthropic][1])
* In some OAuth integrations, requests also require a beta header (observed):
  `anthropic-beta: oauth-2025-04-20`. Treat this as **implementation‑dependent** until GA. ([GitHub][2], [Gist][3], [Reddit][4])

---

## 1) Endpoint & Required Headers

* **Endpoint:** `POST https://api.anthropic.com/v1/messages` ([Anthropic][1])
* **Headers (minimum):**

  * `Authorization: Bearer <ACCESS_TOKEN>` (**OAuth path**)
  * `anthropic-version: 2023-06-01`
  * `Content-Type: application/json`
  * Optional/feature headers: `anthropic-beta: <one-or-more beta names>` (comma‑separated) for features like interleaved thinking, fine‑grained tool streaming, files API, MCP connector, web search tool. ([Anthropic][5])

**cURL (non‑streaming)**

```bash
curl -sS https://api.anthropic.com/v1/messages \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 512,
    "messages": [{"role": "user", "content": "Hello, Claude"}]
  }'
```

---

## 2) Request Schema (top‑level)

* **`model`** *(string, required)* — e.g. `claude-sonnet-4-20250514`. See Models doc for valid IDs. ([Anthropic][1])
* **`max_tokens`** *(int, required)* — absolute generation cap. ([Anthropic][1])
* **`messages`** *(array, required)* — alternating turns of `{ role: "user" | "assistant", content: ... }`. Consecutive same roles are merged. ([Anthropic][1])
* **`system`** *(string | content blocks, optional)* — global instructions; note there is **no `system` role** inside `messages`. ([Anthropic][1])
  - **Required in this project:** Prepend the contents of `prompt/anthropic_spoof.txt` to the system prompt for **all** Anthropic Messages API requests. If you have your own system text, concatenate as: `"<contents of prompt/anthropic_spoof.txt>\n\n<your system text>"`. Do **not** add a `system` field solely to send the spoof text; if you would otherwise omit `system`, omit it and do not send the spoof text by itself. Keep the source of truth in `prompt/anthropic_spoof.txt` — do not inline or duplicate it in code.
* **`stream`** *(bool)* — SSE streaming; see §3. ([Anthropic][6])
* **Generation controls:** `temperature`, `top_p`, `stop_sequences`, `service_tier`, `metadata.user_id`. ([Anthropic][1])
* **Tools:** `tools` (client/server), `tool_choice`. See §4. ([Anthropic][7])
* **Extended thinking:** `thinking: { type: "enabled", budget_tokens: N }` (Claude 4 family). See §5. ([Anthropic][8])
* **MCP:** `mcp_servers` for connecting remote MCP servers (beta). ([Anthropic][9])

**Message `content` forms**

* `string` shorthand → `[{ "type": "text", "text": "..." }]`.
* Or an **array of blocks**: `text`, `image`, `tool_result`, (docs also cover PDFs and custom/file‑based documents), etc. ([Anthropic][1])

---

## 3) Streaming (SSE)

* Set `"stream": true`. You’ll receive named SSE events in this order:
  `message_start` → repeated `content_block_start`/`content_block_delta`/`content_block_stop` → `message_delta` → `message_stop` (plus `ping` and error events). ([Anthropic][6])
* **Tool input deltas** arrive as **partial JSON strings** (`input_json_delta`); accumulate until `content_block_stop`, then parse. ([Anthropic][6])

**cURL (SSE)**

```bash
curl -NsS https://api.anthropic.com/v1/messages \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 256,
    "stream": true,
    "messages": [{"role": "user", "content": "Stream a short reply"}],
    "system": "<contents of prompt/anthropic_spoof.txt>\n\nUse short sentences."
  }'
```

(Your HTTP client should consume SSE events; do not assume a single JSON object.) ([Anthropic][6])

---

## 4) Tool Use

* Define tools with **`name`**, **`description`**, and **`input_schema`** (JSON Schema). Provide them via `tools: [...]`. ([Anthropic][1])
* When Claude decides to use a tool, response includes a `tool_use` block; `stop_reason` may be `"tool_use"`. You then execute the tool and return a new **`user`** message containing a **`tool_result`** block referencing `tool_use_id`. ([Anthropic][7])
* Parallel tool calls are supported; you can disable with `tool_choice.disable_parallel_tool_use: true`. ([Anthropic][7])
* **Fine‑grained tool streaming** (parameters streamed as deltas) is available under a beta header. ([Anthropic][8])

**Client‑tool example (non‑streaming)**

```bash
curl -sS https://api.anthropic.com/v1/messages \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 512,
    "tools": [{
      "name": "get_weather",
      "description": "Get current weather",
      "input_schema": {
        "type": "object",
        "properties": {"location": {"type": "string"}},
        "required": ["location"]
      }
    }],
    "messages": [{"role":"user","content":"Weather in SF?"}]
  }'
```

Follow with a new `user` message that includes a `tool_result` block after you run the tool. ([Anthropic][7])

**Server tools** (e.g., web search) are declared similarly but run on Anthropic’s side; results are incorporated automatically. ([Anthropic][6])

---

## 5) Extended Thinking (Claude 4 family)

* Enable via `thinking: { "type": "enabled", "budget_tokens": 1024+ }`.
* Responses include **`thinking` blocks** (summarized by default in Claude 4) followed by normal `text` content; `thinking` streaming uses `thinking_delta` and a final `signature_delta`. ([Anthropic][6])
* **Interleaved thinking** (mixing tool use and thinking) is beta‑gated. ([Anthropic][8])

---

## 6) Images, PDFs, Files

* Provide images as:

  * `{"type":"image","source":{"type":"base64","media_type":"image/png","data":"..."}}`, or
  * `{"type":"image","source":{"type":"url","url":"https://..."}}`, or
  * Via **Files API** `file_id`. ([Anthropic][10])
* **Files API**: upload/list/delete requires `anthropic-beta: files-api-2025-04-14`. After upload, you can reference `file_id` in `messages` without re‑uploading. ([Anthropic][11])

---

## 7) MCP Connector (optional)

* Use `mcp_servers` to connect Claude to remote MCP servers directly from the Messages API. Requires beta header `mcp-client-2025-04-04`. ([Anthropic][9])

---

## 8) Errors, Limits, and Rate Limits

* **HTTP errors:** `400 invalid_request_error`, `401 authentication_error`, `403 permission_error`, `404 not_found_error`, `413 request_too_large`, `429 rate_limit_error`, `500 api_error`, `529 overloaded_error`. Responses include `request_id`. ([Anthropic][12])
* **Request size:** **32 MB** (Messages). Long calls should stream or use Message Batches. ([Anthropic][12])
* **Rate‑limit headers:** e.g., `anthropic-ratelimit-requests-remaining`, `-tokens-remaining`, with RFC 3339 `-reset` times; use `retry-after` on 429. ([Anthropic][13])

---

## 9) Streaming vs Non‑Streaming Guidance

* Prefer **SSE** for long‑running requests and tool use so you don’t hit network idle timeouts; accumulate deltas as documented. ([Anthropic][6])

---

## 10) Common Pitfalls

* **Missing `anthropic-version`** header → 400. ([Anthropic][14])
* Sending **`x-api-key` with OAuth** → 401/permission issues. Use **only** `Authorization: Bearer ...`. (Docs show `x-api-key` for API keys; OAuth integrations replace it with Bearer.) ([Anthropic][1])
* **Partial tool JSON** in streaming: parse only after `content_block_stop`. ([Anthropic][6])
* **System prompt location:** must be top‑level `system`, not a `system` role inside `messages`. ([Anthropic][1])

---

## 11) End‑to‑End Examples

**A) Simple call (Bearer, no tools)**

```bash
curl -sS https://api.anthropic.com/v1/messages \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 256,
    "messages": [{"role":"user","content":"Summarize OAuth vs API key in 3 bullets."}]
  }'
```

**A1) With system prompt**

```bash
curl -sS https://api.anthropic.com/v1/messages \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 256,
    "messages": [{"role":"user","content":"Summarize OAuth vs API key in 3 bullets."}],
    "system": "<contents of prompt/anthropic_spoof.txt>\n\nBe concise."
  }'
```

**B) Tool use (2‑turn pattern)**

1. Get `tool_use`: send tool definitions + user prompt.
2. Execute tool(s), then post `tool_result` in a new **user** turn. ([Anthropic][7])

**C) Extended thinking + streaming**
Add:

```json
"thinking": {"type": "enabled", "budget_tokens": 4096},
"stream": true
```

Handle `thinking_delta` + `signature_delta` in the SSE stream. ([Anthropic][6])

**D) Vision input (URL)**
Inside a `user` message `content`:

```json
[
  {"type":"text","text":"Describe this image"},
  {"type":"image","source":{"type":"url","url":"https://example.com/image.jpg"}}
]
```

([Anthropic][10])

---

## 12) Operational Notes

* Capture and log `request-id` for support/debug. ([Anthropic][12])
* Honor rate‑limit headers and backoff on 429/529. ([Anthropic][13])
* Consider feature flags for beta headers (e.g., `interleaved-thinking-2025-05-14`, `fine-grained-tool-streaming-2025-05-14`, `files-api-2025-04-14`, `mcp-client-2025-04-04`). ([Anthropic][8])

---

### Extensions to explore

* **Prompt caching** for large few‑shot/system prompts (Message Batches also helps with reliability). ([Anthropic][8])
* **Citations** and **search result** blocks for RAG with built‑in attribution. ([Anthropic][8])
* **MCP** to expose your local tools/services to Claude via `mcp_servers`. ([Anthropic][9])

[1]: https://docs.anthropic.com/en/api/messages "Messages - Anthropic"
[2]: https://github.com/sst/opencode/issues/417?utm_source=chatgpt.com "How does opencode work with Claude Code OAuth tokens ..."
[3]: https://gist.github.com/changjonathanc/9f9d635b2f8692e0520a884eaf098351?utm_source=chatgpt.com "Anthropic OAuth CLI - Simplified Claude Code spoof demo"
[4]: https://www.reddit.com/r/ClaudeAI/comments/1mvxia7/does_anyone_know_how_to_configure_claude_code/?utm_source=chatgpt.com "Does anyone know how to configure claude code with just ..."
[5]: https://docs.anthropic.com/en/api/beta-headers "Beta headers - Anthropic"
[6]: https://docs.anthropic.com/en/docs/build-with-claude/streaming "Streaming Messages - Anthropic"
[7]: https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/overview "Tool use with Claude - Anthropic"
[8]: https://docs.anthropic.com/en/release-notes/api "API - Anthropic"
[9]: https://docs.anthropic.com/en/docs/agents-and-tools/mcp-connector?utm_source=chatgpt.com "MCP connector"
[10]: https://docs.anthropic.com/en/docs/build-with-claude/vision?utm_source=chatgpt.com "Vision"
[11]: https://docs.anthropic.com/en/docs/build-with-claude/files?utm_source=chatgpt.com "Files API"
[12]: https://docs.anthropic.com/en/api/errors "Errors - Anthropic"
[13]: https://docs.anthropic.com/en/api/rate-limits?utm_source=chatgpt.com "Rate limits"
[14]: https://docs.anthropic.com/en/api/versioning?utm_source=chatgpt.com "Versions"
