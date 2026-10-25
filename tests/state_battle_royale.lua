-- Native full-round acceptance: one process pair, no production timing overrides.
local native = assert(_IsaacLan)
local function read(path)
    local file = assert(io.open(path, "r"))
    local value = file:read("*l")
    file:close()
    return value
end
local host = read("./lan-test-role.txt") == "host"
local port = read("./lan-test-menu-port.txt")
local rules = assert(_IsaacLanModules["compat/challenges/battle_royale_rules"])
local phase = rules.phase
local frame, action = _IsaacLanFrame, _IsaacLanActionStep
local frames, linked, chosen, running, finished = 0, false, false, false, false
local step, at, baselineRound, sawGuest = "start", 0, nil, false
local seen = {}
local mapDraws, mapWidths = 0, {}
local flow, winner = _IsaacLanBattleFlow, _IsaacLanBattleWinner or 0
local loser = 1 - winner
local roomOptions = 0
for _, option in ipairs(native.net_room_options()) do
    if option.key == "friendlyFire" or option.key == "specialRoomGather" then
        roomOptions = roomOptions | option.flag
    end
end
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        local player = Isaac.GetPlayer(0)
        assert(player.ControllerIndex == slot + 1)
        fn(player)
    end, 1))
end
local function mark(value)
    step, at = value, Game():GetFrameCount()
    report("BATTLE " .. value)
end
local function view()
    return _IsaacLanState.challengeView()
end
local function park()
    for slot = 0, 1 do
        actor(slot, function(player)
            player:SetMinDamageCooldown(10000)
            player.Velocity = Vector.Zero
        end)
    end
end
local function enterPortal()
    local portal = assert(view().portal)
    actor(winner, function(player)
        player.Position = Vector(portal.x, portal.y)
    end)
end
local function defeatBoss()
    actor(winner, function(player)
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            if entity:IsActiveEnemy(false) then
                entity:TakeDamage(1000000, DamageFlag.DAMAGE_IGNORE_ARMOR, EntityRef(player), 0)
            end
        end
    end)
end
local function advance()
    action()
    local info = native.api_info()
    local state = view()
    if not host or info.ready ~= 1 or not state or state.round == 0 or finished then
        return
    end
    running = true
    assert(info.challenge == rules.id and Game().Difficulty == Difficulty.DIFFICULTY_NORMAL)
    park()
    local elapsed = Game():GetFrameCount() - at
    if step == "start" and state.phase == phase.survival and state.elapsed > 90 then
        assert((info.roomOptions & 1) ~= 0, "Challenge did not force existing PvP")
        local positions = native.rooms_positions()
        assert(positions["0"].index ~= positions["1"].index, "Players did not spawn apart")
        local level = Game():GetLevel()
        assert(level:GetStage() >= 1 and level:GetStage() <= 5)
        assert(level:GetRooms().Size >= 100, "Red rooms did not expand across the floor")
        local final = level:GetRoomByIdx(state.zones[#rules.zoneSizes], 0)
        assert(
            final
                and final.Data
                and final.Data.Type == RoomType.ROOM_DEFAULT
                and final.Data.Shape == RoomShape.ROOMSHAPE_1x1,
            "Final zone is not a playable room"
        )
        report("BATTLE zones=" .. table.concat(state.zones, ","))
        for slot = 0, 1 do
            actor(slot, function(player)
                assert(player:GetPlayerType() == PlayerType.PLAYER_ISAAC)
                assert(not player:HasCollectible(CollectibleType.COLLECTIBLE_D6))
            end)
        end
        local boss
        for index = 0, level:GetRooms().Size - 1 do
            local desc = level:GetRooms():Get(index)
            if desc.Data.Type == RoomType.ROOM_BOSS then
                boss = desc.SafeGridIndex
                break
            end
        end
        assert(boss and not native.api_move(0, boss, 0), "Boss room was accessible before victory")
        assert(native.api_move(0, rules.center, 0) and native.api_move(1, rules.center, 0))
        baselineRound = state.round
        -- Capture the real per-peer wire contract before the corner visits can
        -- be hidden by the compact native minimap's viewport.
        local schema = _IsaacLanModules["sync/world_schema"]
        local fields = _IsaacLanModules["sync/fields"].map
        local own = {}
        for slot = 0, 1 do
            local bytes = _IsaacLanState.capture(slot, info.tick)
            local value = schema.unpack(_IsaacLanState.decode(bytes), info.tick)
            local restored = rules.read(value.challenge[3][1])
            assert(
                table.concat(restored.zones, ",") == table.concat(state.zones, ","),
                "Peer zones differ"
            )
            own[slot] = {}
            for _, entry in ipairs(value.map) do
                own[slot][entry[fields.index]] = entry[fields.visited]
            end
        end
        assert(own[0][positions["0"].index] > 0 and own[1][positions["0"].index] == 0)
        assert(own[1][positions["1"].index] > 0 and own[0][positions["1"].index] == 0)
        report("BATTLE PASS lobby, red-room map, corners and boss gate")
        actor(0, function(player)
            player:SetCard(0, Card.CARD_WORLD)
        end)
        mark("map-effects")
    elseif step == "map-effects" and elapsed > 90 then
        actor(0, function(player)
            assert(player:GetCard(0) == 0, "World card was not consumed through normal input")
        end)
        local schema = _IsaacLanModules["sync/world_schema"]
        local fields = _IsaacLanModules["sync/fields"].map
        local visible = {}
        for slot = 0, 1 do
            local bytes = _IsaacLanState.capture(slot, info.tick)
            local value = schema.unpack(_IsaacLanState.decode(bytes), info.tick)
            visible[slot] = 0
            for _, entry in ipairs(value.map) do
                if entry[fields.display] ~= 0 then
                    visible[slot] = visible[slot] + 1
                end
            end
        end
        assert(visible[0] > 100 and visible[1] < 30, "World card revealed another player's map")
        report("BATTLE PASS private native mapping effect")
        actor(loser, function(player)
            player:AddCollectible(CollectibleType.COLLECTIBLE_1UP)
            player:Kill()
        end)
        mark("extra-life")
    elseif step == "extra-life" and elapsed > 300 then
        assert(state.phase == phase.survival, "Natural revival prematurely ended survival")
        actor(loser, function(player)
            assert(not player:IsDead() and not player:IsCoopGhost())
            assert(not player:HasCollectible(CollectibleType.COLLECTIBLE_1UP))
            if flow then
                player:Kill()
            end
        end)
        report("BATTLE PASS natural extra life")
        mark(flow and "winner" or "circles")
    elseif step == "circles" then
        local _, circle = rules.zone(state)
        if not seen[circle] then
            seen[circle] = true
            report("BATTLE circle=" .. circle)
        end
        if state.elapsed >= rules.survivalFrames + 60 then
            assert(seen[1] and seen[2] and seen[3] and seen[4])
            actor(loser, function(player)
                player:SetMinDamageCooldown(0)
                player:Die()
            end)
            report("BATTLE PASS three natural circles and overtime")
            mark("winner")
        end
    elseif step == "winner" and state.phase == phase.boss then
        assert(
            state.winner == winner and state.scores[winner + 1] == 0 and elapsed < 180,
            "Last survivor did not automatically enter the boss flow"
        )
        report("BATTLE PASS automatic ordinary boss entry")
        mark("boss")
    elseif
        step == "boss"
        and state.phase == phase.boss
        and elapsed > 120
        and not Game():IsPaused()
    then
        actor(winner, function(player)
            assert(player:HasCollectible(CollectibleType.COLLECTIBLE_DOGMA))
        end)
        defeatBoss()
    elseif step == "boss" and state.phase == phase.reward then
        actor(loser, function(player)
            assert(player:IsCoopGhost(), "Boss clear revived the loser")
        end)
        actor(winner, function(player)
            assert(not player:HasCollectible(CollectibleType.COLLECTIBLE_DOGMA))
            local guaranteed = false
            for _, entity in ipairs(Isaac.GetRoomEntities()) do
                if
                    entity.Type == EntityType.ENTITY_PICKUP
                    and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE
                then
                    guaranteed = guaranteed
                        or Isaac.GetItemConfig():GetCollectible(entity.SubType).Quality >= 3
                end
            end
            assert(guaranteed, "Boss did not produce a high-quality reward")
            player.Position = Game():GetRoom():GetCenterPos()
        end)
        report("BATTLE PASS ordinary boss, quality guarantee and no clear revival")
        mark("skip")
    elseif step == "skip" and elapsed > 90 then
        assert(state.scores[winner + 1] == 1 and state.phase == phase.reward)
        enterPortal()
        mark("round-two")
    elseif
        step == "round-two"
        and state.round > baselineRound
        and state.phase == phase.survival
        and state.elapsed > 90
    then
        for slot = 0, 1 do
            actor(slot, function(player)
                assert(
                    not player:IsCoopGhost()
                        and player:GetHearts() == player:GetEffectiveMaxHearts()
                )
            end)
        end
        assert(state.scores[winner + 1] == 1)
        actor(loser, function(player)
            player:Die()
        end)
        mark("match-point")
    elseif step == "match-point" and state.phase == phase.boss then
        assert(elapsed < 180, "Match-point survivor waited for a manual portal or circle")
        report("BATTLE PASS automatic Mom entry before the first shrink")
        mark("mom")
    elseif
        step == "mom"
        and state.phase == phase.boss
        and elapsed > 360
        and not Game():IsPaused()
    then
        actor(winner, function()
            if not seen.mom then
                assert(
                    #Isaac.FindByType(EntityType.ENTITY_MOM) > 0,
                    "Match point did not start Mom"
                )
                seen.mom = true
            end
        end)
        if not seen.failure then
            seen.failure, baselineRound = true, state.round
            actor(winner, function(player)
                player:Kill()
            end)
            mark("boss-failure")
        else
            defeatBoss()
        end
    elseif step == "boss-failure" and state.round > baselineRound and state.elapsed > 90 then
        assert(state.phase == phase.survival and state.scores[winner + 1] == 1)
        actor(loser, function(player)
            player:Kill()
        end)
        report("BATTLE PASS failed Mom retains match point and starts another round")
        mark("match-point")
    elseif step == "mom" and state.phase == phase.trophy then
        actor(loser, function(player)
            assert(player:IsCoopGhost())
        end)
        assert(state.scores[winner + 1] == 2)
        report("BATTLE PASS Mom and two-win championship")
        mark("trophy")
    elseif step == "trophy" and elapsed > 150 then
        actor(winner, function(player)
            local trophies = Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_TROPHY)
            assert(#trophies == 1)
            trophies[1]:ToPickup().Wait = 0
            player.Position = trophies[1].Position
        end)
        mark("finish")
    end
end
function _IsaacLanActionStep()
    local ok, reason = pcall(advance)
    if not ok then
        report("FAILED " .. tostring(reason))
        error(reason)
    end
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 480) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local status = frame()
    local mapInput = host and step == "map-effects" and Game():GetFrameCount() - at < 10
    local current = view()
    local expandMap = current and current.phase == phase.survival and current.elapsed % 600 < 300
    native.test_gamepad((mapInput and 512 or 0) | (expandMap and 32 or 0))
    if status.phase == 4 or status.phase == 9 then
        report("FAILED " .. tostring(status.error))
    end
    if not running and status.phase == 2 then
        if host and status.challenge ~= rules.id then
            _IsaacLanCommand("challenge", tostring(rules.id))
        end
        if host and status.challenge == rules.id and status.roomOptions ~= roomOptions then
            assert(native.net_configure_options(roomOptions))
        end
        if status.challenge == rules.id and status.roomOptions == roomOptions and not chosen then
            chosen = true
            _IsaacLanCommand("choose", "0:1")
        end
        if host and status.players == 2 and status.ready0 == 1 and status.ready1 == 1 then
            _IsaacLanCommand("start", "N024KHNP:0:0:0:0:0")
        end
    end
    local info = native.api_info()
    if info.active == 1 and info.ready == 1 then
        running = true
        local state = view()
        if not host and state and state.phase == phase.trophy then
            assert(state.scores[winner + 1] == 2)
            sawGuest = true
            if not seen.guest then
                seen.guest = true
                report("BATTLE PASS replica progress and trophy")
            end
        end
    end
    if running and not finished and info.active ~= 1 and status.phase == 2 then
        assert(host and step == "finish" or not host and sawGuest)
        assert(mapDraws > 100, "Native minimap projection did not reach the render callback")
        local widths = 0
        for _ in pairs(mapWidths) do
            widths = widths + 1
        end
        assert(widths >= 2, "Both compact and expanded map views were not exercised")
        finished = true
        report("PASS battle royale")
    end
    return status
end

local overlayOwner = { Name = "Isolated battle royale minimap regression" }
Isaac.AddCallback(overlayOwner, ModCallbacks.MC_POST_RENDER, function()
    local current = view()
    if not current or current.phase ~= phase.survival then
        return
    end
    for _, map in pairs(native.presentation_minimap()) do
        assert(map.right > map.left and map.bottom > map.top and map.cellWidth > 0)
        mapDraws = mapDraws + 1
        local width = math.floor(map.right - map.left + 0.5)
        if not mapWidths[width] then
            mapWidths[width] = true
            report("BATTLE minimap width=" .. width .. " cell=" .. map.cellWidth)
        end
    end
end)
