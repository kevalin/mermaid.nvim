local M = {}

local namespace = vim.api.nvim_create_namespace("mermaid_lint")

function M.lint()
  if vim.fn.executable("mmdc") == 0 then
    -- fail silently or log once? 
    -- Better not to spam if mmdc is missing, specific command could warn.
    return
  end

  local filepath = vim.api.nvim_buf_get_name(0)
  -- If buffer is modified, we should ideally lint the content, 
  -- but mmdc takes file input preferably or stdin.
  -- Let's try stdin.
  
  local cmd = "mmdc -i - -o /dev/null"
  local content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  
  -- Using vim.fn.system to pass stdin
  local output = vim.fn.system(cmd, content)
  local exit_code = vim.v.shell_error
  
  local diagnostics = {}
  
  if exit_code ~= 0 then
    -- Parse error
    -- Example format: "Parse error on line 2: ..."
    local line_num = output:match("Parse error on line (%d+)")
    local message = output
    
    if line_num then
        line_num = tonumber(line_num) - 1 -- 0-indexed
        table.insert(diagnostics, {
            lnum = line_num,
            col = 0,
            message = message,
            severity = vim.diagnostic.severity.ERROR,
            source = "mermaid-cli",
        })
    end
  end
  
  vim.diagnostic.set(namespace, 0, diagnostics)
end

function M.setup_autocmd()
    vim.api.nvim_create_autocmd({"BufWritePost", "TextChanged", "InsertLeave"}, {
        pattern = "*.mmd",
        callback = function()
            M.lint()
        end,
    })
    
    -- Also for .mermaid extension if used
    vim.api.nvim_create_autocmd({"BufWritePost", "TextChanged", "InsertLeave"}, {
        pattern = "*.mermaid",
        callback = function()
            M.lint()
        end,
    })
end

return M
