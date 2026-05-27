     1|--- mermaid render: render diagrams inline in the terminal
     2|--
     3|-- Supports multiple terminal capabilities:
     4|--   kitty:  Kitty terminal image protocol (icat)
     5|--   chafa:  ASCII/ANSI art via chafa CLI
     6|--   sixel:  Sixel graphics (if available)
     7|--   none:   Fallback — no inline rendering
     8|--
     9|-- Detection logic:
    10|--   1. Check $KITTY_WINDOW_ID for Kitty protocol
    11|--   2. Check $TERM_PROGRAM for iTerm2
    12|--   3. Check $TERM for "sixel" or "xterm" (best-effort)
    13|--   4. Check if `chafa` is installed
    14|--   5. Fallback to "none" (URL-only)
    15|local M = {}
    16|
    17|--- Detect what terminal rendering capability is available
    18|function M.detect_capability()
    19|  local env = vim.fn.environ()
    20|
    21|  -- Kitty protocol (most reliable)
    22|  if vim.fn.executable("kitty") == 1 and env["KITTY_WINDOW_ID"] ~= vim.NIL then
    23|    return "kitty"
    24|  end
    25|
    26|  -- iTerm2
    27|  if env["TERM_PROGRAM"] == "iTerm.app" then
    28|    return "iterm2"
    29|  end
    30|
    31|  -- Sixel
    32|  local term = env["TERM"] or ""
    33|  if term:match("sixel") then
    34|    return "sixel"
    35|  end
    36|
    37|  -- chafa (universal ASCII/ANSI art)
    38|  if vim.fn.executable("chafa") == 1 then
    39|    return "chafa"
    40|  end
    41|
    42|  -- No capability found
    43|  return "none"
    44|end
    45|
    46|--- Format a human-readable label for the capability
    47|function M.capability_label(cap)
    48|  local labels = {
    49|    kitty  = "Kitty image protocol",
    50|    iterm2 = "iTerm2 image protocol",
    51|    sixel  = "Sixel graphics",
    52|    chafa  = "chafa (ASCII/ANSI art)",
    53|    none   = "None (URL only)",
    54|  }
    55|  return labels[cap] or "Unknown"
    56|end
    57|
    58|--- Generate SVG using mmdc from Mermaid source text.
    59|<<<<<<< HEAD
    60|--- Theme is derived from Neovim's background setting for terminal render.
    61|=======
    62|>>>>>>> origin/main
    63|--- Returns { ok = true, svg_path = "..." } or { ok = false, error = "..." }
    64|function M.generate_svg(content, output_path)
    65|  output_path = output_path or os.tmpname() .. ".svg"
    66|
    67|  local cmd = "mmdc"
    68|  if vim.fn.executable(cmd) == 0 then
    69|    return { ok = false, error = "mmdc not found. Install @mermaid-js/mermaid-cli." }
    70|  end
    71|
    72|<<<<<<< HEAD
    73|  -- Map Neovim background to mermaid theme: dark → "dark", light → "default"
    74|  local mmdc_theme = vim.o.background == "dark" and "dark" or "default"
    75|
    76|=======
    77|>>>>>>> origin/main
    78|  local tmp_input = os.tmpname() .. ".mmd"
    79|  local input_f = io.open(tmp_input, "w")
    80|  if input_f then
    81|    input_f:write(content)
    82|    input_f:close()
    83|  else
    84|    return { ok = false, error = "Failed to write temp file" }
    85|  end
    86|
    87|<<<<<<< HEAD
    88|  local result = vim.fn.system({ cmd, "-i", tmp_input, "-o", output_path, "--theme", mmdc_theme })
    89|=======
    90|  local result = vim.fn.system({ cmd, "-i", tmp_input, "-o", output_path })
    91|>>>>>>> origin/main
    92|  local exit_code = vim.v.shell_error
    93|
    94|  pcall(os.remove, tmp_input)
    95|
    96|  if exit_code ~= 0 then
    97|    pcall(os.remove, output_path)
    98|    return { ok = false, error = "mmdc failed: " .. (result or "unknown error") }
    99|  end
   100|
   101|  return { ok = true, svg_path = output_path }
   102|end
   103|
   104|--- Render an SVG file inline in the terminal.
   105|--- Returns { ok = true, method = "..." } or { ok = false, error = "..." }
   106|function M.render_file(filepath)
   107|  if not filepath or not vim.fn.filereadable(filepath) then
   108|    return { ok = false, error = "File not found: " .. tostring(filepath) }
   109|  end
   110|
   111|  local cap = M.detect_capability()
   112|
   113|  if cap == "kitty" then
   114|    -- Use kitty +kitten icat
   115|    local result = vim.fn.system({ "kitty", "+kitten", "icat", filepath })
   116|    if vim.v.shell_error == 0 then
   117|      return { ok = true, method = "kitty" }
   118|    else
   119|      return { ok = false, error = "kitty icat failed: " .. (result or "") }
   120|    end
   121|  elseif cap == "chafa" then
   122|    -- Convert SVG to PNG first, then render via chafa
   123|    local tmp_png = os.tmpname() .. ".png"
   124|    -- Try converting with ImageMagick or rsvg-convert
   125|    local converter = vim.fn.executable("rsvg-convert") == 1 and "rsvg-convert" or nil
   126|    converter = converter or (vim.fn.executable("convert") == 1 and "convert" or nil)
   127|
   128|    if converter == "rsvg-convert" then
   129|      vim.fn.system({ "rsvg-convert", filepath, "-o", tmp_png })
   130|    elseif converter == "convert" then
   131|      vim.fn.system({ "convert", filepath, tmp_png })
   132|    else
   133|      pcall(os.remove, tmp_png)
   134|      -- Try direct SVG rendering (chafa supports SVG since v0.8+)
   135|      vim.fn.system({ "chafa", filepath })
   136|      if vim.v.shell_error == 0 then
   137|        return { ok = true, method = "chafa" }
   138|      end
   139|      return { ok = false, error = "Neither rsvg-convert nor ImageMagick found for SVG→PNG conversion" }
   140|    end
   141|
   142|    -- Render via chafa
   143|    local result = vim.fn.system({ "chafa", tmp_png })
   144|    pcall(os.remove, tmp_png)
   145|    if vim.v.shell_error == 0 then
   146|      return { ok = true, method = "chafa" }
   147|    else
   148|      return { ok = false, error = "chafa failed: " .. (result or "") }
   149|    end
   150|  else
   151|    -- sixel or none: not supported
   152|    return {
   153|      ok = false,
   154|      error = "Inline rendering not supported. Use :MermaidPreview to open in browser.",
   155|      method = cap,
   156|    }
   157|  end
   158|end
   159|
   160|--- Render Mermaid source text inline in the terminal.
   161|--- Combines generate_svg + render_file.
   162|function M.render_source(content)
   163|  local svg = M.generate_svg(content)
   164|  if not svg.ok then return svg end
   165|
   166|  local result = M.render_file(svg.svg_path)
   167|  pcall(os.remove, svg.svg_path)
   168|  return result
   169|end
   170|
   171|--- Check if inline rendering is available at all
   172|function M.is_available()
   173|  return M.detect_capability() ~= "none"
   174|end
   175|
   176|return M
   177|