local native = assert(_IsaacLan)
local owner = {Name="Isolated native frontend test"}
local file = assert(io.open("./lan-test-role.txt","r"))
local host = file:read("*l") == "host"; file:close()
local linked,finished=false,false
local viewTick=-1
local countFile = assert(io.open("./lan-test-player-count.txt","r"))
local total = tonumber(countFile:read("*l")); countFile:close()
local function report(s) Isaac.DebugString("LAN_NETWORK "..s) end
local starts, renders, chosen = 0, 0, false
Isaac.AddCallback(owner,ModCallbacks.MC_POST_GAME_STARTED,function()
    starts=starts+1
    assert(linked and starts==1, "Network start depended on an earlier solo game")
    report("GAME_STARTED "..Game():GetSeeds():GetStartSeedString())
end)
local portFile=assert(io.open("./lan-test-menu-port.txt","r"))
local port=portFile:read("*l");portFile:close()
local frame=_IsaacLanFrame
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 600) then
        linked=true
        _IsaacLanCommand(host and "host" or "join",host and port or "127.0.0.1:"..port)
        report("MENU_READY")
    end
    local status=frame();viewTick=status.verified
    if status.phase==2 and not chosen then
        _IsaacLanCommand("choose","0"..":1")
        chosen=true
    end
    if linked then
        if status.phase==4 then report("FAILED "..status.error) end
        if host and status.phase==2 and status.players==total and status.ready0==1 and status.ready1==1 then
            _IsaacLanCommand("start","LSB3EQM1:0:0:0:0:0")
        end
        if status.verified>=600 and not finished then
            assert(starts==1,"Native menu start was not exercised")
            finished=true
            report("VERIFIED "..status.verified)
            report("PASS local view ownership")
        end
    end
    return status
end

local gate=native.net_gate
native.net_gate=function(capture,apply,collect,restore,present,beginFloor)
    for i=0,Game():GetNumPlayers()-1 do Isaac.GetPlayer(i):SetMinDamageCooldown(10000) end
    local tick,inputTick=-1,0
    local origin,destination,exitDoor,moveDir,entry
    local started, large, source, reciprocal, witness, witnessSeed, movement = nil,nil,nil,nil,nil,nil,nil
    local checked,arrivalChecked=false,false
    local function synthetic()
        inputTick=inputTick+1
        local current=_IsaacLanStatus();local action=-1
        if not host and current.prepared and current.verified>=25 and current.verified<70 then
            local locations=native.rooms_positions()
            if locations["0"].index~=locations["1"].index then
                assert(native.rooms_with_player(1,function()
                    for slot=0,7 do
                        local door=Game():GetRoom():GetDoor(slot)
                        if door and door.TargetRoomIndex>=0 then
                            local desc=Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex,0)
                            if desc and desc.SafeGridIndex==locations["0"].index then action=({[0]=0,2,1,3})[slot%4];break end
                        end
                    end
                end))
            end
        elseif current.verified>=100 and current.verified<230 then action=host and 1 or 0 end
        local values={};for i=0,15 do values[#values+1]=string.pack(">I2",i==action and 65535 or 0) end
        values[#values+1]=string.pack(">I2",0);return table.concat(values)
    end
    return gate(synthetic,function(t,n,b)
        tick=t;viewTick=t;apply(t,n,b)
        if t==0 then Isaac.GetPlayer(0):SetCard(0,Card.CARD_FOOL);Isaac.GetPlayer(1):SetCard(0,Card.CARD_WORLD) end
        local game=Game(); local level=game:GetLevel()
        if not started and t>=20 and native.rooms_ready() then
            local rooms=level:GetRooms()
            for i=0,rooms.Size-1 do
                local desc=rooms:Get(i)
                if desc.Data.Type==RoomType.ROOM_DEFAULT and desc.Data.Shape>=RoomShape.ROOMSHAPE_1x2 then
                    report("LARGE candidate index="..desc.SafeGridIndex.." shape="..desc.Data.Shape)
                    assert(native.rooms_move(0,desc.SafeGridIndex,0,0))
                    large=desc.SafeGridIndex;started=t;break
                end
            end
            assert(started,"Report seed has no large room")
        elseif started and t==started+2 then
            assert(native.rooms_with_player(0,function()
                local room=game:GetRoom()
                for slot=0,7 do
                    local door=room:GetDoor(slot)
                    if door and door.TargetRoomIndex>=0 and door.TargetRoomIndex<169 then
                        local desc=level:GetRoomByIdx(door.TargetRoomIndex,0)
                        if desc.Data and desc.SafeGridIndex~=large then source=desc.SafeGridIndex;reciprocal=slot;break end
                    end
                end
                assert(source,"Large room had no usable doorway")
                witness=Isaac.Spawn(EntityType.ENTITY_GAPER,0,0,room:GetCenterPos(),Vector.Zero,nil)
                witness:AddEntityFlags(EntityFlag.FLAG_FREEZE);witness.MaxHitPoints=10000;witness.HitPoints=10000;witnessSeed=witness.InitSeed
            end))
            assert(native.rooms_move(1,source,0,0))
        elseif started and t==started+5 then
            assert(native.rooms_with_player(1,function()
                local room=game:GetRoom()
                for slot=0,7 do
                    local door=room:GetDoor(slot)
                    if door and door.TargetRoomIndex>=0 and door.TargetRoomIndex<169 then
                        local desc=level:GetRoomByIdx(door.TargetRoomIndex,0)
                        if desc and desc.SafeGridIndex==large then
                            exitDoor=slot;door:Open();break
                        end
                    end
                end
                assert(exitDoor,"Large room lacked a reciprocal door")
                moveDir=({[0]=0,2,1,3})[exitDoor%4]
                local inward=({[0]=Vector(1,0),Vector(0,1),Vector(-1,0),Vector(0,-1)})[exitDoor%4]
                Isaac.GetPlayer(0).Position=room:GetDoorSlotPosition(exitDoor)+inward*8
                movement=t+1
                report("LARGE walking source="..source.." leave="..exitDoor.." target="..large.." entry="..reciprocal)
            end))
        elseif started and movement and t==movement+40 then
            local positions=native.rooms_positions()
            assert(positions["0"].index==large and positions["1"].index==large,"Walking through a door did not join the large room")
            assert(native.rooms_with_player(1,function()
                assert(witness:Exists() and witness.InitSeed==witnessSeed,"Large-room battle was recreated")
                local player
                for i=0,game:GetNumPlayers()-1 do if Isaac.GetPlayer(i).ControllerIndex==2 then player=Isaac.GetPlayer(i) end end
                assert(player and arrivalChecked,"Large-room arrival was not checked")
            end))
            checked=true;report("DOOR native walking exit verified");report("LARGE doorway and battle identity verified")
        end
        if movement and not arrivalChecked and native.rooms_positions()["1"].index==large then
            assert(native.rooms_with_player(1,function()
                local player
                for i=0,game:GetNumPlayers()-1 do if Isaac.GetPlayer(i).ControllerIndex==2 then player=Isaac.GetPlayer(i) end end
                local expected=game:GetRoom():GetDoorSlotPosition(reciprocal)
                assert(player and player.Position:Distance(expected)<90,"Wrong large-room entrance on arrival")
                arrivalChecked=true
            end))
        end
        if t==250 then
            assert(native.rooms_move(0,source,0,0))
            report("CAMERA split host="..source.." client="..large)
        elseif t==300 then
            assert(native.rooms_with_player(1,function()
                local room=game:GetRoom()
                for i=0,game:GetNumPlayers()-1 do Isaac.GetPlayer(i).Position=room:GetCenterPos()+Vector(120,60) end
            end))
        end
        if t==400 then assert(native.rooms_with_player(1,function()
            local room=Game():GetRoom()
            Isaac.Spawn(EntityType.ENTITY_PICKUP,PickupVariant.PICKUP_COLLECTIBLE,CollectibleType.COLLECTIBLE_SACRED_HEART,room:GetCenterPos(),Vector.Zero,nil)
            report("COSMETIC guest quality four spawned")
        end)) end
        if t==590 then assert(checked,"Large-room test did not complete") end
    end,collect,restore,present,beginFloor)
end

local lastView=-1
Isaac.AddCallback(owner,ModCallbacks.MC_POST_RENDER,function()
    if viewTick<300 or viewTick%60~=0 or lastView==viewTick then return end
    lastView=viewTick
    if viewTick>=480 then
        local music=MusicManager():GetCurrentMusicID()
        local dance=Isaac.GetMusicIdByName("specialist")
        if host then assert(music~=dance,"Guest dance replaced host music")
        else
            assert(EID,"Client EID did not load")
            assert(music==dance,"Guest dance music not presented in its room")
            local found=false
            for _,sprite in ipairs(native.actor_sprites(0,Isaac.GetPlayer(0):GetSprite())) do
                if sprite:GetFilename():lower():find("specialist",1,true) then found=true end
            end
            assert(found,"Guest dance costume missing")
        end
        report("COSMETIC own music="..music.." dance="..dance)
    end
    local game=Game()
    assert(Isaac.GetPlayer(0).ControllerIndex==(host and 1 or 2),"Render selected another player as its primary actor")
    local positions=native.rooms_positions()
    assert(game:GetLevel():GetCurrentRoomIndex()==positions[host and "0" or "1"].index,"Rendering another player room context")
    local p
    for i=0,game:GetNumPlayers()-1 do
        local candidate=Isaac.GetPlayer(i)
        if candidate.ControllerIndex==(host and 1 or 2) then p=candidate end
    end
    if p then
        local v=Isaac.WorldToScreen(p.Position)
        if viewTick>=360 then
            assert(v.X>=0 and v.X<=480 and v.Y>=0 and v.Y<=270,"Local player left the isolated 480x270 viewport")
        end
        local o=game:GetRoom():GetRenderScrollOffset()
        report(string.format("VIEW tick=%d room=%d pos=%.2f,%.2f screen=%.2f,%.2f scroll=%.2f,%.2f",viewTick,game:GetLevel():GetCurrentRoomIndex(),p.Position.X,p.Position.Y,v.X,v.Y,o.X,o.Y))
    end
end)
