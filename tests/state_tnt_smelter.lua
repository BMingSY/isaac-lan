-- Render-time TNT authority and persistent swallowed trinkets, using one pair.
local native, config, input = _IsaacLan, _IsaacLanTest, _IsaacLanTestInput
local fields = _IsaacLanModules["sync/fields"]
local schema = _IsaacLanModules["sync/world_schema"]
local Phase, frame, gate = native.net_phases(), _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local origin, other, expectedTnt, observedTick
local renderSamples, reentrySamples, inventorySamples = 0, 0, 0
local floorSeed, postFloorSamples = nil, 0
local trinket = TrinketType.TRINKET_CANCER
local held = TrinketType.TRINKET_CURVED_HORN
local function report(text)
    Isaac.DebugString("LAN_NETWORK TNT_SMELTER " .. text)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])), Game():GetRoom())
    end))
end
local function clear(room)
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsActiveEnemy(false) then
            entity:Remove()
        end
    end
    room:SetClear(true)
end
local function counts(normal, golden)
    return string.pack(">I2I2I2I2", 1, trinket, normal, golden)
end
local function checkInventory(t)
    if t < 60 or not native.rooms_ready() then
        return
    end
    actor(1, function(p)
        local expected = t < 100 and counts(1, 0) or t < 140 and counts(2, 0) or counts(2, 1)
        assert(
            native.actor_smelted_trinkets(p:GetSprite()) == expected,
            "Swallowed normal/golden counters differ at tick " .. t
        )
        assert(
            p:HasTrinket(trinket) and p:GetTrinketMultiplier(trinket) > 0,
            "Swallowed trinket has no native effect"
        )
        assert(p:GetTrinket(0) == (t < 180 and 0 or held), "Held trinket changed")
        inventorySamples = inventorySamples + 1
        if t >= 650 then
            postFloorSamples = postFloorSamples + 1
        end
    end)
    actor(0, function(p)
        assert(
            native.actor_smelted_trinkets(p:GetSprite()) == string.pack(">I2", 0),
            "Swallowed trinkets leaked to another player"
        )
    end)
end
local observer = RegisterMod("TNT render regression", 1)
observer:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if config.host or finished or not expectedTnt then
        return
    end
    local grid = assert(Game():GetRoom():GetGridEntity(expectedTnt[fields.grid.index]))
    local expected = expectedTnt[fields.grid.sprite][fields.sprite.animation]
    assert(
        grid:GetSprite():GetAnimation() == expected,
        "Native replica update replaced authoritative TNT animation at tick " .. observedTick
    )
    renderSamples = renderSamples + 1
    if observedTick >= 300 then
        reentrySamples = reentrySamples + 1
    end
end)
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (config.host and 60 or 120) then
        linked = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= Phase.failed, status.error)
    if status.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        config.host
        and status.phase == Phase.lobby
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    native.test_gamepad(0)
    return status
end
local function advance(t)
    if t == 20 then
        origin = Game():GetLevel():GetStartingRoomIndex()
        local rooms = Game():GetLevel():GetRooms()
        for i = 0, rooms.Size - 1 do
            local d = rooms:Get(i)
            if d.Data and d.Data.Type == RoomType.ROOM_DEFAULT and d.SafeGridIndex ~= origin then
                other = d.SafeGridIndex
                break
            end
        end
        assert(other)
        actor(1, function(p, room)
            clear(room)
            p:ChangePlayerType(PlayerType.PLAYER_KEEPER)
            p:AddTrinket(trinket, false)
            p:AddCollectible(CollectibleType.COLLECTIBLE_SMELTER, 6, false)
            local index = room:GetGridIndex(Vector(240, 280))
            room:RemoveGridEntity(index, 0, false)
            room:Update()
            assert(room:SpawnGridEntity(index, GridEntityType.GRID_TNT, 0, 123, 0))
        end)
    elseif t == 40 or t == 100 or t == 140 then
        actor(1, function(p, room)
            if t ~= 40 then
                p:AddTrinket(trinket + (t == 140 and TrinketType.TRINKET_GOLDEN_FLAG or 0), false)
            end
            p:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM, 0)
            if t == 40 then
                assert(room:GetGridEntity(room:GetGridIndex(Vector(240, 280))):Destroy(false))
            end
        end)
    elseif t == 180 then
        actor(1, function(p)
            p:AddTrinket(held, false)
        end)
    elseif t == 220 or t == 420 then
        if t == 420 then
            assert(native.rooms_move(0, other, 0, -1))
        end
        assert(native.rooms_move(1, other, 0, -1))
        actor(1, function(_, room)
            clear(room)
        end)
    elseif t == 300 or t == 500 then
        if t == 500 then
            assert(native.rooms_move(0, origin, 0, -1))
        end
        assert(native.rooms_move(1, origin, 0, -1))
    elseif t == 310 or t == 510 then
        actor(1, function(_, room)
            local grid = assert(room:GetGridEntity(room:GetGridIndex(Vector(240, 280))))
            assert(
                grid.State == 4 and grid:GetSprite():GetAnimation() == "Blown",
                "Host lost destroyed TNT on reentry"
            )
        end)
    elseif t == 600 then
        floorSeed = Game():GetSeeds():GetStageSeed(Game():GetLevel():GetStage())
        actor(1, function(p)
            p:UseActiveItem(CollectibleType.COLLECTIBLE_FORGET_ME_NOW, UseFlag.USE_NOANIM, -1)
        end)
    elseif t == 700 then
        assert(
            Game():GetSeeds():GetStageSeed(Game():GetLevel():GetStage()) ~= floorSeed,
            "Forget Me Now did not rebuild the floor"
        )
    end
    checkInventory(t)
    if t >= 850 and not finished then
        assert(inventorySamples > 100 and postFloorSamples > 30)
        finished = true
        report("PASS host TNT, repeated/golden smelting, held slot, reentry and floor reset")
    end
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        function()
            return input.neutral
        end,
        function(t, n, b)
            before(t, n, b)
            advance(t)
        end,
        collect,
        function(bytes, t, ack, between, stable)
            local result = restore(bytes, t, ack, between, stable)
            if result == false then
                return false
            end
            local view = schema.unpack(_IsaacLanState.decode(bytes, stable), t)
            expectedTnt, observedTick = nil, t
            for _, grid in ipairs(view.room[fields.room.grids]) do
                if grid[fields.grid.type] == GridEntityType.GRID_TNT then
                    expectedTnt = grid
                end
            end
            checkInventory(t)
            if t >= 850 and not finished then
                assert(
                    renderSamples > 50
                        and reentrySamples > 30
                        and inventorySamples > 100
                        and postFloorSamples > 30,
                    "Missing TNT render/reentry or inventory observations"
                )
                finished = true
                report("PASS replica render, smelted effects, held slot, reentry and floor reset")
            end
            return result
        end,
        present,
        function(...)
            expectedTnt = nil
            return beginFloor(...)
        end
    )
end
return {
    done = function()
        return finished
    end,
}
