vim.api.nvim_create_user_command("MermaidFormat", function()
  require("mermaid.format").format()
end, {})

vim.api.nvim_create_user_command("MermaidPreview", function()
  require("mermaid.preview").preview()
end, {})

