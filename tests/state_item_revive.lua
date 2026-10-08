-- Exercise native item revivals with a teammate in another occupied room.
local native = assert(_IsaacLan)
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local renders, linked, chosen, finished = 0, false, false, false
local originalFrame = _IsaacLanFrame
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = originalFrame()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    native.test_gamepad(0)
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.verified >= 750 and not finished then
        finished = true
        report("PASS native Collar and Dead Cat resurrection")
    end
    return s
end
local gate = native.net_gate
local origin, other
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(capture, function(t, n, b)
        before(t, n, b)
        if t == 25 then
            origin = Game():GetLevel():GetCurrentRoomIndex()
            local rooms = Game():GetLevel():GetRooms()
            for i = 0, rooms.Size - 1 do
                local d = rooms:Get(i)
                if d.SafeGridIndex ~= origin and d.Data.Type == RoomType.ROOM_DEFAULT then
                    other = d.SafeGridIndex
                    break
                end
            end
            assert(other)
            assert(native.rooms_move(1, other, 0, 0))
        end
        if t == 40 then
            for slot = 0, 1 do
                assert(native.rooms_with_player(slot, function()
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsActiveEnemy(false) then
                            e:Remove()
                        end
                    end
                    Game():GetRoom():SetClear(true)
                end))
            end
            local p = Isaac.GetPlayer(0)
            p:AddCollectible(CollectibleType.COLLECTIBLE_GUPPYS_COLLAR)
            p:GetCollectibleRNG(CollectibleType.COLLECTIBLE_GUPPYS_COLLAR):SetSeed(1, 35)
        end
        if t == 100 then
            assert(native.rooms_with_player(0, function()
                Isaac.GetPlayer(0):Kill()
            end))
            report("COLLAR killed")
        end
        if t >= 100 and t < 350 and t % 30 == 0 then
            local p = Isaac.GetPlayer(0)
            report(
                "COLLAR tick="
                    .. t
                    .. " dead="
                    .. tostring(p:IsDead())
                    .. " ghost="
                    .. tostring(p:IsCoopGhost())
                    .. " visible="
                    .. tostring(p.Visible)
                    .. " cooldown="
                    .. p:GetDamageCooldown()
                    .. " animation="
                    .. p:GetSprite():GetAnimation()
            )
        end
        if t == 350 then
            local p = Isaac.GetPlayer(0)
            assert(
                not p:IsDead() and not p:IsCoopGhost(),
                "Collar did not revive through its native effect"
            )
            assert(p.Visible, "Collar revival left the player hidden")
            assert(p:GetDamageCooldown() == 0, "Revived body retained a frozen damage blink")
            assert(native.rooms_positions()["0"], "Revived controller lost its room")
            p:RemoveCollectible(CollectibleType.COLLECTIBLE_GUPPYS_COLLAR)
            p:AddCollectible(CollectibleType.COLLECTIBLE_DEAD_CAT)
            report("COLLAR revived")
        end
        if t == 420 then
            assert(native.rooms_with_player(0, function()
                Isaac.GetPlayer(0):Kill()
            end))
            report("DEAD_CAT killed")
        end
        if t == 730 then
            local p = Isaac.GetPlayer(0)
            assert(
                not p:IsDead() and not p:IsCoopGhost() and p.Visible,
                "Dead Cat did not restore the body"
            )
            assert(p:GetDamageCooldown() == 0, "Dead Cat retained a frozen damage blink")
            report("DEAD_CAT revived")
        end
    end, collect, restore, present, beginFloor)
end
