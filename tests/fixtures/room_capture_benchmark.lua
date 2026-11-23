-- Run against tagged or working copies of room.lua with the same Lua interpreter.
local root, module = assert(arg[1]), assert(arg[2])
local ticks = tonumber(arg[3]) or 2000
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local codec = dofile(root .. "/src/bridge/sync/codec.lua")
local location, current = { dimension = 0, index = 84 }, { X = 0, Y = 0 }
local function zero()
    return 0
end
local function empty()
    return ""
end
local function identity(value)
    return value
end
local door = {
    Slot = 1,
    TargetRoomIndex = 85,
    CurrentRoomType = 1,
    TargetRoomType = 1,
    Direction = 2,
    Busted = false,
    ExtraVisible = true,
    IsLocked = function()
        return false
    end,
    GetSprite = empty,
}
local grid = {
    State = 0,
    CollisionClass = 1,
    VarData = 0,
    GetType = zero,
    GetVariant = zero,
    GetSprite = empty,
    GetSaveState = function(self)
        return self
    end,
    ToDoor = function(self)
        return self.door
    end,
}
local occupied = {}
for index = 0, 447, 3 do
    occupied[index] = setmetatable(
        { SpawnSeed = index + 1, door = index % 33 == 0 and door },
        { __index = grid }
    )
end
local room = {
    GetGridSize = function()
        return 448
    end,
    GetGridEntity = function(_, i)
        return occupied[i]
    end,
    GetBackdropType = zero,
    GetWaterCurrent = function()
        return current
    end,
    IsClear = zero,
    GetFrameCount = zero,
}
local game = {
    GetRoom = function()
        return room
    end,
}
local entities = {}
Game = function()
    return game
end
Isaac = {
    GetRoomEntities = function()
        return entities
    end,
}
local native = {
    rooms_with_player = function(_, f)
        f()
        return true
    end,
    door_sprite = identity,
    music_state = empty,
    room_layout = empty,
    room_rails = empty,
}
local newCapture = dofile(module)(fields)
for _, changing in ipairs({ false, true }) do
    local capture = newCapture(
        native,
        identity,
        identity,
        { capture = empty },
        { ENTITY_PLAYER = 1 },
        nil,
        {
            capture = function()
                return false
            end,
        }
    )
    for tick = -100, 0 do
        capture(1, tick, 0, location)
    end
    collectgarbage("collect")
    local start = os.clock()
    local view
    for tick = 1, ticks do
        if changing then
            occupied[(tick % 150) * 3].State = tick
        end
        view = capture(1, tick, 0, location)
    end
    local elapsed = os.clock() - start
    local hash = 2166136261
    local packed = codec.encode(view)
    for i = 1, #packed do
        hash = ((hash ~ packed:byte(i)) * 16777619) & 0xffffffff
    end
    print(
        ("%s %d %.3f %08x"):format(
            changing and "changing" or "stable",
            ticks,
            elapsed * 1000000 / ticks,
            hash
        )
    )
end
