local root = assert(arg[1])
local dice = dofile(root .. "/src/bridge/runtime/chat_dice.lua")
local maxSides = 999
local function roll(expression, values, expected)
    local parsed = assert(dice.parse(expression, maxSides))
    local calls = 0
    local result = dice.roll(parsed, function(sides)
        calls = calls + 1
        local value = assert(values[calls], "Unexpected extra random draw")
        assert(value >= 1 and value <= sides, "Wrong random die requested")
        return value
    end)
    assert(result == expected, expression .. ": " .. tostring(result))
    assert(calls == #values, "A die was skipped")
end
roll("d1", { 1 }, "D1 = 1")
roll("1D999", { 999 }, "D999 = 999")
roll("2d6", { 3, 5 }, "2D6 = [3 + 5] = 8")
roll("1d6+2d3", { 4, 1, 3 }, "D6 + 2D3 = 4 + [1 + 3] = 8")
roll(" 1D6 + 2d3 - 1 ", { 4, 1, 3 }, "D6 + 2D3 - 1 = 4 + [1 + 3] - 1 = 7")
roll("d1-2d6-3", { 1, 6, 6 }, "D1 - 2D6 - 3 = 1 - [6 + 6] - 3 = -14")
roll("d6+0", { 3 }, "D6 + 0 = 3 + 0 = 3")
roll("d6+9999", { 3 }, "D6 + 9999 = 3 + 9999 = 10002")
roll("d100b", { 4, 7, 2 }, "D100b = 奖励[74, 24] → 24")
roll("1D100P1", { 4, 7, 2 }, "D100p = 惩罚[74, 24] → 74")
roll("d100b2", { 4, 7, 2, 1 }, "D100b2 = 奖励[74, 24, 14] → 14")
roll("d100p2", { 4, 7, 2, 1 }, "D100p2 = 惩罚[74, 24, 14] → 74")
roll("d100b", { 10, 10, 1 }, "D100b = 奖励[100, 10] → 10")
roll("d100p", { 10, 10, 1 }, "D100p = 惩罚[100, 10] → 100")
roll("d100b", { 1, 10, 10 }, "D100b = 奖励[1, 1] → 1")
roll("d100p", { 10, 10, 10 }, "D100p = 惩罚[100, 100] → 100")
roll(
    "2d100b+d6",
    { 4, 7, 2, 1, 10, 9, 5 },
    "2D100b + D6 = [奖励[74, 24] → 24 + 奖励[1, 91] → 1] + 5 = 30"
)
roll("d6-d100p", { 6, 10, 10, 1 }, "D6 - D100p = 6 - (惩罚[100, 10] → 100) = -94")
-- Every possible pair of percentile candidates with a shared units die,
-- including 100 and both candidate orders, must choose its numeric min/max.
for left = 1, 100 do
    for right = 1, 100 do
        if left % 10 == right % 10 then
            local units = left % 10
            local leftTens, rightTens = math.floor(left / 10) % 10, math.floor(right / 10) % 10
            local values = {
                units == 0 and 10 or units,
                leftTens == 0 and 10 or leftTens,
                rightTens == 0 and 10 or rightTens,
            }
            roll(
                "d100b",
                values,
                "D100b = 奖励[" .. left .. ", " .. right .. "] → " .. math.min(left, right)
            )
            roll(
                "d100p",
                values,
                "D100p = 惩罚[" .. left .. ", " .. right .. "] → " .. math.max(left, right)
            )
        end
    end
end
for _, expression in ipairs({
    "",
    "d",
    "6",
    "2+d6",
    "0d6",
    "21d6",
    "d0",
    "d1000",
    "19d6+2d3",
    "d6+",
    "d6-",
    "-d6",
    "+d6",
    "d6++d6",
    "d6--d6",
    "d6+-1",
    "1 d6",
    "d 6",
    "d6 d6",
    "2d6 extra",
    "d6*2",
    "(d6)",
    "d6/2",
    "0x2d6",
    "1.5d6",
    "d6.5",
    "d6+1.5",
    "d6+10000",
    "d6b",
    "d20p",
    "d100b0",
    "d100b3",
    "d100p0",
    "d100p3",
    "d100bp",
    "d100b2p1",
    "d100 b",
    "d6" .. string.rep("+0", 20),
    string.rep("9", 309) .. "d6",
    "d" .. string.rep("9", 309),
    "d100b" .. string.rep("9", 309),
    "d6+" .. string.rep("9", 309),
}) do
    local parsed, reason = dice.parse(expression, maxSides)
    assert(not parsed and type(reason) == "string", "Accepted invalid expression " .. expression)
end
assert(dice.parse("20d999", maxSides))
assert(dice.parse("d6" .. string.rep("+0", 19), maxSides))
-- A failure after an earlier successful roll must discard the whole result.
local parsed = assert(dice.parse("2d6", maxSides))
for _, invalid in ipairs({ false, 0, 7, 1.5, "3", math.huge, 0 / 0 }) do
    local calls = 0
    assert(not dice.roll(parsed, function()
        calls = calls + 1
        return calls == 1 and 3 or invalid
    end))
    assert(calls == 2)
end
assert(not dice.roll(parsed, function() end))
assert(not dice.roll(parsed, function()
    error("random source failed")
end))
for failureAt = 1, 4 do
    local calls = 0
    assert(not dice.roll(assert(dice.parse("d100b2", maxSides)), function()
        calls = calls + 1
        if calls ~= failureAt then
            return 1
        end
    end))
    assert(calls == failureAt)
end
-- Even the largest supported result fits the unchanged chat packet budget.
local longest = assert(dice.roll(assert(dice.parse("20d100p2", maxSides)), function(n)
    return n
end))
assert(#("【房间】4P 掷骰：" .. longest) <= 2048)
print("PASS mixed dice, bonuses, penalties, all percentile pairs, bounds and random failures")
