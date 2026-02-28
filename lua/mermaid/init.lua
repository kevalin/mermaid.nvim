local M = {}

M.config = {
    format = {
        shift_width = 4, -- Default to 4 spaces
    },
    lint = {
        enabled = true,
        command = "mmdc",
    },
    preview = {
        renderer = "mermaid.js", -- Options: "mermaid.js", "beautiful-mermaid"
        theme = "default",       -- Theme for the renderer
        beautiful_mermaid_path = nil, -- Path to beautiful-mermaid (e.g. /usr/local/lib/node_modules/beautiful-mermaid)
    },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  if M.config.lint.enabled then
      -- Setup linting autocmds
      require("mermaid.lint").setup_autocmd()
  end
end

return M
