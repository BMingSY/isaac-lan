-- Embedded in the native extension. No Workshop registration or mod directory.
local native = assert(_IsaacLan)
local endpoint = _IsaacLanModules["core/endpoint"]
local Phase = native.net_phases()
local integration = assert(_IsaacLanModules)["api/public"]
local registry = _IsaacLanModules["compat/mods/registry"]
local game
local owner = { Name = "Isaac LAN native extension" }
local battleHud
local function callback(id, fn)
    Isaac.AddCallback(owner, id, fn)
end
callback(ModCallbacks.MC_POST_RENDER, function()
    if _IsaacLanState then
        _IsaacLanState.render()
    end
    if battleHud then
        battleHud.render()
    end
end)
function _IsaacLanMinimapRender()
    if battleHud then
        battleHud.renderMap()
    end
end
local keeper = _IsaacLanModules["compat/characters/keeper"](native, RoomType, PickupVariant)
local friendlyFire = _IsaacLanModules["compat/rules/friendly_fire"]({
    policy = _IsaacLanModules["compat/rules/pvp_damage"],
    attacks = _IsaacLanModules["compat/rules/pvp_attacks"],
    health = _IsaacLanModules["compat/rules/pvp_health"],
    items = _IsaacLanModules["compat/items/pvp"],
    native = native,
    player = Isaac.GetPlayer,
    entities = Isaac.GetRoomEntities,
    hash = GetPtrHash,
    ref = EntityRef,
    frame = function()
        return Game():GetFrameCount()
    end,
    paused = function()
        return Game():IsPaused()
    end,
    contact = _IsaacLanModules["core/contacts"],
    enums = {
        entity = EntityType,
        tear = TearFlags,
        damage = DamageFlag,
        collectible = CollectibleType,
        effect = EffectVariant,
    },
})
callback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source)
    return friendlyFire.damage(entity, amount, flags, source)
end)
callback(ModCallbacks.MC_USE_ITEM, function(_, item, _, player)
    friendlyFire.useItem(item, player)
end)
callback(ModCallbacks.MC_PRE_USE_ITEM, function(_, item, _, player)
    friendlyFire.beforeUseItem(item, player)
end)
local challenge, chat, feedback
local function lootAllocation()
    return _IsaacLanModules["compat/rules/loot_roll"]({
        native = native,
        player = Isaac.GetPlayer,
        config = Isaac.GetItemConfig,
        random = math.random,
        enums = { item = ItemType },
        chat = {
            output = function(...)
                return chat.output(...)
            end,
            roll = function(...)
                return chat.roll(...)
            end,
        },
    })
end
local allocation = lootAllocation()
local roomRules = _IsaacLanModules["runtime/room_rules"]({
    native = native,
    allocation = allocation,
    allow = function(key)
        return not challenge or challenge.allow(key)
    end,
    gather = _IsaacLanModules["compat/rules/special_rooms"]({
        native = native,
        game = Game,
        roomTypes = RoomType,
    }),
    charge = _IsaacLanModules["compat/rules/clear_charge"]({
        native = native,
        game = Game,
        party = allocation.party,
        scoped = allocation.scoped,
        enums = {
            shape = RoomShape,
            room = RoomType,
            trinket = TrinketType,
            collectible = CollectibleType,
            active = ActiveSlot,
            charge = ItemConfig,
        },
    }),
})
local function goalRoute(goal)
    return _IsaacLanModules["compat/routes/challenge_goal"]({
        game = Game,
        finish = native.net_finish_challenge,
        chestEnding = native.rooms_chest_ending,
        entities = Isaac.GetRoomEntities,
        spawn = Isaac.Spawn,
        zero = function()
            return Vector(0, 0)
        end,
        enums = {
            pickup = PickupVariant,
            entity = EntityType,
            grid = GridEntityType,
            effect = EffectVariant,
            room = RoomType,
            stage = LevelStage,
            stageType = StageType,
        },
    }, goal)
end
local battleRules = _IsaacLanModules["compat/challenges/battle_royale_rules"]
local battleEnums = {
    collectible = CollectibleType,
    stage = LevelStage,
    stageType = StageType,
    transition = RoomTransitionAnim,
    pool = ItemPoolType,
    entity = EntityType,
    pickup = PickupVariant,
    damage = DamageFlag,
    room = RoomType,
    shape = RoomShape,
    grid = GridEntityType,
    effect = EffectVariant,
}
local battleVisibility = _IsaacLanModules["sync/map_visibility"]({
    native = native,
    game = Game,
    fields = _IsaacLanModules["sync/fields"],
    levelFlags = LevelStateFlag,
})
local battle = _IsaacLanModules["compat/challenges/battle_royale"]({
    native = native,
    game = Game,
    player = Isaac.GetPlayer,
    spawn = Isaac.Spawn,
    vector = Vector,
    ref = EntityRef,
    random = math.random,
    rules = battleRules,
    enums = battleEnums,
    visibility = battleVisibility,
    rewards = _IsaacLanModules["compat/challenges/battle_royale_rewards"]({
        game = Game,
        entities = Isaac.GetRoomEntities,
        config = Isaac.GetItemConfig,
        spawn = Isaac.Spawn,
        vector = Vector,
        random = math.random,
        enums = battleEnums,
    }),
    map = _IsaacLanModules["compat/challenges/battle_royale_map"]({
        native = native,
        rules = battleRules,
        enums = battleEnums,
        random = math.random,
        entities = Isaac.GetRoomEntities,
        resources = _IsaacLanModules["compat/challenges/battle_royale_resources"]({
            native = native,
            rules = battleRules,
            enums = battleEnums,
            random = math.random,
        }),
    }),
})
challenge = _IsaacLanModules["runtime/challenges"]({
    native = native,
    game = Game,
    routes = {
        lamb = goalRoute("lamb"),
        mom = goalRoute("mom"),
        battle_royale = battle,
    },
    effects = {
        [battleRules.id] = battle,
        [1002] = _IsaacLanModules["compat/challenges/luck_game"]({
            allocation = lootAllocation(),
            native = native,
            game = Game,
            config = Isaac.GetItemConfig,
            spawn = Isaac.Spawn,
            zero = function()
                return Vector(0, 0)
            end,
            random = math.random,
            items = _IsaacLanModules["compat/items/glitched"](native),
            enums = {
                item = ItemType,
                trinket = TrinketType,
                collectible = CollectibleType,
                use = UseFlag,
                active = ActiveSlot,
                pill = PillEffect,
                pickup = PickupVariant,
                entity = EntityType,
                stageType = StageType,
            },
        }),
    },
    maps = { [battleRules.id] = battle },
})
_IsaacLanState.setChallenges(challenge)
battleHud = _IsaacLanModules["presentation/battle_royale"]({
    native = native,
    rules = battleRules,
    view = challenge.viewState,
    game = Game,
    sprite = Sprite,
    vector = Vector,
    color = Color,
    screen = Isaac.WorldToScreen,
    width = Isaac.GetScreenWidth,
    height = Isaac.GetScreenHeight,
})
function _IsaacLanAllowChallengeEvent(event)
    return challenge.allow(event)
end
function _IsaacLanMapView(begin, slot, record)
    challenge.mapView(begin, slot, record)
end
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
callback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, function()
    challenge.clearAward()
end)
function _IsaacLanCollectiblePickup(...)
    local accepted = challenge.collect(...)
    if accepted ~= nil then
        return accepted
    end
    return roomRules.collect(...)
end
function _IsaacLanPlayerRoomCleared(...)
    roomRules.cleared(...)
end
function _IsaacLanChallengeStep()
    challenge.step()
    roomRules.step()
    friendlyFire.step()
end
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
local continuedRun = false
local savedPlayers, savedOptions = 0, 0
local bindParty = _IsaacLanModules["runtime/party"](native, Isaac.GetPlayer)
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
chat = _IsaacLanModules["runtime/chat"]({
    limits = chatLimits,
    nonce = native.api_nonce,
    clock = Isaac.GetTime,
    send = native.chat_send,
    receive = native.chat_receive,
    execute = native.chat_execute,
    roll = native.chat_roll,
    dice = _IsaacLanModules["runtime/chat_dice"],
    teleport = _IsaacLanModules["runtime/teleport"]({
        native = native,
        game = Game,
        player = Isaac.GetPlayer,
        hash = GetPtrHash,
        vector = Vector,
        enums = {
            room = RoomType,
            shape = RoomShape,
            grid = GridRooms,
            collision = GridCollisionClass,
        },
        output = function(text, options)
            return chat.output(text, options)
        end,
    }),
    bot = bot.command,
    feedback = function(text)
        return feedback.submit(text, function(message)
            chat.output(message, { audience = "self" })
        end)
    end,
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
    game = Game,
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
-- Automation entry for lab fixtures; players use /lanbot in the LAN chat.
function _IsaacLanBotCommand(args)
    Isaac.ConsoleOutput(bot.command(args) .. "\n")
end
function _IsaacLanBotFrame(frame)
    bot.step(frame)
end
local registeredMods = _IsaacLanModules["compat/mods/observation"](registry, native.debug or debug)
local phaseNames = {}
for name, value in pairs(Phase) do
    phaseNames[value] = name
end
feedback = _IsaacLanModules["diagnostics/feedback"]({
    submit = native.feedback_submit,
    poll = native.feedback_poll,
    mods = function()
        local names = {}
        for _, mod in ipairs(registeredMods) do
            names[#names + 1] = mod.Name or ""
        end
        return names
    end,
    context = function()
        local info = native.api_info()
        return table.concat({
            "phase=" .. tostring(phaseNames[status.phase] or status.phase),
            "hosting=" .. tostring(status.hosting or 0),
            "players=" .. tostring(info.players),
            "slot=" .. tostring(info.slot),
            "ready=" .. tostring(info.ready),
        }, "\n")
    end,
})
function _IsaacLanViewCommitted()
    challenge.view()
    integration.commit()
end
function _IsaacLanActionStep()
    challenge.step()
    roomRules.step()
    friendlyFire.prepare()
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
    return _IsaacLanState.filterInput(assert(native.input_capture(-1)))
end
lifecycle = assert(_IsaacLanModules["runtime/session"])({
    canStart = function()
        return native.input_ready()
    end,
    fail = native.net_fail,
    start = function()
        assert(native.net_engine_start())
    end,
    bindPlayers = function(restoredOrder)
        bindParty(status, continuedRun, restoredOrder)
    end,
    enableRooms = function()
        assert(native.rooms_enable())
    end,
    gate = function()
        assert(
            native.net_gate(
                capture,
                apply,
                _IsaacLanState.captureTransfer,
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
        continuedRun = false
    end,
})
local function prepareCheckpoint()
    if lifecycle.prepare() then
        log("READY players=" .. status.players)
    end
end
callback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    friendlyFire.reset()
    roomRules.reset()
    game = Game()
    if native.diagnostics_begin then
        native.diagnostics_begin(
            game:GetSeeds():GetStartSeedString(),
            lifecycle.active() and (status.hosting == 1 and "host" or "client") or "solo",
            continued and 1 or 0
        )
    end
    challenge.reset()
    _IsaacLanState.reset()
    continuedRun = continued
    if lifecycle.gameStarted(continued) then
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
    prepareCheckpoint()
end)
callback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    friendlyFire.reset()
    roomRules.reset()
    challenge.reset()
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
        assert(native.net_configure_options(native.menu_room_options()), "无法载入房间规则")
        savedPlayers, savedOptions = native.net_saved_info()
    elseif action == "join" then
        bot.reset()
        chat.reset()
        chatUI.reset()
        lifecycle.close()
        assert(native.input_virtual())
        local ip, port = endpoint.parse(value)
        assert(ip, "无效的房主地址或端口")
        assert(native.net_join(ip, port, _IsaacLanFingerprint, modFingerprint()))
    elseif action == "challenge" then
        assert(native.net_challenge(assert(tonumber(value))), "无法选择联机挑战")
    elseif action == "room_options" then
        assert(native.net_configure_options(assert(tonumber(value))), "无法修改房间规则")
        assert(
            native.menu_room_options_save(tonumber(value)),
            "规则已应用，但本机保存失败"
        )
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
        savedPlayers, savedOptions = native.net_saved_info()
    elseif action == "resume" then
        assert(
            native.net_resume(),
            "无法续玩：请检查人数、加入顺序、游戏版本和存档是否一致"
        )
    elseif action == "control" then
        assert(native.net_command(tonumber(value)), "当前玩家没有执行此操作的权限")
    elseif action == "reconnect" then
        assert(native.net_reconnect(), "当前无法重连游戏")
    elseif action == "leave" then
        if lifecycle.active() then
            assert(native.net_leave(), "当前无法离开游戏")
        else
            lifecycle.close()
        end
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
        savedPlayers, savedOptions = native.net_saved_info()
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
    feedback.poll()
    bot.poll()
    if status.phase == Phase.running then
        lifecycle.launch()
    end
    status.prepared = lifecycle.ready()
    chatUI.step(status)
    status.savedPlayers = savedPlayers
    status.savedOptions = savedOptions
    if lifecycle.ready() then
        status.positions = native.rooms_positions()
    end
    return status
end
function _IsaacLanStatus()
    return status
end
log("EMBEDDED_BRIDGE ready")
