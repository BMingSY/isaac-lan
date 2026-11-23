-- Start from the LAN lobby each time. Observe the native starting room before
-- any fixture or replicated entity can populate it.
local native, config = _IsaacLan, _IsaacLanTest
local phases = native.net_phases()
local challengeId, fixedSeed = 1008, "YV039KQF"
local pistolSubtype, gamepadConfirm, firstCinematic = 1, 0x1000, 2
local starts = { "RANDOM", "RANDOM", fixedSeed, fixedSeed }
local run, wins, chosen, requested, checked, renders = 0, 0, 0, 0, 0, 0
local joined, complete, firstSeed, endingAt = false, false, nil, nil
local firstStage, nextFloor, sawShot, fireButtons = nil, false, false, 0
local frame, gate = _IsaacLanFrame, native.net_gate
local owner = { Name = "LAN Crime Mode seed test" }

Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_STARTED, function()
    run = run + 1
    local active = run < #starts
    local seeds = Game():GetSeeds()
    firstStage = Game():GetLevel():GetStage()
    local seed = seeds:GetStartSeedString():gsub("%s", "")
    local effect = Seeds.GetSeedEffect("V1CE BSMT")
    assert(effect > 0 and seeds:HasSeedEffect(effect) == active)
    assert(Game().Challenge == 0)
    if starts[run] == fixedSeed then
        assert(seed == fixedSeed, "Lobby map seed was replaced")
    elseif run == 1 then
        firstSeed = seed
    elseif run == 2 then
        assert(seed ~= firstSeed, "Second random launch reused the same map seed")
    end
    local guns, lights = 0, 0
    local weapon = Isaac.GetEntityVariantByName("Weapon")
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if
            entity.Type == EntityType.ENTITY_PICKUP
            and entity.Variant == weapon
            and entity.SubType == pistolSubtype
        then
            guns = guns + 1
        elseif entity:GetSprite():GetFilename():lower() == "gfx/promo/crime/spotlight.anm2" then
            lights = lights + 1
        end
    end
    assert((guns > 0) == active and (lights > 0) == active, "Unexpected native starting room")
    Isaac.DebugString(
        string.format(
            "LAN_NETWORK CRIME_START run=%d seed=%s stageSeed=%s guns=%d lights=%d",
            run,
            seed,
            tostring(seeds:GetStageSeed(Game():GetLevel():GetStage())),
            guns,
            lights
        )
    )
end)
Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_END, function(_, over)
    assert(not over)
    if run == 1 then
        assert(sawShot, "Missing guest shot from the starting pistol")
    elseif run == 2 then
        assert(nextFloor, "Missing second floor with the lobby seed and crime effect")
    end
    wins = wins + 1
end)
function _IsaacLanFrame()
    renders = renders + 1
    local s = frame()
    assert(s.phase ~= phases.failed, s.error)
    if s.prepared and run == 1 and not sawShot then
        for _, tear in ipairs(Isaac.FindByType(EntityType.ENTITY_TEAR)) do
            local owner = tear.SpawnerEntity or tear.Parent
            local player = owner and owner:ToPlayer()
            if
                player
                and player.ControllerIndex == 2
                and tear:GetSprite():GetFilename():lower() == "gfx/promo/crime/bullet tear.anm2"
            then
                sawShot = true
                Isaac.DebugString("LAN_NETWORK CRIME_SHOT guest")
                break
            end
        end
    elseif
        s.prepared
        and run == 2
        and not nextFloor
        and Game():GetLevel():GetStage() > firstStage
    then
        local seeds = Game():GetSeeds()
        assert(
            seeds:GetStartSeedString():gsub("%s", "") == s.seed
                and seeds:HasSeedEffect(Seeds.GetSeedEffect("V1CE BSMT"))
        )
        nextFloor = true
        Isaac.DebugString(
            "LAN_NETWORK CRIME_FLOOR seed="
                .. s.seed
                .. " stageSeed="
                .. seeds:GetStageSeed(Game():GetLevel():GetStage())
        )
    end
    if not joined and renders >= (config.host and 300 or 360) then
        joined = true
        assert(native.net_challenges()[tostring(challengeId)].available)
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local nextRun = wins + 1
    if s.phase == phases.lobby and s.scene == 1 and run == wins and nextRun <= #starts then
        local id = nextRun < #starts and challengeId or 0
        if s.challenge ~= id then
            if config.host then
                _IsaacLanCommand("challenge", tostring(id))
            end
        elseif chosen < nextRun then
            chosen = nextRun
            _IsaacLanCommand("choose", "0:1")
        elseif
            config.host
            and requested < nextRun
            and s.players == 2
            and s.ready0 == 1
            and s.ready1 == 1
        then
            requested = nextRun
            _IsaacLanCommand("start", starts[nextRun] .. ":0:0:0:0:0")
        end
    end
    if s.prepared and run > checked and (s.verified or 0) >= 30 then
        assert(
            s.seed == Game():GetSeeds():GetStartSeedString():gsub("%s", ""),
            "Peers must use the lobby seed"
        )
        checked = run
        if run == #starts and not complete then
            complete = true
            Isaac.DebugString("LAN_NETWORK PASS crime mode lobby seeds")
        end
    end
    if s.scene == 3 then
        endingAt = endingAt or Isaac.GetTime()
    else
        endingAt = nil
    end
    native.test_gamepad(
        endingAt and Isaac.GetTime() - endingAt > 1000 and renders % 30 < 5 and gamepadConfirm or 0
    )
    return s
end
native.net_gate = function(capture, before, collect, restore, present, floor)
    local function shoot()
        if run ~= 1 or config.host then
            return capture()
        end
        local t = _IsaacLanStatus().verified or 0
        local buttons = t >= 70 and t % 12 < 7 and (1 << ButtonAction.ACTION_SHOOTRIGHT) or 0
        local input = _IsaacLanTestInput.buttons(buttons, buttons & ~fireButtons)
        fireButtons = buttons
        return input
    end
    return gate(shoot, function(t, n, bytes)
        before(t, n, bytes)
        if run == 1 and t == 45 then
            assert(native.rooms_with_player(1, function()
                local gun = assert(
                    Isaac.FindByType(
                        EntityType.ENTITY_PICKUP,
                        Isaac.GetEntityVariantByName("Weapon"),
                        pistolSubtype
                    )[1]
                )
                local guest = Isaac.GetPlayer(assert(native.rooms_heads()["1"]))
                guest.Position, guest.Velocity = gun.Position, Vector.Zero
            end))
        elseif run == 2 and t == 60 then
            assert(native.rooms_with_player(0, function()
                Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
            end))
        elseif run < #starts and t == 210 then
            Game():End(firstCinematic)
        end
    end, collect, restore, present, floor)
end
