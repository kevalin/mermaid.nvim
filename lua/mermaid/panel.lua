     1|--- mermaid panel: Neovim floating window for preview controls
     2|--
     3|-- Shows: preview URL, renderer info, connection status, quick actions.
     4|-- Auto-opens when :MermaidPreview is called.
     5|local M = {}
     6|
     7|local namespace = vim.api.nvim_create_namespace("mermaid_panel")
     8|local buf = nil
     9|local win = nil
    10|
    11|local STATUS_SYMBOLS = {
    12|  connected    = "●",
    13|  disconnected = "○",
    14|  reconnecting = "◌",
    15|  stopped      = "×",
    16|}
    17|
    18|--- Window dimensions (relative to editor)
    19|local WIN_WIDTH = 44
    20|local WIN_HEIGHT = 10
    21|
    22|--- Re-render the panel content
    23|local function refresh()
    24|  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    25|
    26|  local server = require("mermaid.server")
    27|  local port = server.port or "—"
    28|  local url = port ~= "—" and ("http://localhost:" .. port) or "not running"
    29|  local renderer = require("mermaid").config.preview.renderer or "mermaid.js"
    30|<<<<<<< HEAD
    31|  local theme_mode = server.get_effective_theme_mode() or "light"
    32|=======
    33|  local theme_mode = server.theme_mode or "light"
    34|>>>>>>> origin/main
    35|  local client_count = 0
    36|  for _, _ in pairs(server.clients or {}) do client_count = client_count + 1 end
    37|  local status = server.server and "connected" or "stopped"
    38|  local status_sym = STATUS_SYMBOLS[status] or "?"
    39|
    40|  local lines = {
    41|    "  🧜 Mermaid Preview",
    42|    "",
    43|    "  " .. status_sym .. "  Status:      " .. status,
    44|    "  🔗  URL:         " .. url,
    45|    "  🎨  Renderer:    " .. renderer,
    46|    "  🌓  Theme:       " .. theme_mode,
    47|    "  👥  Clients:     " .. client_count,
    48|    "",
    49|    "  [o] Open browser  [c] Copy URL  [q] Close",
    50|  }
    51|
    52|  -- Temporarily allow modification for buffer updates
    53|  local was_modifiable = vim.api.nvim_buf_get_option(buf, "modifiable")
    54|  vim.api.nvim_buf_set_option(buf, "modifiable", true)
    55|  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    56|  if not was_modifiable then
    57|    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    58|  end
    59|
    60|  -- Highlight header
    61|  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    62|  vim.api.nvim_buf_add_highlight(buf, namespace, "Title", 0, 2, #lines[1])
    63|end
    64|
    65|--- Create the floating window
    66|function M.open(_url)
    67|  -- Close existing panel first
    68|  M.close()
    69|
    70|  -- Calculate position (top-right corner)
    71|  local uis = vim.api.nvim_list_uis()
    72|  local ui = uis and uis[1]
    73|  if not ui then
    74|    -- Headless mode or no UI: silently skip
    75|    return
    76|  end
    77|  local row = 1
    78|  local col = math.max(0, ui.width - WIN_WIDTH - 1)
    79|
    80|  buf = vim.api.nvim_create_buf(false, true)
    81|  win = vim.api.nvim_open_win(buf, false, {
    82|    relative = "editor",
    83|    width = WIN_WIDTH,
    84|    height = WIN_HEIGHT,
    85|    row = row,
    86|    col = col,
    87|    style = "minimal",
    88|    border = "rounded",
    89|    title = " mermaid.nvim ",
    90|    title_pos = "center",
    91|  })
    92|
    93|  vim.api.nvim_win_set_option(win, "winhl", "Normal:NormalFloat,FloatBorder:FloatBorder")
    94|  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    95|
    96|  refresh()
    97|
    98|  vim.api.nvim_buf_set_option(buf, "modifiable", false)
    99|  vim.api.nvim_buf_set_keymap(buf, "n", "o", ":MermaidPreview<CR>", { noremap = true, silent = true })
   100|  vim.api.nvim_buf_set_keymap(buf, "n", "c", ":call MermaidCopyURL()<CR>", { noremap = true, silent = true })
   101|  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":lua require('mermaid.panel').close()<CR>", { noremap = true, silent = true })
   102|end
   103|
   104|--- Update panel content (called periodically or on state changes)
   105|function M.update()
   106|  refresh()
   107|end
   108|
   109|--- Close the floating window
   110|function M.close()
   111|  if win and vim.api.nvim_win_is_valid(win) then
   112|    vim.api.nvim_win_close(win, true)
   113|  end
   114|  if buf and vim.api.nvim_buf_is_valid(buf) then
   115|    vim.api.nvim_buf_delete(buf, { force = true })
   116|  end
   117|  win = nil
   118|  buf = nil
   119|end
   120|
   121|--- Check if the panel is currently open
   122|function M.is_open()
   123|  return win ~= nil and vim.api.nvim_win_is_valid(win)
   124|end
   125|
   126|--- Set up a timer to refresh the panel periodically
   127|local refresh_timer = nil
   128|function M.start_auto_refresh()
   129|  if refresh_timer then return end
   130|  refresh_timer = vim.defer_fn(function()
   131|    if M.is_open() then
   132|      refresh()
   133|      M.start_auto_refresh()
   134|    else
   135|      refresh_timer = nil
   136|    end
   137|  end, 2000)
   138|end
   139|
   140|return M
   141|