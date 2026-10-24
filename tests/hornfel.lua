local root = assert(arg[1])
local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
local wire = dofile(root .. "/src/bridge/sync/codec.lua")
local reconcile = dofile(root .. "/src/bridge/sync/entities.lua")(
    dofile(root .. "/src/bridge/sync/fields.lua")
)(enums.EntityType, enums.PickupVariant)
for _, kind in ipairs({ 906, 920 }) do
    local count = kind == 920 and 3 or 2
    local function pack(a, b, c)
        if count == 3 then
            return string.pack(">I4I4I4", a, b, c or 0)
        end
        return string.pack(">I4I4", a, b)
    end
    local objects, refs, writes = {}, {}, 0
    local function entity(kind, index, id)
        local e = {
            Type = kind,
            Index = index,
            Variant = 0,
            SubType = 0,
            id = id,
            alive = true,
            data = {},
        }
        function e:Exists()
            return self.alive
        end
        function e:GetData()
            return self.data
        end
        function e:GetSprite()
            return self
        end
        return e
    end
    local native = {
        boss_held_bombs = function(e, a, b, c)
            if a == nil then
                local indices = {}
                for i = 1, count do
                    indices[i] = e.held[i] and e.held[i].Index or -1
                end
                return table.unpack(indices)
            end
            assert(e.Type == kind)
            writes = writes + 1
            e.held = { a, b, c }
            return true
        end,
    }
    local hornfel = dofile(root .. "/src/bridge/compat/bosses/held_bombs.lua")(
        native,
        enums.EntityType,
        function()
            return objects
        end
    )
    local dogma = dofile(root .. "/src/bridge/compat/bosses/dogma.lua")(function(x, y)
        return { X = x, Y = y }
    end, enums.EntityType, enums.EffectVariant)
    local visual = dofile(root .. "/src/bridge/compat/visuals.lua")(dogma, hornfel)
    local boss, first, second = entity(kind, 10, 101), entity(4, 11, 102), entity(4, 12, 103)
    local third = entity(4, 13, 104)
    boss.held = { first, second, count == 3 and third or nil }
    objects = { boss, second, third, first }
    local value = wire.decode(wire.encode({
        visual.capture(boss, function(e)
            return e.id
        end),
    }))[1]
    assert(value == pack(102, 103, 104), "Native indices leaked onto the wire")
    objects = {}
    local function tuple(id, kind, state)
        local v = { id, kind, 0, 0 }
        for i = 5, 23 do
            v[i] = 0
        end
        v[24] = state
        return v
    end
    local values = { tuple(101, kind, value), tuple(103, 4, false), tuple(102, 4, false) }
    if count == 3 then
        values[#values + 1] = tuple(104, 4, false)
    end
    local env = {
        ref = function(id)
            return refs[id]
        end,
        key = function(e)
            return e
        end,
        entities = function()
            return objects
        end,
        discard = function(e)
            e.alive = false
            refs[e.id] = nil
        end,
        reclaim = function() end,
        spawn = function(v)
            local e = entity(v[2], 900 + v[1], v[1])
            objects[#objects + 1] = e
            return e
        end,
        apply = function(e, v)
            refs[v[1]] = e
            visual.apply(e, v[24])
        end,
        link = function(e, v, ref)
            visual.link(e, v[24], ref)
        end,
    }
    reconcile(values, env)
    local replica = refs[101]
    assert(
        replica.held[1] == refs[102]
            and replica.held[2] == refs[103]
            and (count == 2 or replica.held[3] == refs[104]),
        "Bombs must exist before binding"
    )
    reconcile(values, env)
    assert(
        refs[101] == replica and replica.held[2] == refs[103],
        "Repeated state recreated the boss"
    )
    values[1][24] = pack(0, 103, 104)
    table.remove(values, 3)
    reconcile(values, env)
    assert(
        replica.held[1] == false and replica.held[2] == refs[103] and not refs[102],
        "Released bomb remained linked"
    )
    local before = writes
    for _, invalid in ipairs({
        false,
        "short",
        pack(0, 999, 0),
        count == 3 and pack(0, 0, 999) or "invalid",
    }) do
        assert(not pcall(visual.link, replica, invalid, env.ref))
    end
    assert(writes == before, "Invalid state partially updated the native container")
    reconcile({}, env)
    assert(not refs[101] and not refs[103], "Room departure retained old identities")
    objects = {}
    values = { tuple(101, kind, pack(0, 0, 0)) }
    reconcile(values, env)
    assert(
        refs[101] ~= replica and refs[101].held[1] == false and refs[101].held[2] == false,
        "Recreated room/floor must prepare even empty bomb slots"
    )
    local unrelated = entity(907, 20, 104)
    assert(visual.capture(unrelated) == false)
    visual.apply(unrelated, false)
    visual.link(unrelated, false, env.ref)
    local warning = entity(1000, 21, 105)
    warning.Variant, warning.SubType, warning.TargetPosition = 172, 1, { X = 20, Y = -40 }
    local geometry = visual.capture(warning)
    warning.TargetPosition = { X = 0, Y = 0 }
    visual.apply(warning, geometry)
    assert(
        warning.TargetPosition.X == 20 and warning.TargetPosition.Y == -40,
        "Dogma geometry regressed"
    )
    print(
        "PASS Boss "
            .. kind
            .. " ordered stable links, empty initialization, removal, room/floor recreation and Boss dispatch"
    )
end
