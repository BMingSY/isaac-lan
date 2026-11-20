-- Original Repentance has no native revive slot. Exercise the actual starting room,
-- real ghost conversion, coin purse and the guest's copy of the station.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, phase = config.host, native.net_phases()
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local floorTick, ghostSeen, revived, guestSawStation
local function report(value)
    Isaac.DebugString("LAN_NETWORK REVIVAL_MACHINE " .. value)
end
local function station()
    local found
    for _, e in
        ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.BACKDROP_DECORATION, 0))
    do
        if e:GetSprite():GetFilename():lower() == "gfx/006.010_restockmachine.anm2" then
            assert(not found, "Duplicate revival machine")
            found = e:ToEffect()
        end
    end
    return found
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, ...)
        before(t, ...)
        local level = Game():GetLevel()
        if level:GetStage() == LevelStage.STAGE1_1 then
            if t == 110 then
                assert(not station(), "Unexpected first-floor station")
                assert(native.api_with_owner(0, function()
                    Game():StartStageTransition(false, RoomTransitionAnim.FADE, Isaac.GetPlayer(0))
                end))
            end
            return
        end
        if not native.rooms_ready() or native.api_info().ready ~= 1 then
            return
        end
        floorTick = floorTick or t
        local age = t - floorTick
        if age == 30 then
            local machine = assert(station(), "Second floor has no revival machine")
            assert(native.actor_ghost(native.rooms_heads()["1"], 1))
            local p = Isaac.GetPlayer(native.rooms_heads()["0"])
            p.Position, p.Velocity = machine.Position, Vector.Zero
            p:AddCoins(9 - p:GetNumCoins())
            report("ghost touching 9-cent payer")
        elseif age == 65 then
            local p = Isaac.GetPlayer(native.rooms_heads()["0"])
            assert(Isaac.GetPlayer(native.rooms_heads()["1"]):IsCoopGhost())
            assert(p:GetNumCoins() == 9 and station().State == 2, "Unpaid revive or wrong target")
            p:AddCoins(1)
            p.Position, p.Velocity = station().Position, Vector.Zero
        elseif age == 105 then
            local p = Isaac.GetPlayer(native.rooms_heads()["0"])
            assert(
                not Isaac.GetPlayer(native.rooms_heads()["1"]):IsCoopGhost(),
                "Paid ghost stayed dead"
            )
            assert(p:GetNumCoins() == 0 and station().State == 0, "Wrong price or stale target")
            p:AddCoins(10)
            p.Position = station().Position
        elseif age == 145 then
            assert(
                Isaac.GetPlayer(native.rooms_heads()["0"]):GetNumCoins() == 10,
                "Repeated charge"
            )
            revived = true
        end
    end, collect, restore, present, beginFloor)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            host and "host" or "join",
            host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= phase.failed, s.error)
    if s.phase == phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == phase.lobby and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "HGQRLGKP:0:0:0:0:0")
    end
    if
        not host
        and s.prepared
        and native.rooms_ready()
        and Game():GetLevel():GetStage() == LevelStage.STAGE1_2
    then
        local machine = station()
        local p = Isaac.GetPlayer(native.rooms_heads()["1"])
        if machine then
            guestSawStation = true
            if p:IsCoopGhost() and machine.State == 2 then
                ghostSeen = true
            end
            if ghostSeen and not p:IsCoopGhost() and machine.State == 0 then
                revived = true
            end
        end
    end
    if revived and (host or guestSawStation and ghostSeen) and not finished then
        finished = true
        report("PASS paid native ghost revival and replicated station")
    end
    return s
end
return {
    done = function()
        return finished
    end,
}
