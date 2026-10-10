-- One native session for exit protection, arrivals, buttons, timed spikes and
-- projectile avoidance. Fixtures arrange the world; LANBOT supplies all input.
local native = assert(_IsaacLan)
local host, port = _IsaacLanTest.host, _IsaacLanTest.port
local baseFrame = _IsaacLanFrame
local renders, linked, chosen, done = 0, false, false, false
local ownerSeed
local origin, center, selectedDoor, arrivedRoom, damage = nil, nil, nil, nil, 0
local baseline, exitPosition, minimumExit, spikeDamage, dodgeDamage, spikes, timedPlate
local spikeTransitions, spikeState, occupant = 0, nil, nil
local plates, spawned, results = {}, {}, {}
local trace = host and assert(io.open("./lan-test-digest-lanbot.csv", "w"))
if trace then
    trace:write("time_ms,tick,room,x,y,health,damage\n")
end
local function report(value)
    Isaac.DebugString("LAN_NETWORK " .. value)
end
local function command(value)
    local output = Isaac.ConsoleOutput
    if value == "status" then
        Isaac.ConsoleOutput = function(message)
            report((message:gsub("\n", "")))
            output(message)
        end
    end
    Isaac.ExecuteCommand("lanbot " .. value)
    Isaac.ConsoleOutput = output
end
local function check(name, passed, detail)
    results[#results + 1] = { name = name, passed = passed, detail = detail }
    report("LANBOT_CASE " .. name .. " passed=" .. tostring(passed) .. " " .. detail)
end
local function health(player)
    return player:GetHearts() + player:GetSoulHearts()
end
local function clean()
    command("off")
    local room = Game():GetRoom()
    for _, index in ipairs(spawned) do
        room:RemoveGridEntity(index, 0, false)
    end
    spawned = {}
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e.Type ~= EntityType.ENTITY_PLAYER then
            e:Remove()
        end
    end
    room:SetClear(true)
end
local function grid(position, kind)
    local room = Game():GetRoom()
    local index = room:GetGridIndex(position)
    room:RemoveGridEntity(index, 0, false)
    assert(room:SpawnGridEntity(index, kind, 0, 1234 + index, 0))
    spawned[#spawned + 1] = index
    return room:GetGridEntity(index)
end
local function heart(position)
    local pickup = Isaac.Spawn(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_HEART,
        HeartSubType.HEART_SOUL,
        position,
        Vector.Zero,
        nil
    ):ToPickup()
    pickup.Wait = 0
end
local function spikeWall(room)
    spikes = grid(center, GridEntityType.GRID_SPIKES_ONOFF)
    for index = 0, room:GetGridSize() - 1 do
        local position = room:GetGridPosition(index)
        if
            math.abs(position.X - center.X) < 1
            and math.abs(position.Y - center.Y) > 1
            and room:GetGridCollision(index) == GridCollisionClass.COLLISION_NONE
        then
            grid(position, GridEntityType.GRID_ROCK)
        end
    end
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = baseFrame()
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    native.test_gamepad(0)
    if s.verified >= 1510 and not done then
        done = true
        command("off")
        if host then
            trace:flush()
            trace:close()
            local file = assert(io.open("./lan-test-digest-lanbot.txt", "w"))
            for _, result in ipairs(results) do
                file:write(
                    result.name,
                    " passed=",
                    tostring(result.passed),
                    " ",
                    result.detail,
                    "\n"
                )
            end
            file:close()
        end
        local passed = not host or #results == 7
        if host then
            for _, result in ipairs(results) do
                passed = passed and result.passed
            end
        end
        assert(passed, "LANBOT behavior checks failed; inspect LANBOT_CASE records")
        report("PASS lanbot behavior suite")
    end
    return s
end
local owner = { Name = "LANBOT damage observer" }
local damageCallback = function(_, e)
    if host and e:ToPlayer() and e.InitSeed == ownerSeed then
        damage = damage + 1
    end
end
Isaac.AddCallback(owner, ModCallbacks.MC_ENTITY_TAKE_DMG, damageCallback)

local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, b)
        before(t, n, b)
        if not host or done then
            return
        end
        local room, player = Game():GetRoom(), Isaac.GetPlayer(native.rooms_heads()["0"])
        trace:write(
            string.format(
                "%.3f,%d,%d,%.3f,%.3f,%d,%d\n",
                Isaac.GetTime(),
                t,
                Game():GetLevel():GetCurrentRoomIndex(),
                player.Position.X,
                player.Position.Y,
                health(player),
                damage
            )
        )
        if t == 0 then
            ownerSeed = player.InitSeed
            clean()
            origin, center = Game():GetLevel():GetCurrentRoomIndex(), room:GetCenterPos()
            for index = 0, room:GetGridSize() - 1 do
                local value = room:GetGridEntity(index)
                if
                    value
                    and value:GetType() ~= GridEntityType.GRID_WALL
                    and value:GetType() ~= GridEntityType.GRID_DOOR
                then
                    room:RemoveGridEntity(index, 0, false)
                end
            end
        elseif t == 30 then
            clean()
            player.Position, player.Velocity = center - Vector(120, 0), Vector.Zero
            baseline, minimumExit = health(player), math.huge
            exitPosition = grid(center, GridEntityType.GRID_TRAPDOOR).Position
            heart(center + Vector(120, 0))
            command("mode hold")
            command("on")
        elseif t > 30 and t < 240 then
            minimumExit = math.min(minimumExit, player.Position:Distance(exitPosition))
        elseif t == 240 then
            check(
                "exit-pickup",
                health(player) > baseline
                    and minimumExit >= 24
                    and Game():GetLevel():GetCurrentRoomIndex() == origin,
                "health=" .. health(player) .. " minimum_exit=" .. minimumExit
            )
            clean()
        elseif t == 260 then
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door and door:IsOpen() then
                    selectedDoor = door
                    break
                end
            end
            assert(selectedDoor, "No doorway in LANBOT sandbox")
            local outward = ({ Vector(-1, 0), Vector(0, -1), Vector(1, 0), Vector(0, 1) })[selectedDoor.Slot % 4 + 1]
            player.Position, player.Velocity = selectedDoor.Position - outward * 28, outward * 2
            command("mode hold")
            command("on")
        elseif t == 350 then
            local distance = player.Position:Distance(selectedDoor.Position)
            check(
                "arrival",
                Game():GetLevel():GetCurrentRoomIndex() == origin and distance >= 60,
                "door_distance=" .. distance
            )
            clean()
        elseif t == 370 then
            player.Position, player.Velocity = center - Vector(120, 0), Vector.Zero
            plates = {
                grid(center, GridEntityType.GRID_PRESSURE_PLATE),
                grid(center + Vector(80, 80), GridEntityType.GRID_PRESSURE_PLATE),
            }
            room:SetClear(false)
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door then
                    door:Close(true)
                end
            end
            command("mode explore")
            command("on")
        elseif t > 370 and t < 610 and plates[1].State == 3 and plates[2].State == 3 then
            command("pause") -- Isolate the next fixture after the puzzle succeeds.
        elseif t == 610 then
            check(
                "buttons",
                plates[1].State == 3 and plates[2].State == 3,
                "states=" .. plates[1].State .. "," .. plates[2].State
            )
            clean()
        elseif t == 630 then
            player.Position, player.Velocity = center - Vector(120, 0), Vector.Zero
            baseline, spikeDamage = health(player), damage
            spikeWall(room)
            -- A wall with one gap forces actual timed crossing instead of a detour.
            heart(center + Vector(120, 0))
            command("mode hold")
            command("on")
        elseif t == 800 then
            check(
                "cleared-spikes",
                health(player) > baseline and damage == spikeDamage,
                "health=" .. health(player) .. " damage=" .. (damage - spikeDamage)
            )
            clean()
        elseif t == 810 then
            player.Position, player.Velocity = center - Vector(120, 0), Vector.Zero
            spikeDamage = damage
            local level = Game():GetLevel()
            local location = native.rooms_positions()["0"]
            -- GetCurrentRoomDesc and the room array expose const proxies.
            -- Use the same writable lookup as the production world adapter.
            local descriptor = level:GetRoomByIdx(location.index, location.dimension)
            -- Earlier button fixtures set this persistent flag, which keeps
            -- retracting spikes disabled independently of Room:IsClear().
            descriptor.Flags = descriptor.Flags & ~RoomDescriptor.FLAG_PRESSURE_PLATES_TRIGGERED
            -- Keep the room genuinely uncleared: an empty starting room is
            -- cleared again by the game even after Room:SetClear(false).
            occupant = Isaac.Spawn(
                EntityType.ENTITY_HOST,
                0,
                0,
                center - Vector(120, 160),
                Vector.Zero,
                nil
            )
                :ToNPC()
            occupant.State = NpcState.STATE_IDLE
            occupant:GetSprite():Play("Idle", true)
            occupant:AddFreeze(EntityRef(player), 60)
            occupant:AddEntityFlags(EntityFlag.FLAG_NO_TARGET)
            room:SetClear(false)
            spikeWall(room)
            -- Runtime grid spawns default to a disabled timer. Start one
            -- countdown; subsequent state changes must come from the game.
            spikes.State, spikes:ToSpikes().Timeout = 0, 30
            spikeTransitions, spikeState = 0, spikes.State
            timedPlate = grid(center + Vector(120, 0), GridEntityType.GRID_PRESSURE_PLATE)
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door then
                    door:Close(true)
                end
            end
            command("mode explore")
            command("on")
        elseif t > 810 and t < 1180 then
            -- Refresh the status duration: setting FLAG_FREEZE alone expires
            -- immediately, and the Host can remove NO_TARGET when opening.
            occupant:AddFreeze(EntityRef(player), 60)
            occupant:AddEntityFlags(EntityFlag.FLAG_NO_TARGET)
            if spikes.State ~= spikeState then
                spikeTransitions, spikeState = spikeTransitions + 1, spikes.State
            end
            if timedPlate.State == 3 then
                command("pause")
            elseif t % 30 == 0 then
                report(
                    "LANBOT_SPIKES tick="
                        .. t
                        .. " room_tick="
                        .. room:GetFrameCount()
                        .. " state="
                        .. spikes.State
                        .. " timeout="
                        .. spikes:ToSpikes().Timeout
                        .. " clear="
                        .. tostring(room:IsClear())
                )
                command("status")
            end
        elseif t == 1180 then
            check(
                "timed-spikes",
                timedPlate.State == 3 and damage == spikeDamage and spikeTransitions >= 3,
                "plate="
                    .. timedPlate.State
                    .. " damage="
                    .. (damage - spikeDamage)
                    .. " transitions="
                    .. spikeTransitions
            )
            clean()
        elseif t == 1190 then
            player.Position, player.Velocity = center, Vector.Zero
            dodgeDamage = damage
            command("mode hold")
            command("on")
        elseif t == 1210 then
            for _, direction in ipairs({ Vector(1, 0), Vector(0, 1) }) do
                local projectile = Isaac.Spawn(
                    EntityType.ENTITY_PROJECTILE,
                    0,
                    0,
                    center + direction * 180,
                    -direction * 5,
                    nil
                ):ToProjectile()
                projectile.Height, projectile.FallingSpeed, projectile.FallingAccel = -5, 0, 0
            end
        elseif t == 1290 then
            check(
                "crossing-projectiles",
                damage == dodgeDamage,
                "damage=" .. (damage - dodgeDamage)
            )
            clean()
        elseif t == 1300 then
            origin = Game():GetLevel():GetCurrentRoomIndex()
            command("mode explore")
            command("on")
        elseif t > 1300 and t < 1490 then
            local index = Game():GetLevel():GetCurrentRoomIndex()
            if index ~= origin and not arrivedRoom then
                arrivedRoom = index
                clean()
                command("mode hold")
                command("on")
            end
        elseif t == 1490 then
            local minimumDoor = math.huge
            for slot = 0, 7 do
                local door = room:GetDoor(slot)
                if door then
                    minimumDoor = math.min(minimumDoor, player.Position:Distance(door.Position))
                end
            end
            check(
                "door-transfer",
                arrivedRoom ~= nil
                    and Game():GetLevel():GetCurrentRoomIndex() == arrivedRoom
                    and minimumDoor >= 60,
                "arrived=" .. tostring(arrivedRoom) .. " minimum_door=" .. minimumDoor
            )
            clean()
        end
    end, collect, restore, present, beginFloor)
end
