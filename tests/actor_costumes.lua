local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local Actor, Entity, Sprite, Slots = fields.actor, fields.entity, fields.sprite, fields.actorSprites
local paths, generation, reads, acquisitions, applications = {}, 0, 0, 0, {}
local ids, names = {}, {}
local function lookup(path)
    if path == "unknown-mod" then
        return -1
    end
    if not ids[path] then
        ids[path] = #names + 1
        names[#names + 1] = path
    end
    return ids[path]
end
local function rebuild(nextPaths)
    paths, generation = nextPaths, generation + 1
end
local head = { head = true }
local player = {
    GetSprite = function()
        return head
    end,
    TryRemoveNullCostume = function(_, id)
        local retained = {}
        for _, path in ipairs(paths) do
            if path ~= names[id] then
                retained[#retained + 1] = path
            end
        end
        rebuild(retained)
    end,
    AddNullCostume = function(_, id)
        local nextPaths = { table.unpack(paths) }
        nextPaths[#nextPaths + 1] = names[id]
        table.sort(nextPaths)
        rebuild(nextPaths)
    end,
}
local native = {
    actor_sprites = function()
        acquisitions = acquisitions + 1
        local result, at = {}, generation
        for i = 1, Slots.firstCostume - 1 + #paths do
            local path = i < Slots.firstCostume and "base" or paths[i - Slots.firstCostume + 1]
            result[i] = {
                index = i,
                generation = at,
                GetFilename = function()
                    assert(at == generation, "Read a Sprite invalidated by costume mutation")
                    reads = reads + 1
                    return path
                end,
            }
        end
        return result
    end,
    actor_pose = function()
        return true
    end,
}
local function apply(sprite, value)
    if not sprite.head then
        assert(sprite.generation == generation, "Applied an invalidated costume Sprite")
    end
    applications[#applications + 1] = { index = sprite.index, value = value }
end
local actors = dofile(root .. "/src/bridge/presentation/actors.lua")(fields)(native, lookup, apply)
local function pose(desired)
    local visuals = {}
    for i = 1, Slots.firstCostume - 1 do
        visuals[i] = { [Sprite.path] = "base" }
    end
    for _, path in ipairs(desired) do
        visuals[#visuals + 1] = { [Sprite.path] = path }
    end
    return {
        [Actor.index] = 0,
        [Actor.pose] = "pose",
        [Actor.visuals] = visuals,
        [Actor.entity] = { [Entity.sprite] = { [Sprite.path] = "head" } },
    }
end
local function assigned()
    local result = {}
    for _, entry in ipairs(applications) do
        if entry.index and entry.index >= Slots.firstCostume then
            result[#result + 1] = entry.index
        end
    end
    return table.concat(result, ",")
end
rebuild({ "red", "blue", "red", "unknown-mod" })
actors.apply(player, pose({ "red", "red", "blue", "unknown-mod", "unknown-mod" }))
assert(assigned() == "11,13,12,14", "Duplicate costumes lost occurrence order")
assert(acquisitions == 1 and reads == #paths)
-- Native callbacks changed the vector; removal and addition invalidate every
-- borrowed Sprite, including retained costumes. Only reacquired views may apply.
rebuild({ "red", "stale" })
applications, acquisitions, reads = {}, 0, 0
actors.apply(player, pose({ "blue", "red", "red" }))
assert(assigned() == "11,12,13" and acquisitions == 2)
-- Reverse-order matching of hundreds of costumes must stay linear in native
-- property reads while still restoring every costume on repeated renders.
local many, reversed = {}, {}
for i = 1, 500 do
    many[i], reversed[501 - i] = "costume-" .. i, "costume-" .. i
end
rebuild(many)
local value = pose(reversed)
for _ = 1, 3 do
    applications, acquisitions, reads = {}, 0, 0
    actors.apply(player, value)
    assert(reads == 500 and acquisitions == 1, "Costume lookup scales quadratically")
    assert(#applications == 1 + Slots.baseCount + 500)
    assert(applications[2 + Slots.baseCount].index == Slots.firstCostume + 499)
end
actors.reset()
print("PASS indexed costume matching, duplicate order, invalidation and repeated render")
