     1|local M = {}
     2|local uv = vim.loop
     3|
     4|--- MIME type lookup table for static files
     5|local MIME_TYPES = {
     6|  html = "text/html",
     7|  htm = "text/html",
     8|  css = "text/css",
     9|  js = "application/javascript",
    10|  mjs = "application/javascript",
    11|  svg = "image/svg+xml",
    12|  png = "image/png",
    13|  ico = "image/x-icon",
    14|  json = "application/json",
    15|  txt = "text/plain",
    16|}
    17|
    18|--- Parse an HTTP request line and headers from a raw buffer.
    19|--- Returns {method, path, headers} or nil on parse failure.
    20|local function parse_request(data)
    21|  local header_end = data:find("\r\n\r\n", 1, true)
    22|  if not header_end then return nil end
    23|
    24|  local raw_headers = data:sub(1, header_end - 1)
    25|  local lines = {}
    26|  for line in raw_headers:gmatch("[^\r\n]+") do
    27|    lines[#lines + 1] = line
    28|  end
    29|
    30|  if #lines == 0 then return nil end
    31|
    32|  local method, path = lines[1]:match("^(%w+)%s+(%S+)%s+HTTP")
    33|  if not method or not path then return nil end
    34|
    35|  -- Parse header key-value pairs
    36|  local headers = {}
    37|  for i = 2, #lines do
    38|    local key, value = lines[i]:match("^([%w%-]+):%s*(.+)")
    39|    if key then headers[key:lower()] = value end
    40|  end
    41|
    42|  return { method = method, path = path, headers = headers }
    43|end
    44|
    45|--- Build an HTTP response string
    46|local function build_response(status, body, content_type, extra_headers)
    47|  local status_text = {
    48|    [200] = "OK",
    49|    [404] = "Not Found",
    50|    [500] = "Internal Server Error",
    51|  }
    52|  local lines = {
    53|    "HTTP/1.1 " .. status .. " " .. (status_text[status] or ""),
    54|    "Content-Type: " .. (content_type or "text/plain"),
    55|    "Content-Length: " .. #body,
    56|    "Connection: close",
    57|  }
    58|  if extra_headers then
    59|    for _, h in ipairs(extra_headers) do
    60|      lines[#lines + 1] = h
    61|    end
    62|  end
    63|  lines[#lines + 1] = ""
    64|  lines[#lines + 1] = body
    65|  return table.concat(lines, "\r\n")
    66|end
    67|
    68|--- Send an error response to the client
    69|local function send_error(client, status, message, content_type)
    70|  local response = build_response(status, message, content_type or "text/plain")
    71|  client:write(response, function() client:close() end)
    72|end
    73|
    74|--- Return the plugin root directory
    75|local function get_plugin_root()
    76|  local script_path = debug.getinfo(1, "S").source:sub(2)
    77|  return vim.fn.fnamemodify(script_path, ":h:h:h")
    78|end
    79|
    80|--------------------------------------------------------------------
    81|-- Route Handlers
    82|--------------------------------------------------------------------
    83|
    84|--- Handle the SSE event stream endpoint
    85|local function handle_sse(client, _req)
    86|  -- Must schedule for vim.fn.json_encode
    87|  vim.schedule(function()
    88|    local headers = "HTTP/1.1 200 OK\r\n" ..
    89|      "Content-Type: text/event-stream\r\n" ..
    90|      "Cache-Control: no-cache\r\n" ..
    91|      "Connection: keep-alive\r\n\r\n"
    92|    client:write(headers)
    93|
    94|    -- Send initial content
    95|    local safe_content = vim.fn.json_encode(M.current_content)
    96|    client:write("data: " .. safe_content .. "\n\n")
    97|
    98|    -- Register client for broadcasts
    99|    M.clients[client] = true
   100|
   101|    -- Keep connection alive; listen for close
   102|    client:read_start(function(err, chunk)
   103|      if err or not chunk then
   104|        M.clients[client] = nil
   105|        if not client:is_closing() then client:close() end
   106|      end
   107|      -- Ignore inbound data on SSE connection
   108|    end)
   109|  end)
   110|end
   111|
   112|--- Handle the index page and /content fallback
   113|local function handle_root(client, _req, path)
   114|  if path == "/" or path == "/index.html" then
   115|    local html = M.get_html_template()
   116|    if html then
   117|      client:write(build_response(200, html, MIME_TYPES.html), function()
   118|        client:close()
   119|      end)
   120|    else
   121|      send_error(client, 500, "Failed to load template", MIME_TYPES.plain)
   122|    end
   123|  elseif path == "/content" then
   124|    client:write(build_response(200, M.current_content, MIME_TYPES.plain), function()
   125|      client:close()
   126|    end)
   127|  else
   128|    send_error(client, 404, "Not Found")
   129|  end
   130|end
   131|
   132|--- Handle static file requests (CSS, JS, etc.)
   133|local function handle_static(client, _req, path)
   134|  local filename = path:sub(2) -- strip leading /
   135|  if filename == "" then filename = "index.html" end
   136|
   137|  -- Security: prevent directory traversal
   138|  if filename:find("%.%.") then
   139|    send_error(client, 404, "Not Found")
   140|    return
   141|  end
   142|
   143|  local f = io.open(get_plugin_root() .. "/static/" .. filename, "rb")
   144|  if not f then
   145|    send_error(client, 404, "Not Found")
   146|    return
   147|  end
   148|
   149|  local body = f:read("*a") or ""
   150|  f:close()
   151|
   152|  -- Determine MIME type from extension
   153|  local ext = filename:match("%.([%w]+)$")
   154|  local content_type = MIME_TYPES[ext] or MIME_TYPES.plain
   155|
   156|  client:write(build_response(200, body, content_type), function()
   157|    client:close()
   158|  end)
   159|end
   160|
   161|--------------------------------------------------------------------
   162|-- Public API
   163|--------------------------------------------------------------------
   164|
   165|M.port = nil
   166|M.server = nil
   167|M.current_content = "graph TD\nA[Loading...]"
   168|M.clients = {}
   169|M.monitor_timer = nil
   170|M.theme_mode = "light"  -- "light" or "dark"
   171|M._test_mode = false     -- Set true in tests to skip idle monitor
   172|
   173|--- Broadcast updated content to all connected SSE clients
   174|function M.broadcast(content)
   175|  local safe_content = vim.fn.json_encode(content)
   176|  local message = "data: " .. safe_content .. "\n\n"
   177|
   178|  for client, _ in pairs(M.clients) do
   179|    if not client:is_closing() then
   180|      client:write(message)
   181|    end
   182|  end
   183|end
   184|
   185|--- Set the theme mode (light/dark) for the preview page
   186|function M.set_theme_mode(mode)
   187|  M.theme_mode = (mode == "dark") and "dark" or "light"
   188|end
   189|
   190|--- Update the current diagram content and broadcast changes
   191|function M.set_content(content)
   192|  if M.current_content ~= content then
   193|    M.current_content = content
   194|    M.broadcast(content)
   195|  end
   196|end
   197|
   198|--- Start the HTTP server, return the assigned port
   199|function M.start_server()
   200|  if M.server then return M.port end
   201|
   202|  M.server = uv.new_tcp()
   203|  M.server:bind("127.0.0.1", 0)
   204|
   205|  local addr = M.server:getsockname()
   206|  M.port = addr.port
   207|
   208|  M.server:listen(128, function(err)
   209|    if err then
   210|      vim.schedule(function()
   211|        vim.notify("Mermaid: Listen error: " .. tostring(err), vim.log.levels.ERROR)
   212|      end)
   213|      return
   214|    end
   215|    M.start_monitoring()
   216|
   217|    local client = uv.new_tcp()
   218|    M.server:accept(client)
   219|
   220|    -- Optional: set TCP keepalive
   221|    client:keepalive(true, 30)
   222|
   223|    local data_buffer = ""
   224|    local req_timer = uv.new_timer()
   225|
   226|    -- Request timeout: close connection if headers don't arrive within 10s
   227|    req_timer:start(10000, 0, function()
   228|      if not client:is_closing() then client:close() end
   229|    end)
   230|
   231|    client:read_start(function(read_err, chunk)
   232|      if read_err or not chunk then
   233|        if not req_timer:is_closing() then req_timer:close() end
   234|        if not client:is_closing() then client:close() end
   235|        return
   236|      end
   237|
   238|      data_buffer = data_buffer .. chunk
   239|      local req = parse_request(data_buffer)
   240|
   241|      if req then
   242|        -- Stop the request timeout; we have a complete request
   243|        if not req_timer:is_closing() then
   244|          req_timer:stop()
   245|          req_timer:close()
   246|        end
   247|
   248|        M.last_access = os.time()
   249|
   250|        -- Route dispatch
   251|        if req.path == "/events" then
   252|          handle_sse(client, req)
   253|        elseif req.path:match("^/css/") or req.path:match("^/js/") then
   254|          handle_static(client, req, req.path)
   255|        elseif req.path == "/" or req.path == "/index.html" or req.path == "/content" then
   256|          handle_root(client, req, req.path)
   257|        else
   258|          handle_static(client, req, req.path)
   259|        end
   260|      end
   261|    end)
   262|  end)
   263|
   264|  return M.port
   265|end
   266|
   267|--- Start the idle monitor (auto-close server after 20s with no clients)
   268|function M.start_monitoring()
   269|  if M.monitor_timer or M._test_mode then return end
   270|
   271|  local idle_since = nil
   272|  M.monitor_timer = uv.new_timer()
   273|
   274|  M.monitor_timer:start(2000, 2000, vim.schedule_wrap(function()
   275|    if not M.server then
   276|      M.stop_server()
   277|      return
   278|    end
   279|
   280|    local client_count = 0
   281|    for _, _ in pairs(M.clients) do client_count = client_count + 1 end
   282|
   283|    if client_count == 0 then
   284|      if not idle_since then
   285|        idle_since = os.time()
   286|      elseif os.time() - idle_since > 20 then
   287|        vim.notify("Mermaid: Preview closed (no active clients)", vim.log.levels.INFO)
   288|        M.stop_server()
   289|      end
   290|    else
   291|      idle_since = nil
   292|    end
   293|  end))
   294|end
   295|
   296|--- Stop the server and clean up all resources
   297|function M.stop_server()
   298|  -- Close all SSE clients
   299|  for client, _ in pairs(M.clients) do
   300|    if not client:is_closing() then client:close() end
   301|  end
   302|  M.clients = {}
   303|
   304|  -- Stop monitor timer
   305|  if M.monitor_timer then
   306|    M.monitor_timer:stop()
   307|    if not M.monitor_timer:is_closing() then
   308|      M.monitor_timer:close()
   309|    end
   310|    M.monitor_timer = nil
   311|  end
   312|
   313|  -- Close server socket
   314|  if M.server then
   315|    if not M.server:is_closing() then
   316|      M.server:close()
   317|    end
   318|    M.server = nil
   319|    M.port = nil
   320|  end
   321|<<<<<<< HEAD
   322|end
   323|
   324|--- Get the effective theme mode (light/dark) for HTML preview.
   325|--- Derived from the theme name itself, NOT Neovim's background.
   326|--- This ensures the page CSS matches the chosen renderer theme.
   327|function M.get_effective_theme_mode()
   328|  local theme = require("mermaid").config.preview.theme
   329|  -- Explicit dark themes (mermaid.js + beautiful-mermaid)
   330|  if theme:match("dark") and not theme:match("light") then
   331|    return "dark"
   332|  end
   333|  if theme:match("night") and not theme:match("light") then
   334|    return "dark"
   335|  end
   336|  if theme:match("storm") then return "dark" end
   337|  if theme:match("dracula") then return "dark" end
   338|  if theme:match("mocha") then return "dark" end
   339|  if theme == "nord" then return "dark" end
   340|  return "light"
   341|=======
   342|>>>>>>> origin/main
   343|end
   344|
   345|--- Build the HTML template with injected renderer scripts
   346|function M.get_html_template()
   347|  local mermaid_config = require("mermaid").config
   348|  local renderer = mermaid_config.preview.renderer
   349|  local theme = mermaid_config.preview.theme
   350|
   351|  local scripts
   352|  if renderer == "beautiful-mermaid" then
   353|    scripts = [[
   354|  <script type="module">
   355|    import { renderMermaidSVG, THEMES, DEFAULTS } from 'https://esm.sh/beautiful-mermaid@1.1.3?exports=renderMermaidSVG,THEMES,DEFAULTS';
   356|    window.renderMermaidSVG = renderMermaidSVG;
   357|    window.BEAUTIFUL_THEMES = THEMES;
   358|    window.BEAUTIFUL_DEFAULTS = DEFAULTS;
   359|    window.rendererReady = true;
   360|  </script>]]
   361|  else
   362|    scripts = [[
   363|  <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
   364|  <script>
   365|    window.addEventListener('load', () => {
   366|        mermaid.initialize({ startOnLoad: false, theme: ']] .. theme .. [[' });
   367|        window.rendererReady = true;
   368|    });
   369|  </script>]]
   370|  end
   371|
   372|  local f = io.open(get_plugin_root() .. "/static/index.html", "r")
   373|  if not f then return nil end
   374|  local template = f:read("*a")
   375|  f:close()
   376|
   377|  template = template:gsub("{{RENDERER}}", renderer)
   378|  template = template:gsub("{{THEME}}", theme)
   379|<<<<<<< HEAD
   380|  template = template:gsub("{{THEME_MODE}}", M.get_effective_theme_mode())
   381|=======
   382|  template = template:gsub("{{THEME_MODE}}", M.theme_mode)
   383|>>>>>>> origin/main
   384|  template = template:gsub("{{SCRIPTS}}", scripts)
   385|
   386|  return template
   387|end
   388|
   389|return M
   390|