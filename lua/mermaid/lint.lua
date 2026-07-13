local M = {}
local uv = vim.loop
local namespace = vim.api.nvim_create_namespace("mermaid_lint")
local timer = nil

--- Parse line number and error message from mmdc stderr output.
--- Returns {lnum, message, severity} or nil if parsing fails.
--
-- Supported formats:
--   1. "Parse error on line 5:\nExpecting 'SEMI'..."  (standard mmdc)
--   2. "Error: Parse error on line 12:\ngraph TD\n..." (with "Error:" prefix)
--   3. "Syntax error in line 8: ..."                    (alternative format)
--   4. "Could not parse diagram: error at line 15, ..."  (complex format)
--   5. Other: whole stderr becomes the message, no line number
local function parse_mmdc_error(stderr_data)
  if not stderr_data or stderr_data == "" then
    return nil
  end

  -- Normalize: remove ANSI escape codes
  local clean = stderr_data:gsub("\x1b%[%d+;?%d*m", "")

  local patterns = {
    -- "Parse error on line 42:" or "Error: Parse error on line 42:"
    { pattern = "[Pp]arse error on line (%d+)", severity = vim.diagnostic.severity.ERROR },
    -- "Syntax error in line 8:"
    { pattern = "[Ss]yntax error in line (%d+)", severity = vim.diagnostic.severity.ERROR },
    -- "Syntax error on line 8:"
    { pattern = "[Ss]yntax error on line (%d+)", severity = vim.diagnostic.severity.ERROR },
    -- "Could not parse diagram: error at line 15, unexpected symbol"
    { pattern = "[Cc]ould not parse.-error at line (%d+)", severity = vim.diagnostic.severity.ERROR },
    -- "Warning: something on line 23" (some mmdc configs output warnings)
    { pattern = "[Ww]arning.-line (%d+)", severity = vim.diagnostic.severity.WARN },
  }

  for _, entry in ipairs(patterns) do
    local match_line = clean:match(entry.pattern)
    if match_line then
      -- 0-indexed lnum as expected by vim.diagnostic
      local lnum = tonumber(match_line) - 1
      if lnum < 0 then lnum = 0 end
      return {
        lnum = lnum,
        col = 0,
        message = clean,
        severity = entry.severity,
        source = "mermaid-cli",
      }
    end
  end

  -- Fallback: no line number found, return the whole stderr as error
  -- Only return if there's meaningful content
  if #clean > 5 then
    return {
      lnum = 0,
      col = 0,
      message = clean,
      severity = vim.diagnostic.severity.ERROR,
      source = "mermaid-cli",
    }
  end

  return nil
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

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
  local extracted = require("mermaid.diagram").extract(table.concat(lines, "\n"))
  local tmpfile = os.tmpname() .. ".svg"

  local stdin = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local stdout = uv.new_pipe(false)

  local stderr_data = ""
  local stdout_data = ""
  local closed_stderr = false
  local closed_stdout = false
  local exit_code = nil

  local function on_finish()
    if not closed_stderr or not closed_stdout or exit_code == nil then return end

    -- Cleanup temp file
    pcall(os.remove, tmpfile)

    local diagnostics = {}
    if exit_code ~= 0 then
      local diag = parse_mmdc_error(stderr_data)
      if diag then
        table.insert(diagnostics, diag)
      end
    end

    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.diagnostic.set(namespace, bufnr, diagnostics)
      end
    end)
  end

  local config = require("mermaid").config
  local cmd = config.lint.command

  local handle
  handle = uv.spawn(cmd, {
    args = { "-i", "-", "-o", tmpfile },
    stdio = { stdin, stdout, stderr }
  }, function(code, _signal)
    exit_code = code
    if handle and not handle:is_closing() then handle:close() end
    on_finish()
  end)

  -- Read stderr
  uv.read_start(stderr, function(_err, data)
    if data then
      stderr_data = stderr_data .. data
    else
      if not stderr:is_closing() then stderr:close() end
      closed_stderr = true
      on_finish()
    end
  end)

  -- Read stdout (just to drain, not used for diagnostics)
  uv.read_start(stdout, function(_err, data)
    if data then
      stdout_data = stdout_data .. data
    else
      if not stdout:is_closing() then stdout:close() end
      closed_stdout = true
      on_finish()
    end
  end)

  uv.write(stdin, extracted)
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
