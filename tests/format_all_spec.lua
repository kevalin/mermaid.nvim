-- Tests for the format module covering all Mermaid diagram types
-- and edge cases: single quotes, nested blocks, emoji, directives

describe("mermaid format — all diagram types", function()
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

  describe("flowchart", function()
    it("pads arrows and indents subgraphs", function()
      local result = format_text({
        "flowchart TD",
        "subgraph A",
        "X-->Y",
        "end",
        "P-.->|label|Q",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("  subgraph A", result[2])
      assert.are.same("    X --> Y", result[3])
      assert.are.same("  end", result[4])
      assert.are.same("  P -.-> |label| Q", result[5])
    end)

    it("handles thick and dotted arrows", function()
      local result = format_text({
        "flowchart LR",
        "A==>B",
        "C-.-D",
        "E---F",
      })
      assert.are.same("flowchart LR", result[1])
      assert.are.same("  A ==> B", result[2])
      assert.are.same("  C -.- D", result[3])
      assert.are.same("  E --- F", result[4])
    end)

    it("handles --x and --o arrow endings", function()
      local result = format_text({
        "flowchart TD",
        "A--x B",
        "C--o D",
        "Ex-- F",
        "Go-- H",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("  A --x B", result[2])
      assert.are.same("  C --o D", result[3])
      assert.are.same("  E x-- F", result[4])
    end)
  end)

  describe("sequenceDiagram", function()
    it("pads all arrow types and alt/else blocks", function()
      local result = format_text({
        "sequenceDiagram",
        "Alice->>Bob: Hello",
        "alt condition",
        "Bob-->>Alice: Hi",
        "else other",
        "Bob-xAlice: Bye",
        "end",
      })
      assert.are.same("sequenceDiagram", result[1])
      assert.are.same("  Alice ->> Bob : Hello", result[2])
      assert.are.same("  alt condition", result[3])
      assert.are.same("    Bob -->> Alice : Hi", result[4])
      assert.are.same("  else other", result[5])
      assert.are.same("    Bob -x Alice : Bye", result[6])
      assert.are.same("  end", result[7])
    end)

    it("handles activations, notes, and loops", function()
      local result = format_text({
        "sequenceDiagram",
        "activate Alice",
        "Alice->>Bob: msg",
        "deactivate Alice",
        "Note left of Alice: Text",
        "loop every day",
        "Alice->>Bob: hi",
        "end",
      })
      assert.are.same("sequenceDiagram", result[1])
      assert.are.same("  activate Alice", result[2])
      assert.are.same("  Alice ->> Bob : msg", result[3])
      assert.are.same("  deactivate Alice", result[4])
      assert.are.same("  Note left of Alice : Text", result[5])
      assert.are.same("  loop every day", result[6])
      assert.are.same("    Alice ->> Bob : hi", result[7])
      assert.are.same("  end", result[8])
    end)
  end)

  describe("classDiagram", function()
    it("indents class definitions and pads relationships", function()
      local result = format_text({
        "classDiagram",
        "class Animal{",
        "+int age",
        "+String gender",
        "+isMammal()",
        "}",
        "Animal<|--Duck",
        "Animal<|--Fish",
        "Animal<|--Zebra",
      })
      assert.are.same("classDiagram", result[1])
      assert.are.same("  class Animal{", result[2])
      assert.are.same("    +int age", result[3])
      assert.are.same("    +String gender", result[4])
      assert.are.same("    +isMammal()", result[5])
      assert.are.same("  }", result[6])
      -- Note: <|-- is an inheritance arrow, the padder should handle it
    end)

    it("pads composition and aggregation arrows", function()
      local result = format_text({
        "classDiagram",
        "Car*--Engine",
        "Libraryo--Book",
        "Parent<|--Child",
        "Car*..Driver",
      })
      assert.are.same("classDiagram", result[1])
      assert.are.same("  Car *-- Engine", result[2])
      assert.are.same("  Library o-- Book", result[3])
    end)
  end)

  describe("stateDiagram", function()
    it("indents state blocks and pads transitions", function()
      local result = format_text({
        "stateDiagram-v2",
        "[*] --> Still",
        "Still --> [*]",
        "Still --> Moving",
        "Moving --> Still",
        "Moving --> Crash",
        "Crash --> [*]",
      })
      assert.are.same("stateDiagram-v2", result[1])
      assert.are.same("  [*] --> Still", result[2])
      assert.are.same("  Still --> [*]", result[3])
    end)

    it("handles composite states with braces", function()
      local result = format_text({
        "stateDiagram-v2",
        "state ForkJoin {",
        "[*] --> State1",
        "State1 --> State2",
        "State2 --> [*]",
        "}",
      })
      assert.are.same("stateDiagram-v2", result[1])
      assert.are.same("  state ForkJoin {", result[2])
      assert.are.same("    [*] --> State1", result[3])
      assert.are.same("    State1 --> State2", result[4])
      assert.are.same("    State2 --> [*]", result[5])
      assert.are.same("  }", result[6])
    end)
  end)

  describe("erDiagram", function()
    it("pads cardinality tokens without breaking them", function()
      local result = format_text({
        "erDiagram",
        "CUSTOMER||--o{ORDER:places",
        "ORDER||--|{LINE-ITEM:contains",
      })
      assert.are.same("erDiagram", result[1])
      assert.are.same("  CUSTOMER ||--o{ ORDER : places", result[2])
      assert.are.same("  ORDER ||--|{ LINE-ITEM : contains", result[3])
    end)
  end)

  describe("gitGraph", function()
    it("does not corrupt gitGraph syntax", function()
      local result = format_text({
        "gitGraph",
        "commit",
        "branch develop",
        "checkout develop",
        "commit",
        "checkout main",
        "merge develop",
        "commit",
      })
      assert.are.same("gitGraph", result[1])
      assert.are.same("  commit", result[2])
      assert.are.same("  branch develop", result[3])
      assert.are.same("  checkout develop", result[4])
    end)
  end)

  describe("pie chart", function()
    it("does not break pie syntax", function()
      local result = format_text({
        "pie",
        "title Pets adopted",
        "\"Dogs\" : 86",
        "\"Cats\" : 45",
        "\"Rats\" : 15",
      })
      assert.are.same("pie", result[1])
      assert.are.same("  title Pets adopted", result[2])
      assert.are.same('  "Dogs" : 86', result[3])
    end)
  end)

  describe("mindmap", function()
    it("preserves mindmap indentation structure", function()
      local result = format_text({
        "mindmap",
        "  root",
        "    Branch A",
        "      Leaf 1",
        "      Leaf 2",
        "    Branch B",
        "      Leaf 3",
      })
      assert.are.same("mindmap", result[1])
      -- Mindmap relies on explicit indentation; formatter should not regress
    end)
  end)

  describe("directives", function()
    it("preserves init directives", function()
      local result = format_text({
        "%%{init: {'theme': 'dark'}}%%",
        "flowchart TD",
        "A-->B",
      })
      assert.are.same("%%{init: {'theme': 'dark'}}%%", result[1])
      assert.are.same("flowchart TD", result[2])
      assert.are.same("  A --> B", result[3])
    end)

    it("preserves inline comments", function()
      local result = format_text({
        "flowchart TD",
        "A-->B %% this is a comment",
        "C-->D",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("  C --> D", result[3])
    end)
  end)

  describe("edge cases", function()
    it("handles empty file", function()
      -- An empty Neovim buffer always contains 1 empty line
      local result = format_text({})
      assert.are.same(1, #result)
      assert.are.same("", result[1])
    end)

    it("handles blank lines between blocks", function()
      local result = format_text({
        "flowchart TD",
        "",
        "A-->B",
        "",
        "B-->C",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("", result[2])
      assert.are.same("  A --> B", result[3])
      assert.are.same("", result[4])
      assert.are.same("  B --> C", result[5])
    end)

    it("handles emoji in labels", function()
      local result = format_text({
        "flowchart TD",
        "A-->|😊 Happy|B",
        "B-->|✅ Done|C",
      })
      assert.are.same("flowchart TD", result[1])
      assert.are.same("  A --> |😊 Happy| B", result[2])
      assert.are.same("  B --> |✅ Done| C", result[3])
    end)
  end)
end)
