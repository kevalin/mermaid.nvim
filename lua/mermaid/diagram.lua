local M = {}

--- Extract mermaid diagram content from fenced code blocks.
--- Returns only the diagram content (excluding fence markers).
--- If no fences found, returns original content (for pure mermaid files).
function M.extract(content)
    local fence = content:find('```')
    if not fence then
        return content
    end
    fence = fence + 3
    local ch = content:sub(fence, fence):match('^([%l])')
    if not ch then
        return content
    end
    local fence_type_end = content:find('\n', fence)
    if not fence_type_end then
        return content
    end
    local content_start = fence_type_end + 1
    local content_end = #content
    local search_from = content_start
    while true do
        local next_newline = content:find('\n', search_from)
        if not next_newline then
            break
        end
        local line = content:sub(search_from, next_newline - 1)
        if line:match('^```%s*$') then
            content_end = next_newline - 1
            break
        end
        search_from = next_newline + 1
    end
    while content_end >= content_start and content:sub(content_end, content_end):match('[%s\n\r]') do
        content_end = content_end - 1
    end
    if content_end < content_start then
        return ''
    end
    return content:sub(content_start, content_end)
end

return M
