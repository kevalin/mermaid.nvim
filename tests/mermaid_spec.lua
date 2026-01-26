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
    it("calls prettier when available", function()
      -- Mock vim.fn.executable and vim.fn.system
      local original_executable = vim.fn.executable
      local original_system = vim.fn.system
      
      vim.fn.executable = function(cmd)
        if cmd == "prettier" then return 1 end
        return original_executable(cmd)
      end
      
      local system_stub = stub(vim.fn, "system")
      system_stub.returns("formatted code")
      
      -- Helper: put some lines
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {"original code"})
      
      require("mermaid.format").format()
      
      assert.stub(system_stub).was_called()
      
      -- Restore
      vim.fn.executable = original_executable
      system_stub:revert()
    end)
  end)
end)
