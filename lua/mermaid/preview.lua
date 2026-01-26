local M = {}
local server = require("mermaid.server")

local function update_content()
    local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    server.set_content(content)
end

function M.preview()
  -- Start server if not running
  local port = server.start_server()
  if not port then
      vim.notify("Mermaid: Failed to start server", vim.log.levels.ERROR)
      return
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

  -- Open browser
  if vim.ui.open then
      vim.ui.open(url)
  elseif vim.fn.has("mac") == 1 then
      vim.fn.system({"open", url})
  elseif vim.fn.executable("xdg-open") == 1 then
      vim.fn.system({"xdg-open", url})
  else
      vim.notify("Could not open preview: no opener found", vim.log.levels.ERROR)
  end
end

return M
