-- A coin-operated station for original Repentance. Its native effect and
-- stock sprite travel in ordinary entity snapshots, including the chosen seat.
local price, contactRadius, sampleInterval = 10, 24, 4
local machineSprite = "gfx/006.010_RestockMachine.anm2"
local spriteFilename = machineSprite:lower()
local function isMachine(entity)
    return entity:GetSprite():GetFilename():lower() == spriteFilename
end
return function(native, createFonts, decoration, canRevive)
    local marker, paidContact, lastTick
    local fonts = createFonts(native.presentation_assets.fonts)
    local function reset()
        marker, paidContact, lastTick = nil, false, nil
    end
    local function machine(room)
        local cached = marker and marker.Ref
        if cached and cached:Exists() then
            return cached:ToEffect()
        end
        paidContact = false
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, decoration, 0)) do
            if isMachine(entity) then
                marker = EntityPtr(entity)
                return entity:ToEffect()
            end
        end
        local position =
            room:FindFreePickupSpawnPosition(room:GetCenterPos() + Vector(80, 0), 0, true)
        local effect =
            Isaac.Spawn(EntityType.ENTITY_EFFECT, decoration, 0, position, Vector.Zero, nil)
                :ToEffect()
        effect:GetSprite():Load(machineSprite, true)
        effect:GetSprite():Play("Idle", true)
        effect.Color = Color(0.65, 0.86, 1, 1)
        effect.Timeout, effect.LifeSpan = -1, -1
        effect.State = 0
        marker = EntityPtr(effect)
        return effect
    end
    local function step(info)
        if
            info.authority ~= 1
            or info.ready ~= 1
            or info.players < 2
            or info.tick % sampleInterval ~= 0
            or lastTick == info.tick
        then
            return
        end
        lastTick = info.tick
        local game = Game()
        local level = game:GetLevel()
        if level:GetStage() < LevelStage.STAGE1_2 or not canRevive() then
            return
        end
        local start = level:GetStartingRoomIndex()
        local viewer
        for slot, position in pairs(native.rooms_positions()) do
            local seat = tonumber(slot)
            if
                position.index == start
                and position.dimension == 0
                and (info.connected & (1 << seat)) ~= 0
            then
                viewer = seat
                break
            end
        end
        if not viewer then
            paidContact = false
            return
        end
        local payer, recipient, station
        native.rooms_with_player(viewer, function()
            station = machine(game:GetRoom())
            local nearest = math.huge
            for i = 0, game:GetNumPlayers() - 1 do
                local player = Isaac.GetPlayer(i)
                local slot = player.ControllerIndex - 1
                if
                    slot >= 0
                    and slot < info.players
                    and (info.connected & (1 << slot)) ~= 0
                    and not player.Parent
                then
                    local distance = player.Position:DistanceSquared(station.Position)
                    if player:IsCoopGhost() then
                        if distance < nearest then
                            recipient, nearest = slot, distance
                        end
                    elseif
                        not player:IsDead()
                        and distance <= contactRadius * contactRadius
                        and player:GetNumCoins() >= price
                    then
                        payer = payer or player
                    end
                end
            end
            station.State = recipient and recipient + 1 or 0
        end)
        if not payer then
            paidContact = false
        elseif
            recipient
            and not paidContact
            and native.rooms_machine_revival(payer.ControllerIndex - 1, recipient)
        then
            payer:AddCoins(-price)
            paidContact = true
            station.State = 0
            SFXManager():Play(SoundEffect.SOUND_CASH_REGISTER, 1, 0, false, 1)
        end
    end
    local function render(_, effect, offset)
        if not isMachine(effect) then
            return
        end
        local font = fonts("small")
        local name = Options.Language == "zh" and "复活机" or "Revive"
        local target = effect.State > 0 and (" P" .. effect.State) or ""
        local label = name .. target .. "  " .. price .. "¢"
        local pos = Isaac.WorldToScreen(effect.Position) + offset
        local x = math.floor(pos.X - font:GetStringWidthUTF8(label) * 0.4)
        local y = pos.Y - 41
        font:DrawStringScaledUTF8(
            label,
            x + 1,
            y + 1,
            0.8,
            0.8,
            KColor(0.12, 0.1, 0.1, 1),
            0,
            false
        )
        font:DrawStringScaledUTF8(label, x, y, 0.8, 0.8, KColor(1, 1, 1, 1), 0, false)
    end
    return { step = step, reset = reset, render = render }
end
