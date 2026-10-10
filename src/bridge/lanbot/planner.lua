return function(nav)
    local planner = {}
    local methods = {}
    methods.__index = methods
    function planner.new()
        return setmetatable({ nodes = {}, blocked = {}, mode = "run", bossClaims = {} }, methods)
    end
    function methods:cancel()
        self.goal, self.path, self.pathAt, self.stuckAt, self.lastPosition = nil, nil, nil, nil, nil
        self.advance, self.pendingPickup, self.entry, self.buttonWait = false, nil, nil, nil
        self.waitingTrap = nil
        self.exitContact = nil
        self.needsArrival = true
    end
    function methods:observe(obs)
        if self.world ~= obs.world then
            self.nodes, self.blocked, self.bossClaims = {}, {}, {}
            self:cancel()
            self.world, self.room = obs.world, nil
        end
        local changed = self.room ~= obs.room
        local previousRoom = self.room
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
            self.waitingTrap = nil
            self.exitContact = nil
            node.visits = node.visits + 1
            self.room = obs.room
        end
        if changed or self.needsArrival then
            self.entry, self.needsArrival, self.buttonWait = nil, false, nil
            for _, door in ipairs(obs.doors) do
                local inward = -(
                    (obs.actor.x - door.x) * door.dx + (obs.actor.y - door.y) * door.dy
                )
                local across =
                    math.abs((obs.actor.x - door.x) * door.dy - (obs.actor.y - door.y) * door.dx)
                if inward < 70 and across < 28 and (not self.entry or door.to == previousRoom) then
                    self.entry = door
                end
            end
        end
        node.clear, node.exit = obs.clear, obs.exit
        node.edges = {}
        for _, door in ipairs(obs.doors) do
            node.edges[door.slot] = door
        end
        if self.pendingPickup and self.pendingPickup.room == obs.room then
            local found
            for _, item in ipairs(obs.pickups) do
                if item.id == self.pendingPickup.id then
                    found = item
                    break
                end
            end
            -- Swapping an active item does not increase the inventory count.
            -- Count a disappeared reward after reaching it conservatively.
            if
                obs.actor.items > self.pendingPickup.items
                or self.pendingPickup.near and not found
            then
                self.bossClaims[obs.room] = (self.bossClaims[obs.room] or 0) + 1
                self.pendingPickup = nil
            elseif
                found
                and nav.distance(obs.actor, found)
                    <= obs.actor.radius + (found.radius or 10) + 8
            then
                self.pendingPickup.near = true
            end
        end
    end
    function methods:available(id, frame)
        local untilFrame = self.blocked[(self.room or "") .. "/" .. id]
        return not untilFrame or untilFrame <= frame
    end
    function methods:block(id, frame)
        self.blocked[self.room .. "/" .. id] = frame
    end
    function methods:arrival(obs)
        local door = self.entry
        if not door then
            return nil
        end
        local inward = -((obs.actor.x - door.x) * door.dx + (obs.actor.y - door.y) * door.dy)
        if inward >= 70 then
            self.entry = nil
            return nil
        end
        return {
            x = door.x - door.dx * 84,
            y = door.y - door.dy * 84,
            id = "arrival:" .. door.slot,
            door = door,
            entering = true,
            task = "leave_door",
        }
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
        local best, bestScore, resourceBlocked, pending
        local cursor = 1
        while cursor <= #queue and cursor <= 512 do
            local entry = queue[cursor]
            cursor = cursor + 1
            local node = self.nodes[entry.room]
            if node and node.exit and entry.first and exitOnly then
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
                        elseif
                            self:available(id, obs.frame)
                            and (
                                not self.blocked[entry.room .. "/door:" .. edge.slot .. ":" .. edge.to]
                                or self.blocked[entry.room .. "/door:" .. edge.slot .. ":" .. edge.to]
                                    <= obs.frame
                            )
                        then
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
                                    if self.goal and self.goal.id == id then
                                        score = score + 20
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
                        else
                            pending = true
                        end
                    end
                end
            end
        end
        return best, resourceBlocked, pending
    end
    local function retreatFromClosedExit(obs, contact)
        local best, distance, waiting
        for _, zone in ipairs(obs.map.zones or {}) do
            -- Retreat beyond the observed contact boundary: braking near a
            -- waypoint must not leave an actor inside the wait-clear region.
            local radius = contact == zone.id and zone.contactRadius + obs.actor.radius + 24
                or zone.radius + obs.actor.radius + 12
            if
                zone.exit
                and (zone.closed or contact == zone.id)
                and nav.distance(obs.actor, zone) < radius - 2
            then
                waiting = true
                for direction = 0, 7 do
                    local angle = direction * math.pi / 4
                    local goal = {
                        x = zone.x + math.cos(angle) * radius,
                        y = zone.y + math.sin(angle) * radius,
                        id = "exit-wait:" .. zone.id,
                        task = "wait_for_exit",
                    }
                    local travel = nav.distance(obs.actor, goal)
                    if
                        nav.line(obs.map, obs.actor, goal, obs.actor.radius)
                        and (not distance or travel < distance)
                    then
                        best, distance = goal, travel
                    end
                end
            end
        end
        return best, waiting
    end
    function methods:choose(obs, mode, style)
        self.mode = mode
        if mode ~= "hold" then
            local button, distance
            for _, candidate in ipairs(obs.buttons or {}) do
                if self:available(candidate.id, obs.frame) then
                    local value = nav.distance(obs.actor, candidate)
                        - (self.goal and self.goal.id == candidate.id and 25 or 0)
                    if not distance or value < distance then
                        button, distance = candidate, value
                    end
                end
            end
            if button then
                if nav.distance(obs.actor, button) <= 8 then
                    if not self.buttonWait or self.buttonWait.id ~= button.id then
                        self.buttonWait = { id = button.id, at = obs.frame }
                    elseif obs.frame - self.buttonWait.at > 90 then
                        self:block(button.id, obs.frame + 300)
                        self.buttonWait = nil
                        return nil, "button_not_activated"
                    end
                else
                    self.buttonWait = nil
                end
                return { x = button.x, y = button.y, id = button.id, task = "press_button" }
            elseif #(obs.buttons or {}) > 0 then
                return nil, "button_not_activated"
            end
            self.buttonWait = nil
        end
        if not obs.clear then
            return nil, "room_not_clear"
        end
        local retreat, waiting = retreatFromClosedExit(obs)
        if waiting then
            return retreat, retreat and nil or "exit_closed"
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
                if
                    not self.pendingPickup
                    or self.pendingPickup.id ~= pickup.id
                    or self.pendingPickup.room ~= obs.room
                then
                    self.pendingPickup =
                        { room = obs.room, items = obs.actor.items, id = pickup.id }
                end
                if
                    nav.distance(obs.actor, pickup)
                    <= obs.actor.radius + (pickup.radius or 10) + 8
                then
                    self.pendingPickup.near = true
                end
            end
            return { x = pickup.x, y = pickup.y, id = pickup.id, task = "pickup" }
        end
        if mode == "hold" then
            return nil, "room_clear"
        end
        local function exitGoal()
            if not self.advance and not obs.partyReady then
                return nil, "wait_for_party"
            end
            if not self:available("exit", obs.frame) then
                return nil, "route_blocked"
            end
            local exit = obs.exit
            if exit.contactWait then
                local frame = assert(obs.simulationTick, "Missing authoritative simulation clock")
                local contact = self.exitContact
                if not contact or contact.id ~= exit.id then
                    contact = { id = exit.id }
                    self.exitContact = contact
                end
                if contact.armed and exit.contactBlocked and frame - contact.armed > 90 then
                    contact.armed, contact.clearAt = nil, nil
                end
                if not contact.armed then
                    if exit.contactBlocked then
                        contact.clearAt = nil
                    else
                        contact.clearAt = contact.clearAt or frame
                        if frame - contact.clearAt >= 15 then
                            contact.armed = frame
                        end
                    end
                    if not contact.armed then
                        local retreat = retreatFromClosedExit(obs, exit.id)
                        return retreat, retreat and nil or "wait_for_exit_contact"
                    end
                end
            else
                self.exitContact = nil
            end
            local x, y = exit.x, exit.y
            if exit.kind == "bigchest" then
                -- Big chests have a wide horizontal collision shape. Touch
                -- from the side while preserving a co-located Void portal's
                -- protected center, rather than steering into that portal.
                local offset = exit.radius + obs.actor.radius + 6
                local distance
                for _, side in ipairs({ -1, 1 }) do
                    local candidate = { x = exit.x + side * offset, y = exit.y }
                    local travel = nav.distance(obs.actor, candidate)
                    if
                        nav.passable(obs.map, candidate.x, candidate.y, obs.actor.radius)
                        and (not distance or travel < distance)
                    then
                        x, y, distance = candidate.x, candidate.y, travel
                    end
                end
                if not distance then
                    return nil, "exit_unreachable"
                end
            end
            return {
                x = x,
                y = y,
                id = "exit",
                exit = obs.exit,
                task = "move_to_exit",
            }
        end
        if self.advance and obs.exit then
            return exitGoal()
        end
        local route, resourceBlocked, pending = self:routes(obs, style, self.advance)
        if route then
            return route
        end
        if pending then
            return nil, "route_blocked"
        end
        if mode == "run" or self.advance then
            if obs.exit then
                return exitGoal()
            end
            route = self:routes(obs, style, true)
            if route then
                return route
            end
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
            self.waitingTrap = nil
        end
        if self.waitingTrap then
            self.stuckAt = obs.frame
        end
        if self.lastPosition and nav.distance(p, self.lastPosition) >= 5 then
            self.lastPosition, self.stuckAt = { x = p.x, y = p.y }, obs.frame
        elseif not self.lastPosition then
            self.lastPosition, self.stuckAt = { x = p.x, y = p.y }, obs.frame
        elseif obs.frame - self.stuckAt > 120 and nav.distance(p, goal) > 16 then
            self:block(goal.id, obs.frame + 300)
            self.goal, self.path, self.lastPosition = nil, nil, nil
            return nil, "route_blocked"
        end
        if door and not goal.entering and nav.distance(p, door) < 45 then
            return goal
        end
        local destination = door
                and not goal.entering
                and { x = door.x - door.dx * 32, y = door.y - door.dy * 32 }
            or goal
        if nav.line(obs.map, p, destination, p.radius, door) then
            self.waitingTrap = nil
            return destination
        end
        if
            not self.goal
            or self.goal.id ~= goal.id
            or not self.path
            or obs.frame - (self.pathAt or 0) >= 30
            or not nav.line(obs.map, p, self.path[1], p.radius, door)
        then
            self.goal, self.pathAt = goal, obs.frame
            self.path = nav.path(obs.map, p, destination, p.radius, 640, door)
        end
        if not self.path then
            local spatial = obs.map.timed
                and nav.path(obs.map, p, destination, p.radius, 640, door, true)
            if spatial then
                self.waitingTrap = self.waitingTrap or obs.frame
                self.stuckAt = obs.frame
                if obs.frame - self.waitingTrap > 1200 then
                    return nil, "needs_manual"
                end
                return nav.approachTimed(obs.map, p, spatial, p.radius, door), "wait_for_trap"
            end
            self:block(goal.id, obs.frame + 180)
            return nil, "route_blocked"
        end
        self.waitingTrap = nil
        while
            #self.path > 1
            and (
                nav.distance(p, self.path[1]) < 14
                or nav.line(obs.map, p, self.path[2], p.radius, door)
            )
        do
            table.remove(self.path, 1)
        end
        return self.path[1]
    end
    return planner
end
