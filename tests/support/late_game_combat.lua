-- Host fires a natural late-game loadout while the guest observes the same room.
local config = _IsaacLanTest
local items = {
    CollectibleType.COLLECTIBLE_C_SECTION,
    CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO,
    CollectibleType.COLLECTIBLE_MUTANT_SPIDER,
    CollectibleType.COLLECTIBLE_20_20,
}
local target, hostile = nil, {}
local function setup(case)
    local p = Isaac.GetPlayer(0)
    for _, item in ipairs(items) do
        if p:HasCollectible(item) then
            p:RemoveCollectible(item)
        end
    end
    target, hostile = nil, {}
    if case.loadout then
        for i = 1, case.multi and #items or 2 do
            p:AddCollectible(items[i], 0, false)
        end
        target = EntityPtr(
            Isaac.Spawn(EntityType.ENTITY_GAPER, 0, 0, Vector(365, 220), Vector.Zero, nil)
        )
        target.Ref:AddEntityFlags(EntityFlag.FLAG_FREEZE)
        target.Ref.HitPoints, target.Ref.MaxHitPoints = 1e7, 1e7
    end
    p:AddCacheFlags(CacheFlag.CACHE_ALL)
    p:EvaluateItems()
    if case.loadout then
        p.Position, p.FireDelay, p.MaxFireDelay = Vector(130, 240), 0, 0.5
    end
end
local function advance(case, t)
    Isaac.GetPlayer(0).MaxFireDelay = 0.5
    local enemy = assert(target.Ref)
    enemy.Position, enemy.HitPoints =
        Vector(355 + math.sin(t / 37) * 65, 240 + math.cos(t / 25) * 48), 1e7
    for i = 1, case.hostile or 0 do
        local age = i * 0.21 + t * (0.027 + (i % 7) * 0.001)
        local radius = 26 + (i % 10) * 7
        local e = hostile[i] and hostile[i].Ref and hostile[i].Ref:ToProjectile()
        if not e then
            e = Isaac.Spawn(EntityType.ENTITY_PROJECTILE, 0, 0, enemy.Position, Vector.Zero, enemy)
                :ToProjectile()
            e.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
            e.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
            hostile[i] = EntityPtr(e)
        end
        e.Height, e.FallingSpeed, e.FallingAccel = -20, 0, 0
        e.Position = Vector(320 + math.cos(age) * radius, 240 + math.sin(age) * radius)
        e.Velocity = Vector(-math.sin(age) * radius * 0.03, math.cos(age) * radius * 0.03)
    end
end
local function observe(t, at)
    local players, records = {}, {}
    for i = 0, Game():GetNumPlayers() - 1 do
        players[GetPtrHash(Isaac.GetPlayer(i))] = -(i + 1)
    end
    local function id(e)
        if not e or not e:Exists() then
            return 0
        end
        local player = players[GetPtrHash(e)]
        if player then
            return player
        end
        local data = e:GetData()
        return data and (config.host and data.__isaac_lan_entity or data.__isaac_lan_replica) or 0
    end
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if
            e:Exists()
            and (
                e.Type == EntityType.ENTITY_TEAR
                or e.Type == EntityType.ENTITY_LASER
                or e.Type == EntityType.ENTITY_PROJECTILE
            )
        then
            local key = id(e)
            assert(key ~= 0, "Attack missing authority identity")
            local p, v = e.Position, e.Velocity
            records[#records + 1] = string.pack(
                ">i8I4ffffi8i8i8i8",
                key,
                e.Type,
                p.X,
                p.Y,
                v.X,
                v.Y,
                id(e.Parent),
                id(e.SpawnerEntity),
                id(e.Child),
                id(e.Target)
            )
        end
    end
    table.sort(records)
    local bytes = table.concat(records)
    local hash = 2166136261
    for i = 1, #bytes do
        hash = ((hash ~ bytes:byte(i)) * 16777619) & 0xffffffff
    end
    return table.concat({ t, at, #records, hash }, ",")
end
return {
    cases = {
        { name = "idle" },
        { name = "fetus-tech0", loadout = true },
        { name = "fetus-tech0-multishot", loadout = true, multi = true },
        { name = "mixed-fetus-hostile", loadout = true, multi = true, hostile = 180 },
    },
    setup = setup,
    advance = advance,
    observe = observe,
}
