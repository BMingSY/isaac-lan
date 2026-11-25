-- Sample both native frames after each ghost conversion and the last lethal hit.
local native, config = _IsaacLan, _IsaacLanTest
local phases, challengeId = native.net_phases(), 1008
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, joined, chosen, started = 0, false, false, false
local guestGhost, hostGhost, verified = false, false, 0
local owner = { Name = "LAN Crime Mode co-op deaths" }

local function player(slot)
    return Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
end
local function hit(slot)
    assert(native.rooms_with_player(slot, function()
        local p = player(slot)
        p:AddHearts(1 - p:GetHearts())
        p:ResetDamageCooldown()
        assert(p:TakeDamage(2, DamageFlag.DAMAGE_INVINCIBLE, EntityRef(nil), 0))
    end))
end
local function splitGuest()
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local room = rooms:Get(i)
        if room.Data and room.Data.Type == RoomType.ROOM_TREASURE and room.SafeGridIndex >= 0 then
            assert(native.rooms_move(1, room.SafeGridIndex, 0, -1))
            return
        end
    end
    error("Missing treasure room for the split death")
end

Isaac.AddCallback(owner, ModCallbacks.MC_POST_GAME_END, function(_, gameOver)
    assert(guestGhost and hostGhost and verified >= 600 and gameOver, "Premature game over")
    Isaac.DebugString("LAN_NETWORK PASS crime coop deaths")
end)

function _IsaacLanFrame()
    renders = renders + 1
    local s = frame()
    assert(s.phase ~= phases.failed, s.error)
    if not joined and renders >= (config.host and 300 or 360) then
        joined = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if s.phase == phases.lobby then
        if s.challenge ~= challengeId then
            if config.host then
                _IsaacLanCommand("challenge", tostring(challengeId))
            end
        elseif not chosen then
            chosen = true
            _IsaacLanCommand("choose", "0:1")
        elseif
            config.host
            and not started
            and s.players == 2
            and s.ready0 == 1
            and s.ready1 == 1
        then
            started = true
            _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
        end
    end
    if s.prepared then
        verified = s.verified or 0
        if verified >= 220 and not guestGhost then
            assert(player(1):IsCoopGhost() and not player(0):IsCoopGhost())
            guestGhost = true
            Isaac.DebugString("LAN_NETWORK CRIME_DEATH guest ghost tick=" .. verified)
        elseif verified >= 535 and not hostGhost then
            assert(player(0):IsCoopGhost() and not player(1):IsCoopGhost())
            hostGhost = true
            Isaac.DebugString("LAN_NETWORK CRIME_DEATH host ghost tick=" .. verified)
        end
    end
    return s
end

native.net_gate = function(capture, before, collect, restore, present, floor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if t == 50 then
            hit(1)
        elseif t == 270 then
            assert(guestGhost and native.actor_ghost(assert(native.rooms_heads()["1"]), 0))
        elseif t == 310 then
            assert(not player(1):IsCoopGhost())
            splitGuest()
        elseif t == 340 then
            hit(0)
        elseif t == 600 then
            assert(hostGhost)
            hit(1)
        end
    end, collect, restore, present, floor)
end
