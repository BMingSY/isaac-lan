-- Swept bounds only discard impossible contacts. Exact contact and the first
-- impact remain the caller's decision; large sweeps use a bounded fallback.
local CELL_SIZE, MAX_CELLS = 64, 64
local DIRECT_PAIRS = 64
local function bounds(x, y, oldX, oldY, radius)
    return math.floor((math.min(x, oldX) - radius) / CELL_SIZE),
        math.floor((math.min(y, oldY) - radius) / CELL_SIZE),
        math.floor((math.max(x, oldX) + radius) / CELL_SIZE),
        math.floor((math.max(y, oldY) + radius) / CELL_SIZE)
end
return function(targets, queries)
    if #targets * queries <= DIRECT_PAIRS then
        return function(_, _, _, _, _, visit)
            for _, target in ipairs(targets) do
                visit(target)
            end
        end
    end
    local buckets, wide, seen, serial = {}, {}, {}, 0
    for _, target in ipairs(targets) do
        local left, top, right, bottom =
            bounds(target.x, target.y, target.oldX, target.oldY, target.radius)
        if (right - left + 1) * (bottom - top + 1) > MAX_CELLS then
            wide[#wide + 1] = target
        else
            for x = left, right do
                local column = buckets[x] or {}
                buckets[x] = column
                for y = top, bottom do
                    local cell = column[y] or {}
                    column[y] = cell
                    cell[#cell + 1] = target
                end
            end
        end
    end
    return function(x, y, oldX, oldY, radius, visit)
        local left, top, right, bottom = bounds(x, y, oldX, oldY, radius)
        if (right - left + 1) * (bottom - top + 1) > MAX_CELLS then
            for _, target in ipairs(targets) do
                visit(target)
            end
            return
        end
        serial = serial + 1
        for columnIndex = left, right do
            local column = buckets[columnIndex]
            if column then
                for rowIndex = top, bottom do
                    local cell = column[rowIndex]
                    if cell then
                        for _, target in ipairs(cell) do
                            if seen[target] ~= serial then
                                seen[target] = serial
                                visit(target)
                            end
                        end
                    end
                end
            end
        end
        for _, target in ipairs(wide) do
            visit(target)
        end
    end
end
