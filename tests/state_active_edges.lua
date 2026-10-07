-- Real action queries: one held controller button must use a charged D6 once.
local native=assert(_IsaacLan)
local f=assert(io.open("./lan-test-role.txt","r"));local host=f:read("*l")=="host";f:close()
f=assert(io.open("./lan-test-menu-port.txt","r"));local port=f:read("*l");f:close()
local owner={Name="Isolated active input regression"}
local function report(text) Isaac.DebugString("LAN_NETWORK "..text) end
local originalFrame=_IsaacLanFrame
local renders,linked,chosen,finished=0,false,false,false
local uses,initialHearts,checked=0,nil,false
Isaac.AddCallback(owner,ModCallbacks.MC_USE_ITEM,function(_,item)
    if host and item==CollectibleType.COLLECTIBLE_D6 then uses=uses+1;report("D6 uses="..uses) end
end)
function _IsaacLanFrame()
    renders=renders+1
    if not linked and renders>=(host and 300 or 360) then
        linked=true;_IsaacLanCommand(host and "host" or "join",host and port or "127.0.0.1:"..port);report("MENU_READY")
    end
    local s=originalFrame()
    if s.phase==2 and not chosen then _IsaacLanCommand("choose","0:1");chosen=true end
    if host and s.phase==2 and s.players==2 and s.ready0==1 and s.ready1==1 then _IsaacLanCommand("start","YV039KQF:0:0:0:0:0") end
    local press=s.verified>=120 and s.verified<126 or s.verified>=240 and s.verified<246 or s.verified>=330 and s.verified<336
    native.test_gamepad(0,host and press and 255 or 0)
    if s.phase==4 or s.phase==9 then report("FAILED "..s.error) end
    if s.verified>=430 and not finished then
        if host then assert(checked,"Active effect was not checked") end
        finished=true;report("PASS one physical active press")
    end
    return s
end
local gate=native.net_gate
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
    return gate(capture,function(t,n,b)
        before(t,n,b)
        if t==30 then
            report("ENUM item="..ButtonAction.ACTION_ITEM.." left="..ButtonAction.ACTION_LEFT.." map="..ButtonAction.ACTION_MAP)
            local p=Isaac.GetPlayer(0)
            p:AddMaxHearts(18);p:AddHearts(24)
            p:AddCollectible(CollectibleType.COLLECTIBLE_SHARP_PLUG)
            p:AddCollectible(CollectibleType.COLLECTIBLE_D6,6)
            p:SetActiveCharge(6)
            initialHearts=p:GetHearts()+p:GetSoulHearts()
            report("PLUG prepared health="..initialHearts.." charge="..p:GetActiveCharge().." item="..p:GetActiveItem().." max="..Isaac.GetItemConfig():GetCollectible(p:GetActiveItem()).MaxCharges.." battery="..p:GetBatteryCharge())
        end
        if t>=110 and t<=150 then
            local offset=1+ButtonAction.ACTION_ITEM*2;local value=string.unpack(">I2",b,offset)
            local edge=string.unpack(">I2",b,33)
            if value~=0 or (edge&(1<<ButtonAction.ACTION_ITEM))~=0 then report("ITEM tick="..t.." value="..value.." edge="..edge) end
        end
        if t==190 then
            local p=Isaac.GetPlayer(0);local health=p:GetHearts()+p:GetSoulHearts()
            report("PLUG result health="..health.." charge="..p:GetActiveCharge().." uses="..uses)
            assert(uses==1,"One physical active press did not use D6 exactly once")
            assert(health==initialHearts,"Charged active use also triggered Sharp Plug")
            assert(p:GetActiveCharge()==0,"D6 did not consume its native charge")
            checked=true
        end
        if t==300 then
            local p=Isaac.GetPlayer(0)
            assert(uses==1,"Empty active unexpectedly fired")
            assert(p:GetActiveCharge()==6,"Fresh press on empty active did not invoke native Sharp Plug")
            assert(p:GetHearts()+p:GetSoulHearts()==initialHearts-6,"Sharp Plug did not pay its native charge cost")
        end
        if t==400 then
            local p=Isaac.GetPlayer(0)
            assert(uses==2 and p:GetActiveCharge()==0,"Recharged D6 did not fire once")
            assert(p:GetHearts()+p:GetSoulHearts()==initialHearts-6,"Recharged D6 press also invoked Sharp Plug")
        end
    end,collect,restore,present,beginFloor)
end
