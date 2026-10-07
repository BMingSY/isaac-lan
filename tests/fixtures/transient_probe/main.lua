local mod = RegisterMod("LAN transient entity probe fixture", 1)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    -- UI Mods may spawn/remove this machine to test achievement availability.
    -- Only one peer enables this fixture. No gameplay entity survives, so the
    -- host-room scenario must keep matching when the host later meets a boss.
    local entity = Isaac.Spawn(6, 11, 0, Vector.Zero, Vector.Zero, nil)
    entity:Remove()
end)
