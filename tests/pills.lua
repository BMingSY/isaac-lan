local root = assert(arg[1])
local create = dofile(root .. "/src/bridge/sync/pills.lua")
local function state(effect, known)
    return string.rep(string.pack(">i4B", effect, known), 15)
end
local authority, replica = state(4, 1), state(0, 0)
local writes = 0
local host = create({
    pill_state = function()
        return authority
    end,
})
local guest = create({
    pill_state = function(value)
        replica, writes = value, writes + 1
        return true
    end,
})
guest.apply(host.capture())
assert(replica == authority)
guest.apply(host.capture())
assert(replica == authority)
-- A rewind can unidentify a pill and restore an older color assignment.
authority = state(9, 0)
guest.apply(host.capture())
assert(replica == authority)
-- Invalid data must be rejected before any native write.
for _, invalid in ipairs({ "", state(4096, 0), state(2, 2), authority .. "x" }) do
    local before = writes
    assert(not pcall(guest.apply, invalid) and writes == before)
end
print("PASS pill effect/identification changes, repeated views, rewind and invalid state")
