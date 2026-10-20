return function(env, modules)
    local nav = modules["lanbot/navigation"]
    local combat = modules["lanbot/combat"](nav, modules["lanbot/hazards"](nav))
    local planner = modules["lanbot/planner"](nav, modules["lanbot/greed"], modules["lanbot/items"])
    local bot = {
        state = "off",
        mode = "run",
        style = "balanced",
        task = "idle",
        plan = planner.new(),
        stats = { frames = 0, maxMs = 0, blocked = 0, hits = 0 },
    }
    local modes = { run = true, explore = true, hold = true }
    local function release()
        bot.lastFrame, bot.previous, bot.charging, bot.releasing = nil, 0, nil, nil
        bot.targetId, bot.aimId = nil, nil
        bot.inputs = {}
        bot.kite = nil
        bot.engagement = nil
        env.input(false, 0)
    end
    local function neutral()
        bot.previous, bot.charging, bot.releasing = 0, nil, nil
        bot.targetId, bot.aimId = nil, nil
        bot.inputs = {}
        bot.kite = nil
        bot.engagement = nil
        -- A boundary discards queued press edges as well as held controls.
        env.input(false, 0)
        env.input(true, 0)
    end
    function bot.reset()
        release()
        bot.state, bot.mode, bot.style, bot.task, bot.reason = "off", "run", "balanced", "idle", nil
        bot.plan, bot.world, bot.room, bot.actor, bot.health, bot.runId =
            planner.new(), nil, nil, nil, nil, nil
        bot.flowRevision = nil
        bot.stats = { frames = 0, maxMs = 0, blocked = 0, hits = 0 }
    end
    function bot.poll()
        local info = env.info()
        if info.active ~= 1 and bot.state ~= "off" then
            bot.reset()
        elseif bot.runId and bot.runId ~= info.runId then
            bot.reset()
        end
    end
    function bot.status()
        local info = env.info()
        local message = "LANBOT "
            .. bot.state
            .. " role="
            .. (info.authority == 1 and "host" or "client")
            .. " mode="
            .. bot.mode
            .. " style="
            .. bot.style
            .. " task="
            .. bot.task
        if bot.reason then
            message = message .. " reason=" .. bot.reason
        end
        if bot.plan.flow.phase then
            message = message
                .. " phase="
                .. bot.plan.flow.phase
                .. " phase_reason="
                .. bot.plan.flow.reason
        end
        if bot.plan.goal then
            message = message .. " goal=" .. bot.plan.goal.id
        end
        if bot.engagement then
            message = message .. " combat=" .. bot.engagement.phase
        end
        if bot.targetId then
            message = message .. " target=" .. bot.targetId
        end
        if bot.stats.candidates then
            message = message .. " move=" .. bot.previous .. " candidates=" .. bot.stats.candidates
        end
        return message
            .. string.format(
                " frames=%d hits=%d blocked=%d max_ms=%.3f",
                bot.stats.frames,
                bot.stats.hits,
                bot.stats.blocked,
                bot.stats.maxMs
            )
    end
    function bot.command(args)
        local words = {}
        for word in (args or ""):gmatch("%S+") do
            words[#words + 1] = word
        end
        local command = words[1] or "help"
        if command == "help" and #words <= 1 then
            return "/lanbot on | pause | resume | off | status | next\n/lanbot mode run|explore|hold\n/lanbot style aggressive|balanced|cautious"
        end
        if command == "mode" or command == "style" then
            local allowed = command == "mode" and modes or combat.styles
            if #words ~= 2 or not allowed[words[2]] then
                return "LANBOT error=invalid_" .. command .. "; use lanbot help"
            end
            bot[command] = words[2]
            bot.plan:cancel()
            release()
            bot.task, bot.reason = "idle", nil
            return bot.status()
        end
        if
            #words ~= 1
            or not ({
                on = true,
                pause = true,
                resume = true,
                off = true,
                status = true,
                next = true,
            })[command]
        then
            return "LANBOT error=invalid_command; use lanbot help"
        end
        local info = env.info()
        if command == "status" then
            return bot.status()
        elseif command == "off" or command == "pause" then
            release()
            bot.state = command == "off" and "off" or bot.state == "off" and "off" or "paused"
            bot.task, bot.reason = "idle", nil
            if command == "off" then
                bot.plan:cancel()
            end
        elseif command == "on" or command == "resume" then
            if info.active ~= 1 then
                return "LANBOT error=lan_game_required"
            elseif command == "resume" and bot.state == "off" then
                return "LANBOT error=use_on_first"
            end
            if bot.state ~= "running" then
                release()
                bot.plan:cancel()
                bot.state, bot.task, bot.reason, bot.runId =
                    "running", "wait", "view_not_ready", info.runId
            end
        elseif command == "next" then
            if bot.state ~= "running" or bot.mode == "hold" then
                return "LANBOT error=next_requires_run_or_explore"
            end
            if not bot.plan:nextExit() then
                return "LANBOT error=no_known_exit"
            end
            bot.lastFrame = nil
        end
        return bot.status()
    end
    local function decide(frame)
        local info = env.info()
        if info.active ~= 1 then
            bot.reset()
            return
        end
        if bot.runId and bot.runId ~= info.runId then
            bot.reset()
            return
        end
        if bot.state ~= "running" then
            env.input(false, 0)
            return
        end
        if bot.lastFrame == frame then
            return
        end
        bot.lastFrame = frame
        local start = env.clock()
        local obs, reason = env.observe(frame, info)
        if not obs then
            bot.task, bot.reason, bot.previous, bot.charging = "wait", reason, 0, nil
            neutral()
            return
        end
        obs.now, obs.inputHistory = (info.nowMs or env.clock()) / 1000, bot.inputs or {}
        if bot.world ~= obs.world or bot.room ~= obs.room or bot.actor ~= obs.actor.id then
            if bot.world == obs.world and bot.room == obs.room then
                bot.plan:cancel()
            end
            bot.world, bot.room, bot.actor, bot.health = obs.world, obs.room, obs.actor.id, nil
            bot.task, bot.reason = "wait", "view_changed"
            neutral()
            bot.plan:observe(obs)
            return -- Never carry departure input into an arrival frame.
        end
        bot.plan:observe(obs)
        if bot.health and obs.actor.health < bot.health then
            bot.stats.hits = bot.stats.hits + 1
        end
        bot.health = obs.actor.health
        obs.map.allowedExit = nil
        obs.map.allowedPickup = nil
        obs.map.gridRecovery = obs.clear == true
        local breaking = bot.plan:obstacle(obs)
        local target = breaking or combat.target(obs, bot.style, bot.targetId)
        bot.targetId = target and target.id
        local goal = bot.plan:arrival(obs)
        local kite = not goal
            and not breaking
            and combat.engagement(obs, target, bot)
            and combat.kite(obs, bot.style, bot, function(id)
                return bot.plan:available(id, frame)
            end)
        if goal then
            bot.kite = nil
            bot.task, bot.reason = goal.task, nil
        elseif kite then
            goal, bot.task, bot.reason = kite, "kite", nil
        elseif target then
            goal = combat.goal(obs, target, bot.style, function(id)
                return bot.plan:available(id, frame)
            end, bot.aimId)
            bot.aimId = goal and goal.id
            bot.task, bot.reason = breaking and "clear_obstacle" or "attack", nil
        else
            goal, reason = bot.plan:choose(obs, bot.mode, bot.style)
            bot.task, bot.reason = goal and goal.task or "wait", reason
        end
        if goal and goal.task and not breaking then
            breaking = bot.plan:obstacle(obs, goal, true)
            if breaking then
                target, bot.kite = breaking, nil
                goal, bot.task = combat.goal(obs, breaking, bot.style), "clear_obstacle"
            end
        end
        local flow = bot.plan.flow
        if flow.phase and bot.flowRevision ~= flow.revision then
            bot.flowRevision = flow.revision
            env.log(
                "flow phase=" .. flow.phase .. " reason=" .. flow.reason .. " floor=" .. flow.floor
            )
        end
        if goal and goal.exit then
            obs.map.allowedExit = goal.exit.id
        end
        if goal and goal.paid then
            obs.map.allowedPickup = goal.id
        end
        local waypoint, blocked = bot.plan:waypoint(obs, goal)
        if not waypoint and not breaking then
            breaking = bot.plan:obstacle(obs, goal or target)
            if breaking then
                target, bot.kite = breaking, nil
                obs.map.allowedPickup, obs.map.allowedExit = nil, nil
                goal = combat.goal(obs, breaking, bot.style)
                bot.task = "clear_obstacle"
                waypoint, blocked = bot.plan:waypoint(obs, goal)
            end
        end
        if blocked then
            bot.stats.blocked = bot.stats.blocked + 1
            bot.reason = blocked
        end
        local previous = goal and bot.previous or 0
        local move, _, candidates = combat.move(
            obs,
            waypoint,
            bot.style,
            previous,
            waypoint and goal and goal.door,
            goal and goal.entering
        )
        bot.stats.candidates = candidates
        bot.previous = move
        local inputs = bot.inputs or {}
        bot.inputs = inputs
        local bucket = math.floor(obs.now * 60 + 0.0001)
        local input = { at = obs.now, buttons = move, bucket = bucket }
        if inputs[#inputs] and inputs[#inputs].bucket == bucket then
            inputs[#inputs] = input
        else
            inputs[#inputs + 1] = input
        end
        while #inputs > 32 or #inputs > 1 and inputs[2].at < obs.now - 0.4 do
            table.remove(inputs, 1)
        end
        local shoot = combat.shoot(obs, target, bot)
        env.input(true, move | shoot)
        bot.stats.frames = bot.stats.frames + 1
        bot.stats.maxMs = math.max(bot.stats.maxMs, env.clock() - start)
    end
    function bot.step(frame)
        local ok, error = pcall(decide, frame)
        if not ok then
            release()
            bot.state, bot.task, bot.reason = "paused", "wait", "decision_error"
            env.log("error=" .. tostring(error))
        end
    end
    return bot
end
