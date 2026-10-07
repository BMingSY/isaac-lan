-- Local physical movement in a large room and in Downpour's mirror dimension.
local native=assert(_IsaacLan)
local f=assert(io.open('./lan-test-role.txt','r'));local host=f:read('*l')=='host';f:close()
f=assert(io.open('./lan-test-menu-port.txt','r'));local port=f:read('*l');f:close()
local function report(text) Isaac.DebugString('LAN_NETWORK '..text) end
local frame=_IsaacLanFrame
local renders,linked,chosen,finished=0,false,false,false
local large,axis,mirror=false,nil,false
local mirrorEntry,mirrorSeen,mirrorPrepared
local out=not host and assert(io.open('./lan-test-digest-camera.csv','w'))
local samples,mirrorSamples=0,0
local physical=0
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 360) then linked=true;_IsaacLanCommand(host and 'host' or 'join',host and port or '127.0.0.1:'..port);report('MENU_READY') end
    local s=frame()
    if s.phase==2 and not chosen then _IsaacLanCommand('choose','7:1');chosen=true end
    if host and s.phase==2 and s.players==2 and s.ready0==1 and s.ready1==1 then _IsaacLanCommand('start','LBCD0G4M:0:7:7:7:7') end
    if s.phase==4 or s.phase==9 then report('FAILED '..s.error) end
    local button=0
    if not host and s.prepared and native.rooms_ready() then
        local room=Game():GetRoom()
        if s.verified>=120 and s.verified<200 then button=axis=='x' and 8 or 2
        elseif s.verified>=240 and s.verified<320 then button=axis=='x' and 4 or 1
        elseif room:IsMirrorWorld() then
            mirrorSeen=mirrorSeen or s.verified
            local age=s.verified-mirrorSeen
            if age>=60 and age<72 then button=8 elseif age>=140 and age<152 then button=4 end
        end
    end
    physical=button;native.test_gamepad(button)
    if s.verified>=1250 and not finished then
        if not host then assert(samples>70 and mirrorSamples>20,'Large and mirror movement were not exercised');out:flush() end
        finished=true;report('PASS native mirror direction and large room camera')
    end
    return s
end
local gate=native.net_gate
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
    local level=Game():GetLevel()
    for i=0,level:GetRooms().Size-1 do local d=level:GetRooms():Get(i)
        if d.Data.Type==RoomType.ROOM_DEFAULT and d.Data.Shape>=RoomShape.ROOMSHAPE_1x2 then large=d.SafeGridIndex;break end
    end
    assert(large,'Large room fixture is missing')
    return gate(capture,function(t,n,b)
        before(t,n,b)
        if t==30 then assert(native.rooms_move(1,large,0,-1)) end
        if t==60 then assert(native.rooms_with_player(1,function()
            local room=Game():GetRoom();local p=Isaac.GetPlayer(0)
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e.Type~=1 then e:Remove() end end
            for i=0,room:GetGridSize()-1 do if room:GetGridCollision(i)~=GridCollisionClass.COLLISION_WALL then room:RemoveGridEntity(i,0,false) end end
            room:SetClear(true)
            local size=room:GetBottomRightPos()-room:GetTopLeftPos();axis=size.X>size.Y and 'x' or 'y'
            p.Position=room:GetCenterPos();report('LARGE_AXIS '..axis)
        end)) end
        if t==390 then
            Game():GetLevel():SetStage(2,StageType.STAGETYPE_REPENTANCE)
            Game():StartStageTransition(true,0,Isaac.GetPlayer(0));report('DOWNPOUR_TRANSITION')
        end
        if t>=630 and not mirrorEntry and native.rooms_ready() then
            mirrorEntry=t
            assert(native.rooms_ready(),'Downpour transition did not finish')
            local level=Game():GetLevel();local index=level:GetCurrentRoomIndex()
            assert(level:GetRoomByIdx(index,1).Data,'Mirror room fixture is missing')
            assert(native.rooms_move(1,index,1,-1));report('MIRROR_ENTRY')
        end
        if mirrorEntry and t>=mirrorEntry+30 and not mirrorPrepared then
            mirrorPrepared=true assert(native.rooms_with_player(1,function()
            assert(Game():GetRoom():IsMirrorWorld(),'Native mirror flag is missing')
            local room=Game():GetRoom()
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e.Type~=1 then e:Remove() end end
            for i=0,room:GetGridSize()-1 do if room:GetGridCollision(i)~=GridCollisionClass.COLLISION_WALL then room:RemoveGridEntity(i,0,false) end end
            room:SetClear(true);Isaac.GetPlayer(0).Position=room:GetCenterPos()
        end)) end
    end,collect,function(bytes,t,ack)
        if restore(bytes,t,ack)==false then return false end
        if t>=65 and t<350 then
            local room=Game():GetRoom();local size=room:GetBottomRightPos()-room:GetTopLeftPos();axis=size.X>size.Y and 'x' or 'y'
        end
        if mirrorEntry and t==mirrorEntry+110 then assert(native.rooms_with_player(1,function()
            Isaac.GetPlayer(0).Position=Game():GetRoom():GetCenterPos()
        end)) end
        return true
    end,function(input,sequence)
        present(input,sequence)
    end,beginFloor)
end
Isaac.AddCallback({Name='Isolated mirror and camera observer'},ModCallbacks.MC_POST_RENDER,function()
    if host or not _IsaacLanStatus().prepared or not native.rooms_ready() then return end
    local t=_IsaacLanStatus().verified;local p=Isaac.GetPlayer(native.rooms_heads()['1'])
    local room=Game():GetRoom();local mirror=room:IsMirrorWorld()
    if t>=100 and t<350 then samples=samples+1 end
    if mirror then mirrorSamples=mirrorSamples+1 end
    local position=Isaac.WorldToScreen(p.Position);local origin=Isaac.WorldToScreen(Vector.Zero)
    out:write(string.format('%.3f,%d,%.6f,%.6f,%.6f,%.6f,%s,%s,%d\n',Isaac.GetTime()/1000,t,p.Position.X,p.Position.Y,origin.X,origin.Y,axis or 'none',tostring(mirror),physical))
end)
