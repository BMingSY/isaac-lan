-- Host-owned gameplay, explicit portable state, and client-only presentation.
-- No Lua source, native pointers or Mod tables are transferred over the wire.
local native=assert(_IsaacLan)
local state={}
_IsaacLanState=state
local pack,unpack=string.pack,string.unpack
local function encode(value)
    local pieces,path={},{}
    local function put(v,depth)
        assert(depth<12,"State nesting exceeded")
        local t=type(v)
        if t=="boolean" then pieces[#pieces+1]=v and "\1" or "\0"
        elseif t=="number" then
            if math.type(v)=="integer" then
                if v>=-2147483648 and v<=2147483647 then pieces[#pieces+1]=pack(">Bi4",2,v)
                else pieces[#pieces+1]=pack(">Bi8",3,v) end
            else assert(v==v and math.abs(v)<math.huge,"Non-finite state value");pieces[#pieces+1]=pack(">Bf",4,v) end
        elseif t=="string" then assert(#v<=65535);pieces[#pieces+1]=pack(">Bs2",5,v)
        elseif t=="table" then
            assert(#v<=65535);pieces[#pieces+1]=pack(">BI2",6,#v)
            for i=1,#v do path[depth+1]=i;put(v[i],depth+1);path[depth+1]=nil end
        else error("Unsupported state value: "..t.." at ["..table.concat(path,"][").."]") end
    end
    put(value,0);return table.concat(pieces)
end
local function decode(bytes)
    assert(#bytes<=2*1024*1024,"State size exceeded")
    local cursor,nodes=1,0
    local function read(format) local value;value,cursor=unpack(">"..format,bytes,cursor);return value end
    local function get(depth)
        nodes=nodes+1;assert(depth<12 and nodes<250000,"State structure exceeded")
        local tag=read("B")
        if tag==0 then return false elseif tag==1 then return true
        elseif tag==2 then return read("i4") elseif tag==3 then return read("i8")
        elseif tag==4 then local n=read("f");assert(n==n and math.abs(n)<math.huge);return n
        elseif tag==5 then return read("s2")
        elseif tag==6 then local t={};local count=read("I2");for i=1,count do t[i]=get(depth+1) end;return t end
        error("Unknown state value tag")
    end
    local result=get(0);assert(cursor==#bytes+1,"Trailing state bytes");return result
end
state.encode,state.decode=encode,decode
local function vector(v) return {v.X,v.Y} end
local function vec(v) return Vector(v[1],v[2]) end
local function color(c) return {c.R,c.G,c.B,c.A,c.RO,c.GO,c.BO} end
local function col(c) return Color(table.unpack(c)) end
local nextID=1
local function id(e)
    if not e or not e:Exists() then return 0 end
    local d=e:GetData()
    if not d.__isaac_lan_entity then d.__isaac_lan_entity=nextID;nextID=nextID+1 end
    return d.__isaac_lan_entity
end
local common={"HitPoints","MaxHitPoints","CollisionDamage","Visible","FlipX","DepthOffset","Mass","Size","SpriteRotation"}
local schema={
    [1]={"Damage","MaxFireDelay","FireDelay","ShotSpeed","MoveSpeed","Luck","CanFly","TearHeight","TearRange","TearFallingSpeed","TearFallingAcceleration","HeadFrameDelay","ControlsEnabled"},
    [2]={"FallingAcceleration","FallingSpeed","Height","Rotation","Scale","WaitFrames"},
    [3]={"State","FireCooldown","HeadFrameDelay","MoveDirection","ShootDirection","LastDirection","OrbitAngleOffset","OrbitLayer","OrbitSpeed"},
    [4]={"ExplosionDamage","RadiusMultiplier","IsFetus"},
    [5]={"AutoUpdatePrice","Charge","OptionsPickupIndex","Price","ShopItemId","State","Timeout","Touched","Wait"},
    -- J460 exposes SampleLaser as userdata, not a boolean property.
    -- The native sampling flag and path are already carried by laser_path.
    [7]={"Angle","AngleDegrees","LastAngleDegrees","MaxDistance","Radius","Timeout","LaserLength","Shrink","DisableFollowParent","CurveStrength","GridHit"},
    [8]={"Rotation","RotationOffset","Scale","Charge","MaxDistance","PathFollowSpeed","PathOffset"},
    [9]={"Height","FallingSpeed","FallingAccel","Scale","Damage","Acceleration","HomingStrength","CurvingStrength"},
    [1000]={"State","Timeout","LifeSpan","Rotation","Scale","FallingAcceleration","FallingSpeed","m_Height","MinRadius","MaxRadius"},
    npc={"State","StateFrame","I1","I2","ProjectileCooldown","ProjectileDelay","Scale"}
}
local function typed(e)
    if e.Type==1 then return e:ToPlayer(),schema[1]
    elseif e.Type==2 then return e:ToTear(),schema[2]
    elseif e.Type==3 then return e:ToFamiliar(),schema[3]
    elseif e.Type==4 then return e:ToBomb(),schema[4]
    elseif e.Type==5 then return e:ToPickup(),schema[5]
    elseif e.Type==7 then return e:ToLaser(),schema[7]
    elseif e.Type==8 then return e:ToKnife(),schema[8]
    elseif e.Type==9 then return e:ToProjectile(),schema[9]
    elseif e.Type==1000 then return e:ToEffect(),schema[1000]
    elseif e:ToNPC() then return e:ToNPC(),schema.npc end
    return e,{}
end
local function fields(object,names)
    local result={}
    for i,name in ipairs(names) do
        local v=object[name]
        if type(v)~="number" and type(v)~="boolean" then
            error("Unsupported entity field "..object.Type.."."..object.Variant.."."..object.SubType.."."..name..": "..type(v))
        end
        result[i]=v
    end
    return result
end
local function writeFields(object,names,values)
    assert(#names==#values,"Entity schema mismatch")
    for i,name in ipairs(names) do object[name]=values[i] end
end
local function sprite(s)
    return {s:GetFilename(),s:GetAnimation(),s:GetFrame(),s:GetOverlayAnimation(),s:GetOverlayFrame(),s.FlipX,s.FlipY,s.Rotation,vector(s.Scale),vector(s.Offset),color(s.Color),assert(native.sprite_state(s))}
end
local function applySprite(s,v)
    if s:GetFilename()~=v[1] then
        if v[1]=="" then s:Reset() else s:Load(v[1],true) end
    end
    if v[2]~="" then s:SetFrame(v[2],v[3]) end
    if v[4]~="" then s:SetOverlayFrame(v[4],v[5]) else s:RemoveOverlay() end
    s.FlipX,s.FlipY,s.Rotation=v[6],v[7],v[8];s.Scale=vec(v[9]);s.Offset=vec(v[10]);s.Color=col(v[11])
    local changed=assert(native.sprite_state(s,v[12]))
    for _,layer in ipairs(changed) do s:ReplaceSpritesheet(layer[1],layer[2]) end
    if #changed>0 then s:LoadGraphics() end
end
local function entity(e,visual)
    if visual==nil then visual=true end
    local object,names=typed(e)
    return {id(e),e.Type,e.Variant,e.SubType,e.InitSeed,vector(e.Position),vector(e.Velocity),fields(e,common),fields(object,names),visual and sprite(e:GetSprite()) or false,id(e.Parent),id(e.SpawnerEntity),id(e.Child),id(e.Target),vector(e.SpriteOffset),vector(e.SpriteScale),color(e.Color),e.FrameCount,e:GetEntityFlags(),e.Type==7 and assert(native.laser_path(e:GetSprite())) or false,e.Type==7 and vector(e:ToLaser().EndPoint) or false,visual and assert(native.entity_shadow(e:GetSprite())) or false}
end
local heartTypes={"BrokenHearts","MaxHearts","BoneHearts","Hearts","RottenHearts","EternalHearts","GoldenHearts"}
local function inventory(p)
    local items={};local config=Isaac.GetItemConfig()
    for item=1,config:GetCollectibles().Size-1 do
        -- J460's ghost branch dereferences the ItemConfig even for unused IDs.
        if config:GetCollectible(item) then
            local count=p:GetCollectibleNum(item,true)
            if count>0 then items[#items+1]={item,count} end
        end
    end
    local active={}
    for slot=0,3 do active[#active+1]={p:GetActiveItem(slot),p:GetActiveCharge(slot)+p:GetBatteryCharge(slot)} end
    local hearts={}
    for _,name in ipairs(heartTypes) do hearts[#hearts+1]=p["Get"..name](p) end
    hearts[#hearts+1]=p:GetSoulHearts();hearts[#hearts+1]=p:GetBlackHearts()
    return {p:GetPlayerType(),items,active,hearts,{p:GetNumCoins(),p:GetNumBombs(),p:GetNumKeys(),p:GetSoulCharge(),p:GetBloodCharge()},
        {p:GetTrinket(0),p:GetTrinket(1)},{p:GetCard(0),p:GetCard(1)},{p:GetPill(0),p:GetPill(1)},p:IsCoopGhost(),p:GetEffects():GetNullEffectNum(NullItemID.ID_LOST_CURSE)}
end
local lastInventory,costumeIDs={},{}
local function costumeID(path)
    if costumeIDs[path]==nil then costumeIDs[path]=Isaac.GetCostumeIdByPath(path) end
    return costumeIDs[path]
end
local function actorSprites(p,actor)
    local sprites=assert(native.actor_sprites(actor[1],p:GetSprite()))
    local existing,desired={},{}
    for i=11,#sprites do local path=sprites[i]:GetFilename();existing[path]=(existing[path] or 0)+1 end
    for i=11,#actor[5] do local path=actor[5][i][1];desired[path]=(desired[path] or 0)+1 end
    -- Replica-side callbacks can add a null costume based on a provisional
    -- room before its authoritative contents arrive. The host owns actor
    -- appearance too; discard those stale costumes, not only ones we added.
    for path in pairs(existing) do if not desired[path] then
        local id=costumeID(path)
        if id>=0 then p:TryRemoveNullCostume(id) end
    end end
    for path,count in pairs(desired) do
        local id=costumeID(path)
        if id>=0 then for _=1,count-(existing[path] or 0) do p:AddNullCostume(id) end end
    end
    -- Adding/removing a costume can reallocate the native vector; reacquire
    -- its non-owning Sprite references before applying any animation state.
    return assert(native.actor_sprites(actor[1],p:GetSprite()))
end
local function applyActorVisuals(p,actor)
    if not actor[6] then return end
    local sprites=actorSprites(p,actor)
    -- Costume changes can rebuild the base body layers as well.
    applySprite(p:GetSprite(),actor[3][10])
    local used={}
    for i,v in ipairs(actor[5]) do
        if i<=10 then applySprite(sprites[i],v)
        else
            for j=11,#sprites do if not used[j] and sprites[j]:GetFilename()==v[1] then
                applySprite(sprites[j],v);used[j]=true;break
            end end
        end
    end
    assert(native.actor_pose(p:GetSprite(),actor[6]))
end
local hostLoops,replicaLoops,lastSound={},{},0
local function soundEvents(bytes)
    local result,cursor={},1
    while cursor<=#bytes do
        local serial,tick,id,volume,delay,loop,pitch,pan
        serial,tick,id,volume,delay,loop,pitch,pan,cursor=unpack(">I4I4I4fI4Bff",bytes,cursor)
        result[#result+1]={serial,tick,id,volume,delay,loop,pitch,pan}
    end
    return result
end
local function captureSound(slot)
    local bytes=native.sound_events(slot)
    local loops=hostLoops[slot] or {};hostLoops[slot]=loops
    for _,event in ipairs(soundEvents(bytes)) do if event[6]~=0 then loops[event[3]]=event end end
    local playing={}
    for id,event in pairs(loops) do
        if SFXManager():IsPlaying(id) then playing[#playing+1]=event else loops[id]=nil end
    end
    return {bytes,playing}
end
local function applySound(value,tick)
    local sfx=SFXManager()
    for _,event in ipairs(soundEvents(value[1])) do
        if event[1]>lastSound then
            if event[6]==0 and tick-event[2]<=10 then sfx:Play(event[3],event[4],event[5],false,event[7],event[8]) end
            lastSound=event[1]
        end
    end
    local playing={}
    for _,event in ipairs(value[2]) do
        playing[event[3]]=true
        if not replicaLoops[event[3]] or not sfx:IsPlaying(event[3]) then sfx:Play(event[3],event[4],event[5],true,event[7],event[8]) end
    end
    for id in pairs(replicaLoops) do if not playing[id] then sfx:Stop(id) end end
    replicaLoops=playing
end
local function applyInventory(p,v,refreshItems)
    if v[9] then return end -- Native ghost conversion owns its hidden inventory.
    if p:GetPlayerType()~=v[1] then p:ChangePlayerType(v[1]) end
    local effects=p:GetEffects()
    local delta=v[10]-effects:GetNullEffectNum(NullItemID.ID_LOST_CURSE)
    if delta~=0 then
        if delta>0 then effects:AddNullEffect(NullItemID.ID_LOST_CURSE,true,delta)
        else effects:RemoveNullEffect(NullItemID.ID_LOST_CURSE,-delta) end
    end
    if refreshItems then
    local desired={};for _,entry in ipairs(v[2]) do desired[entry[1]]=entry[2] end
    local config=Isaac.GetItemConfig()
    for item=1,config:GetCollectibles().Size-1 do
        local itemConfig=config:GetCollectible(item)
        if itemConfig and itemConfig.Type~=ItemType.ITEM_ACTIVE then
            local difference=(desired[item] or 0)-p:GetCollectibleNum(item,true)
            for _=1,math.abs(difference) do
                if difference>0 then p:AddCollectible(item,0,false) else p:RemoveCollectible(item,true) end
            end
        end
    end
    end
    for i,active in ipairs(v[3]) do
        local slot=i-1
        if p:GetActiveItem(slot)~=active[1] then
            if p:GetActiveItem(slot)~=0 then p:RemoveCollectible(p:GetActiveItem(slot),true,slot) end
            if active[1]~=0 then
                if slot>=2 then p:SetPocketActiveItem(active[1],slot,true) else p:AddCollectible(active[1],0,false,slot) end
            end
        end
        p:SetActiveCharge(active[2],slot)
    end
    for slot=0,1 do
        if p:GetTrinket(slot)~=v[6][slot+1] then
            for i=0,1 do local t=p:GetTrinket(i);if t~=0 then p:TryRemoveTrinket(t) end end
            -- AddTrinket puts the newest trinket in the first slot.
            for i=2,1,-1 do if v[6][i]~=0 then p:AddTrinket(v[6][i],false) end end
            break
        end
    end
    for _,pair in ipairs({{"Coins",1},{"Bombs",2},{"Keys",3}}) do p["Add"..pair[1]](p,v[5][pair[2]]-p["GetNum"..pair[1]](p)) end
    p:AddSoulCharge(v[5][4]-p:GetSoulCharge());p:AddBloodCharge(v[5][5]-p:GetBloodCharge())
    for i,name in ipairs(heartTypes) do
        local delta=v[4][i]-p["Get"..name](p)
        if delta~=0 then p["Add"..name](p,delta) end
    end
    local souls,black=v[4][8],v[4][9]
    if p:GetSoulHearts()~=souls or p:GetBlackHearts()~=black then
        p:AddSoulHearts(-p:GetSoulHearts())
        for offset=0,souls-1,2 do
            local count=math.min(2,souls-offset)
            if (black & (1<<(offset//2)))~=0 then p:AddBlackHearts(count) else p:AddSoulHearts(count) end
        end
    end
    for slot=0,1 do
        if p:GetCard(slot)~=v[7][slot+1] then p:SetCard(slot,v[7][slot+1]) end
        if v[7][slot+1]==0 and p:GetPill(slot)~=v[8][slot+1] then p:SetPill(slot,v[8][slot+1]) end
    end
end
local function roomState(slot)
    local value
    assert(native.rooms_with_player(slot,function()
        local room=Game():GetRoom();local entities,grids={},{}
        for _,e in ipairs(Isaac.GetRoomEntities()) do if e:Exists() and e.Type~=1 then entities[#entities+1]=entity(e) end end
        for index=0,room:GetGridSize()-1 do
            local grid=room:GetGridEntity(index)
            if grid then
                local door=grid:ToDoor()
                local extra=door and {door.Slot,door.TargetRoomIndex,door.CurrentRoomType,door.TargetRoomType,door.Direction,door:IsLocked(),door.Busted,door.ExtraVisible,sprite(assert(native.door_sprite(door:GetSprite())))} or false
                grids[#grids+1]={index,grid:GetType(),grid:GetVariant(),grid.State,grid.CollisionClass,grid.VarData,sprite(grid:GetSprite()),grid:GetSaveState().SpawnSeed,extra}
            end
        end
        value={room:IsClear(),room:GetFrameCount(),entities,grids,native.music_state(),native.room_layout()}
    end))
    return value
end
local captureTick,captureActors,captureVisuals=nil,{},{}
function state.capture(slot,tick)
    local game=Game();local level=game:GetLevel();local locations=native.rooms_positions();local loc={}
    if captureTick~=tick then captureTick=tick;captureActors={};captureVisuals={} end
    local actors={};local view=assert(locations[tostring(slot)])
    for index=0,game:GetNumPlayers()-1 do
        local p=Isaac.GetPlayer(index)
        local base=captureActors[index]
        if not base then base={index,p.ControllerIndex,entity(p,false),inventory(p),{},false};captureActors[index]=base end
        local position=locations[tostring(p.ControllerIndex-1)]
        if position and position.index==view.index and position.dimension==view.dimension then
            local full=captureVisuals[index]
            if not full then
                local visuals={}
                for _,s in ipairs(assert(native.actor_sprites(index,p:GetSprite()),"Native actor visual layout mismatch")) do visuals[#visuals+1]=sprite(s) end
                full={index,p.ControllerIndex,entity(p),base[4],visuals,assert(native.actor_pose(p:GetSprite()))};captureVisuals[index]=full
            end
            actors[#actors+1]=full
        else actors[#actors+1]=base end
    end
    for player=0,3 do
        local at=locations[tostring(player)]
        if at then
            local position=Isaac.GetPlayer(native.rooms_heads()[tostring(player)]).Position
            loc[#loc+1]={player,at.dimension,at.index,position.X,position.Y}
        end
    end
    local map={};local rooms=level:GetRooms()
    for i=0,rooms.Size-1 do
        local d=rooms:Get(i)
        for dimension=0,2 do
            local match=level:GetRoomByIdx(d.SafeGridIndex,dimension)
            if match and match.Data and match.ListIndex==d.ListIndex then
                map[#map+1]={d.SafeGridIndex,d.DisplayFlags,d.VisitedCount,d.Clear,d.ClearCount,d.Flags,dimension};break
            end
        end
    end
    return encode({4,tick,game:GetFrameCount(),level:GetStage(),level:GetStageType(),native.rooms_connected(),loc,map,actors,slot,roomState(slot),captureSound(slot),native.net_progress(),native.net_floor_epoch(),native.presentation_events(slot)})
end
local replicas,motion={},{}
local replicaRoom,receivedAt,receivedTick,lastRender=nil,0,-1,nil
local predictedInputs={}
local paused=false
local actorVisuals={}
local function ref(identifier)
    local pointer=replicas[identifier];return pointer and pointer.Ref or nil
end
local function discard(e)
    -- J460 can keep a removed NPC in its floor-render queue for one update.
    -- Its replica has no native death update to turn that pose into gore;
    -- hiding before removal prevents baking the old silhouette into the floor.
    e.Visible=false
    e:Remove()
end
local function applyEntity(e,v,now)
    e.Variant,e.SubType=v[3],v[4]
    e.Position=vec(v[6]);e.Velocity=vec(v[7]);writeFields(e,common,v[8])
    local object,names=typed(e);writeFields(object,names,v[9])
    e.SpriteOffset=vec(v[15]);e.SpriteScale=vec(v[16]);e.Color=col(v[17])
    -- Entity.Color resets the Sprite color (including alpha/colorize). Apply
    -- the complete native visual state last so fading creep stays faded.
    if v[10] then applySprite(e:GetSprite(),v[10]) end
    if v[22] then assert(native.entity_shadow(e:GetSprite(),v[22])) end
    -- Floor/wall flags tell EntityList::Update to bake and retire a sprite.
    -- Replicas instead keep receiving its pose/lifetime from the host. Baking
    -- an earlier death pose leaves a permanent silhouette in their backdrop.
    local floor,wall=EntityFlag.FLAG_RENDER_FLOOR,EntityFlag.FLAG_RENDER_WALL
    if e.Type==1 then
        -- Actor lifecycle/persistence flags belong to this native allocation.
        -- Copying the authority's lifecycle bits can retire a live actor when
        -- temporary forms change. Only the visual blink override is replicated.
        local blink=EntityFlag.FLAG_NO_DAMAGE_BLINK
        e:ClearEntityFlags(blink);e:AddEntityFlags(v[19]&blink)
    else
        e:ClearEntityFlags(e:GetEntityFlags())
        e:AddEntityFlags(v[19] & ~(floor|wall))
    end
    if (v[19] & floor)~=0 then e.DepthOffset=e.DepthOffset-10000 end
    if e.Type==7 then assert(native.laser_path(e:GetSprite(),v[20]));e:ToLaser().EndPoint=vec(v[21]) end
    e.EntityCollisionClass=EntityCollisionClass.ENTCOLL_NONE
    e.GridCollisionClass=EntityGridCollisionClass.GRIDCOLL_NONE
    -- Preserve ownership through EntityPtr; local allocation indices are never IDs.
    replicas[v[1]]=EntityPtr(e)
    local prior=motion[v[1]]
    motion[v[1]]={from=prior and prior.target or vec(v[6]),target=vec(v[6]),display=prior and prior.display or vec(v[6]),velocity=vec(v[7]),at=now,actor=e.Type==1,controller=e.Type==1 and e:ToPlayer().ControllerIndex or -1}
end
local replicaEpoch,awaitingFloor=nil,false
function state.beginFloor(epoch,stage,stageType,animation,same,rewind,rKey)
    if replicaEpoch and epoch<=replicaEpoch then return end
    replicaEpoch=epoch;awaitingFloor=true
    motion={};predictedInputs={};actorVisuals={};replicaRoom=nil
    if rewind and #rewind>0 then assert(native.rewind_begin(rewind),"Native hourglass rewind failed");return end
    if rKey then assert(native.r_key_begin(),"Native R Key restart failed");return end
    local localIndex=assert(native.rooms_heads()[tostring(native.net_poll().slot)])
    Game():GetLevel():SetStage(stage,stageType)
    Game():StartStageTransition(same,animation,Isaac.GetPlayer(localIndex))
end
function state.apply(bytes,tick,ack)
    if awaitingFloor and not native.rooms_ready() then return false end
    local value=decode(bytes);assert(value[1]==4 and value[2]==tick,"Invalid state schema")
    local game=Game();local level=game:GetLevel()
    local floorDiffers=level:GetStage()~=value[4] or level:GetStageType()~=value[5]
    if replicaEpoch==nil and not floorDiffers then replicaEpoch=value[14] end
    if value[14]~=replicaEpoch then
        if not native.rooms_ready() then return false end
        level:SetStage(value[4],value[5])
        local localIndex=assert(native.rooms_heads()[tostring(value[10])])
        game:StartStageTransition(true,0,Isaac.GetPlayer(localIndex))
        replicaEpoch=value[14];awaitingFloor=true
        motion={};predictedInputs={};actorVisuals={};replicaRoom=nil
        return false
    end
    if awaitingFloor then
        if not native.rooms_ready() then return false end
        awaitingFloor=false
    end
    assert(level:GetStage()==value[4] and level:GetStageType()==value[5],"Replica floor initialization failed")
    assert(native.room_layout(value[11][6]))
    local parts={pack(">BB",value[6],#value[7])}
    for _,p in ipairs(value[7]) do parts[#parts+1]=pack(">Bi4i4ff",table.unpack(p)) end
    assert(native.rooms_sync(table.concat(parts)))
    native.state_clock(value[3])
    assert(native.net_progress(value[13]))
    local now=Isaac.GetTime()/1000
    for _,actor in ipairs(value[9]) do
        local p=Isaac.GetPlayer(actor[1]);assert(p and p.ControllerIndex==actor[2],"Replica actor roster differs")
        if p:IsCoopGhost()~=actor[4][9] then assert(native.actor_ghost(actor[1],actor[4][9] and 1 or 0)) end
        local encoded=encode({actor[4][1],actor[4][2],actor[4][6]})
        applyInventory(p,actor[4],lastInventory[actor[3][1]]~=encoded or tick%30==0)
        lastInventory[actor[3][1]]=encoded
        applyEntity(p,actor[3],now)
        applyActorVisuals(p,actor)
    end
    actorVisuals=value[9]
    local mapChanged=false
    for _,d in ipairs(value[8]) do
        local descriptor=level:GetRoomByIdx(d[1],d[7])
        if descriptor and descriptor.Data then
            mapChanged=mapChanged or descriptor.DisplayFlags~=d[2] or descriptor.VisitedCount~=d[3] or descriptor.Clear~=d[4] or descriptor.Flags~=d[6]
            descriptor.DisplayFlags,descriptor.VisitedCount,descriptor.Clear,descriptor.ClearCount,descriptor.Flags=d[2],d[3],d[4],d[5],d[6]
        end
    end
    -- DisplayFlags already contain the host's visibility result. Recomputing
    -- it here both overrides that result and walks transient empty descriptors
    -- while the replica is replacing a room.
    local positions=native.rooms_positions();local localPosition=assert(positions[tostring(value[10])])
    local key=localPosition.dimension..":"..localPosition.index
    if key~=replicaRoom then motion={};predictedInputs={};replicaRoom=key;mapChanged=true end
    local currentIDs={}
    assert(native.rooms_with_player(value[10],function()
        local room=game:GetRoom();local data=value[11]
        for _,v in ipairs(data[3]) do
            local e=ref(v[1])
            if e and (not e:Exists() or e.Type~=v[2] or e.Variant~=v[3] or e.SubType~=v[4]) then discard(e);e=nil end
            if not e then
                -- A depleted pedestal has subtype zero. Spawn interprets zero
                -- as a new item roll, so use a concrete placeholder and apply
                -- the authoritative identity and sprite immediately afterward.
                local subtype=v[2]==5 and v[3]==100 and v[4]==0 and 1 or v[4]
                e=game:Spawn(v[2],v[3],vec(v[6]),vec(v[7]),ref(v[12]),subtype,v[5])
            end
            assert(e,"Replica spawn failed")
            e:GetData().__isaac_lan_replica=v[1];applyEntity(e,v,now);currentIDs[v[1]]=true
        end
        for _,v in ipairs(data[3]) do
            local e=ref(v[1]);e.Parent=ref(v[11]);e.SpawnerEntity=ref(v[12]);e.Child=ref(v[13]);e.Target=ref(v[14])
        end
        for _,e in ipairs(Isaac.GetRoomEntities()) do
            if e:Exists() and e.Type~=1 then
                local identifier=e:GetData().__isaac_lan_replica
                if not identifier or not currentIDs[identifier] then discard(e) end
            end
        end
        local present={}
        assert(native.door_slot(-1))
        for _,v in ipairs(data[4]) do
            local grid=room:GetGridEntity(v[1]);present[v[1]]=true
            if grid and grid:GetType()~=v[2] then room:RemoveGridEntity(v[1],0,false);grid=nil end
            if not grid then
                if v[9] then assert(native.door_slot(v[9][1],v[1]))
                else room:SpawnGridEntity(v[1],v[2],v[3],v[8]~=0 and v[8] or 1,v[6]) end
                grid=room:GetGridEntity(v[1])
            end
            if grid then
                -- Door variants change when locks/bars change. Preserve the
                -- native door-slot pointer instead of destroying that door.
                if grid:GetVariant()~=v[3] then assert(native.grid_variant(grid:GetSprite(),v[3])) end
                if v[9] then
                    local door=assert(grid:ToDoor());local d=v[9]
                    if door.CurrentRoomType~=d[3] or door.TargetRoomType~=d[4] then door:SetRoomTypes(d[3],d[4]) end
                    if door:IsLocked()~=d[6] then door:SetLocked(d[6]) end
                    door.Slot,door.TargetRoomIndex,door.Direction=d[1],d[2],d[5]
                    assert(native.door_slot(d[1],v[1],grid:GetSprite()))
                    door.Busted,door.ExtraVisible=d[7],d[8];applySprite(assert(native.door_sprite(door:GetSprite())),d[9])
                end
                grid.State,grid.CollisionClass,grid.VarData=v[4],v[5],v[6];applySprite(grid:GetSprite(),v[7])
            end
        end
        for i=0,room:GetGridSize()-1 do if not present[i] and room:GetGridEntity(i) then room:RemoveGridEntity(i,0,false) end end
        room:SetClear(data[1])
        assert(native.music_state(data[5]))
        if mapChanged then assert(native.map_refresh()) end
    end))
    for identifier,p in pairs(replicas) do if not p.Ref then replicas[identifier]=nil;motion[identifier]=nil;lastInventory[identifier]=nil end end
    for sequence in pairs(predictedInputs) do if sequence<=ack then predictedInputs[sequence]=nil end end
    receivedAt,receivedTick=now,tick
    applySound(value[12],tick)
    assert(native.presentation_events(value[15]))
    state.lastTick=tick
    return true
end
function state.present(input,sequence)
    if receivedTick<0 then return end
    -- Native room and Mod presentation updates run after receiving a packet.
    -- Reassert authoritative actor poses at the render boundary so local
    -- callbacks cannot replace a body or start an unrelated dance.
    for _,actor in ipairs(actorVisuals) do
        local p=Isaac.GetPlayer(actor[1])
        if p and p.ControllerIndex==actor[2] then applyActorVisuals(p,actor) end
    end
    local now=Isaac.GetTime()/1000;local dt=lastRender and math.min(now-lastRender,0.05) or 0;lastRender=now
    local status=_IsaacLanStatus();paused=status.pause~=0
    if paused then return end
    local values={unpack(">I2I2I2I2",input)}
    local direction=Vector((values[2]-values[1])/65535,(values[4]-values[3])/65535)
    assert(native.rooms_with_player(status.slot,function()
        if Game():GetRoom():IsMirrorWorld() then direction.X=-direction.X end
    end))
    if direction:Length()>1 then direction=direction:Normalized() end
    local pending=predictedInputs[sequence]
    if not pending then pending={direction=direction,dt=0};predictedInputs[sequence]=pending end
    pending.dt=math.min(pending.dt+dt,0.1)
    for identifier,m in pairs(motion) do
        local e=ref(identifier)
        if e then
            local age=math.max(0,now-m.at)
            local fraction=math.min(age*30,1)
            local position=m.from+(m.target-m.from)*fraction
            if m.actor and m.controller==status.slot+1 then
                position=m.target
                local p=e:ToPlayer()
                for _,control in pairs(predictedInputs) do position=position+control.direction*p.MoveSpeed*180*control.dt end
                -- Keep immediate local input, but reconcile new acknowledgements
                -- over several render frames instead of jumping to each packet.
                -- Large corrections (teleports) remain immediate.
                local advance=m.display+direction*p.MoveSpeed*180*dt
                local error=position-advance
                if error:LengthSquared()<160*160 then position=advance+error*(1-math.exp(-dt/0.12)) end
                assert(native.rooms_with_player(status.slot,function()
                    local room=Game():GetRoom();position=room:GetClampedPosition(position,math.max(5,e.Size))
                    if not p.CanFly and room:GetGridCollisionAtPos(position)~=GridCollisionClass.COLLISION_NONE then
                        -- Slide along blocked grids; returning to the older
                        -- authority position on every blocked frame flickers.
                        local x=Vector(position.X,m.display.Y)
                        local y=Vector(m.display.X,position.Y)
                        if room:GetGridCollisionAtPos(x)==GridCollisionClass.COLLISION_NONE then position=x
                        elseif room:GetGridCollisionAtPos(y)==GridCollisionClass.COLLISION_NONE then position=y
                        elseif room:GetGridCollisionAtPos(m.display)==GridCollisionClass.COLLISION_NONE then position=m.display
                        else position=m.target end
                    end
                end))
                m.display=position
            elseif age>1/30 then position=position+m.velocity*math.min(age-1/30,0.1)*30 end
            e.Position=position
        end
    end
end
function state.reset()
    native.sound_reset();native.presentation_reset();native.rewind_reset();hostLoops={};replicaLoops={};lastSound=0
    nextID=1;replicas={};motion={};lastInventory={};costumeIDs={};predictedInputs={};actorVisuals={};replicaRoom=nil;receivedTick=-1;lastRender=nil;replicaEpoch=nil;awaitingFloor=false;captureTick=nil;captureActors={};captureVisuals={}
end
