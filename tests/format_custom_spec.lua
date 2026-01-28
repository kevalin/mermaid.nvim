local stub = require("luassert.stub")

describe("mermaid formatted", function()
  
  -- Mock vim.notify to avoid noise
  local original_notify = vim.notify
  before_each(function()
    vim.notify = function() end
  end)
  after_each(function()
    vim.notify = original_notify
  end)

  it("formats complex flowchart", function()
    local input = {
      "flowchart TD",
      "subgraph One",
      "A-->B",
      "end",
      "C-.->D"
    }
    
    -- Setup buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, input)
    vim.api.nvim_set_current_buf(buf)
    
    -- Run format
    require("mermaid.format").format()
    
    local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    
    assert.are.same("flowchart TD", content[1])
    assert.are.same("  subgraph One", content[2])
    assert.are.same("    A --> B", content[3])
    assert.are.same("  end", content[4])
    assert.are.same("  C -.-> D", content[5])
  end)

  it("formats ER diagram with cardinality", function()
    local input = {
      "erDiagram",
      "CUSTOMER ||--o{ ORDER : places",
      "ORDER ||--|{ LINE-ITEM : contains"
    }
    
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, input)
    vim.api.nvim_set_current_buf(buf)
    
    require("mermaid.format").format()
    local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    
    assert.are.same("erDiagram", content[1])
    -- Expect spaces around tokens
    assert.are.same("  CUSTOMER ||--o{ ORDER : places", content[2])
    assert.are.same("  ORDER ||--|{ LINE-ITEM : contains", content[3])
  end)

  it("formats Sequence diagram with alt/else", function()
    local input = {
      "sequenceDiagram",
      "Alice->>Bob: Hello",
      "alt is sick",
      "Bob-->>Alice: Not well",
      "else is well",
      "Bob-->>Alice: Good",
      "end"
    }
    
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, input)
    vim.api.nvim_set_current_buf(buf)
    
    require("mermaid.format").format()
    local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    
    assert.are.same("sequenceDiagram", content[1])
    assert.are.same("  Alice ->> Bob : Hello", content[2]) -- checking colon pad
    assert.are.same("  alt is sick", content[3])
    assert.are.same("    Bob -->> Alice : Not well", content[4])
    assert.are.same("  else is well", content[5]) -- dedented to level 1 (inside seq which is 1? No seq is 0->1. alt is 1->2. else at 1.)
    -- Wait: sequenceDiagram is Start Block? Yes (lev 0->1).
    -- Alice (1).
    -- alt (1->2). (prints at 1).
    -- Bob (2).
    -- else (prints at 1).
    -- Bob (2).
    -- end (prints at 1, dedents 2->1).
    
    assert.are.same("    Bob -->> Alice : Good", content[6])
    assert.are.same("  end", content[7])
  end)
  
  it("formats Gantt chart", function()
     local input = {
         "gantt",
         "title My Project",
         "section Section A",
         "Task 1 : a1, 2014-01-01, 30d",
         "section Section B",
         "Task 2 : 20d"
     }
     
     local buf = vim.api.nvim_create_buf(false, true)
     vim.api.nvim_buf_set_lines(buf, 0, -1, false, input)
     vim.api.nvim_set_current_buf(buf)
     
     require("mermaid.format").format()
     local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
     
     assert.are.same("gantt", content[1])
     assert.are.same("  title My Project", content[2])
     assert.are.same("  section Section A", content[3])
     assert.are.same("  Task 1 : a1, 2014-01-01, 30d", content[4])
     assert.are.same("  section Section B", content[5])
     assert.are.same("  Task 2 : 20d", content[6])
  end)

end)
