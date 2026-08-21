local function ensure_plenary()
  local plenary_dir = "/tmp/plenary.nvim"
  local is_not_present = vim.fn.empty(vim.fn.glob(plenary_dir)) > 0
  if is_not_present then
    print("Downloading plenary.nvim...")
    vim.fn.system({'git', 'clone', '--depth', '1', 'https://github.com/nvim-lua/plenary.nvim.git', plenary_dir})
  end
  vim.opt.rtp:append(plenary_dir)
  vim.opt.rtp:append(".")
end

ensure_plenary()

vim.o.expandtab = true

require("mermaid").setup({
  format = { shift_width = 2 },
  lint = { enabled = false },
  preview = { enabled = false },
})
require("mermaid.server")._test_mode = true  -- Skip idle monitor in tests
require("plenary.busted") -- Ensure plenary is loaded
