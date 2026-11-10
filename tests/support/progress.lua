-- The native counters precede the run-award ledger in net_progress bytes.
local ACHIEVEMENT_COUNT, COUNTER_COUNT, COUNTER_BYTES = 642, 523, 4
local COUNTERS_START = 2 + ACHIEVEMENT_COUNT
return {
    privateCounter = function(bytes)
        local value =
            string.unpack(">I4", bytes, COUNTERS_START + (COUNTER_COUNT - 1) * COUNTER_BYTES)
        return value
    end,
}
