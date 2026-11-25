-- The external HUD observer reads the game's bound panels independently.
-- Supply its expected online seats even across disconnects and reconnects.
do
    local frame = _IsaacLanFrame
    local previousSlot, previousMask
    function _IsaacLanFrame(...)
        local status = frame(...)
        if
            status.prepared and (status.slot ~= previousSlot or status.connected ~= previousMask)
        then
            previousSlot, previousMask = status.slot, status.connected
            Isaac.DebugString(
                "LAN_NETWORK HUD_AUDIENCE slot=" .. status.slot .. " connected=" .. status.connected
            )
        end
        return status
    end
end
