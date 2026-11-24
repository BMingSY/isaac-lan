local root = assert(arg[1])
local runtime = dofile(root .. "/tests/fixtures/api_runtime.lua")(root)
local host, guest, other = runtime.peer(0), runtime.peer(1), runtime.peer(2)
for _, peer in pairs(runtime.peers) do
    peer.players, peer.connected = 3, 7
end
local function poll(peer)
    peer.bridge.actions.poll()
end
local function claims(first, second)
    assert(host.bridge.effects.forPeer(1) == first and host.bridge.effects.forPeer(2) == second)
end
local function heartbeat()
    host.now = host.now + 1001
    poll(host)
    poll(guest)
    poll(guest)
    poll(other)
    poll(host)
end
local variants = host.env.EffectVariant
local particle, explosion = variants.BLOOD_PARTICLE, variants.BLOOD_EXPLOSION
local classes = host.env._IsaacLanModules["sync/effect_classes"]
local exact, allParticles, poof =
    classes.mask(variants, particle, 99),
    classes.mask(variants, particle),
    classes.mask(variants, explosion, 2)
local integration = guest.api:Attach({}, "effect-test")
local second = guest.api:Attach({}, "other-observer")
local unused = integration:RequireEffectSync(variants.DOGMA_ORB)
integration:RequireEffectSync(particle, 11)
heartbeat()
claims(0, 0)
assert(#guest.sent == 0 and #other.sent == 0)
for _, args in ipairs({ {}, { -1 }, { 5.5 }, { particle, -1 }, { particle, false } }) do
    assert(not pcall(integration.RequireEffectSync, integration, table.unpack(args)))
end
local release = integration:RequireEffectSync(particle, 99)
poll(guest)
assert(#host.inbox == 1)
host.inbox = {} -- The first change never reached the host.
heartbeat()
claims(exact, 0)
local duplicate = second:RequireEffectSync(particle, 99)
local wildcard = integration:RequireEffectSync(particle)
poll(guest)
poll(host)
claims(allParticles, 0)
local owner = host.api:Attach({}, "host-observer")
owner:RequireEffectSync(explosion, 2)
claims(allParticles | poof, poof)
wildcard()
wildcard()
release()
unused()
poll(guest)
poll(host)
claims(exact | poof, poof)

local function inject(sender, changes)
    local info = host.env._IsaacLan.api_info()
    local message =
        { kind = "effect_sync", runId = info.runId, worldEpoch = info.worldEpoch, mask = exact }
    for k, v in pairs(changes) do
        message[k] = v
    end
    local codec = host.env._IsaacLanModules["api/codec"]
    host.inbox[#host.inbox + 1] = { sender = sender, bytes = codec.encode(message) }
end
for _, peer in pairs(runtime.peers) do
    peer.epoch = peer.epoch + 1
end
inject(2, { worldEpoch = host.epoch - 1 })
inject(2, { runId = "previous run" })
inject(2, { mask = classes.all + 1 })
inject(2, { mask = -1 })
inject(2, { mask = false })
inject(0, {})
poll(host)
claims(exact | poof, poof)
host.connected = 5
inject(1, {})
poll(host)
claims(poof, poof)
host.connected = 7
heartbeat()
claims(exact | poof, poof)
duplicate()
poll(guest)
host.inbox = {} -- Release to zero must also be repaired.
heartbeat()
claims(poof, poof)
local before = #guest.sent
heartbeat()
assert(#guest.sent == before and #other.sent == 0)
second:RequireEffectSync(particle)
poll(guest)
poll(host)
claims(allParticles | poof, poof)
for _, peer in pairs(runtime.peers) do
    peer.active = 0
    poll(peer)
end
claims(poof, poof)
for _, peer in pairs(runtime.peers) do
    peer.active, peer.runId = 1, "another-run"
end
heartbeat()
claims(allParticles | poof, poof)
second:Close()
integration:Close()
owner:Close()
poll(guest)
poll(host)
claims(0, 0)
assert(not pcall(integration.RequireEffectSync, integration, particle))
local standalone = dofile(root .. "/src/bridge/api/sdk.lua").attach({}, "solo")
local cancel = standalone:RequireEffectSync(particle)
cancel()
standalone:Close()
cancel()
print("Effect sync SDK scope, reference counting, peer negotiation and recovery passed")
