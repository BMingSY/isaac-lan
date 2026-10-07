local native=assert(_IsaacLan)
local owner={Name="Isolated local HUD and room animation regression"}
local f=assert(io.open("./lan-test-role.txt","r"));local host=f:read("*l")=="host";f:close()
f=assert(io.open("./lan-test-menu-port.txt","r"));local port=f:read("*l");f:close()
local function report(s) Isaac.DebugString("LAN_NETWORK "..s) end
local frames,joined,chosen,done,tick=0,false,false,false,-1
local sawUp,sawDown=false,false
local lastActor=nil
local original=_IsaacLanFrame
function _IsaacLanFrame()
 frames=frames+1
 if not joined and frames>=(host and 300 or 600) then joined=true;_IsaacLanCommand(host and "host" or "join",host and port or "127.0.0.1:"..port);report("MENU_READY") end
 local s=original();tick=s.verified
 if s.phase==2 and not chosen then chosen=true;_IsaacLanCommand("choose","0:1") end
 if host and s.phase==2 and s.players==2 and s.ready0==1 and s.ready1==1 then _IsaacLanCommand("start","N024KHNP:0:0:0:0:0") end
 if s.phase==4 or s.phase==9 then report("FAILED "..s.error) end
 if s.verified>=1100 and not done then done=true;assert(Game():GetLevel():GetStage()==2);assert(sawUp and sawDown,"Teleport animation sequence missing");report("PASS local HUD after floor and cards") end
 return s
end
local function player(controller)
 for i=0,Game():GetNumPlayers()-1 do local p=Isaac.GetPlayer(i);if p.ControllerIndex==controller then return p end end
end
local function clear()
 for _,e in ipairs(Isaac.GetRoomEntities()) do if e:IsActiveEnemy(false) then e:Remove() end end
 Game():GetRoom():SetClear(true)
end
local function diagnostic(p,t)
 local index;for i=0,Game():GetNumPlayers()-1 do if GetPtrHash(Isaac.GetPlayer(i))==GetPtrHash(p) then index=i;break end end
 local a=native.actor_sprites(index,p:GetSprite());local parts={}
 for i,s in ipairs(a) do parts[#parts+1]=i..":"..s:GetFilename()..":"..s:GetAnimation()..":"..s:GetFrame() end
 report("POSE tick="..t.." ctrl="..p.ControllerIndex.." visible="..tostring(p.Visible).." main="..p:GetSprite():GetAnimation()..":"..p:GetSprite():GetFrame().." extra="..table.concat(parts,"|"))
end
local gate=native.net_gate
native.net_gate=function(capture,before,collect,restore,present,beginFloor)
 return gate(function()
  local v={};for i=1,17 do v[i]=string.pack(">I2",0) end;return table.concat(v)
 end,function(t,n,b)
  before(t,n,b)
  for c=1,2 do local p=player(c);if p then p:SetMinDamageCooldown(60);p:AddEntityFlags(EntityFlag.FLAG_NO_DAMAGE_BLINK) end end
  if t==20 then
   player(1):AddCollectible(CollectibleType.COLLECTIBLE_SAD_ONION)
   player(2):AddCollectible(CollectibleType.COLLECTIBLE_MAGIC_MUSHROOM)
   player(2):AddMaxHearts(2);player(2):AddHearts(2)
   player(1):SetCard(0,Card.CARD_WORLD);player(2):SetCard(0,Card.CARD_FOOL)
  end
  if t==100 or t==450 or t==900 then
   local origin=native.rooms_positions()["1"].index;local dest
   local list=Game():GetLevel():GetRooms()
   for i=0,list.Size-1 do local d=list:Get(i);if d.SafeGridIndex~=origin and d.Data.Type==RoomType.ROOM_DEFAULT and d.Data.Shape==RoomShape.ROOMSHAPE_1x1 then dest=d.SafeGridIndex;break end end
   assert(dest);assert(native.rooms_move(1,dest,0,0));report("GUEST room transfer "..t)
  end
  if t==160 then assert(native.rooms_with_player(1,function() clear();player(2):UseCard(Card.CARD_FOOL,UseFlag.USE_OWNED) end));report("CARD Fool") end
  if t==300 then assert(native.rooms_with_player(1,function() clear();player(2):UseCard(Card.CARD_STARS,UseFlag.USE_OWNED) end));report("CARD Stars") end
  if t==480 then
   local list=Game():GetLevel():GetRooms();for i=0,list.Size-1 do local d=list:Get(i);if d.Data.Type==RoomType.ROOM_TREASURE then assert(native.rooms_move(0,d.SafeGridIndex,0,0));break end end
   report("HOST background transfer")
  end
  if t==550 then assert(native.rooms_with_player(0,function() Game():StartStageTransition(false,0,player(1)) end));report("NEXT FLOOR") end
  if t==960 then assert(native.rooms_with_player(1,function() clear();player(2).Position=Game():GetRoom():GetCenterPos() end)) end
  if (t>=150 and t<=200 or t>=295 and t<=340 or t>=895 and t<=930) and t%5==0 then diagnostic(player(2),t) end
 end,function(slot,t)
  local bytes=collect(slot,t)
  local value=_IsaacLanState.decode(bytes)
  for _,a in ipairs(value[9]) do if a[2]==2 then
   local anim=a[3][10][2];if anim=="TeleportUp" then sawUp=true elseif anim=="TeleportDown" then sawDown=true end
  end end
  return bytes
 end,function(bytes,t,ack)
  if restore(bytes,t,ack)==false then return false end
  local value=_IsaacLanState.decode(bytes)
  for _,a in ipairs(value[9]) do if a[2]==2 then
   lastActor=a;local anim=a[3][10][2];if anim=="TeleportUp" then sawUp=true elseif anim=="TeleportDown" then sawDown=true end
  end end
  if (t>=150 and t<=200 or t>=295 and t<=340 or t>=895 and t<=930) and t%5==0 then diagnostic(player(2),t) end
 end,present,beginFloor)
end

Isaac.AddCallback(owner,ModCallbacks.MC_POST_RENDER,function()
 if host or not lastActor or not _IsaacLanStatus().prepared or not native.rooms_ready() or tick<800 then return end
 local p=player(2)
 assert(p and p:GetSprite():GetAnimation()==lastActor[3][10][2],"Replica callback overwrote actor animation")
 -- Validate the pose after every native/Mod update, at the actual draw boundary.
 local pose=native.actor_pose(p:GetSprite())
 assert(pose:sub(1,10)==lastActor[6]:sub(1,10),"Replica callback overwrote body visibility or damage blink timer")
 local expected={};for i=4,#lastActor[5] do expected[lastActor[5][i][1]]=true end
 local sprites=native.actor_sprites(0,p:GetSprite())
 for i=4,#sprites do assert(expected[sprites[i]:GetFilename()],"Replica retained an unrequested costume") end
end)

-- Reproduce a replica Mod making an animation decision after the packet was
-- applied (for example from provisional room contents). Only the test peer is
-- changed; no installed Mod source is edited.
Isaac.AddCallback(owner,ModCallbacks.MC_POST_UPDATE,function()
 if host or not lastActor or tick<800 or tick>950 or not native.rooms_ready() then return end
 local p=player(2)
 if p then
  p:AnimateSad()
  p:SetMinDamageCooldown(90)
  local costume=Isaac.GetCostumeIdByPath("the/specialist_isaac.anm2")
  if costume>=0 then p:AddNullCostume(costume) end
 end
end)
