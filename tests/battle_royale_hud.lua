local root = assert(arg[1])
local rules = dofile(root .. "/src/bridge/compat/challenges/battle_royale_rules.lua")
local draws, maps = {}, {}
local state = { phase = rules.phase.survival, elapsed = 3000, zones = { 0, 14, 42, 56 } }
local function vector(x, y)
    return { X = x, Y = y }
end
local hud = dofile(root .. "/src/bridge/presentation/battle_royale.lua")({
    rules = rules,
    native = {
        api_info = function()
            return { active = 1, ready = 1, challenge = 1003, slot = 0 }
        end,
        presentation_player_huds = function()
            return {}
        end,
        presentation_minimap = function()
            return maps
        end,
        rooms_positions = function()
            return {}
        end,
    },
    view = function()
        return state
    end,
    vector = vector,
    color = function(_, _, _, alpha)
        return { A = alpha }
    end,
    sprite = function()
        return {
            Load = function() end,
            Play = function() end,
            GetDefaultAnimation = function() end,
            SetFrame = function() end,
            Render = function(self, position)
                draws[#draws + 1] = {
                    x = position.X,
                    y = position.Y,
                    w = self.Scale.X * 480,
                    h = self.Scale.Y * 270,
                    alpha = self.Color.A,
                }
            end,
        }
    end,
})
hud.renderMap()
assert(#draws == 0, "A hidden native map must not leave a separate zone diagram")
maps = {
    {
        x = 110,
        y = 60,
        cellWidth = 6,
        cellHeight = 5,
        left = 100,
        top = 50,
        right = 180,
        bottom = 100,
        alpha = 0.5,
        dimension = 0,
    },
}
hud.renderMap()
assert(#draws > 4, "Expected outlines, preview and countdown on the existing minimap")
for _, draw in ipairs(draws) do
    assert(draw.x >= 100 and draw.x + draw.w <= 180.001)
    assert(draw.y >= 50 and draw.y + draw.h <= 104.001, "Overlay escaped the native crop/countdown")
    assert(draw.alpha <= 0.5, "Overlay must follow native map fading")
end
draws = {}
maps[1].dimension = 1
hud.renderMap()
assert(#draws == 0, "Main-floor zone must not cover another dimension")
maps[1].dimension = 0
state.phase = rules.phase.boss
hud.renderMap()
assert(#draws == 0, "Survival overlay must end with survival")
print("battle royale native-map overlay tests passed")
