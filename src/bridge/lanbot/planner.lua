return function(nav)
    local planner = {}
    local methods = {}
    methods.__index = methods
    function planner.new()
        return setmetatable({ nodes = {}, blocked = {}, mode = "run", bossClaims = {} }, methods)
    end
    function methods:cancel()
        self.goal, self.path, self.pathAt, self.stuckAt, self.lastPosition = nil, nil, nil, nil, nil
        self.advance, self.pendingPickup = false, nil
    end
    function methods:observe(obs)
        if self.world ~= obs.world then
            self.nodes, self.blocked, self.bossClaims = {}, {}, {}
            self:cancel()
            self.world, self.room = obs.world, nil
        end
        local node = self.nodes[obs.room] or { visits = 0, edges = {} }
        self.nodes[obs.room] = node
        if self.room ~= obs.room then
            local previous = self.nodes[self.room]
            if previous then
                for _, edge in pairs(previous.edges) do
                    if edge.to == obs.room then
                        edge.open, edge.locked = true, false
                    end
                end
            end
            self.goal, self.path, self.lastPosition, self.stuckAt = nil, nil, nil, nil
            node.visits = node.visits + 1
            self.room = obs.room
        end
        node.clear, node.exit = obs.clear, obs.exit
        for _, door in ipairs(obs.doors) do
            node.edges[door.slot] = door
        end
        if
            self.pendingPickup
            and self.pendingPickup.room == obs.room
            and obs.actor.items > self.pendingPickup.items
        then
            self.bossClaims[obs.room] = (self.bossClaims[obs.room] or 0) + 1
            self.pendingPickup = nil
        end
    end
    function methods:available(id, frame)
        return not self.blocked[id] or self.blocked[id] <= frame
    end
    function methods:nextExit()
        for _, node in pairs(self.nodes) do
            if node.exit then
                self.advance = true
                self.goal, self.path = nil, nil
                return true
            end
        end
        return false
    end
    local function goalForDoor(door)
        return {
            x = door.x + door.dx * 32,
            y = door.y + door.dy * 32,
            id = "door:" .. door.slot .. ":" .. door.to,
            door = door,
            task = "move_to_door",
        }
    end
    function methods:routes(obs, style, exitOnly)
        local queue, seen = { { room = obs.room, distance = 0 } }, { [obs.room] = true }
        local best, bestScore, resourceBlocked
        local cursor = 1
        while cursor <= #queue and cursor <= 512 do
            local entry = queue[cursor]
            cursor = cursor + 1
            local node = self.nodes[entry.room]
            if node and node.exit and entry.first and (exitOnly or self.mode == "run") then
                local score = 2000 - entry.distance * 20
                if not bestScore or score > bestScore then
                    best, bestScore = goalForDoor(entry.first), score
                end
            end
            if node then
                for slot = 0, 7 do
                    local edge = node.edges[slot]
                    if edge and not edge.skip and (edge.open or edge.locked) then
                        local first = entry.first or edge
                        local id = "door:" .. first.slot .. ":" .. first.to
                        if edge.locked and obs.actor.keys < 1 then
                            resourceBlocked = true
                        elseif self:available(id, obs.frame) then
                            local nextNode = self.nodes[edge.to]
                            if not nextNode then
                                if not exitOnly then
                                    local score = 100 - entry.distance * 20 - slot * 0.01
                                    if self.mode == "run" then
                                        score = score
                                            + (edge.boss and 350 or edge.treasure and 250 or 0)
                                    end
                                    if style == "cautious" and edge.cost then
                                        score = score - 300
                                    end
                                    if not bestScore or score > bestScore then
                                        best, bestScore = goalForDoor(first), score
                                    end
                                end
                            elseif not seen[edge.to] then
                                seen[edge.to] = true
                                queue[#queue + 1] =
                                    { room = edge.to, first = first, distance = entry.distance + 1 }
                            end
                        end
                    end
                end
            end
        end
        return best, resourceBlocked
    end
    function methods:choose(obs, mode, style)
        self.mode = mode
        if not obs.clear then
            return nil, "room_not_clear"
        end
        local pickup, score
        for _, item in ipairs(obs.pickups) do
            if self:available(item.id, obs.frame) and (mode ~= "hold" or item.heal) then
                local allowed = not (
                    obs.boss
                    and item.collectible
                    and (self.bossClaims[obs.room] or 0) >= 1
                )
                local value = nav.distance(obs.actor, item)
                    - (item.heal and 400 or item.collectible and 200 or 0)
                if allowed and (not score or value < score) then
                    pickup, score = item, value
                end
            end
        end
        if pickup and not self.advance then
            if obs.boss and pickup.collectible then
                self.pendingPickup = { room = obs.room, items = obs.actor.items }
            end
            return { x = pickup.x, y = pickup.y, id = pickup.id, task = "pickup" }
        end
        if mode == "hold" then
            return nil, "room_clear"
        end
        if obs.exit and (mode == "run" or self.advance) then
            if not self.advance and not obs.partyReady then
                return nil, "wait_for_party"
            end
            if not self:available("exit", obs.frame) then
                return nil, "route_blocked"
            end
            return { x = obs.exit.x, y = obs.exit.y, id = "exit", task = "move_to_exit" }
        end
        local route, resourceBlocked = self:routes(obs, style, self.advance)
        if route then
            return route
        end
        return nil,
            resourceBlocked and "resource_missing"
                or self.advance and "exit_unreachable"
                or "exploration_complete"
    end
    function methods:waypoint(obs, goal)
        if not goal then
            self.goal, self.path = nil, nil
            return nil
        end
        local p, door = obs.actor, goal.door
        if not self.goal or self.goal.id ~= goal.id then
            self.goal, self.path, self.lastPosition, self.stuckAt = goal, nil, nil, nil
        end
        if self.lastPosition and nav.distance(p, self.lastPosition) >= 5 then
            self.lastPosition, self.stuckAt = { x = p.x, y = p.y }, obs.frame
        elseif not self.lastPosition then
            self.lastPosition, self.stuckAt = { x = p.x, y = p.y }, obs.frame
        elseif obs.frame - self.stuckAt > 120 and nav.distance(p, goal) > 16 then
            self.blocked[goal.id] = obs.frame + 300
            self.goal, self.path, self.lastPosition = nil, nil, nil
            return nil, "route_blocked"
        end
        if door and nav.distance(p, door) < 45 then
            return goal
        end
        local destination = door and { x = door.x - door.dx * 32, y = door.y - door.dy * 32 }
            or goal
        if nav.line(obs.map, p, destination, p.radius, door) then
            return destination
        end
        if
            not self.goal
            or self.goal.id ~= goal.id
            or not self.path
            or obs.frame - (self.pathAt or 0) >= 30
        then
            self.goal, self.pathAt = goal, obs.frame
            self.path = nav.path(obs.map, p, destination, p.radius, 640, door)
        end
        if not self.path then
            self.blocked[goal.id] = obs.frame + 180
            return nil, "route_blocked"
        end
        while #self.path > 1 and nav.distance(p, self.path[1]) < 14 do
            table.remove(self.path, 1)
        end
        return self.path[1]
    end
    return planner
end
