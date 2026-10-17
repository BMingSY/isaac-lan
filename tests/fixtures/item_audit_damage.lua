return function(report, actor, moveRoom, moveFloor)
    local nextStep = 1
    local pending = {}
    local function health(p)
        return {
            hearts = p:GetHearts(),
            soul = p:GetSoulHearts(),
            broken = p:GetBrokenHearts(),
            cooldown = p:GetDamageCooldown(),
        }
    end
    return {
        prepare = function(case)
            nextStep = 1
            pending = {}
            if not case.damage_effects then
                return
            end
            for slot = 0, 1 do
                actor(slot, function(p)
                    p:AddMaxHearts(24 - p:GetMaxHearts(), false)
                    p:AddSoulHearts(-p:GetSoulHearts())
                    local desired = slot == case.slot and case.damage_effects.hearts or 24
                    p:AddHearts(desired - p:GetHearts())
                    -- Clear arrival protection before acquiring the tested
                    -- effect. Subsequent trials let native cooldowns expire.
                    p:ResetDamageCooldown()
                end)
            end
        end,
        advance = function(case, tick)
            if not case.damage_effects then
                return
            end
            -- Native damage may be buffered until the simulation update.
            -- Observe the result on the next tick, without applying damage again.
            for _, trial in ipairs(pending) do
                actor(trial.slot, function(p)
                    trial.after, trial.after_tick = health(p), tick
                    report("damage_trial", trial)
                end)
            end
            pending = {}
            local step = case.damage_effects.steps[nextStep]
            if not step or tick < step.tick then
                return
            end
            nextStep = nextStep + 1
            if step.action ~= "hit" then
                report("damage_transition", {
                    tick = tick,
                    action = step.action,
                    room = _IsaacLan.rooms_positions()[tostring(case.slot)].index,
                    stage = Game():GetLevel():GetStage(),
                })
                if step.action == "room" then
                    moveRoom()
                else
                    moveFloor()
                end
                return
            end
            for slot = 0, 1 do
                actor(slot, function(p)
                    local before = health(p)
                    p:TakeDamage(step.amount, 0, EntityRef(p), 0)
                    pending[#pending + 1] = {
                        probe = step.name,
                        tick = tick,
                        slot = slot,
                        amount = step.amount,
                        room = _IsaacLan.rooms_positions()[tostring(slot)].index,
                        stage = Game():GetLevel():GetStage(),
                        before = before,
                    }
                end)
            end
        end,
    }
end
