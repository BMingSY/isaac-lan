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
        for field = fields.inventory.cards, fields.inventory.smeltedTrinkets do
            actor[fields.actor.inventory][field] = false
        end
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
    actor[fields.actor.inventory][fields.inventory.items] = schema.unpack(
        codec.decode(complete),
        42
    ).actors[1][fields.actor.inventory][fields.inventory.items]
    actor[fields.actor.inventory][fields.inventory.smeltedTrinkets] =
        string.pack(">I2I2I2I2", 1, 39, 2, 1)
    local _, swallowed = layers.split(view)
    assert(
        codec.encode(swallowed) ~= stableBytes,
        "Swallowed effects lost their dependency revision"
    )
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

-- Every peer gets one complete combat tick regardless of its optional byte budget.
local Entity, Room, Actor = fields.entity, fields.room, fields.actor
local projectCalls = 0
local function project(raw, player)
    projectCalls = projectCalls + 1
    return (player and "smooth" or "exact:") .. raw, player, -0.0, 42.5
end
local function expand(wire)
    if wire:sub(1, 6) == "smooth" then
        return "draw:" .. wire:sub(7), true, -0.0, 42.5
    end
    return wire:sub(7), false, -0.0, 42.5
end
local combat = dofile(root .. "/src/bridge/sync/layers.lua")(fields, project, expand)
local view = schema.unpack(codec.decode(codec.encode(workloads[1].value)), 42)
for _, actor in ipairs(view.actors) do
    local inventory = actor[Actor.inventory]
    for _, field in ipairs({
        fields.inventory.items,
        fields.inventory.trinkets,
        fields.inventory.smeltedTrinkets,
    }) do
        inventory[field] = inventory[field] or {}
    end
end
local source = view.actors[1][Actor.entity][Entity.id]
local function row(id, x, parent, spawner, path)
    return {
        [Entity.id] = id,
        [Entity.position] = { x, 10 },
        [Entity.parent] = parent,
        [Entity.spawner] = spawner,
        [Entity.laserPath] = path,
        [Entity.typed] = { 6 },
    }
end
local enemyId, shotId, laserId = 501, 502, 503
local rows = {
    row(enemyId, 21, 0, 0),
    row(shotId, 23, 0, enemyId),
    row(laserId, 24, 0, source, "one"),
    row(504, 25, source, enemyId, "enemy"),
    row(505, 26, 0, 0, "unknown"),
    row(506, 27, source, 0, "two"),
}
rows[3][Entity.laserEndPoint] = { -0.0, 42.5 }
rows[4][Entity.laserEndPoint] = { 11, 42.5 }
rows[5][Entity.laserEndPoint] = { 0.0, 42.5 }
view.room[Room.entities] = rows
local projections = {}
local core, stable, none = combat.split(view, nil, projections, 0)
assert(not none and projectCalls == 4 and rows[3][Entity.laserPath] == "one")
local budget = #string.pack(">i8s2", laserId, "one")
local _, _, detail = combat.split(view, nil, projections, budget)
local _, _, all = combat.split(view, nil, projections, 2 * budget)
local _, _, small = combat.split(view, nil, projections, budget - 1)
assert(not small and #detail == budget and #all == 2 * budget and projectCalls == 4)
local id, raw = string.unpack(">i8s2", detail)
assert((id == laserId and raw == "one") or (id == 506 and raw == "two"))
assert(core.room[Room.entities][3][Entity.laserEndPoint] == true)
assert(core.room[Room.entities][4][Entity.laserEndPoint][1] == 11)
assert(1 / core.room[Room.entities][5][Entity.laserEndPoint][1] == math.huge)
local accepted = combat.join(core, stable)
assert(
    1 / accepted.room[Room.entities][3][Entity.laserEndPoint][1] == -math.huge
        and accepted.room[Room.entities][3][Entity.laserEndPoint][2] == 42.5
)
local entities = accepted.room[Room.entities]
assert(
    accepted.tick == 42
        and entities[1][Entity.position][1] == 21
        and entities[1][Entity.typed][1] == 6
)
assert(
    entities[2][Entity.spawner] == entities[1][Entity.id] and entities[2][Entity.position][1] == 23
)
assert(
    entities[3][Entity.laserPath] == "draw:one"
        and entities[4][Entity.laserPath] == "enemy"
        and entities[5][Entity.laserPath] == "unknown"
)
assert(
    accepted.laserRefinements[laserId]
        and accepted.laserRefinements[506]
        and not accepted.laserRefinements[504]
        and not accepted.laserRefinements[505]
)
print(
    "Combat core preserves shooter and hazards, player-only refinement and per-peer budgets passed"
)
