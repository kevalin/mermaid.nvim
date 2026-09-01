local stub = require("luassert.stub")

describe("mermaid.nvim", function()

  describe("setup", function()
    it("can setup the plugin", function()
      require("mermaid").setup({ test_option = true })
      assert.is_true(true)
    end)

    it("defaults preview.port to 0", function()
      local mermaid = require("mermaid")
      mermaid.setup()
      assert.are.equal(0, mermaid.config.preview.port)
    end)

    it("allows configuring custom preview.port", function()
      local mermaid = require("mermaid")
      mermaid.setup({ preview = { port = 8080 } })
      assert.are.equal(8080, mermaid.config.preview.port)
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
