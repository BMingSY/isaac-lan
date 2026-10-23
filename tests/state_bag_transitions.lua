local testInput = assert(_IsaacLanTestInput)
-- Repeated raise/lower transitions, with EID on/off, in one isolated session.
local native = assert(_IsaacLan)
local previousSprite, previousPrediction = native.sprite_state, _IsaacLanPrediction.new
local previousEidMethods, previousBagMode = {}, nil
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local renders, verified, previousButtons = 0, 0, 0
local linked, chosen, finished, prepared = false, false, false, false
local eid, lastRender, remoteBag
local resets, transitions = 0, 0
local output = assert(io.open(_IsaacLanTest.sceneOutput or "./lan-test-digest-scenes.csv", "w"))
output:write(
    "time_ms,tick,phase,interval_ms,x,y,extra_finished,animation,extra_animation,holding,prediction_resets\n"
)
local function report(message)
    Isaac.DebugString("LAN_NETWORK SCENES " .. message)
end
local function actor(slot, fn)
    assert(native.rooms_with_player(slot, function()
        fn(Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)])))
    end))
end
local function scene(t)
    local cycle = math.floor((t - 216) / 72)
    return cycle, (t - 216) % 72
end
local newPrediction = _IsaacLanPrediction.new
_IsaacLanPrediction.new = function(...)
    local value = newPrediction(...)
    local reset = value.reset
    value.reset = function(...)
        resets = resets + 1
        return reset(...)
    end
    return value
end
local frame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if finished then
        native.test_gamepad(0)
        return frame()
    end
    if not eid then
        for mod, handle in pairs(_IsaacLanModules["api/public"].modHandles) do
            if handle.id == "isaac-lan.compat.eid" then
                eid = mod
                previousBagMode = eid.Config.DisplayBagOfCrafting
            end
        end
    end
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local s = frame()
    assert(s.phase ~= 4 and s.phase ~= 9, s.error)
    verified, prepared = s.verified, s.prepared
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "23:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:23:23:0:0")
    end
    local cycle, offset = scene(verified)
    local moving = prepared and not host and cycle >= 0 and cycle < 6
    native.test_gamepad(moving and (offset < 18 and 8 or offset >= 36 and offset < 54 and 4) or 0)
    local visibleEID = cycle < 3 or cycle == 6
    if eid then
        eid.Config.DisplayBagOfCrafting = visibleEID and "hold" or "never"
    end
    if prepared and native.rooms_ready() and verified >= 180 then
        local index = assert(native.rooms_heads()["1"])
        local p = Isaac.GetPlayer(index)
        local sprites = assert(native.actor_sprites(index, p:GetSprite()))
        local holding = host and p:GetItemState() == CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING
            or not host and remoteBag and remoteBag[2]
            or false
        local now = Isaac.GetTime()
        output:write(
            string.format(
                "%.3f,%d,%s,%.3f,%.3f,%.3f,%s,%s,%s,%s,%d\n",
                now,
                verified,
                visibleEID and "eid" or "no_eid",
                lastRender and now - lastRender or 0,
                p.Position.X,
                p.Position.Y,
                tostring(p:IsExtraAnimationFinished()),
                p:GetSprite():GetAnimation(),
                sprites[1]:GetAnimation(),
                tostring(holding),
                resets
            )
        )
        lastRender, resets = now, 0
        if renders % 60 == 0 then
            output:flush()
        end
    end
    if verified >= 810 then
        assert(eid, "EID adapter was not active")
        assert(host or transitions >= 16, "Not all repeated raise/lower transitions arrived")
        output:flush()
        finished = true
        report("PASS scene observation")
    end
    return s
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        function()
            local physical, input, buttons = testInput.decode(capture()), {}, 0
            local cycle, offset = scene(verified)
            for action = 0, testInput.actionCount - 1 do
                local value = physical.values[action]
                if action == ButtonAction.ACTION_PILLCARD then
                    value = prepared
                            and not host
                            and cycle >= 0
                            and cycle < 8
                            and ((offset >= 6 and offset < 9) or (offset >= 42 and offset < 45))
                            and testInput.maxValue
                        or 0
                end
                input[action] = value
                if value > 0 then
                    buttons = buttons | (1 << action)
                end
            end
            local bytes =
                testInput.encode({ values = input, triggered = buttons & ~previousButtons })
            previousButtons = buttons
            return bytes
        end,
        function(t, n, bytes)
            before(t, n, bytes)
            if t == 30 then
                for slot = 0, 1 do
                    actor(slot, function(p)
                        p:SetMinDamageCooldown(100000)
                        p.Position = Game():GetRoom():GetCenterPos()
                            + Vector(slot == 0 and -130 or 50, 0)
                        for _, e in ipairs(Isaac.GetRoomEntities()) do
                            if e:IsActiveEnemy(false) then
                                e:Remove()
                            end
                        end
                        Game():GetRoom():SetClear(true)
                    end)
                end
                for i, variant in ipairs({ 10, 20, 30, 40, 90, 300, 70, 10, 20, 30, 40, 90 }) do
                    Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        variant,
                        1,
                        Vector(100 + (i % 6) * 70, 200 + math.floor(i / 6) * 60),
                        Vector.Zero,
                        nil
                    )
                end
            end
        end,
        collect,
        function(bytes, t, ack, betweenUpdates, stable)
            if restore(bytes, t, ack, betweenUpdates, stable) == false then
                return false
            end
            for _, a in ipairs(_IsaacLanState.decode(bytes, stable)[9]) do
                if a[2] == 2 then
                    if remoteBag and remoteBag[2] ~= a[8][2] then
                        transitions = transitions + 1
                        report("BAG holding=" .. tostring(a[8][2]) .. " tick=" .. t)
                    end
                    remoteBag = a[8]
                end
            end
            return true
        end,
        present,
        beginFloor
    )
end

return {
    done = function()
        return finished
    end,
    cleanup = function()
        output:close()
        native.sprite_state, _IsaacLanPrediction.new = previousSprite, previousPrediction
        if eid then
            for name, fn in pairs(previousEidMethods) do
                eid[name] = fn
            end
            eid.Config.DisplayBagOfCrafting = previousBagMode
        end
    end,
}
