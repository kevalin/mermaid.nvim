-- Additional edge cases for the format module:
-- comments, single quotes, directives, format-ignore marker
describe("mermaid format — edge cases v2", function()
  local format = require("mermaid.format")

  before_each(function()
    require("mermaid").setup({ format = { shift_width = 2 } })
    vim.o.expandtab = true
    vim.o.shiftwidth = 2
  end)

  local function format_text(input_lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, input_lines)
    vim.api.nvim_set_current_buf(buf)
    format.format()
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  describe("%% comments", function()
    it("preserves inline %% comments without padding inside them", function()
      local result = format_text({
        "flowchart TD",
        "A-->B %% this is a comment with --> inside",
        "B-->C",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("  A --> B %% this is a comment with --> inside", result[2])
      assert.are.same("  B --> C", result[3])
    end)

    it("preserves %% comments on standalone lines", function()
      local result = format_text({
        "flowchart LR",
        "%% This diagram shows the flow",
        "A-->B",
      })
      assert.are.same("flowchart LR", result[1])
      -- Comments should stay at base indent level (they're between top-level items)
      assert.are.same("  %% This diagram shows the flow", result[2])
      assert.are.same("  A --> B", result[3])
    end)

    it("does not break %%{init: ...}%% directives", function()
      local result = format_text({
        "%%{init: {'theme': 'dark'}}%%",
        "flowchart TD",
        "A-->B",
      })
      assert.are.same("%%{init: {'theme': 'dark'}}%%", result[1])
      assert.are.same("flowchart TD", result[2])
      assert.are.same("  A --> B", result[3])
    end)
  end)

  describe("single-quoted strings", function()
    it("preserves content inside single quotes", function()
      local result = format_text({
        "flowchart TD",
        "A-->|'arrow text with -->'|B",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("  A --> |'arrow text with -->'|B", result[2])
    end)
  end)

  describe("format-ignore marker", function()
    it("skips lines with -- mermaid-format-ignore", function()
      local result = format_text({
        "flowchart TD",
        "A-->B",
        "C--x D  -- mermaid-format-ignore",
        "E-->F",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("  A --> B", result[2])
      -- The ignored line should stay exactly as written
      assert.are.same("C--x D  -- mermaid-format-ignore", result[3])
      assert.are.same("  E --> F", result[4])
    end)

    it("skips lines with case-insensitive marker", function()
      local result = format_text({
        "flowchart LR",
        "A--x B  -- MERMAID-FORMAT-IGNORE",
      })
      assert.are.same("flowchart LR", result[1])
      assert.are.same("A--x B  -- MERMAID-FORMAT-IGNORE", result[2])
    end)
  end)

  describe("xychart and timeline (new diagram types)", function()
    it("handles xychart-beta", function()
      local result = format_text({
        "xychart-beta",
        "title \"Sales\"",
        "x-axis \"Months\" [jan, feb]",
        "y-axis \"Revenue\" [100, 200]",
        "bar [50, 60]",
        "line [70, 80]",
      })
      assert.are.same("xychart-beta", result[1])
      assert.are.same('  title "Sales"', result[2])
      assert.are.same('  x-axis "Months" [jan, feb]', result[3])
    end)

    it("handles timeline", function()
      local result = format_text({
        "timeline",
        "title History of Social Media",
        "2002 : LinkedIn",
        "2004 : Facebook",
        "2005 : YouTube",
        "2006 : Twitter",
      })
      assert.are.same("timeline", result[1])
      assert.are.same("  title History of Social Media", result[2])
    end)

    it("handles sankey-beta", function()
      local result = format_text({
        "sankey-beta",
        "Source1,Target1,10",
        "Source1,Target2,20",
      })
      assert.are.same("sankey-beta", result[1])
    end)
  end)

  describe("single braces in content", function()
    it("treats balanced braces on one line as self-closing", function()
      local result = format_text({
        "classDiagram",
        "class Animal {",
        "+int age",
        "}",
      })
      assert.are.same("classDiagram", result[1])
      assert.are.same("  class Animal {", result[2])
      assert.are.same("    +int age", result[3])
      assert.are.same("  }", result[4])
    end)
  end)

  describe("thin arrows handling", function()
    it("pads single -> and -x arrows", function()
      local result = format_text({
        "flowchart TD",
        "A->B",
        "C-xD",
        "E-)F",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("  A -> B", result[2])
      assert.are.same("  C -x D", result[3])
      assert.are.same("  E -) F", result[4])
    end)
  end)

  describe("multiple colons in labels", function()
    it("handles labels with multiple colons", function()
      local result = format_text({
        "sequenceDiagram",
        "Alice->>Bob: Hello: How are you?",
      })
      assert.are.same("sequenceDiagram", result[1])
      -- Every `:` now sits tight to the left word. This is a known limitation:
      -- the formatter doesn't distinguish structural `:` (label separator)
      -- from content `:` inside the message text.
      assert.are.same("  Alice ->> Bob: Hello: How are you?", result[2])
    end)
  end)

  describe("pipe-delimited labels", function()
    it("pads the first pipe but not the second (known limitation)", function()
      local result = format_text({
        "flowchart TD",
        "A-->|label|B",
      })
      assert.are.same("flowchart TD", result[1])
      -- First | gets padded via the ER cardinality pattern, second | doesn't
      assert.are.same("  A --> |label|B", result[2])
    end)
  end)

  describe("class assignment operator", function()
    it("does not split the ::: class assignment operator", function()
      local result = format_text({
        "flowchart TD",
        "A:::myClass --> B:::otherClass",
        "C:::class1-->D:::class2",
        "E ::: class3",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("  A:::myClass --> B:::otherClass", result[2])
      assert.are.same("  C:::class1 --> D:::class2", result[3])
      assert.are.same("  E:::class3", result[4])
    end)
  end)

  describe("empty buffer", function()
    it("handles completely empty buffer gracefully", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      -- Should not error
      format.format()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.are.same(1, #lines)
      assert.are.same("", lines[1])
    end)
  end)
end)
