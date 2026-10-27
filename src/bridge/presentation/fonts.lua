-- The backend supplies available game resources; callers use logical font sizes.
return function(definitions)
    local loaded, fonts = {}, {}
    return function(name)
        if fonts[name] then
            return fonts[name]
        end
        local definition = assert(definitions[name], "Missing menu font definition")
        local font = loaded[definition.path]
        if not font then
            font = Font()
            font:Load(definition.path)
            assert(font:IsLoaded(), "Cannot load the game's menu font: " .. definition.path)
            loaded[definition.path] = font
        end
        local scale = definition.scale
        if scale == 1 then
            fonts[name] = font
            return font
        end
        -- Keep measurement, centering, wrapping and drawing in the same units.
        local scaled = {}
        function scaled:GetStringWidthUTF8(value)
            return font:GetStringWidthUTF8(value) * scale
        end
        function scaled:DrawStringUTF8(value, x, y, color, boxWidth, center)
            self:DrawStringScaledUTF8(value, x, y, 1, 1, color, boxWidth, center)
        end
        function scaled:DrawStringScaledUTF8(value, x, y, sx, sy, color, boxWidth, center)
            font:DrawStringScaledUTF8(value, x, y, sx * scale, sy * scale, color, boxWidth, center)
        end
        fonts[name] = scaled
        return scaled
    end
end
