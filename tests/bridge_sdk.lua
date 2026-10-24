-- Exercise the same SDK file inside LAN and in an ordinary game without LAN.
local root = arg[1] or "."
local function modFixture()
    local mod = { callbacks = {} }
    function mod:AddCallback(id, fn)
        self.callbacks[fn] = id
    end
    function mod:RemoveCallback(_, fn)
        self.callbacks[fn] = nil
    end
    function mod:emit(id)
        local current = {}
        for fn, event in pairs(self.callbacks) do
            if event == id then
                current[#current + 1] = fn
            end
        end
        for _, fn in ipairs(current) do
            fn()
        end
    end
    function mod:render()
        self:emit(2)
    end
    return mod
end
local runtime = assert(loadfile(root .. "/tests/fixtures/api_runtime.lua"))()(root)
local host, guest = runtime.peer(0), runtime.peer(1)
host.env.ModCallbacks, guest.env.ModCallbacks = { MC_POST_RENDER = 2 }, { MC_POST_RENDER = 2 }
local hm, gm = modFixture(), modFixture()
local hs = host.env._IsaacLanModules["api/sdk"]
local gs = guest.env._IsaacLanModules["api/sdk"]
local h, g = hs.attach(hm, "example.sdk"), gs.attach(gm, "example.sdk")
assert(hs.attach(hm, "example.sdk") == h)
assert(not pcall(hs.attach, hm, "other"))
assert(not pcall(hs.attach, {}, "example.sdk"))
assert(hs.attach ~= nil and h.RegisterAction == nil and host.api.RegisterMod == nil)
local renders = 0
local cancel = g:OnLocalRender(function(view)
    renders = renders + 1
    assert(view.networked and view.ownerId == 2 and view.players[1] == runtime.actors[2])
    assert(guest.scope == 1 and g:IsLocalPlayer(view.players[1]))
    assert(not g:IsLocalPlayer(runtime.actors[1]))
end)
gm:render()
assert(renders == 0, "View preparation fell back to a single-player view")
guest.active = 0
assert(
    not g:IsReady() and g:View() == nil and not g:IsAuthority(),
    "A LAN ending or lobby fell back to solo while native players remained"
)
guest.networked = 0
assert(g:IsReady() and not g:View().networked and g:IsAuthority())
guest.active, guest.networked = 1, 1
host.bridge.commit()
guest.bridge.commit()
gm:render()
gm:render()
gm:render()
assert(renders == 3, "Render callback depended on incoming snapshot frequency")
local broken = 0
g:OnLocalRender(function()
    broken = broken + 1
    error("render error")
end)
gm:render()
gm:render()
assert(
    broken == 1 and guest.scope == nil and renders == 5,
    "Render error leaked scope or disabled another listener"
)
cancel()
cancel()
gm:render()
assert(renders == 5)
-- Requests target a stable owned body, never a sender-supplied owner number.
local secondBody = {
    hash = 33,
    GetPlayerType = function()
        return 20
    end,
}
for _, peer in ipairs({ host, guest }) do
    peer.actors[3] = secondBody
    peer.env._IsaacLan.api_actors = function()
        return {
            { index = 0, owner = 1, role = 1 },
            { index = 1, owner = 2, role = 1 },
            {
                index = 2,
                owner = 2,
                role = 2,
            },
        }
    end
    peer.bridge.commit()
end
local executions = 0
h:Action("cast", {
    execute = function(ctx)
        executions = executions + 1
        assert(ctx.player == secondBody and ctx.playerId == "p2:2" and ctx.ownerId == 2)
        return { status = "applied", code = "cast", data = { count = executions } }
    end,
})
local cast = g:Action("cast")
host.bridge.actions.poll()
guest.bridge.actions.poll()
assert(cast:IsAvailable())
local forbidden = cast:Request(nil, { player = runtime.actors[1] })
assert(forbidden.code == "player_not_local" and executions == 0)
local calls = 0
local request = cast:Request(nil, {
    player = secondBody,
    onResult = function(result)
        calls = calls + 1
        assert(result.status == "applied")
    end,
})
assert(request.status == "pending" and executions == 0)
host.bridge.actions.poll()
host.bridge.actions.step()
guest.bridge.actions.poll()
assert(request.status == "applied" and request.result.data.count == 1 and calls == 1)
local bytes = guest.sent[#guest.sent].bytes
host.inbox[#host.inbox + 1] = { sender = 1, bytes = bytes }
host.bridge.actions.step()
guest.bridge.actions.poll()
assert(executions == 1 and calls == 1)
-- A malicious peer cannot bypass local actor checks by forging the wire identity.
local codec = host.env._IsaacLanModules["api/codec"]
local forged = codec.decode(bytes)
forged.playerId = "p1:1"
forged.nonce = string.rep("f", 32)
forged.sequence = 1
forged.requestId = forged.nonce .. ":" .. forged.sequence
host.inbox[#host.inbox + 1] = { sender = 1, bytes = codec.encode(forged) }
host.bridge.actions.step()
local rejected = codec.decode(host.sent[#host.sent].bytes)
assert(rejected.code == "player_unavailable" and executions == 1)
-- Invalid business results become a definite unknown result, rather than timing out.
h:Action("bad-result", {
    execute = function()
        return { status = "applied", code = "bad", data = function() end }
    end,
})
host.bridge.actions.poll()
guest.bridge.actions.poll()
local bad = g:Action("bad-result"):Request()
host.bridge.actions.step()
guest.bridge.actions.poll()
assert(bad.status == "unknown" and bad.code == "invalid_result_data")
-- Version mismatch is scoped to this action, with a single synchronous notification.
local mismatch = g:Action("versioned", { version = 2 })
h:Action("versioned", {
    execute = function()
        error("wrong version executed")
    end,
})
host.bridge.actions.poll()
guest.bridge.actions.poll()
assert(mismatch:Request().code == "action_unavailable")
-- Closing resolves local waiting once; a late authority receipt cannot replay it.
h:Action("late", {
    execute = function()
        return { status = "applied", code = "late" }
    end,
})
host.bridge.actions.poll()
guest.bridge.actions.poll()
local lateCalls = 0
local late = g:Action("late"):Request(nil, {
    onResult = function()
        lateCalls = lateCalls + 1
    end,
})
g:Close()
g:Close()
assert(late.status == "unknown" and late.code == "integration_closed" and lateCalls == 1)
host.bridge.actions.step()
guest.bridge.actions.poll()
assert(lateCalls == 1 and next(gm.callbacks) == nil and not g:IsAttached())
-- The copied SDK needs no LAN modules or private globals for a normal solo game.
local env = setmetatable(
    { Isaac = guest.env.Isaac, Game = guest.env.Game, ModCallbacks = { MC_POST_RENDER = 2 } },
    { __index = _G }
)
env._G = env
local sdk = assert(loadfile(root .. "/src/bridge/api/sdk.lua", "t", env))()
local soloMod = modFixture()
local solo = sdk.attach(soloMod, "example.solo")
assert(sdk.attach(soloMod, "example.solo") == solo)
local soloRenders = 0
solo:OnLocalRender(function(view)
    assert(not view.networked and view.players[1] == runtime.actors[1])
    soloRenders = soloRenders + 1
end)
soloMod:render()
local soloCalls = 0
local effect = solo:Action("effect", {
    execute = function(ctx)
        soloCalls = soloCalls + 1
        assert(ctx.player == secondBody and not ctx.networked)
        return { status = "applied", code = "solo" }
    end,
})
assert(effect:Request(nil, { player = secondBody }).status == "applied" and soloCalls == 1)
assert(effect:Request({ unexpected = true }).code == "invalid_payload" and soloCalls == 1)
solo:Close()
soloMod:render()
assert(soloRenders == 1 and next(soloMod.callbacks) == nil)
assert(sdk.attach(soloMod, "example.solo") ~= solo)
-- Run the published example itself: a guest F6 submits once, the host grants
-- only that guest's coin, and the standalone copy uses the same input path.
for _, player in ipairs(runtime.actors) do
    player.coins = 5
    player.AddCoins = function(self, count)
        self.coins = self.coins + count
    end
    player.GetNumCoins = function(self)
        return self.coins
    end
end
local function example(environment, facade)
    local mod, triggered, text = modFixture(), false, {}
    environment.ModCallbacks = { MC_POST_RENDER = 2, MC_POST_UPDATE = 3 }
    environment.RegisterMod = function()
        return mod
    end
    environment.include = function(name)
        assert(name == "isaac_lan")
        return facade
    end
    environment.Keyboard = { KEY_F6 = 6 }
    environment.Input = {
        IsButtonTriggered = function()
            local value = triggered
            triggered = false
            return value
        end,
    }
    environment.Isaac.RenderText = function(value)
        text[#text + 1] = value
    end
    assert(loadfile(root .. "/examples/mod-api/main.lua", "t", environment))()
    return mod, function()
        triggered = true
        mod:emit(3)
    end, text
end
local _, hostPress = example(host.env, hs)
local exampleGuest, guestPress, guestText = example(guest.env, gs)
host.bridge.actions.poll()
guest.bridge.actions.poll()
guestPress()
assert(runtime.actors[2].coins == 5)
host.bridge.actions.step()
guest.bridge.actions.poll()
assert(runtime.actors[2].coins == 6 and runtime.actors[1].coins == 5)
exampleGuest:render()
assert(guestText[1] == "Local player 1: 6 coins")
hostPress()
host.bridge.actions.step()
host.bridge.actions.poll()
assert(runtime.actors[1].coins == 6)
local _, soloPress = example(env, sdk)
soloPress()
assert(runtime.actors[1].coins == 7)
print(
    "PASS API 2 SDK: render cadence, scope/error cleanup, owned bodies, results, versions, late replies, solo fallback"
)
