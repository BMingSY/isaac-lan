local native=assert(_IsaacLan)
local owner={Name="Isolated native save/continue regression"}
local file=assert(io.open("./lan-test-role.txt","r"))
local host=file:read("*l")=="host";file:close()
local round,renders,starts=1,0,0
local pf=assert(io.open("./lan-test-menu-port.txt","r"));local port=pf:read("*l");pf:close()
local linked,chosen,finished=false,false,false
local saved,other,origin
local function report(s) Isaac.DebugString("LAN_NETWORK "..s) end
Isaac.AddCallback(owner,ModCallbacks.MC_POST_GAME_STARTED,function(_,continued)
    starts=starts+1
    assert(continued==(round==2),"Native continuation flag was incorrect")
    report("GAME_STARTED round="..round.." continued="..tostring(continued))
end)
Isaac.AddCallback(owner,ModCallbacks.MC_PRE_GAME_EXIT,function(_,save)
    if round==1 then
        if host then assert(save,"Network exit did not request a native save") end
        round=2;renders=0;linked=false;chosen=false
        report("RESUME native save exit")
    end
end)
local frame=_IsaacLanFrame
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 360) then
        linked=true
        _IsaacLanCommand(host and "host" or "join",host and port or "127.0.0.1:"..port)
        report("MENU_READY")
    end
    local status=frame()
    if status.phase==2 and not chosen then _IsaacLanCommand("choose","0:1");chosen=true end
    if status.phase==4 then report("FAILED "..status.error) end
    if host and status.phase==2 and status.players==2 and status.ready0==1 and status.ready1==1 then
        if round==2 then _IsaacLanCommand("resume","")
        else _IsaacLanCommand("start","YV039KQF:0:0:0:0:0") end
    end
    if round==2 and status.verified>=600 and not finished then
        assert(starts==2,"Continuation never started")
        finished=true;report("VERIFIED "..status.verified);report("PASS authoritative saved session")
    end
    return status
end
local gate=native.net_gate
native.net_gate=function(capture,apply,collect,restore,present,beginFloor)
    assert(Game():GetNumPlayers()==2,"Continue duplicated or removed players")
    for i=0,1 do Isaac.GetPlayer(i):SetMinDamageCooldown(10000) end
    local tick=-1
    return gate(function() return string.rep("\0",34) end,function(t,n,b)
        tick=t;apply(t,n,b)
        if round==1 and t==0 then
            local level=Game():GetLevel();origin=level:GetCurrentRoomIndex()
            for i=0,level:GetRooms().Size-1 do
                local d=level:GetRooms():Get(i)
                if d.SafeGridIndex~=origin and d.Data.Type==RoomType.ROOM_DEFAULT then other=d.SafeGridIndex;break end
            end
            assert(other)
            Isaac.GetPlayer(0):AddCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY)
            Isaac.GetPlayer(1):AddCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)
            Isaac.GetPlayer(0):AddCoins(7);Isaac.GetPlayer(1):AddCoins(11)
            assert(native.rooms_move(1,other,0,0))
        elseif round==1 and t==120 then
            saved={}
            for i=0,1 do
                local p=Isaac.GetPlayer(i)
                saved[i+1]={hearts=p:GetHearts(),coins=p:GetNumCoins()}
            end
            if host then assert(native.net_command(3))
            else assert(not native.net_command(3),"Guest could end the host's session") end
        elseif round==2 and t==0 then
            for i=0,1 do
                local p=Isaac.GetPlayer(i)
                assert(p:GetHearts()==saved[i+1].hearts and p:GetNumCoins()==saved[i+1].coins,"Native continue lost player stats")
            end
            assert(Isaac.GetPlayer(0):HasCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY),"Continue lost P1 collectible")
            assert(Isaac.GetPlayer(1):HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE),"Continue lost P2 collectible")
        elseif round==2 and t==5 then
            local positions=native.rooms_positions()
            assert(positions["0"].index==origin and positions["1"].index==other,"Continue failed to restore split rooms")
            report("RESUME native inventory and split rooms verified")
        end
    end,collect,function(bytes,t,ack)
        if restore(bytes,t,ack)==false then return false end
        if round==2 then
            assert(Isaac.GetPlayer(0):HasCollectible(CollectibleType.COLLECTIBLE_BROTHER_BOBBY))
            assert(Isaac.GetPlayer(1):HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE))
            assert(Isaac.GetPlayer(0):GetNumCoins()==18 and Isaac.GetPlayer(1):GetNumCoins()==18)
        end
    end,present,beginFloor)
end
