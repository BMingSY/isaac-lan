local root = assert(arg[1])
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local module = dofile(root .. "/src/bridge/compat/characters/lazarus.lua")(
    dofile(root .. "/src/bridge/sync/fields.lua")
)
local function body(kind, controller)
    return {
        ControllerIndex = controller or 2,
        GetPlayerType = function()
            return kind
        end,
        ChangePlayerType = function()
            error("Flip must not reinitialize a Tainted Lazarus body")
        end,
    }
end
local alive, dead, other = body(29), body(38), body(0, 1)
local roster, replacements = { other, alive }, 0
local forms = module({
    actor_form = function(index, desired)
        assert(index == 1)
        replacements = replacements + 1
        roster[2] = desired == 38 and dead or alive
        return true
    end,
}, function(index)
    return roster[index + 1]
end, enums.PlayerType)
local function inventory(kind, ghost)
    return { kind, {}, {}, {}, {}, {}, {}, {}, ghost or false }
end
assert(forms.resolve(1, inventory(38)) == dead and replacements == 1)
assert(forms.resolve(1, inventory(38)) == dead and replacements == 1)
assert(forms.resolve(1, inventory(29)) == alive and replacements == 2)
assert(forms.resolve(0, inventory(0)) == other and replacements == 2)
assert(forms.resolve(1, inventory(38, true)) == alive and replacements == 2)
local listed = 0
local birthright = module({
    actor_form = function(index, desired, controller)
        assert(index == 2 and desired == 38 and controller == 2)
        assert(roster[1] == other and roster[2] == alive and not roster[3])
        roster[3] = dead
        listed = listed + 1
        return true
    end,
}, function(index)
    -- Native Isaac.GetPlayer returns player zero for an absent index.
    return roster[index + 1] or roster[1]
end, enums.PlayerType)
assert(birthright.resolve(2, inventory(38), 2) == dead and listed == 1)
assert(birthright.resolve(2, inventory(38), 2) == dead and listed == 1)
assert(birthright.resolve(0, inventory(0), 1) == other and listed == 1)
assert(not pcall(birthright.resolve, 3, inventory(0), 2))
assert(roster[1] == other and roster[2] == alive and roster[3] == dead)
local redirected = { Ref = dead }
local replicas = { [10] = redirected, [11] = redirected, [12] = { Ref = other } }
local motion = { [10] = { actor = true }, [11] = { actor = true }, [12] = { actor = false } }
local inventories = { [10] = "old", [11] = "new" }
forms.prune(replicas, motion, inventories, { { 1, 2, { 11 } } })
assert(not replicas[10] and not motion[10] and not inventories[10])
assert(replicas[11] == redirected and motion[11] and inventories[11] == "new")
assert(replicas[12] and motion[12], "Room entities must retain their own reconciliation")
forms.prune(replicas, motion, inventories, { { 1, 2, { 11 } } })
assert(replicas[11] == redirected)
local broken = module({
    actor_form = function()
        return false
    end,
}, function()
    return alive
end, enums.PlayerType)
assert(not pcall(broken.resolve, 0, inventory(38)))
print(
    "PASS Tainted Lazarus replacement, Birthright backup listing, idempotence and redirected motion cleanup"
)
local wire = dofile(root .. "/src/bridge/sync/fields.lua")
local restore = dofile(root .. "/src/bridge/sync/actor_roster.lua")(wire)
local packets = {}
local sync = restore({
    actor_companions = function(bytes)
        packets[#packets + 1] = bytes
        return true
    end,
})
local function actor(index, controller, identifier, parent, kind, variant)
    return {
        index,
        controller,
        { [1] = identifier, [3] = variant or 0, [11] = parent or 0 },
        { kind or 0 },
    }
end
local host, guest = actor(0, 1, 100), actor(1, 2, 200)
local soul = actor(2, 2, 300, 200, 16)
sync({ host, guest, soul })
local count, identifier, index, parent, controller, kind, variant, nextByte =
    string.unpack(">I1I4I1I1I1I2I2", packets[#packets])
assert(count == 1 and identifier == 300 and index == 2 and parent == 1)
assert(controller == 2 and kind == 16 and variant == 0 and nextByte == #packets[#packets] + 1)
sync({ host, guest, soul })
assert(packets[1] == packets[2], "Repeated companion snapshots changed identity")
sync({ host, guest })
assert(packets[3] == string.pack(">I1", 0), "Missing companions must reach native cleanup")
assert(not pcall(sync, { host, guest, actor(2, 1, 300, 200, 20) }))
assert(not pcall(sync, { host, actor(1, 1, 200, 300), actor(2, 1, 300) }))
print("PASS parented actor identities, owner validation, repeated state and cleanup request")
