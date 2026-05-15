-- luacheck configuration for mermaid.nvim
-- https://github.com/lunarmodules/luacheck

std = "lua51"
globals = { "vim" }

-- Neovim-specific globals (no warning on these)
read_globals = {
  "vim",
}

-- Allow test files to use busted globals
files["tests/"] = {
  std = "+busted",
  globals = { "vim", "describe", "it", "before_each", "after_each", "assert" },
  ignore = {
    "581", -- operator used as a statement
    "211", -- unused variable (common in test mocks)
  },
}

-- Ignore harmless patterns
ignore = {
  "631", -- line too long (we use readable formatting)
}

exclude_files = {
  ".luacheckrc",
  ".git/**",
  "node_modules/**",
}
