local api, native = assert(IsaacLAN), assert(_IsaacLan)
local wrapping = _IsaacLanModules["compat/mods/wrapping"]
local definition = {
    id = "isaac-lan.compat.emote-binds",
    adapterVersion = 1,
    modName = "Emote Binds",
    targets = { { workshopId = "3034946842" } },
}
local animations = {
    Happy = "Happy",
    Sad = "Sad",
    Jump = "Jump",
    Glitch = "Glitch",
    Death = "Death",
    Fall = "DeathTeleport",
    LightTravel = "LightTravel",
}
local buttonsPerController, explosionDelay = 32, 30
local lan, play, upstream
function definition.probe(target)
    local manager = target.mod.KeybindManager
    if type(manager) ~= "function" then
        return "pending", "keybinds_not_loaded"
    end
    target.settings = wrapping.find(manager, function(value)
        return type(value.GetSaveData) == "function"
    end)
    target.emotes = wrapping.find(manager, function(value)
        return type(value.Happy) == "function" and type(value.Sad) == "function"
    end)
    if not target.settings or not target.emotes then
        return "unsupported", "keybind_contract_mismatch"
    end
    return "ready"
end
local function buttonDown(button, device)
    return Input.IsButtonPressed(button, device) or Input.IsButtonTriggered(button, device)
end
local function boundInput(name, settings)
    local key = settings.KeyboardBinds[name]
    if key and key >= 0 and buttonDown(key, native.input_keyboard_device) then
        return true
    end
    local button = settings.ControllerBinds[name]
    if button and button >= 0 then
        -- Emote Binds stores the physical button in the low five bits.
        for device = 1, native.input_gamepad_count do
            if buttonDown(button % buttonsPerController, device) then
                return true
            end
        end
    end
    return false
end
-- The standard gestures are native extra animations even when only the sender has the Mod.
local function nativeGesture(player, name)
    local sound = ({
        Happy = SoundEffect.SOUND_THUMBSUP,
        Sad = SoundEffect.SOUND_THUMBS_DOWN,
        Death = SoundEffect.SOUND_ISAACDIES,
    })[name]
    if sound then
        SFXManager():Play(sound)
    end
    player:PlayExtraAnimation(animations[name])
end
local function execute(context, name)
    if upstream and type(upstream.emotes[name]) == "function" then
        local effect = upstream.emotes[name]
        local extra = upstream.settings:GetSaveData().ExtraData
        if name == "BloodExplode" and extra and extra.KillbindsEnabled then
            -- The Mod schedules Game:End for its single-player killbind. Keep the particles
            -- and their cleanup, then let co-op resolve the requesting player's death.
            local previous = extra.KillbindsEnabled
            extra.KillbindsEnabled = false
            local ok, reason = pcall(effect, context.player)
            extra.KillbindsEnabled = previous
            if not ok then
                error(reason, 0)
            end
            local started, playerId = Game():GetFrameCount(), context.playerId
            return context:Wait({
                poll = function()
                    if Game():GetFrameCount() - started < explosionDelay then
                        return
                    end
                    for i = 0, Game():GetNumPlayers() - 1 do
                        local player = Isaac.GetPlayer(i)
                        if lan:GetPlayerId(player) == playerId then
                            if not player:IsDead() then
                                player:Kill()
                            end
                            return { status = "applied", code = "played" }
                        end
                    end
                    return { status = "cancelled", code = "player_unavailable" }
                end,
            })
        else
            effect(context.player)
        end
    elseif animations[name] then
        nativeGesture(context.player, name)
    else
        return { status = "rejected", code = "host_mod_required" }
    end
    return { status = "applied", code = "played" }
end
function definition.authority(api)
    lan = api:Attach({ Name = "Isaac LAN Emote Binds authority" }, definition.id)
    play = lan:Action("play", {
        cooldownTicks = 1,
        validate = function(name)
            return type(name) == "string" and (animations[name] ~= nil or name == "BloodExplode")
        end,
        execute = execute,
    })
    return function()
        lan:Close()
        lan, play = nil, nil
    end
end
function definition.install(target)
    upstream = target
    local held = {}
    local reset = lan:On("StateReset", function()
        held = {}
    end)
    target.poll = function(player)
        if not lan:IsReady() or not lan:IsLocalPlayer(player) then
            return
        end
        local settings = target.settings:GetSaveData()
        for name in pairs(target.emotes) do
            local down = boundInput(name, settings)
            if down and not held[name] and play:IsAvailable() then
                play:Request(name, { player = player })
            end
            held[name] = down or nil
        end
    end
    return function()
        reset()
        upstream = nil
        target.poll, target.emotes, target.settings = nil, nil, nil
    end
end
function definition.dispatch(target, record, ...)
    if
        record.id == ModCallbacks.MC_POST_PLAYER_RENDER
        and record.original == target.mod.KeybindManager
        and lan
        and lan:IsActive()
    then
        local _, player = ...
        return target.poll(player)
    end
    return record.original(...)
end
api:RegisterAdapter(definition)
return definition
