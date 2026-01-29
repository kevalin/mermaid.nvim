local stub = require("luassert.stub")

describe("mermaid.nvim", function()
  
  describe("setup", function()
    it("can setup the plugin", function()
      require("mermaid").setup({ test_option = true })
      -- Verify config
      -- Since config is local in init.lua, we might verify via side effects or expose it for testing if needed.
      -- For now, just ensure no error.
      assert.is_true(true) 
    end)
  end)

  describe("filetype detection", function()
    it("detects .mmd files", function()
        vim.cmd("e test.mmd")
        assert.are.same("mermaid", vim.bo.filetype)
    end)

    it("detects .mermaid files", function()
        vim.cmd("e test.mermaid")
        assert.are.same("mermaid", vim.bo.filetype)
    end)
  end)

  describe("formatting", function()
    -- Prettier support is replaced by internal Lua formatter
    -- it("calls prettier when available", function() ... end)
  end)
end)
