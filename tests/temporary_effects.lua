local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local sync = dofile(root .. "/src/bridge/sync/temporary_effects.lua")(fields)
local kinds = { "Collectible", "Trinket", "Null" }
local function player()
    local effects = { counts = { {}, {}, {} }, additions = 0, removals = 0 }
    for kind, name in ipairs(kinds) do
        effects["Get" .. name .. "EffectNum"] = function(self, id)
            return self.counts[kind][id] or 0
        end
        effects["Add" .. name .. "Effect"] = function(self, id, costume, delta)
            assert(costume and delta > 0)
            self.counts[kind][id] = (self.counts[kind][id] or 0) + delta
            self.additions = self.additions + 1
        end
        effects["Remove" .. name .. "Effect"] = function(self, id, delta)
            assert(delta > 0)
            self.counts[kind][id] = self.counts[kind][id] - delta
            self.removals = self.removals + 1
        end
    end
    function effects:GetEffectsList()
        local values = {}
        for kind, counts in ipairs(self.counts) do
            for id, count in pairs(counts) do
                local item = { ID = id }
                for i, name in ipairs(kinds) do
                    item["Is" .. name] = function()
                        return i == kind
                    end
                end
                values[#values + 1] = { Item = item, Count = count }
            end
        end
        return {
            Size = #values,
            Get = function(_, index)
                return values[index + 1]
            end,
        }
    end
    return {
        GetEffects = function()
            return effects
        end,
    }, effects
end
local function snapshot(p)
    local rows = {}
    for _, value in ipairs(sync.capture(p)) do
        rows[#rows + 1] = table.concat(value, ":")
    end
    return table.concat(rows, ",")
end
local authority, original = player()
local guest, effects = player()
local teammate, other = player()
-- Real inventory alone is insufficient: Scissors and Decap Attack put native
-- IsHeadless state in TemporaryEffects. Null effects use a distinct ID space.
original.counts =
    { { [325] = 1, [729] = 1, [625] = 1, [58] = 2, [313] = 1 }, { [55] = 2 }, { [55] = 1 } }
sync.apply(guest, sync.capture(authority))
sync.apply(teammate, {})
assert(snapshot(guest) == snapshot(authority) and other.additions == 0, "Effects crossed owners")
local additions = effects.additions
for _ = 1, 10 do
    sync.apply(guest, sync.capture(authority))
end
assert(effects.additions == additions, "Repeated snapshots replayed item effects")
-- Room changes, shield consumption and expiring head separation remove absent
-- effects, including provisional effects created by local inventory setters.
original.counts = { { [625] = 1, [58] = 1 }, {}, {} }
effects.counts[1][999] = 3
sync.apply(guest, sync.capture(authority))
assert(snapshot(guest) == snapshot(authority), "Expired or stale effect survived")
sync.apply(guest, {})
local removals = effects.removals
sync.apply(guest, {})
assert(snapshot(guest) == "" and effects.removals == removals, "Cleanup was not idempotent")
-- A newly introduced item is data, not another per-item synchronization patch.
original.counts = { { [12345] = 4 }, {}, {} }
sync.apply(guest, sync.capture(authority))
assert(snapshot(guest) == "1:12345:4", "Effect set depends on a fixed item whitelist")
sync.apply(guest, { { 1.0, 12345.0, 4.0 } })
assert(effects.additions == additions + 1, "Integral Lua numbers caused effect replay")
for _, bad in ipairs({
    { { 1, 325, -1 } },
    { { 1, 325, 0 } },
    { { 1, 325, 0.5 } },
    { { 1, 325, 65536 } },
    { { 1, 325, math.huge } },
    { { 4, 325, 1 } },
    { { 1, false, 1 } },
    { { 1, 325, 1 }, { 1, 325, 2 } },
    { { 1, 325, 1 }, { 3, 55, false } },
    { { 1, 325 } },
}) do
    local before, a, r = snapshot(guest), effects.additions, effects.removals
    assert(not pcall(sync.apply, guest, bad), "Invalid effect set accepted")
    assert(
        snapshot(guest) == before and effects.additions == a and effects.removals == r,
        "Partial effect set applied"
    )
end
print(
    "PASS temporary effects: split models, kinds, ownership, duplicate snapshots, expiry and validation"
)
