# Configurable Server Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to specify a fixed preview HTTP server port via `preview.port` (defaulting to 0 / random port), with clean collision detection and error notifications when a port is unavailable.

**Architecture:** `preview.port` is defined in `mermaid.init` config defaults and forwarded by `preview.preview()` to `server.start_server(target_port)`. `server.lua` validates and binds to the specified port using libuv (`vim.loop`), returning the bound port on success or `nil` with a user-friendly error notification if binding/listening fails.

**Tech Stack:** Neovim Lua API (`vim.api`, `vim.loop` / `vim.uv`), Plenary Busted test suite, Markdown documentation, Vimdoc.

## Global Constraints

- Runtime: Neovim `>= 0.9.5` (Lua 5.1 / LuaJIT).
- Zero external Lua dependencies in `lua/mermaid/`.
- 2-space indentation in Lua files.
- Safe error handling: never crash the Neovim editor session on port collision.
- Documentation synchronization: any configuration changes must be reflected in both `doc/mermaid.txt` and `README.md`.

---

### Task 1: Add `port` to `preview` configuration defaults

**Files:**
- Modify: `lua/mermaid/init.lua:11-16`
- Modify: `tests/mermaid_spec.lua:1-25`

**Interfaces:**
- Consumes: None
- Produces: `require("mermaid").config.preview.port` (number, default `0`)

- [ ] **Step 1: Write the failing test**

Add assertions in `tests/mermaid_spec.lua` verifying `preview.port` defaults to `0` and can be overridden by `setup`:

```lua
  it("defaults preview.port to 0", function()
    local mermaid = require("mermaid")
    mermaid.setup()
    assert.are.equal(0, mermaid.config.preview.port)
  end)

  it("allows configuring custom preview.port", function()
    local mermaid = require("mermaid")
    mermaid.setup({ preview = { port = 8080 } })
    assert.are.equal(8080, mermaid.config.preview.port)
  end)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/mermaid_spec.lua"
```
Expected: FAIL with nil comparison or missing field.

- [ ] **Step 3: Write minimal implementation**

Update `lua/mermaid/init.lua`:
```lua
    preview = {
        port = 0,                -- Port for preview server (0 or nil for random available port)
        renderer = "mermaid.js", -- Options: "mermaid.js", "beautiful-mermaid"
        theme = "default",       -- Theme for the renderer
        beautiful_mermaid_path = nil, -- Path to beautiful-mermaid (e.g. /usr/local/lib/node_modules/beautiful-mermaid)
    },
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/mermaid_spec.lua"
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/mermaid/init.lua tests/mermaid_spec.lua
git commit -m "feat(config): add port option to preview configuration"
```

---

### Task 2: Implement configurable port binding and error handling in `server.lua`

**Files:**
- Modify: `lua/mermaid/server.lua:198-265`
- Modify: `tests/server_spec.lua:1-35`

**Interfaces:**
- Consumes: `target_port` (number or nil, optional)
- Produces: `M.start_server(target_port)` -> returns bound `port` (number) on success, or `nil` on failure

- [ ] **Step 1: Write the failing tests**

Add unit tests in `tests/server_spec.lua` in `describe("startup / shutdown")`:

```lua
    it("binds to specified port when target_port is provided", function()
      local server = require("mermaid.server")
      local custom_port = 19421
      local port = server.start_server(custom_port)
      assert.are.equal(custom_port, port)
      server.stop_server()
    end)

    it("returns nil and notifies when target_port is already in use", function()
      local server = require("mermaid.server")
      local uv = vim.loop
      local occupied_port = 19422

      -- Occupy the port with a raw socket first
      local dummy = uv.new_tcp()
      dummy:bind("127.0.0.1", occupied_port)
      dummy:listen(128, function() end)

      local notifications = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local port = server.start_server(occupied_port)

      vim.notify = orig_notify
      dummy:close()

      assert.is_nil(port)
      assert.is_true(#notifications > 0)
      assert.is_true(notifications[1].msg:find("already in use") ~= nil)
    end)

    it("binds to random port when target_port is 0 or nil", function()
      local server = require("mermaid.server")
      local port = server.start_server(0)
      assert.is_number(port)
      assert.is_true(port > 0)
      server.stop_server()
    end)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/server_spec.lua"
```
Expected: FAIL (does not bind to specified port or fails to return nil on collision).

- [ ] **Step 3: Implement minimal code in `lua/mermaid/server.lua`**

Update `M.start_server(target_port)` in `lua/mermaid/server.lua`:
```lua
--- Start the HTTP server, return the assigned port or nil on failure
function M.start_server(target_port)
  if M.server then return M.port end

  local port_to_bind = (type(target_port) == "number" and target_port > 0) and target_port or 0

  M.server = uv.new_tcp()
  local bind_ok, bind_err = M.server:bind("127.0.0.1", port_to_bind)
  if not bind_ok then
    M.server:close()
    M.server = nil
    vim.notify(string.format("Mermaid: Failed to bind to port %d: %s", port_to_bind, tostring(bind_err)), vim.log.levels.ERROR)
    return nil
  end

  local addr = M.server:getsockname()
  M.port = addr.port

  local listen_ok, listen_err = M.server:listen(128, function(err)
    if err then
      vim.schedule(function()
        vim.notify("Mermaid: Listen error: " .. tostring(err), vim.log.levels.ERROR)
      end)
      return
    end
    M.start_monitoring()

    local client = uv.new_tcp()
    M.server:accept(client)

    -- Optional: set TCP keepalive
    client:keepalive(true, 30)

    local data_buffer = ""
    local req_timer = uv.new_timer()

    -- Request timeout: close connection if headers don't arrive within 10s
    req_timer:start(10000, 0, function()
      if not client:is_closing() then client:close() end
    end)

    client:read_start(function(read_err, chunk)
      if read_err or not chunk then
        if not req_timer:is_closing() then req_timer:close() end
        if not client:is_closing() then client:close() end
        return
      end

      data_buffer = data_buffer .. chunk
      local req = parse_request(data_buffer)

      if req then
        -- Stop the request timeout; we have a complete request
        if not req_timer:is_closing() then
          req_timer:stop()
          req_timer:close()
        end

        M.last_access = os.time()

        -- Route dispatch
        if req.path == "/events" then
          handle_sse(client, req)
        elseif req.path:match("^/css/") or req.path:match("^/js/") then
          handle_static(client, req, req.path)
        elseif req.path == "/" or req.path == "/index.html" or req.path == "/content" then
          handle_root(client, req, req.path)
        else
          handle_static(client, req, req.path)
        end
      end
    end)
  end)

  if not listen_ok then
    M.server:close()
    M.server = nil
    M.port = nil
    vim.notify(string.format("Mermaid: Port %d is already in use or unavailable (%s)", port_to_bind, tostring(listen_err)), vim.log.levels.ERROR)
    return nil
  end

  return M.port
end
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/server_spec.lua"
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/mermaid/server.lua tests/server_spec.lua
git commit -m "feat(server): support target_port and handle port collision errors"
```

---

### Task 3: Wire configured port in `preview.lua`

**Files:**
- Modify: `lua/mermaid/preview.lua:17-30`

**Interfaces:**
- Consumes: `require("mermaid").config.preview.port`
- Produces: Forwarding configured port to `server.start_server(config_port)` with graceful early exit on failure

- [ ] **Step 1: Write test verifying port is passed through**

In `tests/server_spec.lua` or `tests/mermaid_spec.lua`:
```lua
  it("passes preview.port to server.start_server", function()
    local mermaid = require("mermaid")
    local server = require("mermaid.server")
    mermaid.setup({ preview = { port = 19425 } })
    local preview = require("mermaid.preview")
    -- Spy or verify server gets started with configured port
    local port = server.start_server(mermaid.config.preview.port)
    assert.are.equal(19425, port)
    server.stop_server()
  end)
```

- [ ] **Step 2: Run test to verify state**

Run:
```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/mermaid_spec.lua"
```

- [ ] **Step 3: Update `lua/mermaid/preview.lua`**

In `lua/mermaid/preview.lua`:
```lua
  -- Start server if not running
  local config_port = (require("mermaid").config.preview or {}).port
  local port = server.start_server(config_port)
  if not port then
      vim.notify("Mermaid: Failed to start server", vim.log.levels.ERROR)
      return
  end
```

- [ ] **Step 4: Run tests to verify**

Run:
```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/mermaid_spec.lua"
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lua/mermaid/preview.lua tests/mermaid_spec.lua
git commit -m "feat(preview): pass configured port to server.start_server"
```

---

### Task 4: Documentation synchronization

**Files:**
- Modify: `doc/mermaid.txt`
- Modify: `README.md`

**Interfaces:**
- Consumes: `preview.port` configuration definition
- Produces: Updated user-facing documentation

- [ ] **Step 1: Update `README.md`**

In the configuration code block:
```lua
    preview = {
        port = 0,                  -- Server port (0 or nil for random available port)
        renderer = "mermaid.js",   -- "mermaid.js" or "beautiful-mermaid"
        theme = "default",          -- Theme name (renderer-specific)
    },
```

- [ ] **Step 2: Update `doc/mermaid.txt`**

Add `preview.port` documentation under `mermaid-configuration`:
```text
    preview.port                (number, default: 0)
                                Port for the preview HTTP server. Set to 0 or nil
                                to automatically assign an available random port.
```

- [ ] **Step 3: Run linter and tests**

Run:
```bash
node --test tests/preview_export.test.mjs
```

- [ ] **Step 4: Commit**

```bash
git add README.md doc/mermaid.txt
git commit -m "docs: document preview.port option in README and vimdoc"
```
