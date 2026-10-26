local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local schema = dofile(root .. "/src/bridge/sync/world_schema.lua")
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local layers = dofile(root .. "/src/bridge/sync/layers.lua")(fields)
local workloads = dofile(root .. "/tests/fixtures/codec_workloads.lua")(root)
for _, workload in ipairs(workloads) do
    local view = schema.unpack(codec.decode(codec.encode(workload.value)), 42)
    -- Workload actors predate the specialized state fields.
    for _, actor in ipairs(view.actors) do
        actor[fields.actor.inventory][fields.inventory.resources] = { 0, 0, 0, 0, 0, 0, 0 }
        actor[fields.actor.inventory][fields.inventory.trinkets] = {}
        actor[fields.actor.poop] = false
        actor[fields.actor.craftingBag] = { "bag", false }
        actor[fields.actor.temporaryEffects] = { 0, 1, 2 }
    end
    local complete = codec.encode(schema.pack(view))
    local fast, stable = layers.split(view)
    local dynamicBytes, stableBytes = codec.encode(schema.pack(fast)), codec.encode(stable)
    assert(codec.encode(schema.pack(view)) == complete, "Projection mutated the shared capture")
    local restored =
        layers.join(schema.unpack(codec.decode(dynamicBytes), 42), codec.decode(stableBytes))
    assert(codec.encode(schema.pack(restored)) == complete, "Split changed authoritative fields")
    view.tick, view.frame = 43, 86
    view.actors[1][fields.actor.entity][fields.entity.position] = { 100, 200 }
    local actor = view.actors[1]
    actor[fields.actor.inventory][fields.inventory.active] = { { 33, 6 } }
    actor[fields.actor.inventory][fields.inventory.resources] = { 99, 10, 1, 0, 0, 0, 0 }
    actor[fields.actor.inventory][fields.inventory.hearts] = { 0, 6, 0, 6, 0, 0, 0, 8, 0 }
    actor[fields.actor.temporaryEffects] = { 1, 2, 3 }
    actor[fields.actor.poop] = { 1, 2 }
    actor[fields.actor.craftingBag] = { "changed", false }
    local _, same = layers.split(view)
    assert(
        codec.encode(same) == stableBytes,
        "Dynamic player state changed the reliable dependency"
    )
    view.actors[1][fields.actor.inventory][fields.inventory.items] = { { 25, 2 } }
    local _, changed = layers.split(view)
    assert(codec.encode(changed) ~= stableBytes, "Inventory change lost its revision")
    local invalid = schema.unpack(codec.decode(dynamicBytes), 42)
    invalid.actors[1][fields.actor.entity][fields.entity.id] = -100
    assert(not pcall(layers.join, invalid, codec.decode(stableBytes)))

    for _, layout in ipairs({ "single", "same", "split", "dimension", "disconnected" }) do
        local source = schema.unpack(codec.decode(complete), 42)
        source.connected = (layout == "single" or layout == "disconnected") and 3 or 15
        source.locations = {
            { 0, 0, 84, 0, 0 },
            { 1, 0, 84, 0, 0 },
            { 2, layout == "dimension" and 1 or 0, layout == "split" and 85 or 84, 0, 0 },
            { 3, 0, 86, 0, 0 },
        }
        local memo = {}
        local peers = source.connected == 3 and 1 or 3
        for slot = 1, peers do
            source.slot = slot
            local dynamic, dependency = layers.split(source, memo)
            assert(codec.encode(dynamic.room) == codec.encode(layers.split(source).room))
            local dynamicBytes = codec.encode(schema.pack(dynamic), memo)
            local dependencyBytes = codec.encode(dependency, memo)
            local joined = layers.join(
                schema.unpack(codec.decode(dynamicBytes), 42),
                codec.decode(dependencyBytes)
            )
            assert(codec.encode(schema.pack(joined)) == codec.encode(schema.pack(source)))
            if slot == 1 then
                local cached = memo[source.room[fields.room.entities]]
                if layout == "same" then
                    assert(
                        cached and cached.bytes == codec.encode(source.room[fields.room.entities])
                    )
                else
                    assert(cached == nil, "Room fragments cached without another viewer")
                end
            end
        end
        if peers == 1 then
            assert(next(memo) == nil, "Single recipient acquired extra encoding fragments")
        end
    end
end
print("state layers round trips, dependency identity and connected same-room fragment reuse passed")
