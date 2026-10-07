local native = assert(_IsaacLan)
local owner = {Name="Isolated native frontend test"}
local file = assert(io.open("./lan-test-role.txt","r"))
local host = file:read("*l") == "host"; file:close()
local pf=assert(io.open("./lan-test-menu-port.txt","r"));local port=pf:read("*l");pf:close()
local linked,finished=false,false
local countFile = assert(io.open("./lan-test-player-count.txt","r"))
local total = tonumber(countFile:read("*l")); countFile:close()
local function report(s) Isaac.DebugString("LAN_NETWORK "..s) end
local starts, renders, chosen = 0, 0, false
Isaac.AddCallback(owner,ModCallbacks.MC_POST_GAME_STARTED,function()
    starts=starts+1
    assert(linked and starts==1, "Network start depended on an earlier solo game")
    report("GAME_STARTED "..Game():GetSeeds():GetStartSeedString())
end)
local frame=_IsaacLanFrame
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=300 then
        linked=true
        _IsaacLanCommand(host and "host" or "join",host and port or "127.0.0.1:"..port)
        report("MENU_READY")
    end
    local status=frame()
    if status.phase==2 and not chosen then
        _IsaacLanCommand("choose",(host and "19" or "16")..":1")
        chosen=true
    end
    if linked then
        if status.phase==4 then report("FAILED "..status.error) end
        if host and status.phase==2 and status.players==total and status.ready0==1 and status.ready1==1 then
            _IsaacLanCommand("start","YV039KQF:0:19:16:0:0")
        end
        if status.verified>=600 and not finished then
            assert(starts==1,"Native menu start was not exercised")
            finished=true
            report("VERIFIED "..status.verified)
            report("PASS authoritative character forms")
        end
    end
    return status
end

local gate=native.net_gate
native.net_gate=function(capture,apply,collect,restore,present,beginFloor)
    local tick, inputTick=-1,0
    local first,other
    local switched=false
    local function synthetic()
        local values={}
        local trigger=0
        if not host and (inputTick==120 or inputTick==360) then trigger=1<<11 end
        for action=0,15 do
            local direction=({0,2,1,3})[math.floor(inputTick/20)%4+1]
            local v=(action==direction or action==5 or (action==11 and trigger~=0)) and 65535 or 0
            values[#values+1]=string.pack(">I2",v)
        end
        values[#values+1]=string.pack(">I2",trigger)
        inputTick=inputTick+1
        return table.concat(values)
    end
    return gate(synthetic,function(t,n,b)
        tick=t;apply(t,n,b)
        if not first then
            local level=Game():GetLevel();first=level:GetCurrentRoomIndex()
            for i=0,level:GetRooms().Size-1 do
                local desc=level:GetRooms():Get(i)
                if desc.SafeGridIndex~=first and desc.Data.Type==RoomType.ROOM_DEFAULT and desc.Data.Shape==RoomShape.ROOMSHAPE_1x1 then
                    other=desc.SafeGridIndex;break
                end
            end
            assert(other)
        end
        local moves={[20]={1,other},[80]={0,other},[200]={1,first},[300]={0,first},[420]={1,other}}
        if moves[t] then assert(native.rooms_move(moves[t][1],moves[t][2],0,0)) end
        if t%60==30 then
            local positions=native.rooms_positions()
            for slot=0,1 do assert(native.rooms_with_player(slot,function()
                for _,entity in ipairs(Isaac.GetRoomEntities()) do
                    local p=entity:ToPlayer()
                    if p then
                        assert(positions[tostring(p.ControllerIndex-1)].index==Game():GetLevel():GetCurrentRoomIndex(),"Character companion was left in a different room")
                        if p:GetPlayerType()==PlayerType.PLAYER_THESOUL and t>120 and t<360 then switched=true end
                    end
                end
            end)) end
        end
        if t==580 then assert(switched,"Forgotten did not switch to Soul");report("CHARACTERS native form switching and transfers verified") end
    end,collect,function(bytes,t,ack)
        if restore(bytes,t,ack)==false then return false end
        local v=_IsaacLanState.decode(bytes)
        for _,actor in ipairs(v[9]) do
            local player=Isaac.GetPlayer(actor[1])
            assert(player.ControllerIndex==actor[2] and player:GetPlayerType()==actor[4][1],"Character replica differs")
        end
    end,present,beginFloor)
end
