local root = assert(arg[1])
local compat = dofile(root .. "/src/bridge/compat/items/temporary_effects.lua")({
    COLLECTIBLE_MEGA_MUSH = 625,
    COLLECTIBLE_BOOK_OF_SHADOWS = 58,
    COLLECTIBLE_HOLY_MANTLE = 313,
})
local function player()
    local effects = { counts = {}, additions = 0, removals = 0 }
    function effects:GetCollectibleEffectNum(id)
        return self.counts[id] or 0
    end
    function effects:AddCollectibleEffect(id, costume, delta)
        assert(costume == true and delta > 0)
        self.counts[id], self.additions =
            self:GetCollectibleEffectNum(id) + delta, self.additions + 1
    end
    function effects:RemoveCollectibleEffect(id, delta)
        assert(delta > 0)
        self.counts[id], self.removals = self:GetCollectibleEffectNum(id) - delta, self.removals + 1
    end
    return {
        GetEffects = function()
            return effects
        end,
    }, effects
end
local holder, effects = player()
local teammate, other = player()
local function captured(p)
    return table.concat(compat.capture(p), ",")
end
compat.apply(holder, { 1, 1, 2 })
compat.apply(teammate, { 0, 0, 0 })
assert(captured(holder) == "1,1,2" and other.additions == 0, "Effects crossed player ownership")
for _ = 1, 10 do
    compat.apply(holder, { 1, 1, 2 })
end
assert(effects.additions == 3, "Repeated snapshots replayed the temporary effects")
-- A consumed shield and an expired timed shield clear independently of the
-- giant form. Unrelated temporary effects stay owned by their native sources.
effects.counts[999] = 3
compat.apply(holder, { 1, 0, 1 })
assert(captured(holder) == "1,0,1" and effects.counts[999] == 3)
compat.apply(holder, { 0, 0, 0 })
local removals = effects.removals
compat.apply(holder, { 0, 0, 0 })
assert(captured(holder) == "0,0,0" and effects.removals == removals, "Expiry was not idempotent")
compat.apply(holder, { 1, 1, 1 })
compat.apply(holder, { 2, 1, 0 })
compat.apply(holder, { 1, 0, 1 })
assert(captured(holder) == "1,0,1", "Room entry/reapplication did not reconcile the new state")
for _, bad in ipairs({ -1, 0.5, 65536, math.huge, false }) do
    local before, additions = captured(holder), effects.additions
    assert(not pcall(compat.apply, holder, { 2, 1, bad }), "Invalid effect count accepted")
    assert(
        captured(holder) == before and effects.additions == additions,
        "Partial tuple was applied"
    )
end
for _, bad in ipairs({ false, 1, {}, { 1, 1 }, { 1, 1, 1, 1 } }) do
    assert(not pcall(compat.apply, holder, bad), "Invalid effect tuple accepted")
end
print("PASS temporary effect ownership, repeated snapshots, consumption, expiry and reapplication")
