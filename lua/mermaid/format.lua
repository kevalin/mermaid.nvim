local M = {}

------------------------------------------------------------------------------
-- Format: skip marker
------------------------------------------------------------------------------

-- Lines containing this marker are left completely untouched.
local SKIP_MARKER = "-- mermaid-format-ignore"

------------------------------------------------------------------------------
-- Token padding utilities
------------------------------------------------------------------------------

--- Mask Mermaid comments (%% to end of line), single-quoted strings,
--- double-quoted strings, AND %%{init} directives before token padding.
--- Directives are kept masked through the padding step and only restored
--- by the returned unmask function (prevents `:` inside directives from being padded).
local function mask_ignored(line)
  local masked = { _str = {}, _quote = {}, _comment = {}, _directive = {} }

  -- 1) Mask %%{...}%% directives FIRST (highest priority)
  local function protect_directive(s)
    table.insert(masked._directive, s)
    return "\x04" .. #masked._directive .. "\x04"
  end
  masked._str = line:gsub("%%{.-}%%", protect_directive)

  -- 2) Mask bare %% comments (from %% to end of line)
  local function mask_comment(s)
    table.insert(masked._comment, s)
    return "\x03" .. #masked._comment .. "\x03"
  end
  masked._str = masked._str:gsub("%%%%[^\n]*", mask_comment)

  -- 3) Mask single and double-quoted strings
  local function mask_quote(s)
    table.insert(masked._quote, s)
    return "\x02" .. #masked._quote .. "\x02"
  end
  masked._str = masked._str:gsub("'[^']*'", mask_quote)
  masked._str = masked._str:gsub('"[^"]*"', mask_quote)

  -- Unmask function for final restore AFTER padding
  local function unmask(s)
    s = s:gsub("\x02(%d+)\x02", function(idx)
      return masked._quote[tonumber(idx)]
    end)
    s = s:gsub("\x03(%d+)\x03", function(idx)
      return masked._comment[tonumber(idx)]
    end)
    s = s:gsub("\x04(%d+)\x04", function(idx)
      return masked._directive[tonumber(idx)]
    end)
    return s
  end

  return masked._str, unmask
end

--- Pad Mermaid tokens with surrounding spaces
local function pad_mermaid_tokens(line)
  local tokens = {}
  local function stash(_, match, _post)
    table.insert(tokens, match)
    return "\001" .. #tokens .. "\001"
  end

  local patterns = {
    -- ER Diagram Cardinality (e.g. }|..|{ )
    -- Must be before simple arrows to avoid partial matches
    "%;{%s*%.%.%s*|}",          -- ;{..|}
    "[|{}]?[|o][%.%-][%.%-]+[|o][|{}]?",

    -- Flowchart thick chain markers (===, ===>)
    "%=%=%=",
    "%=%=%>",

    -- Sequence/Flowchart/Class Arrows (Complex)
    "%<%<%-%-%>%>",  -- <<-->>
    "%<%<%-%>%>",    -- <<->>
    "%-%-%>%!",      -- -->!
    "%-%-%>%>",      -- -->>
    "%-%.%-%>",      -- -.->

    -- GitGraph arrows
    "%-%-%-%>",      -- --->

    -- Standard arrows (longer patterns first to avoid greedy matches)
    "%-%-%>",        -- -->
    "%-%-%+",        -- --+
    "%-%-%-",        -- ---

    -- Class Diagram Relationships (must be before bare -- to avoid splitting)
    "%<|%-%-",       -- <|-- (Inheritance)
    "%*%-%-",        -- *-- (Composition)
    "o%-%-",         -- o-- (Aggregation)
    "%<|%.%.",       -- <|.. (Realization)
    "%*%.%.",        -- *..
    "o%.%.",         -- o..
    "%-%-|%>",       -- --|>
    "%-%-%*",        -- --*
    "%-%-o",         -- --o
    "%.%.|%>",       -- ..|>
    "%.%.%*",        -- ..*
    "%.%.o",         -- ..o

    -- Arrow ends
    "%-%-x",         -- --x
    "x%-%-",         -- x--
    "%-%-%o",        -- --o
    "o%-%-",         -- o--
    "%-%-%)",        -- --)
    "%-%-",          -- -- (Link)

    -- Multi-char thin arrows (must be before single-char)
    "%-%>%>",        -- ->>
    "%-%.%>",        -- -.>
    "%-%.%-",        -- -.-

    -- Thin arrows (single dash - after multi-char to avoid greed)
    "%-%>",          -- ->
    "%-x",           -- -x
    "%-%)",          -- -)

    -- Thick links
    "%=%=%>",        -- ==>
    "%=%=",          -- == (Thick link)

    -- Misc
    ":::",          -- Class assignment (must be before bare :)
    ":",            -- Colon (often splits label)
  }

  -- TODO: Use string.find with proper word boundaries for single-char tokens
  for _, pat in ipairs(patterns) do
    line = line:gsub("(%s*)(" .. pat .. ")(%s*)", stash)
  end

  -- Restore with exactly one space around each token
  line = line:gsub("\001(%d+)\001", function(idx)
    return " " .. tokens[tonumber(idx)] .. " "
  end)

  -- Cleanup double/triple spaces
  line = line:gsub("%s+", " ")

  -- Remove space before colon when it follows a word character
  -- (sequence diagram labels: `Bob: Hello`, not `Bob : Hello`)
  line = line:gsub("(%w) :", "%1:")

  -- Remove spaces around class assignment operator :::
  line = line:gsub("%s*:::%s*", ":::")

  return line
end

------------------------------------------------------------------------------
-- Block indentation logic
------------------------------------------------------------------------------

local BLOCK_START_KEYWORDS = {
  "subgraph", "graph", "flowchart", "sequenceDiagram", "classDiagram",
  "stateDiagram", "stateDiagram-v2", "erDiagram", "gantt", "pie", "journey",
  "requirementDiagram", "gitGraph", "mindmap", "timeline", "xychart-beta",
  "sankey-beta", "block", "info",
  "loop", "rect", "opt", "alt", "par", "critical", "group", "parallel",
}

local BLOCK_END_KEYWORDS = {
  "end",
}

local BLOCK_MID_KEYWORDS = {
  "else", "elseif",
}

--- Check if a line begins a block that increases indent
local function is_start_block(line)
  -- Structural braces
  if line:match("{$") or line:match("%%{$") then return true end

  for _, kw in ipairs(BLOCK_START_KEYWORDS) do
    local escaped = vim.pesc(kw)
    if line == kw or line:match("^" .. escaped .. "%s") or line:match("^" .. escaped .. ":") then
      return true
    end
  end
  return false
end

--- Check if a line ends a block that decreases indent
local function is_end_block(line)
  if line:match("^}") or line:match("}%%$") then return true end
  for _, kw in ipairs(BLOCK_END_KEYWORDS) do
    if line == kw or line:match("^" .. kw .. "%s") then return true end
  end
  return false
end

--- Check if a line is a mid-block continuation (else, elseif)
local function is_mid_block(line)
  for _, kw in ipairs(BLOCK_MID_KEYWORDS) do
    if line:match("^" .. kw) then return true end
  end
  return false
end

--- Check if a line is self-closing (opens and closes on same line)
local function is_self_closing(line)
  -- Detect lines like: class A { int x }
  local opens_brace = line:match("{%s")
  local closes_brace = line:match("%s}")
  if opens_brace and closes_brace then return true end

  -- Empty braces
  if line:match("{") and line:match("}") and not line:match("}%%$") then
    -- Check it's not a multi-line open/close structure
    local open_count = 0
    local close_count = 0
    for c in line:gmatch(".") do
      if c == "{" then open_count = open_count + 1
      elseif c == "}" then close_count = close_count + 1 end
    end
    -- If balanced braces on one line, treat as self-closing
    if open_count == close_count and open_count > 0 then
      return true
    end
  end

  return false
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

function M.format()
  local config = require("mermaid").config
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local formatted_lines = {}
  local indent_level = 0

  local shift_width = (config.format and config.format.shift_width) or vim.o.shiftwidth
  local indent_size = shift_width > 0 and shift_width or 4
  local indent_char = vim.o.expandtab and string.rep(" ", indent_size) or "\t"

  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")

    if trimmed == "" then
      table.insert(formatted_lines, "")
    elseif trimmed:match("^" .. vim.pesc(SKIP_MARKER)) or trimmed:lower():match("^" .. vim.pesc(SKIP_MARKER)) then
      -- Skip marker at line start: keep original line as-is (no indent, no padding)
      table.insert(formatted_lines, line)
    elseif line:lower():match(vim.pesc(SKIP_MARKER)) then
      -- Inline skip marker: keep original line as-is
      table.insert(formatted_lines, line)
    else
      -- Step 1: Mask comments and strings
      local masked_line, unmask = mask_ignored(trimmed)

      -- Step 2: Pad tokens on the masked version
      masked_line = pad_mermaid_tokens(masked_line)

      -- Step 3: Restore original strings and comments
      masked_line = unmask(masked_line)

      -- Step 4: Trim again after padding/unmasking
      masked_line = masked_line:match("^%s*(.-)%s*$")

      local current_adjust = 0

      if not is_self_closing(masked_line) then
        if is_end_block(masked_line) then
          indent_level = math.max(0, indent_level - 1)
        elseif is_mid_block(masked_line) then
          current_adjust = -1
        end
      end

      -- Apply indent
      local print_level = math.max(0, indent_level + current_adjust)
      table.insert(formatted_lines, string.rep(indent_char, print_level) .. masked_line)

      -- Adjust for next line
      if is_start_block(masked_line) and not is_self_closing(masked_line) then
        indent_level = indent_level + 1
      end
    end
  end

  vim.api.nvim_buf_set_lines(0, 0, -1, false, formatted_lines)
  vim.notify("Mermaid: Formatted", vim.log.levels.INFO)
end

return M
