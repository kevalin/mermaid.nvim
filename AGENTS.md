# AGENTS.md

This file provides architecture context, coding standards, and operational guidelines for AI agents working in `mermaid.nvim`.

---

## Project Overview

`mermaid.nvim` is a lightweight, zero-dependency Neovim plugin for working with [Mermaid](https://mermaid.js.org/) diagrams. It provides:
- Live browser preview with Server-Sent Events (SSE) via a built-in Lua HTTP server.
- Built-in pure-Lua diagram formatter.
- Asynchronous diagnostics and linting via `mermaid-cli` (`mmdc`).
- Inline diagram rendering for modern terminals (Kitty graphics protocol and `chafa` fallback).
- Floating control panel for managing server and preview states.

### Core Architectural Principles
- **Zero External Lua Dependencies**: The built-in HTTP server, SSE broadcaster, and diagram formatter must remain pure Lua without requiring third-party Lua rocks or libraries. Leverage Neovim's native libuv bindings (`vim.uv` / `vim.loop`).
- **Defensive & Resilient**: Gracefully handle missing optional binaries (`mmdc`, `chafa`), port conflicts, browser spawning errors, and client disconnects.
- **Asynchronous Execution**: Long-running operations (rendering, linting, CLI calls) must run asynchronously to keep Neovim UI responsive.

---

## Repository Structure

```
mermaid.nvim/
├── lua/mermaid/
│   ├── init.lua        # Plugin entry point, default options merging, setup()
│   ├── format.lua      # Built-in pure-Lua Mermaid formatter (indentation, tokens)
│   ├── lint.lua        # Diagnostics integration with vim.diagnostic and mmdc
│   ├── preview.lua     # Preview coordinator (buffer tracking, browser trigger, debounce)
│   ├── server.lua      # Embedded HTTP server & SSE handler via vim.loop / vim.uv
│   ├── render.lua      # Inline terminal rendering (Kitty graphics protocol / chafa)
│   └── panel.lua       # Floating UI panel for status and quick actions
├── plugin/
│   └── mermaid.lua     # Exposes user commands (:MermaidPreview, :MermaidFormat, etc.)
├── ftdetect/
│   └── mermaid.lua     # Filetype detection (.mmd, .mermaid -> filetype=mermaid)
├── static/
│   ├── index.html      # Browser preview HTML shell
│   ├── css/preview.css # Preview page layout and theme styling
│   └── js/preview.js   # Browser SSE client, Mermaid/Beautiful-Mermaid renderers & toolbar
├── tests/
│   ├── minimal_init.lua          # Minimal Neovim init for headless test runs
│   ├── preview_export.test.mjs   # Node.js test suite for preview export logic
│   └── *_spec.lua                # Plenary Busted test specifications
├── doc/
│   └── mermaid.txt     # Vimdoc reference documentation
├── .github/workflows/
│   └── ci.yml          # GitHub Actions matrix (Luacheck + Neovim versions test + auto-tag)
├── Makefile            # Convenience targets (test, lint, clean)
└── CONTRIBUTING.md     # Contributor guide and workflow reference
```

---

## Tech Stack & Runtime Environment

- **Target Runtime**: Neovim `>= 0.9.5` (Lua 5.1 / LuaJIT).
- **Node.js**: Required for running client-side preview export unit tests (`node --test`).
- **Optional Tools**:
  - `mmdc` (`@mermaid-js/mermaid-cli`) for diagram linting and rasterization.
  - `chafa` or a Kitty-compatible terminal for inline rendering.
- **Development Tools**:
  - `luacheck` (configured in `.luacheckrc`) for Lua linting.
  - `plenary.nvim` for Busted testing.

---

## Coding Standards & Style Conventions

1. **Lua Conventions**:
   - **Indentation**: 2 spaces (no tabs).
   - **Identifiers**: `snake_case` for functions, local variables, and file names; `PascalCase` for module namespaces or classes if applicable.
   - **Neovim API**: Prefer `vim.api.*` functions and `vim.uv` / `vim.loop` for file and process operations.
   - **Scope**: Keep module helpers `local` unless explicitly meant for public API or test assertions.
2. **Zero External Lua Dependencies**:
   - Never introduce external Lua rocks or plugin dependencies in `lua/mermaid/`.
   - Maintain pure-Lua implementations for HTTP request parsing and SSE broadcasting.
3. **Documentation Synchronization**:
   - Any additions or modifications to user commands, configuration keys, or default values MUST be kept in sync across:
     - `doc/mermaid.txt` (Vimdoc tags and options).
     - `README.md` (Configuration table and Command table).
4. **Notification & Logging**:
   - Use `vim.notify` with standard levels (`vim.log.levels.INFO`, `WARN`, `ERROR`).
   - Avoid spamming notifications in automated or headless test runs.

---

## Git Workflow & Conventions

- **Single-Main Workflow**: Development is based directly off `main`. There is no `develop` branch.
- **Branch Naming**:
  - `feat/short-description` — new features
  - `fix/short-description` — bug fixes
  - `refactor/short-description` — code restructure
  - `docs/short-description` — documentation updates
  - `ci/short-description` — CI/workflow changes
  - `test/short-description` — test-only changes
- **Commit Messages**: Follow [Conventional Commits](https://www.conventionalcommits.org/):
  - `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `ci:`.
- **Automated Releases**: CI automatically generates version tags and GitHub releases when commits land on `main`. Ensure PRs and commits are fully tested and clean.

---

## Testing & Verification

Always verify changes locally before committing:

1. **Run Full Test Suite**:
   ```bash
   make test
   ```
2. **Run Individual Test Suites**:
   - Preview export Node.js tests:
     ```bash
     node --test tests/preview_export.test.mjs
     ```
   - Plenary Busted Lua tests:
     ```bash
     nvim --headless -u tests/minimal_init.lua \
       -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
     ```
3. **Run Linter**:
   ```bash
   make lint
   # or directly:
   luacheck lua tests --ignore 631
   ```
4. **Clean Test Dependencies**:
   ```bash
   make clean
   ```
