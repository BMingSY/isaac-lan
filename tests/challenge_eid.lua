local root = assert(arg[1])
local restricted, calls = 0, 0
_IsaacLan = {
    api_info = function()
        return { restrictedBags = restricted }
    end,
}
_IsaacLanModules = {
    ["api/public"] = { api = { RegisterCompatibility = function() end } },
    ["compat/mods/wrapping"] = dofile(root .. "/src/bridge/compat/mods/wrapping.lua"),
}
local definition = dofile(root .. "/src/bridge/compat/mods/eid.lua")
local original = function(_, value)
    calls = calls + 1
    return value
end
local eid = { setPlayer = function() end, handleBagOfCraftingRendering = original }
local handle = {
    IsActive = function()
        return false
    end,
    On = function()
        return function() end
    end,
    Unregister = function() end,
}
local cleanup = definition.install({ mod = eid, addCleanup = function() end }, {
    RegisterMod = function()
        return handle
    end,
})
assert(eid:handleBagOfCraftingRendering("normal") == "normal" and calls == 1)
restricted = 1
assert(eid:handleBagOfCraftingRendering("hidden") == false and calls == 1)
restricted = 0
assert(eid:handleBagOfCraftingRendering("next run") == "next run" and calls == 2)
cleanup()
assert(eid.handleBagOfCraftingRendering == original)
print("PASS scoped EID recipe restriction and cleanup without config/source changes")
