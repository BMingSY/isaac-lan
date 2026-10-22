local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local exerciseMenu = _IsaacLanTest.exerciseMenu
local fields = _IsaacLanModules["sync/fields"]
local E, R = fields.entity, fields.room
local schema = _IsaacLanModules["sync/world_schema"]
local json = require("json")
local function report(name, value)
    Isaac.DebugString("LAN_NETWORK NPC_PROBE " .. name .. " " .. json.encode(value))
end
local frame = _IsaacLanFrame
local renders, linked, chosen, done = 0, false, false, false
local menuButtons, menuFrames = 0, 0
local function pollMenuInput()
    local path = "./lan-test-pad.txt"
    if menuFrames == 0 then
        local input = io.open(path, "r")
        if input then
            menuButtons = assert(tonumber(input:read("*l")))
            input:close()
            menuFrames = 12
        end
    end
    native.test_gamepad(menuFrames > 6 and menuButtons or 0)
    if menuFrames > 0 then
        menuFrames = menuFrames - 1
        if menuFrames == 0 then
            assert(os.remove(path))
        end
    end
end
local observedChat, observedField, editing, fieldOptions = false, false, nil, nil
local beginText, endText, menu = native.menu_text_begin, native.menu_text_end, _IsaacLanMenuRender
native.menu_text_begin = function(value, field)
    editing = field
    assert(type(Options.MusicVolume) == "number" and type(Options.SFXVolume) == "number")
    assert(type(Options.Fullscreen) == "boolean", "Fullscreen observation is unavailable")
    fieldOptions = { Options.MusicVolume, Options.SFXVolume, Options.Fullscreen }
    return beginText(value, field)
end
native.menu_text_end = function(...)
    editing, fieldOptions = nil, nil
    return endText(...)
end
function _IsaacLanMenuRender(available, visible, key, typed, ...)
    if editing then
        assert(Options.MusicVolume == fieldOptions[1], "Field typing changed music volume")
        assert(Options.SFXVolume == fieldOptions[2], "Field typing changed sound volume")
        assert(Options.Fullscreen == fieldOptions[3], "Field typing changed fullscreen")
        if editing == "ip" and typed:lower():find("mf", 1, true) and not observedField then
            observedField = true
            Isaac.DebugString("LAN_NETWORK FIELD_HOTKEYS typed MF without changing options")
        end
    end
    return menu(available, visible, key, typed, ...)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not exerciseMenu and not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    if exerciseMenu and not status.prepared then
        pollMenuInput()
    end
    if exerciseMenu and status.phase == 2 and not linked then
        linked = true
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    if not exerciseMenu and status.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if
        not exerciseMenu
        and host
        and status.phase == 2
        and status.players == 2
        and status.ready0 == 1
        and status.ready1 == 1
    then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    if exerciseMenu and not observedChat then
        for _, message in ipairs(_IsaacLanChatMessages()) do
            if message.text:lower() == "lanlobby" then
                assert(status.phase == 2, "Chat was only received after starting gameplay")
                observedChat = true
                Isaac.DebugString("LAN_NETWORK LOBBY_CHAT")
            end
        end
    end
    local tick = status.verified or 0
    local phase = tick % 240
    if status.prepared then
        native.test_gamepad(
            not host and phase > 30 and phase < 210 and (math.floor(phase / 20) % 2 == 0 and 1 or 2)
                or 0
        )
    end
    if status.phase == 4 or status.phase == 9 then
        error(status.error)
    end
    if tick >= 740 and not done then
        done = true
        if exerciseMenu then
            assert(observedChat, "Lobby keyboard chat was not exercised")
            assert(host or observedField, "Address shortcut typing was not exercised")
        end
        Isaac.DebugString("LAN_NETWORK NPC_PROBE PASS native pursuit and display capture")
    end
    return status
end
local cases = {
    { name = "spider", kind = EntityType.ENTITY_SPIDER },
    { name = "charger", kind = EntityType.ENTITY_CHARGER },
    { name = "attackfly", kind = EntityType.ENTITY_ATTACKFLY },
}
local current, lastView, ticks = nil, nil, 0
local function prepare(index)
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type ~= 1 then
            e:Remove()
        end
    end
    local room = Game():GetRoom()
    for i = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(i)
        if
            grid
            and grid:GetType() ~= GridEntityType.GRID_DOOR
            and room:GetGridCollision(i) ~= GridCollisionClass.COLLISION_WALL
        then
            room:RemoveGridEntity(i, 0, false)
        end
    end
    for i = 0, 1 do
        local p = Isaac.GetPlayer(i)
        p.Position = i == 0 and Vector(80, 80) or Vector(360, 250)
        p.Velocity = Vector.Zero
        p:SetMinDamageCooldown(10000)
    end
    current = cases[index]
    Isaac.Spawn(current.kind, 0, 0, Vector(500, 250), Vector.Zero, nil)
    report("CASE", current)
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, ...)
        before(t, ...)
        ticks = t
        if t < 720 and t % 240 == 0 then
            prepare(math.floor(t / 240) + 1)
        end
    end, function(slot, t)
        local bytes, stable = collect(slot, t)
        if slot == 1 and current then
            local v = schema.unpack(_IsaacLanState.decode(bytes, stable), t)
            for _, e in ipairs(v.room[R.entities]) do
                if e[E.type] == current.kind then
                    local target
                    for _, actual in ipairs(Isaac.GetRoomEntities()) do
                        if actual.Type == current.kind then
                            local p = actual:ToNPC():GetPlayerTarget()
                            local player = p and p:ToPlayer()
                            target = player
                                and { player.ControllerIndex, player.Position.X, player.Position.Y }
                            break
                        end
                    end
                    report("HOST", {
                        case = current.name,
                        t = t,
                        at = Isaac.GetTime(),
                        source = v.captured,
                        id = e[E.id],
                        p = e[E.position],
                        v = e[E.velocity],
                        target = target,
                    })
                end
            end
        end
        return bytes, stable
    end, function(bytes, t, ack, between, stable)
        local result = restore(bytes, t, ack, between, stable)
        if result == false then
            return false
        end
        local v = schema.unpack(_IsaacLanState.decode(bytes, stable), t)
        lastView = { t = t, at = Isaac.GetTime(), source = v.captured, entities = {} }
        for _, e in ipairs(v.room[R.entities]) do
            for _, case in ipairs(cases) do
                if e[E.type] == case.kind then
                    lastView.entities[e[E.id]] =
                        { case = case.name, p = e[E.position], v = e[E.velocity] }
                end
            end
        end
        return result
    end, function(...)
        local result = present(...)
        if lastView and not done then
            for _, actual in ipairs(Isaac.GetRoomEntities()) do
                local id = actual:GetData().__isaac_lan_replica
                local a = lastView.entities[id]
                if a then
                    report("CLIENT", {
                        case = a.case,
                        t = lastView.t,
                        at = Isaac.GetTime(),
                        source = lastView.source,
                        received = lastView.at,
                        id = id,
                        p = { actual.Position.X, actual.Position.Y },
                        auth = a.p,
                        v = a.v,
                    })
                end
            end
        end
        return result
    end, beginFloor)
end
