-- Main-bridge fixtures use real UI/lifecycle components with no local requests.
return function(root, native, modules)
    EntityType = EntityType or {}
    ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD = ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD or 9
    native.chat_style = { opacity = 70, background = 0x231b18, border = 0x79604c, text = 0xe8dfcb }
    for _, name in ipairs({
        "compat/challenges/luck_game",
        "compat/items/glitched",
        "runtime/restart",
        "runtime/chat_wire",
        "runtime/chat_dice",
        "runtime/chat",
        "presentation/chat_layout",
        "presentation/chat",
    }) do
        modules[name] = dofile(root .. "/src/bridge/" .. name .. ".lua")
    end
    native.net_lifecycle_receive = function() end
    native.net_lifecycle_send = function()
        return false
    end
    native.net_restart_request = function()
        return false
    end
    native.net_restart = function()
        error("Unexpected restart without a local request")
    end
    native.chat_limits = function()
        return { characters = 60, commandBytes = 2048, history = 200, dice = 999 }
    end
    native.api_nonce = native.api_nonce or function()
        return string.rep("n", 32)
    end
    native.emote_count = function()
        return 59
    end
    native.emote_poll = function()
        return { open = false, selected = 0 }
    end
    native.emote_show = function() end
    native.chat_ui_pointer = function()
        return { x = -1000, y = -1000, down = false }
    end
    native.chat_ui_copy = function()
        return false
    end
    native.chat_receive = function() end
    native.chat_send = function()
        return false
    end
    native.chat_ui_available = function() end
    native.chat_ui_reset = function() end
    native.chat_ui_modal = function() end
    native.chat_ui_state = function()
        return { open = false, text = "", cursor = 0, anchor = 0, scroll = 0 }
    end
    native.chat_controls = function()
        return {}
    end
end
