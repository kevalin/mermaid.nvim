--- mermaid panel: Neovim floating window for preview controls
--
-- Shows: preview URL, renderer info, connection status, quick actions.
-- Auto-opens when :MermaidPreview is called.
local M = {}

local namespace = vim.api.nvim_create_namespace("mermaid_panel")
local buf = nil
local win = nil

local STATUS_SYMBOLS = {
  connected    = "●",
  disconnected = "○",
  reconnecting = "◌",
  stopped      = "×",
}

--- Window dimensions (relative to editor)
local WIN_WIDTH = 44
local WIN_HEIGHT = 10

--- Re-render the panel content
local function refresh()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local server = require("mermaid.server")
  local port = server.port or "—"
  local url = port ~= "—" and ("http://localhost:" .. port) or "not running"
  local renderer = require("mermaid").config.preview.renderer or "mermaid.js"
  local theme_mode = server.get_effective_theme_mode() or "light"
  local client_count = 0
  for _, _ in pairs(server.clients or {}) do client_count = client_count + 1 end
  local status = server.server and "connected" or "stopped"
  local status_sym = STATUS_SYMBOLS[status] or "?"

  local lines = {
    "  🧜 Mermaid Preview",
    "",
    "  " .. status_sym .. "  Status:      " .. status,
    "  🔗  URL:         " .. url,
    "  🎨  Renderer:    " .. renderer,
    "  🌓  Theme:       " .. theme_mode,
    "  👥  Clients:     " .. client_count,
    "",
    "  [o] Open browser  [c] Copy URL  [q] Close",
  }

  -- Temporarily allow modification for buffer updates
  local was_modifiable = vim.api.nvim_buf_get_option(buf, "modifiable")
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if not was_modifiable then
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
  end

  -- Highlight header
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, namespace, "Title", 0, 2, #lines[1])
end

--- Create the floating window
function M.open(_url)
  -- Close existing panel first
  M.close()

  -- Calculate position (top-right corner)
  local uis = vim.api.nvim_list_uis()
  local ui = uis and uis[1]
  if not ui then
    -- Headless mode or no UI: silently skip
    return
  end
  local row = 1
  local col = math.max(0, ui.width - WIN_WIDTH - 1)

  buf = vim.api.nvim_create_buf(false, true)
  win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = WIN_WIDTH,
    height = WIN_HEIGHT,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " mermaid.nvim ",
    title_pos = "center",
  })

  vim.api.nvim_win_set_option(win, "winhl", "Normal:NormalFloat,FloatBorder:FloatBorder")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  refresh()

  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_keymap(buf, "n", "o", ":MermaidPreview<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "c", ":call MermaidCopyURL()<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":lua require('mermaid.panel').close()<CR>", { noremap = true, silent = true })
end

--- Update panel content (called periodically or on state changes)
function M.update()
  refresh()
end

--- Close the floating window
function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  win = nil
  buf = nil
end

--- Check if the panel is currently open
function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

--- Set up a timer to refresh the panel periodically
local refresh_timer = nil
function M.start_auto_refresh()
  if refresh_timer then return end
  refresh_timer = vim.defer_fn(function()
    if M.is_open() then
      refresh()
      M.start_auto_refresh()
    else
      refresh_timer = nil
    end
  end, 2000)
end

return M
