local native=assert(_IsaacLan)
local owner={Name="Isolated challenge room ownership"}
local f=assert(io.open("./lan-test-role.txt","r"));local host=f:read("*l")=="host";f:close()
f=assert(io.open("./lan-test-menu-port.txt","r"));local port=f:read("*l");f:close()
local function report(s) Isaac.DebugString("LAN_NETWORK "..s) end
local renders,linked,chosen,finished=0,false,false,false
local done=false
local frame=_IsaacLanFrame
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 600) then
        linked=true;_IsaacLanCommand(host and "host" or "join",host and port or "127.0.0.1:"..port);report("MENU_READY")
    end
    local s=frame()
    if s.phase==2 and not chosen then _IsaacLanCommand("choose","0:1");chosen=true end
    if host and s.phase==2 and s.players==2 and s.ready0==1 and s.ready1==1 then _IsaacLanCommand("start","N024KHNP:0:0:0:0:0") end
    if s.phase==4 or s.phase==9 then report("FAILED "..s.error) end
    if done and not finished then finished=true;report("PASS challenge room ownership") end
    return s
end
local gate=native.net_gate
if host then os.remove("D:/isaac-lan-lab/client-002/game/lan-test-challenge-done.txt") end
local selected,waves,hadEnemies,complete=nil,0,false,false
local nextSearch,startTick,doneTick=20,nil,nil
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
    for i=0,Game():GetNumPlayers()-1 do Isaac.GetPlayer(i):SetMinDamageCooldown(10000) end
    return gate(function() return string.rep("\0",34) end,function(t,n,b)
        before(t,n,b)
        if not selected and t>=nextSearch then
            local level=Game():GetLevel()
            for i=0,level:GetRooms().Size-1 do local d=level:GetRooms():Get(i)
                if d.Data.Type==RoomType.ROOM_CHALLENGE then selected=d.SafeGridIndex;break end
            end
            if selected then
                assert(native.rooms_move(1,selected,0,0));startTick=t
                report("CHALLENGE selected="..selected.." floor="..level:GetStage())
            else
                assert(level:GetStage()<6,"Fixture generated no challenge room")
                assert(native.rooms_with_player(0,function() Game():StartStageTransition(false,0,Isaac.GetPlayer(0)) end))
                nextSearch=t+300
            end
        end
        if startTick and t==startTick+10 then assert(native.rooms_with_player(1,function()
            local room=Game():GetRoom();assert(room:GetType()==RoomType.ROOM_CHALLENGE)
            local chest=Isaac.Spawn(5,50,0,room:GetCenterPos(),Vector.Zero,nil):ToPickup()
            Isaac.GetPlayer(0).Position=chest.Position
            report("CHALLENGE player touches chest")
        end)) end
        if startTick and t==startTick+100 then
            local rooms=Game():GetLevel():GetRooms()
            for i=0,rooms.Size-1 do local d=rooms:Get(i)
                if d.Data.Type==RoomType.ROOM_DEFAULT and d.SafeGridIndex~=native.rooms_positions()["0"].index then
                    assert(native.rooms_move(0,d.SafeGridIndex,0,0));report("HOST moved during guest challenge");break
                end
            end
        end
        if startTick and t>=startTick+15 then assert(native.rooms_with_player(1,function()
            local room=Game():GetRoom();local enemies={}
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e:IsActiveEnemy(false) then enemies[#enemies+1]=e end end
            if #enemies>0 and not hadEnemies then waves=waves+1;report("CHALLENGE wave="..waves) end
            hadEnemies=#enemies>0
            if t>=startTick+120 and t%60==0 then for _,e in ipairs(enemies) do e:Kill() end end
            complete=room:IsAmbushDone()
        end)) end
        if startTick and t>=startTick+150 and waves>=2 and complete and not doneTick then
            doneTick=t;report("CHALLENGE complete waves="..waves)
        end
        if startTick then assert(t<startTick+650 or doneTick,"Challenge waves did not complete in their own room") end
        if doneTick and t>=doneTick+30 then done=true;local f=assert(io.open("D:/isaac-lan-lab/client-002/game/lan-test-challenge-done.txt","w"));f:write("done");f:close() end
    end,collect,function(bytes,t,ack)
        if restore(bytes,t,ack)==false then return false end
        local value=_IsaacLanState.decode(bytes)
        if value[2]>=0 then
            local flag=io.open("D:/isaac-lan-lab/client-002/game/lan-test-challenge-done.txt","r")
            if flag then flag:close();done=true end
        end
        if value[4]>=1 then assert(native.rooms_with_player(1,function()
            local ids={};for _,e in ipairs(Isaac.GetRoomEntities()) do if e:Exists() then ids[e:GetData().__isaac_lan_replica or -1]=e end end
            for _,e in ipairs(value[11][3]) do assert(ids[e[1]],"Challenge entity missing on guest") end
        end)) end
    end,present,beginFloor)
end
