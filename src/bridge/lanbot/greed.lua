-- Floor workflow only. It consumes observations and never changes the game.
local greed = {}
function greed.needsShop(obs)
    local actor = obs.actor
    return obs.greed
        and (
            (actor.keys < 1 and (actor.coins or 0) >= 5)
            or actor.needsHeal and (actor.coins or 0) >= 3
            or (actor.coins or 0) >= 15
        )
end
function greed.new()
    local flow = { revision = 0 }
    function flow:reset()
        self.floor, self.phase, self.reason, self.enteredShop, self.supplyAt, self.lootAt =
            nil, nil, nil, nil, nil, nil
        self.revision = self.revision + 1
    end
    function flow:transition(phase, reason)
        if self.phase ~= phase then
            self.phase, self.reason = phase, reason
            self.revision = self.revision + 1
        end
    end
    function flow:update(obs, mode)
        if not obs.greed or mode ~= "run" then
            if self.phase then
                self:reset()
            end
            return
        end
        local floor = obs.world .. ":" .. obs.greed.stage
        if self.floor ~= floor then
            self:reset()
            self.floor = floor
            self:transition("fight", "floor_started")
        end
        if self.phase == "fight" and obs.clear and obs.greed.wave >= obs.greed.bossWave then
            self:transition("supply", "boss_waves_complete")
            self.supplyAt = obs.frame
        end
        if self.phase == "supply" then
            if obs.shop then
                self.enteredShop = true
                local resource
                for _, pickup in ipairs(obs.pickups) do
                    resource = resource or pickup.paid
                end
                if not resource then
                    self:transition("loot", "supply_complete")
                elseif obs.frame - self.supplyAt >= 1200 then
                    self:transition("loot", "supply_unreachable")
                end
            elseif self.enteredShop or not greed.needsShop(obs) then
                self:transition("loot", self.enteredShop and "shop_left" or "no_supply_needed")
            elseif obs.frame - self.supplyAt >= 1200 then
                self:transition("loot", "shop_unreachable")
            end
        end
        if self.phase == "loot" then
            self.lootAt = self.lootAt or obs.frame
            if obs.frame - self.lootAt >= 1800 then
                self:transition("gather", "loot_unreachable")
            end
        end
        if self.phase == "gather" and obs.exit and obs.partyReady then
            self:transition("leave", "party_at_exit")
        end
    end
    return flow
end
return greed
