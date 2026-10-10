-- Deliberately small player/config contract. Unknown methods fail immediately.
return function(root, sharedResources)
    local module = dofile(root .. "/src/bridge/sync/inventory.lua")
    local fixture = {}
    local methods = {}
    local function active(id)
        return id == 2 or id == 4
    end
    local config = {}
    function config:GetCollectibles()
        return { Size = 9 }
    end
    function config:GetCollectible(id)
        if id > 0 and id < 9 then
            return { Type = active(id) and 2 or 1 }
        end
    end
    local inventory = module({
        config = function()
            return config
        end,
        activeType = 2,
        curse = 1,
    })
    local player
    function fixture.reset(ghost)
        player = setmetatable({
            kind = 0,
            ghost = ghost or false,
            curse = 0,
            items = {},
            actives = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
            trinkets = { 0, 0 },
            cards = { 0, 0 },
            pills = { 0, 0 },
            hearts = { 0, 0, 0, 0, 0, 0, 0 },
            souls = 0,
            black = 0,
            resources = { 0, 0, 0, 0, 0 },
            itemMutations = 0,
            resourceDelta = 0,
        }, {
            __index = function(_, name)
                return assert(methods[name], "Unsupported offline player method: " .. name)
            end,
        })
    end
    function methods:GetPlayerType()
        return self.kind
    end
    function methods:ChangePlayerType(kind)
        self.kind = kind
    end
    function methods:IsCoopGhost()
        return self.ghost
    end
    function methods:GetEffects()
        local p = self
        return {
            GetNullEffectNum = function()
                return p.curse
            end,
            AddNullEffect = function(_, _, _, delta)
                p.curse = p.curse + delta
            end,
            RemoveNullEffect = function(_, _, delta)
                p.curse = p.curse - delta
            end,
        }
    end
    function methods:GetCollectibleNum(id)
        local count = self.items[id] or 0
        for _, entry in ipairs(self.actives) do
            if entry[1] == id then
                count = count + 1
            end
        end
        return count
    end
    function methods:AddCollectible(id, _, _, slot)
        self.itemMutations = self.itemMutations + 1
        if active(id) then
            self.actives[(slot or 0) + 1] = { id, 0 }
        else
            self.items[id] = (self.items[id] or 0) + 1
        end
    end
    function methods:RemoveCollectible(id, _, slot)
        self.itemMutations = self.itemMutations + 1
        if active(id) then
            if slot then
                self.actives[slot + 1] = { 0, 0 }
            else
                for i, entry in ipairs(self.actives) do
                    if entry[1] == id then
                        self.actives[i] = { 0, 0 }
                        break
                    end
                end
            end
        else
            self.items[id] = math.max(0, (self.items[id] or 0) - 1)
        end
    end
    function methods:GetActiveItem(slot)
        return self.actives[slot + 1][1]
    end
    function methods:GetActiveCharge(slot)
        return self.actives[slot + 1][2]
    end
    function methods:GetBatteryCharge()
        return 0
    end
    function methods:SetActiveCharge(charge, slot)
        self.actives[slot + 1][2] = charge
    end
    function methods:SetPocketActiveItem(id, slot)
        self:AddCollectible(id, 0, false, slot)
    end
    function methods:GetTrinket(slot)
        return self.trinkets[slot + 1]
    end
    function methods:TryRemoveTrinket(id)
        for i, value in ipairs(self.trinkets) do
            if value == id then
                table.remove(self.trinkets, i)
                self.trinkets[2] = 0
                return
            end
        end
    end
    function methods:AddTrinket(id)
        self.trinkets = { id, self.trinkets[1] }
    end
    function methods:GetCard(slot)
        return self.cards[slot + 1]
    end
    function methods:GetPill(slot)
        return self.pills[slot + 1]
    end
    function methods:SetCard(slot, value)
        self.cards[slot + 1] = value
        if value ~= 0 then
            self.pills[slot + 1] = 0
        end
    end
    function methods:SetPill(slot, value)
        self.pills[slot + 1] = value
        if value ~= 0 then
            self.cards[slot + 1] = 0
        end
    end
    for i, name in ipairs({ "Coins", "Bombs", "Keys", "SoulCharge", "BloodCharge" }) do
        local getter = i <= 3 and "GetNum" .. name or "Get" .. name
        methods[getter] = function(p)
            if i <= 3 and sharedResources then
                return sharedResources[i]
            end
            return p.resources[i]
        end
        methods["Add" .. name] = function(p, delta)
            local resources = i <= 3 and sharedResources or p.resources
            resources[i] = resources[i] + delta
            p.resourceDelta = p.resourceDelta + math.abs(delta)
        end
    end
    for i, name in ipairs({
        "BrokenHearts",
        "MaxHearts",
        "BoneHearts",
        "Hearts",
        "RottenHearts",
        "EternalHearts",
        "GoldenHearts",
    }) do
        methods["Get" .. name] = function(p)
            return p.hearts[i]
        end
        methods["Add" .. name] = function(p, delta)
            p.hearts[i] = p.hearts[i] + delta
        end
    end
    function methods:GetSoulHearts()
        return self.souls
    end
    function methods:GetBlackHearts()
        return self.black
    end
    function methods:AddSoulHearts(delta)
        self.souls = math.max(0, self.souls + delta)
        self.black = self.black & ((1 << ((self.souls + 1) // 2)) - 1)
    end
    function methods:AddBlackHearts(delta)
        local before = self.souls
        self:AddSoulHearts(delta)
        for i = before // 2, (self.souls - 1) // 2 do
            self.black = self.black | (1 << i)
        end
    end
    function fixture.apply(value, refresh)
        inventory.apply(player, value, refresh)
        return fixture.read()
    end
    function fixture.read()
        return { inventory.capture(player), player.itemMutations, player.resourceDelta }
    end
    fixture.reset()
    return fixture
end
