-- Native introspection works without changing the game's sandbox globals.
return function(registry, inspection)
    local maxExportNodes, maxExportDepth = 64, 4
    local registeredMods = {}
    local registerMod, originalRequire = RegisterMod, require
    local function exportSource(value)
        local seen, remaining = {}, maxExportNodes
        local function visit(candidate, depth)
            if remaining == 0 or depth > maxExportDepth or seen[candidate] then
                return
            end
            remaining = remaining - 1
            if type(candidate) == "function" then
                local info = inspection.getinfo(candidate, "S")
                return info and info.source:sub(1, 1) == "@" and info.source or nil
            end
            if type(candidate) ~= "table" then
                return
            end
            seen[candidate] = true
            for _, child in next, candidate do
                local source = visit(child, depth + 1)
                if source then
                    return source
                end
            end
            local meta = getmetatable(candidate)
            return type(meta) == "table" and visit(rawget(meta, "__index"), depth + 1) or nil
        end
        return visit(value, 0)
    end
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
        -- Another Mod can relay require through pcall. In that case the caller
        -- belongs to C/the relay, while exported service methods still identify
        -- their owning Mod. Registry fingerprint checks remain authoritative.
        registry.observeRequire(
            exportSource(value) or (caller and caller.source or ""),
            name,
            value
        )
        return value
    end
    return registeredMods
end
