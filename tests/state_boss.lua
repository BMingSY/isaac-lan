local native=assert(_IsaacLan)
local owner={Name="Isolated authoritative state regression"}
local f=assert(io.open("./lan-test-role.txt","r"));local host=f:read("*l")=="host";f:close()
f=assert(io.open("./lan-test-menu-port.txt","r"));local port=f:read("*l");f:close()
local function report(text) Isaac.DebugString("LAN_NETWORK "..text) end
local renders,linked,chosen,finished=0,false,false,false
local originalFrame=_IsaacLanFrame
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 360) then
        linked=true;_IsaacLanCommand(host and "host" or "join",host and port or "127.0.0.1:"..port);report("MENU_READY")
    end
    local s=originalFrame()
    if s.phase==2 and not chosen then _IsaacLanCommand("choose","0:1");chosen=true end
    if host and s.phase==2 and s.players==2 and s.ready0==1 and s.ready1==1 then _IsaacLanCommand("start","YV039KQF:0:0:0:0:0") end
    if s.phase==4 or s.phase==9 then report("FAILED "..s.error) end
    if s.verified>=1100 and not finished then finished=true;assert(Game():GetLevel():GetStage()==2,"Floor checkpoint was not applied");report("PASS authoritative state simulation") end
    return s
end
local gate=native.net_gate
local ticks,corrected,samples=0,0,0
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
    for i=0,Game():GetNumPlayers()-1 do Isaac.GetPlayer(i):SetMinDamageCooldown(10000) end
    return gate(function()
        samples=samples+1
        local v={};for i=1,16 do v[i]=0 end
        -- Leave input neutral; spawned enemies may still push players through doors.
        local pieces={};for i=1,16 do pieces[i]=string.pack(">I2",v[i]) end
        pieces[17]=string.pack(">I2",0);return table.concat(pieces)
    end,function(t,n,b)
        before(t,n,b);ticks=t
        if t==0 then report("AUTHORITY host simulation begins") end
        if t==20 then
            Isaac.GetPlayer(1):AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
            Isaac.GetPlayer(1):AddCoins(7)
            Game():Spawn(EntityType.ENTITY_GAPER,0,Vector(400,300),Vector.Zero,nil,0,123456)
        end
        if t==100 then
            local level=Game():GetLevel();local origin=level:GetCurrentRoomIndex();local other
            for i=0,level:GetRooms().Size-1 do local d=level:GetRooms():Get(i);if d.SafeGridIndex~=origin and d.Data.Type==RoomType.ROOM_BOSS and d.Data.Shape==RoomShape.ROOMSHAPE_1x1 then other=d.SafeGridIndex;break end end
            assert(other);assert(native.rooms_move(1,other,0,0));report("HOST split room="..other)
        end
        if t==110 then assert(native.rooms_with_player(1,function() assert(Game():GetRoom():GetType()==RoomType.ROOM_BOSS,"Transfer loaded the wrong destination") end)) end
        if t==160 then assert(native.rooms_with_player(0,function()
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e:IsActiveEnemy(false) then e:Remove() end end
        end)) end
        if t==170 then assert(native.rooms_with_player(0,function() Isaac.GetPlayer(0):Kill() end));report("HOST died") end
        if t==290 then assert(Isaac.GetPlayer(0):IsCoopGhost(),"Host did not become ghost");report("HOST ghost") end
        if t>=310 and t<=350 then assert(native.rooms_with_player(1,function()
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e:IsActiveEnemy(false) then e:Kill() end end
        end)) end
        if t>=400 and t<=570 then assert(native.rooms_with_player(1,function()
            for _,e in ipairs(Isaac.GetRoomEntities()) do
                local p=e:ToPickup()
                if p and p.Variant==PickupVariant.PICKUP_COLLECTIBLE and p.SubType>0 then Isaac.GetPlayer(0).Position=p.Position;break end
            end
        end)) end
        if t==600 then
            assert(not Isaac.GetPlayer(0):IsCoopGhost(),"Boss did not revive remote teammate")
            assert(Isaac.GetPlayer(1):GetCollectibleCount()==4,"Boss reward did not match party count")
            report("HOST boss rewards and remote revival verified")
        end


        if t==610 then assert(native.net_command(1));report("HOST pause") end
        if t==630 then assert(native.net_command(2));report("HOST resume") end
        if t==650 then
            assert(native.rooms_with_player(0,function() Game():StartStageTransition(false,0,Isaac.GetPlayer(0)) end));report("HOST next floor")
        end
        if t%120==0 then report("HOST tick="..t) end
    end,function(slot,t)
        local bytes=collect(slot,t)
        if t==150 or t==300 then local out=assert(io.open("./authority-"..t..".bin","wb"));out:write(bytes);out:close() end
        return bytes
    end,function(bytes,t,ack)
        if restore(bytes,t,ack)==false then return false end;corrected=corrected+1
        local v=_IsaacLanState.decode(bytes)
        assert(native.rooms_connected()==v[6],"Roster not restored")
        for _,actor in ipairs(v[9]) do
            local p=Isaac.GetPlayer(actor[1])
            assert(math.abs(p.Position.X-actor[3][6][1])<0.01 and math.abs(p.Position.Y-actor[3][6][2])<0.01,"Actor position not restored")
            assert(p:GetNumCoins()==actor[4][5][1],"Resources not restored")
            assert(p:IsCoopGhost()==actor[4][9],"Ghost state not restored")
        end
        assert(native.rooms_with_player(1,function()
            local ids={}
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e:Exists() then ids[e:GetData().__isaac_lan_replica or -1]=e end end
            for _,e in ipairs(v[11][3]) do
                local actual=assert(ids[e[1]],"Authoritative entity missing")
                assert(actual.Type==e[2] and actual.Variant==e[3] and actual.SubType==e[4],"Entity identity differs tick="..t.." expected="..e[2].."."..e[3].."."..e[4].." actual="..actual.Type.."."..actual.Variant.."."..actual.SubType)
                assert(math.abs(actual.Position.X-e[6][1])<0.01 and math.abs(actual.Position.Y-e[6][2])<0.01,"Entity position differs")
            end
        end))
        if corrected%90==0 then report("CLIENT corrected="..corrected.." hostTick="..t) end
        if t>=40 and t<=45 then
            Isaac.GetPlayer(1):AddCoins(-7)
            for _=1,100 do Random() end
        end
        if t%120==0 then assert(native.rooms_with_player(1,function()
            local count,live=0,0;for _,e in ipairs(Isaac.GetRoomEntities()) do count=count+1;if e:Exists() then live=live+1 end end
            report("CLIENT entities="..count.." live="..live)
        end)) end
        if t>=150 and t<154 then
            assert(native.rooms_with_player(1,function()
                for _,e in ipairs(Isaac.GetRoomEntities()) do if e.Type~=1 and e:Exists() then e:Remove();break end end
                Isaac.Spawn(EntityType.ENTITY_EFFECT,EffectVariant.WALL_BUG,0,Vector(80,80),Vector.Zero,nil)
            end))
        end
    end,present,beginFloor)
end
