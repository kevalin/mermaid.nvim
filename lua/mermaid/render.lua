--- mermaid render: render diagrams inline in the terminal
--
-- Supports multiple terminal capabilities:
--   kitty:  Kitty terminal image protocol (icat)
--   chafa:  ASCII/ANSI art via chafa CLI
--   sixel:  Sixel graphics (if available)
--   none:   Fallback — no inline rendering
--
-- Detection logic:
--   1. Check Kitty/Ghostty environment markers and the kitty CLI
--   2. Check $TERM_PROGRAM for iTerm2
--   3. Check $TERM for "sixel" or "xterm" (best-effort)
--   4. Check if `chafa` is installed
--   5. Fallback to "none" (URL-only)
--
-- Kitty rendering uses nvim_ui_send() (Neovim 0.12+) to forward protocol
-- escape sequences to the host TUI. Older versions safely fall back to chafa.
local M = {}

local function host_tui()
  if type(vim.api.nvim_ui_send) ~= "function" then return nil end

  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    if ui.stdout_tty then return ui end
  end

  return nil
end

local function render_with_kitty(filepath, ui)
  local width = math.max(1, ui.width or vim.o.columns)
  local height = math.max(1, (ui.height or vim.o.lines) - 1)
  local window_size = string.format("%d,%d,%d,%d", width, height, width * 10, height * 20)
  local place = string.format("%dx%d@0x0", width, height)
  local output = vim.fn.system({
    "kitty", "+kitten", "icat",
    "--stdin=no",
    "--use-window-size", window_size,
    "--place", place,
    "--transfer-mode=stream",
    filepath,
  })

  if vim.v.shell_error ~= 0 then
    return { ok = false, error = "kitty icat failed: " .. (output or "") }
  end

  local ok, err = pcall(vim.api.nvim_ui_send, output)
  if not ok then
    return { ok = false, error = "failed to send kitty output to terminal: " .. tostring(err) }
  end

  return { ok = true, method = "kitty" }
end

--- Detect what terminal rendering capability is available
function M.detect_capability()
  local env = vim.fn.environ()
  local term = type(env["TERM"]) == "string" and env["TERM"]:lower() or ""
  local term_program = type(env["TERM_PROGRAM"]) == "string" and env["TERM_PROGRAM"]:lower() or ""

  local kitty_window_id = env["KITTY_WINDOW_ID"]
  local supports_kitty = (type(kitty_window_id) == "string" and kitty_window_id ~= "")
    or term_program == "ghostty"
    or term:match("ghostty") ~= nil
  if vim.fn.executable("kitty") == 1 and supports_kitty then
    return "kitty"
  end

  -- iTerm2
  if env["TERM_PROGRAM"] == "iTerm.app" then
    return "iterm2"
  end

  -- Sixel
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
    local kitty_result
    local ui = host_tui()
    if ui then
      kitty_result = render_with_kitty(filepath, ui)
      if kitty_result.ok then return kitty_result end
    else
      kitty_result = {
        ok = false,
        error = "Kitty inline rendering requires Neovim 0.12+; install chafa or use :MermaidPreview.",
      }
    end

    if vim.fn.executable("chafa") ~= 1 then
      return kitty_result
    end
    cap = "chafa"
  end

  if cap == "chafa" then
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
