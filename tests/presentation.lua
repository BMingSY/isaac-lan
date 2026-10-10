local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/state/presentation.lua")
local captured, applied, order = {}, {}, {}
local main = { layers = { "card_face", "card_border", "card_glow" }, frame = 14 }
local mega = { layers = { "player", "costumes" }, frame = 6 }
local scene = { layers = { "dream", "television", "fade" }, frame = 23 }
local sceneActive = true
local native = {}
function native.home_scene_sprite(sample)
    assert(sample == "native metatable")
    return sceneActive and scene or false
end
function native.home_scene_pose(value)
    if not value then
        return "scene bytes"
    end
    assert(value == "scene bytes" or value == "inactive scene")
    sceneActive = value ~= "inactive scene"
    order[#order + 1] = "scene"
    return true
end
function native.item_presentation_sprite(slot, sample, part)
    assert(slot == 1 and sample == "native metatable")
    return part == 0 and main or mega
end
function native.item_presentation_events(value)
    if value == 1 then
        return "event bytes"
    end
    assert(value == "event bytes")
    order[#order + 1] = "event"
    return true
end
function native.item_presentation_pose(slot, value)
    assert(slot == 1)
    if not value then
        return "pose bytes"
    end
    assert(value == "pose bytes")
    order[#order + 1] = "pose"
    return true
end
local presentation = factory(native, function()
    return "native metatable"
end, function(sprite)
    captured[#captured + 1] = sprite
    return { sprite.layers, sprite.frame }
end, function(sprite, value)
    applied[#applied + 1] = { sprite, value }
    order[#order + 1] = "sprite"
end)
local value = presentation.capture(1)
assert(value[1] == "event bytes" and value[4] == "pose bytes")
assert(value[2][1] == mega.layers and value[3][1] == main.layers)
assert(value[3][2] == 14 and #captured == 3)
assert(value[5] == "scene bytes" and value[6][1] == scene.layers and value[6][2] == 23)
presentation.apply(1, value)
assert(table.concat(order, ",") == "event,pose,scene,sprite,sprite,sprite")
assert(applied[1][1] == main and applied[2][1] == mega)
assert(applied[1][2][1] == main.layers)
assert(applied[3][1] == scene and applied[3][2][1] == scene.layers)
-- A completed animation must clear native display state without touching
-- empty sprites, and a repeated snapshot must retain every layer and frame.
order, applied = {}, {}
presentation.apply(1, { "event bytes", false, false, "pose bytes", "inactive scene", false })
assert(#applied == 0 and table.concat(order, ",") == "event,pose,scene")
assert(presentation.capture(1)[6] == false)
presentation.apply(1, value)
assert(applied[1][2][2] == 14)
print("PASS complete local item presentation")
