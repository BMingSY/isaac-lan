local root = assert(arg[1])
local module = dofile(root .. "/src/bridge/state/forms.lua")
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
end)
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
end)
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
end)
assert(not pcall(broken.resolve, 0, inventory(38)))
print(
    "PASS Tainted Lazarus replacement, Birthright backup listing, idempotence and redirected motion cleanup"
)
