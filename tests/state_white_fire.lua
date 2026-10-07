local native=assert(_IsaacLan)
local f=assert(io.open('./lan-test-role.txt','r'));local host=f:read('*l')=='host';f:close()
f=assert(io.open('./lan-test-menu-port.txt','r'));local port=f:read('*l');f:close()
local function report(s) Isaac.DebugString('LAN_NETWORK '..s) end
local original=_IsaacLanFrame
local renders,linked,chosen,done=0,false,false,false
local origin,other,changed,returned,departed
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 360) then linked=true;_IsaacLanCommand(host and 'host' or 'join',host and port or '127.0.0.1:'..port);report('MENU_READY') end
    local s=original()
    if s.phase==2 and not chosen then _IsaacLanCommand('choose','0:1');chosen=true end
    if host and s.phase==2 and s.players==2 and s.ready0==1 and s.ready1==1 then _IsaacLanCommand('start','YV039KQF:0:0:0:0:0') end
    if s.phase==4 or s.phase==9 then report('FAILED '..s.error) end
    native.test_gamepad(0)
    if s.verified>=420 and not done then
        assert(changed,'White fire did not transform guest')
        assert(returned,'Native room completion did not restore guest')
        assert(not Isaac.GetPlayer(native.rooms_heads()['1']):GetEffects():HasNullEffect(NullItemID.ID_LOST_CURSE),
            'White-fire fixture left the guest transformed after completion')
        done=true;report('PASS native white-fire transformation and room-clear restoration')
    end
    return s
end
local gate=native.net_gate
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
    local level=Game():GetLevel();origin=level:GetCurrentRoomIndex()
    for i=0,level:GetRooms().Size-1 do local d=level:GetRooms():Get(i)
        if d.Data.Type==RoomType.ROOM_DEFAULT and d.SafeGridIndex~=origin and not d.Clear and d.VisitedCount==0 then
            other=d.SafeGridIndex;break
        end
    end
    assert(other,'White-fire fixture requires a fresh uncleared combat room')
    return gate(capture,function(t,n,b)
        before(t,n,b)
        if t==35 then assert(native.rooms_with_player(1,function()
            local p=Isaac.GetPlayer(1)
            assert(Isaac.Spawn(EntityType.ENTITY_FIREPLACE,4,0,p.Position,Vector.Zero,nil))
            report('HOST spawned native white fire')
        end)) end
        local p=Isaac.GetPlayer(1)
        if t==60 then p:SetMinDamageCooldown(10000) end
        if t>=102 and t<110 then assert(native.rooms_with_player(1,function()
            assert(Game():GetLevel():GetCurrentRoomIndex()==other,'White-fire room transfer did not finish')
            assert(not Game():GetRoom():IsClear(),'White-fire combat room was already cleared')
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e:IsActiveEnemy(false) then e:AddEntityFlags(EntityFlag.FLAG_FREEZE) end end
            Isaac.GetPlayer(0):SetMinDamageCooldown(10000)
        end)) end
        local lost=p:GetEffects():HasNullEffect(NullItemID.ID_LOST_CURSE)
        if t>=36 and lost then changed=true end
        if changed and not departed and t>100 then
            departed=true;assert(native.rooms_move(1,other,0,-1))
            report('HOST ghost entered combat room')
        end
        if t>=180 and t<250 then assert(native.rooms_with_player(1,function()
            -- Different fresh rooms can contain enemies that spawn children.
            -- Finish those native deaths too; never force the room clear flag.
            for _,e in ipairs(Isaac.GetRoomEntities()) do if e:IsActiveEnemy(false) and not e:IsDead() then
                e:ClearEntityFlags(EntityFlag.FLAG_FREEZE);e:Kill()
            end end
        end));if t==180 then report('HOST native enemy deaths') end end
        if t==260 then
            assert(native.rooms_with_player(1,function() assert(Game():GetRoom():IsClear(),'Combat fixture did not clear natively') end))
            -- Reused starting positions may coincide with the return doorway.
            -- Remove the fixture fire after completion to avoid a second touch.
            assert(native.rooms_with_player(0,function()
                for _,e in ipairs(Isaac.GetRoomEntities()) do if e.Type==EntityType.ENTITY_FIREPLACE and e.Variant==4 then e:Remove() end end
            end))
            assert(native.rooms_move(1,origin,0,0))
        end
        if changed and t>220 and not lost then returned=true end
        if t%30==0 then report('HOST type='..p:GetPlayerType()..' lost='..tostring(lost)..' ghost='..tostring(p:IsCoopGhost())..' tick='..t) end
        if t==90 then report('VISUAL_READY') end
    end,collect,function(bytes,t,ack)
        if restore(bytes,t,ack)==false then return false end
        local p=Isaac.GetPlayer(1)
        local lost=p:GetEffects():HasNullEffect(NullItemID.ID_LOST_CURSE)
        if lost then changed=true end
        if changed and t>220 and not lost then returned=true end
        if t%30==0 then report('CLIENT type='..p:GetPlayerType()..' lost='..tostring(lost)..' ghost='..tostring(p:IsCoopGhost())..' tick='..t) end
    end,present,beginFloor)
end
