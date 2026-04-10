[toc]

# Copilot Instructions

## Project overview

Neovim plugin for live Markdown preview in the browser. Pure Lua, no npm/Node. Depends on [`live-server.nvim`](https://github.com/selimacerbas/live-server.nvim) — a sibling repo that may be edited in the same session.

## Testing

No automated test suite. Testing is manual:

1. Open a `.md` file in Neovim, run `:MarkdownPreview`
2. For **takeover mode**: open another `.md` in a separate Neovim instance, run `:MarkdownPreview` — same browser tab should update
3. For **multi mode**: set `instance_mode = "multi"` in setup; each instance opens its own tab
4. Test scroll sync by moving the cursor — browser should follow
5. Test `:MarkdownPreviewStop` — server stops, lock file cleaned up (takeover primary only)
6. Test **TOC sidebar**: add `[toc]` to a `.md` file with multiple headings — a sticky sidebar should appear on the left 1/3; removing `[toc]` should revert to single-column layout

## Architecture

```
Neovim (Lua)  →  writes content.md to workspace dir
                 ↓
          live-server.nvim  →  serves workspace over HTTP + pushes SSE events
                                ↓
                          Browser (assets/index.html)
                          markdown-it + morphdom DOM diffing
```

**SSE events:** `reload` (content changed), `scroll` (cursor line sync)

### Browser layout

- The header is `position: fixed` — always visible regardless of scroll position.
- When the rendered markdown contains a `[toc]` token, `markdown-it-toc-done-right` emits a `<nav class="table-of-contents">`. After each morphdom update, `extractTOC()` moves that nav into `<aside id="toc-sidebar">` and adds `has-toc` to `#page-layout`, activating a flex layout: sidebar 1/3 (sticky below header), content 2/3. Without `[toc]`, the sidebar is hidden and the normal centered single-column layout is used.

### Instance modes

- **takeover** (default): shared workspace at `stdpath("cache")/markdown-preview/shared`, fixed port 8421. First Neovim instance is _primary_ (runs the server and writes a lock file). Subsequent instances are _secondary_ — they write `content.md` directly; live-server's `fs_watch` triggers the SSE reload. Secondary instances send scroll events via `remote.lua`'s HTTP injection endpoint (`GET /__live/inject`).
- **multi**: each instance runs its own server on an OS-assigned port (port 0). Separate browser tab per instance.

### Key live-server.nvim APIs

- `server.start(cfg)` → returns instance with `.port`
- `server.stop(inst)`, `server.reload(inst, path)`, `server.send_event(inst, event, data)`
- `server.update_target(inst, root, index)`, `server.connected_client_count(inst)`

### Mermaid rendering

Two modes (controlled by `mermaid_renderer` config key):

- `"js"` (default): fences are passed as-is; browser-side mermaid.js renders them
- `"rust"`: `mmdr` CLI pre-renders fences to SVG in Lua before writing `content.md`; failed blocks fall back to browser-side JS silently

### Workspace resolution

- `util.workspace_for_buffer(bufnr)` → `stdpath("cache")/markdown-preview/<sha256(bufname):12>`
- `util.shared_workspace()` → `stdpath("cache")/markdown-preview/shared`
- Lock file: `stdpath("cache")/markdown-preview/server.lock` (JSON: `{port, workspace, pid}`)

## Conventions

- **Lua patterns only** — no regex. The `{n,m}` quantifier syntax does not exist in Lua patterns; use repetition loops or anchored patterns instead.
- **`vim.loop` / `uv` for all async I/O** — file reads/writes, TCP connections, timers.
- **No default keymaps** — users map commands themselves. Never add `vim.keymap.set` calls in plugin or init code.
- **Debounce via `vim.defer_fn` + a sequence counter** — see `debounced_refresh` in `init.lua` for the canonical pattern.
- **`pcall` wrapping for all live-server calls** — the server may not be running; never let those errors propagate.
- **Asset resolution** uses `vim.api.nvim_get_runtime_file` first, then falls back to `debug.getinfo` path math (`util.resolve_asset`).
- **No Co-Authored-By trailers** in commits.
- **Release titles**: clean version numbers only (e.g., `v1.2.0`).
