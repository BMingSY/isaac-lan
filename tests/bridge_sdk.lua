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
local withView = guest.env._IsaacLan.api_with_local_view
guest.env._IsaacLan.api_with_local_view = function()
    return false
end
gm:render()
local unavailable, reason = g:WithLocalView(function()
    error("Uncommitted view")
end)
assert(unavailable == nil and reason == "view_not_ready" and renders == 0)
guest.env._IsaacLan.api_with_local_view = withView
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
local commands = guest.bridge.chatCommands
local function register(name, aliases)
    return g:RegisterChatCommand({
        name = name,
        aliases = aliases,
        description = "查看路线",
        execute = function() end,
    })
end
local remove = register("Route", { "path" })
assert(commands.byName.route == commands.byName.path)
for _, names in ipairs({
    { "other", { "free", "PATH" } },
    { "Other", { "OTHER" } },
    { "help" },
    { "console" },
    { "fb" },
    { "d6" },
    { "d10p" },
    { "3d6" },
    { "a/b" },
    { "space here" },
    { "other", { [2] = "gap" } },
}) do
    assert(not pcall(register, table.unpack(names)))
    assert(not commands.byName.other and not commands.byName.free)
end
remove()
local removeAgain = register("path", { "route" })
remove()
assert(commands.byName.path and commands.byName.route)
g:Close()
g:Close()
assert(not commands.byName.route and not commands.byName.path)
removeAgain()
assert(not pcall(register, "closed"))
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
local cancelCommand = solo:RegisterChatCommand({
    name = "route",
    description = "查看路线",
    execute = function()
        error("No LAN console in solo")
    end,
})
cancelCommand()
cancelCommand()
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
for _, player in ipairs({ runtime.actors[1], runtime.actors[2], secondBody }) do
    player.coins = 5
    player.AddCoins = function(self, count)
        self.coins = self.coins + count
    end
    player.GetNumCoins = function(self)
        return self.coins
    end
end
local function example(environment, facade, keyboardIndex)
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
        IsButtonPressed = function(key, index)
            return key == environment.Keyboard.KEY_F6 and index == keyboardIndex and triggered
        end,
    }
    environment.Isaac.RenderText = function(value)
        text[#text + 1] = value
    end
    assert(loadfile(root .. "/examples/mod-api/main.lua", "t", environment))()
    return mod,
        function()
            triggered = true
            mod:render()
            mod:render()
            triggered = false
            mod:render()
            mod:emit(3)
            mod:emit(3)
        end,
        text
end
local _, hostPress = example(host.env, hs, 0)
local exampleGuest, guestPress, guestText = example(guest.env, gs, -2)
host.bridge.actions.poll()
guest.bridge.actions.poll()
guestPress()
assert(runtime.actors[2].coins == 5)
host.bridge.actions.step()
guest.bridge.actions.poll()
assert(runtime.actors[2].coins == 6 and runtime.actors[1].coins == 5)
local beforeRender = #guestText
exampleGuest:render()
assert(guestText[beforeRender + 1] == "Local player 1: 6 coins")
hostPress()
host.bridge.actions.step()
host.bridge.actions.poll()
assert(runtime.actors[1].coins == 6)
local _, soloPress = example(env, sdk, 0)
soloPress()
assert(runtime.actors[1].coins == 7)
-- Cancelling a temporary UI or closing an action must release its captured
-- state while the integration itself remains alive for subsequent panels.
for _, temporary in ipairs({
    sdk.attach(modFixture(), "example.temporary"),
    hs.attach(modFixture(), "example.temporary"),
}) do
    local released = setmetatable({}, { __mode = "v" })
    local cancelled = {}
    for index = 1, 32 do
        local state = { value = index }
        released[index] = state
        local cancel = temporary:OnLocalRender(function()
            return state.value
        end)
        cancel()
        cancelled[#cancelled + 1] = cancel
        temporary:On("StateReset", function()
            return state.value
        end)()
        temporary
            :Action("temporary", {
                execute = function()
                    return { status = "applied", code = tostring(state.value) }
                end,
            })
            :Close()
    end
    collectgarbage("collect")
    collectgarbage("collect")
    assert(next(released) == nil, "Disposed SDK registrations retained captured Mod state")
    for _, cancel in ipairs(cancelled) do
        cancel()
    end
    temporary:Close()
end

print(
    "PASS API 2 SDK: render cadence, scope/error cleanup, owned bodies, results, versions, late replies, solo fallback"
)

-- External entries are registered before the lobby and can be applied on a
-- guest independently of having stepped or captured a previous snapshot.
do
    local function registry(ordinal)
        local peer = runtime.peer(ordinal)
        local native, declarations = peer.env._IsaacLan, {}
        function native.api_register_challenge(
            version,
            name,
            who,
            difficulty,
            players,
            contract,
            locked
        )
            local slot = 0x8000
            while declarations[slot] do
                slot = slot + 1
            end
            declarations[slot] =
                { version = version, players = players, contract = contract, locked = locked }
            return slot
        end
        function native.api_remove_challenge(slot)
            declarations[slot] = nil
        end
        function native.net_finish_challenge(slot)
            return peer.challenge == slot
        end
        return peer, declarations
    end
    local host, hostSpecs = registry(0)
    local guest, guestSpecs = registry(1)
    local h = host.api:Attach(modFixture(), "raid.fixture")
    local g = guest.api:Attach(modFixture(), "raid.fixture")
    local other = host.api:Attach(modFixture(), "other.mod")
    local remoteOther = guest.api:Attach(modFixture(), "other.mod")
    local ticks, state, resets, replica = 0, false, 0, nil
    local basic = { id = "raid", name = "Other", roomOptionsLocked = true }
    local def = {
        id = "raid",
        name = "Raid",
        players = 4,
        character = 0,
        step = function(ctx)
            ticks = ticks + 1
            assert(ctx.players[1] == runtime.actors[1] and ctx.players[2] == nil)
        end,
        capture = function()
            return state
        end,
        apply = function(value)
            replica = value
        end,
        reset = function()
            resets = resets + 1
        end,
    }
    local challenge = h:RegisterChallenge(def)
    local second = other:RegisterChallenge(basic)
    local guestOther = remoteOther:RegisterChallenge(basic)
    local localized = {}
    for key, value in pairs(def) do
        localized[key] = value
    end
    localized.name = "雷霆"
    local remote = g:RegisterChallenge(localized)
    local function slotOf(peer, handle)
        for slot, entry in pairs(peer.bridge.challenges.entries) do
            if entry.key == handle.id then
                return slot
            end
        end
    end
    local hs, gs = slotOf(host, challenge), slotOf(guest, remote)
    assert(hs ~= gs and remote.id == challenge.id and challenge.id == "raid.fixture:raid")
    assert(second.id == guestOther.id and second.id ~= challenge.id)
    assert(hostSpecs[hs].contract == guestSpecs[gs].contract and hostSpecs[hs].players == 4)
    assert(hostSpecs[hs].version == 1 and not hostSpecs[hs].locked and guestSpecs[hs].locked)
    assert(hostSpecs[hs].contract ~= guestSpecs[hs].contract)
    assert(not pcall(h.RegisterChallenge, h, def))
    assert(
        not pcall(h.RegisterChallenge, h, { id = "bad", name = "Bad", capture = function() end })
    )
    local coord = dofile(root .. "/src/bridge/runtime/challenges.lua")
    local function coordinator(peer, selected)
        local native = peer.env._IsaacLan
        native.net_challenges = function()
            return { [tostring(selected)] = { id = selected, version = 1 } }
        end
        local info = native.api_info
        native.api_info = function()
            local v = info()
            v.challengeVersion = 1
            return v
        end
        return coord({ native = native, external = peer.bridge.challenges.entries, routes = {} })
    end
    host.challenge, guest.challenge = hs, gs
    host.bridge.commit()
    guest.bridge.commit()
    assert(h:View().challengeId == challenge.id and g:View().challengeId == remote.id)
    local authority, client = coordinator(host, hs), coordinator(guest, gs)
    host.connected = 1
    authority.step()
    authority.step()
    assert(ticks == 1 and authority.snapshot()[3] == "F")
    state = { damage = 6, party = { 1, 2, 3, 4 } }
    local snapshot = authority.snapshot()
    assert(snapshot[1] == challenge.id)
    client.apply(snapshot)
    client.apply(snapshot)
    assert(replica.damage == 6 and replica.party[4] == 4)
    assert(not pcall(client.apply, { second.id, 1, snapshot[3] }))
    assert(challenge:Finish() and not second:Finish())
    local originalContract = hostSpecs[hs].contract
    local before = resets
    h:Close()
    challenge:Close()
    assert(not hostSpecs[hs] and not challenge:Finish() and resets == before + 1)
    assert(hostSpecs[slotOf(host, second)])
    local replacement = host.api:Attach(modFixture(), "raid.fixture")
    local locked = replacement:RegisterChallenge({
        id = "raid",
        name = "Raid",
        players = 4,
        character = 0,
        roomOptionsLocked = true,
    })
    assert(
        locked.id == challenge.id and hostSpecs[slotOf(host, locked)].contract ~= originalContract
    )
    local numeric = other:RegisterChallenge({ id = 1, name = "One" })
    assert(
        numeric.id == "other.mod:1"
            and not pcall(other.RegisterChallenge, other, { id = "1", name = "One" })
    )
    assert(not challenge:Finish(), "A recycled slot revived a closed handle")
    local minimal = coordinator(host, slotOf(host, numeric))
    host.challenge = slotOf(host, numeric)
    minimal.step()
    assert(minimal.snapshot() == false)
    minimal.apply(false)
end
