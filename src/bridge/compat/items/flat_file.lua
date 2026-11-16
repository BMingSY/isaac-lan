-- Curse-door spikes follow the current room's holders, including resident
-- doors whose native initialization ran before a teammate arrived.
return function(deps)
    local native, game, player = deps.native, deps.game, deps.player
    local spiked, flattened = 0, 1
    return function()
        local info = native.api_info()
        if info.active ~= 1 or info.authority ~= 1 or info.ready ~= 1 then
            return
        end
        local positions, visited = native.rooms_positions(), {}
        for slot = 0, info.players - 1 do
            local position = positions[tostring(slot)]
            if position and (info.connected & (1 << slot)) ~= 0 then
                local key = position.dimension .. ":" .. position.index
                if not visited[key] then
                    visited[key] = true
                    assert(native.rooms_with_player(slot, function()
                        local current = game()
                        local desired = spiked
                        for index = 0, current:GetNumPlayers() - 1 do
                            if player(index):HasTrinket(deps.trinket) then
                                desired = flattened
                                break
                            end
                        end
                        local room = current:GetRoom()
                        for doorSlot = 0, deps.doorSlots - 1 do
                            local door = room:GetDoor(doorSlot)
                            if
                                door
                                and door:IsRoomType(deps.curseRoom)
                                and door.VarData ~= desired
                            then
                                -- Native curse doors cache Flat File in VarData.
                                -- SetRoomTypes refreshes their own art and collision
                                -- rules while retaining the destination and lock state.
                                door.VarData = desired
                                door:SetRoomTypes(door.CurrentRoomType, door.TargetRoomType)
                            end
                        end
                    end))
                end
            end
        end
    end
end
