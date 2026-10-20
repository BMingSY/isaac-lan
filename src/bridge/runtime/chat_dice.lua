-- Chat expressions use an injected random source and never touch gameplay RNG.
local dice = {}
local maxCount, maxTerms, maxConstant, maxExtra = 20, 20, 9999, 2
local percentileSides, digitSides = 100, 10
local modifierNames = { b = "奖励", p = "惩罚" }

function dice.help(maxSides)
    return {
        "/MdN：全队掷骰，M 默认 1；每次最多 "
            .. maxCount
            .. " 颗，N 为 1～"
            .. maxSides,
        "骰子可加减组合，例如 /d6+2d3+1",
        "/d100b /d100p：奖励／惩罚骰；后接 1～" .. maxExtra .. " 指定数量",
    }
end

function dice.parse(text, maxSides)
    local terms, labels, count = {}, {}, 0
    local rest, sign = text:lower(), 1
    while true do
        local token, ending = rest:match("^%s*([^%s+%-]+)()")
        if not token then
            return nil, "用法：/MdN，例如 /2d6 或 /d6+2d3"
        end
        local amount, sides, modifier, extra = token:match("^(%d*)d(%d+)([bp]?)(%d*)$")
        local term = { sign = sign }
        local label
        if amount then
            amount = amount == "" and 1 or tonumber(amount)
            sides = tonumber(sides)
            if not amount or amount < 1 or amount > maxCount then
                return nil, "骰子数量 M 为 1～" .. maxCount .. " 的整数"
            end
            if not sides or sides < 1 or sides > maxSides then
                return nil, "骰子面数 N 为 1～" .. maxSides .. " 的整数"
            end
            count = count + amount
            if count > maxCount then
                return nil, "每次最多投掷 " .. maxCount .. " 颗骰子"
            end
            term.count, term.sides = amount, sides
            label = (amount == 1 and "" or tostring(amount)) .. "D" .. sides
            if modifier ~= "" then
                extra = extra == "" and 1 or tonumber(extra)
                if sides ~= percentileSides or not extra or extra < 1 or extra > maxExtra then
                    return nil, "奖惩骰仅用于 D100，b／p 后的数量为 1～" .. maxExtra
                end
                term.modifier, term.extra = modifier, extra
                label = label .. modifier .. (extra == 1 and "" or tostring(extra))
            end
        elseif #terms > 0 and token:match("^%d+$") then
            term.constant = tonumber(token)
            if not term.constant or term.constant > maxConstant then
                return nil, "加减常数为 0～" .. maxConstant .. " 的整数"
            end
            label = tostring(term.constant)
        else
            return nil, "用法：/MdN，例如 /2d6 或 /d6+2d3"
        end
        if #terms >= maxTerms then
            return nil, "掷骰表达式最多 " .. maxTerms .. " 项"
        end
        terms[#terms + 1] = term
        labels[#labels + 1] = (#labels == 0 and "" or (sign == 1 and " + " or " - ")) .. label
        rest = rest:sub(ending):gsub("^%s+", "")
        if rest == "" then
            break
        end
        local operator = rest:sub(1, 1)
        if operator ~= "+" and operator ~= "-" then
            return nil, "用法：/MdN，例如 /2d6 或 /d6+2d3"
        end
        sign, rest = operator == "+" and 1 or -1, rest:sub(2)
    end
    return { terms = terms, expression = table.concat(labels) }
end

function dice.roll(parsed, random)
    local function draw(sides)
        local ok, value = pcall(random, sides)
        if ok and type(value) == "number" and value >= 1 and value <= sides and value % 1 == 0 then
            return value
        end
    end
    local function single(term)
        if not term.modifier then
            local value = draw(term.sides)
            return value, value and tostring(value)
        end
        local units = draw(digitSides)
        if not units then
            return
        end
        units = units % digitSides
        local candidates, chosen = {}, nil
        for _ = 1, term.extra + 1 do
            local tens = draw(digitSides)
            if not tens then
                return
            end
            local value = (tens % digitSides) * digitSides + units
            -- 00 is 100, including when comparing bonus/penalty candidates.
            if value == 0 then
                value = percentileSides
            end
            candidates[#candidates + 1] = tostring(value)
            if
                not chosen
                or (term.modifier == "b" and value < chosen)
                or (term.modifier == "p" and value > chosen)
            then
                chosen = value
            end
        end
        return chosen,
            modifierNames[term.modifier]
                .. "["
                .. table.concat(candidates, ", ")
                .. "] → "
                .. chosen
    end
    local total, details = 0, {}
    for index, term in ipairs(parsed.terms) do
        local value, detail = term.constant, term.constant and tostring(term.constant)
        if not term.constant then
            local values = {}
            value = 0
            for _ = 1, term.count do
                local result, text = single(term)
                if not result then
                    return nil
                end
                value = value + result
                values[#values + 1] = text
            end
            detail = table.concat(values, " + ")
            if term.count > 1 then
                detail = "[" .. detail .. "]"
            elseif term.modifier and #parsed.terms > 1 then
                detail = "(" .. detail .. ")"
            end
        end
        total = total + term.sign * value
        details[index] = (index == 1 and "" or (term.sign == 1 and " + " or " - ")) .. detail
    end
    local result = parsed.expression .. " = " .. table.concat(details)
    if #parsed.terms > 1 or parsed.terms[1].count > 1 then
        result = result .. " = " .. total
    end
    return result, total
end

return dice
