return function(root)
    local peers = {}
    local actor1, actor2 = { hash = 11, type = 0 }, { hash = 22, type = 0 }
    function actor1:GetPlayerType()
        return self.type
    end
    function actor2:GetPlayerType()
        return self.type
    end
    local function peer(slot)
        local p = {
            slot = slot,
            actors = { actor1, actor2 },
            positions = {
                ["0"] = { index = 84, dimension = 0 },
                ["1"] = { index = 84, dimension = 0 },
            },
            inbox = {},
            sent = {},
            tick = 0,
            epoch = 0,
            now = 0,
            active = 1,
            ready = 1,
            logs = {},
            settings = {},
            scope = nil,
        }
        peers[slot] = p
        local env = setmetatable({}, { __index = _G })
        env._G = env
        p.env = env
        local native = {}
        env._IsaacLan = native
        env._IsaacLanModules = {}
        env.GetPtrHash = function(actor)
            return actor.hash
        end
        env.Game = function()
            return {
                GetNumPlayers = function()
                    return p.scope ~= nil and 1 or #p.actors
                end,
            }
        end
        env.Isaac = {
            DebugString = function(message)
                p.logs[#p.logs + 1] = message
            end,
            GetPlayer = function(index)
                return p.actors[p.scope ~= nil and p.scope + 1 or index + 1]
            end,
        }
        function native.api_info()
            return {
                active = p.active,
                ready = p.ready,
                authority = slot == 0 and 1 or 0,
                slot = slot,
                players = 2,
                connected = 3,
                worldEpoch = p.epoch,
                tick = p.tick,
                nowMs = p.now,
                runId = string.rep("a", 32),
            }
        end
        function native.api_nonce()
            return string.rep(tostring(slot + 1), 32)
        end
        function native.api_send(destination, bytes)
            p.sent[#p.sent + 1] = { destination = destination, bytes = bytes }
            peers[destination].inbox[#peers[destination].inbox + 1] =
                { sender = slot, bytes = bytes }
            return true
        end
        function native.api_receive()
            local message = table.remove(p.inbox, 1)
            if message then
                return message.sender, message.bytes
            end
        end
        function native.api_actors()
            return { { index = 0, owner = 1, role = 1 }, { index = 1, owner = 2, role = 1 } }
        end
        function native.rooms_positions()
            return p.positions
        end
        function native.api_with_local_view(fn)
            local previous = p.scope
            p.scope = slot
            local ok, errorMessage = pcall(fn)
            p.scope = previous
            if not ok then
                error(errorMessage, 0)
            end
            return true
        end
        function native.api_with_owner(owner, fn)
            local previous = p.scope
            p.scope = owner
            local ok, errorMessage = pcall(fn)
            p.scope = previous
            if not ok then
                error(errorMessage, 0)
            end
            return true
        end
        function native.api_move(owner, index, dimension)
            p.queuedMove = { owner = owner, index = index, dimension = dimension }
            return true
        end
        function native.api_cancel_move()
            p.queuedMove = nil
        end
        function native.api_mod_info()
            return p.modInfo
        end
        function native.api_setting(id, enabled)
            if enabled == nil then
                return p.settings[id] ~= false
            end
            p.settings[id] = enabled
            return true
        end
        for _, name in ipairs({
            "api/codec",
            "api/lifecycle",
            "api/actions",
            "api/public",
            "compat/mods/wrapping",
            "compat/mods/registry",
        }) do
            env._IsaacLanModules[name] =
                assert(loadfile(root .. "/src/bridge/" .. name .. ".lua", "t", env))()
        end
        p.bridge = env._IsaacLanModules["api/public"]
        p.api = env.IsaacLAN
        return p
    end

    return { peer = peer, peers = peers, actors = { actor1, actor2 } }
end
