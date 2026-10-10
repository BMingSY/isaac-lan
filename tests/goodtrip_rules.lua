local root = arg[1] or "."
local runtime = assert(loadfile(root .. "/tests/fixtures/api_runtime.lua"))()(root)
local host, guest = runtime.peer(0), runtime.peer(1)
local native = host.env._IsaacLan
local actor = runtime.actors[2]
local rooms, curses, stage, doors, entities = {}, 0, 1, {}, {}
local function resetRooms()
    rooms = {
        [84] = {
            GridIndex = 84,
            SafeGridIndex = 84,
            ListIndex = 0,
            Clear = true,
            VisitedCount = 1,
            Data = { Type = 1, Name = "Start", Shape = 1 },
        },
        [71] = {
            GridIndex = 71,
            SafeGridIndex = 71,
            ListIndex = 1,
            Clear = true,
            VisitedCount = 1,
            Data = { Type = 1, Name = "Normal", Shape = 1 },
        },
        [72] = {
            GridIndex = 72,
            SafeGridIndex = 72,
            ListIndex = 2,
            Clear = true,
            VisitedCount = 1,
            Data = { Type = 1, Name = "Normal", Shape = 1 },
        },
    }
    curses, stage, doors, entities = 0, 1, {}, {}
    actor.damage, actor.hp, actor.dead, actor.flat, actor.flying = 0, 6, false, false, false
    host.positions["1"].index, guest.positions["1"].index = 84, 84
    host.queuedMove = nil
end
function actor:IsDead()
    return self.dead
end
function actor:GetHearts()
    return self.hp
end
function actor:GetSoulHearts()
    return 0
end
function actor:GetBlackHearts()
    return 0
end
function actor:GetMaxHearts()
    return 6
end
function actor:IsFlying()
    return self.flying
end
function actor:HasTrinket()
    return self.flat
end
function actor:HasCollectible()
    return false
end
function actor:TakeDamage(amount)
    self.damage = self.damage + amount
    self.hp = self.hp - amount
    if self.hp <= 0 then
        self.dead = true
    end
end
host.env.EntityRef = function(player)
    return player
end
host.env.LevelCurse = { CURSE_OF_THE_LOST = 1, CURSE_OF_MAZE = 2 }
host.env.DamageFlag = { DAMAGE_CURSED_DOOR = 1, DAMAGE_NO_PENALTIES = 2 }
local level = {}
function level:GetRoomByIdx(index)
    return rooms[index]
end
function level:GetCurrentRoomDesc()
    return rooms[host.positions[tostring(host.scope or 0)].index]
end
function level:GetStage()
    return stage
end
function level:GetCurses()
    return curses
end
function level:RemoveCurses()
    error("GoodTrip changed global curses")
end
local room = {}
function room:GetDoor(slot)
    return doors[slot]
end
host.env.Game = function()
    return {
        GetLevel = function()
            return level
        end,
        GetRoom = function()
            return room
        end,
        IsGreedMode = function()
            return false
        end,
    }
end
host.env.Isaac.GetRoomEntities = function()
    return entities
end
local authority =
    assert(loadfile(root .. "/src/bridge/compat/mods/goodtrip/authority.lua", "t", host.env))()
authority.install(host.api)
local lan = guest.api:RegisterMod({}, { id = authority.id, integrationVersion = 1 })
resetRooms()
host.bridge.commit()
guest.bridge.commit()
local function execute(options)
    options = options or {}
    host.tick = host.tick + 100
    guest.tick = host.tick
    host.now, guest.now = host.now + 100, guest.now + 100
    guest.bridge.commit()
    host.bridge.actions.poll()
    guest.bridge.actions.poll()
    authority.observe()
    local result
    assert(
        lan:RequestAction(
            "travel",
            { index = options.index or 71, dimension = options.dimension or 0 },
            function(value)
                result = value
            end
        )
    )
    local packet = guest.sent[#guest.sent].bytes
    if options.duplicate then
        host.inbox[#host.inbox + 1] = { sender = 1, bytes = packet }
    end
    host.bridge.actions.step()
    local legs = 0
    for _ = 1, 5 do
        if host.queuedMove then
            local move = host.queuedMove
            host.queuedMove = nil
            host.positions[tostring(move.owner)] =
                { index = move.index, dimension = move.dimension }
            legs = legs + 1
        end
        host.bridge.commit()
        guest.bridge.actions.poll()
        if result then
            break
        end
    end
    assert(result, "GoodTrip result missing")
    return result, legs
end
rooms[84].Data.Type = 10
local result = execute({ duplicate = true })
assert(
    result.status == "applied" and actor.damage == 1 and host.positions["1"].index == 71,
    "Curse cost or duplicate handling wrong"
)
local cases = {
    {
        code = "source_not_clear",
        change = function()
            rooms[84].Clear = false
        end,
    },
    {
        code = "map_hidden",
        change = function()
            curses = 1
        end,
    },
    {
        code = "destination_unavailable",
        change = function()
            rooms[71].VisitedCount = 0
        end,
    },
    {
        code = "source_locked",
        change = function()
            rooms[84].Data.Type = 6
        end,
    },
    {
        code = "chase_active",
        change = function()
            entities = { { Type = 867 } }
        end,
    },
    {
        code = "mom_locked",
        change = function()
            rooms[84].Data.Name = "Mom"
        end,
    },
    {
        code = "challenge_health",
        change = function()
            rooms[71].Data.Type = 11
            stage = 2
        end,
    },
    {
        code = "challenge_health",
        change = function()
            rooms[71].Data.Type = 11
            actor.hp = 4
        end,
    },
    {
        code = "secret_path_unknown",
        change = function()
            rooms[84].Data.Type = 7
        end,
    },
    { code = "dimension_mismatch", dimension = 1, change = function() end },
}
for _, case in ipairs(cases) do
    resetRooms()
    case.change()
    result = execute({ dimension = case.dimension })
    assert(
        result.status == "rejected"
            and result.code == case.code
            and actor.damage == 0
            and not host.queuedMove,
        "Rule failed: " .. case.code
    )
end
resetRooms()
rooms[71].Data.Type = 10
actor.flying = true
result = execute()
assert(result.status == "applied" and actor.damage == 0, "Flight charged curse entrance")
resetRooms()
rooms[84].Data.Type = 10
actor.flat = true
result = execute()
assert(result.status == "applied" and actor.damage == 0, "Flat File charged curse damage")
resetRooms()
rooms[84].Data.Type = 10
curses = 2
result = execute()
assert(
    result.status == "applied" and curses == 2 and actor.damage == 1,
    "Maze did not retain curse or destination"
)
resetRooms()
rooms[84].Data.Type = 10
actor.hp = 1
result = execute()
assert(
    result.status == "cancelled"
        and result.code == "player_dead"
        and actor.damage == 1
        and host.positions["1"].index == 84,
    "Death did not cancel pending migration"
)
-- Secret-room exits acknowledge the intermediate native room before the destination.
resetRooms()
rooms[84].Data.Type = 7
rooms[71].Data.Type = 10
rooms[71].VisitedCount = 0
local door = { Desc = { Variant = 8 }, TargetRoomIndex = 71, TargetRoomType = 10 }
function door:IsOpen()
    return true
end
doors[0] = door
result, legs = execute({ index = 72 })
assert(
    result.status == "applied"
        and legs == 2
        and actor.damage == 1
        and host.positions["1"].index == 72,
    "Secret route or completion wrong"
)
print("PASS GoodTrip authority conditions, curse cost, death, maze and secret route")
