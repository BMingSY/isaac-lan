local mod = RegisterMod("Isolated cosmetic wall bug", 1)
local spawned = false
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    spawned = false
end)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not spawned and Game():GetFrameCount() >= 20 then
        spawned = true
        Isaac.Spawn(
            EntityType.ENTITY_EFFECT,
            EffectVariant.WALL_BUG,
            0,
            Vector(120, 100),
            Vector.Zero,
            nil
        )
        Isaac.DebugString("LAN_COSMETIC_WALL_BUG spawned on one renderer")
    end
end)
