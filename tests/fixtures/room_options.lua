-- Expected player-facing groups, resolved through the game's RoomType contract.
return function(types)
    local first = 1 << 5
    local groups = {
        {
            key = "ordinary",
            name = "普通房间",
            types = {
                "ROOM_DEFAULT",
                "ROOM_ISAACS",
                "ROOM_BARREN",
                "ROOM_GREED_EXIT",
                "ROOM_SECRET_EXIT",
                "ROOM_BLUE",
            },
        },
        {
            key = "boss",
            name = "Boss 房",
            types = { "ROOM_BOSS", "ROOM_MINIBOSS", "ROOM_BOSSRUSH" },
        },
        {
            key = "treasure",
            name = "宝物房",
            types = { "ROOM_TREASURE", "ROOM_PLANETARIUM", "ROOM_CHEST", "ROOM_DUNGEON" },
        },
        { key = "shop", name = "商店", types = { "ROOM_SHOP", "ROOM_BLACK_MARKET" } },
        {
            key = "secret",
            name = "隐藏房",
            types = { "ROOM_SECRET", "ROOM_SUPERSECRET", "ROOM_ULTRASECRET", "ROOM_ERROR" },
        },
        { key = "deals", name = "天使／恶魔房", types = { "ROOM_ANGEL", "ROOM_DEVIL" } },
        {
            key = "special",
            name = "其他特殊房",
            types = {
                "ROOM_CHALLENGE",
                "ROOM_CURSE",
                "ROOM_SACRIFICE",
                "ROOM_LIBRARY",
                "ROOM_ARCADE",
                "ROOM_DICE",
            },
        },
    }
    local all = 0
    for _, group in ipairs(groups) do
        group.flag = 0
        for _, name in ipairs(group.types) do
            group.flag = group.flag | (first << (assert(types[name]) - types.ROOM_DEFAULT))
        end
        assert(all & group.flag == 0)
        all = all | group.flag
    end
    return {
        { flag = 1, key = "friendlyFire", name = "队友伤害", shortName = "友伤" },
        { flag = 2, key = "sharedClearCharge", name = "清房充能共享", shortName = "充能" },
        { flag = 4, key = "lootRoll", name = "道具掷骰分配", shortName = "掷骰" },
        {
            flag = all,
            firstRoomFlag = first,
            key = "autoTeleport",
            name = "自动传送",
            shortName = "传送",
            groups = groups,
        },
    }
end
