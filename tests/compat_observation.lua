local root = assert(arg[1])
local observed = {}
local env = setmetatable({
    RegisterMod = function(name)
        return { Name = name }
    end,
}, { __index = _G })
local module = assert(
    load(
        "return { PlayerService = { prototype = { getPlayers = function() end } } }",
        "@mods/stats-plus/services/PlayerService.lua",
        "t",
        env
    )
)()
env.require = function(name)
    if name == "missing" then
        error("missing module sentinel")
    end
    return module
end
local registry = {
    observeMod = function(mod, source)
        observed.mod, observed.registration = mod, source
    end,
    observeRequire = function(source, name, value)
        observed.source, observed.name, observed.value = source, name, value
    end,
}
assert(loadfile(root .. "/src/bridge/compat/mods/observation.lua", "t", env))()(registry, debug)
-- MCM's compatibility loader calls the previously installed require via pcall.
-- Its immediate caller is C, not the Mod importing the returned service.
assert(load(
    [[
        local original = require
        require = function(name)
            local ok, result = pcall(original, name)
            if not ok then error(result, 2) end
            return result
        end
    ]],
    "@mods/mcm/scripts/compatibility.lua",
    "t",
    env
))()
local service = assert(load(
    [[
        local service = require("services.PlayerService")
        RegisterMod("stats-plus", 1)
        return service
    ]],
    "@mods/stats-plus/main.lua",
    "t",
    env
))()
assert(service == module and observed.value == module, "Observation replaced module exports")
assert(observed.name == "services.PlayerService")
assert(observed.registration == "@mods/stats-plus/main.lua")
assert(
    observed.source:match("^@mods/stats%-plus/"),
    "Wrapped require attributed Stats+ exports to " .. observed.source
)
-- Container instances expose their owning methods through a prototype, and
-- may contain cycles or protected metatables. Observation must neither loop
-- nor invoke their user-defined traversal/index methods.
local method = module.PlayerService.prototype.getPlayers
module = setmetatable({}, {
    __index = { method = method },
    __pairs = function()
        error("Observation invoked exported behavior")
    end,
})
module.self = module
assert(env.require("app.APPLICATION_CONTAINER") == module)
assert(observed.source == "@mods/stats-plus/services/PlayerService.lua")
module = setmetatable({ value = 42 }, { __metatable = "private" })
assert(env.require("constants") == module)
module = false
assert(env.require("optional") == false)
local ok, message = pcall(env.require, "missing")
assert(not ok and message:find("missing module sentinel", 1, true))
print("PASS wrapped require preserves module identity and source ownership")
