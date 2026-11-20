-- Revive the submitting guest and a teammate in another room through the LAN console.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local frame, gate, step = _IsaacLanFrame, native.net_gate, _IsaacLanActionStep
local phase = native.net_phases()
local renders, linked, chosen, done = 0, false, false, false
local floorTick, destination, ghostSeen, selfRevived, splitAt, remoteDeath, remoteRevived
local hostSawGhost, guestSelf, guestTarget, repeatChecked, returnRequested, crossRoomReady
local crossRoomRevived, splitAgain
local testedMachine, startingCoins
local reviveMachineVariant =
    _IsaacLanModules["compat/challenges/battle_royale_rules"].reviveMachineVariant
local function report(message)
    Isaac.DebugString("LAN_NETWORK REVIVE_COMMAND " .. message)
end
local function actor(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
local function chatHas(text)
    for _, line in ipairs(_IsaacLanChatMessages()) do
        if line.text == text then
            return true
        end
    end
    return false
end
local function checkStation()
    for _, effect in
        ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.BACKDROP_DECORATION, 0))
    do
        assert(
            effect:GetSprite():GetFilename():lower() ~= "gfx/006.010_restockmachine.anm2",
            "Decorative restock machine in starting room"
        )
    end
    local slots = Isaac.FindByType(EntityType.ENTITY_SLOT, reviveMachineVariant)
    assert(#slots == (native.menu_official and 1 or 0), "Unexpected native revival machine count")
    report("second-floor native revival slots=" .. #slots)
    testedMachine = true
end
native.net_gate = function(capture, update, collect, restore, present, beginFloor)
    return gate(capture, function(t, ...)
        update(t, ...)
        if t == 40 then
            Game():StartStageTransition(false, RoomTransitionAnim.FADE, actor(0))
        end
        if not native.rooms_ready() or Game():GetLevel():GetStage() ~= LevelStage.STAGE1_2 then
            return
        end
        floorTick = floorTick or t
        if t - floorTick < 70 then
            return
        end
        if not testedMachine then
            checkStation()
            startingCoins = actor(0):GetNumCoins()
            actor(1):Kill()
        elseif not selfRevived then
            ghostSeen = ghostSeen or actor(1):IsCoopGhost()
            if ghostSeen and not actor(1):IsCoopGhost() and not actor(1):IsDead() then
                selfRevived = t
                report("guest revived self")
            end
        elseif not destination and t > selfRevived + 55 then
            local list = Game():GetLevel():GetRooms()
            for i = 0, list.Size - 1 do
                local d = list:Get(i)
                if
                    d.Data.Type == RoomType.ROOM_DEFAULT
                    and d.SafeGridIndex ~= Game():GetLevel():GetStartingRoomIndex()
                then
                    destination = d.SafeGridIndex
                    break
                end
            end
            assert(native.rooms_move(1, assert(destination), 0, -1))
        elseif destination and native.rooms_positions()["1"].index == destination then
            splitAt = splitAt or t
            actor(1):SetMinDamageCooldown(90)
            if not remoteDeath and t > splitAt + 40 then
                report("host died in a separate room")
                remoteDeath = true
                actor(0):Kill()
            elseif remoteDeath and not remoteRevived then
                hostSawGhost = hostSawGhost or actor(0):IsCoopGhost()
                if hostSawGhost and not actor(0):IsCoopGhost() and not actor(0):IsDead() then
                    remoteRevived = t
                    report("guest revived remote host")
                end
            elseif remoteRevived and t > remoteRevived + 55 and not returnRequested then
                returnRequested = true
                assert(native.rooms_move(0, Game():GetLevel():GetStartingRoomIndex(), 0, -1))
            elseif returnRequested and not crossRoomRevived then
                crossRoomReady = native.rooms_positions()["0"].index ~= destination
            end
        end
    end, collect, restore, present, beginFloor)
end
function _IsaacLanActionStep()
    if not crossRoomReady then
        return step()
    end
    -- A lone ghost normally follows a living teammate. Exercise the command
    -- on an already split roster before the next automatic room transfer.
    crossRoomReady = false
    assert(native.actor_ghost(native.rooms_heads()["1"], 1) and actor(1):IsCoopGhost())
    local positions = native.rooms_positions()
    assert(positions["0"].index ~= positions["1"].index)
    assert(_IsaacLanChatSubmit("/revive P2"))
    step()
    assert(
        not actor(1):IsCoopGhost() and native.rooms_positions()["1"].index == positions["1"].index
    )
    assert(chatHas("2P 已复活"))
    crossRoomRevived = true
    report("host revived guest in the other room")
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (config.host and 300 or 360) then
        linked = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= phase.failed, s.error)
    if s.phase == phase.lobby and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        config.host
        and s.phase == phase.lobby
        and s.players == 2
        and s.ready0 == 1
        and s.ready1 == 1
    then
        _IsaacLanCommand("start", "HGQRLGKP:0:0:0:0:0")
    end
    if
        not done
        and s.prepared
        and s.phase == phase.running
        and native.api_info().ready == 1
        and Game():GetLevel():GetStage() == LevelStage.STAGE1_2
    then
        local positions = native.rooms_positions()
        local split = positions["0"].index ~= positions["1"].index
        if not config.host then
            if not testedMachine and s.verified > 130 then
                checkStation()
            end
            if not guestSelf and actor(1):IsCoopGhost() and not split then
                guestSelf = true
                assert(_IsaacLanChatSubmit("/复活"))
            elseif
                not repeatChecked
                and guestSelf
                and chatHas("2P 已复活")
                and not actor(1):IsCoopGhost()
            then
                repeatChecked = true
                assert(_IsaacLanChatSubmit("/revive 2p"))
                assert(_IsaacLanChatSubmit("/c revive 4p"))
                assert(not _IsaacLanChatSubmit("/复活 5p"))
            elseif not guestTarget and actor(0):IsCoopGhost() then
                guestTarget = true
                assert(_IsaacLanChatSubmit("/c revive 1p"))
            elseif guestTarget and split and chatHas("1P 已复活") then
                splitAgain = splitAgain or s.verified
            end
        end
        if
            split
            and not actor(0):IsCoopGhost()
            and not actor(1):IsCoopGhost()
            and (
                config.host and crossRoomRevived
                or not config.host and splitAgain and s.verified > splitAgain + 15
            )
        then
            if config.host then
                assert(actor(0):GetNumCoins() == startingCoins)
            else
                assert(
                    testedMachine
                        and chatHas("2P 当前不是合作幽灵")
                        and chatHas("4P 未在线")
                )
            end
            done = true
            report("PASS self and remote teammate revived")
        end
        assert(s.verified < 1200 or done, "Revival or command result missing")
    end
    return s
end
return {
    done = function()
        return done
    end,
    cleanup = function()
        _IsaacLanActionStep = step
    end,
}
