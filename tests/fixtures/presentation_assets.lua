return function(vanilla)
    if vanilla then
        return {
            native_lobby = false,
            fonts = {
                small = { path = "font/cjk/lanapixel.fnt", scale = 1 },
                normal = { path = "font/cjk/lanapixel.fnt", scale = 1.2 },
                heading = { path = "font/cjk/lanapixel.fnt", scale = 1.6 },
            },
        }
    end
    return {
        native_lobby = true,
        fonts = {
            small = { path = "font/TeamMeatEx/TeamMeatEx10.fnt", scale = 1 },
            normal = { path = "font/TeamMeatEx/TeamMeatEx12.fnt", scale = 1 },
            heading = { path = "font/TeamMeatEx/TeamMeatEx16.fnt", scale = 1 },
        },
    }
end
