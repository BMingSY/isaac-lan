-- Run with the unchanged Samael Mod in both isolated peers.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, phases = config.host, native.net_phases()
local fields = assert(_IsaacLanModules["sync/fields"])
local Entity, Room = fields.entity, fields.room
local world = assert(_IsaacLanModules["sync/world_schema"])
local npcState = assert(_IsaacLanModules["sync/npc"])
local normal = Isaac.GetPlayerTypeByName("Samael", false)
local tainted = Isaac.GetPlayerTypeByName("Samael", true)
assert(normal > 0 and tainted > 0 and normal ~= tainted, "Samael characters unavailable")
local MAX_VERIFIED_TICK = 1800
if config.modNpcTainted then
    assert(
        SamaelMod and not SamaelMod.ContentManager:CharacterLocked(tainted),
        "Run mod-npcs first to prepare the isolated tainted unlock"
    )
end
local selected = config.modNpcTainted and tainted or normal
local custom = {
    [Isaac.GetEntityTypeByName("Samael Scythe")] = true,
    [Isaac.GetEntityTypeByName("Samael Scythe Blade")] = true,
}
assert(not custom[0], "Samael NPC definitions unavailable")
local frame, gate = _IsaacLanFrame, native.net_gate
local frames, gates, samples = 0, 0, 0
local linked, chosen, finished, requested, departed = false, false, false, false, false
local characterSeen, reentry, restoredFloor = false, false, false
local floorTick, resumedAt, presented
local unlockPrepared = false
local function report(message)
    Isaac.DebugString("LAN_NETWORK MOD_NPCS " .. message)
end
local function owner(slot, callback)
    assert(native.api_with_owner(slot, callback))
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
                        Isaac.GetPlayer(0):SetMinDamageCooldown(10000)
                    end)
                end
            elseif tick == 360 then
                local level = Game():GetLevel()
                local start = level:GetStartingRoomIndex()
                local rooms = level:GetRooms()
                local destination
                for i = 0, rooms.Size - 1 do
                    local room = rooms:Get(i)
                    if
                        room.Data
                        and room.Data.Type == RoomType.ROOM_DEFAULT
                        and room.SafeGridIndex ~= start
                    then
                        destination = room.SafeGridIndex
                        break
                    end
                end
                assert(destination and native.rooms_teleport(1, destination, 0))
            elseif tick == 420 then
                assert(native.rooms_teleport(1, Game():GetLevel():GetStartingRoomIndex(), 0))
                report("room reentry")
            elseif tick == 510 then
                owner(0, function()
                    Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
                end)
            end
        end,
        collect,
        function(bytes, tick, ...)
            local result = restore(bytes, tick, ...)
            if not result or host then
                return result
            end
            local view = world.unpack(_IsaacLanState.decode(bytes), tick)
            local expected = {}
            for _, entity in ipairs(view.room[Room.entities]) do
                if custom[entity[Entity.type]] then
                    expected[entity[Entity.id]] = entity[Entity.npc]
                end
            end
            local count = 0
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                local state = expected[entity:GetData().__isaac_lan_replica]
                if state then
                    local npc =
                        assert(entity:ToNPC(), "Custom NPC restored as another native class")
                    assert(npcState.capture(npc) == state, "Custom NPC state differs from the view")
                    if not presented then
                        assert(native.combat_present(entity:GetSprite()))
                        presented = true
                        report("local hit presentation accepted type=" .. entity.Type)
                    end
                    count = count + 1
                end
            end
            if count >= 2 then
                samples = samples + 1
                characterSeen = true
                reentry = reentry or tick >= 450
                if Game():GetLevel():GetStage() == 2 then
                    floorTick = floorTick or tick
                    restoredFloor = tick - floorTick >= 90
                end
            end
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
    assert(status.phase ~= phases.failed, tostring(status.error))
    assert(
        finished or not status.prepared or status.verified < MAX_VERIFIED_TICK,
        "Mod NPC scenario did not finish; stage=" .. Game():GetLevel():GetStage()
    )
    native.test_gamepad(0)
    if
        not config.modNpcTainted
        and not unlockPrepared
        and status.prepared
        and status.verified >= 10
    then
        -- Prepare the Mod's own unlock in the disposable copy, before the next
        -- session. Locked tainted characters are deliberately sent to Home.
        Isaac.ExecuteCommand("samael unlocktainted")
        assert(not SamaelMod.ContentManager:CharacterLocked(tainted))
        unlockPrepared = true
        report("isolated tainted unlock prepared")
    end
    if status.phase == phases.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", (host and selected or PlayerType.PLAYER_ISAAC) .. ":1")
    end
    if
        host
        and status.phase == phases.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "HGQRLGKP:0:" .. selected .. ":0:0:0")
    end
    if host and status.prepared and status.connected == 1 then
        departed = true
    end
    if status.prepared and native.api_info().ready == 1 and not status.recovering then
        if not host and restoredFloor and gates == 1 and not requested then
            assert(characterSeen and reentry and presented and samples >= 30)
            requested = true
            report("reconnect after custom NPC restore and travel")
            _IsaacLanCommand("reconnect")
        end
        if (host and departed or not host and gates == 2) and status.connected == 3 then
            resumedAt = resumedAt or status.verified
            if status.verified - resumedAt >= 120 and not finished then
                assert(Game():GetLevel():GetStage() == 2)
                finished = true
                report(
                    "PASS "
                        .. (config.modNpcTainted and "tainted" or "normal")
                        .. ", room reentry, floor and reconnect"
                )
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
