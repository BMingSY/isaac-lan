-- Numeric slots are local to this Lua state. Snapshots and public views use the
-- qualified name, while the lobby negotiates the declaration's fingerprint.
return function(native, codec)
    local entries, byId = {}, {}
    local function integer(value, low, high)
        return math.type(value) == "integer" and value >= low and value <= high
    end
    local function register(namespace, def)
        assert(type(def) == "table", "invalid_challenge")
        local key = def.id
        if integer(key, 0, 0xffff) then
            key = tostring(key)
        end
        assert(
            type(key) == "string" and #key <= 64 and key:match("^[%w_.%-]+$"),
            "invalid_challenge_id"
        )
        local qualifiedId = namespace .. ":" .. key
        assert(not byId[qualifiedId], "duplicate_challenge_id: " .. qualifiedId)
        local version = def.version == nil and 1 or def.version
        local character, difficulty, count =
            def.character or 65535, def.difficulty or 0, def.players or 0
        assert(
            integer(version, 1, 65535)
                and type(def.name) == "string"
                and #def.name > 0
                and #def.name <= 96
                and not def.name:find("[%z%c]")
                and integer(character, 0, 65535)
                and integer(difficulty, 0, 3)
                and (count == 0 or integer(count, 2, native.max_players))
                and (def.roomOptionsLocked == nil or type(def.roomOptionsLocked) == "boolean")
                and (def.step == nil or type(def.step) == "function")
                and (def.reset == nil or type(def.reset) == "function")
                and (def.canEnter == nil or type(def.canEnter) == "function"),
            "invalid_challenge"
        )
        local stateless = def.capture == nil and def.apply == nil
        assert(
            stateless or (type(def.capture) == "function" and type(def.apply) == "function"),
            "challenge_snapshot_pair_required"
        )
        local locked = def.roomOptionsLocked == true
        local contract = table.concat(
            { qualifiedId, version, character, difficulty, count, locked and 1 or 0 },
            "/"
        )
        local slot = assert(
            native.api_register_challenge(
                version,
                def.name,
                character,
                difficulty,
                count,
                contract,
                locked
            ),
            "challenge_registration_rejected"
        )
        local entry, previous = { key = qualifiedId, canEnter = def.canEnter }, nil
        function entry.reset()
            previous = nil
            if def.reset then
                def.reset()
            end
        end
        if def.step then
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
        end
        if def.capture then
            function entry.snapshot()
                return codec.encode(def.capture())
            end
            function entry.apply(payload)
                def.apply(codec.decode(payload))
            end
        end
        entries[slot], byId[qualifiedId] = entry, entry
        local function release()
            if entries[slot] ~= entry then
                return
            end
            native.api_remove_challenge(slot)
            entries[slot], byId[qualifiedId] = nil, nil
            entry.reset()
        end
        local function finish()
            return entries[slot] == entry and native.net_finish_challenge(slot)
        end
        return release, finish, qualifiedId
    end
    return { entries = entries, register = register }
end
