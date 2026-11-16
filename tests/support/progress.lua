-- The native counters precede the run-award ledger in net_progress bytes.
local ACHIEVEMENT_COUNT, COUNTER_COUNT, COUNTER_BYTES = 642, 523, 4
local COUNTERS_START = 2 + ACHIEVEMENT_COUNT
return {
    fixture = function(achievement, privateCounter)
        return "\1"
            .. string.rep(string.char(achievement), ACHIEVEMENT_COUNT)
            .. string.rep("\0", (COUNTER_COUNT - 1) * COUNTER_BYTES)
            .. string.pack(">I4", privateCounter)
            .. string.rep("\0", ACHIEVEMENT_COUNT + COUNTER_COUNT)
    end,
    privateCounter = function(bytes)
        local value =
            string.unpack(">I4", bytes, COUNTERS_START + (COUNTER_COUNT - 1) * COUNTER_BYTES)
        return value
    end,
}
