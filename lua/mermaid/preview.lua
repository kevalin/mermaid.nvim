local M = {}
local server = require("mermaid.server")
local panel = require("mermaid.panel")

--- Detect Neovim background and map to a CSS class name
local function detect_theme_mode()
  local bg = vim.o.background or "light"
  if bg == "dark" then return "dark" end
  return "light"
end

local function update_content()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local content = table.concat(lines, "\n")
    content = require("mermaid.diagram").extract(content)
    server.set_content(content)
end

function M.preview()
  -- Sync theme mode from Neovim to server
  server.set_theme_mode(detect_theme_mode())

  -- Start server if not running
  local mermaid_config = require("mermaid")
  local port, bind_err = server.start_server()
  if not port then
      if bind_err then
          vim.notify("Mermaid: Failed to bind to port " .. mermaid_config.config.preview.port .. " (" .. bind_err .. "). Falling back to auto-assigned port.", vim.log.levels.WARN)
          server.stop_server()
          mermaid_config.config.preview.port = 0
          port, bind_err = server.start_server()
          if not port then
              vim.notify("Mermaid: Failed to start server: " .. (bind_err or "unknown error"), vim.log.levels.ERROR)
              return
          end
      else
          vim.notify("Mermaid: Failed to start server: no port available", vim.log.levels.ERROR)
          return
      end
  end

  update_content()

  -- Setup autocmd to update content
  local bufnr = vim.api.nvim_get_current_buf()
  local group = vim.api.nvim_create_augroup("MermaidLivePreview-" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI", "BufWritePost"}, {
      group = group,
      buffer = bufnr,
      callback = function()
          update_content()
      end
  })

  local url = "http://localhost:" .. port
  vim.notify("Mermaid: Live Preview at " .. url, vim.log.levels.INFO)

  -- Open floating panel
  panel.open(url)
  panel.start_auto_refresh()

  -- Open browser
  local uname = vim.loop.os_uname().sysname
  if uname == "Darwin" then
      -- Force 'open' via shell on macOS to avoid Code -600 (LaunchServices) errors
      -- that can happen with vim.ui.open or vim.fn.system in some envs.
      os.execute("open '" .. url .. "'")
  elseif vim.ui.open then
      vim.ui.open(url)
  elseif vim.fn.executable("xdg-open") == 1 then
      vim.fn.system({"xdg-open", url})
  elseif vim.fn.executable("wslview") == 1 then
      vim.fn.system({"wslview", url})
  else
      vim.notify("Could not open preview: no opener found", vim.log.levels.ERROR)
  end


  -- Autocleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
          server.stop_server()
      end
  })

  -- Sync background changes to preview
  vim.api.nvim_create_autocmd("OptionSet", {
      group = group,
      pattern = "background",
      callback = function()
          local new_mode = detect_theme_mode()
          if server.theme_mode ~= new_mode then
              server.set_theme_mode(new_mode)
              -- Force a content re-broadcast to trigger page refresh with new theme
              update_content()
          end
      end
  })

  -- Cleanup on buffer close
  vim.api.nvim_create_autocmd("BufDelete", {
      group = group,
      buffer = bufnr,
      callback = function()
          -- Don't stop the server - other buffers might use it
      end
  })
end

return M
