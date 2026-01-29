local M = {}

local function pad_mermaid_tokens(line)
  local tokens = {}
  local function stash(pre, match, post)
    table.insert(tokens, match)
    return "\001" .. #tokens .. "\001"
  end

  -- Order matters! Longer/More specific patterns first.
  -- We capture surrounding spaces to replace them with a single space.
  local patterns = {
    -- ER Diagram Cardinality (e.g. }|..|{ )
    -- Must be before simple arrows to avoid partial matches
    -- Left: }| |{ }o o{ || |o
    -- Conn: -- ..
    -- Right: Same as left reversed
    "[|{}]?[|o][%.%-][%.%-]+[|o][|{}]?", 

    -- Sequence/Flowchart/Class Arrows (Complex)
    "%<%<%-%-%>%>", -- <<-->>
    "%<%<%-%>%>",   -- <<->>
    "%-%-%>%!",     -- -->! (Activations?) - Rare but possible
    "%-%-%>%>",     -- -->>
    "%-%.%-%>",     -- -.->
    "%-%-%>",       -- -->
    "%-%-%+",       -- --+ (Activation shorthand?)
    "%-%-%-",       -- ---
    
    -- Specific Endings
    "%-%-x",        -- --x
    "x%-%-",        -- x--
    "%-%-%o",       -- --o
    "o%-%-",        -- o--
    "%-%-%)",       -- --)
    "%-%-",         -- -- (Link)

    -- Shorter Arrows
    "%-%>%>",       -- ->>
    "%-%.%>",       -- -.>
    "%-%.%-",       -- -.-
    "%=%=%>",       -- ==>
    "%=%=",         -- == (Thick link)
    "%-%>",         -- ->
    "%-%+",         -- -+
    "%-x",          -- -x
    "x%-",          -- x-
    "%-%)",         -- -)
    
    -- Class Diagram Relationships
    "%<|%-%-",      -- <|-- (Inheritance)
    "%*%-%-",       -- *-- (Composition)
    "o%-%-",        -- o-- (Aggregation)
    "%<|%.%.",      -- <|.. (Realization)
    "%*%.%.",       -- *..
    "o%.%.",        -- o..
    "%-%-|%>",      -- --|>
    "%-%-%*",       -- --*
    "%-%-o",        -- --o
    "%.%.|%>",      -- ..|>
    "%.%.%*",       -- ..*
    "%.%.o",        -- ..o
    
    -- Misc
    ":",            -- Colon (often splits label)
  }

  for _, pat in ipairs(patterns) do
    -- Using () to capture groups in gsub. 
    -- We want to match: (spaces?)(pattern)(spaces?)
    -- And replace with: \001...
    -- But we need to be careful not to match inside words if possible.
    -- Most symbolic tokens are safe.
    -- We use %f to ensure specific boundaries if needed, but for symbols usually not needed 
    -- unless they can part of a word. 
    -- Dash can be in words "state-diagram". 
    -- So we should be careful with single dashes or words containing dashes.
    
    -- Strategy: We iterate and replace.
    -- However, replacing `-` might be dangerous.
    -- The patterns above are mostly multi-char or specific.
    -- Exception: `:`
    
    line = line:gsub("(%s*)(" .. pat .. ")(%s*)", stash)
  end

  -- Restore with exactly one space around, except for special cases if needed.
  -- For now, consistent 1-space padding is the goal.
  line = line:gsub("\001(%d+)\001", function(idx)
    return " " .. tokens[tonumber(idx)] .. " "
  end)

  -- Cleanup double spaces potentially created
  line = line:gsub("%s+", " ")
  return line
end

function M.format()
  local config = require("mermaid").config
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local formatted_lines = {}
  local indent_level = 0
  
  local shift_width = (config.format and config.format.shift_width) or vim.o.shiftwidth
  local indent_size = shift_width > 0 and shift_width or 4
  local indent_char = vim.o.expandtab and string.rep(" ", indent_size) or "\t"

  -- Regex helpers
  local function is_start_block(line)
     -- Structural braces
     if line:match("{$") or line:match("%%{$") then return true end
     
     -- Keywords that open blocks
     local keywords = {
        "subgraph", "graph", "flowchart", "sequenceDiagram", "classDiagram", 
        "stateDiagram", "stateDiagram-v2", "erDiagram", "gantt", "pie", "journey", 
        "requirementDiagram", "gitGraph", "mindmap", "timeline",
        "loop", "rect", "opt", "alt", "par", "critical", "group", "parallel"
     }
     for _, kw in ipairs(keywords) do
        -- Check for exact match or match followed by whitespace to avoid partial matches
        -- We anchor to start of trimmed line
        if line == kw or line:match("^" .. vim.pesc(kw) .. "%s") or line:match("^" .. vim.pesc(kw) .. ":") then 
            return true 
        end
     end
     return false
  end

  local function is_end_block(line)
     if line:match("^}") or line:match("}%%$") then return true end
     -- 'end' keyword, alone or with comment
     if line == "end" or line:match("^end%s") then return true end
     return false
  end

  local function is_mid_block(line)
     -- Keywords that are continuations: else, and, opt (sometimes used inside alt)
     -- Note: 'opt' is start block usually. 
     -- 'else', 'and', 'autonumber' (not really a block mid, but a setting)
     if line:match("^else") or line:match("^and") then return true end
     return false
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
      -- Pad symbols
      -- Note: Padding can disrupt some strict formats like `title:` or specific configs.
      -- But standard Mermaid usually survives spaces. 
      -- Exception: Strings "..." - we should probably NOT pad inside strings.
      -- For simplicity, we assume pad_mermaid_tokens logic is greedy enough for tokens 
      -- but might be naive about strings. 
      -- Ideally, we'd mask strings first.
      
      -- Basic string masking
      local strings = {}
      local function mask_string(s)
          table.insert(strings, s)
          return "\002" .. #strings .. "\002"
      end
      trimmed = trimmed:gsub('"[^"]*"', mask_string)
      
      trimmed = pad_mermaid_tokens(trimmed)
      
      -- Unmask
      trimmed = trimmed:gsub("\002(%d+)\002", function(idx)
          return strings[tonumber(idx)]
      end)
      
      -- Clean up spaces again after potential masking/unmasking weirdness
      trimmed = trimmed:match("^%s*(.-)%s*$")

      local current_adjust = 0
      
      if is_self_closing(trimmed) then
          -- No indent change logic
      else
          if is_end_block(trimmed) then
              indent_level = math.max(0, indent_level - 1)
          elseif is_mid_block(trimmed) then
              current_adjust = -1
          end
      end
      
      -- Apply and print
      local print_level = math.max(0, indent_level + current_adjust)
      table.insert(formatted_lines, string.rep(indent_char, print_level) .. trimmed)
      
      -- Indent for next line
      if is_start_block(trimmed) and not is_self_closing(trimmed) then
          indent_level = indent_level + 1
      end
    end
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, formatted_lines)
  vim.notify("Mermaid: Formatted", vim.log.levels.INFO)
end

return M
