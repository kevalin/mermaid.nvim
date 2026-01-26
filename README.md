# mermaid.nvim 🧜

A feature-rich Neovim plugin for working with [Mermaid](https://mermaid.js.org/) diagrams.

![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)

## ✨ Features

- **syntax Highlighting**: Full Tree-sitter support for all Mermaid diagram types.
- **Live Preview**: 
  - **Real-time**: Diagram updates instantly as you type.
  - **Interactive**: Pan and Zoom support (with `svg-pan-zoom`).
  - **Toolbar**: Custom controls for Zoom, Reset, **Copy Image (PNG)**, and Downloading SVG.
  - **Zero-config**: Built-in Lua HTTP server (no external node/python server needed).
- **Auto-Formatting**: 
  - Built-in indentation engine (no `prettier` dependency required).
  - Smart handling of blocks, diagrams, and directives.
- **Diagnostics**: 
  - Integration with `vim.diagnostic` to show syntax errors (requires `mermaid-cli`).

## ⚡ Requirements

- **Neovim** >= 0.8.0
- **nvim-treesitter**: For syntax highlighting.
- **mermaid-cli** (Optional): Only needed for diagnostics (error checking).
  - `npm install -g @mermaid-js/mermaid-cli`

## 📦 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
    "your-username/mermaid.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
        require("mermaid").setup()
        
        -- Install the tree-sitter parser manually if TSInstall fails
        -- :TSInstall mermaid
    end,
}
```

## ⚙️ Configuration

The default configuration works out of the box. You can customize standard options:

```lua
require('mermaid').setup({
    format = {
        shift_width = 2, -- Indentation size
    },
    lint = {
        enabled = true,  -- Enable usage of mmdc for checking errors
        command = "mmdc", -- Path to mermaid-cli executable
    }
})
```

## 🚀 Usage

### Commands

| Command | Description |
| :--- | :--- |
| `:MermaidPreview` | Open a Live Preview in your browser (localhost). Updates on edit. |
| `:MermaidFormat` | Auto-format the current buffer (indentation). |

### Keybindings

You can set up your own keybindings in your `init.lua` or `ftplugin/mermaid.lua`:

```lua
vim.api.nvim_create_autocmd("FileType", {
    pattern = "mermaid",
    callback = function()
        local buf = vim.api.nvim_get_current_buf()
        vim.keymap.set("n", "<leader>mp", "<cmd>MermaidPreview<CR>", { buffer = buf, desc = "Mermaid Preview" })
        vim.keymap.set("n", "<leader>mf", "<cmd>MermaidFormat<CR>", { buffer = buf, desc = "Mermaid Format" })
    end,
})
```

## 🛠️ Tree-sitter Setup

If you don't see syntax highlighting, ensure the parser is installed:

```vim
:TSInstall mermaid
```

## 📸 Preview Features

The live preview window includes a floating toolbar with:
- **Zoom In/Out/Reset**: Navigate complex diagrams easily.
- **Copy Image**: Renders a high-resolution PNG (3x scale) and copies it to your clipboard.
- **Download SVG**: Save the vector diagram locally.

## 🤝 Contributing

Pull requests are welcome! Please feel free to open an issue for bugs or feature requests.

## 📄 License

MIT
