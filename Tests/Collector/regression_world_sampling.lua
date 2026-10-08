local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")

local function harness(initial,saved)
  local st={played=0,now=0,x=0,y=0,map=1,speed=0,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,
            vehicle=false,possessed=false,inside=false,itype='none',iname='Instance',iid=0,class='WARRIOR',faction='Alliance',
            guid='Player-1-AAA',name='Tester',realm='Realm',noPos=false,worldThrows=false,playedThrows=false,instanceThrows=false,
            taxiUnknown=false,lifeUnknown=false,callThrows=false,getTimeThrows=false,numThrows=false}
  for k,v in pairs(initial or {}) do st[k]=v end
  local listeners,onload,ticker={},nil,nil; local q={}; local worldCalls=0; local ns={}
  ns.Num=function(v) if st.numThrows then error('num unavailable') end; return tonumber(v) end
  ns.Call=function(n,...)
    if st.callThrows then error('call unavailable') end
    if n=='UnitIsGhost' then if st.lifeUnknown then return nil end; return st.ghost end
    if n=='UnitIsDeadOrGhost' then if st.lifeUnknown then return nil end; return st.dead or st.ghost end
    if n=='UnitOnTaxi' then if st.taxiUnknown then return nil end; return st.taxi end
    if n=='IsMounted' then return st.mounted end
    if n=='IsSwimming' then return st.swimming end
    if n=='GetUnitSpeed' then return st.speed end
    if n=='UnitInVehicle' then return st.vehicle end
    if n=='UnitHasVehicleUI' then return st.vehicle end
    if n=='UnitIsPossessed' then return st.possessed end
    if n=='UnitClass' then return 'Warrior',st.class end
    if n=='UnitFactionGroup' then return st.faction end
    if n=='UnitGUID' then return st.guid end
    if n=='UnitFullName' then return st.name,st.realm end
    if n=='UnitName' then return st.name end
    if n=='GetNormalizedRealmName' or n=='GetRealmName' then return st.realm end
  end
  ns.PlayedNow=function() if st.playedThrows then error('played unavailable') end; return st.played end
  ns.WorldPos=function() worldCalls=worldCalls+1;if st.worldThrows then error('world unavailable') end;if st.noPos then return nil end;return st.x,st.y,st.map end
  ns.Listen=function(e,f) listeners[e]=f end
  ns.OnLoad=function(f) onload=f end
  _G.GetTime=function() if st.getTimeThrows then error('clock unavailable') end; return st.now end
  _G.IsInInstance=function() if st.instanceThrows then error('instance unavailable') end; return st.inside,st.itype end
  _G.GetInstanceInfo=function() return st.iname,st.itype,nil,nil,nil,nil,nil,st.iid end
  _G.C_Timer={NewTicker=function(_,f)ticker=f;return{}end,After=function(delay,f)q[#q+1]={delay=delay,f=f} end}
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
  local function flush(maxRuns)
    maxRuns=maxRuns or 1000
    local runs=0
    while #q>0 do
      runs=runs+1;assert(runs<=maxRuns,'queue runaway')
      local item=table.remove(q,1);item.f()
    end
  end
  local function tick(t,x,y,map,flushTimers,nowValue)
    st.played=t;st.now=(nowValue~=nil) and nowValue or t
    if x~=nil then st.x=x end;if y~=nil then st.y=y end;if map~=nil then st.map=map end
    ticker()
    if flushTimers~=false then flush() end
  end
  return st,listeners,db,tick,flush,function()return worldCalls end
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
local function points(db)
 local o={};for _,ch in ipairs(db.heroPath.chunks or{})do for _,p in ipairs(decode(ch))do o[#o+1]=p end end
 for _,p in ipairs(db.heroPath.tail or{})do o[#o+1]=p end;return o
end
local function stateCount(db,code)
 local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==2 and (not code or e[2]==code) then n=n+1 end end;return n
end
local function eventCount(db,kind)
 local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==kind then n=n+1 end end;return n
end
local function ok(v,m) assert(v,m) end
local function eq(a,b,m) assert(a==b,(m or 'eq')..' got='..tostring(a)..' expected='..tostring(b)) end
local function lastPoint(db)local p=points(db);return p[#p] end

-- 1. Fixed 4 Hz observation: GetUnitSpeed=0 must never suppress world-position reads.
do
 local s,l,db,tick,flush,wc=harness();s.speed=0
 tick(0,0,0,1);local before=wc()
 for i=1,8 do tick(i*.25,i*2,0,1) end
 eq(wc()-before,8,'world position was not read on every ticker')
 ok(#points(db)>=4,'adaptive store over-sparsified forced/platform movement')
end

-- 2. One unavailable WorldPos frame is ignored; a sustained outage becomes one explicit gap.
do
 local s,l,db,tick=harness();tick(0,0,0,1)
 s.noPos=true;tick(.25);s.noPos=false;tick(.50,1,0,1)
 eq(stateCount(db,5),0,'single missing frame created GAP_START')
 eq(stateCount(db,6),0,'single missing frame created GAP_END')
 s.noPos=true;tick(.75);tick(1.0)
 ok(stateCount(db,5)==1,'sustained outage did not create one GAP_START')
 s.noPos=false;tick(1.25,2,0,1)
 ok(stateCount(db,6)==1,'gap recovery did not create GAP_END')
 local p=lastPoint(db);ok(p and p[6]==1 and p[9]==5,'gap recovery anchor not explicitly broken')
end

-- 3. A single absurd coordinate/map spike is discarded; a confirmed jump is kept as a break.
do
 local s,l,db,tick=harness();tick(0,0,0,1);tick(.25,2,0,1)
 tick(.50,5000,5000,2) -- candidate only
 tick(.75,4,0,1)       -- returns to old track
 eq(stateCount(db,7),0,'one-frame map spike created WORLD_TRANSITION')
 eq(stateCount(db,8),0,'one-frame map spike created TELEPORT')
 for _,p in ipairs(points(db))do ok(p[2]~=2,'spike point leaked into path') end
 tick(1.00,100,0,1);tick(1.25,101,0,1) -- confirmed same-map jump
 ok(stateCount(db,8)==1,'confirmed jump did not create TELEPORT')
 local p=lastPoint(db);ok(p[6]==1 and p[9]==3,'confirmed jump missing teleport break')
end

-- 4. Taxi false for one frame must not end a flight or turn a large displacement into a teleport.
do
 local s,l,db,tick=harness({taxi=true});tick(0,0,0,1);tick(.25,10,0,1)
 s.taxi=false;tick(.50,20,0,1);s.taxi=true;tick(.75,30,0,1)
 eq(stateCount(db,4),0,'one-frame taxi false created TAXI_END')
 eq(stateCount(db,8),0,'taxi flicker created TELEPORT')
end

-- 5. IsInInstance false for one frame cannot split an instance; a real exit always cuts the exterior line.
do
 local s,l,db,tick=harness();tick(0,0,0,1)
 s.inside=true;s.itype='party';s.iname='Test Dungeon';s.iid=123;tick(.25)
 ok(eventCount(db,1)==0,'first candidate instance frame committed too early')
 tick(.50);ok(eventCount(db,1)==1,'confirmed instance entry missing')
 s.inside=false;s.itype='none';tick(.75);s.inside=true;s.itype='party';tick(1.0)
 eq(eventCount(db,1),1,'one-frame instance false split event')
 local e=db.heroPath.events[#db.heroPath.events];ok(e[1]==1 and e[3]==0,'instance closed on flicker')
 s.inside=false;s.itype='none';tick(1.25);tick(1.50,0,0,1)
 local p=lastPoint(db);ok(p and p[6]==1 and p[9]==6,'real instance exit did not force BREAK_INSTANCE_EXIT')
end

-- 6. Starting/reloading while already inside never trusts an old unrelated outdoor point as entrance anchor.
do
 local saved={heroPath={version=8,chunks={},tail={{10,1,999,999,0,0,1,1,0}},events={},lastPlayed=10,sequence=1,ownerKey='guid:Player-1-AAA'}}
 local s,l,db,tick=harness({played=10,inside=true,itype='party',iname='Deep Dungeon',iid=777,noPos=true},saved)
 tick(10.25)
 local e
 for _,x in ipairs(db.heroPath.events)do if x[1]==1 then e=x end end
 ok(e and e[12]==0,'stale historical point became a fake instance entrance anchor')
end

-- 7. /played regression is rejected; recovery records a gap instead of appending backward timestamps.
do
 local s,l,db,tick=harness();tick(100,0,0,1);tick(101,1,0,1)
 s.played=10;s.now=102;tick(10,2,0,1)
 eq(db.heroPath.lastPlayed,101,'regressed /played contaminated lastPlayed')
 s.played=102;s.now=103;tick(102,3,0,1)
 eq(db.heroPath.lastPlayed,102,'/played did not recover')
 ok(stateCount(db,5)>=1 and stateCount(db,6)>=1,'/played outage did not become an explicit gap')
 local prev=-1
 for _,p in ipairs(points(db))do ok(p[1]>=prev,'point timestamps went backwards');prev=p[1] end
end

-- 8. API exceptions are contained. Two failed WorldPos probes become a gap; IsInInstance failure does not close an open instance.
do
 local s,l,db,tick=harness();tick(0,0,0,1)
 s.worldThrows=true;tick(.25);tick(.50);s.worldThrows=false;tick(.75,1,0,1)
 ok(stateCount(db,5)==1 and stateCount(db,6)==1,'WorldPos exception was not isolated as a gap')
 s.inside=true;s.itype='party';s.iid=42;tick(1.0);tick(1.25)
 local before=eventCount(db,1);s.instanceThrows=true;tick(1.50);s.instanceThrows=false;tick(1.75)
 eq(eventCount(db,1),before,'IsInInstance exception split the open instance')
end

-- 9. Login is a conservative break; explicit /reload can remain continuous when coordinates prove it.
do
 local s,l,db,tick,flush=harness();tick(0,0,0,1);tick(.25,1,0,1)
 s.played=.50;s.now=.50;s.x=1;l.PLAYER_ENTERING_WORLD(true,false);flush()
 local p=lastPoint(db);ok(p[6]==1 and p[9]==7,'initial login did not force resume break')
 local s2,l2,db2,tick2,flush2=harness();tick2(0,0,0,1);tick2(.25,1,0,1)
 s2.played=.50;s2.now=.50;s2.x=1;l2.PLAYER_ENTERING_WORLD(false,true);flush2()
 local p2=lastPoint(db2);ok(p2[7]==1 and p2[6]==0,'explicit UI reload created false break')
end

-- 10. A loading-screen world transition on foot is cut even if the player reappears nearby; taxi is the explicit exception.
do
 local s,l,db,tick,flush=harness();tick(0,0,0,1);tick(.25,1,0,1)
 s.played=.5;s.now=.5;s.x=1.1;l.PLAYER_ENTERING_WORLD(false,false);flush()
 local p=lastPoint(db);ok(p[6]==1 and p[9]==7,'world loading transition was silently bridged')
 local s2,l2,db2,tick2,flush2=harness({taxi=true});tick2(0,0,0,1);tick2(.25,10,0,1)
 s2.played=.5;s2.now=.5;s2.x=20;l2.PLAYER_ENTERING_WORLD(false,false);flush2()
 local p2=lastPoint(db2);ok(p2[6]==0,'taxi world transition was broken despite explicit taxi continuity')
end

-- 11. Vehicle/possession keeps measured positions but never lies that the movement is ordinary foot travel.
do
 local s,l,db,tick=harness({vehicle=true});tick(0,0,0,1);tick(.25,4,0,1)
 ok(lastPoint(db)[5]==5,'vehicle movement was mislabeled as foot')
 local s2,l2,db2,tick2=harness({possessed=true});tick2(0,0,0,1);tick2(.25,4,0,1)
 ok(lastPoint(db2)[5]==5,'possession movement was mislabeled as foot')
end

-- 12. Stable API death transition records a death even if PLAYER_DEAD itself is missed.
do
 local s,l,db,tick=harness();tick(0,0,0,1)
 s.dead=true;tick(.25,0,0,1);tick(.50,0,0,1)
 ok(eventCount(db,0)==1,'missed PLAYER_DEAD had no stable-state fallback')
end

-- 13. Shared SavedVariables are isolated by character identity and restored when switching back.
do
 local s,l,db,tick=harness({guid='A'});tick(0,0,0,1);tick(.25,1,0,1)
 local aCount=#points(db)
 s.guid='B';s.played=.5;s.now=.5;l.PLAYER_LOGIN();tick(.5,100,0,1)
 eq(db.heroPath.ownerKey,'guid:B','character B did not get an isolated active profile')
 local bCount=#points(db);ok(bCount>=1 and bCount<aCount+2,'character B inherited A path')
 s.guid='A';s.played=.75;s.now=.75;l.PLAYER_LOGIN()
 eq(db.heroPath.ownerKey,'guid:A','character A profile was not restored')
 ok(#points(db)>=aCount,'character A history was lost after switching back')
end

-- 14. Hearth is additive metadata: observed teleport/world facts are not replaced by the cause label.
do
 local s,l,db,tick=harness();tick(0,0,0,1)
 s.played=.25;s.now=.25;l.UNIT_SPELLCAST_SUCCEEDED('player',8690)
 tick(.25,100,0,1);tick(.50,101,0,1)
 ok(stateCount(db,8)==1,'Hearth replaced the observed TELEPORT fact')
 ok(stateCount(db,9)==1,'confirmed Hearth cause missing')
end

-- 15. Collector metadata explicitly advertises fixed world-position collection.
do
 local s,l,db,tick=harness();tick(0,0,0,1)
 eq(db.heroPath.collectionPolicy,'fixed-world-position-4hz-observe+curvature-aware-adaptive-store','collector policy metadata missing')
 eq(db.heroPath.adaptiveSampling,1,'adaptive store not advertised as active')
end

-- 16. The generic API wrapper itself may throw: collection survives and degrades mode semantics instead of aborting.
do
 local s,l,db,tick=harness();tick(0,0,0,1)
 s.callThrows=true;tick(.25,1,0,1)
 local p=lastPoint(db);ok(p and p[5]==5,'throwing ns.Call did not degrade movement to unknown/special')
 s.callThrows=false;tick(.50,2,0,1);ok(lastPoint(db)[1]==.5,'collector did not recover after ns.Call exception')
end

-- 17. A sustained IsInInstance outage while outside suspends collection and opens one explicit unknown interval.
do
 local s,l,db,tick=harness();tick(0,0,0,1);tick(.25,1,0,1)
 s.instanceThrows=true;tick(.50,2,0,1);tick(.75,4,0,1)
 ok(stateCount(db,5)==1,'sustained instance-state outage did not open GAP_START')
 for _,p in ipairs(points(db))do ok(math.abs(p[3]-4)>.01,'uncertain instance-state point leaked into exterior path') end
 s.instanceThrows=false;tick(1.0,6,0,1)
 ok(stateCount(db,6)==1,'instance-state recovery did not close GAP_END')
 local p=lastPoint(db);ok(p[6]==1 and p[9]==5,'instance-state recovery did not resume with unavailable break')
end

-- 18. A large forward /played jump relative to wall time is treated as a timing discontinuity, not continuous motion.
do
 local s,l,db,tick=harness();tick(0,0,0,1);tick(.25,1,0,1)
 tick(100,2,0,1,true,.50)
 ok(stateCount(db,5)>=1 and stateCount(db,6)>=1,'forward /played discontinuity was silently accepted')
 local p=lastPoint(db);ok(p[6]==1 and p[9]==5,'forward /played recovery did not create unavailable break')
end

-- 19. GetTime and numeric conversion exceptions are contained; recovery is explicit when time cannot be trusted.
do
 local s,l,db,tick=harness();tick(0,0,0,1)
 s.getTimeThrows=true;tick(.25,1,0,1);s.getTimeThrows=false;tick(.50,2,0,1)
 ok(lastPoint(db)~=nil,'GetTime exception aborted collection')
 s.numThrows=true;tick(.75,3,0,1);s.numThrows=false;tick(1.0,4,0,1)
 ok(stateCount(db,5)>=1 and stateCount(db,6)>=1,'numeric/API conversion outage was not represented as a gap')
end

-- 20. With no trustworthy life-state at first activation, no exterior point is written until the state becomes known.
do
 local s,l,db,tick=harness({lifeUnknown=true,x=123,y=456,map=987654});tick(0,123,456,987654)
 eq(#points(db),0,'unknown startup life-state wrote an unqualified path point')
 s.lifeUnknown=false;tick(.25,124,456,987654)
 local p=lastPoint(db);ok(p and p[2]==987654,'arbitrary valid startup map was not accepted once state became trustworthy')
end

-- 21. If instance-state APIs are unavailable from first activation, the collector does not assume "outside".
do
 local s,l,db,tick=harness({instanceThrows=true,x=900,y=900,map=222});tick(0,900,900,222);tick(.25,901,900,222)
 eq(#points(db),0,'startup instance uncertainty contaminated exterior history')
 s.instanceThrows=false;s.inside=true;s.itype='party';s.iname='Unknown-start dungeon';s.iid=555;tick(.50)
 ok(eventCount(db,1)==1,'instance was not recognized after startup API recovery')
 local e=db.heroPath.events[#db.heroPath.events];ok(e[1]==1 and e[12]==0,'uncertain startup invented an exterior instance anchor')
end

print('WORLD_SAMPLING_FIXED_WORLD_SAMPLING=PASS')
print('WORLD_SAMPLING_TRANSIENT_API_FILTERS=PASS')
print('WORLD_SAMPLING_DISCONTINUITY_CONFIRMATION=PASS')
print('WORLD_SAMPLING_STATE_DEBOUNCE=PASS')
print('WORLD_SAMPLING_PLAYED_INTEGRITY=PASS')
print('WORLD_SAMPLING_INSTANCE_EXIT_BREAK=PASS')
print('WORLD_SAMPLING_SESSION_BOUNDARIES=PASS')
print('WORLD_SAMPLING_OWNER_ISOLATION=PASS')
print('WORLD_SAMPLING_SPECIAL_CONTEXT=PASS')
print('WORLD_SAMPLING_API_CONTAINMENT=PASS')
print('WORLD_SAMPLING_STARTUP_UNCERTAINTY=PASS')
print('REGRESSION_WORLD_SAMPLING=PASS')
