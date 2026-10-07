-- Targeted native fixtures. Normal-menu/raw-input coverage is run separately.
local native=assert(_IsaacLan)
local owner={Name="Isolated single-view replica regression"}
local f=assert(io.open("./lan-test-role.txt","r"));local host=f:read("*l")=="host";f:close()
f=assert(io.open("./lan-test-menu-port.txt","r"));local port=f:read("*l");f:close()
local function report(s) Isaac.DebugString("LAN_NETWORK "..s) end
local renders,linked,chosen,finished=0,false,false,false
local baseFrame=_IsaacLanFrame
local observedDevil,observedBoss,observedFloor=false,false,false
local floorBegan=false
local guestRoomCallbacks=0
Isaac.AddCallback(owner,ModCallbacks.MC_POST_NEW_ROOM,function() guestRoomCallbacks=guestRoomCallbacks+1 end)
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 360) then
        linked=true;_IsaacLanCommand(host and "host" or "join",host and port or "127.0.0.1:"..port);report("MENU_READY")
    end
    local s=baseFrame()
    if s.phase==2 and not chosen then _IsaacLanCommand("choose","7:1");chosen=true end
    if host and s.phase==2 and s.players==2 and s.ready0==1 and s.ready1==1 then _IsaacLanCommand("start","LBCD0G4M:0:7:7:7:7") end
    if s.phase==4 or s.phase==9 then report("FAILED "..s.error) end
    if not host and s.prepared and s.verified>=410 and s.verified<440 then
        assert(MusicManager():GetCurrentMusicID()==Music.MUSIC_BOSS,"Boss music did not switch immediately")
        observedBoss=true
    end
    if s.prepared and s.verified>=150 and s.verified<180 then report("VISUAL_READY") end
    if s.verified>=850 and not finished then
        if not host then assert(observedDevil and observedBoss and observedFloor and floorBegan,"Replica omitted a required fixture") end
        finished=true;report("PASS single-view special rooms and native floor transition")
    end
    return s
end
local gate=native.net_gate
local origin,large,boss,baselineCallbacks
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
    local level=Game():GetLevel();origin=level:GetCurrentRoomIndex()
    for i=0,level:GetRooms().Size-1 do
        local d=level:GetRooms():Get(i)
        if d.Data.Type==RoomType.ROOM_DEFAULT and d.Data.Shape>=RoomShape.ROOMSHAPE_1x2 then large=d.SafeGridIndex end
        if d.Data.Type==RoomType.ROOM_BOSS then boss=d.SafeGridIndex end
    end
    assert(large and boss)
    for i=0,Game():GetNumPlayers()-1 do Isaac.GetPlayer(i):SetMinDamageCooldown(10000) end
    return gate(function() return string.rep("\0",34) end,function(t,n,b)
        before(t,n,b)
        if t==30 then assert(native.rooms_move(1,large,0,0)) end
        if t==110 then assert(native.rooms_move(0,71,0,0)) end
        if t==185 then assert(native.rooms_with_player(0,function() Isaac.ExecuteCommand("goto s.devil.1") end)) end
        if t==195 then assert(native.rooms_with_player(0,function()
            assert(Game():GetRoom():GetType()==RoomType.ROOM_DEVIL,"Devil fixture was not entered")
            local enemy=Isaac.Spawn(EntityType.ENTITY_GAPER,0,0,Game():GetRoom():GetCenterPos(),Vector.Zero,nil)
            enemy:AddEntityFlags(EntityFlag.FLAG_FREEZE);enemy.MaxHitPoints=10000;enemy.HitPoints=10000
            Game():GetRoom():SetClear(false)
        end));report("HOST enemy Devil room while guest remains in large room") end
        if t==240 then local p=native.rooms_positions()["0"];assert(native.rooms_move(1,p.index,p.dimension,-1)) end
        if t==300 then assert(native.rooms_move(1,origin,0,0)) end
        if t==400 then assert(native.rooms_move(1,boss,0,0)) end
        if t==500 then assert(native.rooms_with_player(1,function()
            local p=Isaac.GetPlayer(0)
            Isaac.Spawn(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,CollectibleType.COLLECTIBLE_SAD_ONION,p.Position,Vector.Zero,nil)
        end)) end
        if t==580 then assert(native.rooms_with_player(0,function() Game():StartStageTransition(false,0,Isaac.GetPlayer(0)) end)) end
        if t==800 then assert(Game():GetLevel():GetStage()==2);report("HOST native second floor reached") end
    end,collect,function(bytes,t,ack)
        if restore(bytes,t,ack)==false then return false end
        local v=_IsaacLanState.decode(bytes)
        local pos=native.rooms_positions()
        if t>=150 and t<180 then
            assert(pos["1"].index==large and pos["0"].index==71)
            assert(native.rooms_with_player(1,function() assert(Game():GetRoom():GetRoomShape()>=RoomShape.ROOMSHAPE_1x2) end))
            baselineCallbacks=guestRoomCallbacks
        end
        if t>=205 and t<235 then
            assert(pos["0"].index<0 and pos["1"].index==large,"Special room did not remain separate")
            assert(guestRoomCallbacks==baselineCallbacks,"Remote Devil entry initialized a replica room")
            observedDevil=true
        end
        if t>=255 and t<280 then assert(native.rooms_with_player(1,function() assert(Game():GetRoom():GetType()==RoomType.ROOM_DEVIL,"Local Devil layout was not replicated") end)) end
        if t>=800 then
            assert(Game():GetLevel():GetStage()==2,"Online replica never completed native floor loading")
            observedFloor=true
        end
        for _,actor in ipairs(v[9]) do
            local p=Isaac.GetPlayer(actor[1]);assert(p:GetSoulHearts()==actor[4][4][8],"Multiplayer health differs")
        end
    end,present,function(epoch,stage,stageType,animation,same)
        assert(Game():GetLevel():GetStage()==1 and stage==1,"Floor event arrived after the new floor")
        assert(not same and animation==0,"Native transition arguments changed")
        floorBegan=true;report("FLOOR_BEGIN event before next-floor state time="..Isaac.GetTime())
        return beginFloor(epoch,stage,stageType,animation,same)
    end)
end
