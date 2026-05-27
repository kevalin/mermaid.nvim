--- mermaid render: render diagrams inline in the terminal
--
-- Supports multiple terminal capabilities:
--   kitty:  Kitty terminal image protocol (icat)
--   chafa:  ASCII/ANSI art via chafa CLI
--   sixel:  Sixel graphics (if available)
--   none:   Fallback — no inline rendering
--
-- Detection logic:
--   1. Check $KITTY_WINDOW_ID for Kitty protocol
--   2. Check $TERM_PROGRAM for iTerm2
--   3. Check $TERM for "sixel" or "xterm" (best-effort)
--   4. Check if `chafa` is installed
--   5. Fallback to "none" (URL-only)
local M = {}

--- Detect what terminal rendering capability is available
function M.detect_capability()
  local env = vim.fn.environ()

  -- Kitty protocol (most reliable)
  if vim.fn.executable("kitty") == 1 and env["KITTY_WINDOW_ID"] ~= vim.NIL then
    return "kitty"
  end

  -- iTerm2
  if env["TERM_PROGRAM"] == "iTerm.app" then
    return "iterm2"
  end

  -- Sixel
  local term = env["TERM"] or ""
  if term:match("sixel") then
    return "sixel"
  end

  -- chafa (universal ASCII/ANSI art)
  if vim.fn.executable("chafa") == 1 then
    return "chafa"
  end

  -- No capability found
  return "none"
end

--- Format a human-readable label for the capability
function M.capability_label(cap)
  local labels = {
    kitty  = "Kitty image protocol",
    iterm2 = "iTerm2 image protocol",
    sixel  = "Sixel graphics",
    chafa  = "chafa (ASCII/ANSI art)",
    none   = "None (URL only)",
  }
  return labels[cap] or "Unknown"
end

--- Generate SVG using mmdc from Mermaid source text.
--- Theme is derived from Neovim's background setting for terminal render.
--- Returns { ok = true, svg_path = "..." } or { ok = false, error = "..." }
function M.generate_svg(content, output_path)
  output_path = output_path or os.tmpname() .. ".svg"

  local cmd = "mmdc"
  if vim.fn.executable(cmd) == 0 then
    return { ok = false, error = "mmdc not found. Install @mermaid-js/mermaid-cli." }
  end

  -- Map Neovim background to mermaid theme: dark → "dark", light → "default"
  local mmdc_theme = vim.o.background == "dark" and "dark" or "default"

  local tmp_input = os.tmpname() .. ".mmd"
  local input_f = io.open(tmp_input, "w")
  if input_f then
    input_f:write(content)
    input_f:close()
  else
    return { ok = false, error = "Failed to write temp file" }
  end

  local result = vim.fn.system({ cmd, "-i", tmp_input, "-o", output_path, "--theme", mmdc_theme })
  local exit_code = vim.v.shell_error

  pcall(os.remove, tmp_input)

  if exit_code ~= 0 then
    pcall(os.remove, output_path)
    return { ok = false, error = "mmdc failed: " .. (result or "unknown error") }
  end

  return { ok = true, svg_path = output_path }
end

--- Render an SVG file inline in the terminal.
--- Returns { ok = true, method = "..." } or { ok = false, error = "..." }
function M.render_file(filepath)
  if not filepath or not vim.fn.filereadable(filepath) then
    return { ok = false, error = "File not found: " .. tostring(filepath) }
  end

  local cap = M.detect_capability()

  if cap == "kitty" then
    -- Use kitty +kitten icat
    local result = vim.fn.system({ "kitty", "+kitten", "icat", filepath })
    if vim.v.shell_error == 0 then
      return { ok = true, method = "kitty" }
    else
      return { ok = false, error = "kitty icat failed: " .. (result or "") }
    end
  elseif cap == "chafa" then
    -- Convert SVG to PNG first, then render via chafa
    local tmp_png = os.tmpname() .. ".png"
    -- Try converting with ImageMagick or rsvg-convert
    local converter = vim.fn.executable("rsvg-convert") == 1 and "rsvg-convert" or nil
    converter = converter or (vim.fn.executable("convert") == 1 and "convert" or nil)

    if converter == "rsvg-convert" then
      vim.fn.system({ "rsvg-convert", filepath, "-o", tmp_png })
    elseif converter == "convert" then
      vim.fn.system({ "convert", filepath, tmp_png })
    else
      pcall(os.remove, tmp_png)
      -- Try direct SVG rendering (chafa supports SVG since v0.8+)
      vim.fn.system({ "chafa", filepath })
      if vim.v.shell_error == 0 then
        return { ok = true, method = "chafa" }
      end
      return { ok = false, error = "Neither rsvg-convert nor ImageMagick found for SVG→PNG conversion" }
    end

    -- Render via chafa
    local result = vim.fn.system({ "chafa", tmp_png })
    pcall(os.remove, tmp_png)
    if vim.v.shell_error == 0 then
      return { ok = true, method = "chafa" }
    else
      return { ok = false, error = "chafa failed: " .. (result or "") }
    end
  else
    -- sixel or none: not supported
    return {
      ok = false,
      error = "Inline rendering not supported. Use :MermaidPreview to open in browser.",
      method = cap,
    }
  end
end

--- Render Mermaid source text inline in the terminal.
--- Combines generate_svg + render_file.
function M.render_source(content)
  local svg = M.generate_svg(content)
  if not svg.ok then return svg end

  local result = M.render_file(svg.svg_path)
  pcall(os.remove, svg.svg_path)
  return result
end

--- Check if inline rendering is available at all
function M.is_available()
  return M.detect_capability() ~= "none"
end

return M
