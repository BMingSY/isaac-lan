local root = assert(arg[1])
local rules = dofile(root .. "/src/bridge/compat/routes/jericho_rules.lua")
local layout = dofile(root .. "/src/bridge/compat/routes/jericho_layout.lua")
local F = rules.fields
local view = { "floor", 2, 10, 20, 1, 2, 3, false, 3, 0, 0 }
local index, dimension, backdrop, sprites = 10, 0, 1, {}
local vectors = {}
local function vector(x, y)
    return setmetatable({ X = x, Y = y }, vectors)
end
function vectors.__add(a, b)
    return vector(a.X + b.X, a.Y + b.Y)
end
local function sprite()
    local value = { draws = {}, sheets = {} }
    function value:Load(path)
        self.path = path
        sprites[path] = self
    end
    function value:SetFrame() end
    function value:LoadGraphics() end
    function value:ReplaceSpritesheet(layer, path)
        self.sheets[layer] = path
    end
    function value:Render(point)
        self.draws[#self.draws + 1] = point
    end
    return value
end
local types = setmetatable({}, {
    __index = function(t, key)
        rawset(t, key, key)
        return key
    end,
})
local room = {
    IsMirrorWorld = function()
        return dimension == 1
    end,
    GetCenterPos = function()
        return vector(300, 250)
    end,
    GetBackdropType = function()
        return backdrop
    end,
}
local level = {
    GetCurrentRoomDesc = function()
        return { SafeGridIndex = index, ListIndex = index + 169 * dimension }
    end,
    GetRoomByIdx = function(_, at, dim)
        return { ListIndex = at + 169 * dim }
    end,
}
local presentation = dofile(root .. "/src/bridge/presentation/jericho.lua")({
    native = {
        api_info = function()
            return { active = 1, ready = 1, challenge = 0 }
        end,
    },
    rules = rules,
    layout = layout,
    view = function()
        return view
    end,
    vector = vector,
    sprite = sprite,
    color = function(...)
        return { ... }
    end,
    screen = function(point)
        return point
    end,
    width = function()
        return 800
    end,
    backdrop = types,
    config = function()
        return {
            GetCollectible = function(_, id)
                return { GfxFileName = "item-" .. id }
            end,
        }
    end,
    game = function()
        return {
            GetRoom = function()
                return room
            end,
            GetLevel = function()
                return level
            end,
            GetFrameCount = function()
                return 20
            end,
        }
    end,
})
presentation.render()
local item = sprites["gfx/005.100_collectible.anm2"]
local plate = sprites["gfx/grid/grid_pressureplate.anm2"]
assert(item.sheets[1] == "item-1" and #item.draws == 1)
assert(plate.draws[1].X == 140)
index = 20
presentation.render()
assert(item.sheets[1] == "item-2")
local draws = #item.draws
dimension, backdrop = 1, types.DOWNPOUR
presentation.render()
assert(#item.draws == draws, "Mirror displayed a collectible preview")
assert(plate.draws[#plate.draws - 7].X == 660, "Mirror omitted final screen reflection")
local rock = sprites["gfx/grid/grid_rock.anm2"]
assert(rock.sheets[0] == "gfx/grid/rocks_downpour.png")
dimension, view[F.complete] = 0, true
for _, entry in ipairs({
    { types.WOMB, "womb" },
    { types.ASHPIT, "ashpit" },
    { types.DROSS, "dross" },
}) do
    backdrop = entry[1]
    presentation.render()
    assert(rock.sheets[0] == "gfx/grid/rocks_" .. entry[2] .. ".png")
end
assert(#item.draws == draws, "Solved room retained a virtual item")
dimension = 2
local count = #rock.draws
presentation.render()
assert(#rock.draws == count, "Other dimensions inherited mirror ruins")
presentation.reset()
print("Jericho preview, mirror projection, native floor textures and cleanup passed")
