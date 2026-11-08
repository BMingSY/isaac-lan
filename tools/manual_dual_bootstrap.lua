-- Connect and select through the ordinary LAN commands, then relinquish the frame hook.
return function(config)
    local native, frame = assert(_IsaacLan), assert(_IsaacLanFrame)
    local menu = assert(_IsaacLanMenuRender)
    local Phase, json = native.net_phases(), require("json")
    local character = type(config.character) == "number" and config.character
        or PlayerType[config.character]
    local renders, linked, chosen, started = 0, false, false, false
    local menuReady = false
    local connectFrame = config.host and 300 or 360
    function _IsaacLanMenuRender(available, ...)
        menuReady = available
        return menu(available, ...)
    end
    local function finish(result)
        _IsaacLanFrame = frame
        _IsaacLanMenuRender = menu
        result.session, result.role = config.session, config.host and "host" or "client"
        local file = assert(io.open("./manual-dual-ready.json.tmp", "w"))
        file:write(json.encode(result))
        file:close()
        os.remove("./manual-dual-ready.json")
        assert(os.rename("./manual-dual-ready.json.tmp", "./manual-dual-ready.json"))
    end
    local function command(action, value)
        -- The bridge commands return nil on success and raise on rejection.
        local ok, message = pcall(_IsaacLanCommand, action, value)
        if not ok then
            finish({ error = tostring(message) })
        end
        return ok
    end
    function _IsaacLanFrame()
        local status = frame()
        renders = renders + 1
        if status.phase == Phase.failed or status.phase == Phase.waiting then
            finish({ error = status.error or "Connection failed" })
            return status
        end
        if not linked and menuReady and renders >= connectFrame then
            linked = true
            local address = tostring(config.port)
            if not config.host then
                address = "127.0.0.1:" .. address
            end
            command(config.host and "host" or "join", address)
        elseif linked and status.phase == Phase.lobby then
            if not chosen then
                local available = native.net_characters()
                local allowed = false
                for _, id in ipairs(available) do
                    allowed = allowed or id == character
                end
                if not allowed then
                    finish({
                        error = "Character "
                            .. tostring(character)
                            .. " is unavailable in this peer's save",
                        available = available,
                    })
                    return status
                end
                chosen = command("choose", character .. ":1")
                if not chosen then
                    return status
                end
            end
            if
                config.host
                and not started
                and status.players == 2
                and status.ready0 == 1
                and status.ready1 == 1
            then
                started = command(
                    "start",
                    "RANDOM:0:" .. status.choice0 .. ":" .. status.choice1 .. ":0:0"
                )
            end
        elseif
            status.phase == Phase.running
            and status.prepared
            and native.rooms_ready()
            and status.verified >= 2
            and (status.ping1 or -1) >= 0
        then
            local actual, matched = {}, false
            for index = 0, Game():GetNumPlayers() - 1 do
                local player = Isaac.GetPlayer(index)
                if player.ControllerIndex == status.slot + 1 then
                    local id = player:GetPlayerType()
                    actual[#actual + 1] = id
                    matched = matched or id == character
                end
            end
            finish({
                ready = matched,
                error = not matched and "Spawned character differs from selection" or nil,
                character = character,
                actual = actual,
                slot = status.slot,
                ping_ms = status.ping1,
                stage = Game():GetLevel():GetStage(),
            })
        end
        return status
    end
end
