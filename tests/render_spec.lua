-- Tests for the render module
describe("mermaid render", function()
  local render

  before_each(function()
    render = require("mermaid.render")
  end)

  describe("capability detection", function()
    it("detect_capability always returns a valid string", function()
      local cap = render.detect_capability()
      assert.is_string(cap)
      local valid = { kitty = true, iterm2 = true, sixel = true, chafa = true, none = true }
      assert.is_true(valid[cap] ~= nil, "Unexpected capability: " .. cap)
    end)

    it("capability_label returns a human-readable label", function()
      local label = render.capability_label("kitty")
      assert.is_string(label)
      assert.is_true(#label > 0)

      assert.is_string(render.capability_label("none"))
      assert.is_string(render.capability_label("chafa"))
    end)

    it("capability_label handles unknown values", function()
      local label = render.capability_label("unknown_protocol")
      assert.is_string(label)
    end)

    it("is_available returns boolean", function()
      local avail = render.is_available()
      assert.is_boolean(avail)
    end)

    it("does not identify an unrelated terminal as kitty just because kitty is installed", function()
      local original_path = vim.env.PATH
      local original_kitty_window_id = vim.env.KITTY_WINDOW_ID
      local original_term_program = vim.env.TERM_PROGRAM
      local original_term = vim.env.TERM
      local temp_dir = vim.fn.tempname()
      local kitty_path = temp_dir .. "/kitty"

      vim.fn.mkdir(temp_dir, "p")
      vim.fn.writefile({ "#!/bin/sh", "exit 0" }, kitty_path)
      vim.fn.setfperm(kitty_path, "rwxr-xr-x")
      vim.env.PATH = temp_dir
      vim.env.KITTY_WINDOW_ID = nil
      vim.env.TERM_PROGRAM = "unrelated-terminal"
      vim.env.TERM = "dumb"

      local capability = render.detect_capability()

      vim.env.PATH = original_path
      vim.env.KITTY_WINDOW_ID = original_kitty_window_id
      vim.env.TERM_PROGRAM = original_term_program
      vim.env.TERM = original_term
      vim.fn.delete(temp_dir, "rf")

      assert.are.equal("none", capability)
    end)

    it("recognizes Ghostty as a kitty graphics terminal", function()
      local original_path = vim.env.PATH
      local original_kitty_window_id = vim.env.KITTY_WINDOW_ID
      local original_term_program = vim.env.TERM_PROGRAM
      local original_term = vim.env.TERM
      local temp_dir = vim.fn.tempname()
      local kitty_path = temp_dir .. "/kitty"

      vim.fn.mkdir(temp_dir, "p")
      vim.fn.writefile({ "#!/bin/sh", "exit 0" }, kitty_path)
      vim.fn.setfperm(kitty_path, "rwxr-xr-x")
      vim.env.PATH = temp_dir
      vim.env.KITTY_WINDOW_ID = nil
      vim.env.TERM_PROGRAM = "ghostty"
      vim.env.TERM = "xterm-ghostty"

      local capability = render.detect_capability()

      vim.env.PATH = original_path
      vim.env.KITTY_WINDOW_ID = original_kitty_window_id
      vim.env.TERM_PROGRAM = original_term_program
      vim.env.TERM = original_term
      vim.fn.delete(temp_dir, "rf")

      assert.are.equal("kitty", capability)
    end)
  end)

  describe("SVG generation", function()
    it("generate_svg returns error when mmdc is absent", function()
      -- This test should work regardless of mmdc being installed
      local result = render.generate_svg("graph TD\nA-->B")
      -- If mmdc exists, it might succeed. If not, should return error.
      assert.is_table(result)
      assert.is_boolean(result.ok)
      if not result.ok then
        assert.is_string(result.error)
      end
    end)

    it("generate_svg accepts custom output path", function()
      local tmp = os.tmpname() .. ".svg"
      local result = render.generate_svg("graph LR\nX-->Y", tmp)
      -- Cleanup if file was created
      pcall(os.remove, tmp)
      assert.is_table(result)
    end)
  end)

  describe("file rendering", function()
    it("render_file returns error for non-existent file", function()
      local result = render.render_file("/nonexistent/file.svg")
      assert.is_false(result.ok)
      assert.is_string(result.error)
    end)

    it("uses chafa without invoking kitty when raw TUI output is unavailable", function()
      local original_path = vim.env.PATH
      local original_kitty_window_id = vim.env.KITTY_WINDOW_ID
      local original_ui_send = vim.api.nvim_ui_send
      local original_list_uis = vim.api.nvim_list_uis
      local temp_dir = vim.fn.tempname()
      local image_path = temp_dir .. "/diagram.svg"
      local kitty_marker = temp_dir .. "/kitty.called"

      vim.fn.mkdir(temp_dir, "p")

      local function write_executable(name, body)
        local path = temp_dir .. "/" .. name
        vim.fn.writefile({ "#!/bin/sh", body }, path)
        vim.fn.setfperm(path, "rwxr-xr-x")
      end

      write_executable("kitty", "echo called > '" .. kitty_marker .. "'; exit 1")
      write_executable("chafa", "exit 0")
      vim.fn.writefile({ "<svg xmlns='http://www.w3.org/2000/svg'></svg>" }, image_path)

      vim.env.PATH = temp_dir
      vim.env.KITTY_WINDOW_ID = "1"
      vim.api.nvim_ui_send = function() error("GUI should not receive terminal escape sequences") end
      vim.api.nvim_list_uis = function()
        return { { width = 80, height = 24, stdout_tty = false } }
      end

      local ok, result = pcall(render.render_file, image_path)
      local kitty_called = vim.fn.filereadable(kitty_marker)

      vim.env.PATH = original_path
      vim.env.KITTY_WINDOW_ID = original_kitty_window_id
      vim.api.nvim_ui_send = original_ui_send
      vim.api.nvim_list_uis = original_list_uis
      vim.fn.delete(temp_dir, "rf")

      assert.is_true(ok)
      assert.is_true(result.ok)
      assert.are.equal("chafa", result.method)
      assert.are.equal(0, kitty_called)
    end)

    it("sends no-TTY kitty output to the host UI when supported", function()
      local original_path = vim.env.PATH
      local original_kitty_window_id = vim.env.KITTY_WINDOW_ID
      local original_ui_send = vim.api.nvim_ui_send
      local original_list_uis = vim.api.nvim_list_uis
      local temp_dir = vim.fn.tempname()
      local image_path = temp_dir .. "/diagram.svg"
      local sent

      vim.fn.mkdir(temp_dir, "p")

      local kitty_path = temp_dir .. "/kitty"
      vim.fn.writefile({
        "#!/bin/sh",
        "case \"$*\" in",
        "  *--stdin=no*--use-window-size*--place*--transfer-mode=stream*) printf '\\033_Gpayload\\033\\\\'; exit 0 ;;",
        "esac",
        "echo '/dev/tty: device not configured'; exit 1",
      }, kitty_path)
      vim.fn.setfperm(kitty_path, "rwxr-xr-x")
      vim.fn.writefile({ "<svg xmlns='http://www.w3.org/2000/svg'></svg>" }, image_path)

      vim.env.PATH = temp_dir
      vim.env.KITTY_WINDOW_ID = "1"
      vim.api.nvim_ui_send = function(content) sent = content end
      vim.api.nvim_list_uis = function()
        return { { width = 80, height = 24, stdout_tty = true } }
      end

      local ok, result = pcall(render.render_file, image_path)

      vim.env.PATH = original_path
      vim.env.KITTY_WINDOW_ID = original_kitty_window_id
      vim.api.nvim_ui_send = original_ui_send
      vim.api.nvim_list_uis = original_list_uis
      vim.fn.delete(temp_dir, "rf")

      assert.is_true(ok)
      assert.is_true(result.ok)
      assert.are.equal("kitty", result.method)
      assert.are.equal("\27_Gpayload\27\\", sent)
    end)
  end)

  describe("source rendering", function()
    it("render_source works end-to-end or returns a clear error", function()
      local result = render.render_source("graph TD\nA-->B")
      assert.is_table(result)
      -- Either succeeds (uncommon without mmdc) or gives a clear error
      if not result.ok then
        assert.is_string(result.error)
      end
    end)
  end)
end)
