local root = assert(arg[1])
local runtime = dofile(root .. "/tests/fixtures/api_runtime.lua")(root)
local host, guest = runtime.peer(0), runtime.peer(1)
local h, g = host.api:Attach({}, "skin"), guest.api:Attach({}, "skin")
local other = guest.api:Attach({}, "backup")
local function expect(peer, hearts, active, pocket, render)
    local filters = peer.hudFilters or {}
    local heart = filters.hearts or { 0, 0 }
    assert(heart[1] == hearts and (heart[2] ~= 0) == render)
    assert(
        (filters.activeItem or { 0 })[1] == active and (filters.pocketItems or { 0 })[1] == pocket
    )
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
local function draw(index, x, y, scale)
    return guest.env._IsaacLanRenderHUD("hearts", index, x, y, scale, 1, -1)
end
local reads = 0
guest.bridge.readHUDCollectibles = function(player, catalog)
    reads = reads + 1
    catalog.read = true
    return { { id = -2, count = player.hash } }
end
for _, actor in ipairs(guest.actors) do
    function actor:GetSprite()
        return self
    end
    function actor:GetActiveItem(slot)
        return ({ 42, 0, 333, 0 })[slot + 1]
    end
    function actor:GetActiveCharge(slot)
        return slot + 1
    end
    function actor:GetBatteryCharge(slot)
        return slot + 2
    end
    function actor:GetTrinket(slot)
        return slot == 0 and 32769 or 0
    end
    function actor:GetNumCoins()
        return self.hash
    end
    function actor:GetNumKeys()
        return 2
    end
    function actor:GetNumBombs()
        return 7
    end
    function actor:HasGoldenBomb()
        return true
    end
    function actor:HasGoldenKey()
        return false
    end
    function actor:GetSoulCharge()
        return 1
    end
    function actor:GetBloodCharge()
        return 3
    end
end
guest.env._IsaacLan.items_active_charge = function(sprite, slot)
    assert(sprite:GetActiveItem(slot) ~= 0)
    return 1, 6
end
guest.env._IsaacLan.actor_pockets = function(sprite)
    assert(sprite.hash)
    return string.pack(">I4I4I4I4I4I4I4I4", 11, 1, 3, 2, 2050, 0, 0, 1)
end
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
assert(reads == 0)
local snapshot = g:GetHUDPlayers({ includeCollectibles = true })[1]
assert(reads == 3 and snapshot.collectibles[1].id == -2)
assert(
    #snapshot.activeItems == 4
        and snapshot.activeItems[3].slot == 2
        and snapshot.activeItems[3].id == 333
)
assert(snapshot.activeItems[3].charge == 3 and snapshot.activeItems[3].batteryCharge == 4)
assert(
    snapshot.activeItems[1].maxCharge == 6
        and snapshot.activeItems[1].chargeType == 1
        and snapshot.activeItems[2].maxCharge == nil
)
assert(snapshot.trinkets[1].id == 32769 and snapshot.trinkets[2].id == 0)
assert(snapshot.pocketItems[1].kind == "card" and snapshot.pocketItems[1].id == 11)
assert(
    snapshot.pocketItems[2].kind == "activeItem"
        and snapshot.pocketItems[2].activeSlot == 2
        and snapshot.pocketItems[2].id == 333
)
assert(
    snapshot.pocketItems[3].kind == "pill"
        and snapshot.pocketItems[3].id == 2050
        and snapshot.pocketItems[4].kind == "empty"
)
assert(
    snapshot.resources.coins == 11
        and snapshot.resources.goldenBomb
        and not snapshot.resources.goldenKey
)
snapshot.collectibles[1].count = -5
assert(
    g:GetHUDPlayers({ includeCollectibles = true })[1].collectibles[1].count == 11 and reads == 3
)
assert(g:GetHUDPlayers()[1].collectibles == nil)
guest.bridge.commit()
assert(
    g:GetHUDPlayers({ includeCollectibles = true })[1].collectibles[1].count == 11 and reads == 6
)
invalid(function()
    g:GetHUDPlayers({ includeCollectibles = 1 })
end, "invalid_hud_options")
local calls = {}
for _, component in ipairs({ "activeItem", "trinket", "pocketItems", "ping" }) do
    g:OnHUDRender(component, "teammates", function(panel)
        assert(
            panel.component == component and panel.x == 12 and panel.y == 13 and panel.ownerId == 1
        )
        assert(panel.alpha == (component == "ping" and 1 or 0.25) and not panel.isLocal)
        assert(panel.health == nil and panel.collectibles == nil)
        if component == "activeItem" then
            assert(panel.activeItem.slot == 2 and panel.activeItem.id == 333)
        elseif component == "trinket" then
            assert(panel.trinket.slot == 0 and panel.trinket.id == 32769)
        elseif component == "pocketItems" then
            assert(panel.pocketItems[2].id == 333)
        else
            assert(panel.networkMs == 0 and panel.syncMs == nil and panel.playerId == nil)
        end
        calls[component] = (calls[component] or 0) + 1
        return true
    end)
end
local componentDraw = guest.env._IsaacLanRenderHUD
assert(componentDraw("activeItem", 0, 12, 13, -0.5, 0.25, 2))
assert(not componentDraw("activeItem", 0, 12, 13, -0.5, 0.25, 1))
assert(not componentDraw("activeItem", 1, 12, 13, -0.5, 0.25, 2))
assert(componentDraw("trinket", 0, 12, 13, 0.5, 0.25, 0))
assert(not componentDraw("trinket", 0, 12, 13, 0.5, 0.25, 1))
assert(componentDraw("pocketItems", 0, 12, 13, 0.5, 0.25, -1))
local ping = guest.bridge.hud.ping
local show = g:HideHUD("ping", "teammates")
assert(ping(1, 12, 13, 0.6, 0, -1) and calls.ping == nil)
show()
assert(ping(1, 12, 13, 0.6, 0, -1) and calls.ping == 1)
assert(not ping(2, 12, 13, 0.6, 0, 0) and calls.ping == 1)
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
