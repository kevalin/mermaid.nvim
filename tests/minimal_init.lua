     1|local function ensure_plenary()
     2|  local plenary_dir = "/tmp/plenary.nvim"
     3|  local is_not_present = vim.fn.empty(vim.fn.glob(plenary_dir)) > 0
     4|  if is_not_present then
     5|    print("Downloading plenary.nvim...")
     6|    vim.fn.system({'git', 'clone', '--depth', '1', 'https://github.com/nvim-lua/plenary.nvim.git', plenary_dir})
     7|  end
     8|  vim.opt.rtp:append(plenary_dir)
     9|  vim.opt.rtp:append(".")
    10|end
    11|
    12|ensure_plenary()
    13|
    14|<<<<<<< HEAD
    15|require("mermaid").setup({})
    16|=======
    17|vim.o.expandtab = true
    18|
    19|require("mermaid").setup({ format = { shift_width = 2 } })
    20|>>>>>>> origin/main
    21|require("mermaid.server")._test_mode = true  -- Skip idle monitor in tests
    22|require("plenary.busted") -- Ensure plenary is loaded
    23|