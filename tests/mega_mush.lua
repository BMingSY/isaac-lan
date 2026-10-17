local root = assert(arg[1])
local compat =
    dofile(root .. "/src/bridge/compat/items/mega_mush.lua")({ COLLECTIBLE_MEGA_MUSH = 625 })
local function player()
    local effects = { count = 0, additions = 0, removals = 0 }
    function effects:GetCollectibleEffectNum(id)
        assert(id == 625)
        return self.count
    end
    function effects:AddCollectibleEffect(id, costume, delta)
        assert(id == 625 and costume == true and delta > 0)
        self.count, self.additions = self.count + delta, self.additions + 1
    end
    function effects:RemoveCollectibleEffect(id, delta)
        assert(id == 625 and delta > 0)
        self.count, self.removals = self.count - delta, self.removals + 1
    end
    return {
        GetEffects = function()
            return effects
        end,
    }, effects
end
local holder, effects = player()
local teammate, other = player()
compat.apply(holder, 1)
compat.apply(teammate, 0)
assert(compat.capture(holder) == 1 and other.count == 0, "Giant form crossed player ownership")
for _ = 1, 10 do
    compat.apply(holder, 1)
end
assert(effects.additions == 1, "Repeated snapshots replayed the transformation")
compat.apply(holder, 0)
compat.apply(holder, 0)
assert(effects.count == 0 and effects.removals == 1, "Expiry failed to restore the normal form")
compat.apply(holder, 1)
compat.apply(holder, 2)
compat.apply(holder, 1)
assert(effects.count == 1, "Stacked temporary effects did not reconcile")
for _, bad in ipairs({ -1, 0.5, 65536, math.huge, false }) do
    assert(not pcall(compat.apply, holder, bad), "Invalid effect count accepted")
end
print("PASS giant form ownership, repeated snapshots, expiry and reapplication")
