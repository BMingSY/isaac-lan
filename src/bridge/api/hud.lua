-- Registrations are local to one VM. Native components receive only audience masks.
return function(bridge, native, snapshots)
    local audiences = { ["local"] = 1, teammates = 2, all = 3 }
    local components = {}
    for _, name in ipairs({ "hearts", "activeItem", "trinket", "pocketItems", "ping" }) do
        components[name] = { hidden = {}, renderers = {}, hideMask = 0, drawMask = 0 }
    end
    local function changed(name, group)
        local hidden, drawn = 0, 0
        for _, bits in pairs(group.hidden) do
            hidden = hidden | bits
        end
        for _, entry in ipairs(group.renderers) do
            drawn = drawn | entry.bits
        end
        group.hideMask, group.drawMask = hidden, drawn
        if name ~= "ping" then
            native.presentation_hud_filters(name, hidden, drawn)
        end
    end
    local hud = { players = snapshots.players, reset = snapshots.reset }
    function hud.hide(name, audience)
        local group = assert(components[name], "invalid_hud_component")
        local token = {}
        group.hidden[token] = assert(audiences[audience], "invalid_hud_audience")
        changed(name, group)
        return function()
            group.hidden[token] = nil
            changed(name, group)
        end
    end
    function hud.subscribe(id, name, audience, fn)
        local group = assert(components[name], "invalid_hud_component")
        local bits = assert(audiences[audience], "invalid_hud_audience")
        assert(type(fn) == "function", "invalid_hud_renderer")
        local entry = { id = id, bits = bits, fn = fn }
        table.insert(group.renderers, entry)
        changed(name, group)
        function entry.remove()
            entry.fn = nil
            -- A callback may unregister itself or another renderer during this draw.
            local remaining = {}
            for _, other in ipairs(group.renderers) do
                if other ~= entry then
                    remaining[#remaining + 1] = other
                end
            end
            group.renderers = remaining
            changed(name, group)
        end
        return entry.remove
    end
    local function dispatch(group, bit, panel)
        local current = group.renderers
        for i = 1, #current do
            local entry = current[i]
            if entry.fn and not entry.drawing and entry.bits & bit ~= 0 then
                entry.drawing = true
                local ok, claimed = pcall(bridge.withView, function()
                    return entry.fn(bridge.copy(panel))
                end)
                entry.drawing = nil
                if not ok then
                    entry.remove()
                    bridge.log(
                        entry.id
                            .. " hud_renderer_disabled="
                            .. panel.component
                            .. " "
                            .. tostring(claimed)
                    )
                elseif claimed == true then
                    return true
                end
            end
        end
        return false
    end
    function hud.render(name, index, x, y, scale, alpha, slot)
        local group = components[name]
        if group.drawMask == 0 or not bridge.ready() then
            return false
        end
        local panel = snapshots.panel(name, index, x, y, scale, alpha, slot)
        return panel
                and dispatch(
                    group,
                    panel.isLocal and audiences["local"] or audiences.teammates,
                    panel
                )
            or false
    end
    function hud.ping(owner, x, y, scale, network, sync)
        local group = components.ping
        if group.hideMask == 0 and group.drawMask == 0 then
            return false
        end
        if not bridge.ready() then
            return false
        end
        local isLocal = owner == bridge.info().slot + 1
        local bit = isLocal and audiences["local"] or audiences.teammates
        if group.hideMask & bit ~= 0 then
            return true
        end
        if group.drawMask & bit == 0 then
            return false
        end
        return dispatch(group, bit, {
            component = "ping",
            ownerId = owner,
            isLocal = isLocal,
            x = x,
            y = y,
            scale = scale,
            alpha = 1,
            networkMs = network and network >= 0 and network or nil,
            syncMs = sync and sync >= 0 and sync or nil,
        })
    end
    return hud
end
