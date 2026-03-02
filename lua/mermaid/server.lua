local M = {}
local uv = vim.loop

local function get_plugin_root()
  local script_path = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(script_path, ":h:h:h")
end


M.port = nil
M.server = nil
M.current_content = "graph TD\nA[Loading...]"
M.clients = {}

function M.broadcast(content)
    -- Format as SSE data: "data: <json_encoded_content>\n\n"
    -- Only graph content changes usually.
    -- We'll just send raw text line by line or json-encoded.
    -- JSON is safer for newlines.
    local safe_content = vim.fn.json_encode(content)
    local message = "data: " .. safe_content .. "\n\n"
    
    for client, _ in pairs(M.clients) do
        if not client:is_closing() then
            client:write(message)
        end
    end
end

-- Removed get_beautiful_mermaid_root as we now use CDN for all dependencies

function M.start_server()
  if M.server then return M.port end

  M.server = uv.new_tcp()
  -- Bind to localhost on a random available port (0)
  M.server:bind("127.0.0.1", 0)
  
  -- Get the assigned port
  local addr = M.server:getsockname()
  M.port = addr.port

  M.server:listen(128, function(err)
    assert(not err, err)
    
    -- Start monitoring for idle timeout once we start listening
    -- We assume client will connect shortly. 
    -- If no client connects within 5s, it will shutdown, which is acceptable behavior.
    M.start_monitoring()
    
    local client = uv.new_tcp()
    M.server:accept(client)
    
    local data_buffer = ""

    client:read_start(function(err, chunk)
      if err or not chunk then
        client:close()
        return
      end
      
      data_buffer = data_buffer .. chunk
      
      -- Simple HTTP parsing (very basic)
      -- We assume GET requests
      if data_buffer:match("\r\n\r\n") then
          -- Request complete
          M.last_access = os.time()  -- Reset idle timer
          
          local method, path = data_buffer:match("^(%w+)%s+(%S+)%s+HTTP")
          
          if path == "/events" then
             -- SSE endpoint
             -- E5560: Must schedule this because we use vim.fn.json_encode
             vim.schedule(function()
                 local headers = "HTTP/1.1 200 OK\r\n" ..
                                 "Content-Type: text/event-stream\r\n" ..
                                 "Cache-Control: no-cache\r\n" ..
                                 "Connection: keep-alive\r\n\r\n"
                 
                 client:write(headers)
                 
                 -- Send initial content
                 local safe_content = vim.fn.json_encode(M.current_content)
                 client:write("data: " .. safe_content .. "\n\n")
                 
                 -- Add to clients list
                 M.clients[client] = true
                 vim.schedule(function()
                    vim.notify("Mermaid: SSE Client connected", vim.log.levels.DEBUG)
                 end)
                 
                 -- Remove on close
                 client:read_start(function(err, chunk)
                     if err or not chunk then
                          M.clients[client] = nil
                          client:close()
                          vim.schedule(function()
                             vim.notify("Mermaid: SSE Client disconnected", vim.log.levels.DEBUG)
                          end)
                     end
                     -- Ignore incoming data on SSE connection
                 end)
             end)
             
             -- DO NOT close client here, it stays open
             return
          end

          local response_body = ""
          local headers = "HTTP/1.1 200 OK\r\nConnection: close\r\n"
          
          if path == "/" or path == "/index.html" then
              response_body = M.get_html_template()
              headers = headers .. "Content-Type: text/html\r\n"
          elseif path == "/content" then
              -- Fallback for polling if needed, or initial load
              response_body = M.current_content
              headers = headers .. "Content-Type: text/plain\r\n"
          else
              -- Static files catch-all (index.html, CSS, and our own JS)
              local filename = path:sub(2)
              if filename == "" then filename = "index.html" end
              local f = io.open(get_plugin_root() .. "/static/" .. filename, "rb")
              if f then
                  response_body = f:read("*a") or ""
                  f:close()
                  if filename:match("%.js$") or filename:match("%.mjs$") then
                      headers = headers .. "Content-Type: application/javascript\r\n"
                  elseif filename:match("%.css$") then
                      headers = headers .. "Content-Type: text/css\r\n"
                  elseif filename:match("%.html$") then
                      headers = headers .. "Content-Type: text/html\r\n"
                  else
                      headers = headers .. "Content-Type: application/octet-stream\r\n"
                  end
              else
                  headers = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n"
                  response_body = "Not Found"
              end
          end
          
          headers = headers .. "Content-Length: " .. #response_body .. "\r\n\r\n"
          
          client:write(headers .. response_body, function()
             client:close()
          end)
      end
    end)
  end)
  
  return M.port
end

M.monitor_timer = nil

function M.start_monitoring()
    if M.monitor_timer then return end
    
    local idle_since = nil
    
    M.monitor_timer = uv.new_timer()
    -- Check every 2 seconds
    M.monitor_timer:start(2000, 2000, vim.schedule_wrap(function()
        -- If server stopped unexpectedly, cleanup timer
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

function M.stop_server()
    if M.monitor_timer then
        M.monitor_timer:stop()
        M.monitor_timer:close()
        M.monitor_timer = nil
    end

    if M.server then
        M.server:close()
        M.server = nil
        M.port = nil
    end
end


function M.set_content(content)
    if M.current_content ~= content then
        M.current_content = content
        M.broadcast(content)
    end
end

function M.get_html_template()
    local mermaid_config = require("mermaid").config
    local renderer = mermaid_config.preview.renderer
    local theme = mermaid_config.preview.theme

    local scripts = ""
    if (renderer == "beautiful-mermaid") then
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
    if not f then return "Error: static/index.html not found" end
    local template = f:read("*a")
    f:close()

    template = template:gsub("{{RENDERER}}", renderer)
    template = template:gsub("{{THEME}}", theme)
    template = template:gsub("{{SCRIPTS}}", scripts)

    return template
end

return M
