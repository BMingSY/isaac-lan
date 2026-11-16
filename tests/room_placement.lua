local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/runtime/room_placement.lua")
local collision = {
    COLLISION_NONE = 0,
    COLLISION_PIT = 1,
    COLLISION_OBJECT = 2,
    COLLISION_SOLID = 3,
    COLLISION_WALL = 4,
    COLLISION_WALL_EXCEPT_PLAYER = 5,
}
local function vector(x, y)
    return { X = x, Y = y }
end
local tiles, bodies, topDown = {}, {}, true
local room = {}
function room:GetGridSize()
    return 25
end
function room:GetGridPosition(index)
    return vector(20 + index % 5 * 40, 20 + (index // 5) * 40)
end
function room:IsPositionInRoom(point, radius)
    return point.X - radius >= 0
        and point.Y - radius >= 0
        and point.X + radius < 200
        and point.Y + radius < 200
end
function room:GetGridCollisionAtPos(point)
    return tiles[math.floor(point.X / 40) + math.floor(point.Y / 40) * 5] or 0
end
local placement = factory({
    game = function()
        return {
            GetRoom = function()
                return room
            end,
            GetNumPlayers = function()
                return #bodies
            end,
        }
    end,
    player = function(index)
        return bodies[index + 1]
    end,
    vector = vector,
    collision = collision,
    canPlace = function()
        return topDown
    end,
})
local function body(x, y)
    return {
        Position = vector(x, y),
        Velocity = vector(4, 2),
        Size = 10,
        CanFly = false,
        IsCoopGhost = function(self)
            return self.ghost
        end,
    }
end
local function unchanged(p, door)
    local position, velocity = p.Position, p.Velocity
    assert(placement.arrive(door))
    assert(p.Position == position and p.Velocity == velocity, "Valid arrival was moved")
end
for _, obstacle in ipairs({
    collision.COLLISION_SOLID,
    collision.COLLISION_OBJECT,
    collision.COLLISION_PIT,
}) do
    tiles = { [12] = obstacle }
    bodies = { body(100, 100), body(100, 100) }
    bodies[2].CanFly = true
    assert(placement.arrive(-1))
    assert(bodies[1].Position.X == 100 and bodies[1].Position.Y == 60)
    assert(bodies[1].Velocity.X == 0 and bodies[1].Velocity.Y == 0)
    assert(bodies[2].Position.X == 100 and bodies[2].Position.Y == 100)
    assert(bodies[2].Velocity.X == 4)
    unchanged(bodies[1], -1)
end
tiles = { [12] = collision.COLLISION_SOLID }
bodies = { body(80, 100) } -- Center's cell edge is not sufficient clearance.
assert(placement.arrive(-1))
assert(bodies[1].Position.X == 60 and bodies[1].Position.Y == 100)
bodies = { body(100, 100) }
bodies[1].ghost = true
unchanged(bodies[1], -1)
tiles[12] = collision.COLLISION_WALL
assert(placement.arrive(-1))
assert(bodies[1].Position.Y == 60, "A flying ghost was placed in a wall")
tiles[12] = collision.COLLISION_WALL_EXCEPT_PLAYER
bodies = { body(100, 100) }
unchanged(bodies[1], -1)
tiles = {}
bodies = { body(-80, 100) }
assert(placement.arrive(-1) and bodies[1].Position.X == 20)
-- Large bodies need space for their full footprint, including adjacent cells.
tiles = { [13] = collision.COLLISION_SOLID }
bodies = { body(100, 100) }
bodies[1].Size = 25
assert(placement.arrive(-1))
assert(bodies[1].Position.X == 60 and bodies[1].Position.Y == 100)
-- A failed multi-body placement commits nothing.
for i = 0, 24 do
    tiles[i] = collision.COLLISION_SOLID
end
bodies = { body(-80, 100), body(100, 100) }
bodies[1].CanFly = true
local firstPosition, firstVelocity = bodies[1].Position, bodies[1].Velocity
local before, velocity = bodies[2].Position, bodies[2].Velocity
assert(not placement.arrive(-1))
assert(bodies[1].Position == firstPosition and bodies[1].Velocity == firstVelocity)
assert(bodies[2].Position == before and bodies[2].Velocity == velocity)
unchanged(bodies[2], 0) -- Door placement is owned by native entry.
topDown = false
unchanged(bodies[2], -1) -- Side-scrolling platforms retain native placement.
print("PASS doorless arrival rocks/pits/walls, flight, ghosts, bounds, size and atomic failure")
