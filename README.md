# mermaid.nvim 🧜

> A feature-rich Neovim plugin for working with [Mermaid](https://mermaid.js.org/) diagrams — preview, format, lint, and render inline in your terminal.

![License](https://img.shields.io/github/license/kevalin/mermaid.nvim)
![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.9.5-green)
![Test](https://github.com/kevalin/mermaid.nvim/actions/workflows/ci.yml/badge.svg)

---

## ✨ Features

| Feature | Description | Dependencies |
|---------|-------------|-------------|
| **Live Preview** | Real-time browser preview via built-in Lua HTTP server + SSE | None |
| **Dual Renderers** | Standard `mermaid.js` or aesthetic `beautiful-mermaid` | None |
| **Floating Panel** | In-editor control panel with URL, status, and quick actions | None |
| **Inline Render** | Render diagrams directly in Kitty/chafa-capable terminals | `mmdc` + chafa/Kitty |
| **Auto-Format** | Built-in Lua formatter for indentation and token spacing | None |
| **Diagnostics** | Lint with `vim.diagnostic` via mermaid-cli | `mmdc` (optional) |
| **Dark Mode** | Auto-detects Neovim `background` setting, live-syncs preview | None |
| **Toolbar** | Zoom, pan, copy PNG, download SVG in browser preview | None |

---

## 📦 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
    "kevalin/mermaid.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
        require("mermaid").setup()

        -- Install the Tree-sitter parser:
        -- :TSInstall mermaid
    end,
}
```

> **Note:** Requires Tree-sitter for syntax highlighting. Install with `:TSInstall mermaid`.

---

## ⚙️ Configuration

All options with defaults:

```lua
require("mermaid").setup({
    format = {
        shift_width = 4,           -- Indentation size (spaces)
    },
    lint = {
        enabled = true,            -- Enable diagnostics via mmdc
        command = "mmdc",          -- Path to mermaid-cli executable
    },
    preview = {
        renderer = "mermaid.js",   -- "mermaid.js" or "beautiful-mermaid"
        theme = "default",         -- Theme name (renderer-specific)
        port = nil,                -- Optional, specify a port to use. Not recommended if starting multiple sessions on the same host
    },
})
```

### Renderer Themes

**`mermaid.js`** (official): Uses Mermaid's built-in themes — `default`, `dark`, `forest`, `neutral`.

**`beautiful-mermaid`** (aesthetic):

| Palette | Light | Dark |
|---------|-------|------|
| Zinc | `zinc-light` ✅ | `zinc-dark` ✅ |
| Tokyo Night | `tokyo-night-light` | `tokyo-night-storm`, `tokyo-night` |
| Catppuccin | `catppuccin-latte` | `catppuccin-mocha` ✅ |
| Nord | `nord-light` | `nord` |
| Dracula | — | `dracula` ✅ |
| GitHub | `github-light` | `github-dark` |
| Solarized | `solarized-light` | `solarized-dark` |
| One Dark | — | `one-dark` |

> ✅ = recommended starters

---

## 🚀 Commands

| Command | Description |
|---------|-------------|
| `:MermaidPreview` | Open live browser preview (auto-updates on edit) |
| `:MermaidPreviewStop` | Stop the preview server |
| `:MermaidFormat` | Auto-format current buffer |
| `:MermaidRender` | Render inline in Kitty/chafa terminals |
| `:MermaidCopyURL` | Copy preview URL to clipboard |

### Suggested Keybindings

```lua
vim.api.nvim_create_autocmd("FileType", {
    pattern = "mermaid",
    callback = function()
        local buf = vim.api.nvim_get_current_buf()
        vim.keymap.set("n", "<leader>mp", "<cmd>MermaidPreview<CR>",
            { buffer = buf, desc = "Mermaid Preview" })
        vim.keymap.set("n", "<leader>mf", "<cmd>MermaidFormat<CR>",
            { buffer = buf, desc = "Mermaid Format" })
        vim.keymap.set("n", "<leader>mr", "<cmd>MermaidRender<CR>",
            { buffer = buf, desc = "Mermaid Render" })
        vim.keymap.set("n", "<leader>mc", "<cmd>MermaidCopyURL<CR>",
            { buffer = buf, desc = "Mermaid Copy URL" })
        vim.keymap.set("n", "<leader>mx", "<cmd>MermaidPreviewStop<CR>",
            { buffer = buf, desc = "Mermaid Stop Preview" })
    end,
})
```

---

## 🖼️ Renderer Comparison

**Input:**
```
flowchart TD
  A(Start) --> B{Is it sunny?}
  B -- Yes --> C[Go to the park]
  B -- No --> D[Stay indoors]
  C --> E[Finish]
  D --> E
```

### beautiful-mermaid (Premium aesthetic)
Designed for modern, high-quality diagram rendering.

![beautiful-mermaid example](media/preview-beautiful.png)

> **[!NOTE]**
> `beautiful-mermaid` uses a simplified parser. Complex diagrams with **Font Awesome icons** or **edge labels** (`A --> |label| B`) should use `mermaid.js`.

### mermaid.js (Full specification)
Supports the complete Mermaid feature set.

![mermaid.js example](media/preview-mermaid.png)

---

## 🧑‍💻 Terminal Inline Rendering

`mermaid.nvim` can render diagrams directly in your terminal:

```
kitty protocol  ─── ✅ Full-color, scalable SVG rendering
chafa           ─── ✅ ASCII/ANSI art (works in any terminal)
sixel           ─── ⏳ Planned
iTerm2          ─── ⏳ Planned
```

Run `:MermaidRender` to try it. The plugin auto-detects your terminal's capabilities.

---

## 📂 Filetype Detection

| Extension | Filetype |
|-----------|----------|
| `.mmd` | `mermaid` |
| `.mermaid` | `mermaid` |

---

## ❓ FAQ

**Q: The preview opens but shows "Loading..."**
A: Make sure you have content in your buffer and the SSE connection is established. Check the connection status indicator (top-right of the preview page).

**Q: `:MermaidFormat` broke my diagram**
A: Add `-- mermaid-format-ignore` at the end of lines you want to skip. File a bug report with the Mermaid code if it's a genuine formatting error.

**Q: How do I use `mermaid-cli` for diagnostics?**
A: Install it globally: `npm install -g @mermaid-js/mermaid-cli`. The plugin auto-detects the `mmdc` binary.

**Q: Can I use this without a browser?**
A: Yes! Use `:MermaidRender` with Kitty terminal or `chafa` installed for inline rendering.

**Q: The preview page is white in dark mode**
A: The plugin auto-detects your Neovim `background` setting. Run `:set background=dark` and the preview will sync. If it doesn't, restart the preview with `:MermaidPreviewStop` then `:MermaidPreview`.

**Q: Does this work on Windows?**
A: The plugin is Lua-based so it runs anywhere Neovim runs. The built-in server uses `vim.loop` which is cross-platform.

---

## 🔧 Troubleshooting

### Preview not opening
- **Check the server**: `:lua print(require("mermaid.server").port)`
- **Manual open**: Navigate to `http://localhost:<port>` in your browser
- **Check logs**: `:messages` for Mermaid-related notifications

### Formatting issues
- **Wrong indentation**: Adjust `shift_width` in config
- **Broken syntax**: Use `-- mermaid-format-ignore` on problem lines
- **Missing diagram type**: Some block structures may need a custom pattern — open an issue

### Inline rendering not working
- **Terminal detection**: `:lua print(require("mermaid.render").detect_capability())`
- **Kitty**: Ensure `kitty +kitten icat` works: `echo test | kitty +kitten icat`
- **chafa**: `chafa --version` should print a version ≥ 0.8

### Diagnostics not showing errors
- **Ensure mmdc is installed**: `which mmdc`
- **Test manually**: `echo "graph TD\nA-->B" | mmdc -i - -o /tmp/test.svg`
- **Check config**: `lint.enabled` must be `true` in setup

---

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Project structure overview
- Development setup (`make test`)
- Code style guide
- Commit conventions (Conventional Commits)

---

## 🗺️ Roadmap

- [x] Live preview with SSE
- [x] Built-in Lua HTTP server
- [x] Dual renderers (mermaid.js + beautiful-mermaid)
- [x] Auto-formatting
- [x] Lint via diagnostics
- [x] CI/CD (GitHub Actions)
- [x] Dark mode adaptive preview
- [x] Floating panel in-editor
- [x] Terminal inline rendering
- [ ] Split-window preview mode
- [ ] SVG export with custom dimensions
- [ ] Snippet support for Mermaid diagrams
- [ ] Obsidian-style diagram embedding

---

## ❤️ Credits

- [mermaid.js](https://mermaid.js.org/) — Diagram rendering engine
- [beautiful-mermaid](https://github.com/lukilabs/beautiful-mermaid) — Aesthetic renderer
- [svg-pan-zoom](https://github.com/bumbu/svg-pan-zoom) — Interactive zoom/pan

## 📄 License

MIT — see [LICENSE](LICENSE)
