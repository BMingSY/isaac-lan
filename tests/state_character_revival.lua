-- Native boss revival must retain newly allocated bodies and shared resources.
local native, input, config = assert(_IsaacLan), assert(_IsaacLanTestInput), assert(_IsaacLanTest)
local host, port = config.host, config.port
local kind = config.revivalKind or "tainted-forgotten"
local ownerSlot = config.revivalOwner or 1
local types = {
    ["tainted-forgotten"] = PlayerType.PLAYER_THEFORGOTTEN_B,
    forgotten = PlayerType.PLAYER_THEFORGOTTEN,
    lazarus = PlayerType.PLAYER_LAZARUS_B,
    ["lazarus-birthright"] = PlayerType.PLAYER_LAZARUS_B,
    twins = PlayerType.PLAYER_JACOB,
}
local desired = assert(types[kind], "Unknown revival character")
local expectedBodies = (
    kind == "tainted-forgotten"
    or kind == "twins"
    or kind == "lazarus-birthright"
)
        and 2
    or 1
local fields = assert(_IsaacLanModules["sync/fields"])
local schema = assert(_IsaacLanModules["sync/world_schema"])
local Phase = native.net_phases()
local Actor, Inventory, Resource = fields.actor, fields.inventory, fields.resources
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local snapshots, revivedSamples, initialStage, origin, boss = 0, 0, nil, nil, nil
local pickupSeeds = {}
local owner = { Name = "Native character revival regression" }
local function report(text)
    Isaac.DebugString(
        "LAN_NETWORK CHARACTER_REVIVAL kind=" .. kind .. " owner=" .. ownerSlot .. " " .. text
    )
end
local function player(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(player(slot))
    end))
end
local function roster(ghost)
    local bodies, indexed = {}, {}
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        indexed[p.Index] = p
        if p.ControllerIndex == ownerSlot + 1 then
            assert(p:IsCoopGhost() == ghost, "Owner bodies disagree about revival")
            bodies[#bodies + 1] = p
        end
    end
    if not ghost then
        assert(#bodies == expectedBodies, "Revival lost or duplicated an owned body: " .. #bodies)
        if expectedBodies == 2 then
            for _, p in ipairs(bodies) do
                local twin = assert(p:GetOtherTwin(), "Revival lost the paired body reference")
                assert(indexed[twin.Index], "Paired body is absent from the authoritative roster")
                assert(twin.ControllerIndex == p.ControllerIndex, "Paired body changed owner")
                assert(
                    twin:GetOtherTwin().Index == p.Index,
                    "Paired body reference is not reciprocal"
                )
            end
        end
    end
    return bodies
end
local function resources(coins, bombs, keys)
    for i = 0, Game():GetNumPlayers() - 1 do
        local p = Isaac.GetPlayer(i)
        assert(
            p:GetNumCoins() == coins and p:GetNumBombs() == bombs and p:GetNumKeys() == keys,
            "Revival changed shared resources: "
                .. p:GetNumCoins()
                .. "/"
                .. p:GetNumBombs()
                .. "/"
                .. p:GetNumKeys()
        )
        local golden = Game():GetLevel():GetStage() == initialStage
        assert(
            p:HasGoldenBomb() == golden and p:HasGoldenKey() == golden,
            "Revival or floor travel restored incorrect golden resources"
        )
    end
end
local function pickups()
    actor(1 - ownerSlot, function(p)
        p.Position = Game():GetRoom():GetCenterPos()
        p.Velocity = Vector.Zero
        for _, variant in ipairs({
            PickupVariant.PICKUP_COIN,
            PickupVariant.PICKUP_BOMB,
            PickupVariant.PICKUP_KEY,
        }) do
            local pickup =
                Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, 1, p.Position, Vector.Zero, nil)
                    :ToPickup()
            pickup.Wait = 0
            pickupSeeds[pickup.InitSeed] = true
        end
    end)
end
local function collectPickups()
    actor(1 - ownerSlot, function(p)
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if e:ToPickup() and pickupSeeds[e.InitSeed] then
                p.Position, p.Velocity = e.Position, Vector.Zero
                break
            end
        end
    end)
end
local function verify(t)
    local bodies = roster(false)
    resources(19, 4, 6)
    for _, p in ipairs(bodies) do
        local carried = p:GetPlayerType() == PlayerType.PLAYER_THEFORGOTTEN_B
            and native.actor_held_entity(p:GetOtherTwin():GetSprite()) == p.Index
        assert(
            not p:IsDead() and (p.Visible or carried),
            "Revival left an invisible or dead body: type="
                .. p:GetPlayerType()
                .. " animation="
                .. p:GetSprite():GetAnimation()
        )
        assert(p:GetDamageCooldown() == 0, "Revival body retained a frozen damage blink")
    end
    if kind ~= "lazarus" and kind ~= "lazarus-birthright" then
        assert(
            player(ownerSlot):HasCollectible(CollectibleType.COLLECTIBLE_SAD_ONION),
            "Revival lost the owner's item"
        )
    end
    revivedSamples = revivedSamples + 1
    if t == 620 or t == 760 or t == 1000 then
        report("VERIFIED tick=" .. t .. " bodies=" .. #bodies .. " resources=19/4/6")
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, function()
    if host then
        return false
    end
end, EntityType.ENTITY_PLAYER)
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    if s.phase == Phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == Phase.lobby and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if s.phase == Phase.failed then
        Isaac.DebugString("LAN_NETWORK FAILED " .. s.error)
    end
    if s.verified >= 1020 and not finished then
        assert(revivedSamples > 20, "Missing repeated post-revival observations")
        assert(
            Game():GetLevel():GetStage() > initialStage,
            "Post-revival floor transfer did not complete"
        )
        assert(host or snapshots > 100, "Replica revival was not observed")
        finished = true
        report("PASS boss revival, room travel and floor travel")
    end
    return s
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    initialStage = Game():GetLevel():GetStage()
    return gate(
        function()
            return input.neutral
        end,
        function(t, n, b)
            before(t, n, b)
            if t == 20 then
                actor(ownerSlot, function(p)
                    p:ChangePlayerType(desired)
                    if kind == "lazarus-birthright" then
                        p:AddCollectible(CollectibleType.COLLECTIBLE_BIRTHRIGHT, 0, false)
                    end
                    p:AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION, 0, false)
                end)
                local level = Game():GetLevel()
                origin = level:GetCurrentRoomIndex()
                for i = 0, level:GetRooms().Size - 1 do
                    local d = level:GetRooms():Get(i)
                    if
                        d.Data.Type == RoomType.ROOM_BOSS
                        and d.Data.Shape == RoomShape.ROOMSHAPE_1x1
                    then
                        boss = d.SafeGridIndex
                        break
                    end
                end
                assert(boss, "Missing deterministic boss room")
            elseif t == 60 then
                assert(native.rooms_move(0, boss, 0, 0))
                assert(native.rooms_move(1, boss, 0, 0))
            elseif t == 300 then
                assert(not native.presentation_active(), "Boss introduction did not finish")
                actor(1 - ownerSlot, function(p)
                    p:AddCoins(17 - p:GetNumCoins())
                    p:AddBombs(2 - p:GetNumBombs())
                    p:AddKeys(4 - p:GetNumKeys())
                    p:AddGoldenBomb()
                    p:AddGoldenKey()
                end)
            elseif t == 310 then
                pickups()
            elseif t == 345 then
                roster(false)
                resources(18, 3, 5)
                report("BEFORE_DEATH resources=18/3/5")
            elseif t == 360 then
                actor(ownerSlot, function(p)
                    p:Kill()
                end)
            elseif t == 450 then
                assert(player(ownerSlot):IsCoopGhost(), "Character did not become a co-op ghost")
                resources(18, 3, 5)
                pickups()
            elseif t == 490 then
                resources(19, 4, 6)
                report("GHOST resources=19/4/6")
            end
            if (t > 310 and t < 345) or (t > 450 and t < 490) then
                collectPickups()
            end
            if t >= 500 and t <= 510 then
                actor(1 - ownerSlot, function()
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsActiveEnemy(false) then
                            e:Kill()
                        end
                    end
                end)
            end
            if t == 640 then
                assert(native.rooms_move(ownerSlot, origin, 0, -1))
            elseif t == 700 then
                assert(native.rooms_move(ownerSlot, boss, 0, -1))
            elseif t == 800 then
                Game():GetLevel():SetStage(initialStage + 1, StageType.STAGETYPE_ORIGINAL)
                Game():StartStageTransition(true, RoomTransitionAnim.FADE, player(0))
            end
            if (t >= 610 and t <= 630) or (t >= 750 and t <= 770) or (t >= 990 and t <= 1010) then
                verify(t)
            end
        end,
        collect,
        function(bytes, t, ack, between, stable)
            local result = restore(bytes, t, ack, between, stable)
            if result == false then
                return false
            end
            snapshots = snapshots + 1
            local value = schema.unpack(_IsaacLanState.decode(bytes, stable), t)
            assert(Game():GetNumPlayers() == #value.actors, "Replica roster differs from authority")
            for _, a in ipairs(value.actors) do
                local p = Isaac.GetPlayer(a[Actor.index])
                local inventory = a[Actor.inventory]
                assert(p.ControllerIndex == a[Actor.controller], "Replica body changed owner")
                assert(p:IsCoopGhost() == inventory[Inventory.ghost], "Replica ghost state differs")
                assert(
                    p:GetNumCoins() == inventory[Inventory.resources][Resource.coins],
                    "Replica resource pool differs"
                )
            end
            if (t >= 610 and t <= 630) or (t >= 750 and t <= 770) or (t >= 990 and t <= 1010) then
                verify(t)
            end
            return result
        end,
        present,
        beginFloor
    )
end
return {
    done = function()
        return finished
    end,
}
