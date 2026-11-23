local native = assert(_IsaacLanCodec)
local function coords(count, fn)
    local bytes = { string.pack(">I2", count) }
    for i = 0, count - 1 do
        bytes[#bytes + 1] = string.pack(">ff", fn(i))
    end
    return table.concat(bytes)
end
local header = string.pack(">BffffffI4", 255, 40, 50, 160, 180, 120, 1, 51)
local line = coords(2, function(i)
    return 40 + i * 120, 50 + i * 130
end)
local curve = coords(51, function(i)
    return 40 + i * 2.4, 50 + i * i * 0.052 + (i % 2) * 0.003
end)
local full = header .. line .. curve
local coarse, fine, hostEndX, hostEndY = native.laser_project(full, true)
assert(fine and #coarse < #full / 3)
local expanded, approximate, guestEndX, guestEndY = native.laser_expand(coarse)
assert(
    approximate
        and hostEndX == 160
        and hostEndY == 180
        and guestEndX == hostEndX
        and guestEndY == hostEndY
)
assert(
    #expanded == #full and expanded:sub(1, #header + #line + 2) == full:sub(1, #header + #line + 2)
)
for i = 0, 50 do
    local pos = #header + #line + 3 + i * 8
    local x, y = string.unpack(">ff", full, pos)
    local a, b = string.unpack(">ff", expanded, pos)
    assert((x - a) ^ 2 + (y - b) ^ 2 <= 1 / 32 ^ 2)
    if i == 0 or i == 50 then
        assert(a == x and b == y)
    end
end
local corner = header .. line .. coords(51, function(i)
    return i * 2, (i == 14 and 12 or 0)
end)
local irregular, refine = native.laser_project(corner, true)
assert(not refine and native.laser_expand(irregular) == corner, "An unsampled bend was lost")
for _, data in ipairs({
    full,
    corner,
    header .. line .. coords(0, function() end),
    header .. line .. coords(2048, function(i)
        return i * 0.037, -1 / (i + 1)
    end),
}) do
    local critical, detail = native.laser_project(data, false)
    assert(not detail and native.laser_expand(critical) == data, "Hostile geometry changed")
end
assert(not pcall(native.laser_project, full:sub(1, -2), true))
assert(not pcall(native.laser_expand, coarse .. "!"))
assert(not pcall(native.laser_expand, coarse:sub(1, -2)))
print("PASS exact hostile and irregular paths, bounded smooth interiors, native limits")
