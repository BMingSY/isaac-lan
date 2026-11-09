-- Observe real Abyss conversions through native collectible suppression/restore.
return function(native, actor, report)
    local prepared, entered, returned, replicaChecks = false, false, false, 0
    local replicaReturnAt
    local expected = {
        [0] = { CollectibleType.COLLECTIBLE_LUNCH },
        [1] = { CollectibleType.COLLECTIBLE_SAD_ONION, CollectibleType.COLLECTIBLE_SPOON_BENDER },
    }
    local function signature(slot)
        local result = {}
        actor(slot, function(p)
            for _, e in ipairs(Isaac.GetRoomEntities()) do
                local f = e:ToFamiliar()
                if
                    f
                    and f.Variant == FamiliarVariant.ABYSS_LOCUST
                    and f:Exists()
                    and f.Player
                    and f.Player.InitSeed == p.InitSeed
                then
                    result[#result + 1] = f.SubType
                end
            end
        end)
        table.sort(result)
        return table.concat(result, ",")
    end
    local function check(slot, label)
        local wanted = { table.unpack(expected[slot]) }
        table.sort(wanted)
        local actual = signature(slot)
        assert(
            actual == table.concat(wanted, ","),
            "Abyss locust ownership/subtypes changed "
                .. label
                .. " slot="
                .. slot
                .. " actual="
                .. actual
        )
    end
    local probe = {}
    function probe.prepare()
        for slot = 0, 1 do
            actor(slot, function(p)
                p:AddCollectible(CollectibleType.COLLECTIBLE_ABYSS)
                for _, item in ipairs(expected[slot]) do
                    Isaac.Spawn(
                        EntityType.ENTITY_PICKUP,
                        PickupVariant.PICKUP_COLLECTIBLE,
                        item,
                        p.Position + Vector(80, 0),
                        Vector.Zero,
                        nil
                    )
                    p:UseActiveItem(CollectibleType.COLLECTIBLE_ABYSS, UseFlag.USE_NOANIM, -1)
                end
            end)
        end
        prepared = true
        report("ABYSS native conversions prepared")
    end
    function probe.observe(t)
        if not prepared or t % 30 ~= 0 then
            return
        end
        local position = native.rooms_positions()["1"]
        if position.dimension == 1 then
            if not entered then
                report("ABYSS inside escape locusts=" .. signature(1))
            end
            entered = true
        elseif not entered then
            check(0, "before escape")
            check(1, "before escape")
        end
        check(0, "resident during escape")
    end
    function probe.returned()
        assert(entered, "Abyss did not enter native escape")
        check(0, "returned resident")
        check(1, "returned guest")
        if not returned then
            report("ABYSS restored guest=" .. signature(1) .. " resident=" .. signature(0))
        end
        returned = true
    end
    function probe.replica(t)
        local position = native.rooms_positions()["1"]
        if not position then
            return
        end
        if position.dimension == 1 then
            entered = true
        end
        if entered and position.dimension == 0 and position.index >= 0 then
            replicaReturnAt = replicaReturnAt or t
            if t - replicaReturnAt < 60 then
                return
            end
            check(1, "replica after escape")
            replicaChecks = replicaChecks + 1
            if replicaChecks == 1 then
                report("ABYSS replica restored=" .. signature(1) .. " tick=" .. t)
            end
        end
    end
    function probe.finish(host)
        assert(
            host and returned or not host and replicaChecks > 10,
            "Missing post-escape locust observations"
        )
    end
    return probe
end
