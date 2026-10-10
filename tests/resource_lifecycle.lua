local root = assert(arg[1])
local reconcile = dofile(root .. "/src/bridge/sync/entities.lua")
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local refs, live = {}, {}
local observed = setmetatable({}, { __mode = "v" })
local spawned, removed = 0, 0
local env = {
    ref = function(id)
        return refs[id]
    end,
    spawn = function(v)
        local e = { Type = v[2], Variant = v[3], SubType = v[4], data = {}, alive = true }
        function e:Exists()
            return self.alive
        end
        function e:GetData()
            return self.data
        end
        refs[v[1]], live[e] = e, true
        spawned = spawned + 1
        observed[spawned] = e
        return e
    end,
    apply = function() end,
    entities = function()
        local all = {}
        for e in pairs(live) do
            all[#all + 1] = e
        end
        return all
    end,
    discard = function(e)
        live[e], refs[e.data.__isaac_lan_replica] = nil, nil
        e.alive = false
        removed = removed + 1
    end,
}
local function cycle()
    local values = {}
    for id = 1, 32 do
        local v = { id, 10, 0, 0 }
        v[11], v[12], v[13], v[14] = id % 32 + 1, 0, 0, 0
        values[#values + 1] = v
    end
    reconcile(values, env)
    local before = spawned
    reconcile(values, env)
    assert(spawned == before, "Repeated snapshot allocated new identities")
    reconcile({}, env)
    assert(next(refs) == nil and next(live) == nil, "Removed identities remain retained")
    local bytes = codec.encode(values)
    assert(#codec.decode(bytes) == 32)
end
for _ = 1, 10 do
    cycle()
end
collectgarbage("collect")
local baseline = collectgarbage("count")
for _ = 1, 1000 do
    cycle()
end
collectgarbage("collect")
assert(spawned == removed, "Entity destruction does not balance creation")
assert(next(observed) == nil, "Parent cycles kept removed entities reachable")
assert(collectgarbage("count") - baseline < 64, "Warm lifecycle retained more than 64 KiB")
print("PASS repeated reconciliation, cyclic entity cleanup and post-GC retained memory")
local samples = {}
local active = false
local profile = dofile(root .. "/src/bridge/diagnostics/performance.lua")({
    diagnostics_enabled = function()
        return active
    end,
    diagnostics_sample = function(name, value)
        samples[#samples + 1] = { name, value }
    end,
}, function()
    return 1
end)
local function returns(...)
    return ...
end
assert(profile.wrap("disabled", returns) == returns, "Disabled profiling wraps normal calls")
active = true
profile = dofile(root .. "/src/bridge/diagnostics/performance.lua")({
    diagnostics_enabled = function()
        return true
    end,
    diagnostics_sample = function(name, value)
        samples[#samples + 1] = { name, value }
    end,
}, function()
    return 1
end)
local packed = table.pack(profile.wrap("values", returns)(1, nil, 3, nil))
assert(packed.n == 4 and packed[3] == 3 and #samples == 1)
local ok, message = pcall(profile.wrap("error", function()
    error("original failure")
end))
assert(not ok and message:find("original failure", 1, true))
print("PASS instrumentation preserves values and original failures")
