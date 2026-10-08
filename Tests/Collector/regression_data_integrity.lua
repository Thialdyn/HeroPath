local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
local PF=9
local function harness(initial,saved)
  local st={played=0,now=0,x=0,y=0,map=0,speed=0,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,inside=false,itype='none',iname='Instance',iid=0,class='WARRIOR',faction='Alliance'}
  for k,v in pairs(initial or {}) do st[k]=v end
  local listeners,onload,ticker={},nil,nil; local q={}; local ns={}
  ns.Num=tonumber
  ns.Call=function(n,...)
    if n=='UnitIsGhost' then return st.ghost end
    if n=='UnitIsDeadOrGhost' then return st.dead or st.ghost end
    if n=='UnitOnTaxi' then return st.taxi end
    if n=='IsMounted' then return st.mounted end
    if n=='IsSwimming' then return st.swimming end
    if n=='GetUnitSpeed' then return st.speed end
    if n=='UnitClass' then return 'Warrior',st.class end
    if n=='UnitFactionGroup' then return st.faction end
  end
  ns.PlayedNow=function() return st.played end
  ns.WorldPos=function() if st.noPos then return nil end; return st.x,st.y,st.map end
  ns.Listen=function(e,f) listeners[e]=f end
  ns.OnLoad=function(f) onload=f end
  _G.GetTime=function() return st.now end
  _G.IsInInstance=function() return st.inside,st.itype end
  _G.GetInstanceInfo=function() return st.iname,st.itype,nil,nil,nil,nil,nil,st.iid end
  _G.C_Timer={NewTicker=function(_,f) ticker=f;return{}end,After=function(_,f)q[#q+1]=f end}
  -- TEST_API_CALL_BRIDGE: production reaches these through Bootstrap.SafeRead; the harness mirrors that boundary.
  do
    local priorCall=ns.Call
    ns.Call=function(n,...)
      if n=='IsInInstance' and type(_G.IsInInstance)=='function' then return _G.IsInInstance(...) end
      if n=='GetInstanceInfo' and type(_G.GetInstanceInfo)=='function' then return _G.GetInstanceInfo(...) end
      if n=='GetTime' and type(_G.GetTime)=='function' then return _G.GetTime(...) end
      return priorCall(n,...)
    end
  end
  assert(loadfile(CONTRACT))('HeroPath',ns);assert(loadfile(DATAMODEL))('HeroPath',ns);assert(loadfile(METADATA))('HeroPath',ns);assert(loadfile(MODULE))('HeroPath',ns)
  local db=saved or {};onload(db)
  local function flush() local guard=0; while #q>0 do guard=guard+1;assert(guard<1000,'queue runaway');local a=q;q={};for _,f in ipairs(a)do f() end end end
  local function tick(t,x,y,map)
    st.played=t;st.now=t;if x~=nil then st.x=x end;if y~=nil then st.y=y end;if map~=nil then st.map=map end;ticker();flush()
  end
  return st,listeners,db,tick,flush
end
local VA='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_'
local function vmap(c)local p=string.find(VA,c,1,true);return p and p-1 end
local function decode(ch)
 local out={}
 if type(ch)~='table' or ch[1]~='HP1' then return out end
 local data=ch[2] or '';local pos=1;local pt,pm,px,py,po,pmode=0,0,0,0,0,0
 local function rv()
  local u,m=0,1
  while true do
   local d=vmap(data:sub(pos,pos));assert(d,'bad/truncated varint');pos=pos+1
   local more=d>=32;if more then d=d-32 end;u=u+d*m
   if not more then break end;m=m*32;assert(m<=2^53,'varint huge')
  end
  return u%2==0 and u/2 or -(u+1)/2
 end
 for idx=1,(ch[3] or 0) do
  local t,m,x,y,mode,flags,o
  if idx==1 then
   t=rv();m=rv();x=rv();y=rv();mode=rv();flags=rv();o=rv()
  else
   flags=rv();t=pt+rv();x=px+rv();y=py+rv();o=po+rv();m=pm;mode=pmode
   if flags%2>=1 then m=pm+rv() end
   if math.floor(flags/2)%2>=1 then mode=rv() end
  end
  local br=math.floor(flags/4)%2;local prot=math.floor(flags/8)%2;local reason=br==1 and math.floor(flags/16) or 0
  out[#out+1]={t/1000,m,x/10,y/10,mode,br,prot,o,reason}
  pt,pm,px,py,po,pmode=t,m,x,y,o,mode
 end
 assert(pos==#data+1,'trailing bytes in encoded chunk')
 return out
end
local function points(db)local o={};for _,ch in ipairs(db.heroPath.chunks or{})do for _,p in ipairs(decode(ch))do o[#o+1]=p end end;for _,p in ipairs(db.heroPath.tail or{})do o[#o+1]=p end;return o end
local function stateCount(db,code)local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==2 and e[2]==code then n=n+1 end end;return n end
local function eventCount(db,kind)local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==kind then n=n+1 end end;return n end
local function ok(v,m)assert(v,m)end

-- 1) /reload while on taxi: a large same-map displacement is still valid taxi continuity, never TELEPORT.
do
  local s,l,db,tick,flush=harness();s.taxi=true;s.speed=35;tick(0,0,0,0);tick(.25,10,0,0)
  s.played=5;s.now=5;s.x=250;s.y=40;l.PLAYER_ENTERING_WORLD(false,true);flush()
  local ps=points(db); local last=ps[#ps]
  ok(last and last[5]==3,'taxi mode lost after reload')
  ok(last[6]==0,'taxi reload created a path break')
  ok(stateCount(db,8)==0,'taxi reload created false TELEPORT')
end

-- 2) First activation while already inside an instance must create an instance event even without exterior anchor.
do
  local s,l,db,tick=harness({inside=true,itype='party',iname='Scholomance',iid=289,noPos=true})
  tick(1)
  ok(eventCount(db,1)==1,'fresh in-instance startup lost instance event')
  local e=db.heroPath.events[1];ok(e[12]==0,'unknown instance anchor was marked trustworthy')
  s.inside=false;s.itype='none';s.noPos=false;s.x=100;s.y=200;s.map=0;tick(20,100,200,0);tick(20.25,100,200,0)
  local ps=points(db); local p=ps[#ps];ok(p and p[6]==1 and p[9]==6,'unknown-anchor instance exit did not create explicit break')
end

-- 3) Death inside that anchorless instance must still be recorded, with unknown position accuracy.
do
  local s,l,db,tick,flush=harness({inside=true,itype='party',iname='Scholomance',iid=289,noPos=true})
  tick(1);s.played=2;s.now=2;l.PLAYER_DEAD();flush()
  ok(eventCount(db,0)==1,'anchorless in-instance death was dropped')
  local death
  for _,e in ipairs(db.heroPath.events)do if e[1]==0 then death=e end end
  ok(death and death[8]==4 and death[6]==1,'anchorless death accuracy/inside flag incorrect')
end

-- 4) Terminal-to-terminal teleports must not become boat/zeppelin by proximity.
do
  local s,l,db,tick=harness();s.speed=20;tick(0,-3905.2,-585.8,0);tick(.25,6594.4,759.8,1);tick(.5,6594.4,759.8,1)
  ok(stateCount(db,12)==0 and stateCount(db,13)==0,'terminal proximity invented transport type')
  ok(stateCount(db,7)==1,'measured world transition missing')
end

-- 5) Fast continuous same-map platform motion is retained and classified unknown/special, not teleport.
do
  local s,l,db,tick=harness();s.speed=0;tick(0,0,0,0)
  for i=1,20 do tick(i*.25,i*8,0,0) end -- 32 yd/s observed world motion, not mounted/taxi
  local ps=points(db); local seenSpecial=false
  for _,p in ipairs(ps)do if p[5]==5 then seenSpecial=true end end
  ok(seenSpecial,'fast unclassified platform never entered special mode')
  ok(stateCount(db,8)==0,'continuous platform motion created false teleport')
end

-- 6) SavedVariables metadata advertises the raw-position-only collection policy.
do
  local s,l,db,tick=harness();tick(0,0,0,0)
  ok(db.heroPath.schema==1,'schema is not 1')
  ok(db.heroPath.transportInference=='raw-position-only','transport policy metadata missing')
end

print('DATA_INTEGRITY_TAXI_RELOAD=PASS')
print('DATA_INTEGRITY_INSTANCE_WITHOUT_ANCHOR=PASS')
print('DATA_INTEGRITY_DEATH_WITHOUT_ANCHOR=PASS')
print('DATA_INTEGRITY_NO_ENDPOINT_TRANSPORT_INFERENCE=PASS')
print('DATA_INTEGRITY_SPECIAL_PLATFORM_TRACKING=PASS')
print('DATA_INTEGRITY_METADATA=PASS')
print('REGRESSION_DATA_INTEGRITY=PASS')
