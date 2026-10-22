-- NPC scratch vectors also contain native integer sentinels. Their IEEE
-- representation can be NaN; keep them in a bounded binary field rather than
-- weakening the finite-number checks for positions, velocities and stats.
local pack, unpack = string.pack, string.unpack
local FORMAT = ">ffffff"
local BYTE_COUNT = string.packsize(FORMAT)
local function validTarget(x, y)
    return x == x and y == y and math.abs(x) < math.huge and math.abs(y) < math.huge
end
return {
    capture = function(npc)
        if not npc then
            return false
        end
        local target = npc.TargetPosition
        assert(validTarget(target.X, target.Y), "Invalid NPC target position")
        return pack(FORMAT, npc.V1.X, npc.V1.Y, npc.V2.X, npc.V2.Y, target.X, target.Y)
    end,
    apply = function(npc, bytes)
        assert(type(bytes) == "string" and #bytes == BYTE_COUNT, "Invalid NPC scratch state")
        local x1, y1, x2, y2, targetX, targetY = unpack(FORMAT, bytes)
        assert(validTarget(targetX, targetY), "Invalid NPC target position")
        npc.V1, npc.V2 = Vector(x1, y1), Vector(x2, y2)
        -- Render paths can use this point even when replica AI is suspended.
        npc.TargetPosition = Vector(targetX, targetY)
    end,
}
