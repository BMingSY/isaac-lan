-- Native introspection works without changing the game's sandbox globals.
return function(registry, inspection)
    local registeredMods = {}
    local registerMod, originalRequire = RegisterMod, require
    function RegisterMod(name, version)
        local mod = registerMod(name, version)
        registeredMods[#registeredMods + 1] = mod
        local caller = inspection.getinfo(2, "S")
        registry.observeMod(mod, caller and caller.source or "")
        return mod
    end
    function require(name)
        local caller = inspection.getinfo(2, "S")
        local value = originalRequire(name)
        registry.observeRequire(caller and caller.source or "", name, value)
        return value
    end
    return registeredMods
end
