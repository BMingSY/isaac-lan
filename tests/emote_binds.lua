local root = arg[1] or "."
local runtime = assert(loadfile(root .. "/tests/fixtures/api_runtime.lua"))()(root)
local host, guest = runtime.peer(0), runtime.peer(1)
local render = 1
local function install(peer, keyboard, firstPad)
    local env = peer.env
    env.ModCallbacks = { MC_POST_PLAYER_RENDER = render }
    env._IsaacLan.input_keyboard_device, env._IsaacLan.input_gamepad_count = keyboard, 4
    env.Input = {
        IsButtonPressed = function(key, device)
            return device == keyboard and key == peer.key
                or device == firstPad and key == peer.button
        end,
        IsButtonTriggered = function()
            return false
        end,
    }
    local bindings = {
        KeyboardBinds = { Happy = 80, BloodExplode = 81 },
        ControllerBinds = { Sad = 34 },
        ExtraData = { KillbindsEnabled = true },
    }
    local settings = {
        GetSaveData = function()
            return bindings
        end,
    }
    local emotes = {
        Happy = function(p)
            peer.happy = p
        end,
        BloodExplode = function(player)
            assert(not bindings.ExtraData.KillbindsEnabled, "Party-ending callback was scheduled")
            peer.explosion = player
        end,
        Sad = function(p)
            peer.sad = p
        end,
    }
    local mod = {
        Name = "Emote Binds",
        KeybindManager = function(_, player)
            peer.solo = player
            return settings:GetSaveData(), emotes
        end,
        AddCallback = function(_, id, fn)
            assert(id == render)
            peer.render = fn
        end,
        AddPriorityCallback = function() end,
        RemoveCallback = function() end,
    }
    peer.modInfo = { directory = "emote-binds", workshopId = "3034946842", sourceHash = "workshop" }
    local adapter = assert(loadfile(root .. "/src/bridge/compat/mods/emote_binds.lua", "t", env))()
    peer.bridge.registry.observeMod(mod, "emote-binds-source")
    mod:AddCallback(render, mod.KeybindManager)
    assert(peer.bridge.registry.status()[1].state == "active")
    peer.bridge.commit()
    return adapter.id, mod, bindings
end
local id, hostMod, hostBinds = install(host, -2, 4)
local _, guestMod, guestBinds = install(guest, 0, 1)
host.bridge.actions.poll()
guest.bridge.actions.poll()
local owner, teammate = runtime.actors[2], runtime.actors[1]
guestBinds.KeyboardBinds.Happy = 90
guest.key = 90
local sent = #guest.sent
guest.render(guestMod, teammate)
assert(#guest.sent == sent)
guest.render(guestMod, owner)
guest.render(guestMod, owner)
assert(#guest.sent == sent + 1 and not guest.happy and not host.happy)
host.bridge.actions.step()
assert(host.happy == owner and not guest.solo)
guest.bridge.actions.poll()
host.tick = host.tick + 1
host.button = 2
host.render(hostMod, teammate)
host.bridge.actions.step()
assert(host.sad == teammate)
-- A held key crosses simulation frames without replaying. Release rearms it.
guest.tick, host.tick = guest.tick + 1, host.tick + 1
sent = #guest.sent
guest.render(guestMod, owner)
assert(#guest.sent == sent)
guest.key = nil
guest.render(guestMod, owner)
guest.key = 81
function owner:IsDead()
    return false
end
function owner:Kill()
    assert(host.scope == 1)
    host.killed = self
end
guest.render(guestMod, owner)
host.bridge.actions.step()
assert(host.explosion == owner and hostBinds.ExtraData.KillbindsEnabled and not host.killed)
host.tick = host.tick + 29
host.bridge.actions.commit()
assert(not host.killed)
host.tick = host.tick + 1
host.bridge.actions.commit()
assert(host.killed == owner)
assert(guest.api:SetAdapterEnabled(id, false))
guest.render(guestMod, owner)
assert(guest.solo == owner)
assert(guest.api:SetAdapterEnabled(id, true))
guest.solo, guest.active = nil, 0
guest.render(guestMod, owner)
assert(guest.solo == owner)
-- A vanilla host can play a guest's standard gesture in the owner's room.
host, guest = runtime.peer(0), runtime.peer(1)
host.env.SoundEffect = { SOUND_THUMBSUP = 5 }
host.env.SFXManager = function()
    return {
        Play = function(_, sound)
            assert(sound == 5)
            host.sound = sound
        end,
    }
end
function owner:PlayExtraAnimation(name)
    assert(host.scope == 1)
    host.gesture = name
end
assert(loadfile(root .. "/src/bridge/compat/mods/emote_binds.lua", "t", host.env))()
host.bridge.commit()
_, guestMod = install(guest, -2, 4)
host.bridge.actions.poll()
guest.bridge.actions.poll()
guest.key = 80
guest.render(guestMod, owner)
host.bridge.actions.step()
assert(host.gesture == "Happy" and host.sound == 5)
print(
    "PASS Emote Binds keyboard/gamepad ownership, held keys, scoped kill, vanilla host and cleanup"
)
