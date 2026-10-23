-- A local door preview covers the handoff without changing the room or its AI.
return function(env)
    local departure, arrival, fill
    local fadeOut, fadeIn, timeout = 0.09, 0.12, 0.5
    local function now()
        return env.clock() / 1000
    end
    local function alpha()
        local t = now()
        if arrival then
            local remaining = 1 - (t - arrival.at) / fadeIn
            if remaining <= 0 then
                arrival = nil
                return 0
            end
            return arrival.alpha * remaining
        end
        if not departure then
            return 0
        end
        local age = t - departure
        if age > timeout then
            departure = nil
            return 0
        end
        return math.min(1, age / fadeOut)
    end
    local function finish()
        local value = alpha()
        departure = nil
        arrival = value > 0 and { at = now(), alpha = value } or nil
    end
    return {
        begin = function()
            if not departure then
                departure, arrival = now(), nil
            end
        end,
        arrive = finish,
        cancel = finish,
        alpha = alpha,
        render = function()
            local value = alpha()
            if value <= 0 then
                return
            end
            if not fill then
                fill = env.sprite()
                fill:Load("gfx/ui/bossoverlay_whiteout.anm2", true)
                fill:SetFrame("Fade", 15)
            end
            fill.Scale = env.vector(env.width() / 480, env.height() / 270)
            fill.Color = env.color(0, 0, 0, value, -1, -1, -1)
            fill:Render(env.vector(0, 0))
        end,
        reset = function()
            departure, arrival, fill = nil, nil, nil
        end,
    }
end
