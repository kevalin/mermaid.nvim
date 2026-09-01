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

  describe("preview port integration", function()
    it("forwards configured port to server.start_server", function()
      local mermaid = require("mermaid")
      local server = require("mermaid.server")
      local passed_port = nil
      local s = stub(server, "start_server", function(port)
        passed_port = port
        return nil
      end)

      mermaid.setup({ preview = { port = 7890 } })
      require("mermaid.preview").preview()

      assert.are.equal(7890, passed_port)
      s:revert()
    end)
  end)
end)
