-- Embedded in the native extension. No Workshop registration or mod directory.
local native = assert(_IsaacLan)
local integration = assert(_IsaacLanModules)["api/public"]
local registry = _IsaacLanModules["compat/registry"]
local game
local owner = { Name = "Isaac LAN native extension" }
local function callback(id, fn)
    Isaac.AddCallback(owner, id, fn)
end
local status, started, prepared, engineStarted, tick = {}, false, false, false, 0
local players = {}
local continuedRun = false
local savedPlayers = 0
local function refreshPlayers()
    local heads = native.rooms_heads()
    players = {}
    for slot = 0, status.players - 1 do
        if heads[tostring(slot)] then
            players[#players + 1] = Isaac.GetPlayer(heads[tostring(slot)])
        else
            assert(
                (native.rooms_connected() & (1 << slot)) == 0,
                "联机角色数量与房间人数不一致"
            )
        end
    end
    return heads
end
local function log(s)
    Isaac.DebugString("ISAAC_LAN " .. s)
end
local observation =
    _IsaacLanModules["lanbot/observe"](native, integration, _IsaacLanModules["lanbot/navigation"])
local bot = _IsaacLanModules["lanbot"]({
    info = native.api_info,
    input = function(active, buttons)
        assert(native.input_bot(active and 1 or 0, buttons))
    end,
    observe = observation.read,
    clock = Isaac.GetTime,
    log = function(message)
        log("LANBOT " .. message)
    end,
}, _IsaacLanModules)
function _IsaacLanBotCommand(args)
    Isaac.ConsoleOutput(bot.command(args) .. "\n")
end
callback(ModCallbacks.MC_EXECUTE_CMD, function(_, command, args)
    if command == "lanbot" then
        _IsaacLanBotCommand(args)
    end
    -- MC_EXECUTE_CMD must return nil, including for unhandled commands.
end)
function _IsaacLanBotFrame(frame)
    bot.step(frame)
end
local registeredMods = {}
local registerMod = RegisterMod
function RegisterMod(name, version)
    local mod = registerMod(name, version)
    registeredMods[#registeredMods + 1] = mod
    local caller = debug.getinfo(2, "S")
    registry.observeMod(mod, caller and caller.source or "")
    return mod
end
local originalRequire = require
function require(name)
    local caller = debug.getinfo(2, "S")
    local value = originalRequire(name)
    registry.observeRequire(caller and caller.source or "", name, value)
    return value
end
function _IsaacLanViewCommitted()
    integration.commit()
end
function _IsaacLanActionStep()
    if native.api_info().ready == 1 then
        _IsaacLanModules["compat/goodtrip/authority"].observe()
    end
    integration.actions.step()
end
local function modFingerprint()
    local parts = {}
    for _, mod in ipairs(registeredMods) do
        local name = mod.Name or ""
        parts[#parts + 1] = string.pack(">I4", #name) .. name
    end
    local result = native.configuration_hash(table.concat(parts))
    log("MOD_FINGERPRINT " .. (result ~= "" and result or "unknown"))
    return result
end
local function apply(frame)
    tick = frame
end
local function capture()
    return assert(native.input_capture(-1))
end
local function prepareCheckpoint()
    assert(native.rooms_enable())
    assert(
        native.net_gate(
            capture,
            apply,
            _IsaacLanState.capture,
            _IsaacLanState.apply,
            _IsaacLanState.present,
            _IsaacLanState.beginFloor
        )
    )
    assert(native.net_restore_rooms())
    prepared = true
    log("READY players=" .. status.players)
end
callback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    game = Game()
    _IsaacLanState.reset()
    continuedRun = continued
    if started then
        engineStarted = true
        if continued then
            -- Native continue detaches unavailable physical controllers. Bind
            -- the restored heads before its first update can pause for them.
            local heads = refreshPlayers()
            for slot = 0, status.players - 1 do
                assert(native.input_assign(heads[tostring(slot)], slot + 1))
            end
        end
        math.randomseed(game:GetSeeds():GetStartSeed())
        log("GAME_STARTED " .. game:GetSeeds():GetStartSeedString())
        if status.firstTick > 0 and not prepared then
            prepareCheckpoint()
        end
    end
end)
callback(ModCallbacks.MC_POST_UPDATE, function()
    if not engineStarted or prepared or game:GetRoom():GetFrameCount() < 10 then
        return
    end
    if continuedRun then
        local heads = refreshPlayers()
        for slot = 0, status.players - 1 do
            assert(native.input_assign(heads[tostring(slot)], slot + 1))
        end
    else
        players = { Isaac.GetPlayer(0) }
        assert(native.input_assign(0, 1))
        for slot = 1, status.players - 1 do
            local index = assert(native.players_spawn(status["character" .. slot], slot + 1))
            players[#players + 1] = Isaac.GetPlayer(index)
        end
    end
    assert(native.rooms_enable())
    assert(
        native.net_gate(
            capture,
            apply,
            _IsaacLanState.capture,
            _IsaacLanState.apply,
            _IsaacLanState.present,
            _IsaacLanState.beginFloor
        )
    )
    assert(native.net_restore_rooms())
    prepared = true
    log("READY players=" .. status.players)
end)
callback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    bot.reset()
    integration.reset("session_ended")
    if prepared then
        native.net_close(1)
        started, prepared, engineStarted = false, false, false
        players = {}
    end
end)
function _IsaacLanCommand(action, value)
    if action == "host" then
        bot.reset()
        native.net_close()
        started, prepared = false, false
        assert(native.input_virtual())
        assert(native.net_host(tonumber(value), _IsaacLanFingerprint, modFingerprint()))
        savedPlayers = native.net_saved_info()
    elseif action == "join" then
        bot.reset()
        native.net_close()
        started, prepared = false, false
        assert(native.input_virtual())
        local ip, port = value:match("^([%d%.]+):(%d+)$")
        assert(ip and native.net_join(ip, tonumber(port), _IsaacLanFingerprint, modFingerprint()))
    elseif action == "start" then
        local seed, difficulty, a, b, c, d = value:match("^([%w]+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
        if seed == "RANDOM" then
            seed = Seeds.Seed2String(Random()):gsub("%s", "")
        end
        assert(
            seed and #seed == 8 and Seeds.String2Seed(seed:sub(1, 4) .. " " .. seed:sub(5)) ~= 0,
            "种子无效，请输入八位有效种子或留空随机生成"
        )
        assert(
            native.net_start(
                seed,
                tonumber(difficulty),
                tonumber(a),
                tonumber(b),
                tonumber(c),
                tonumber(d)
            )
        )
    elseif action == "resume" then
        assert(
            native.net_resume(),
            "无法续玩：请检查人数、加入顺序、游戏版本和存档是否一致"
        )
    elseif action == "control" then
        assert(native.net_command(tonumber(value)), "当前玩家没有执行此操作的权限")
    elseif action == "choose" then
        local character, ready = value:match("^(%d+):([01])$")
        assert(character and native.net_choose(tonumber(character), tonumber(ready)))
    elseif action == "close" then
        assert(not prepared, "A running game must exit through the shared pause menu")
        native.net_close()
        started = false
    end
end
function _IsaacLanFrame()
    status = native.net_poll()
    integration.poll()
    bot.poll()
    if status.phase == 3 and not started then
        started = true
        assert(native.net_engine_start())
    end
    status.prepared = prepared
    status.savedPlayers = savedPlayers
    if prepared then
        status.positions = native.rooms_positions()
    end
    return status
end
function _IsaacLanStatus()
    return status
end
log("EMBEDDED_BRIDGE ready")
