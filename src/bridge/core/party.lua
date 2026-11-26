-- The wire format assigns one bit of an unsigned byte to each seat.
local party = { capacity = 8 }
function party.number(text)
    local value = tonumber(text)
    if
        math.type(value) == "integer"
        and tostring(value) == text
        and value >= 1
        and value <= party.capacity
    then
        return value
    end
end
return party
