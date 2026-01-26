local M = {}

function M.format()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local formatted_lines = {}
  local indent_level = 0
  local indent_size = vim.o.shiftwidth > 0 and vim.o.shiftwidth or 2
  local indent_char = vim.o.expandtab and string.rep(" ", indent_size) or "\t"

  -- Regex helpers
  local function is_start_block(line)
     -- Structural braces
     if line:match("{$") or line:match("%%{$") then return true end
     
     -- Keywords that open blocks
     local keywords = {
        "subgraph", "graph", "flowchart", "sequenceDiagram", "classDiagram", 
        "stateDiagram", "stateDiagram-v2", "erDiagram", "gantt", "pie", "journey", 
        "requirementDiagram", "gitGraph", "mindmap", 
        "loop", "rect", "opt", "alt", "par", "critical", "group", "parallel"
     }
     for _, kw in ipairs(keywords) do
        -- Check for exact match or match followed by whitespace to avoid partial matches
        -- e.g. 'par' should not match 'participant'
        if line == kw or line:match("^" .. vim.pesc(kw) .. "%s") then return true end
     end
     return false
  end

  local function is_end_block(line)
     if line:match("^}") or line:match("}%%$") then return true end
     return line:match("^end$")
  end

  local function is_mid_block(line)
     return line:match("^else") or line:match("^and") or line:match("^autonumber")
  end

  local function is_self_closing(line)
      -- Check if line contains both start and end signals
      -- Simple heuristic: starts with block opener, ends with block closer
      -- e.g. "class A { int x }" or "%%{init: {}}%%"
      local starts = is_start_block(line) or line:match("^{") or line:match("^%%{")
      local ends = is_end_block(line) or line:match("}$") or line:match("}%%$")
      
      if starts and ends then return true end
      
      -- Empty braces
      if line:match("{}") then return true end
      
      return false
  end

  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    
    if trimmed == "" then
      table.insert(formatted_lines, "")
    else
      local current_adjust = 0
      
      -- Self-closing lines (e.g. `class A {}`) shouldn't change indent permanently or trigger dedent
      if is_self_closing(trimmed) then
          -- It acts as a standard line, print at current indent
          -- Do nothing to indent_level
      else
          -- If it's an end block, dedent BEFORE printing
          if is_end_block(trimmed) then
              indent_level = math.max(0, indent_level - 1)
          elseif is_mid_block(trimmed) then
              -- Mid blocks (else, and) print at indent-1 but stay inside
              current_adjust = -1
          end
      end
      
      -- Apply and print
      local print_level = math.max(0, indent_level + current_adjust)
      table.insert(formatted_lines, string.rep(indent_char, print_level) .. trimmed)
      
      -- If it's a start block (and not self closing), indent AFTER printing
      if is_start_block(trimmed) and not is_self_closing(trimmed) then
          indent_level = indent_level + 1
      end
    end
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, formatted_lines)
  vim.notify("Mermaid: Formatted", vim.log.levels.INFO)
end

return M
