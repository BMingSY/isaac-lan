local root = assert(arg[1])
local enter = dofile(root .. "/src/bridge/compat/bosses/rotgut.lua")
local data, roster = {}, {}
local game = {
    GetLevel = function()
        return {
            GetCurrentRoomDesc = function()
                return { Data = data }
            end,
        }
    end,
    GetNumPlayers = function()
        return #roster
    end,
}
local function actor(animation, active)
    local stops = 0
    return {
        IsExtraAnimationFinished = function()
            return not active
        end,
        GetSprite = function()
            return {
                GetAnimation = function()
                    return animation
                end,
            }
        end,
        AnimatePitfallOut = function()
            animation, active, stops = "FallOut", true, stops + 1
        end,
        stops = function()
            return stops
        end,
    }
end
local function arrival()
    enter(game, function(i)
        return assert(roster[i + 1])
    end, 16)
end
local resident = actor("FallIn", true)
for _, variant in ipairs({ 1010, 1020 }) do
    data = { Type = 16, Variant = variant }
    local head, twin = actor("FallIn", true), actor("FallIn", true)
    local idle, teleport = actor("WalkDown", false), actor("TeleportUp", true)
    roster = { head, twin, idle, teleport }
    arrival()
    assert(not head:IsExtraAnimationFinished() and not twin:IsExtraAnimationFinished())
    assert(
        head:GetSprite():GetAnimation() == "FallOut"
            and twin:GetSprite():GetAnimation() == "FallOut"
    )
    assert(head.stops() == 1 and twin.stops() == 1)
    assert(idle.stops() == 0 and teleport.stops() == 0 and resident.stops() == 0)
    arrival()
    assert(
        head.stops() == 1 and twin.stops() == 1,
        "Repeated entry restarted native pitfall recovery"
    )
end
for _, room in ipairs({ { Type = 1, Variant = 1010 }, { Type = 16, Variant = 1 }, {} }) do
    data, roster = room, { actor("FallIn", true) }
    arrival()
    assert(roster[1].stops() == 0, "Unrelated room lost its native animation")
end
data = nil
arrival()
assert(roster[1].stops() == 0)
print("PASS Rotgut arriving bodies, occupied stomach, repeat and unrelated room boundaries")
