-- Authoritative challenge adapter. Round policy, floor construction, personal
-- visibility and HUD rendering have separate owners; transport stays opaque.
return function(deps)
    local native, rules, enums = deps.native, deps.rules, deps.enums
    local phase = rules.phase
    local model = rules.new()
    local layout, portal, clientView, encounterRoom
    local lastFrame, pressureFrame, bossFrame = nil, nil, nil
    local initialized, deadSince, eliminated, dogma = {}, {}, {}, {}
    local observed = {}
    local pendingSpawns = {}
    local moving, generated, awardPending = false, false, false
    local finishing = false
    local PORTAL_RADIUS, PORTAL_ARM_FRAMES, AWARD_DELAY = 22, 30, 15
    local VISIBILITY_FRAMES = 15
    local function party()
        local result = {}
        for _, actor in ipairs(native.api_actors()) do
            if actor.role == 1 then
                result[actor.owner - 1] = deps.player(actor.index)
            end
        end
        return result
    end
    local function scoped(slot, fn)
        assert(native.rooms_with_player(slot, fn, 1), "Battle royale actor unavailable")
    end
    local function cleanupDogma()
        local players = party()
        for slot, count in pairs(dogma) do
            local player = players[slot]
            if player and player:GetCollectibleNum(enums.collectible.COLLECTIBLE_DOGMA) > count then
                scoped(slot, function()
                    player:RemoveCollectible(enums.collectible.COLLECTIBLE_DOGMA)
                end)
            end
        end
        dogma = {}
    end
    local function nextRound()
        cleanupDogma()
        model.state.phase = phase.loading
        portal, moving, generated, awardPending = nil, false, false, false
        encounterRoom = nil
        deadSince, eliminated = {}, {}
        pendingSpawns = {}
        local game = deps.game()
        game:GetLevel():SetStage(
            deps.random(1, 5),
            deps.random(enums.stageType.STAGETYPE_ORIGINAL, enums.stageType.STAGETYPE_AFTERBIRTH)
        )
        game:StartStageTransition(
            true,
            enums.transition.FADE,
            assert(party()[native.api_info().slot])
        )
    end
    local function initialize(info)
        if info.authority ~= 1 then
            return
        end
        for slot, player in pairs(party()) do
            if not initialized[slot] then
                scoped(slot, function()
                    if player:HasCollectible(enums.collectible.COLLECTIBLE_D6) then
                        player:RemoveCollectible(enums.collectible.COLLECTIBLE_D6)
                    end
                end)
                initialized[slot] = true
            end
        end
    end
    local function onLayoutReady(info, level)
        initialize(info)
        if model.state.round == 0 and not generated then
            generated = true
            nextRound()
            -- The first randomized floor still belongs to round one.
            generated = true
            return
        end
        layout = deps.map.build(level)
        deps.visibility.reset()
        observed = {}
        deadSince, eliminated = {}, {}
        for slot, player in pairs(party()) do
            if player:IsCoopGhost() then
                assert(native.rooms_revive_player(slot), "Round revival failed")
            end
            scoped(slot, function()
                if player:IsDead() then
                    player:Revive()
                end
                player.ControlsEnabled = true
                player:AddHearts(math.max(0, player:GetEffectiveMaxHearts() - player:GetHearts()))
            end)
        end
        model.start(layout.zones)
        generated, moving, lastFrame, pressureFrame, bossFrame = true, false, nil, nil, nil
        for slot in pairs(party()) do
            pendingSpawns[slot] = layout.spawns[slot + 1]
            assert(
                native.rooms_teleport(slot, layout.spawns[slot + 1], 0),
                "Battle royale corner placement failed"
            )
        end
    end
    local function makePortal(slot, kind, frame)
        local at = assert(native.rooms_positions()[tostring(slot)])
        local player = assert(party()[slot])
        scoped(slot, function()
            local room = deps.game():GetRoom()
            local position = kind == "boss" and player.Position
                or room:FindFreePickupSpawnPosition(
                    room:GetCenterPos() + deps.vector(90, 0),
                    0,
                    true
                )
            portal = {
                dimension = at.dimension,
                room = at.index,
                x = position.X,
                y = position.Y,
                kind = kind,
                ready = frame + PORTAL_ARM_FRAMES,
                armed = (player.Position.X - position.X) ^ 2 + (player.Position.Y - position.Y) ^ 2
                    > PORTAL_RADIUS * PORTAL_RADIUS,
            }
            if kind == "boss" then
                player.Velocity = deps.vector(0, 0)
                player:AddControlsCooldown(PORTAL_ARM_FRAMES)
                player:SetMinDamageCooldown(PORTAL_ARM_FRAMES)
                player:AnimateTeleport(true)
            end
        end)
    end
    local function living(info, players, frame)
        local alive, reviving = 0, false
        for slot, player in pairs(players) do
            if (info.connected & (1 << slot)) == 0 then
                eliminated[slot] = true
            elseif eliminated[slot] then
                player:AddControlsCooldown(2)
            elseif player:IsCoopGhost() then
                eliminated[slot] = true
                player:AddControlsCooldown(2)
            elseif player:IsDead() then
                deadSince[slot] = deadSince[slot] or frame
                if
                    player:WillPlayerRevive()
                    or frame - deadSince[slot] < rules.deathGraceFrames
                then
                    reviving = true
                else
                    eliminated[slot] = true
                end
            else
                deadSince[slot] = nil
                alive = alive | (1 << slot)
            end
        end
        return alive, reviving
    end
    local function rewards(slot, frame)
        scoped(slot, function()
            local room = deps.game():GetRoom()
            deps.rewards(assert(party()[slot]))
            deps.map.restrictRoom(room, true)
            if model.state.phase == phase.trophy then
                local trophy = deps.spawn(
                    enums.entity.ENTITY_PICKUP,
                    enums.pickup.PICKUP_TROPHY,
                    0,
                    room:FindFreePickupSpawnPosition(
                        room:GetCenterPos() + deps.vector(-90, 0),
                        0,
                        true
                    ),
                    deps.vector(0, 0),
                    nil
                ):ToPickup()
                trophy.Wait = PORTAL_ARM_FRAMES
            end
        end)
        if model.state.phase == phase.reward then
            makePortal(slot, "next", frame)
        end
    end
    local function enterBoss(slot, player, frame)
        if not model.enter(slot) then
            return
        end
        scoped(slot, function()
            player:AnimateTeleport(false)
        end)
        portal, moving, bossFrame = nil, true, frame
        encounterRoom = model.state.scores[slot + 1] == 1 and layout.finalBoss or layout.boss
        -- This destination is already chosen by the challenge. Native routing
        -- would let Curse of the Maze send the winner to an unrelated room.
        assert(native.rooms_teleport(slot, encounterRoom, 0), "Battle royale boss entry failed")
    end
    local function step(info)
        initialize(info)
        local game, state = deps.game(), model.state
        if state.phase == phase.loading or not layout or game:IsPaused() then
            return
        end
        local frame = game:GetFrameCount()
        if lastFrame == frame then
            return
        end
        local delta = lastFrame and math.max(0, frame - lastFrame) or 0
        lastFrame = frame
        local players = party()
        local alive, reviving = living(info, players, frame)
        local action = model.step(delta, alive, reviving)
        if action == "next" then
            nextRound()
            return
        elseif action == "winner" then
            makePortal(state.winner, "boss", frame)
        end
        local positions = native.rooms_positions()
        for slot, player in pairs(players) do
            local at = positions[tostring(slot)]
            if at and (info.connected & (1 << slot)) ~= 0 then
                local previous = observed[slot]
                if
                    not previous
                    or previous.index ~= at.index
                    or previous.dimension ~= at.dimension
                    or frame - previous.frame >= VISIBILITY_FRAMES
                then
                    deps.visibility.observe(slot)
                    observed[slot] = { index = at.index, dimension = at.dimension, frame = frame }
                end
                scoped(slot, function()
                    local room = game:GetRoom()
                    deps.map.openResources(room)
                    if pendingSpawns[slot] == at.index and at.dimension == 0 then
                        deps.map.clearSpawn(room)
                        pendingSpawns[slot] = nil
                    end
                    if state.phase == phase.survival then
                        if state.elapsed >= rules.shrinkFrames[1] then
                            deps.map.escape(room)
                        end
                        if
                            (alive & (1 << slot)) ~= 0
                            and (not pressureFrame or frame - pressureFrame >= rules.framesPerSecond)
                            and (
                                at.dimension ~= 0
                                or rules.outside(at.index, state)
                                or state.elapsed >= rules.survivalFrames
                            )
                        then
                            player:TakeDamage(
                                rules.pressure(state.elapsed),
                                enums.damage.DAMAGE_NO_PENALTIES,
                                deps.ref(nil),
                                0
                            )
                        end
                    end
                    deps.map.restrictRoom(room)
                end)
            end
        end
        if not pressureFrame or frame - pressureFrame >= rules.framesPerSecond then
            pressureFrame = frame
        end
        local slot, player = state.winner, players[state.winner]
        local at = positions[tostring(slot)]
        if not player or not at or player:IsDead() or player:IsCoopGhost() then
            return
        end
        if portal and portal.kind == "boss" then
            -- Survival has already ended. The portal is a brief automatic
            -- transition, independent of movement, circle deadlines or items
            -- teleporting the winner away from the source room.
            player:AddControlsCooldown(2)
            if frame >= portal.ready and not reviving then
                enterBoss(slot, player, frame)
            end
            return
        end
        if
            state.phase == phase.boss
            and not moving
            and (at.index ~= encounterRoom or at.dimension ~= 0)
        then
            -- Native extra lives may revive in the previous room. Resume the
            -- same encounter without recreating the boss or the temporary item.
            assert(
                native.rooms_teleport(slot, encounterRoom, 0),
                "Battle royale boss return failed"
            )
            return
        end
        if state.phase == phase.boss and at.index == encounterRoom and at.dimension == 0 then
            if moving then
                -- Pickup effects (including the room's shield) belong to the
                -- destination room. Keep the real item through the reward phase.
                scoped(slot, function()
                    dogma[slot] = player:GetCollectibleNum(enums.collectible.COLLECTIBLE_DOGMA)
                    player:AddCollectible(enums.collectible.COLLECTIBLE_DOGMA, 0, true)
                end)
                moving, bossFrame = false, frame
            end
            local clear = false
            scoped(slot, function()
                clear = game:GetRoom():IsClear()
            end)
            if clear and frame - bossFrame >= AWARD_DELAY then
                if not awardPending then
                    awardPending = frame
                elseif frame - awardPending >= AWARD_DELAY and model.clear(slot) then
                    rewards(slot, frame)
                end
            end
        end
        if
            portal
            and frame >= portal.ready
            and at.index == portal.room
            and at.dimension == portal.dimension
        then
            local dx, dy = player.Position.X - portal.x, player.Position.Y - portal.y
            if dx * dx + dy * dy > PORTAL_RADIUS * PORTAL_RADIUS then
                portal.armed = true
            elseif portal.armed then
                if model.leave(slot) then
                    nextRound()
                end
            end
        end
    end
    local function snapshot()
        return {
            model.snapshot(),
            portal and {
                portal.dimension,
                portal.room,
                portal.x,
                portal.y,
                portal.kind,
            } or false,
        }
    end
    local function apply(value)
        assert(type(value) == "table" and #value == 2, "Invalid battle royale view")
        clientView = rules.read(value[1])
        local p = value[2]
        assert(
            p == false
                or (
                    type(p) == "table"
                    and #p == 5
                    and math.type(p[1]) == "integer"
                    and p[1] >= 0
                    and p[1] <= 2
                    and math.type(p[2]) == "integer"
                    and p[2] >= -20
                    and p[2] < 169
                    and type(p[3]) == "number"
                    and p[3] == p[3]
                    and math.abs(p[3]) < 10000
                    and type(p[4]) == "number"
                    and p[4] == p[4]
                    and math.abs(p[4]) < 10000
                    and (p[5] == "boss" or p[5] == "next")
                ),
            "Invalid battle royale portal"
        )
        clientView.portal = p and { dimension = p[1], room = p[2], x = p[3], y = p[4], kind = p[5] }
            or nil
    end
    local function view()
        if native.api_info().authority ~= 1 then
            return clientView
        end
        local result = rules.read(model.snapshot())
        result.portal = portal
        return result
    end
    local function canEnter(ctx)
        if ctx.info.authority ~= 1 then
            return true
        end
        local desc = deps.game():GetLevel():GetRoomByIdx(ctx.room, ctx.dimension)
        local boss = desc and desc.Data and desc.Data.Type == enums.room.ROOM_BOSS
        local state = model.state
        local encounter = state.phase == phase.boss
            or state.phase == phase.reward
            or state.phase == phase.trophy
        if boss then
            local player = party()[ctx.slot]
            local spectator = eliminated[ctx.slot] and player and player:IsCoopGhost()
            return encounter
                and (ctx.slot == state.winner or spectator)
                and layout
                and ctx.room == encounterRoom
                and ctx.dimension == 0
        end
        return not encounter or ctx.slot ~= state.winner or deadSince[ctx.slot] ~= nil
    end
    return {
        initialize = initialize,
        onLayoutReady = onLayoutReady,
        canEnter = canEnter,
        step = step,
        level = function() end,
        clearAward = function() end,
        collect = function()
            return false
        end,
        snapshot = snapshot,
        apply = apply,
        view = view,
        projectMap = deps.visibility.project,
        mapView = function(begin, slot, record)
            local info = native.api_info()
            if info.authority == 1 and model.state.round > 0 then
                deps.visibility.present(slot and slot >= 0 and slot or info.slot, begin, record)
            end
        end,
        allow = function(event)
            if
                event == "coop_revive"
                or event == "game_over"
                or event == "shared_award"
                or event == "specialRoomGather"
            then
                return false
            end
            if event == "floor" or event == "round_revive" then
                return model.state.phase == phase.loading
            end
            return true
        end,
        handles = function(pickup)
            return pickup.Variant == enums.pickup.PICKUP_TROPHY
                or pickup.Variant == enums.pickup.PICKUP_BIGCHEST
        end,
        pickup = function(pickup)
            if pickup.Variant == enums.pickup.PICKUP_BIGCHEST then
                pickup:Remove()
            end
        end,
        collide = function(pickup, player)
            if
                pickup.Variant == enums.pickup.PICKUP_TROPHY
                and model.state.phase == phase.trophy
                and player.ControllerIndex - 1 == model.state.winner
                and not player:IsDead()
                and not player:IsCoopGhost()
                and pickup.Wait <= 0
                and not finishing
            then
                assert(native.net_finish_challenge(), "Battle royale completion rejected")
                finishing = true
            end
            return true
        end,
        reset = function()
            model = rules.new()
            layout, portal, clientView, encounterRoom = nil, nil, nil, nil
            initialized, deadSince, eliminated, dogma = {}, {}, {}, {}
            observed, pendingSpawns = {}, {}
            lastFrame, pressureFrame, bossFrame = nil, nil, nil
            moving, generated, awardPending = false, false, false
            finishing = false
            deps.visibility.reset()
        end,
    }
end
