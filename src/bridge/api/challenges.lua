-- Public challenge callbacks run only for the selected declaration. Native code
-- owns the lobby contract; the Mod owns its encounter and its bounded snapshot.
return function(native, codec)
    local entries = {}
    local function integer(value, low, high)
        return math.type(value) == "integer" and value >= low and value <= high
    end
    local function register(namespace, def)
        assert(type(def) == "table", "invalid_challenge")
        local id, version = def.id, def.version
        local character, difficulty, count =
            def.character or 65535, def.difficulty or 0, def.players or 0
        assert(
            integer(id, 0x8000, 0xffff)
                and integer(version, 1, 65535)
                and type(def.name) == "string"
                and #def.name > 0
                and #def.name <= 96
                and not def.name:find("[%z%c]")
                and integer(character, 0, 65535)
                and integer(difficulty, 0, 3)
                and (count == 0 or integer(count, 2, 4))
                and type(def.step) == "function"
                and type(def.capture) == "function"
                and type(def.apply) == "function"
                and type(def.reset) == "function"
                and (def.canEnter == nil or type(def.canEnter) == "function"),
            "invalid_challenge"
        )
        assert(not entries[id], "duplicate_challenge_id")
        local contract = table.concat({ namespace, id, version, character, difficulty, count }, "/")
        assert(
            native.api_register_challenge(
                id,
                version,
                def.name,
                character,
                difficulty,
                count,
                contract
            ),
            "challenge_registration_rejected"
        )
        local entry, previous = {}, nil
        function entry.reset()
            previous = nil
            def.reset()
        end
        function entry.step(info)
            if previous == info.tick then
                return
            end
            previous = info.tick
            local players = {}
            for _, actor in ipairs(native.api_actors()) do
                if actor.role == 1 and (info.connected & (1 << (actor.owner - 1))) ~= 0 then
                    players[actor.owner] = Isaac.GetPlayer(actor.index)
                end
            end
            def.step({
                runId = info.runId,
                worldEpoch = info.worldEpoch,
                tick = info.tick,
                players = players,
            })
        end
        function entry.snapshot()
            return codec.encode(def.capture())
        end
        function entry.apply(payload)
            def.apply(codec.decode(payload))
        end
        entry.canEnter = def.canEnter
        entries[id] = entry
        local function release()
            if entries[id] ~= entry then
                return
            end
            native.api_remove_challenge(id)
            entries[id] = nil
            entry.reset()
        end
        local function finish()
            return entries[id] == entry and native.net_finish_challenge(id)
        end
        return release, finish
    end
    return { entries = entries, register = register }
end
