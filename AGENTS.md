# Magnet Terminal

A production-grade Flutter macOS terminal emulator using our custom `dart_xterm` and `dart_pty` packages.

## Dependency Repos — WE OWN THESE

We own and maintain the two core dependency repos. You have full permission to read, modify, and commit to them when needed, such as fixing escape sequence parsing, adding PTY features, or exposing new APIs.

| Package | Path | qdexcode ID | What it does |
|---|---|---|---|
| **dart_xterm** | `/Users/chrisdrury/projects/dart_xterm` | `e0273d34-522c-454c-af6b-031f04a9e77d` | Terminal emulator library — escape sequence parser, TerminalView widget, buffer management, SGR/OSC handling |
| **dart_pty** | `/Users/chrisdrury/projects/dart_pty` | `c1308426-62c4-4361-82b4-3e819dd5c96f` | PTY allocation via native FFI — process spawning, env vars, resize, lifecycle management |

**When to modify them:**
- Escape sequence parsing bugs or missing sequences: fix in **dart_xterm**
- PTY spawn behavior, env var handling, signal issues: fix in **dart_pty**
- New terminal capabilities such as DA responses or DECRQM: add in **dart_xterm**
- Never fork or vendor: use path dependencies and fix upstream

**How to explore them with qdexcode:**
```text
mcp__qdexcode__search(command: "explore", project: "e0273d34-522c-454c-af6b-031f04a9e77d")  → dart_xterm
mcp__qdexcode__search(command: "explore", project: "c1308426-62c4-4361-82b4-3e819dd5c96f")  → dart_pty
```

## MCP DevTools — Built with dart_mcp SDK

The MCP devtools server (Phase 4) is written in **Dart** using the `dart_mcp` SDK, running in-process inside the Flutter app. This gives tools direct access to the `dart_xterm` `Terminal` object without IPC for cell inspection, cursor state, and similar introspection.

| Package | qdexcode ID | Key classes |
|---|---|---|
| **dart_mcp** | `1bab1707-226a-4d24-aed7-1322257b0e44` | `FastMCP` (tool registration), `McpServer` (JSON-RPC base), `Transport` (pluggable transport interface) |

**Architecture:**
- `FastMCP` extends `McpServer`: use `mcp.registerTool()` or `mcp.tool()` to add tools
- SDK ships with `StdioTransport`: we implement `HttpTransport` where the `Transport` interface is `Stream<String> incoming` plus `send(String)` plus `close()`
- Freezed types handle MCP protocol serialization for requests, responses, and tool schemas

**How to explore:**
```text
mcp__qdexcode__search(command: "explore", args: {query: "how does the MCP server work"}, project: "1bab1707-226a-4d24-aed7-1322257b0e44")
mcp__qdexcode__search(command: "read_file", args: {file_path: "lib/src/mcp/server/fastmcp.dart"}, project: "1bab1707-226a-4d24-aed7-1322257b0e44")
mcp__qdexcode__search(command: "read_file", args: {file_path: "example/fastmcp_echo.dart"}, project: "1bab1707-226a-4d24-aed7-1322257b0e44")
```

## Reference Implementations (read-only, for comparison)

| Project | qdexcode ID | Use for |
|---|---|---|
| xterm.js (Microsoft) | `5e4a74c8-07a9-414e-a44f-d65a8776c266` | Escape sequence handling reference, compatibility targets |
| wezterm | `605be883-a7a7-4e7f-9d69-e29845093679` | Terminal capability advertisement, DA responses, modern terminal features |
| wails-devtools MCP | `21d77535-3dca-4de7-bc04-ff793134759d` | MCP server architecture pattern for desktop app introspection |
| Go MCP SDK | `aa427fbe-a1eb-4e9c-b877-7eec16ff0247` | Streamable HTTP transport reference — see `mcp/streamable.go` for the HTTP contract with POST JSON-RPC, session headers, and Accept negotiation |

**Streamable HTTP contract (from Go SDK reference):**
- `POST /mcp` with `Content-Type: application/json`: send JSON-RPC request, get JSON response
- Headers: `Mcp-Protocol-Version` such as `2025-06-18`, and `Mcp-Session-Id` for session tracking
- Accept: `application/json, text/event-stream` for `POST`, `text/event-stream` for `GET` when using SSE
- For local devtools, use JSON response mode and skip SSE unless there is a concrete need for streaming

## Known Issues

- **SGR 4m underline problem**: some agent-driven terminal clients send SGR `4m` underlines instead of OSC 8 hyperlinks because they do not detect this terminal as hyperlink-capable. The MCP devtools server (Phase 4) will help diagnose which environment variable or capability query causes that fallback.

## Key Technical Decisions

- **macOS only** for now: no iOS, Android, web, Linux, or Windows
- **App Sandbox disabled**: PTY allocation requires `tcsetattr()`, which fails under sandbox
- **TERM=xterm-256color, COLORTERM=truecolor, TERM_PROGRAM=magnet-terminal**: set at PTY spawn time
- **ChangeNotifier for state**: no Riverpod or Bloc, keep it simple for a desktop app
- **MCP devtools via streamable HTTP**: server runs inside the app and the client connects over HTTP

---

# qdexcode MCP Tools

This project is indexed by **qdexcode**. Use the MCP tools below for code navigation, search, and exploration. These replace raw grep/find with richer results such as symbol definitions, call graphs, impact analysis, and semantic search.

## Gateways

All commands go through gateway tools. Use `command` to select the operation and `args` for parameters.

| Gateway | Purpose |
|---|---|
| `code` | Symbol lookup, call graph navigation, module exploration |
| `search` | Full-text search, regex search, semantic search, file listing |
| `project` | Project stats, module breakdown, recent changes |

## Getting Oriented

Start every session by understanding the project:

```text
project(command: "overview")                                    → scale, modules, key types, hot spots
code(command: "module_context", args: {module_path: "src"})     → drill into a directory
project(command: "tasks")                                       → discover build/test/lint targets
```

## Code Gateway

### extract — Deep-dive a symbol

Definition, source code, callers, and callees in one call. Use this before modifying any function.

```text
code(command: "extract", args: {symbol: "functionName"})
code(command: "extract", args: {symbol: "functionName", include_source: true})
```

### module_context — Explore a directory

File count, symbols, language stats, inbound callers, and outbound dependencies.

```text
code(command: "module_context", args: {module_path: "src/components"})
code(command: "module_context", args: {module_path: "internal/api", limit: 100})
```

### symbol — Exact symbol lookup

Find a symbol by exact name. Returns file path, line number, kind, and signature.

```text
code(command: "symbol", args: {name: "MyComponent"})
```

### resolve — Fuzzy symbol search

Partial or fuzzy name matching when you do not know the exact name.

```text
code(command: "resolve", args: {name: "MyComp", limit: 10})
```

### callers — Who calls this?

All incoming call sites for a symbol.

```text
code(command: "callers", args: {symbol: "fetchData"})
```

### callees — What does this call?

All outgoing calls from a symbol.

```text
code(command: "callees", args: {symbol: "fetchData"})
```

### what_breaks_if — Impact analysis

Before changing a symbol's signature or deleting it, check what breaks.

```text
code(command: "what_breaks_if", args: {symbol: "fetchData", change_type: "change-signature"})
code(command: "what_breaks_if", args: {symbol: "fetchData", change_type: "delete", max_depth: 3})
```

`change_type`: `"delete"` | `"change-signature"` | `"change-behavior"`

### graph_path — Trace call path between two symbols

```text
code(command: "graph_path", args: {from: "handleRequest", to: "saveToDatabase", max_depth: 5})
```

## Search Gateway

### search — Unified search

Combines symbol name matching with semantic vector similarity.

```text
search(command: "search", args: {query: "authentication"})
search(command: "search", args: {query: "authentication", include_source: true, limit: 10})
```

### content — Full-text search

Case-insensitive substring match across all indexed file contents.

```text
search(command: "content", args: {query: "TODO", limit: 50})
```

### grep — Regex search

POSIX regex with optional glob filtering.

```text
search(command: "grep", args: {pattern: "func.*New", glob: "*.go"})
search(command: "grep", args: {pattern: "import.*react", glob: "*.tsx"})
```

### files — List indexed files

Filter by language and/or path pattern.

```text
search(command: "files", args: {language: "TypeScript", pattern: "src/**"})
search(command: "files", args: {language: "Go", limit: 200})
```

### context — RAG retrieval

Semantic search that returns symbol info, source code, callers, callees, and relevance scores. Best for natural-language questions about the codebase.

```text
search(command: "context", args: {query: "how does authentication work", limit: 5})
```

## Project Gateway

### overview — Project stats

Scale, modules, key types, entry points, and hot spots. Use `sections` to pick what you need.

```text
project(command: "overview")
project(command: "overview", args: {sections: ["modules", "key_types"]})
project(command: "overview", args: {sections: ["all"]})
```

Sections: `scale`, `modules`, `key_types`, `hot_spots`, `entry_points`

### summary / snapshot — Quick stats

```text
project(command: "summary")    → lightweight overview
project(command: "snapshot")   → raw stats only
```

### changes — Recently modified files

```text
project(command: "changes", args: {since: "24h"})
project(command: "changes", args: {since: "7d"})
```

### tasks — Build/test/lint targets

Discovers Makefile targets, package.json scripts, and CI configs.

```text
project(command: "tasks")
```

## When to Use What

| I need to... | Command |
|---|---|
| Understand a function before editing | `code → extract` |
| Explore a directory I'm unfamiliar with | `code → module_context` |
| Find where something is called | `code → callers` |
| Check what breaks if I change something | `code → what_breaks_if` |
| Trace how A connects to B | `code → graph_path` |
| Search for a pattern in code | `search → grep` |
| Find files by language or path | `search → files` |
| Ask a natural-language question about code | `search → context` |
