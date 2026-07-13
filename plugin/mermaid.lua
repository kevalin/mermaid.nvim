vim.api.nvim_create_user_command("MermaidFormat", function()
  require("mermaid.format").format()
end, {})

vim.api.nvim_create_user_command("MermaidPreview", function()
  require("mermaid.preview").preview()
end, {})

vim.api.nvim_create_user_command("MermaidPreviewStop", function()
  require("mermaid.server").stop_server()
  require("mermaid.panel").close()
  vim.notify("Mermaid: Preview stopped", vim.log.levels.INFO)
end, {})

vim.api.nvim_create_user_command("MermaidCopyURL", function()
  local port = require("mermaid.server").port
  if port then
    local url = "http://localhost:" .. port
    vim.fn.setreg("+", url)
    vim.notify("Mermaid: Copied '" .. url .. "' to clipboard", vim.log.levels.INFO)
  else
    vim.notify("Mermaid: Preview server not running", vim.log.levels.WARN)
  end
end, {})

vim.api.nvim_create_user_command("MermaidRender", function()
  local render = require("mermaid.render")
  local cap = render.detect_capability()
  vim.notify("Mermaid: Terminal capability: " .. render.capability_label(cap), vim.log.levels.INFO)

  if not render.is_available() then
    vim.notify(
      "Mermaid: No inline renderer available. Install chafa or use :MermaidPreview.",
      vim.log.levels.WARN
    )
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")
  content = require("mermaid.diagram").extract(content)
  if content:match("^%s*$") then
    vim.notify("Mermaid: Buffer is empty", vim.log.levels.WARN)
    return
  end

  local result = render.render_source(content)
  if not result.ok then
    vim.notify("Mermaid: Render failed: " .. (result.error or "unknown"), vim.log.levels.ERROR)
  else
    vim.notify("Mermaid: Rendered inline via " .. result.method, vim.log.levels.INFO)
  end
end, {})

