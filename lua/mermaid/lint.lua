local M = {}
local uv = vim.loop
local namespace = vim.api.nvim_create_namespace("mermaid_lint")
local timer = nil

function M.lint()
  local config = require("mermaid").config
  local cmd = config.lint.command
  
  if vim.fn.executable(cmd) == 0 then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Debounce: cancel previous timer if it exists
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
  end

  timer = uv.new_timer()
  -- Wait 500ms
  timer:start(500, 0, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.do_lint_async(bufnr)
    end
  end))
end


function M.do_lint_async(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    local tmpfile = os.tmpname() .. ".svg"
    
    local stdin = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    
    local stderr_data = ""
    local closed_stderr = false
    local exit_code = nil
    
    local function on_finish()
        if not closed_stderr or exit_code == nil then return end
        
        -- Cleanup temp file
        os.remove(tmpfile)
        
        local diagnostics = {}
        if exit_code ~= 0 then
            local line_num = stderr_data:match("Parse error on line (%d+)")
            local message = stderr_data
            
            if line_num then
                line_num = tonumber(line_num) - 1
                table.insert(diagnostics, {
                    lnum = line_num,
                    col = 0,
                    message = message,
                    severity = vim.diagnostic.severity.ERROR,
                    source = "mermaid-cli",
                })
            end
        end
        
        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
                vim.diagnostic.set(namespace, bufnr, diagnostics)
            end
        end)
    end
    
    local handle
    local config = require("mermaid").config
    local cmd = config.lint.command

    handle = uv.spawn(cmd, {
        args = { "-i", "-", "-o", tmpfile },
        stdio = { stdin, nil, stderr }
    }, function(code, signal)
        exit_code = code
        if handle and not handle:is_closing() then handle:close() end
        on_finish()
    end)
    
    uv.read_start(stderr, function(err, data)
        if data then
            stderr_data = stderr_data .. data
        else
            if not stderr:is_closing() then stderr:close() end
            closed_stderr = true
            on_finish()
        end
    end)
    
    uv.write(stdin, content)
    uv.shutdown(stdin, function() 
        if not stdin:is_closing() then stdin:close() end 
    end)
end

function M.do_lint_wrapper(bufnr)
    M.do_lint_async(bufnr)
end

function M.setup_autocmd()
    vim.api.nvim_create_autocmd({"BufWritePost", "TextChanged", "InsertLeave"}, {
        pattern = {"*.mmd", "*.mermaid"},
        callback = function()
            M.lint()
        end,
    })
end

return M
