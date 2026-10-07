-- Native controller door entries while the other viewport remains still.
local native=assert(_IsaacLan)
local f=assert(io.open('./lan-test-role.txt','r'));local host=f:read('*l')=='host';f:close()
f=assert(io.open('./lan-test-menu-port.txt','r'));local port=f:read('*l');f:close()
local function report(s) Isaac.DebugString('LAN_NETWORK '..s) end
local original=_IsaacLanFrame
local renders,linked,chosen,done=0,false,false,false
local entries,current,waitUntil,newRooms,initialRooms=0,nil,0,0,nil
Isaac.AddCallback({Name='Isolated peer door viewport observer'},ModCallbacks.MC_POST_NEW_ROOM,function() newRooms=newRooms+1 end)
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 360) then
        linked=true;_IsaacLanCommand(host and 'host' or 'join',host and port or '127.0.0.1:'..port);report('MENU_READY')
    end
    local s=original()
    if s.phase==2 and not chosen then _IsaacLanCommand('choose','7:1');chosen=true end
    if host and s.phase==2 and s.players==2 and s.ready0==1 and s.ready1==1 then _IsaacLanCommand('start','LBCD0G4M:0:7:7:7:7') end
    if s.phase==4 or s.phase==9 then report('FAILED '..s.error) end
    local buttons=0
    if s.prepared and native.rooms_ready() then
        if host then
            if s.verified>=10 and not initialRooms then initialRooms=newRooms end
            if s.verified>=60 then
                assert(native.rooms_positions()['0'].index==84,'Stationary host changed rooms')
                assert(newRooms==initialRooms,'Remote room entry dispatched a global local-room callback')
            end
        elseif s.verified>=60 then
            local room=Game():GetRoom();local index=Game():GetLevel():GetCurrentRoomIndex()
            if not current then current=index end
            if current~=index then
                entries=entries+1;current=index;waitUntil=s.verified+30
                report('PEER_ENTRY '..entries..' room='..index..' tick='..s.verified)
            end
            if entries<6 and s.verified>=waitUntil then
                local p=Isaac.GetPlayer(native.rooms_heads()['1'])
                local target=index==84 and 71 or 84
                for slot=0,7 do local door=room:GetDoor(slot)
                    if door and door.TargetRoomIndex==target then
                        local delta=door.Position-p.Position
                        if math.abs(delta.X)>8 then buttons=delta.X>0 and 8 or 4 else buttons=delta.Y>0 and 2 or 1 end
                    end
                end
            end
        end
    end
    native.test_gamepad(buttons)
    if s.verified>=640 and not done then
        if not host then assert(entries>=6,'Native raw-input door cycle was not completed') end
        done=true;report('PASS peer native door viewport isolation entries='..entries)
    end
    return s
end
local gate=native.net_gate
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
    return gate(capture,function(t,n,b)
        before(t,n,b)
        if t==20 then assert(native.rooms_move(1,71,0,-1)) end
        if t==30 then assert(native.rooms_with_player(1,function()
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e:ToNPC() then e:Remove() end end
            Game():GetRoom():SetClear(true)
        end)) end
        if t==40 then assert(native.rooms_move(1,84,0,-1)) end
    end,collect,restore,present,beginFloor)
end
