-- Owned isolated frontend fixture. Native disk selection is checked separately
-- with real files/hashes; this supplies one pending result to the normal UI.
assert(type(_IsaacLan.test_update_notice) == "function", "Owned frontend fixture required")
local original = _IsaacLanMenuRender
local requested, shown, dismissedFrames = false, false, 0
_IsaacLanMenuRender = function(...)
    local available = select(1, ...)
    local version = select(10, ...)
    if available and not requested then
        requested = true
        _IsaacLan.test_update_notice("0.7.1")
        Isaac.DebugString("LAN_UPDATE_NOTICE REQUESTED")
    end
    if available and version and version ~= "" then
        assert(dismissedFrames == 0, "Dismissed update notice reopened")
        if not shown then
            shown = true
            Isaac.DebugString("LAN_UPDATE_NOTICE SHOWN")
        end
    elseif shown and available then
        dismissedFrames = dismissedFrames + 1
        if dismissedFrames == 120 then
            Isaac.DebugString("LAN_UPDATE_NOTICE CONTINUE_PASS")
        end
    end
    return original(...)
end
