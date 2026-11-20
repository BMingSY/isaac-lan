-- The native counters precede the run-award ledger in net_progress bytes.
local ACHIEVEMENT_COUNT, COUNTER_COUNT, COUNTER_BYTES = 642, 523, 4
local COUNTERS_START = 2 + ACHIEVEMENT_COUNT
local nativeCount, privateAchievement, counterIndex = ...
nativeCount = nativeCount or ACHIEVEMENT_COUNT
privateAchievement = privateAchievement or 640
counterIndex = counterIndex or COUNTER_COUNT - 1
return {
    achievementCount = nativeCount,
    privateAchievement = privateAchievement,
    counterIndex = counterIndex,
    fixture = function(achievement, privateCounter)
        return "\1"
            .. string.rep(string.char(achievement), nativeCount)
            .. string.rep("\0", ACHIEVEMENT_COUNT - nativeCount + counterIndex * COUNTER_BYTES)
            .. string.pack(">I4", privateCounter)
            .. string.rep("\0", (COUNTER_COUNT - counterIndex - 1) * COUNTER_BYTES)
            .. string.rep("\0", ACHIEVEMENT_COUNT + COUNTER_COUNT)
    end,
    privateCounter = function(bytes)
        local value = string.unpack(">I4", bytes, COUNTERS_START + counterIndex * COUNTER_BYTES)
        return value
    end,
    startupMatches = function(bytes, test)
        if not bytes or bytes:byte(1) ~= 1 then
            return false
        end
        local function flag(id)
            return bytes:byte(id + 2)
        end
        local function counter(id)
            return string.unpack(">I4", bytes, COUNTERS_START + id * COUNTER_BYTES)
        end
        local expected = test.host and 1 or 0
        if
            flag(privateAchievement) ~= expected
            or counter(counterIndex) ~= (test.host and 98765 or 321)
        then
            return false
        end
        if test.ascent and test.host and (flag(4) ~= 1 or flag(57) ~= 1 or flag(635) ~= 1) then
            return false
        end
        if test.endings and test.host then
            for id = 0, nativeCount - 1 do
                if flag(id) ~= (test.altPath and id == 412 and 0 or 1) then
                    return false
                end
            end
        elseif test.endings and flag(407) ~= 0 then
            return false
        end
        return (not test.hush or (flag(320) == expected and counter(158) == (test.host and 3 or 0)))
            and (not test.altPath or (flag(407) == expected and flag(412) == 0))
    end,
}
