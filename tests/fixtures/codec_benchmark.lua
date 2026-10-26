local root, iterations = assert(arg[1]), assert(tonumber(arg[2]))
local native = assert(_IsaacLanCodec)
local reference = dofile(root .. "/src/bridge/sync/codec.lua")
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local schema = dofile(root .. "/src/bridge/sync/world_schema.lua")
local layers = dofile(root .. "/src/bridge/sync/layers.lua")(fields)
local workloads = dofile(root .. "/tests/fixtures/codec_workloads.lua")(root)
if arg[3] then
    local file = assert(io.open(arg[3], "rb"))
    local bytes = file:read("*a")
    file:close()
    workloads = {
        {
            name = "recorded",
            value = reference.decode(bytes),
            memo = function()
                return {}
            end,
        },
    }
end
local function transferWorkload(case, peers, splitRooms)
    local source = reference.decode(reference.encode(case.value))
    local view = schema.unpack(source, source[2])
    -- Older synthetic actors omit fields that the production projection splits.
    for _, actor in ipairs(view.actors) do
        local inventory = actor[fields.actor.inventory]
        inventory[fields.inventory.resources] = inventory[fields.inventory.resources] or {}
        inventory[fields.inventory.trinkets] = inventory[fields.inventory.trinkets] or {}
    end
    if not arg[3] then
        local template = reference.encode(view.actors[1])
        for index = 1, peers + 1 do
            local actor = reference.decode(template)
            actor[fields.actor.index], actor[fields.actor.controller] = index - 1, index
            actor[fields.actor.entity][fields.entity.id] = 10000 + index
            view.actors[index] = actor
        end
    end
    view.connected, view.locations = (1 << (peers + 1)) - 1, {}
    for slot = 0, peers do
        view.locations[#view.locations + 1] = { slot, 0, 84 + (splitRooms and slot or 0), 0, 0 }
    end
    local views, expected, size = {}, {}, 0
    for slot = 1, peers do
        local projection = {}
        for name, value in pairs(view) do
            projection[name] = value
        end
        projection.slot = slot
        if splitRooms then
            projection.room = reference.decode(reference.encode(view.room))
        end
        views[slot] = projection
        local realtime, stable = layers.split(projection)
        local dynamic, dependency =
            reference.encode(schema.pack(realtime)), reference.encode(stable)
        expected[slot] = { realtime = dynamic, stable = dependency }
        size = size + #dynamic + #dependency
        local restored = layers.join(
            schema.unpack(reference.decode(dynamic), view.tick),
            reference.decode(dependency)
        )
        assert(reference.encode(schema.pack(restored)) == reference.encode(schema.pack(projection)))
    end
    return {
        bytes = size,
        run = function(encode, verify)
            local memo = { [view.map] = false, [view.locations] = false }
            for slot, projection in ipairs(views) do
                for _, actor in ipairs(projection.actors) do
                    if memo[actor] == nil then
                        memo[actor] = false
                    end
                end
                if memo[projection.room] == nil then
                    memo[projection.room] = false
                end
                local realtime, stable = layers.split(projection, memo)
                local dynamic, dependency =
                    encode(schema.pack(realtime), memo), encode(stable, memo)
                if verify then
                    assert(
                        dynamic == expected[slot].realtime and dependency == expected[slot].stable,
                        "Layered memo changed wire bytes"
                    )
                end
            end
        end,
    }
end
local function measure(fn)
    for _ = 1, 3 do
        fn()
    end
    collectgarbage("collect")
    local samples, sum = {}, 0
    for i = 1, iterations do
        local start = os.clock()
        fn()
        local cost = (os.clock() - start) * 1000
        samples[i], sum = cost, sum + cost
    end
    table.sort(samples)
    return sum / #samples, samples[math.ceil(#samples * 0.95)]
end
for _, case in ipairs(workloads) do
    local bytes = reference.encode(case.value)
    assert(native.state_encode(case.value) == bytes)
    assert(reference.encode(native.state_decode(bytes)) == bytes)
    local transfers = {
        ["transfer-one-peer"] = transferWorkload(case, 1, false),
        ["transfer-three-peers"] = transferWorkload(case, 3, false),
        ["transfer-split-rooms"] = transferWorkload(case, 3, true),
    }
    for _, implementation in ipairs({
        { name = "lua", encode = reference.encode, decode = reference.decode },
        { name = "native", encode = native.state_encode, decode = native.state_decode },
    }) do
        for _, transfer in pairs(transfers) do
            transfer.run(implementation.encode, true)
        end
        for _, operation in ipairs({
            "encode",
            "decode",
            "encode-three-peers",
            "transfer-one-peer",
            "transfer-three-peers",
            "transfer-split-rooms",
        }) do
            local transfer = transfers[operation]
            local mean, p95 = measure(function()
                if transfer then
                    transfer.run(implementation.encode)
                elseif operation == "decode" then
                    implementation.decode(bytes)
                elseif operation == "encode" then
                    implementation.encode(case.value)
                else
                    local memo = case.memo()
                    for _ = 1, 3 do
                        implementation.encode(case.value, memo)
                    end
                end
            end)
            io.write(
                string.format(
                    '{"case":"%s","implementation":"%s","operation":"%s","bytes":%d,"samples":%d,"mean_ms":%.6f,"p95_ms":%.6f}\n',
                    case.name,
                    implementation.name,
                    operation,
                    transfer and transfer.bytes or #bytes,
                    iterations,
                    mean,
                    p95
                )
            )
        end
    end
end
