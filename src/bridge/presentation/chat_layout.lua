local layout = { lineHeight = 11, bubbleLines = 3, recentLines = 3, expandedLines = 6 }
function layout.wrap(text, width, measure)
    local lines, line = {}, ""
    for _, code in utf8.codes(text) do
        local character = utf8.char(code)
        if code == 10 then
            lines[#lines + 1], line = line, ""
        elseif line ~= "" and measure(line .. character) > width then
            lines[#lines + 1], line = line, character
        else
            line = line .. character
        end
    end
    lines[#lines + 1] = line
    return lines
end
function layout.fit(text, width, measure)
    if measure(text) <= width then
        return text
    end
    local result = ""
    for _, code in utf8.codes(text) do
        local nextText = result .. utf8.char(code)
        if measure(nextText .. "…") > width then
            break
        end
        result = nextText
    end
    return result .. "…"
end
function layout.bubble(text, width, measure)
    local lines = layout.wrap(text, width, measure)
    if #lines > layout.bubbleLines then
        lines[layout.bubbleLines] = layout.fit(lines[layout.bubbleLines] .. "…", width, measure)
        while #lines > layout.bubbleLines do
            table.remove(lines)
        end
    end
    return lines
end
function layout.duration(text)
    return math.min(8000, 4000 + (utf8.len(text) or 0) * 65)
end
function layout.anchor(x, y, width, height, screenWidth, screenHeight)
    return math.max(4, math.min(screenWidth - width - 4, x - width / 2)),
        math.max(4, math.min(screenHeight - height - 4, y - height - 28))
end
function layout.avoidOverlap(x, y, width, height, screenWidth, screenHeight, occupied)
    local gap = 5
    local candidates = { { x, y } }
    for _, other in ipairs(occupied) do
        candidates[#candidates + 1] = { x, other.y - height - gap }
        candidates[#candidates + 1] = { other.x - width - gap, y }
        candidates[#candidates + 1] = { other.x + other.width + gap, y }
    end
    local bestX, bestY, bestScore = x, y, math.huge
    for _, candidate in ipairs(candidates) do
        local cx = math.max(4, math.min(screenWidth - width - 4, candidate[1]))
        local cy = math.max(4, math.min(screenHeight - height - 4, candidate[2]))
        local overlap = 0
        for _, other in ipairs(occupied) do
            local dx =
                math.max(0, math.min(cx + width, other.x + other.width) - math.max(cx, other.x))
            local dy =
                math.max(0, math.min(cy + height, other.y + other.height) - math.max(cy, other.y))
            overlap = overlap + dx * dy
        end
        -- Prefer nearby empty space; retain a bounded result in a crowded corner.
        local score = overlap * screenWidth * screenHeight + math.abs(cx - x) + math.abs(cy - y)
        if score < bestScore then
            bestX, bestY, bestScore = cx, cy, score
        end
    end
    occupied[#occupied + 1] = { x = bestX, y = bestY, width = width, height = height }
    return bestX, bestY
end
return layout
