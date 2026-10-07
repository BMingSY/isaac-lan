-- Isolated, externally driven XInput buttons and read-only observations.
-- No host/join commands, input-frame substitution, room transfers or cheats.
local native=assert(_IsaacLan)
local json=require("json")
local frame=_IsaacLanFrame
local held,remaining,sequence=0,0,0
local frames=0
local lastFloorReady,lastStage
local function write(path,value)
    local f=assert(io.open(path..".tmp","w"));f:write(json.encode(value));f:close()
    os.remove(path);assert(os.rename(path..".tmp",path))
end
function _IsaacLanFrame()
    frames=frames+1
    local f=io.open("./lan-human-input.json","r")
    if f then
        local value=json.decode(f:read("*a"));f:close();os.remove("./lan-human-input.json")
        held,remaining,sequence=value.buttons,value.frames,value.sequence
        native.test_gamepad(held)
        Isaac.DebugString("LAN_HUMAN_INPUT "..json.encode(value))
    elseif remaining>0 then
        remaining=remaining-1
        if remaining==0 then held=0;native.test_gamepad(0) end
    end
    local status=frame()
    if status.prepared then
        local ready=native.rooms_ready();local stage=Game():GetLevel():GetStage()
        if ready~=lastFloorReady or stage~=lastStage then
            local trace=assert(io.open("./lan-human-floors.jsonl","a"))
            trace:write(json.encode({time=Isaac.GetTime()/1000,ready=ready,stage=stage}).."\n");trace:close()
            lastFloorReady,lastStage=ready,stage
        end
    end
    if frames%12==0 then
        local out={frames=frames,input=held,inputRemaining=remaining,sequence=sequence,
            phase=status.phase,error=status.error,slot=status.slot,players=status.players,
            pause=status.pause,positions=status.positions,verified=status.verified}
        if status.prepared and native.rooms_ready() then
            local g=Game();local level=g:GetLevel();local room=g:GetRoom()
            out.stage=level:GetStage();out.playersState={};out.entities={};out.effects={};out.doors={}
            for i=0,g:GetNumPlayers()-1 do
                local p=Isaac.GetPlayer(i)
                out.playersState[#out.playersState+1]={index=i,type=p:GetPlayerType(),x=p.Position.X,y=p.Position.Y,
                    hearts=p:GetHearts(),soul=p:GetSoulHearts(),card=p:GetCard(0),item=p:GetActiveItem(0),
                    coins=p:GetNumCoins(),keys=p:GetNumKeys(),bombs=p:GetNumBombs(),visible=p.Visible,
                    controller=p.ControllerIndex,damageCooldown=p:GetDamageCooldown(),
                    ghost=p:IsCoopGhost(),collectibles=p:GetCollectibleCount(),
                    animation=p:GetSprite():GetAnimation(),animationFrame=p:GetSprite():GetFrame()}
            end
            native.rooms_with_player(status.slot,function()
            room=g:GetRoom();out.room=level:GetCurrentRoomIndex();out.roomType=room:GetType();out.clear=room:IsClear();out.gridWidth=room:GetGridWidth()
            out.center={x=room:GetCenterPos().X,y=room:GetCenterPos().Y}
            local scroll=room:GetRenderScrollOffset();out.scroll={x=scroll.X,y=scroll.Y}
            for i=0,g:GetNumPlayers()-1 do
                local p=Isaac.GetPlayer(i)
                if p.ControllerIndex==status.slot+1 then
                    local screen=Isaac.WorldToScreen(p.Position);out.localScreen={x=screen.X,y=screen.Y}
                end
            end
            for _,e in ipairs(Isaac.GetRoomEntities()) do
                if e:ToNPC() or e.Type==5 or e.Type==9 then
                    out.entities[#out.entities+1]={type=e.Type,variant=e.Variant,subtype=e.SubType,
                        x=e.Position.X,y=e.Position.Y,vx=e.Velocity.X,vy=e.Velocity.Y,hp=e.HitPoints,visible=e.Visible,
                        active=e:ToNPC() and e:IsVulnerableEnemy() or false}
                elseif e.Type==1000 then
                    local s=e:GetSprite();local shadow=native.entity_shadow(s)
                    out.effects[#out.effects+1]={variant=e.Variant,subtype=e.SubType,x=e.Position.X,y=e.Position.Y,
                        visible=e.Visible,path=s:GetFilename(),animation=s:GetAnimation(),frame=s:GetFrame(),
                        shadowSize=string.unpack(">f",shadow),depth=e.DepthOffset,
                        color={s.Color.R,s.Color.G,s.Color.B,s.Color.A}}
                end
            end
            for slot=0,7 do
                local door=room:GetDoor(slot)
                if door then
                    local target=level:GetRoomByIdx(door.TargetRoomIndex)
                    out.doors[#out.doors+1]={slot=slot,target=target.SafeGridIndex,targetIndex=door.TargetRoomIndex,
                    targetType=door.TargetRoomType,x=door.Position.X,y=door.Position.Y,open=door:IsOpen()} end
            end
            end)
        end
        write("./lan-human-state.json",out)
    end
    return status
end
