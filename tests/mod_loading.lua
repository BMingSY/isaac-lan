local root = arg[1] or "."
local observed, original = {}, {}
local env = setmetatable({}, {
    __index = function(_, key)
        if key ~= "debug" then
            return _G[key]
        end
    end,
})
env._G = env
env.RegisterMod = function(name, version)
    local mod = { Name = name, version = version }
    original.mod = mod
    return mod
end
env.require = function(name)
    if name == "bad" then
        error("original module failure", 0)
    end
    return { name = name }
end
local inspection =
    { getinfo = debug.getinfo, getupvalue = debug.getupvalue, setupvalue = debug.setupvalue }
local observe = assert(loadfile(root .. "/src/bridge/compat/observation.lua", "t", env))()
local mods = observe({
    observeMod = function(mod, source)
        observed.mod, observed.source = mod, source
    end,
    observeRequire = function(source, name, value)
        observed.requireSource, observed.name, observed.value = source, name, value
    end,
}, inspection)
local loaded = assert(
    load("return RegisterMod('solo', 1), require('dependency')", "@mods/solo/main.lua", "t", env)
)
local mod, value = loaded()
assert(mod == original.mod and mods[1] == mod and value == observed.value)
assert(observed.source == "@mods/solo/main.lua" and observed.requireSource == observed.source)
assert(env.debug == nil and observed.name == "dependency", "Sandbox changed or Mod load failed")
local ok, reason = pcall(env.require, "bad")
assert(not ok and reason == "original module failure", "Original require failure changed")
env._IsaacLan = { debug = inspection }
local wrapping = assert(loadfile(root .. "/src/bridge/compat/wrapping.lua", "t", env))()
local captured = { identity = "private upvalue" }
local function closure()
    return captured
end
assert(wrapping.find(closure, function(value)
    return value == captured
end) == captured)
assert(env.debug == nil, "Introspection enabled the game's global debug library")
print("PASS Mod registration, require and private introspection with debug absent")
