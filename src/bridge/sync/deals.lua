return function(fields)
    local Deal = fields.deals
    -- One host-owned pair: total deal chance and conditional Angel room chance.
    -- Native queries retain vanilla item, damage, history and room-selection rules.
    return function(native)
        local function validate(value)
            assert(type(value) == "table" and #value == 2, "Invalid shared deal chances")
            local total, angel = value[Deal.total], value[Deal.angel]
            assert(
                type(total) == "number" and total >= 0 and total < math.huge,
                "Invalid total deal chance"
            )
            assert(
                type(angel) == "number" and angel >= 0 and angel <= 1,
                "Invalid conditional Angel room chance"
            )
            return total, angel
        end
        return {
            capture = function()
                local value = { native.deal_chances() }
                validate(value)
                return value
            end,
            apply = function(value)
                local total, angel = validate(value)
                assert(native.deal_chances(total, angel), "Cannot apply shared deal chances")
            end,
            reset = function()
                native.deal_chances_reset()
            end,
        }
    end
end
