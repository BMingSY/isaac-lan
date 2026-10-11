-- Game API adaptation only. Timed windows are learned from complete observed
-- cycles, never from an assumed period or a wall clock that advances in menus.
return function()
    local terrain = { cycles = {} }
    function terrain:reset(world, room, actor)
        local key = world .. ":" .. room .. ":" .. actor
        if self.key ~= key then
            self.key, self.cycles = key, {}
        end
    end
    function terrain:spikes(index, state, tick, disabled)
        if disabled and state == 1 then
            self.cycles[index] = nil
            return math.huge
        end
        local cycle = self.cycles[index]
        if not cycle or tick < cycle.tick or tick - cycle.tick > 2 then
            cycle = { state = state, tick = tick }
            self.cycles[index] = cycle
        elseif cycle.state ~= state then
            if cycle.state == 1 and cycle.started then
                local duration = tick - cycle.started
                cycle.duration = math.min(cycle.duration or duration, duration)
            end
            cycle.state, cycle.started = state, state == 1 and tick or nil
        end
        cycle.tick = tick
        if state == 1 and cycle.started and cycle.duration then
            return math.max(0, (cycle.duration - (tick - cycle.started)) / 30 - 0.15)
        end
        return 0
    end
    function terrain:trapdoor(grid, clear)
        -- Boss exits reopen only after nearby actors leave. Keep a closed
        -- exit out of the route and retreat beyond the native 50 px guard;
        -- the actor radius adds room to wait, without forcing the grid open.
        local open = clear and grid.State == 1
        return open, open and 24 or 50
    end
    function terrain:button(grid, greed, clear)
        -- Vanilla states: ordinary plate pressed=3, reward plate pressed=4.
        -- Reward/rail plates are deliberately not ordinary room puzzles.
        if grid:GetVariant() == 0 then
            return grid.State ~= 3
        end
        if grid:GetVariant() == 2 and greed then
            -- OffRed is the stop button: touching it costs health and pauses
            -- waves. Start/resume ordinary waves and then the Boss round;
            -- leave the optional Devil round to human input.
            local animation = grid:GetSprite():GetAnimation()
            return clear
                and greed.stage < 7
                and greed.wave < greed.bossWave
                and grid.State == 0
                and (animation == "Off" or animation == "OffSkull")
        end
        return false
    end
    return terrain
end
