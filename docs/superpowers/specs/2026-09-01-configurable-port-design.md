# Design Spec: Configurable Server Port in mermaid.nvim

**Date**: 2026-09-01  
**Topic**: Configurable Server Port (`preview.port`)  
**Status**: Approved  

---

## 1. Overview

Currently, `mermaid.nvim` always binds the built-in HTTP server to a random ephemeral port via `uv.new_tcp():bind("127.0.0.1", 0)`. While this prevents port collisions by default, users may require a fixed port (e.g. for bookmarking, reverse proxy setups, firewall rules, or predictable browser tabs).

This specification introduces a configurable `preview.port` option while keeping random port allocation as the default when omitted, set to `0`, or set to `nil`.

---

## 2. Requirements & Behavior

1. **Configuration Schema**:
   - Add `port` to `preview` section in `require("mermaid").setup({ preview = { port = ... } })`.
   - Default value is `0` (or `nil` / omitted).
   - Any value `<= 0` or `nil` indicates that an available random port must be assigned by the operating system.
   - Any positive integer (e.g., `8080`, `3000`) instructs the server to bind to that exact port.

2. **Deterministic Port Collision Handling**:
   - If a specific port is requested and is unavailable / in use:
     - The server must not crash or leave unclosed TCP handles.
     - Emit a clear notification: `vim.notify("Mermaid: Port <port> is already in use or unavailable", vim.log.levels.ERROR)`.
     - `server.start_server()` returns `nil`.
     - `preview.lua` halts preview initialization cleanly (no browser launch, no floating panel opened).

3. **Backwards Compatibility**:
   - Calling `server.start_server()` without arguments maintains the existing behavior (binds to port 0).
   - Calling `server.start_server(0)` or `server.start_server(nil)` binds to port 0.
   - Existing configs without `preview.port` continue working unchanged.

---

## 3. Architecture & Detailed Changes

### 3.1 `lua/mermaid/init.lua`
Update default configuration table:
```lua
M.config = {
    format = {
        shift_width = 4,
    },
    lint = {
        enabled = true,
        command = "mmdc",
    },
    preview = {
        port = 0,                -- Port for preview server (0 or nil for random available port)
        renderer = "mermaid.js",
        theme = "default",
        beautiful_mermaid_path = nil,
    },
}
```

### 3.2 `lua/mermaid/server.lua`
Update `M.start_server(target_port)`:
1. Normalize `target_port`:
   ```lua
   local port_to_bind = (type(target_port) == "number" and target_port > 0) and target_port or 0
   ```
2. Bind TCP handle and check for errors:
   ```lua
   local success, err = pcall(function()
     return M.server:bind("127.0.0.1", port_to_bind)
   end)
   ```
   Or check libuv's return value directly from `M.server:bind("127.0.0.1", port_to_bind)`. In luv / `vim.loop`, `tcp:bind(...)` returns `0` (or true/nil) on success, or raises/returns an error code/string on failure.
   If bind fails:
   - Clean up: close `M.server` and set `M.server = nil`.
   - Notify error: `vim.notify(string.format("Mermaid: Port %d is already in use or unavailable (%s)", port_to_bind, tostring(err)), vim.log.levels.ERROR)`.
   - Return `nil`.
3. If bind succeeds, query `M.server:getsockname().port` to record the actual bound port (crucial when `port_to_bind == 0`).

### 3.3 `lua/mermaid/preview.lua`
In `M.preview()`:
1. Read configured port from `require("mermaid").config.preview.port`.
2. Pass it to `server.start_server(config_port)`.
3. If `not port`, stop execution immediately with early return.

### 3.4 Documentation Synchronization
- Update `doc/mermaid.txt` in the options table for `preview.port`.
- Update `README.md` in the Configuration code block and options description.

---

## 4. Testing Strategy

Add tests to `tests/server_spec.lua`:
1. **Random Port (Default / 0 / nil)**:
   - Calling `server.start_server()` or `server.start_server(0)` returns a valid positive port number.
2. **Custom Fixed Port**:
   - Calling `server.start_server(specific_port)` returns the exact specified port.
3. **Port In Use Error**:
   - When a port is already bound, attempting to start another server on that same port fails cleanly, returns `nil`, and emits an error notification.

---

## 5. Verification Plan

1. Run unit tests:
   ```bash
   nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
   ```
2. Run Luacheck:
   ```bash
   luacheck lua tests --ignore 631
   ```
3. Run Node tests:
   ```bash
   node --test tests/preview_export.test.mjs
   ```
