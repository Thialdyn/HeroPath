local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
local function harness()
  local st={played=0,now=0,x=0,y=0,map=0,speed=0,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,inside=false,itype='none',iname='Instance',iid=0,class='WARRIOR',faction='Alliance'}
  local listeners,onload,ticker={},nil,nil; local q={}; local ns={}; local worldCalls=0
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
  ns.WorldPos=function() worldCalls=worldCalls+1; return st.x,st.y,st.map end
  ns.Listen=function(e,f) listeners[e]=f end
  ns.OnLoad=function(f) onload=f end
  _G.GetTime=function() return st.now end
  _G.IsInInstance=function() return st.inside,st.itype end
  _G.GetInstanceInfo=function() return st.iname,st.itype,nil,nil,nil,nil,nil,st.iid end
  _G.C_Timer={NewTicker=function(_,f) ticker=f;return{} end,After=function(_,f) q[#q+1]=f end}
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
  local db={};onload(db)
  local function flush()
    local guard=0
    while #q>0 do guard=guard+1;assert(guard<1000,'queue runaway');local a=q;q={};for _,f in ipairs(a)do f() end end
  end
  local function tick(t,x,y,map)
    st.played=t;st.now=t;if x~=nil then st.x=x end;if y~=nil then st.y=y end;if map~=nil then st.map=map end;ticker();flush()
  end
  return st,listeners,db,tick,flush,function()return worldCalls end
end
local function stateCount(db,code)local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==2 and e[2]==code then n=n+1 end end;return n end
local function ok(v,m)assert(v,m)end

-- Collector invariant: world position is observed on every 4 Hz collector tick, even while idle.
do
  local s,l,db,tick,flush,calls=harness()
  for i=0,8 do tick(i*.25,0,0,0) end
  local c=calls();ok(c==9,'fixed world-position sampling count mismatch: '..c)
  ok(db.heroPath.adaptiveSampling==1 and db.heroPath.sampleFast==.25 and db.heroPath.sampleMoving==.25 and db.heroPath.sampleIdle==.25,'4 Hz observation + adaptive-store metadata')
  ok(db.heroPath.playerClass=='warrior' and db.heroPath.playerFaction=='alliance','player identity metadata')
end


-- A sub-gap scheduler delay while idle must not be mistaken for unknown position.
do
  local s,l,db,tick=harness();tick(0,0,0,0);tick(1.0,0,0,0)
  ok(stateCount(db,5)==0 and stateCount(db,6)==0,'adaptive idle jitter created a false gap')
end

-- Movement APIs do not gate coordinate observation: idle/walk/mount all read WorldPos every tick.
do
  local s,l,db,tick,flush,calls=harness();tick(0,0,0,0);local base=calls()
  s.speed=7;tick(.25,2,0,0);local wake=calls();ok(wake==base+1,'walking position observation missing')
  tick(.50,4,0,0);ok(calls()==wake+1,'walking tick skipped WorldPos')
  tick(.75,6,0,0);ok(calls()==wake+2,'walking 4 Hz observation missing')
  s.mounted=true;s.speed=14;tick(1.00,10,0,0);tick(1.25,14,0,0);ok(calls()==wake+4,'mounted observation cadence changed')
end

-- Hearth spell hint + impossible jump => explicit Hearth classification (state 9).
do
  local s,l,db,tick=harness();s.speed=7;tick(0,-11017,1517,0)
  l.UNIT_SPELLCAST_SUCCEEDED('player','cast-guid',8690)
  tick(.5,-9463,16,0);tick(.75,-9463,16,0)
  ok(stateCount(db,9)==1,'hearth not classified')
end

-- Slow loading after a successful Hearth must keep the semantic Hearth label.
do
  local s,l,db,tick,flush=harness();s.speed=7;tick(0,-11017,1517,0)
  l.UNIT_SPELLCAST_SUCCEEDED('player','cast-guid',8690)
  s.played=.10;s.now=.10;l.PLAYER_LEAVING_WORLD()
  s.x=-9463;s.y=16;s.played=30;s.now=30;l.PLAYER_ENTERING_WORLD(false,false);flush()
  tick(30.25,-9463,16,0);tick(30.50,-9463,16,0)
  ok(stateCount(db,9)==1,'slow Hearth/loading lost classification')
end

-- Transport truth rule: endpoint proximity never invents boat/zeppelin semantics.
-- A world handoff remains a measured world transition; transport labeling can be added offline later.
do
  local s,l,db,tick=harness();s.speed=20;tick(0,-3850,-731,0);tick(.25,6325,554,1);tick(.5,6325,554,1)
  ok(stateCount(db,12)==0 and stateCount(db,7)==1,'boat was inferred from terminal endpoints')
end

do
  local s,l,db,tick=harness();s.speed=20;tick(0,1382,-4371,1);tick(.25,1850,236,0);tick(.5,1850,236,0)
  ok(stateCount(db,13)==0 and stateCount(db,7)==1,'zeppelin was inferred from terminal endpoints')
end

-- Deeprun Tram is explicit from instance identity, with start/end states.
do
  local s,l,db,tick,flush=harness();s.speed=7;tick(0,-9154,364,0)
  s.inside=true;s.itype='party';s.iname='Deeprun Tram';s.iid=369;s.played=.25;s.now=.25;l.PLAYER_ENTERING_WORLD(false,false);flush();tick(.5,-9154,364,0)
  ok(stateCount(db,10)>=1,'tram start not classified')
  s.inside=false;s.itype='none';s.iname='Eastern Kingdoms';s.iid=0;s.x=-5021;s.y=-834;s.map=0;s.played=30;s.now=30;l.PLAYER_ENTERING_WORLD(false,false);flush();tick(30.25,-5021,-834,0)
  ok(stateCount(db,11)>=1,'tram end not classified')
end

-- Tram identity must win even when a fork reports IsInInstance=false/type none.
do
  local s,l,db,tick,flush=harness();s.speed=7;tick(0,-9154,364,0)
  s.inside=false;s.itype='none';s.iname='Deeprun Tram';s.iid=369;s.played=.25;s.now=.25;l.PLAYER_ENTERING_WORLD(false,false);flush();tick(.5,-9154,364,0)
  ok(stateCount(db,10)>=1,'tram ID fallback not classified')
end

print('FIXED_WORLD_POSITION_4HZ=PASS')
print('FIXED_IDLE_JITTER=PASS')
print('MOVEMENT_API_NOT_A_GATE=PASS')
print('SMART_HEARTH=PASS')
print('SMART_HEARTH_SLOW_LOAD=PASS')
print('RAW_POSITION_BOAT_NO_INFERENCE=PASS')
print('RAW_POSITION_ZEPPELIN_NO_INFERENCE=PASS')
print('SMART_TRAM=PASS')
print('SMART_TRAM_ID_FALLBACK=PASS')
print('FIXED_SAMPLING_TRANSPORT_COMPAT=PASS')
