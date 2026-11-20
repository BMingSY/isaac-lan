return function(vanilla)
    if vanilla then
        return {
            native_lobby = false,
            main_title = "cache/menu/online.anm2",
            fonts = {
                small = { path = "resources-dlc3.zh/font/TeamMeatFontExtended10.fnt", scale = 1 },
                normal = { path = "resources-dlc3.zh/font/TeamMeatFontExtended12.fnt", scale = 1 },
                heading = {
                    path = "resources-dlc3.zh/font/TeamMeatFontExtended16Bold.fnt",
                    scale = 1,
                },
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
