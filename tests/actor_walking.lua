local root = assert(arg[1])
local fields = dofile(root .. "/src/bridge/sync/fields.lua")
local function sprite(path, length)
    local s = {
        name = "WalkDown",
        frame = 0,
        overlay = "HeadRight",
        overlayFrame = 7,
        PlaybackSpeed = 1,
        length = length,
    }
    function s:GetFilename()
        return path
    end
    function s:GetAnimation()
        return self.name
    end
    function s:Play(name)
        self.name, self.frame = name, 0
    end
    function s:SetFrame(name, frame)
        self.name, self.frame = name, frame
    end
    return s
end
local body, costume, action = sprite("body", 20), sprite("costume", 13), sprite("action", 8)
action.name = "UseItem"
local sprites = {
    [fields.actorSprites.firstCostume] = costume,
    [fields.actorSprites.firstCostume + 1] = action,
}
for i = 1, fields.actorSprites.firstCostume - 1 do
    sprites[i] = body
end
local native = {
    actor_sprites = function()
        return sprites
    end,
    sprite_animation_length = function(s)
        return s.length
    end,
}
local component = dofile(root .. "/src/bridge/presentation/actors.lua")(fields)(native)
local player = {
    GetSprite = function()
        return body
    end,
    IsCoopGhost = function()
        return false
    end,
}
local function direction(x, y)
    return {
        X = x,
        Y = y,
        LengthSquared = function()
            return x * x + y * y
        end,
    }
end
local model = { prediction = { velocity = direction(0, 0) } }
local actor = { [fields.actor.index] = 0 }
for frame = 1, 50 do
    -- A received idle pose must not rewind the local locomotion clock.
    body.name, body.frame, costume.name, costume.frame = "WalkDown", 0, "WalkDown", 0
    component.walk(player, actor, model, direction(1, 0), 1 / 60, true)
    assert(body.name == "WalkRight" and body.frame == math.floor(frame / 2) % 20)
    assert(costume.frame == math.floor(frame / 2) % 13, "Mod costume length was assumed")
    assert(body.overlay == "HeadRight" and body.overlayFrame == 7 and action.name == "UseItem")
end
component.walk(player, actor, model, direction(-1, 0), 1 / 60, true)
assert(body.name == "WalkLeft" and body.frame == 0, "Turn waited for authority")
body.name, body.frame = "WalkUp", 16
component.walk(player, actor, model, direction(0, 0), 1 / 60, true)
assert(
    body.name == "WalkUp" and body.frame == 16 and model.walk == nil,
    "Idle attack facing was replaced by a walking prediction"
)
body.name = "TeleportUp"
component.walk(player, actor, model, direction(1, 0), 1 / 60, true)
assert(body.name == "TeleportUp" and model.walk == nil)
body.name = "WalkDown"
component.walk(player, actor, model, direction(1, 0), 1 / 60, false)
assert(body.name == "WalkDown" and model.walk == nil)
print("PASS immediate local walking, fractional frames, costume lengths, aiming and action locks")

local departures = 0
function player:AnimateTrapdoor()
    departures = departures + 1
end
component.departFloor(player, 0, false)
assert(departures == 1, "Accepted descent omitted the native departure pose")
component.departFloor(player, 0, true)
for animation = 1, 6 do
    component.departFloor(player, animation, false)
end
assert(departures == 1, "Non-descent transition acquired an unrelated jump")
player.IsCoopGhost = function()
    return true
end
component.departFloor(player, 0, false)
assert(departures == 1, "Co-op ghost acquired a living body's jump")
print("PASS floor descent, other transition ownership and ghost presentation")
