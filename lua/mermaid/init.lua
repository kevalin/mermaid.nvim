local M = {}

M.config = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  -- Setup linting autocmds
  require("mermaid.lint").setup_autocmd()
end

return M
