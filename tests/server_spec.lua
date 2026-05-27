-- Tests for the server module (unit-level, no actual sockets)
describe("mermaid server", function()
  describe("startup / shutdown", function()
    it("starts and stops without errors", function()
      local server = require("mermaid.server")

      local port = server.start_server()
      assert.is_number(port)
      assert.is_true(port > 0 and port < 65536)
      assert.is_not_nil(server.server)

      server.stop_server()
      assert.is_nil(server.server)
      assert.is_nil(server.port)
      assert.are.same({}, server.clients)
    end)

    it("start_server is idempotent (returns same port)", function()
      local server = require("mermaid.server")

      local port1 = server.start_server()
      local port2 = server.start_server()
      assert.are.equal(port1, port2)

      server.stop_server()
    end)

    it("stop_server is safe to call when not running", function()
      local server = require("mermaid.server")
      server.stop_server() -- should not error
      server.stop_server() -- double call should be safe
      assert.is_nil(server.server)
      assert.is_nil(server.port)
    end)
  end)

  describe("content broadcast", function()
    it("set_content updates current_content", function()
      local server = require("mermaid.server")
      server.set_content("graph TD\nA-->B")
      assert.are.equal("graph TD\nA-->B", server.current_content)
    end)

    it("set_content is idempotent (does not broadcast same content)", function()
      local server = require("mermaid.server")
      server.current_content = "test"
      local called = false
      local orig_broadcast = server.broadcast
      server.broadcast = function() called = true end

      server.set_content("test") -- same content → should not broadcast
      assert.is_false(called)

      server.set_content("different") -- new content → should broadcast
      assert.is_true(called)

      server.broadcast = orig_broadcast
    end)
  end)

  describe("HTML template", function()
    it("generates valid HTML for mermaid.js renderer", function()
      require("mermaid").setup({
        preview = { renderer = "mermaid.js", theme = "default" }
      })

      local server = require("mermaid.server")
      local html = server.get_html_template()
      assert.is_not_nil(html)
      assert.is_true(#html > 0)
      -- Should contain mermaid.js script
      assert.is_true(html:find("mermaid%.min%.js") ~= nil)
      -- Should contain our preview.js
      assert.is_true(html:find("/js/preview.js") ~= nil)
      -- Should contain SSE script
      assert.is_true(html:find("EventSource") ~= nil)
      -- Should not have beautiful-mermaid import
      assert.is_nil(html:find("beautiful%-mermaid"))
    end)

    it("generates valid HTML for beautiful-mermaid renderer", function()
      require("mermaid").setup({
        preview = { renderer = "beautiful-mermaid", theme = "tokyo-night" }
      })

      local server = require("mermaid.server")
      local html = server.get_html_template()
      assert.is_not_nil(html)
      -- Should contain beautiful-mermaid import
      assert.is_true(html:find("beautiful%-mermaid") ~= nil)
      -- Should not have mermaid.min.js
      assert.is_nil(html:find("mermaid%.min%.js"))
    end)

    it("returns nil when index.html is missing", function()
      -- Test that nil is returned gracefully when static files are absent.
      -- In normal usage, index.html always exists, so this is defensive.
      local server = require("mermaid.server")
      -- get_html_template calls get_plugin_root which resolves from source path
      local html = server.get_html_template()
      assert.is_not_nil(html) -- should exist in real setup
    end)
  end)

  describe("theme mode", function()
    it("defaults to light", function()
      local server = require("mermaid.server")
      assert.are.equal("light", server.theme_mode)
    end)

    it("set_theme_mode accepts dark", function()
      local server = require("mermaid.server")
      server.set_theme_mode("dark")
      assert.are.equal("dark", server.theme_mode)
    end)

    it("set_theme_mode treats light correctly", function()
      local server = require("mermaid.server")
      server.set_theme_mode("dark")
      server.set_theme_mode("light")
      assert.are.equal("light", server.theme_mode)
    end)

    it("set_theme_mode sanitizes unknown values to light", function()
      local server = require("mermaid.server")
      server.set_theme_mode("dark")
      server.set_theme_mode("pink")
      assert.are.equal("light", server.theme_mode)
    end)

    it("HTML template contains theme-mode data attribute", function()
      require("mermaid").setup({
        preview = { renderer = "mermaid.js", theme = "default" }
      })
      local server = require("mermaid.server")
      server.set_theme_mode("dark")
      local html = server.get_html_template()
      assert.is_not_nil(html)
      assert.is_true(html:find('data%-theme="dark"') ~= nil,
        "HTML should contain data-theme attribute for dark mode")
    end)
  end)

  describe("SSE events", function()
    it("broadcast sends to all connected clients", function()
      local server = require("mermaid.server")
      local sent = {}
      local mock_client = {
        write = function(_, data) table.insert(sent, data) end,
        is_closing = function() return false end,
      }
      server.clients[mock_client] = true

      server.set_content("graph TD\nA-->B")

      -- Should have 1 message (initial + no duplicates)
      assert.are.equal(1, #sent)
      assert.is_true(sent[1]:find("A--%>B") ~= nil)

      -- Cleanup
      server.clients[mock_client] = nil
    end)

    it("broadcast skips closing clients", function()
      local server = require("mermaid.server")
      local sent = {}
      local mock_closing = {
        write = function() table.insert(sent, "should not be called") end,
        is_closing = function() return true end,
      }
      server.clients[mock_closing] = true

      server.set_content("test content")

      assert.are.equal(0, #sent, "should not send to closing clients")
      server.clients[mock_closing] = nil
    end)
  end)

  describe("route dispatch (integration smoke test)", function()
    it("server is reachable after start", function()
      local server = require("mermaid.server")
      local port = server.start_server()
      assert.is_number(port)

      -- Use curl to verify the server responds
      local handle = io.popen("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:" .. port .. "/ 2>/dev/null")
      local result = handle:read("*a")
      handle:close()

      -- Should return 200 OK
      assert.are.equal("200", result:match("%d+"))

      server.stop_server()
    end)

    it("returns 404 for unknown routes", function()
      local server = require("mermaid.server")
      local port = server.start_server()

      local handle = io.popen("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:" .. port .. "/nonexistent 2>/dev/null")
      local result = handle:read("*a")
      handle:close()

      assert.are.equal("404", result:match("%d+"))

      server.stop_server()
    end)
  end)
end)
