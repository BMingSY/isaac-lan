local root = assert(arg[1])
local create = dofile(root .. "/src/bridge/presentation/fonts.lua")
local loads, draws = {}, {}
local missing = true
Font = function()
    return {
        Load = function(self, path)
            loads[path] = (loads[path] or 0) + 1
            self.path = path
        end,
        IsLoaded = function(self)
            return self.path ~= "font/missing.fnt" or not missing
        end,
        GetStringWidthUTF8 = function(_, value)
            return utf8.len(value) * 6
        end,
        DrawStringScaledUTF8 = function(_, value, x, y, sx, sy, color, width, center)
            draws[#draws + 1] = { value, x, y, sx, sy, color, width, center }
        end,
    }
end
local fonts = create({
    small = { path = "font/shared.fnt", scale = 1 },
    normal = { path = "font/shared.fnt", scale = 1.2 },
    heading = { path = "font/shared.fnt", scale = 1.6 },
    missing = { path = "font/missing.fnt", scale = 1.2 },
})
assert(next(loads) == nil, "Module construction loaded game resources")
local normal = fonts("normal")
assert(fonts("normal") == normal and loads["font/shared.fnt"] == 1)
assert(fonts("small"):GetStringWidthUTF8("联机") == 12)
assert(math.abs(normal:GetStringWidthUTF8("联机") - 14.4) < 0.00001)
assert(math.abs(fonts("heading"):GetStringWidthUTF8("联机") - 19.2) < 0.00001)
assert(loads["font/shared.fnt"] == 1, "Logical sizes duplicated the same native font")
normal:DrawStringUTF8("联机", 20, 30, "ink", 0, false)
assert(draws[1][1] == "联机" and draws[1][2] == 20 and draws[1][3] == 30)
assert(draws[1][4] == 1.2 and draws[1][5] == 1.2 and draws[1][6] == "ink")
normal:DrawStringScaledUTF8("Lan", 10, 15, 0.5, 0.75, "ink", 0, false)
assert(draws[2][4] == 0.6 and math.abs(draws[2][5] - 0.9) < 0.00001)
assert(not pcall(fonts, "unknown"))
assert(not pcall(fonts, "missing"))
missing = false
assert(fonts("missing") and loads["font/missing.fnt"] == 2)
print("Version font resources: PASS")
