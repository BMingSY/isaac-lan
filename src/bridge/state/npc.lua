-- NPC scratch vectors also contain native integer sentinels. Their IEEE
-- representation can be NaN; keep them in a bounded binary field rather than
-- weakening the finite-number checks for positions, velocities and stats.
local pack, unpack = string.pack, string.unpack
return {
    capture = function(npc)
        if not npc then
            return false
        end
        return pack(">ffff", npc.V1.X, npc.V1.Y, npc.V2.X, npc.V2.Y)
    end,
    apply = function(npc, bytes)
        assert(type(bytes) == "string" and #bytes == 16, "Invalid NPC scratch state")
        local x1, y1, x2, y2 = unpack(">ffff", bytes)
        npc.V1, npc.V2 = Vector(x1, y1), Vector(x2, y2)
    end,
}
