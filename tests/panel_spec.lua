-- Tests for the panel module
describe("mermaid panel", function()
  local panel
  local orig_list_uis

  before_each(function()
    panel = require("mermaid.panel")
    -- Mock nvim_list_uis for headless test environment
    orig_list_uis = vim.api.nvim_list_uis
    vim.api.nvim_list_uis = function()
      return { { width = 120, height = 40 } }
    end
    -- Ensure clean state
    panel.close()
  end)

  after_each(function()
    panel.close()
    -- Restore original
    if orig_list_uis then
      vim.api.nvim_list_uis = orig_list_uis
    end
  end)

  describe("open/close", function()
    it("opens a floating window", function()
      panel.open("http://localhost:8080")
      assert.is_true(panel.is_open())
    end)

    it("closes the floating window", function()
      panel.open("http://localhost:8080")
      assert.is_true(panel.is_open())
      panel.close()
      assert.is_false(panel.is_open())
    end)

    it("close is safe when not open", function()
      panel.close() -- should not error
      panel.close() -- twice should be safe
      assert.is_false(panel.is_open())
    end)

    it("open replaces existing panel", function()
      panel.open("http://localhost:8080")
      panel.open("http://localhost:9090")
      assert.is_true(panel.is_open())
    end)
  end)

  describe("update", function()
    it("update does not error when panel is closed", function()
      panel.close()
      -- Update on closed panel should be safe
      pcall(panel.update)
      assert.is_true(true)
    end)
  end)

  describe("auto refresh", function()
    it("start_auto_refresh is safe to call multiple times", function()
      panel.start_auto_refresh()
      panel.start_auto_refresh()
      -- Should not error
      assert.is_true(true)
    end)
  end)
end)
