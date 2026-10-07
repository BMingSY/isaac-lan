-- Native charged weapon, raw shooting input, and replicated native charge UI.
local native=assert(_IsaacLan)
local f=assert(io.open("./lan-test-role.txt","r"));local host=f:read("*l")=="host";f:close()
f=assert(io.open("./lan-test-menu-port.txt","r"));local port=f:read("*l");f:close()
local function report(text) Isaac.DebugString("LAN_NETWORK "..text) end
local frame=_IsaacLanFrame
local renders,linked,chosen,finished,charged=0,false,false,false,0
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 360) then
        linked=true;_IsaacLanCommand(host and "host" or "join",host and port or "127.0.0.1:"..port);report("MENU_READY")
    end
    local s=frame()
    if s.phase==2 and not chosen then _IsaacLanCommand("choose","0:1");chosen=true end
    if host and s.phase==2 and s.players==2 and s.ready0==1 and s.ready1==1 then _IsaacLanCommand("start","LBCD0G4M:0:0:0:0:0") end
    native.test_gamepad(not host and s.verified>=100 and s.verified<220 and 8192 or 0)
    if s.phase==4 or s.phase==9 then report("FAILED "..s.error) end
    if s.verified>=320 and not finished then
        if not host then assert(charged>10,"Native charge state was not exercised") end
        finished=true;report("PASS guest native charged weapon")
    end
    return s
end
local function weapons(bytes)
    local result,cursor={},11
    for i=1,5 do
        local exists;exists,cursor=string.unpack(">B",bytes,cursor)
        if exists==1 then
            local kind,delay,maximum,charge
            kind,delay,maximum,charge,cursor=string.unpack(">I4fff",bytes,cursor)
            result[i]={kind,delay,maximum,charge}
        end
    end
    return result
end
local gate=native.net_gate
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
    return gate(capture,function(t,n,b)
        before(t,n,b)
        if t==30 then
            Options.ChargeBars=true
            local p=Isaac.GetPlayer(1);p:AddCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)
            assert(p.ControllerIndex==2 and p:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE),
                'Brimstone fixture did not equip the guest actor: controller='..p.ControllerIndex..
                ' ghost='..tostring(p:IsCoopGhost())..' owned='..p:GetCollectibleNum(CollectibleType.COLLECTIBLE_BRIMSTONE,true))
            p:SetMinDamageCooldown(10000)
            p.Position=Vector(400,240);Isaac.GetPlayer(0).Position=Vector(180,240)
        end
        if t==100 then report("CHARGE_INPUT_BEGIN") end
    end,function(slot,t)
        local bytes=collect(slot,t)
        if t==60 then
            local value=_IsaacLanState.decode(bytes)
            for _,actor in ipairs(value[9]) do if actor[2]==2 then
                local equipped=false
                for _,item in ipairs(actor[4][2]) do if item[1]==CollectibleType.COLLECTIBLE_BRIMSTONE then equipped=item[2]>0 end end
                assert(equipped,'Authoritative guest inventory lost Brimstone')
            end end
        end
        return bytes
    end,function(bytes,t,ack)
        if restore(bytes,t,ack)==false then return false end
        Options.ChargeBars=true
        local v=_IsaacLanState.decode(bytes)
        for _,actor in ipairs(v[9]) do if actor[2]==2 and actor[6] then
            local expected=weapons(actor[6]);local actual=weapons(assert(native.actor_pose(Isaac.GetPlayer(actor[1]):GetSprite())))
            if t>=100 and t<220 then
                local sprites=native.actor_sprites(actor[1],Isaac.GetPlayer(actor[1]):GetSprite())
                assert(sprites[4]:GetFilename()=='gfx/chargebar.anm2','Native charge-bar sprite is missing')
                assert(sprites[4]:GetAnimation()==actor[5][4][2],'Native charge-bar animation did not replicate')
                for slot,weapon in pairs(expected) do
                    assert(actual[slot],"Replica charged weapon is missing")
                    assert(actual[slot][1]==weapon[1],"Replica weapon type differs")
                    assert(math.abs(actual[slot][4]-weapon[4])<0.0001,"Native weapon charge was not replicated")
                    if weapon[4]>0 then charged=charged+1 end
                end
            end
            if t%30==0 then
                local w=expected[2] or {0,0,0,0};report("CHARGE tick="..t.." type="..w[1].." delay="..w[2].." max="..w[3].." charge="..w[4])
            end
        end end
        return true
    end,present,beginFloor)
end
