-- Optional --mod Allstars exercises a live revive machine whose XML is absent.
-- Keep the same peers through a floor, room changes and checkpoint reconnect.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host = config.host
local Phase = native.net_phases()
local fields = assert(_IsaacLanModules["sync/fields"])
local world = assert(_IsaacLanModules["sync/world_schema"])
local Entity, Room = fields.entity, fields.room
local schema = _IsaacLanModules["sync/entity_schema"](EntityType)
local REVIVE_MACHINE, FIRST_RADIUS, SECOND_RADIUS = 19, 7.25, 4.5
local TARGET_STAGE, HOST_CONNECTED, BOTH_CONNECTED = 2, 1, 3
local sizeField
for index, name in ipairs(schema.common) do
    if name == "Size" then
        sizeField = index
    end
end
assert(sizeField)
local frame, gate = _IsaacLanFrame, native.net_gate
local frames, gates, samples = 0, 0, 0
local linked, chosen, finished = false, false, false
local firstSize, secondSize, reentry, rejected = false, false, false, false
local requested, departed, resumedAt, floorTick, start, other
local multiplier
local function report(message)
    Isaac.DebugString("LAN_NETWORK ENTITY_SIZE " .. message)
end
local function owner(slot, callback)
    assert(native.api_with_owner(slot, callback))
end
local function machine()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_SLOT and entity.Variant == REVIVE_MACHINE then
            return entity
        end
    end
end
local function resize(radius)
    owner(0, function()
        local entity = assert(machine(), "Missing authoritative revive machine")
        -- Explicit public arguments do not request XML defaults. This exercises
        -- actual size changes as well as repeated identical snapshots.
        entity:SetSize(radius, entity.SizeMulti, 0)
        assert(entity.Size == radius)
        report("authority radius=" .. radius)
    end)
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    gates = gates + 1
    return gate(
        capture,
        function(tick, ...)
            before(tick, ...)
            if not host then
                return
            end
            if tick == 30 then
                for slot = 0, 1 do
                    owner(slot, function()
                        local player = Isaac.GetPlayer(0)
                        player:ChangePlayerType(
                            slot == 0 and PlayerType.PLAYER_EDEN_B or PlayerType.PLAYER_JUDAS
                        )
                        player:SetMinDamageCooldown(10000)
                    end)
                end
            elseif tick == 120 then
                owner(0, function()
                    Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
                end)
            end
            if
                Game():GetLevel():GetStage() ~= TARGET_STAGE
                or not native.rooms_ready()
                or native.api_info().ready ~= 1
            then
                return
            end
            if not floorTick then
                floorTick = tick
                local level = Game():GetLevel()
                start = level:GetStartingRoomIndex()
                local rooms = level:GetRooms()
                for index = 0, rooms.Size - 1 do
                    local room = rooms:Get(index)
                    if
                        room.Data
                        and room.Data.Type == RoomType.ROOM_DEFAULT
                        and room.SafeGridIndex ~= start
                    then
                        other = room.SafeGridIndex
                        break
                    end
                end
                assert(other)
                owner(0, function()
                    local entity = assert(machine(), "Second floor did not create a revive machine")
                    local original = entity.Size
                    assert(not pcall(native.entity_size, entity:GetSprite(), FIRST_RADIUS))
                    assert(entity.Size == original, "Authority accepted a replica-only write")
                    report("second floor radius=" .. original)
                end)
            end
            local age = tick - floorTick
            if age == 30 then
                resize(FIRST_RADIUS)
            elseif age == 90 then
                resize(SECOND_RADIUS)
            elseif age == 150 then
                assert(native.rooms_teleport(1, other, 0))
            elseif age == 210 then
                assert(native.rooms_teleport(1, start, 0))
            end
        end,
        collect,
        function(bytes, tick, ...)
            local result = restore(bytes, tick, ...)
            if not result or host or Game():GetLevel():GetStage() ~= TARGET_STAGE then
                return result
            end
            local view = world.unpack(_IsaacLanState.decode(bytes), tick)
            local expected = {}
            for _, entity in ipairs(view.room[Room.entities]) do
                if
                    entity[Entity.type] == EntityType.ENTITY_SLOT
                    and entity[Entity.variant] == REVIVE_MACHINE
                then
                    expected[entity[Entity.id]] = entity[Entity.common][sizeField]
                end
            end
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                local radius = expected[entity:GetData().__isaac_lan_replica]
                if radius then
                    assert(entity.Size == radius, "Replica size differs from the committed view")
                    local shape = entity.SizeMulti
                    multiplier = multiplier or { shape.X, shape.Y }
                    assert(
                        shape.X == multiplier[1] and shape.Y == multiplier[2],
                        "Size restore changed the collision shape"
                    )
                    firstSize = firstSize or radius == FIRST_RADIUS
                    secondSize = secondSize or radius == SECOND_RADIUS
                    if not rejected then
                        assert(not pcall(native.entity_size, Sprite(), radius))
                        assert(not pcall(native.entity_size, entity:GetSprite(), math.huge))
                        assert(entity.Size == radius)
                        rejected = true
                    end
                    samples = samples + 1
                    if floorTick and tick - floorTick >= 240 then
                        reentry = true
                    end
                end
            end
            floorTick = floorTick or tick
            return result
        end,
        present,
        beginFloor
    )
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= Phase.failed, tostring(status.error))
    native.test_gamepad(0)
    if status.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == Phase.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "HGQRLGKP:0:0:0:0:0")
    end
    if host and status.prepared and status.connected == HOST_CONNECTED then
        departed = true
    end
    if status.prepared and native.api_info().ready == 1 and not status.recovering then
        if not host and reentry and gates == 1 and not requested then
            assert(firstSize and secondSize and rejected and samples >= 20)
            requested = true
            report("reconnect after repeated sizes and room reentry")
            _IsaacLanCommand("reconnect")
        end
        if
            (host and departed or not host and gates == 2)
            and status.connected == BOTH_CONNECTED
        then
            resumedAt = resumedAt or status.verified
            if status.verified - resumedAt >= 120 and not finished then
                assert(Game():GetLevel():GetStage() == TARGET_STAGE)
                if not host then
                    assert(machine() and machine().Size == SECOND_RADIUS)
                end
                finished = true
                report("PASS floor, changing sizes, reentry and checkpoint reconnect")
            end
        end
    end
    return status
end
return {
    done = function()
        return finished
    end,
}
