-- Repeated metadata, live inventory and tether lifecycle in one native session.
local native, host, port = _IsaacLan, _IsaacLanTest.host, _IsaacLanTest.port
local fields = assert(_IsaacLanModules["sync/fields"])
local schema = assert(_IsaacLanModules["sync/world_schema"])
local A, E, I, M, R = fields.actor, fields.entity, fields.inventory, fields.map, fields.room
local base, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local checks, tetherViews, emptyViews, returnedViews, floorViews = 0, 0, 0, 0, 0
local draws, emptyDraws = 0, nil
local draw = native.familiar_tether_render
native.familiar_tether_render = function(...)
    draws = draws + 1
    return draw(...)
end

local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = base()
    assert(status.phase ~= 4 and status.phase ~= 9, status.error)
    if status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if status.verified >= 600 and not finished then
        assert(
            checks > 50
                and tetherViews > 10
                and emptyViews > 10
                and returnedViews > 10
                and floorViews > 10,
            "Missing repeated metadata/tether/floor observations"
        )
        assert(host or draws > 20, "Replica did not execute native rope drawing")
        finished = true
        report("PASS view metadata inventory costumes and tether lifecycle")
    end
    return status
end
local function verify(bytes, tick, stable)
    if tick < 100 then
        return
    end
    local value = schema.unpack(_IsaacLanState.decode(bytes, stable), tick)
    for _, entry in ipairs(value.map) do
        assert(
            native.room_layout(entry[M.index], entry[M.dimension]) == entry[M.layout],
            "Repeated layout differs from native descriptor"
        )
        assert(
            native.map_pickups(entry[M.index], entry[M.dimension]) == entry[M.pickups],
            "Repeated map pickups differ from native metadata"
        )
    end
    for _, actor in ipairs(value.actors) do
        local player = Isaac.GetPlayer(actor[A.index])
        for _, item in ipairs(actor[A.inventory][I.items]) do
            assert(
                player:GetCollectibleNum(item[1], true) == item[2],
                "Live inventory count differs"
            )
        end
    end
    local ropes = 0
    for _, entity in ipairs(value.room[R.entities]) do
        if entity[E.tether] then
            ropes = ropes + 1
        end
    end
    if tick >= 100 and tick < 160 then
        if ropes == 0 then
            local live = {}
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if entity.Type == EntityType.ENTITY_FAMILIAR then
                    live[#live + 1] = entity.Variant
                        .. ":"
                        .. tostring(not not native.familiar_tether(entity:GetSprite()))
                end
            end
            error("Missing Lilith tether; live familiars=" .. table.concat(live, ","))
        end
        tetherViews = tetherViews + 1
    elseif tick >= 220 and tick < 270 then
        assert(ropes == 0, "Removed familiar retained a tether")
        if not host then
            emptyDraws = emptyDraws or draws
            assert(draws == emptyDraws, "Retired tether still rendered")
        end
        emptyViews = emptyViews + 1
    elseif tick >= 330 and tick < 390 then
        assert(ropes > 0, "Reacquired familiar lost its tether")
        returnedViews = returnedViews + 1
    elseif tick >= 500 then
        assert(value.stage == 2, "Floor cache invalidation was not exercised")
        floorViews = floorViews + 1
    end
    checks = checks + 1
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(function()
        return _IsaacLanTestInput.neutral
    end, function(tick, ...)
        before(tick, ...)
        for i = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            player:SetMinDamageCooldown(10000)
            if tick == 30 or tick == 280 then
                player:ChangePlayerType(PlayerType.PLAYER_LILITH_B)
                player:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
                player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
                player:EvaluateItems()
            elseif tick == 180 then
                player:ChangePlayerType(PlayerType.PLAYER_ISAAC)
                player:RemoveCollectible(CollectibleType.COLLECTIBLE_SAD_ONION, true)
                player:AddCacheFlags(CacheFlag.CACHE_FAMILIARS)
                player:EvaluateItems()
            end
        end
        if tick == 420 then
            Isaac.ExecuteCommand("stage 2")
        end
    end, function(slot, tick)
        local bytes, stable = collect(slot, tick)
        verify(bytes, tick, stable)
        return bytes, stable
    end, function(bytes, tick, ack, between, stable)
        local result = restore(bytes, tick, ack, between, stable)
        if result ~= false then
            verify(bytes, tick, stable)
        end
        return result
    end, present, beginFloor)
end

return {
    done = function()
        return finished
    end,
    cleanup = function()
        _IsaacLanFrame, native.net_gate = base, gate
        native.familiar_tether_render = draw
    end,
}
