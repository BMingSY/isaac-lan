local root = assert(arg[1])
local runtime = dofile(root .. "/tests/fixtures/api_runtime.lua")(root)
local host, guest = runtime.peer(0), runtime.peer(1)
local h, g = host.api:Attach({}, "skin"), guest.api:Attach({}, "skin")
local other = guest.api:Attach({}, "backup")
local function expect(peer, hearts, active, pocket, render)
    local v = peer.hudFilters or { 0, 0, 0, false }
    assert(v[1] == hearts and v[2] == active and v[3] == pocket and v[4] == render)
end
local function invalid(fn, message)
    local ok, reason = pcall(fn)
    assert(not ok and tostring(reason):find(message, 1, true))
end
local release = g:HideHUD("hearts", "teammates")
local overlap = other:HideHUD("hearts", "all")
local own = g:HideHUD("activeItem", "local")
g:HideHUD("pocketItems", "teammates")
expect(guest, 3, 1, 2, false)
expect(host, 0, 0, 0, false)
release()
release()
expect(guest, 3, 1, 2, false)
overlap()
own()
expect(guest, 0, 0, 2, false)
invalid(function()
    h:HideHUD("everything", "all")
end, "invalid_hud_component")
invalid(function()
    h:OnHUDHearts("team", function() end)
end, "invalid_hud_audience")

local unknown, ghost = 0, false
guest.env.LevelCurse = { CURSE_OF_THE_UNKNOWN = 64 }
local game = guest.env.Game
guest.env.Game = function()
    local value = game()
    function value:GetLevel()
        return {
            GetCurses = function()
                return unknown
            end,
        }
    end
    return value
end
local twin = { hash = 23, type = 20, GetPlayerType = runtime.actors[2].GetPlayerType }
guest.actors[3] = twin
function guest.env._IsaacLan.api_actors()
    return {
        { owner = 1, index = 0, role = 1 },
        { owner = 2, index = 1, role = 1 },
        { owner = 2, index = 2, role = 2 },
    }
end
for _, actor in ipairs(guest.actors) do
    for index, field in ipairs({
        "Hearts",
        "MaxHearts",
        "SoulHearts",
        "BlackHearts",
        "BoneHearts",
        "BrokenHearts",
        "RottenHearts",
        "EternalHearts",
        "GoldenHearts",
    }) do
        actor["Get" .. field] = function()
            assert(unknown == 0 and not ghost, "Hidden health was read")
            return index
        end
    end
    function actor:IsCoopGhost()
        return ghost
    end
end
local draw = guest.env._IsaacLanRenderHearts
local faulty = 0
g:OnHUDHearts("teammates", function(panel)
    faulty = faulty + 1
    panel.health.red = 999
    error("faulty skin")
end)
local first, rest, expectedLocal = 0, 0, false
local cancel = g:OnHUDHearts("all", function(panel)
    assert(panel.x == 17 and panel.y == 22 and panel.scale == 0.75)
    assert(guest.scope == 1 and panel.isLocal == expectedLocal)
    if unknown ~= 0 or ghost then
        assert(panel.health == nil and panel.unknown == (unknown ~= 0) and panel.isGhost == ghost)
    else
        assert(
            panel.health.red == 1
                and panel.health.maxRed == 2
                and panel.health.blackMask == 4
                and panel.health.golden == 9
        )
    end
    first = first + 1
    return true
end)
other:OnHUDHearts("local", function(panel)
    rest = rest + 1
    assert(panel.playerId == "p2:2" and panel.ownerId == 2 and panel.playerType == 20)
end)
assert(not draw(0, 17, 22, 0.75))
guest.bridge.commit()
g:WithLocalView(function()
    local players = g:GetHUDPlayers()
    assert(#players == 3 and players[3].playerId == "p2:2" and guest.scope == 1)
    assert(players[1].ownerId == 1 and not players[1].isLocal and players[2].isLocal)
    assert(players[1].x == nil and players[3].scale == nil)
    players[1].health.red = 20
    assert(g:GetHUDPlayers()[1].health.red == 1)
    guest.connected = 2
    assert(#g:GetHUDPlayers() == 2)
    guest.connected = nil
end)
assert(draw(0, 17, 22, 0.75) and faulty == 1 and #guest.logs == 1)
unknown = 64
assert(g:GetHUDPlayers()[1].health == nil)
assert(draw(0, 17, 22, 0.75) and faulty == 1)
unknown, ghost, expectedLocal = 0, true, true
assert(draw(2, 17, 22, 0.75) and rest == 0 and first == 3 and guest.scope == nil)
cancel()
assert(not draw(2, 17, 22, 0.75) and rest == 1)
guest.bridge.reset("world_rebuilt")
assert(#g:GetHUDPlayers() == 0)
assert(not draw(2, 17, 22, 0.75) and rest == 1)
guest.epoch = 1
guest.bridge.commit()
assert(not draw(2, 17, 22, 0.75) and rest == 2)
-- A callback may close its handle mid-dispatch. Its successor must still run.
local closing = guest.api:Attach({}, "closing")
local count = 0
closing:OnHUDHearts("teammates", function()
    closing:Close()
end)
closing:OnHUDHearts("teammates", function()
    error("released callback ran")
end)
other:OnHUDHearts("all", function()
    count = count + 1
    return true
end)
assert(draw(0, 17, 22, 0.75) and count == 1 and #guest.logs == 1)
g:Close()
expect(guest, 0, 0, 0, true)
other:Close()
expect(guest, 0, 0, 0, false)

local modA, modB = host.api:Attach({}, "b"), host.api:Attach({}, "a")
local selection, values = 1, { "Default", "Hide", "Draw" }
local function def(fn)
    return { id = "hearts", name = "Team hearts", choices = values, onChange = fn }
end
local settings = host.bridge.menuSettings.entries
local cancelSetting = modA:RegisterMenuSetting(def(function(i)
    selection = i
end))
modB:RegisterMenuSetting(def(function()
    error("failed setting")
end))
invalid(function()
    modA:RegisterMenuSetting(def(function() end))
end, "duplicate_menu_setting")
assert(#settings == 2 and settings[1].key == "a:hearts" and settings[2].key == "b:hearts")
assert(#guest.bridge.menuSettings.entries == 0 and next(host.sent) == nil)
values[2] = "Mutated"
local old = settings[2]
old.change(-1)
assert(selection == 3 and old.value == "Draw")
old.change(-1)
assert(selection == 2 and old.value == "Hide")
settings[1].change(1)
assert(#settings == 1 and settings[1] == old and #host.logs == 1)
cancelSetting()
assert(#settings == 0)
old.change(1)
assert(selection == 2)
local malformed = def(function() end)
malformed.selected = 4
invalid(function()
    modA:RegisterMenuSetting(malformed)
end, "invalid_menu_selection")
modA:RegisterMenuSetting(def(function() end))
modA:Close()
assert(#settings == 0)
local solo = dofile(root .. "/src/bridge/api/sdk.lua").attach({}, "solo.hud")
assert(#solo:GetHUDPlayers() == 0)
solo:HideHUD("hearts", "all")()
solo:OnHUDHearts("all", function()
    error("solo")
end)()
solo:RegisterMenuSetting(def(function()
    error("solo")
end))()
solo:Close()
print("PASS local HUD scopes, ownership, health snapshot, fallback, menu choices and reload")
