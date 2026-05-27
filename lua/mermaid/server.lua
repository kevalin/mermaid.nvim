local M = {}
local uv = vim.loop

--- MIME type lookup table for static files
local MIME_TYPES = {
  html = "text/html",
  htm = "text/html",
  css = "text/css",
  js = "application/javascript",
  mjs = "application/javascript",
  svg = "image/svg+xml",
  png = "image/png",
  ico = "image/x-icon",
  json = "application/json",
  txt = "text/plain",
}

--- Parse an HTTP request line and headers from a raw buffer.
--- Returns {method, path, headers} or nil on parse failure.
local function parse_request(data)
  local header_end = data:find("\r\n\r\n", 1, true)
  if not header_end then return nil end

  local raw_headers = data:sub(1, header_end - 1)
  local lines = {}
  for line in raw_headers:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end

  if #lines == 0 then return nil end

  local method, path = lines[1]:match("^(%w+)%s+(%S+)%s+HTTP")
  if not method or not path then return nil end

  -- Parse header key-value pairs
  local headers = {}
  for i = 2, #lines do
    local key, value = lines[i]:match("^([%w%-]+):%s*(.+)")
    if key then headers[key:lower()] = value end
  end

  return { method = method, path = path, headers = headers }
end

--- Build an HTTP response string
local function build_response(status, body, content_type, extra_headers)
  local status_text = {
    [200] = "OK",
    [404] = "Not Found",
    [500] = "Internal Server Error",
  }
  local lines = {
    "HTTP/1.1 " .. status .. " " .. (status_text[status] or ""),
    "Content-Type: " .. (content_type or "text/plain"),
    "Content-Length: " .. #body,
    "Connection: close",
  }
  if extra_headers then
    for _, h in ipairs(extra_headers) do
      lines[#lines + 1] = h
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = body
  return table.concat(lines, "\r\n")
end

--- Send an error response to the client
local function send_error(client, status, message, content_type)
  local response = build_response(status, message, content_type or "text/plain")
  client:write(response, function() client:close() end)
end

--- Return the plugin root directory
local function get_plugin_root()
  local script_path = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(script_path, ":h:h:h")
end

--------------------------------------------------------------------
-- Route Handlers
--------------------------------------------------------------------

--- Handle the SSE event stream endpoint
local function handle_sse(client, _req)
  -- Must schedule for vim.fn.json_encode
  vim.schedule(function()
    local headers = "HTTP/1.1 200 OK\r\n" ..
      "Content-Type: text/event-stream\r\n" ..
      "Cache-Control: no-cache\r\n" ..
      "Connection: keep-alive\r\n\r\n"
    client:write(headers)

    -- Send initial content
    local safe_content = vim.fn.json_encode(M.current_content)
    client:write("data: " .. safe_content .. "\n\n")

    -- Register client for broadcasts
    M.clients[client] = true

    -- Keep connection alive; listen for close
    client:read_start(function(err, chunk)
      if err or not chunk then
        M.clients[client] = nil
        if not client:is_closing() then client:close() end
      end
      -- Ignore inbound data on SSE connection
    end)
  end)
end

--- Handle the index page and /content fallback
local function handle_root(client, _req, path)
  if path == "/" or path == "/index.html" then
    local html = M.get_html_template()
    if html then
      client:write(build_response(200, html, MIME_TYPES.html), function()
        client:close()
      end)
    else
      send_error(client, 500, "Failed to load template", MIME_TYPES.plain)
    end
  elseif path == "/content" then
    client:write(build_response(200, M.current_content, MIME_TYPES.plain), function()
      client:close()
    end)
  else
    send_error(client, 404, "Not Found")
  end
end

--- Handle static file requests (CSS, JS, etc.)
local function handle_static(client, _req, path)
  local filename = path:sub(2) -- strip leading /
  if filename == "" then filename = "index.html" end

  -- Security: prevent directory traversal
  if filename:find("%.%.") then
    send_error(client, 404, "Not Found")
    return
  end

  local f = io.open(get_plugin_root() .. "/static/" .. filename, "rb")
  if not f then
    send_error(client, 404, "Not Found")
    return
  end

  local body = f:read("*a") or ""
  f:close()

  -- Determine MIME type from extension
  local ext = filename:match("%.([%w]+)$")
  local content_type = MIME_TYPES[ext] or MIME_TYPES.plain

  client:write(build_response(200, body, content_type), function()
    client:close()
  end)
end

--------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------

M.port = nil
M.server = nil
M.current_content = "graph TD\nA[Loading...]"
M.clients = {}
M.monitor_timer = nil
M.theme_mode = "light"  -- "light" or "dark"
M._test_mode = false     -- Set true in tests to skip idle monitor

--- Broadcast updated content to all connected SSE clients
function M.broadcast(content)
  local safe_content = vim.fn.json_encode(content)
  local message = "data: " .. safe_content .. "\n\n"

  for client, _ in pairs(M.clients) do
    if not client:is_closing() then
      client:write(message)
    end
  end
end

--- Set the theme mode (light/dark) for the preview page
function M.set_theme_mode(mode)
  M.theme_mode = (mode == "dark") and "dark" or "light"
end

--- Update the current diagram content and broadcast changes
function M.set_content(content)
  if M.current_content ~= content then
    M.current_content = content
    M.broadcast(content)
  end
end

--- Start the HTTP server, return the assigned port
function M.start_server()
  if M.server then return M.port end

  M.server = uv.new_tcp()
  M.server:bind("127.0.0.1", 0)

  local addr = M.server:getsockname()
  M.port = addr.port

  M.server:listen(128, function(err)
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

  return M.port
end

--- Start the idle monitor (auto-close server after 20s with no clients)
function M.start_monitoring()
  if M.monitor_timer or M._test_mode then return end

  local idle_since = nil
  M.monitor_timer = uv.new_timer()

  M.monitor_timer:start(2000, 2000, vim.schedule_wrap(function()
    if not M.server then
      M.stop_server()
      return
    end

    local client_count = 0
    for _, _ in pairs(M.clients) do client_count = client_count + 1 end

    if client_count == 0 then
      if not idle_since then
        idle_since = os.time()
      elseif os.time() - idle_since > 20 then
        vim.notify("Mermaid: Preview closed (no active clients)", vim.log.levels.INFO)
        M.stop_server()
      end
    else
      idle_since = nil
    end
  end))
end

--- Stop the server and clean up all resources
function M.stop_server()
  -- Close all SSE clients
  for client, _ in pairs(M.clients) do
    if not client:is_closing() then client:close() end
  end
  M.clients = {}

  -- Stop monitor timer
  if M.monitor_timer then
    M.monitor_timer:stop()
    if not M.monitor_timer:is_closing() then
      M.monitor_timer:close()
    end
    M.monitor_timer = nil
  end

  -- Close server socket
  if M.server then
    if not M.server:is_closing() then
      M.server:close()
    end
    M.server = nil
    M.port = nil
  end
end

--- Get the effective theme mode (light/dark) for HTML preview.
--- Derived from the theme name itself, NOT Neovim's background.
--- This ensures the page CSS matches the chosen renderer theme.
function M.get_effective_theme_mode()
  local theme = require("mermaid").config.preview.theme
  -- Explicit dark themes (mermaid.js + beautiful-mermaid)
  if theme:match("dark") and not theme:match("light") then
    return "dark"
  end
  if theme:match("night") and not theme:match("light") then
    return "dark"
  end
  if theme:match("storm") then return "dark" end
  if theme:match("dracula") then return "dark" end
  if theme:match("mocha") then return "dark" end
  if theme == "nord" then return "dark" end
  return "light"
end

--- Build the HTML template with injected renderer scripts
function M.get_html_template()
  local mermaid_config = require("mermaid").config
  local renderer = mermaid_config.preview.renderer
  local theme = mermaid_config.preview.theme

  local scripts
  if renderer == "beautiful-mermaid" then
    scripts = [[
  <script type="module">
    import { renderMermaidSVG, THEMES, DEFAULTS } from 'https://esm.sh/beautiful-mermaid@1.1.3?exports=renderMermaidSVG,THEMES,DEFAULTS';
    window.renderMermaidSVG = renderMermaidSVG;
    window.BEAUTIFUL_THEMES = THEMES;
    window.BEAUTIFUL_DEFAULTS = DEFAULTS;
    window.rendererReady = true;
  </script>]]
  else
    scripts = [[
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
  <script>
    window.addEventListener('load', () => {
        mermaid.initialize({ startOnLoad: false, theme: ']] .. theme .. [[' });
        window.rendererReady = true;
    });
  </script>]]
  end

  local f = io.open(get_plugin_root() .. "/static/index.html", "r")
  if not f then return nil end
  local template = f:read("*a")
  f:close()

  template = template:gsub("{{RENDERER}}", renderer)
  template = template:gsub("{{THEME}}", theme)
  template = template:gsub("{{THEME_MODE}}", M.get_effective_theme_mode())
  template = template:gsub("{{SCRIPTS}}", scripts)

  return template
end

return M
