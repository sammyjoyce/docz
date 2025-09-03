#!/usr/bin/env -S bun run
/*
 Layer Auditor (Zig repo) — Bun + TypeScript

 Features
 - Infers layers by path (L4 Foundation, L3 Engine, L2 Agents, L1 Application)
 - Parses @import("…") to build a coarse import graph
 - Enforces allowed dependency edges (no upward deps); L1 should not import Engine
 - Flags re-implementation smells (network/auth/session/tools/cli/tui) outside L4
 - Lightweight duplicate detection vs lower layers (sameish name or short body-hash)
 - Heuristically parses build.zig for addModule/addImport to resolve package names
 - Foundation sub-order (term < render < ui < tui < cli), exemptions for network/session/tools
 - Zero external deps; optional Opencode SDK integration when --use-opencode

 Usage
   bun run scripts/layer-audit.ts --root . --format md
   bun run scripts/layer-audit.ts --root . --format json --ignore ".git/**,docs/**"

 Exit codes: 0=OK, 1=warns, 2=fails, 3=error
*/

import fs from "fs/promises";
import path from "path";
import crypto from "crypto";
import os from "os";
// Track SDK 0.6.3 API surface used here
import type { createOpencodeClient as CreateOpencodeClientType } from "@opencode-ai/sdk";
import * as WTS from "web-tree-sitter";
import { fileURLToPath } from "url";
import { execFile as _execFile } from "child_process";
import { promisify } from "util";
const execFile = promisify(_execFile);

type LayerName = "L1" | "L2" | "L3" | "L4";
type Verdict = "PASS" | "WARN" | "FAIL";

interface Options {
  root: string;
  format: "md" | "json";
  ignore: string[];
  opencodeUrl: string;
  fsFallback: boolean;
  toast: boolean;
  startServer: boolean;
  pattern: string;
  useTreeSitter: boolean;
  zigWasmPath?: string;
  emitGraph?: string;
  // Fix flow
  fix: boolean;
  includeWarn: boolean;
  approve: "once" | "always" | "reject";
  postConcurrency: number;
  sessionTitle?: string;
}

// ---------------- CLI args ----------------
const argv = new Map<string, string>();
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a?.startsWith("--")) {
    const k = a.slice(2);
    const v = process.argv[i + 1]?.startsWith("--") ? "true" : process.argv[i + 1] ?? "true";
    argv.set(k, v);
  }
}

if (argv.has("help") || argv.has("h")) {
  console.log(
    "Layer Auditor\n\n" +
      "Options:\n" +
      "  --root <dir>           Root directory (default: .)\n" +
      "  --format <md|json>     Output format (default: md)\n" +
      "  --ignore <pat,pat,...> Glob-ish ignore segments (comma-separated)\n" +
      "  --opencode-url <url>   Opencode server URL (default: env OPENCODE_URL or http://localhost:4096)\n" +
      "  --fs-fallback <bool>   Fallback to local FS if Opencode unavailable (default: false)\n" +
      "  --toast <bool>         Show TUI toast with summary (default: false)\n" +
      "  --start-server <bool>  Auto-start a local Opencode server if unreachable (default: true)\n" +
      "  --treesitter <bool>    Use Tree-sitter if available (default: true)\n" +
      "  --zig-wasm <path>      Path to tree-sitter Zig grammar wasm (default: env ZIG_TS_WASM)\n" +
      "  --emit-graph <path>    Emit a repo-wide graph JSON (nodes, edges, legality)\n" +
      "  --pattern <glob>       Hint include pattern (default: **/*.zig, simplified)\n" +
      "  --fix <bool>           Post patch tasks to Opencode to fix violations (default: false)\n" +
      "  --include-warn <bool>  Include WARN-level reimplementation smells in fixes (default: false)\n" +
      "  --approve <mode>       Auto-approve permissions: once | always | reject (default: env OPENCODE_APPROVE or reject)\n" +
      "  --post-concurrency <n> Parallel patch postings (default: CPU*2, max 16)\n"
  );
  process.exit(0);
}

const options: Options = {
  root: path.resolve(argv.get("root") ?? "."),
  format: ((argv.get("format") ?? "md").toLowerCase() as Options["format"]) || "md",
  ignore: (argv.get("ignore") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean),
  opencodeUrl: argv.get("opencode-url") || process.env.OPENCODE_URL || "http://localhost:4096",
  fsFallback: (argv.get("fs-fallback") ?? "false").toLowerCase() === "true",
  toast: (argv.get("toast") ?? "false").toLowerCase() === "true",
  // default to autostart unless explicitly disabled
  startServer: (argv.get("start-server") ?? "true").toLowerCase() !== "false",
  pattern: argv.get("pattern") ?? "**/*.zig",
  useTreeSitter: (argv.get("treesitter") ?? "true").toLowerCase() !== "false",
  zigWasmPath: argv.get("zig-wasm") || process.env.ZIG_TS_WASM,
  emitGraph: argv.get("emit-graph") || undefined,
  fix: (argv.get("fix") ?? "false").toLowerCase() === "true",
  includeWarn: (argv.get("include-warn") ?? "false").toLowerCase() === "true",
  approve: ((argv.get("approve") || process.env.OPENCODE_APPROVE || process.env.OPENCODE_AUTO_APPROVE || "reject").toLowerCase() as any),
  postConcurrency: (() => {
    const envN = Number(process.env.OPENCODE_CONCURRENCY || 0);
    const flagN = Number(argv.get("post-concurrency") || 0);
    const def = Math.min(16, Math.max(2, (os.cpus()?.length || 8) * 2));
    return Number.isFinite(flagN) && flagN > 0 ? flagN : Number.isFinite(envN) && envN > 0 ? envN : def;
  })(),
  sessionTitle: argv.get("session-title") || process.env.OPENCODE_SESSION_TITLE || undefined,
};

// ---------------- Layer policy ----------------
const layerRank: Record<LayerName, number> = { L4: 1, L3: 2, L2: 3, L1: 4 };
const layerHuman: Record<LayerName, string> = { L4: "Foundation", L3: "Engine", L2: "Agent", L1: "Application" };
const allowed: Record<LayerName, Set<LayerName>> = {
  L1: new Set<LayerName>(["L4"]),
  L2: new Set<LayerName>(["L3", "L4"]),
  L3: new Set<LayerName>(["L4"]),
  L4: new Set<LayerName>([]),
};

const FOUNDATION_ORDER = ["term", "render", "ui", "tui", "cli"] as const;
const FOUNDATION_EXEMPT = new Set(["network", "session", "tools"]);

const FOUNDATION_SMELLS = [
  "http",
  "https",
  "sse",
  "oauth",
  "token",
  "authorization",
  "bearer",
  "request",
  "response",
  "headers",
  "url",
  "client",
  "retry",
  "backoff",
  "session",
  "state",
  "history",
  "persist",
  "load",
  "store",
  "tool",
  "registry",
  "reflection",
  "typeinfo",
  "schema",
  "json",
  "encode",
  "decode",
  "cli",
  "tui",
  "ansi",
  "cursor",
  "vt100",
  "termios",
  "render",
  "surface",
  "widget",
];

const DEFAULT_IGNORES = [
  "**/zig-cache/**",
  "**/.zig-cache/**",
  "**/.zig-cache-global/**",
  "**/zig-cache-*/**",
  "**/zig-out/**",
  "**/zig-out-*/**",
  "**/target/**",
  "**/build/**",
  "**/.cache/**",
  "**/node_modules/**",
  "**/.git/**",
  "**/*.zig.zon",
  "**/*.zigdoc",
  "**/tests/**",
];
const IGNORE_PATTERNS = [...DEFAULT_IGNORES, ...options.ignore];

// ---------------- Utilities ----------------
function posixRel(root: string, abs: string): string {
  return path.posix.normalize(path.relative(root, abs).replace(/\\/g, "/"));
}

function tokenize(s: string): string[] {
  return s.toLowerCase().split(/[^a-z0-9_]+/g).filter(Boolean);
}

function smellScore(src: string): number {
  const t = new Set(tokenize(src));
  let score = 0;
  for (const k of FOUNDATION_SMELLS) if (t.has(k)) score += 1;
  return score;
}

function sameish(a: string, b: string): boolean {
  if (a === b) return true;
  if (a?.toLowerCase() === b?.toLowerCase()) return true;
  const norm = (x: string) => x.replace(/[_-]/g, "").toLowerCase();
  return norm(a) === norm(b);
}

function matchesIgnore(relPath: string): boolean {
  const p = relPath;
  for (const pat of IGNORE_PATTERNS) {
    if (!pat) continue;
    const norm = pat.replace(/\\/g, "/");
    if (norm === p) return true;
    // **/segment/**
    if (norm.startsWith("**/") && norm.endsWith("/**")) {
      const mid = norm.slice(3, -3);
      if (mid && (p.includes(`/${mid}/`) || p.startsWith(`${mid}/`))) return true;
    }
    if (norm.startsWith("**/")) {
      const end = norm.slice(3);
      if (p.endsWith(end)) return true;
    }
    if (norm.endsWith("/**")) {
      const base = norm.slice(0, -3);
      if (p.startsWith(base)) return true;
    }
    if (norm.startsWith("*")) {
      const end = norm.slice(1);
      if (p.endsWith(end)) return true;
    }
    if (norm.endsWith("*")) {
      const start = norm.slice(0, -1);
      if (p.startsWith(start)) return true;
    }
  }
  return false;
}

// ---------------- Opencode SDK (required, with optional FS fallback) ----------------
type OpencodeClient = {
  config: { get: (opts?: any) => Promise<any> };
  find: { files: (args: { query: { query: string; directory?: string } }) => Promise<string[]> };
  file: { read: (args: { query: { path: string; directory?: string } }) => Promise<{ type: "raw" | "patch"; content: string }> };
  tui?: { showToast?: (args: { body?: { title?: string; message: string; variant: "info" | "success" | "warning" | "error" } }) => Promise<boolean> };
  app?: { log?: (args: { body?: any }) => Promise<boolean> };
  session: {
    create: (args: { body?: { title?: string } }) => Promise<{ id: string }>;
    prompt: (args: { path: { id: string }; body: { model?: { providerID: string; modelID: string }; agent?: string; tools?: Record<string, boolean>; parts: Array<{ type: "text"; text: string }> } }) => Promise<any>;
  };
  event: { subscribe: (args?: any) => Promise<any> };
  postSessionByIdPermissionsByPermissionId?: (args: { path: { id: string; permissionID: string }; body: { response: "once" | "always" | "reject" } }) => Promise<boolean>;
};

let startedServer: { close: () => void } | null = null;
async function createOpencode(): Promise<OpencodeClient | null> {
  const tryClient = async (baseUrl?: string): Promise<OpencodeClient> => {
    const mod: any = await import("@opencode-ai/sdk");
    const createOpencodeClient: typeof CreateOpencodeClientType = mod.createOpencodeClient;
    const client: OpencodeClient = createOpencodeClient({ baseUrl: baseUrl ?? options.opencodeUrl, responseStyle: "data" }) as any;
    await client.config.get();
    return client;
  };

  // First, attempt to connect to an existing server
  try {
    return await tryClient();
  } catch (err) {
    // If connection fails, auto-start when enabled and URL is local-ish
    if (options.startServer) {
      try {
        const mod: any = await import("@opencode-ai/sdk");
        const u = new URL(options.opencodeUrl);
        const host = (u.hostname || "127.0.0.1").toLowerCase();
        const isLocal = ["localhost", "127.0.0.1", "::1", "[::1]", "0.0.0.0"].includes(host);
        if (!isLocal) throw new Error(`Refusing to auto-start Opencode for non-local URL: ${options.opencodeUrl}`);
        const hostname = "127.0.0.1";
        const port = Number(u.port || 4096);
        const server = await mod.createOpencodeServer({ hostname, port });
        startedServer = server;
        return await tryClient(server.url);
      } catch (e) {
        if (options.fsFallback) return null;
        console.error(`[layer-audit] Unable to auto-start Opencode at ${options.opencodeUrl}.`);
        throw e;
      }
    }
    if (options.fsFallback) return null;
    console.error(`[layer-audit] Failed to connect to Opencode at ${options.opencodeUrl}.`);
    throw err;
  }
}

async function listZigFilesLocal(root: string): Promise<string[]> {
  const out: string[] = [];
  async function walk(dir: string) {
    const ents = await fs.readdir(dir, { withFileTypes: true });
    for (const e of ents) {
      const abs = path.join(dir, e.name);
      const rel = posixRel(root, abs);
      if (matchesIgnore(rel)) continue;
      if (e.isDirectory()) {
        await walk(abs);
      } else if (e.isSymbolicLink()) {
        try {
          const st = await fs.stat(abs).catch(() => null);
          if (!st) continue;
          if (st.isDirectory()) await walk(abs);
          else if (st.isFile() && abs.endsWith(".zig")) out.push(abs);
        } catch {}
      } else if (e.isFile() && abs.endsWith(".zig")) {
        out.push(abs);
      }
    }
  }
  await walk(root);
  return out;
}

async function listZigFilesOpencode(client: OpencodeClient): Promise<string[] | null> {
  try {
    const res: string[] = await client.find.files({ query: { query: "**/*.zig" } });
    const abs = res
      .map((p: string) => path.resolve(options.root, p))
      .filter((p: string) => !matchesIgnore(posixRel(options.root, p)));
    return abs;
  } catch {
    return null;
  }
}

async function readFile(client: OpencodeClient | null, absPath: string): Promise<string> {
  if (client) {
    try {
      const rel = posixRel(options.root, absPath);
      const file = await client.file.read({ query: { path: rel } });
      if (file?.type === "raw" && typeof file.content === "string") return file.content;
    } catch {
      // ignore and fallback to FS
    }
    // fall through to FS if client returned unexpected
  }
  return fs.readFile(absPath, "utf8");
}

// ---------------- build.zig module map (heuristic) ----------------
type ModuleMap = { map: Map<string, string>; alias: Map<string, string> };

async function parseBuildZigModuleMap(root: string): Promise<ModuleMap> {
  const file = path.join(root, "build.zig");
  let txt = "";
  try {
    txt = await fs.readFile(file, "utf8");
  } catch {
    return { map: new Map(), alias: new Map() };
  }

  const map = new Map<string, string>();
  const alias = new Map<string, string>();
  const varToName = new Map<string, string>();
  const nameToRoot = new Map<string, string>();

  const addModuleRx = /(var|const)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:[A-Za-z0-9_\.]+)?b\.addModule\(\s*"([^"]+)"\s*,\s*\.\{[\s\S]*?root_source_file\s*=\s*(?:[A-Za-z0-9_\.]+)?path\("([^"]+)"\)[\s\S]*?\)\s*;/g;
  let m: RegExpExecArray | null;
  while ((m = addModuleRx.exec(txt))) {
    const varName = m[2];
    const name = m[3];
    const rel = m[4];
    varToName.set(varName, name);
    nameToRoot.set(name, path.resolve(root, rel));
  }

  const addImportRx = /\.addImport\(\s*"([^"]+)"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/g;
  while ((m = addImportRx.exec(txt))) {
    const importName = m[1];
    const varName = m[2];
    const moduleName = varToName.get(varName);
    if (moduleName) alias.set(importName, moduleName);
  }

  for (const [name, rootSrc] of nameToRoot) map.set(name, rootSrc);
  return { map, alias };
}

// ---------------- Layer inference & foundation subdomain ----------------
function inferLayer(root: string, abs: string): LayerName {
  const rel = posixRel(root, abs);
  if (rel === "src/foundation.zig" || rel.startsWith("src/foundation/") || rel.startsWith("foundation/")) return "L4";
  if (rel === "src/engine.zig" || rel.startsWith("src/engine/")) return "L3";
  if (rel.startsWith("agents/")) return "L2";
  if (rel === "src/main.zig" || rel.startsWith("docz/")) return "L1";
  if (rel.startsWith("src/")) return "L3";
  return "L4";
}

function foundationSubdomain(rel: string): string | null {
  const p = rel.startsWith("src/") ? rel.slice(4) : rel;
  if (!p.startsWith("foundation/")) return null;
  const parts = p.split("/").slice(1);
  const dom = parts[0];
  if (!dom) return null;
  if (FOUNDATION_EXEMPT.has(dom)) return dom;
  if (FOUNDATION_ORDER.includes(dom as any)) return dom;
  return null;
}

function foundationOrderIndex(dom: string | null): number | null {
  if (!dom) return null;
  const i = FOUNDATION_ORDER.indexOf(dom as any);
  return i === -1 ? null : i;
}

// ---------------- Parsing Zig ----------------
const IMPORT_RX = /@import\("([^"]+)"\)/g;
const FN_RX = /\b(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)/g;

function getImports(src: string): string[] {
  const out: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = IMPORT_RX.exec(src))) out.push(m[1]);
  return out;
}

type FnSig = { name: string; argsSig: string; bodyHash: string };

function getFunctions(src: string): FnSig[] {
  const out: FnSig[] = [];
  let m: RegExpExecArray | null;
  while ((m = FN_RX.exec(src))) {
    const name = m[1];
    const argsSig = m[2].replace(/\s+/g, " ").trim();
    const window = src.slice(m.index, Math.min(src.length, m.index + 1000));
    const bodyHash = crypto.createHash("sha1").update(window).digest("hex").slice(0, 12);
    out.push({ name, argsSig, bodyHash });
  }
  return out;
}

// ---------------- Optional Tree-sitter integration ----------------
type TsContext = { parser: WTS.Parser | null };

async function initTreeSitter(): Promise<TsContext> {
  if (!options.useTreeSitter) return { parser: null };
  try {
    // Initialize core runtime, point to a known wasm for the runtime itself
    // Use the runtime wasm shipped with @vscode/tree-sitter-wasm
    let runtimeWasm = '';
    const resolveSpec = (spec: string): string | null => {
      try {
        // Bun/Node ESM compatible resolution to file path
        // @ts-ignore
        const url: string = import.meta.resolve ? import.meta.resolve(spec) : '';
        if (url && url.startsWith('file:')) return fileURLToPath(url);
      } catch {}
      // naive fallback
      const p = path.join(options.root, 'node_modules', spec);
      return p;
    };
    // Prefer @vscode runtime
    runtimeWasm = resolveSpec("@vscode/tree-sitter-wasm/wasm/tree-sitter.wasm") ?? '';
    if (!runtimeWasm) runtimeWasm = resolveSpec("web-tree-sitter/tree-sitter.wasm") ?? '';
    if (runtimeWasm) {
      await WTS.default.init({ locateFile: () => runtimeWasm });
    } else {
      await WTS.default.init();
    }

    const zigWasmCandidates: string[] = [];
    if (options.zigWasmPath) zigWasmCandidates.push(path.resolve(options.zigWasmPath));
    // common locations
    zigWasmCandidates.push(
      path.join(options.root, "wasm", "tree-sitter-zig.wasm"),
      path.join(options.root, "scripts", "tree-sitter-zig.wasm"),
      path.join(options.root, "scripts", "zig-ts-grammar", "tree-sitter-zig.wasm"),
      path.join(options.root, "vendor", "tree-sitter-zig.wasm"),
      path.join(options.root, "node_modules", "tree-sitter-zig", "tree-sitter-zig.wasm"),
      path.join(options.root, "node_modules", "tree-sitter-zig", "dist", "tree-sitter-zig.wasm"),
    );

    let zigWasm: string | null = null;
    for (const c of zigWasmCandidates) {
      try { const st = await fs.stat(c); if (st.isFile()) { zigWasm = c; break; } } catch {}
    }

    if (!zigWasm) {
      // Attempt auto-build if grammar sources exist
      const grammarDir = path.join(options.root, "scripts", "zig-ts-grammar");
      const buildScript = path.join(options.root, "scripts", "build-zig-grammar.sh");
      try {
        const st = await fs.stat(grammarDir).catch(() => null);
        const bs = await fs.stat(buildScript).catch(() => null);
        if (st?.isDirectory() && bs?.isFile()) {
          await runBuildScript(buildScript);
          const candidate = path.join(grammarDir, "tree-sitter-zig.wasm");
          const st2 = await fs.stat(candidate).catch(() => null);
          if (st2?.isFile()) zigWasm = candidate;
        }
      } catch {}
      if (!zigWasm) {
        // No grammar found; operate without Tree-sitter but keep the runtime initialized
        return { parser: null };
      }
    }

    const lang = await (WTS as any).Language.load(zigWasm);
    const parser = new WTS.default();
    parser.setLanguage(lang);
    return { parser };
  } catch {
    return { parser: null };
  }
}

function stripCommentsAndStringsWithTs(src: string, parser: WTS.Parser): string {
  const tree = parser.parse(src);
  const cursor = tree.walk();
  const ranges: { start: number; end: number }[] = [];
  function visit() {
    const type = cursor.nodeType;
    if (type && (type.includes("comment") || type.includes("string"))) {
      const n = cursor.currentNode as any;
      ranges.push({ start: n.startIndex, end: n.endIndex });
    }
    if (cursor.gotoFirstChild()) {
      do { visit(); } while (cursor.gotoNextSibling());
      cursor.gotoParent();
    }
  }
  visit();
  if (ranges.length === 0) return src;
  ranges.sort((a, b) => a.start - b.start);
  let out = "";
  let pos = 0;
  for (const r of ranges) {
    if (r.start > pos) out += src.slice(pos, r.start);
    out += " ".repeat(Math.max(0, r.end - r.start));
    pos = r.end;
  }
  out += src.slice(pos);
  return out;
}

function getFunctionsTS(src: string, parser: WTS.Parser): FnSig[] {
  try {
    const tree = parser.parse(src);
    const cursor = tree.walk();
    const out: FnSig[] = [];
    function visit() {
      const type = cursor.nodeType;
      const n = cursor.currentNode as any;
      // Heuristic: any node that likely represents a function (type contains 'fn' or 'function')
      if (type && (type.includes("fn") || type.includes("function"))) {
        const text = src.slice(n.startIndex, Math.min(src.length, n.endIndex));
        // Reuse regex within the node window for robust name+args capture
        let m: RegExpExecArray | null;
        const rx = /\b(?:pub\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)/g;
        while ((m = rx.exec(text))) {
          const name = m[1];
          const argsSig = m[2].replace(/\s+/g, " ").trim();
          const bodyHash = crypto.createHash("sha1").update(text.slice(m.index, Math.min(text.length, m.index + 2000))).digest("hex").slice(0, 12);
          out.push({ name, argsSig, bodyHash });
        }
      }
      if (cursor.gotoFirstChild()) {
        do { visit(); } while (cursor.gotoNextSibling());
        cursor.gotoParent();
      }
    }
    visit();
    return out.length ? out : getFunctions(src);
  } catch {
    return getFunctions(src);
  }
}

function getImportsTS(src: string, parser: WTS.Parser): string[] {
  try {
    const tree = parser.parse(src);
    const cursor = tree.walk();
    const out: string[] = [];
    function visit() {
      const type = cursor.nodeType;
      const n = cursor.currentNode as any;
      if (type === 'import_call') {
        const text = src.slice(n.startIndex, n.endIndex);
        const m = text.match(/@import\(\s*"([^"]+)"\s*\)/);
        if (m) out.push(m[1]);
      }
      if (cursor.gotoFirstChild()) {
        do { visit(); } while (cursor.gotoNextSibling());
        cursor.gotoParent();
      }
    }
    visit();
    return out.length ? out : getImports(src);
  } catch {
    return getImports(src);
  }
}

// ---------------- Graph emission ----------------
type GraphNode = { id: string; layer: LayerName };
type GraphEdge = { from: string; to: string; from_layer: LayerName; to_layer: LayerName; allowed: boolean; reason?: string };

function isAllowedEdge(from: LayerName, to: LayerName, fromRel: string, toRel: string): { ok: boolean; reason?: string } {
  if (from === to) return { ok: true };
  if (from === "L1" && to === "L3") return { ok: false, reason: `Application should use Foundation, not Engine (${toRel})` };
  const ok = allowed[from].has(to);
  return ok ? { ok } : { ok: false, reason: `Illegal import: ${layerHuman[from]} → ${layerHuman[to]} (${toRel})` };
}

async function emitGraphJSON(outPath: string, reports: FileReport[]) {
  const nodes: GraphNode[] = reports.map(r => ({ id: r.rel, layer: r.layer }));
  const edges: GraphEdge[] = [];
  const idset = new Set(nodes.map(n => n.id));
  for (const r of reports) {
    for (const im of r.imports) {
      if (im.layer === "external" || im.layer === "unknown") continue;
      if (!idset.has(im.target)) continue; // skip unresolved
      const check = isAllowedEdge(r.layer, im.layer as LayerName, r.rel, im.target);
      edges.push({ from: r.rel, to: im.target, from_layer: r.layer, to_layer: im.layer as LayerName, allowed: check.ok, reason: check.reason });
    }
  }
  const out = { nodes, edges };
  await fs.mkdir(path.dirname(outPath), { recursive: true }).catch(() => {});
  await fs.writeFile(outPath, JSON.stringify(out, null, 2));
}

type ImportLayer = LayerName | "external" | "unknown";

async function resolveImport(fromFile: string, importStr: string, root: string, moduleMap: ModuleMap): Promise<string | null> {
  if (["std", "builtin", "root"].includes(importStr)) return null;
  const mm = moduleMap?.map ?? new Map<string, string>();
  const alias = moduleMap?.alias ?? new Map<string, string>();
  const resolvedName = alias.get(importStr) || importStr;
  const moduleRoot = mm.get(resolvedName);
  if (moduleRoot) {
    try {
      const st = await fs.stat(moduleRoot);
      if (st.isFile()) return path.resolve(moduleRoot);
    } catch {}
  }
  const base = path.dirname(fromFile);
  const candidates: string[] = [];
  if (importStr.startsWith("./") || importStr.startsWith("../") || importStr.endsWith(".zig")) {
    const abs = path.resolve(base, importStr);
    candidates.push(abs, abs + ".zig", path.join(abs, "index.zig"));
  } else {
    candidates.push(
      path.join(root, importStr),
      path.join(root, importStr + ".zig"),
      path.join(root, "src", importStr + ".zig"),
      path.join(root, "src", importStr, "main.zig"),
      path.join(root, "src", importStr, "index.zig"),
      path.join(root, "agents", importStr, "main.zig"),
      path.join(root, "agents", importStr, "spec.zig")
    );
  }
  for (const c of candidates) {
    try {
      const st = await fs.stat(c);
      if (st.isFile()) return path.resolve(c);
    } catch {}
  }
  return null;
}

// ---------------- Analysis ----------------
type FileReport = {
  file: string;
  rel: string;
  layer: LayerName;
  imports: { target: string; layer: ImportLayer }[];
  violations: string[];
  reimplWarnings: string[];
  verdict: Verdict;
  functions: FnSig[];
  graph?: {
    layer: LayerName;
    imports: { target: string; layer: LayerName; allowed: boolean; reason?: string }[];
    importedBy: { source: string; layer: LayerName; allowed: boolean; reason?: string }[];
    summary: { upstream_illegal: number; downstream_illegal: number };
  };
};

type Summary = {
  totals: Record<Verdict, number>;
  byLayer: Record<LayerName, Record<Verdict, number>>;
};

async function analyze(root: string, files: string[], client: OpencodeClient | null): Promise<{ reports: FileReport[]; summary: Summary }> {
  const ts = await initTreeSitter();
  const moduleMap = await parseBuildZigModuleMap(root);
  const entries = files
    .map((abs) => ({ abs, rel: posixRel(root, abs), layer: inferLayer(root, abs) }))
    .sort((a, b) => layerRank[a.layer] - layerRank[b.layer] || a.rel.localeCompare(b.rel));

  const lowerFnIndex: { layer: LayerName; file: string; sig: FnSig }[] = [];
  const reports: FileReport[] = [];

  for (const f of entries) {
    const srcOriginal = await readFile(client, f.abs);
    const srcForSmell = ts.parser ? (() => { try { return stripCommentsAndStringsWithTs(srcOriginal, ts.parser); } catch { return srcOriginal; } })() : srcOriginal;
    const imps = ts.parser ? getImportsTS(srcOriginal, ts.parser) : getImports(srcOriginal);
    const importsResolved: { target: string; layer: ImportLayer }[] = [];
    for (const im of imps) {
      const targetAbs = await resolveImport(f.abs, im, root, moduleMap);
      if (!targetAbs) importsResolved.push({ target: im, layer: "external" });
      else importsResolved.push({ target: posixRel(root, targetAbs), layer: inferLayer(root, targetAbs) });
    }

    const violations: string[] = [];
    for (const r of importsResolved) {
      if (r.layer === "external" || r.layer === "unknown") continue;
      if (!allowed[f.layer].has(r.layer) && f.layer !== r.layer) {
        violations.push(`Illegal import: ${layerHuman[f.layer]} → ${layerHuman[r.layer]} (${r.target})`);
      }
      if (f.layer === "L1" && r.layer === "L3") {
        violations.push(
          `Application should delegate via Foundation (agent_main/auth), not import Engine directly: ${r.target}`
        );
      }
    }

    if (f.layer === "L2") {
      const selfAgent = /^agents\/([^\/]+)/.exec(f.rel)?.[1];
      for (const r of importsResolved) {
        if (r.layer !== "L2") continue;
        const other = /^agents\/([^\/]+)/.exec(r.target)?.[1];
        if (selfAgent && other && other !== selfAgent) {
          violations.push(`Cross-agent import not allowed: ${selfAgent} → ${other} (${r.target})`);
        }
      }
    }

    if (f.layer === "L4") {
      const fromDom = foundationSubdomain(f.rel);
      const fromIdx = foundationOrderIndex(fromDom);
      if (fromIdx != null) {
        for (const r of importsResolved) {
          if (r.layer !== "L4") continue;
          const toDom = foundationSubdomain(r.target);
          if (!toDom || FOUNDATION_EXEMPT.has(toDom)) continue;
          const toIdx = foundationOrderIndex(toDom);
          if (toIdx != null && toIdx > fromIdx) {
            violations.push(`Foundation sub-order violation: ${fromDom} cannot import ${toDom} (${r.target})`);
          }
        }
      }
    }

    const reimplWarnings: string[] = [];
    if (f.layer !== "L4") {
      const score = smellScore(srcForSmell);
      if (score >= 3)
        reimplWarnings.push(
          `Contains ${score} Foundation-like keywords (network/session/tools/cli/tui). Consider using Foundation APIs instead.`
        );
    }

    const fns = ts.parser ? getFunctionsTS(srcOriginal, ts.parser) : getFunctions(srcOriginal);
    for (const fn of fns) {
      for (const prev of lowerFnIndex) {
        const sameName = sameish(fn.name, prev.sig.name);
        const bodyClash = fn.bodyHash === prev.sig.bodyHash;
        if (sameName || bodyClash) {
          const msg = sameName
            ? `Function "${fn.name}" resembles lower-layer "${prev.sig.name}" (${layerHuman[prev.layer]} @ ${prev.file}). Consider delegating.`
            : `Function body for "${fn.name}" looks very similar to lower-layer "${prev.sig.name}" (${layerHuman[prev.layer]} @ ${prev.file}).`;
          reimplWarnings.push(msg);
        }
      }
    }

    let verdict: Verdict = "PASS";
    if (violations.length > 0) verdict = "FAIL";
    else if (reimplWarnings.length > 0) verdict = "WARN";

    reports.push({
      file: f.abs,
      rel: f.rel,
      layer: f.layer,
      imports: importsResolved,
      violations,
      reimplWarnings,
      verdict,
      functions: fns,
    });

    for (const fn of fns) lowerFnIndex.push({ layer: f.layer, file: f.rel, sig: fn });
  }

  const summary: Summary = {
    totals: { PASS: 0, WARN: 0, FAIL: 0 },
    byLayer: { L1: { PASS: 0, WARN: 0, FAIL: 0 }, L2: { PASS: 0, WARN: 0, FAIL: 0 }, L3: { PASS: 0, WARN: 0, FAIL: 0 }, L4: { PASS: 0, WARN: 0, FAIL: 0 } },
  };
  for (const r of reports) {
    summary.totals[r.verdict] += 1;
    summary.byLayer[r.layer][r.verdict] += 1;
  }

  // Build reverse import map for graph (only repo-internal edges)
  const byRel = new Map<string, FileReport>();
  for (const r of reports) byRel.set(r.rel, r);
  const importedBy = new Map<string, { source: string; layer: LayerName }[]>();
  for (const r of reports) {
    for (const im of r.imports) {
      if (im.layer === "external" || im.layer === "unknown") continue;
      const arr = importedBy.get(im.target) ?? [];
      arr.push({ source: r.rel, layer: r.layer });
      importedBy.set(im.target, arr);
    }
  }

  // Fill graph field per file
  function isAllowedEdge(from: LayerName, to: LayerName, fromRel: string, toRel: string): { ok: boolean; reason?: string } {
    if (from === to) return { ok: true };
    if (from === "L1" && to === "L3") return { ok: false, reason: `Application should use Foundation, not Engine (${toRel})` };
    const ok = allowed[from].has(to);
    return ok ? { ok } : { ok: false, reason: `Illegal import: ${layerHuman[from]} → ${layerHuman[to]} (${toRel})` };
  }

  for (const r of reports) {
    const importsG: { target: string; layer: LayerName; allowed: boolean; reason?: string }[] = [];
    for (const im of r.imports) {
      if (im.layer === "external" || im.layer === "unknown") continue;
      const check = isAllowedEdge(r.layer, im.layer, r.rel, im.target);
      importsG.push({ target: im.target, layer: im.layer, allowed: check.ok, reason: check.reason });
    }
    const importers = importedBy.get(r.rel) ?? [];
    const importedByG: { source: string; layer: LayerName; allowed: boolean; reason?: string }[] = [];
    for (const s of importers) {
      const check = isAllowedEdge(s.layer, r.layer, s.source, r.rel);
      importedByG.push({ source: s.source, layer: s.layer, allowed: check.ok, reason: check.reason });
    }
    const upstreamIllegal = importsG.filter(x => !x.allowed).length;
    const downstreamIllegal = importedByG.filter(x => !x.allowed).length;
    r.graph = { layer: r.layer, imports: importsG, importedBy: importedByG, summary: { upstream_illegal: upstreamIllegal, downstream_illegal: downstreamIllegal } };
  }

  return { reports, summary };
}

// ---------------- Rendering ----------------
function renderMD(reports: FileReport[], summary: Summary): string {
  const lines: string[] = [];
  lines.push(`# Layer Audit Report`);
  lines.push("");
  lines.push(`Totals — PASS: ${summary.totals.PASS}, WARN: ${summary.totals.WARN}, FAIL: ${summary.totals.FAIL}`);
  lines.push("");
  lines.push(`By Layer`);
  for (const L of ["L4", "L3", "L2", "L1"] as LayerName[]) {
    const s = summary.byLayer[L];
    lines.push(`- ${layerHuman[L]} (${L}) — PASS: ${s.PASS}, WARN: ${s.WARN}, FAIL: ${s.FAIL}`);
  }
  lines.push("");

  for (const r of reports) {
    lines.push(`## ${r.rel} — ${layerHuman[r.layer]} (${r.layer}) — ${r.verdict}`);
    if (r.imports.length) {
      lines.push(`<details><summary>Imports (${r.imports.length})</summary>`);
      lines.push("");
      for (const im of r.imports) lines.push(`- ${im.target} → ${im.layer}`);
      lines.push("");
      lines.push(`</details>`);
    }
    if (r.violations.length) {
      lines.push(`Violations`);
      for (const v of r.violations) lines.push(`- ${v}`);
    }
    if (r.reimplWarnings.length) {
      lines.push(`Re-implementation Warnings`);
      for (const w of r.reimplWarnings) lines.push(`- ${w}`);
    }
    if (r.graph) {
      lines.push(`Graph`);
      const g = r.graph;
      lines.push(`- Layer: ${layerHuman[g.layer]} (${g.layer})`);
      lines.push(`- Upstream illegal: ${g.summary.upstream_illegal}, Downstream illegal: ${g.summary.downstream_illegal}`);
      const show = (arr: any[], dir: 'imports' | 'importedBy') => {
        if (!arr.length) return;
        lines.push(`  - ${dir === 'imports' ? 'Imports' : 'Imported By'} (${arr.length})`);
        for (const e of arr.slice(0, 10)) {
          if (dir === 'imports') lines.push(`    - ${e.target} → ${layerHuman[e.layer]} [${e.allowed ? 'ok' : 'ILLEGAL'}]${e.reason ? ' — ' + e.reason : ''}`);
          else lines.push(`    - ${e.source} (${layerHuman[e.layer]}) [${e.allowed ? 'ok' : 'ILLEGAL'}]${e.reason ? ' — ' + e.reason : ''}`);
        }
        if (arr.length > 10) lines.push(`    - ... ${arr.length - 10} more`);
      };
      show(g.imports, 'imports');
      show(g.importedBy, 'importedBy');
    }
    lines.push("");
  }
  return lines.join("\n");
}

// ---------------- Auto-fix via Opencode ----------------
type ProviderModel = { providerID: string; modelID: string } | null;

async function chooseModel(client: OpencodeClient): Promise<ProviderModel> {
  try {
    const cfg = await (client as any).config.providers();
    const providers = (cfg?.providers ?? []) as any[];
    const defaults = cfg?.default ?? {};
    const envProv = (process.env.OPENCODE_PROVIDER || "").trim();
    const envModel = (process.env.OPENCODE_MODEL || "").trim();
    if (envProv && envModel) return { providerID: envProv, modelID: envModel };

    const byId: Record<string, any> = Object.create(null);
    for (const p of providers) if (p?.id) byId[p.id] = p;

    const supportsTools = (provId?: string, modelId?: string) => {
      if (!provId || !modelId) return false;
      const prov = byId[provId];
      const model = prov?.models?.find?.((m: any) => m?.id === modelId);
      return !!model?.tool_call;
    };

    // prefer server default if tool-capable
    const defEntries = Object.entries(defaults);
    if (defEntries.length) {
      const [prov, model] = defEntries[0];
      if (supportsTools(prov, model)) return { providerID: prov, modelID: model };
    }

    // otherwise pick first tool-capable model from common providers
    const prefer = ["opencode", "anthropic", "openai", "google"];
    for (const pid of prefer) {
      const p = byId[pid];
      const m = p?.models?.find?.((m: any) => !!m?.tool_call);
      if (p?.id && m?.id) return { providerID: p.id, modelID: m.id };
    }

    // fallback to first available model
    for (const p of providers) {
      const m = p?.models?.[0]?.id;
      if (p?.id && m) return { providerID: p.id, modelID: m };
    }
  } catch {}
  return null;
}

const FIX_GUIDELINES = `
You are modifying a Zig 0.15.1 repository with strict layering and module rules.
- Layers: L4 Foundation, L3 Engine, L2 Agents, L1 Application. Allowed imports: L1→L4 only; L2→L3/L4; L3→L4; L4 has no upwards deps.
- Barrels: Import via module barrels only. Use src/foundation.zig or src/foundation/<ns>.zig (term, render, ui, tui, cli) — avoid deep paths.
- Foundation order: term < render < ui < tui < cli; do not introduce cycles or reverse deps.
- No re-implementing foundation subsystems in higher layers (network/auth/session/tools/cli/tui). Prefer delegating to barrels.
- Zig 0.15.1 APIs: new std.Io Reader/Writer; no usingnamespace; narrow public error sets; no anyerror; pass allocators; use @This pattern.
Keep edits minimal to satisfy the rules and compile. Prefer adjusting imports and simple refactors over large rewrites.
`;

function formatFixPrompt(report: FileReport, source: string): string {
  const issues: string[] = [];
  for (const v of report.violations) issues.push(`VIOLATION: ${v}`);
  for (const w of report.reimplWarnings) issues.push(`SMELL: ${w}`);
  const header = `File: ${report.rel} — Layer ${report.layer}`;
  const body = issues.length ? issues.map((l) => `- ${l}`).join("\n") : "- No explicit issues collected (fix any latent layering problems).";
  const code = source ?? "";
  return [
    header,
    "\nIssues:",
    body,
    "\nGuidelines:",
    FIX_GUIDELINES,
    "\nCurrent contents:",
    "```zig\n" + code.replace(/```/g, "\u0060\u0060\u0060") + "\n```",
    "\nMake the smallest edits needed to resolve the issues. Apply changes using the patch tool only. Do not output explanations.",
    "If imports are illegal, switch to correct barrel imports. If code reimplements foundation behavior, replace with calls to foundation APIs.",
  ].join("\n");
}

async function watchForApprovals(client: OpencodeClient, sessionID: string, approve: Options["approve"], postedAllRef: { done: boolean }) {
  if (approve === "reject") return { changed: [] as string[], approvals: 0 };
  let approvals = 0;
  const changed = new Set<string>();
  const events = await client.event.subscribe();
  let lastActivity = Date.now();
  const QUIET_MS = 10_000;
  const tryApprove = async (permissionID: string) => {
    try {
      if (client.postSessionByIdPermissionsByPermissionId) {
        await client.postSessionByIdPermissionsByPermissionId({ path: { id: sessionID, permissionID }, body: { response: approve } });
        approvals++;
      }
    } catch {}
  };
  try {
    for await (const ev of (events as any)?.stream ?? []) {
      if (!ev || typeof ev !== "object") continue;
      const t = ev.type as string;
      if (t === "permission.updated" && ev.properties?.sessionID === sessionID && ev.properties?.id) {
        lastActivity = Date.now();
        await tryApprove(String(ev.properties.id));
      } else if (t === "file.edited" && typeof ev.properties?.file === "string") {
        changed.add(ev.properties.file);
        lastActivity = Date.now();
      } else if (t === "message.part.updated" && ev.properties?.part?.type === "patch") {
        for (const f of ev.properties?.part?.files ?? []) if (typeof f === "string") changed.add(f);
        lastActivity = Date.now();
      } else if (t?.startsWith("session.")) {
        lastActivity = Date.now();
      }
      if (postedAllRef.done && Date.now() - lastActivity > QUIET_MS) break;
    }
  } catch {}
  return { changed: Array.from(changed), approvals };
}

async function postFixes(client: OpencodeClient, reports: FileReport[], providerModel: ProviderModel): Promise<{ posted: number; changed: string[]; approvals: number }> {
  const toFix = reports.filter((r) => r.violations.length > 0 || (options.includeWarn && r.reimplWarnings.length > 0));
  if (toFix.length === 0) return { posted: 0, changed: [], approvals: 0 };

  const title = options.sessionTitle || `Layer audit fixes (${new Date().toISOString()})`;
  const existing = process.env.OPENCODE_SESSION_ID?.trim();
  const sessionID = existing && existing.length > 0 ? existing : (await client.session.create({ body: { title } }))?.id;

  const postedAllRef = { done: false };
  const monitor = watchForApprovals(client, sessionID, options.approve, postedAllRef);

  let posted = 0;
  const queue = [...toFix];
  const workers: Promise<void>[] = [];
  for (let i = 0; i < Math.max(1, options.postConcurrency); i++) {
    workers.push((async () => {
      while (true) {
        const r = queue.pop();
        if (!r) break;
        try {
          const src = await readFile(client, r.file);
          const prompt = formatFixPrompt(r, src);
          const body: any = { parts: [{ type: "text", text: prompt }], tools: { patch: true } };
          if (providerModel) body.model = providerModel;
          await client.session.prompt({ path: { id: sessionID }, body });
          posted++;
        } catch (e) {
          console.warn(`[layer-audit] Failed to post fix for ${r.rel}:`, (e as any)?.message || e);
        }
      }
    })());
  }
  await Promise.all(workers);
  postedAllRef.done = true;
  const { changed, approvals } = await monitor;
  return { posted, changed, approvals };
}

// ---------------- Main ----------------
async function main() {
  try {
    const client = await createOpencode();
    let files: string[] = [];
    if (client) {
      const [ocFiles, fsFiles] = await Promise.all([
        listZigFilesOpencode(client).catch(() => null),
        listZigFilesLocal(options.root),
      ]);
      const merged = new Set<string>();
      for (const f of fsFiles) merged.add(f);
      if (ocFiles && ocFiles.length) for (const f of ocFiles) merged.add(f);
      files = Array.from(merged);
    } else {
      files = await listZigFilesLocal(options.root);
    }

    const { reports, summary } = await analyze(options.root, files, client);

    if (client) {
      if (options.toast && client.tui?.showToast) {
        try {
          const variant = summary.totals.FAIL > 0 ? "error" : summary.totals.WARN > 0 ? "warning" : "success";
          await client.tui.showToast({ body: { message: `Layer audit: PASS ${summary.totals.PASS}, WARN ${summary.totals.WARN}, FAIL ${summary.totals.FAIL}`, variant } });
        } catch {}
      }
    }

    if (options.emitGraph) {
      const outPath = path.isAbsolute(options.emitGraph)
        ? options.emitGraph
        : path.join(options.root, options.emitGraph);
      try {
        await emitGraphJSON(outPath, reports);
        console.log(`[layer-audit] Graph written to ${outPath}`);
      } catch (e) {
        console.error(`[layer-audit] Failed to emit graph:`, (e as any)?.message || e);
        process.exitCode = 2;
      }
    }
    if (options.format === "json") console.log(JSON.stringify({ summary, reports }, null, 2));
    else console.log(renderMD(reports, summary));

    // Optional: attempt auto-fix via Opencode
    if (options.fix && client) {
      try {
        const model = await chooseModel(client);
        const { posted, changed, approvals } = await postFixes(client, reports, model);
        console.log(`[fix] Posted ${posted} patch tasks${approvals ? `; auto-approved ${approvals}` : ''}${changed.length ? `; files changed: ${changed.length}` : ''}`);
        if (changed.length) {
          for (const f of changed.slice(0, 25)) console.log(`[changed] ${f}`);
          if (changed.length > 25) console.log(`[changed] …and ${changed.length - 25} more`);
        }
      } catch (e) {
        console.warn(`[fix] Auto-fix encountered an error:`, (e as any)?.message || e);
      }
      // Do not fail hard when fix mode is enabled
      process.exitCode = 0;
      return;
    }

    if (summary.totals.FAIL > 0) process.exit(2);
    if (summary.totals.WARN > 0) process.exitCode = 1;
  } catch (err: any) {
    console.error(err?.stack || String(err));
    process.exit(3);
  } finally {
    if (startedServer) {
      try { startedServer.close(); } catch {}
    }
  }
}

async function runBuildScript(scriptPath: string) {
  try {
    await execFile(scriptPath, { cwd: path.dirname(scriptPath) });
  } catch (e) {
    // best-effort only
  }
}

main();
