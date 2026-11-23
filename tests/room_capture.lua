-- Exercise shared room capture with separate rooms, dimensions and floor reuse.
local root = assert(arg[1])
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local active, calls = 0, 0
local current = { X = 0, Y = 1 }
local entity = {
    Type = 10,
    Exists = function()
        return true
    end,
}
local backdrop = 17
local roomType = enums.RoomType.ROOM_DEFAULT
local room = {
    GetType = function()
        return roomType
    end,
    GetBackdropType = function()
        return backdrop
    end,
    GetWaterCurrent = function()
        return current
    end,
    GetGridSize = function()
        return 0
    end,
    IsClear = function()
        return false
    end,
    GetFrameCount = function()
        return calls
    end,
}
Game = function()
    return {
        GetRoom = function()
            return room
        end,
    }
end
Isaac = {
    GetRoomEntities = function()
        return { entity }
    end,
}
local native = {
    rooms_with_player = function(slot, fn)
        active = slot
        calls = calls + 1
        fn()
        return true
    end,
    music_state = function()
        return "music"
    end,
    room_layout = function()
        return "layout"
    end,
    room_rails = function()
        return string.rep(string.char(active), 448)
    end,
}
local bossRush =
    dofile(root .. "/src/bridge/compat/routes/boss_rush.lua")(native, enums.RoomType.ROOM_BOSSRUSH)
local capture = assert(loadfile(root .. "/src/bridge/sync/room.lua"))()(
    dofile(root .. "/src/bridge/sync/fields.lua")
)(native, function()
    return { active }
end, function()
    error("No grids")
end, {
    capture = function()
        return "return"
    end,
}, enums.EntityType, nil, bossRush)
local one = capture(1, 10, 0, { dimension = 0, index = 84 })
assert(one == capture(2, 10, 0, { dimension = 0, index = 84 }) and calls == 1)
assert(one[3][1][1] == 1)
assert(one[8][1] == 0 and one[8][2] == 1)
assert(one[9] == string.rep("\1", 448))
assert(#one == 11 and one[10] == 17 and one[11] == false)
backdrop = 18
assert(capture(2, 10, 0, { dimension = 0, index = 85 }) ~= one and calls == 2)
assert(capture(3, 10, 0, { dimension = 1, index = 84 }) ~= one and calls == 3)
current.Y = 0
local nextTick = capture(1, 11, 0, { dimension = 0, index = 84 })
assert(nextTick[8][2] == 0 and one[8][2] == 1, "Room current view is mutable/stale")
assert(nextTick ~= one and calls == 4 and nextTick[10] == 18 and one[10] == 17)
assert(capture(2, 11, 0, { dimension = 0, index = 84 }) == nextTick and calls == 4)
assert(capture(1, 11, 1, { dimension = 0, index = 84 }) ~= nextTick and calls == 5)
local fresh = assert(loadfile(root .. "/src/bridge/sync/room.lua"))()(
    dofile(root .. "/src/bridge/sync/fields.lua")
)(native, function()
    return { active }
end, function()
    error("No grids")
end, {
    capture = function()
        return "return"
    end,
}, enums.EntityType, nil, bossRush)
assert(fresh(1, 11, 1, { dimension = 0, index = 84 }) ~= nextTick and calls == 6)

-- Native room ambience survives both reconciliation passes and never enters
-- the snapshot. A real projectile still uses normal authority ownership.
local spray = { Type = 1000, Exists = entity.Exists }
local objects, captures, reclaimed = { spray, entity }, 0, 0
local function localEffect(e)
    return e == spray
end
Isaac.GetRoomEntities = function()
    return objects
end
local filtered = dofile(root .. "/src/bridge/sync/room.lua")(
    dofile(root .. "/src/bridge/sync/fields.lua")
)(native, function(e)
    assert(e == entity, "Local ambience was serialized")
    captures = captures + 1
    return { 1, e.Type, 0, 0 }
end, function()
    error("No grids")
end, {
    capture = function()
        return "return"
    end,
}, enums.EntityType, localEffect, bossRush)
entity.Variant, entity.SubType = 0, 0
function entity:GetData()
    return {}
end
for tick = 1, 3 do
    local value = filtered(1, tick, tick == 3 and 1 or 0, { dimension = 0, index = tick })
    assert(#value[3] == 1 and value[3][1][2] == 10)
    dofile(root .. "/src/bridge/sync/entities.lua")(dofile(root .. "/src/bridge/sync/fields.lua"))(
        enums.EntityType,
        enums.PickupVariant
    )(value[3], {
        ref = function(id)
            return id == 1 and entity or nil
        end,
        key = function(e)
            return e
        end,
        entities = function()
            return objects
        end,
        localEffect = localEffect,
        discard = function()
            error("Retained ambience/authority entity was discarded")
        end,
        reclaim = function()
            reclaimed = reclaimed + 1
        end,
        spawn = function()
            error("Existing authority entity was respawned")
        end,
        apply = function() end,
    })
end
assert(captures == 3 and reclaimed == 0, "Ambient particles forced native room cleanup")

-- Grid reads remain live, including external changes and replacements. Only
-- equal immutable records are retained across consecutive capture generations.
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local Room, Grid, Door = fields.room, fields.grid, fields.door
local pose = { "idle", 0 }
local door = {
    Slot = 0,
    TargetRoomIndex = 85,
    CurrentRoomType = 1,
    TargetRoomType = 1,
    Direction = 0,
    Busted = false,
    ExtraVisible = false,
    locked = true,
    IsLocked = function(self)
        return self.locked
    end,
    GetSprite = function()
        return pose
    end,
}
local grid = {
    State = 0,
    CollisionClass = 1,
    VarData = 0,
    variant = 1,
    seed = 9,
    GetType = function()
        return 16
    end,
    GetVariant = function(self)
        return self.variant
    end,
    GetSprite = function()
        return pose
    end,
    GetSaveState = function(self)
        return { SpawnSeed = self.seed }
    end,
    ToDoor = function()
        return door
    end,
}
local grids = { [0] = grid }
room.GetGridSize = function()
    return 2
end
room.GetGridEntity = function(_, index)
    return grids[index]
end
native.door_sprite = function(value)
    return value
end
local previousSprite
local cached = dofile(root .. "/src/bridge/sync/room.lua")(fields)(native, function()
    return { 1, 10, 0, 0 }
end, function(value, previous)
    previousSprite = previous
    return value
end, {
    capture = function()
        return "return"
    end,
}, enums.EntityType, localEffect, bossRush)
local location = { dimension = 0, index = 84 }
local first = cached(1, 20, 2, location)
local firstBytes = codec.encode(first)
local same = cached(1, 21, 2, location)
assert(same[Room.grids] == first[Room.grids] and same[Room.entities] ~= first[Room.entities])
assert(previousSprite == pose, "Previous grid sprite was not supplied")
door.locked = false
local unlocked = cached(1, 22, 2, location)
assert(unlocked[Room.grids] ~= first[Room.grids])
assert(not unlocked[Room.grids][1][Grid.door][Door.locked])
assert(codec.encode(first) == firstBytes, "Grid reuse mutated a prior view")
pose = { "open", 1 }
local animated = cached(1, 23, 2, location)
assert(animated[Room.grids][1][Grid.sprite] == pose)
grid.variant, grid.seed, grid.State, grid.CollisionClass, grid.VarData = 2, 10, 3, 0, 8
local changed = cached(1, 24, 2, location)[Room.grids][1]
assert(changed[Grid.variant] == 2 and changed[Grid.seed] == 10 and changed[Grid.state] == 3)
assert(changed[Grid.collision] == 0 and changed[Grid.data] == 8)
grids[0] = nil
assert(#cached(1, 25, 2, location)[Room.grids] == 0)
grids[1] = grid
local replaced = cached(1, 26, 2, location)
assert(replaced[Room.grids][1][Grid.index] == 1)
cached(1, 27, 2, { dimension = 1, index = 84 })
assert(previousSprite == nil, "Another dimension reused prior captures")
cached(1, 28, 2, location)
assert(previousSprite == nil, "An unobserved room retained capture history")
cached(1, 28, 3, location)
assert(previousSprite == nil, "New floor reused a prior capture")
cached(1, 27, 3, location)
assert(previousSprite == nil, "A regressed tick retained future captures")
-- Inserting or removing a lower occupied index shifts the later tuple's position.
local tail = cached(1, 29, 3, location)[Room.grids][1]
grids[0] = grid
local inserted = cached(1, 30, 3, location)[Room.grids]
assert(#inserted == 2 and inserted[1][Grid.index] == 0 and inserted[2] == tail)
grids[0] = nil
local removed = cached(1, 31, 3, location)[Room.grids]
assert(#removed == 1 and removed[1] == tail and #inserted == 2)
print("PASS live grid reuse, door animation, replacement and room/floor invalidation")
print("PASS room views capture once per room/tick and clear on tick/floor changes")

local rushType = enums.RoomType.ROOM_BOSSRUSH
roomType = rushType
local running, done, wave, total = false, false, 0, 15
room.IsAmbushActive = function()
    return running
end
room.IsAmbushDone = function()
    return done
end
native.room_ambush_wave = function()
    return wave, total
end
local guest = { active = false, done = false }
local restore = dofile(root .. "/src/bridge/compat/routes/boss_rush.lua")({
    room_ambush_wave = function(activeFlag, currentWave, totalWaves)
        guest.active, guest.wave, guest.total = activeFlag == 1, currentWave, totalWaves
        return true
    end,
}, rushType)
guest.GetType = function()
    return roomType
end
guest.IsAmbushDone = function()
    return guest.done
end
guest.SetAmbushDone = function(_, value)
    guest.done = value
end
for t, state in ipairs({
    { false, false, 0 },
    { true, false, 0 },
    { true, false, 1 },
    { true, false, 1 },
    { true, false, 2 },
    { false, true, 15 },
}) do
    running, done, wave = table.unpack(state)
    local snapshot = cached(1, t, 4, { dimension = 0, index = -5 })
    restore.apply(guest, snapshot[Room.bossRush])
    assert(
        guest.active == running
            and guest.done == done
            and guest.wave == wave
            and guest.total == total
    )
end
roomType = enums.RoomType.ROOM_DEFAULT
local outside = cached(2, 6, 4, { dimension = 0, index = 84 })[Room.bossRush]
assert(outside == false)
restore.apply(guest, outside)
assert(not pcall(restore.apply, guest, { true, false, 2, 15 }))
roomType = rushType
assert(not pcall(restore.apply, guest, outside))
print("PASS Boss Rush entry, gaps, final clear and separate room views")
