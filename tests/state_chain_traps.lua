local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local host, port = config.host, config.port
local frame, gate = _IsaacLanFrame, native.net_gate
local renders, linked, chosen, finished = 0, false, false, false
local chainsAt, joined, placed
local checks = 0
local function report(s)
    Isaac.DebugString("LAN_NETWORK CHAIN_TRAPS " .. s)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(native.rooms_heads()[tostring(slot)]), Game():GetRoom())
    end, 1))
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "1XJTX49A:0:0:0:0:0")
    end
    local buttons = 0
    native.test_gamepad(buttons)
    if s.prepared and s.verified > 900 and not finished then
        assert(checks >= 50, "Chain anchor checks were not exercised")
        finished = true
        report("PASS native chain anchors")
    end
    return s
end
local function inspect(t)
    if t < 300 or t % 5 ~= 0 then
        return
    end
    local count = 0
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type == EntityType.ENTITY_BALL_AND_CHAIN then
            assert(
                e.TargetPosition:Distance(Vector(320, 280)) < 0.01,
                "Native chain anchor was not restored"
            )
            count = count + 1
        end
    end
    assert(count == 2, "Real Gehenna chain traps are missing")
    checks = checks + 1
end
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, bytes)
        before(t, n, bytes)
        if t == 30 then
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:SetMinDamageCooldown(10000)
                end)
            end
            Game():GetLevel():SetStage(6, StageType.STAGETYPE_REPENTANCE_B)
            Game():StartStageTransition(true, 0, Isaac.GetPlayer(0))
        end
        if
            t > 220
            and native.rooms_ready()
            and Game():GetLevel():GetStage() == 6
            and not chainsAt
        then
            chainsAt = t
            actor(0, function()
                report("GOTO " .. Isaac.ExecuteCommand("goto d.281"))
            end)
        elseif chainsAt and t >= chainsAt + 30 and not joined then
            joined = true
            local l = native.rooms_positions()["0"]
            assert(native.rooms_move(1, l.index, l.dimension, -1))
        elseif joined and t >= chainsAt + 45 and not placed then
            placed = true
            for slot = 0, 1 do
                actor(slot, function(p, room)
                    p.Position = Vector(160 + slot * 60, 380)
                    p.Velocity = Vector.Zero
                    local count = 0
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e.Type == EntityType.ENTITY_BALL_AND_CHAIN then
                            count = count + 1
                        end
                    end
                    assert(count == 2, "Actual chain room did not spawn its traps")
                end)
            end
        end
    end, function(slot, t)
        if slot == 1 then
            actor(slot, function()
                inspect(t)
            end)
        end
        return collect(slot, t)
    end, function(bytes, t, ack, between, stable)
        local ok = restore(bytes, t, ack, between, stable)
        if ok ~= false then
            actor(1, function()
                inspect(t)
            end)
        end
        return ok
    end, present, beginFloor)
end
return {
    done = function()
        return finished
    end,
}
