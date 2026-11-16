-- Public render-order properties must survive native phases on both peers.
return function(native, actor, report)
    local samples, variants, last = 0, {}, nil
    local overlap = 0
    local function sample(e)
        return { e.Type, e.Variant, e.SortingLayer, e.RenderZOffset, e.DepthOffset }
    end
    local probe = {}
    function probe.direction(slot)
        if not native.rooms_ready() then
            return -1
        end
        local direction = -1
        assert(native.api_with_local_view(function()
            local beast
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == EntityType.ENTITY_BEAST and e.Variant == 0 and e:Exists() then
                    beast = e
                    break
                end
            end
            if not beast then
                return
            end
            local p = Isaac.GetPlayer(assert(native.rooms_heads()[tostring(slot)]))
            local dx, dy = 320 + (slot == 0 and -22 or 22) - p.Position.X, 340 - p.Position.Y
            if math.abs(dx) > 8 then
                direction = dx < 0 and ButtonAction.ACTION_LEFT or ButtonAction.ACTION_RIGHT
            elseif math.abs(dy) > 8 then
                direction = dy < 0 and ButtonAction.ACTION_UP or ButtonAction.ACTION_DOWN
            else
                overlap = overlap + 1
                if overlap == 60 then
                    report("BEAST_LAYERS OVERLAP_READY slot=" .. slot)
                end
            end
        end))
        return direction
    end
    function probe.capture()
        local result = {}
        actor(1, function()
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == EntityType.ENTITY_BEAST and e:Exists() then
                    result[#result + 1] = sample(e)
                    variants[e.Variant] = true
                end
            end
        end)
        if #result == 0 then
            return false
        end
        for slot = 0, 1 do
            actor(slot, function(p)
                result[#result + 1] = sample(p)
            end)
        end
        samples = samples + 1
        local rows = {}
        for _, value in ipairs(result) do
            rows[#rows + 1] = table.concat(value, ",")
        end
        local key = table.concat(rows, ";")
        if key ~= last then
            report("BEAST_LAYERS authority=" .. key)
            last = key
        end
        return result
    end
    function probe.restore(expected)
        if not expected then
            return
        end
        local actual = {}
        assert(native.api_with_local_view(function()
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                if e.Type == EntityType.ENTITY_BEAST and e:Exists() then
                    actual[#actual + 1] = sample(e)
                end
            end
        end))
        for slot = 0, 1 do
            actor(slot, function(p)
                actual[#actual + 1] = sample(p)
            end)
        end
        local function key(e)
            return table.concat(e, ",")
        end
        local wanted, found = {}, {}
        for _, e in ipairs(expected) do
            wanted[#wanted + 1] = key(e)
            if e[1] == EntityType.ENTITY_BEAST then
                variants[e[2]] = true
            end
        end
        for _, e in ipairs(actual) do
            found[#found + 1] = key(e)
        end
        table.sort(wanted)
        table.sort(found)
        assert(
            table.concat(wanted, ";") == table.concat(found, ";"),
            "Beast/player render order differs from authority"
        )
        samples = samples + 1
        if samples % 120 == 0 then
            report("BEAST_LAYERS replica_samples=" .. samples)
        end
    end
    function probe.finish(requireOverlap)
        local count = 0
        for _ in pairs(variants) do
            count = count + 1
        end
        assert(samples > 120 and count >= 2, "Missing native Beast render phases")
        assert(not requireOverlap or overlap >= 60, "Player did not reach the Beast silhouette")
        report("BEAST_LAYERS PASS samples=" .. samples .. " variants=" .. count)
    end
    return probe
end
