-- One owned pair keeps both random pools anonymous until the native launch.
local native, config = assert(_IsaacLan), assert(_IsaacLanTest)
local frame, menu = _IsaacLanFrame, _IsaacLanMenuRender
local Phase = native.net_phases()
local slot = config.host and 0 or 1
local choiceKey, readyKey = "choice" .. slot, "ready" .. slot
local renders, linked, began, stage, due, key = 0, false, false, 1, 0, 0
local normal, tainted, finalChoice, readyAnchors
local finalPool = {}
local finished = false
local function report(value)
    Isaac.DebugString("LAN_CHARACTER_MENU " .. value)
end
local function send(value)
    assert(key == 0)
    key = value
    due = renders + 90 -- Leave a stable native frame for each selection.
    stage = stage + 1
end
local function selected(status, expected)
    assert(status[choiceKey] == expected, "Native menu selected another character")
    assert(status[readyKey] == 0, "Selection unexpectedly readied the player")
    assert(not status["random" .. slot], "Concrete selection remained deferred")
end
local function randomSelection(status, group)
    local choices, catalog = native.net_characters()
    assert(
        status["random" .. slot] and not status["marks" .. slot],
        "Random choice exposed a character preview"
    )
    local entry = assert(catalog[tostring(status[choiceKey])])
    assert(entry.tainted == group, "Random crossed the selected character group")
    local found = false
    for _, id in ipairs(choices) do
        found = found or id == status[choiceKey]
    end
    assert(found, "Random selected an unavailable character")
end
local function randomReady(status, group)
    randomSelection(status, group)
    assert(status[readyKey] == 1, "Random menu selection did not ready")
    report("RANDOM_READY tainted=" .. tostring(group) .. " hidden=true")
end
function _IsaacLanMenuRender(available, visible, input, typed, mx, my, clicked, ...)
    if linked and _IsaacLanStatus().phase == Phase.lobby then
        visible, input, typed, mx, my, clicked = true, key, "", -1000, -1000, false
        key = 0
    end
    return menu(available, visible, input, typed, mx, my, clicked, ...)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (config.host and 300 or 420) then
        linked = true
        _IsaacLanCommand(
            config.host and "host" or "join",
            config.host and config.port or "127.0.0.1:" .. config.port
        )
        _IsaacLanMenuOpen(true)
        Isaac.DebugString("LAN_NETWORK MENU_READY")
    end
    local status = frame()
    assert(status.phase ~= Phase.failed, status.error)
    if status.phase == Phase.lobby and status.players == 2 and not began then
        began = true
        local choices, catalog = native.net_characters()
        local available = {}
        for _, id in ipairs(choices) do
            available[id] = true
        end
        for _, id in ipairs(choices) do
            local entry = catalog[tostring(id)]
            if not entry.tainted and entry.counterpart and available[entry.counterpart] then
                normal, tainted = id, entry.counterpart
                break
            end
        end
        assert(normal and tainted, "Fixture needs an unlocked native or Mod pair")
        _IsaacLanCommand("choose", normal .. ":0")
        due = renders + 90
    end
    if began and status.phase == Phase.lobby and key == 0 and renders >= due then
        if stage == 1 then
            selected(status, normal)
            send(69)
        elseif stage == 2 then
            selected(status, tainted)
            report("PAIRED_TAINTED character=" .. tainted)
            send(69)
        elseif stage == 3 then
            selected(status, normal)
            report("PAIRED_NORMAL character=" .. normal)
            -- First selectable role in each group is immediately after Random.
            local choices, catalog = native.net_characters()
            for _, id in ipairs(choices) do
                if not catalog[tostring(id)].tainted then
                    _IsaacLanCommand("choose", id .. ":0")
                    break
                end
            end
            send(0)
        elseif stage == 4 then
            send(37)
        elseif stage == 5 then
            randomSelection(status, false)
            report("RANDOM_NORMAL_VISIBLE")
            send(40)
        elseif stage == 6 then
            send(13)
        elseif stage == 7 then
            randomReady(status, false)
            send(13) -- Unready keeps the deferred group, without drawing.
        elseif stage == 8 then
            assert(status[readyKey] == 0)
            randomSelection(status, false)
            local choices, catalog = native.net_characters()
            for _, id in ipairs(choices) do
                if catalog[tostring(id)].tainted then
                    _IsaacLanCommand("choose", id .. ":0")
                    break
                end
            end
            send(38)
        elseif stage == 9 then
            send(37)
        elseif stage == 10 then
            randomSelection(status, true)
            report("RANDOM_TAINTED_VISIBLE")
            send(69) -- Random switches pools without drawing.
        elseif stage == 11 then
            randomSelection(status, false)
            report("RANDOM_NORMAL_SWITCHED")
            send(config.host and 0 or 69) -- Launch one normal and one tainted random role.
        elseif stage == 12 then
            send(40)
        elseif stage == 13 then
            send(13)
        elseif stage == 14 then
            randomReady(status, not config.host)
            finalChoice = status[choiceKey]
            send(38)
        elseif stage == 15 then
            send(69) -- Ready locks switching.
        elseif stage == 16 then
            assert(status[readyKey] == 1 and status[choiceKey] == finalChoice)
            randomSelection(status, not config.host)
            if status.ready0 == 1 and status.ready1 == 1 then
                assert(
                    status.random0 and status.random1 and not status.marks0 and not status.marks1
                )
                readyAnchors = { status.choice0, status.choice1 }
                local choices, catalog = native.net_characters()
                for _, id in ipairs(choices) do
                    if catalog[tostring(id)].tainted == not config.host then
                        finalPool[id] = true
                    end
                end
                report("LOCKED_AND_PUBLISHED hidden=true")
                if config.host then
                    -- Start through the production menu after the client also checks its lock.
                    send(40)
                    due = renders + 240
                else
                    stage = 22
                end
            end
        elseif stage >= 17 and stage <= 20 then
            send(40)
        elseif stage == 21 then
            send(13)
        end
    end
    if readyAnchors and status.phase == Phase.running and status.prepared and not finished then
        assert(status.choice0 == readyAnchors[1] and status.choice1 == readyAnchors[2])
        assert(status.random0 and status.random1, "Launch rewrote the lobby choice")
        assert(finalPool[status["character" .. slot]], "Launch left the local unlocked random pool")
        local _, catalog = native.net_characters()
        assert(
            not catalog[tostring(status.character0)].tainted
                and catalog[tostring(status.character1)].tainted
        )
        if status.verified >= 60 then
            for index = 0, 1 do
                assert(native.rooms_with_player(index, function()
                    local actor = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(index)]))
                    assert(actor:GetPlayerType() == status["character" .. index])
                end))
            end
            finished = true
            report(
                "ACTORS_MATCH_RANDOM_RANGE roster=" .. status.character0 .. ":" .. status.character1
            )
            Isaac.DebugString("LAN_NETWORK PASS character selection menu")
        end
    end
    return status
end
return {
    done = function()
        return finished
    end,
    cleanup = function()
        _IsaacLanFrame, _IsaacLanMenuRender = frame, menu
    end,
}
