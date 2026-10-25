-- Main-bridge fixtures use real UI/lifecycle components with no local requests.
return function(root, native, modules)
    local enums = dofile(root .. "/tests/fixtures/game_enums.lua")
    RoomType = RoomType or enums.RoomType
    RoomShape = RoomShape or enums.RoomShape
    GridRooms = GridRooms or enums.GridRooms
    GridCollisionClass = GridCollisionClass or enums.GridCollisionClass
    EntityType = EntityType or {}
    ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD = ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD or 9
    ModCallbacks.MC_ENTITY_TAKE_DMG = ModCallbacks.MC_ENTITY_TAKE_DMG or 11
    ModCallbacks.MC_USE_ITEM = ModCallbacks.MC_USE_ITEM or 12
    ModCallbacks.MC_PRE_USE_ITEM = ModCallbacks.MC_PRE_USE_ITEM or 13
    native.net_room_options = function()
        return {
            { flag = 1, key = "friendlyFire", name = "队友伤害" },
            { flag = 2, key = "sharedClearCharge" },
            { flag = 4, key = "lootRoll" },
            { flag = 8, key = "specialRoomGather" },
        }
    end
    native.menu_room_options = native.menu_room_options or function()
        return 0
    end
    native.menu_room_options_save = native.menu_room_options_save
        or function()
            return true
        end
    native.net_configure_options = native.net_configure_options
        or function()
            return true
        end
    native.chat_style = { opacity = 70, background = 0x231b18, border = 0x79604c, text = 0xe8dfcb }
    for _, name in ipairs({
        "core/contacts",
        "core/endpoint",
        "compat/rules/pvp_damage",
        "compat/rules/pvp_attacks",
        "compat/rules/pvp_health",
        "compat/items/pvp",
        "compat/rules/friendly_fire",
        "compat/rules/loot_roll",
        "compat/rules/clear_charge",
        "compat/rules/special_rooms",
        "runtime/room_rules",
        "compat/challenges/luck_game",
        "compat/items/glitched",
        "runtime/restart",
        "runtime/chat_wire",
        "runtime/chat_dice",
        "runtime/teleport",
        "runtime/chat",
        "presentation/chat_layout",
        "presentation/chat",
        "diagnostics/feedback",
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
    native.feedback_submit = function()
        error("Unexpected feedback without a local request")
    end
    native.feedback_poll = function() end
end
