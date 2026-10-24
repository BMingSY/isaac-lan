-- A local door preview covers the handoff without changing the room or its AI.
return function(env)
    local departure, arrival, fill
    local function newUnlocks()
        return setmetatable({}, { __mode = "k" })
    end
    local unlocks, stairs = newUnlocks(), nil
    local fadeOut, fadeIn, timeout = 0.09, 0.12, 0.5
    local unlockTimeout = 0.25
    local outward = { { -1, 0 }, { 0, -1 }, { 1, 0 }, { 0, 1 } }
    local function now()
        return env.clock() / 1000
    end
    local function alpha()
        local t = now()
        if arrival then
            if not arrival.at then
                return arrival.alpha
            end
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
    local function finish(blockMovement)
        local value = alpha()
        departure = nil
        arrival = value > 0
                and {
                    at = not blockMovement and now() or nil,
                    alpha = value,
                    blockMovement = blockMovement,
                }
            or nil
    end
    local function movementBlocked()
        return alpha() > 0 and arrival ~= nil and arrival.blockMovement
    end
    local function begin()
        if not departure then
            departure, arrival = now(), nil
        end
    end
    local function preview(room, player, position, direction, owner)
        owner = owner or player
        local attempts = unlocks[owner]
        if not attempts then
            attempts = {}
            unlocks[owner] = attempts
        end
        local t, pending = now(), nil
        local variants = env.doorVariants
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            local axis = outward[slot % 4 + 1]
            local dx, dy =
                door and door.Position.X - position.X or 0,
                door and door.Position.Y - position.Y or 0
            local along, across = dx * axis[1] + dy * axis[2], math.abs(dx * axis[2] - dy * axis[1])
            local approaching = door
                and along > 0
                and along < 64
                and across < 16
                and direction.X * axis[1] + direction.Y * axis[2] > 0
            if not approaching or door:IsOpen() then
                attempts[slot] = nil
            elseif room:IsClear() and door:IsLocked() then
                local variant = door:GetVariant()
                local cost = variant == variants.DOOR_LOCKED and 1
                    or variant == variants.DOOR_LOCKED_DOUBLE and 2
                if cost and (player:HasGoldenKey() or player:GetNumKeys() >= cost) then
                    -- An affordance is only a bounded approach preview. It never
                    -- calls TryUnlock, spends keys, opens a door or selects a room.
                    local attempt = attempts[slot] or t
                    attempts[slot] = attempt
                    if t - attempt < unlockTimeout then
                        pending = slot
                    end
                end
            end
        end
        local lookahead = env.vector(position.X + direction.X * 12, position.Y + direction.Y * 12)
        local grid = room:GetGridEntityFromPos(lookahead)
        local entrance = grid and grid:GetType() == env.gridTypes.GRID_STAIRS and grid.Position
        if entrance then
            local dx, dy = entrance.X - position.X, entrance.Y - position.Y
            if dx * dx + dy * dy < 32 * 32 and dx * direction.X + dy * direction.Y > 0 then
                if not stairs then
                    stairs = {
                        owner = owner,
                        x = entrance.X,
                        y = entrance.Y,
                        dx = direction.X,
                        dy = direction.Y,
                    }
                    begin()
                end
            end
        end
        if stairs and stairs.owner == owner then
            local dx, dy = stairs.x - position.X, stairs.y - position.Y
            if
                stairs.dx * direction.X + stairs.dy * direction.Y <= 0
                or dx * dx + dy * dy > 48 * 48
            then
                finish(false)
                stairs = nil
            end
        end
        return pending
    end
    return {
        begin = begin,
        preview = preview,
        arrive = function()
            finish(true)
            unlocks, stairs = newUnlocks(), nil
        end,
        cancel = function()
            finish(false)
        end,
        movementBlocked = movementBlocked,
        filterInput = function(bytes)
            if not movementBlocked() then
                return bytes
            end
            -- Match the local movement preview during arrival. Keep held fire
            -- intact so the fade cannot release a charged weapon.
            local movementBytes, actionBytes, movementMask = 4 * 2, 16 * 2, 0xf
            local edges, tail = string.unpack(">I2", bytes, actionBytes + 1)
            return string.rep("\0", movementBytes)
                .. bytes:sub(movementBytes + 1, actionBytes)
                .. string.pack(">I2", edges & ~movementMask)
                .. bytes:sub(tail)
        end,
        alpha = alpha,
        render = function()
            -- Loading a new room can block between its commit and first draw.
            -- Keep input held until the reveal is actually presented locally.
            if arrival and not arrival.at then
                arrival.at = now()
            end
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
            unlocks, stairs = newUnlocks(), nil
        end,
    }
end
