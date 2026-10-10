-- Render-only movement and interpolation; authority remains on the host.
return function(native, actorsPresentation, view)
    local Vector = view.vector
    local unpack = string.unpack
    local lastRender
    local outwardDirections = { Vector(-1, 0), Vector(0, -1), Vector(1, 0), Vector(0, 1) }
    local function doorCorridor(room, position)
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door:IsOpen() then
                local outward = outwardDirections[slot % 4 + 1]
                local delta = door.Position - position
                local along = delta:Dot(outward)
                local across = math.abs(delta.X * outward.Y - delta.Y * outward.X)
                if along < 64 and along > -24 and across < 16 then
                    return slot, outward, along
                end
            end
        end
    end
    local function clearForPlayer(room, position, aperture)
        local collision = room:GetGridCollisionAtPos(position)
        return collision == GridCollisionClass.COLLISION_NONE
            or collision == GridCollisionClass.COLLISION_WALL_EXCEPT_PLAYER
            or (aperture and collision == GridCollisionClass.COLLISION_WALL)
    end
    local function present(input, sequence, actorVisuals, motion, ref, receivedTick)
        if receivedTick < 0 then
            return
        end
        -- Native room and Mod presentation updates run after receiving a packet.
        -- Reassert authoritative actor poses at the render boundary so local
        -- callbacks cannot replace a body or start an unrelated dance.
        for _, actor in ipairs(actorVisuals) do
            local p = view.player(actor[1])
            if p and p.ControllerIndex == actor[2] then
                actorsPresentation.apply(p, actor)
            end
        end
        local now = view.clock() / 1000
        local dt = lastRender and math.max(0, math.min(now - lastRender, 0.05)) or 0
        lastRender = now
        local status = view.status()
        if status.pause ~= 0 then
            return
        end
        local values = { unpack(">I2I2I2I2", input) }
        local direction = Vector((values[2] - values[1]) / 65535, (values[4] - values[3]) / 65535)
        assert(native.rooms_with_player(status.slot, function()
            if view.room():IsMirrorWorld() then
                direction.X = -direction.X
            end
        end))
        if direction:Length() > 1 then
            direction = direction:Normalized()
        end
        for identifier, m in pairs(motion) do
            local e = ref(identifier)
            if e then
                local age = math.max(0, now - m.at)
                local fraction = math.min(age * 30, 1)
                local position = m.from + (m.target - m.from) * fraction
                if m.actor and m.controller == status.slot + 1 then
                    local p = e:ToPlayer()
                    local controls = p.ControlsEnabled
                        and p:AreControlsEnabled()
                        and p:IsExtraAnimationFinished()
                    if not controls then
                        m.prediction:reset(m.target, sequence - 1)
                        m.doorway = nil
                    end
                    position = m.prediction:step(
                        controls and direction or Vector(0, 0),
                        sequence,
                        p.MoveSpeed * (4.4117647 * 60),
                        dt
                    )
                    assert(native.rooms_with_player(status.slot, function()
                        local room = view.room()
                        if m.doorway then
                            local door = room:GetDoor(m.doorway.slot)
                            if
                                not door
                                or not door:IsOpen()
                                or direction:Dot(m.doorway.outward) <= 0
                                or now - m.doorway.at > 0.5
                            then
                                m.doorway = nil
                            end
                        end
                        local slot, outward, along = doorCorridor(room, position)
                        local aperture = controls and slot ~= nil
                        if
                            aperture
                            and not m.doorway
                            and direction:Dot(outward) > 0
                            and along < 18
                        then
                            m.doorway =
                                { slot = slot, outward = outward, at = now, position = position }
                        end
                        if m.doorway then
                            -- Await the host's room commit at the doorway. Do not
                            -- extrapolate a source-room walk into the destination.
                            position = m.doorway.position
                            m.prediction.velocity = Vector(0, 0)
                        end
                        if not aperture then
                            position = room:GetClampedPosition(position, math.max(5, e.Size))
                        end
                        if not p.CanFly and not clearForPlayer(room, position, aperture) then
                            -- Slide along blocked grids; returning to the older
                            -- authority position on every blocked frame flickers.
                            local x = Vector(position.X, m.display.Y)
                            local y = Vector(m.display.X, position.Y)
                            if clearForPlayer(room, x, aperture) then
                                position = x
                            elseif clearForPlayer(room, y, aperture) then
                                position = y
                            elseif clearForPlayer(room, m.display, aperture) then
                                position = m.display
                            else
                                position = m.target
                            end
                        end
                    end))
                    m.prediction:clip(position)
                    m.display = position
                elseif age > 1 / 30 then
                    position = position + m.velocity * math.min(age - 1 / 30, 0.1) * 30
                end
                e.Position = position
            end
        end
    end
    return {
        present = present,
        reset = function()
            lastRender = nil
        end,
    }
end
