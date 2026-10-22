-- The weapon prefix of actor_pose; the remaining costume/layer bytes stay opaque.
-- This is the existing wire contract, not a native memory layout.
local prefix = ">BBI4I4f"
local record = ">I4fff"
local slots = 5
local function read(bytes)
    local weapons, cursor = {}, string.packsize(prefix) + 1
    for slot = 1, slots do
        local exists
        exists, cursor = string.unpack(">B", bytes, cursor)
        if exists ~= 0 then
            local kind, delay, maximum, charge
            kind, delay, maximum, charge, cursor = string.unpack(record, bytes, cursor)
            weapons[slot] = { kind = kind, delay = delay, maximum = maximum, charge = charge }
        end
    end
    return weapons
end
local function display(bytes, weapons)
    local cursor = string.packsize(prefix) + 1
    local parts = { bytes:sub(1, cursor - 1) }
    for slot = 1, slots do
        local exists
        exists, cursor = string.unpack(">B", bytes, cursor)
        parts[#parts + 1] = string.pack(">B", exists)
        if exists ~= 0 then
            local kind, delay, maximum, charge, nextCursor = string.unpack(record, bytes, cursor)
            local value = weapons[slot]
            if value and value.kind == kind then
                charge = value.charge
            end
            -- Cooldowns are authoritative. Only Render's charge-bar value is replaced.
            parts[#parts + 1] = string.pack(record, kind, delay, maximum, charge)
            cursor = nextCursor
        end
    end
    parts[#parts + 1] = bytes:sub(cursor)
    return table.concat(parts)
end
return { read = read, display = display, slotCount = slots, primarySlot = 2 }
