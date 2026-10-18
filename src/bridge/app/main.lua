-- Embedded in the native extension. No Workshop registration or mod directory.
local native = assert(_IsaacLan)
local Phase = native.net_phases()
local integration = assert(_IsaacLanModules)["api/public"]
local registry = _IsaacLanModules["compat/mods/registry"]
local game
local owner = { Name = "Isaac LAN native extension" }
local function callback(id, fn)
    Isaac.AddCallback(owner, id, fn)
end
local keeper = _IsaacLanModules["compat/characters/keeper"](native, RoomType, PickupVariant)
local challenge = _IsaacLanModules["runtime/challenges"]({
    native = native,
    game = Game,
    routes = {
        lamb = _IsaacLanModules["compat/routes/challenge_lamb"]({
            game = Game,
            finish = native.net_finish_challenge,
            chestEnding = native.rooms_chest_ending,
            entities = Isaac.GetRoomEntities,
            enums = {
                pickup = PickupVariant,
                entity = EntityType,
                grid = GridEntityType,
                effect = EffectVariant,
                stage = LevelStage,
                stageType = StageType,
                room = RoomType,
            },
        }),
    },
    maps = {},
})
callback(ModCallbacks.MC_POST_PICKUP_INIT, function(_, pickup)
    challenge.pickup(pickup)
end)
callback(ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup)
    challenge.pickup(pickup)
end)
callback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup, collider)
    keeper.collide(pickup, collider)
    return challenge.collide(pickup, collider)
end)
callback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    challenge.level()
end)
function _IsaacLanCanEnterRoom(...)
    return challenge.canEnter(...)
end
local restart = _IsaacLanModules["runtime/restart"]({
    running = Phase.running,
    now = function()
        return native.api_info().nowMs
    end,
    send = native.net_lifecycle_send,
    receive = native.net_lifecycle_receive,
    request = native.net_restart_request,
    restart = function()
        return native.net_restart(Seeds.Seed2String(Random()):gsub("%s", ""))
    end,
})
local status, tick = {}, 0
local lifecycle
local players = {}
local continuedRun = false
local savedPlayers = 0
local function refreshPlayers(restoredOrder)
    local heads = restoredOrder and native.rooms_heads(1) or native.rooms_heads()
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
local observation = _IsaacLanModules["lanbot/observe"](
    native,
    integration,
    _IsaacLanModules["lanbot/navigation"],
    _IsaacLanModules["lanbot/terrain"],
    _IsaacLanModules["lanbot/items"],
    _IsaacLanState.actorPose,
    function()
        return status
    end
)
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
local chatLimits = native.chat_limits()
local emotes = native.emote_count()
local chat = _IsaacLanModules["runtime/chat"]({
    limits = chatLimits,
    nonce = native.api_nonce,
    clock = Isaac.GetTime,
    send = native.chat_send,
    receive = native.chat_receive,
    execute = native.chat_execute,
    roll = native.chat_roll,
    bot = bot.command,
    emotes = emotes,
    info = function()
        local info = native.api_info()
        info.hosting = status.hosting or 0
        return info
    end,
    context = function(slot)
        return native.rooms_positions()[tostring(slot)]
    end,
}, _IsaacLanModules["runtime/chat_wire"])
local chatUI = _IsaacLanModules["presentation/chat"]({
    native = native,
    options = Options,
    chat = chat,
    phase = Phase,
    limits = chatLimits,
    clock = Isaac.GetTime,
}, _IsaacLanModules["presentation/chat_layout"])
function _IsaacLanChatRender()
    chatUI.render(status)
end
function _IsaacLanChatSubmit(text)
    return chat.submit(text)
end
function _IsaacLanChatOutput(text, options)
    return chat.output(text, options)
end
function _IsaacLanChatMessages()
    return chat.messages
end
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
local registeredMods = _IsaacLanModules["compat/mods/observation"](registry, native.debug or debug)
function _IsaacLanViewCommitted()
    integration.commit()
end
function _IsaacLanActionStep()
    challenge.step()
    if native.api_info().ready == 1 then
        _IsaacLanModules["compat/mods/goodtrip/authority"].observe()
    end
    integration.actions.step()
    chat.step()
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
lifecycle = assert(_IsaacLanModules["runtime/session"])({
    start = function()
        assert(native.net_engine_start())
    end,
    enableRooms = function()
        assert(native.rooms_enable())
    end,
    gate = function()
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
    end,
    restoreRooms = function()
        assert(native.net_restore_rooms())
    end,
    close = function(preserve)
        if preserve == nil then
            native.net_close()
        else
            native.net_close(preserve)
        end
        players = {}
        continuedRun = false
    end,
})
local function prepareCheckpoint()
    if lifecycle.prepare() then
        log("READY players=" .. status.players)
    end
end
callback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    game = Game()
    if native.diagnostics_begin then
        native.diagnostics_begin(
            game:GetSeeds():GetStartSeedString(),
            lifecycle.active() and (status.hosting == 1 and "host" or "client") or "solo",
            continued and 1 or 0
        )
    end
    _IsaacLanState.reset()
    continuedRun = continued
    if lifecycle.gameStarted() then
        if continued then
            -- Native continue detaches unavailable physical controllers. Bind
            -- the restored heads before its first update can pause for them.
            -- Native Continue may attach a saved controller to a different
            -- physical device or keyboard. Use restored roster order until
            -- assigning LAN controllers; physical IDs cannot identify slots yet.
            local heads = refreshPlayers(true)
            for slot = 0, status.players - 1 do
                assert(native.input_assign(heads[tostring(slot)], slot + 1))
            end
        end
        math.randomseed(game:GetSeeds():GetStartSeed())
        log("GAME_STARTED " .. game:GetSeeds():GetStartSeedString())
        if status.firstTick > 0 then
            prepareCheckpoint()
        end
    end
end)
callback(ModCallbacks.MC_POST_UPDATE, function()
    keeper.update()
    if not lifecycle.initializing() or game:GetRoom():GetFrameCount() < 10 then
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
    prepareCheckpoint()
end)
callback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    bot.reset()
    integration.reset("session_ended")
    if lifecycle.active() then
        -- The native exit tail still owns save/progress guards, including
        -- cancellation before the bridge has finished preparing.
        lifecycle.close(1)
    end
    if native.diagnostics_end then
        native.diagnostics_end()
    end
end)
function _IsaacLanCommand(action, value)
    if action == "host" then
        bot.reset()
        chat.reset()
        chatUI.reset()
        lifecycle.close()
        assert(native.input_virtual())
        assert(native.net_host(tonumber(value), _IsaacLanFingerprint, modFingerprint()))
        savedPlayers = native.net_saved_info()
    elseif action == "join" then
        bot.reset()
        chat.reset()
        chatUI.reset()
        lifecycle.close()
        assert(native.input_virtual())
        local ip, port = value:match("^([a-zA-Z0-9%.%-]+):(%d+)$")
        assert(ip and native.net_join(ip, tonumber(port), _IsaacLanFingerprint, modFingerprint()))
    elseif action == "challenge" then
        assert(native.net_challenge(assert(tonumber(value))), "无法选择联机挑战")
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
    elseif action == "retry_save" then
        assert(native.net_retry_save(), "联机存档保存失败，请重试保存")
        savedPlayers = native.net_saved_info()
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
        assert(not lifecycle.ready(), "A running game must exit through the shared pause menu")
        lifecycle.close()
    end
end
local chatSession = false
function _IsaacLanFrame()
    local previousPhase = status.phase
    status = native.net_poll()
    if status.phase == Phase.lobby and previousPhase ~= Phase.lobby then
        savedPlayers = native.net_saved_info()
    end
    if
        status.phase == Phase.lobby
        or status.phase == Phase.running
        or status.phase == Phase.waiting
    then
        chatSession = true
    elseif
        chatSession
        and (
            status.phase == Phase.idle
            or status.phase == Phase.closed
            or status.phase == Phase.failed
        )
    then
        chatSession = false
        chat.reset()
        chatUI.reset()
    end
    restart.poll(status)
    integration.poll()
    chat.poll()
    bot.poll()
    if status.phase == Phase.running then
        lifecycle.launch()
    end
    status.prepared = lifecycle.ready()
    chatUI.step(status)
    status.savedPlayers = savedPlayers
    if lifecycle.ready() then
        status.positions = native.rooms_positions()
    end
    return status
end
function _IsaacLanStatus()
    return status
end
log("EMBEDDED_BRIDGE ready")
