-- Targeted native fixtures. Normal-menu/raw-input coverage is run separately.
local native=assert(_IsaacLan)
local owner={Name="Isolated conditional door protection regression"}
local f=assert(io.open("./lan-test-role.txt","r"));local host=f:read("*l")=="host";f:close()
f=assert(io.open("./lan-test-menu-port.txt","r"));local port=f:read("*l");f:close()
local function report(s) Isaac.DebugString("LAN_NETWORK "..s) end
local renders,linked,chosen,finished=0,false,false,false
local baseFrame=_IsaacLanFrame

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
    if s.prepared and s.verified>=150 and s.verified<180 then report("VISUAL_READY") end
    if s.verified>=380 and not finished then
        finished=true;report("PASS door protection only when joining occupied combat")
    end
    return s
end
local gate=native.net_gate
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
    local level=Game():GetLevel();local origin=level:GetCurrentRoomIndex();local combat,empty
    for i=0,level:GetRooms().Size-1 do
        local d=level:GetRooms():Get(i)
        if d.Data.Type==RoomType.ROOM_DEFAULT and d.SafeGridIndex~=origin then
            if not combat then combat=d.SafeGridIndex elseif not empty then empty=d.SafeGridIndex end
        end
    end
    assert(combat and empty)
    local function player(slot,fn) assert(native.rooms_with_player(slot,function()
        local actor
        for i=0,Game():GetNumPlayers()-1 do local p=Isaac.GetPlayer(i);if p.ControllerIndex==slot+1 then actor=p;break end end
        fn(assert(actor),Game():GetRoom())
    end)) end
    local function freeze(slot) player(slot,function(p,room)
        for _,e in ipairs(Isaac.GetRoomEntities()) do if e:ToNPC() then e:AddFreeze(EntityRef(p),10000) end end
        p:ResetDamageCooldown()
    end) end
    return gate(function() return string.rep("\0",34) end,function(t,n,b)
        before(t,n,b)
        -- Native freeze durations are capped. Renew them without touching
        -- actor cooldowns, which are what this fixture measures.
        if t%30==0 then for slot=0,1 do player(slot,function(p)
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e:ToNPC() then e:AddFreeze(EntityRef(p),150) end end
        end) end end
        if t==30 then assert(native.rooms_move(1,empty,0,0)) end
        if t==32 then player(1,function(p) assert(p:GetDamageCooldown()<80,"Fresh room granted join protection") end);report("Fresh room: no bonus") end
        if t==50 then freeze(1) end
        if t==80 then assert(native.rooms_move(1,origin,0,0)) end
        if t==82 then player(1,function(p) assert(p:GetDamageCooldown()<80,"Cleared occupied room granted protection") end);report("Cleared occupied room: no bonus") end
        if t==100 then assert(native.rooms_move(0,combat,0,0)) end
        if t==110 then player(0,function(p,room)
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e:ToNPC() then e:AddFreeze(EntityRef(p),10000) end end
            p:ResetDamageCooldown()
            local e=Isaac.Spawn(EntityType.ENTITY_GAPER,0,0,room:GetCenterPos()+Vector(60,80),Vector.Zero,nil)
            e:AddFreeze(EntityRef(p),10000);e.MaxHitPoints=10000;e.HitPoints=10000;room:SetClear(false)
        end) end
        if t==120 then player(0,function(p,room) report("PRE_JOIN clear="..tostring(room:IsClear()).." controller="..p.ControllerIndex) end);assert(native.rooms_move(1,combat,0,0)) end
        if t==122 then player(1,function(p) report("ARRIVAL cooldown="..p:GetDamageCooldown());assert(p:GetDamageCooldown()>=85,"Joining a resident combat room omitted protection") end)
            player(0,function(p) assert(p:GetDamageCooldown()<80,"Resident gained arrival protection") end)
            report("Occupied combat room: protection only for arriving player") end
        if t==220 then assert(native.rooms_move(1,origin,0,0)) end
        if t==222 then player(1,function(p) assert(p:GetDamageCooldown()<80,"Regular return granted protection") end) end
        if t==240 then assert(native.rooms_move(0,origin,0,0)) end
        if t==270 then assert(native.rooms_move(1,combat,0,0)) end
        if t==272 then player(1,function(p) assert(p:GetDamageCooldown()<80,"Empty combat room granted protection") end);report("Unoccupied combat room: no bonus") end
    end,collect,restore,present,beginFloor)
end
