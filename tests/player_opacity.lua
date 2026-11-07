local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/presentation/player_opacity.lua")
local function peer(slot, default)
    local info, values, calls = { slot = slot }, nil, 0
    local component = factory({
        default = default,
        info = function()
            return info
        end,
        apply = function(...)
            values = { ... }
            calls = calls + 1
            return true
        end,
    })
    local function expect(expected)
        assert(table.concat(values, ",") == expected, table.concat(values, ","))
    end
    return component, info, expect, function()
        return calls
    end
end
local host, info, expect, calls = peer(0, 50)
assert(calls() == 0, "Loading a presentation component changed native state")
host.step()
expect("100,50,50,50")
for _ = 1, 20 do
    host.step()
end
assert(calls() == 1, "Unchanged frames rewrote preferences")
assert(host.command("2p 25"):find("25%%"))
expect("100,25,50,50")
host.command("1p 80")
expect("80,25,50,50")
host.command("others 0")
expect("80,0,0,0")
host.command("4P 100")
expect("80,0,0,100")
host.command("  others   60 ")
expect("80,60,60,60")
local before = calls()
for _, args in ipairs({
    "",
    "help",
    "2p -1",
    "2p 101",
    "2p 0.5",
    "2p nan",
    "2p inf",
    "2p 1e1",
    "0p 50",
    "5p 50",
    "p2 50",
    "2p",
    "others",
    "reset 50",
    "2p 50 extra",
    "2p " .. string.rep("9", 300),
}) do
    assert(host.command(args):find("/opacity"))
    expect("80,60,60,60")
end
assert(calls() == before, "Invalid input or help mutated preferences")
-- A body/room/floor/run replacement does not change the owning LAN slot.
info.worldEpoch, info.runId = 5, "new-run"
host.step()
expect("80,60,60,60")
assert(calls() == before)
host.command("reset")
expect("100,50,50,50")
host.command("3p 10")
info.slot = -1
host.reset()
expect("100,100,100,100")
assert(host.command("others 40"):find("联机会话"))
info.slot = 2
host.step()
expect("50,50,100,50")
host.command("others 100")
expect("100,100,100,100")
host.reset()
expect("50,50,100,50")
-- Each process keeps its own defaults and overrides; 0 is a valid default.
local guest, _, expectGuest = peer(1, 0)
guest.step()
expectGuest("0,100,0,0")
guest.command("1p 35")
expectGuest("35,100,0,0")
expect("50,50,100,50")
guest.command("reset")
expectGuest("0,100,0,0")
print("PASS local player opacity defaults, commands, slots, repeated frames and session cleanup")
