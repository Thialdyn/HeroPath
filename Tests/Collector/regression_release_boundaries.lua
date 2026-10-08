local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")

local function harness(opts, initialDB)
  opts=opts or {}
  local st={played=0,now=0,x=0,y=0,map=1,source='dual',missing=false,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,vehicle=false,possessed=false,
            inside=false,itype='none',iname='World',iid=0,guid='Player-TEST-A',name='Tester',realm='Forever'}
  local listeners,onload={},nil
  local afterQ={};local tickers={}
  local secret=opts.secret
  local ns={EnableResumePrime=opts.resumePrime==true,EnableCollectorWatchdog=false,RequireWorldEntryBeforeSampling=false}
  ns.Num=function(v) if secret and v==secret then error('secret value') end return tonumber(v) end
  ns.Call=function(n,...)
    if n=='UnitGUID' then return st.guid end
    if n=='UnitFullName' then return st.name,st.realm end
    if n=='UnitName' then return st.name end
    if n=='GetNormalizedRealmName' or n=='GetRealmName' then return st.realm end
    if n=='UnitClass' then return 'Warrior','WARRIOR' end
    if n=='UnitFactionGroup' then return 'Alliance' end
    if n=='UnitIsGhost' then return st.ghost end
    if n=='UnitIsDeadOrGhost' then return st.dead or st.ghost end
    if n=='UnitOnTaxi' then return st.taxi end
    if n=='IsMounted' then return st.mounted end
    if n=='IsSwimming' then return st.swimming end
    if n=='UnitInVehicle' or n=='UnitHasVehicleUI' then return st.vehicle end
    if n=='UnitIsPossessed' then return st.possessed end
  end
  ns.PlayedNow=function() return st.played end
  ns.MapContext=function() return {uiMapID=st.map,mapType=3,parentMapID=0,mapName='Test Map',zone='Test Zone',subzone='Test Subzone'} end
  ns.WorldPos=function()
    if st.missing then return nil,nil,nil,st.source or 'none' end
    return st.x,st.y,st.map,st.source
  end
  ns.Listen=function(e,f) listeners[e]=f;return true end
  ns.OnLoad=function(f) onload=f end
  _G.GetTime=function() return st.now end
  _G.IsInInstance=function() return st.inside,st.itype end
  _G.GetInstanceInfo=function() return st.iname,st.itype,nil,nil,nil,nil,nil,nil,st.iid end
  _G.C_Timer={
    NewTicker=function(interval,f)local o={interval=interval,cb=f,cancelled=false};function o:Cancel()self.cancelled=true end;tickers[#tickers+1]=o;return o end,
    After=function(delay,f)afterQ[#afterQ+1]={delay=delay,cb=f}end,
  }
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
  local db=initialDB or {};onload(db)
  local function sampleTicker()for i=#tickers,1,-1 do if tickers[i].interval==.25 and not tickers[i].cancelled then return tickers[i] end end end
  local function tick(t,x,y,map)
    st.played=t;st.now=t;if x~=nil then st.x=x end;if y~=nil then st.y=y end;if map~=nil then st.map=map end
    assert(sampleTicker(),'no sample ticker').cb()
  end
  local function one()local q=table.remove(afterQ,1);if q then q.cb();return true end;return false end
  local function flush(limit)local n=0;limit=limit or 10000;while #afterQ>0 do n=n+1;assert(n<=limit,'timer runaway');one() end end
  return {st=st,ns=ns,db=db,listeners=listeners,tick=tick,one=one,flush=flush,secret=secret}
end

local function allPoints(e)
  local out={};local H=e.db.heroPath
  for _,ch in ipairs(H.chunks or {}) do local d=assert(e.ns.DecodeHeroPathChunk(ch));for _,p in ipairs(d)do out[#out+1]=p end end
  for _,p in ipairs(H.tail or {})do out[#out+1]=p end
  table.sort(out,function(a,b)return (a[8]or 0)<(b[8]or 0)end)
  return out
end
local function stateCount(e,code)local n=0;for _,v in ipairs(e.db.heroPath.events or{})do if v[1]==2 and v[2]==code then n=n+1 end end;return n end
local function deathLast(e)for i=#e.db.heroPath.events,1,-1 do local v=e.db.heroPath.events[i];if v[1]==0 then return v end end end
local function instanceLast(e)for i=#e.db.heroPath.events,1,-1 do local v=e.db.heroPath.events[i];if v[1]==1 then return v end end end

-- 1. A corrupt encoded interval must become an intrinsic break on decode.
do
  local seed=harness()
  local chunks={}
  for firstIndex=1,1500,500 do
    local pts={}
    for i=firstIndex,firstIndex+499 do pts[#pts+1]={i*.25,1,i,0,0,0,0,i,0} end
    chunks[#chunks+1]=assert(seed.ns.DataModel.EncodeChunk(pts))
  end
  local first=harness({}, {schema=1,heroPath={schema=1,chunks=chunks,tail={},events={}}})
  assert(#first.db.heroPath.chunks==3,'failed to build seed chunks')
  first.db.heroPath.chunks[2][2]=first.db.heroPath.chunks[2][2]..'X' -- recognized HP1, invalid checksum
  local second=harness({}, first.db)
  assert(#second.db.heroPath.chunks>=2,'valid chunk after corruption was lost')
  local d=assert(second.ns.DecodeHeroPathChunk(second.db.heroPath.chunks[2]))
  assert(d[1][6]==1 and d[1][7]==1 and d[1][9]==5,'forceBreak metadata did not become BREAK_UNAVAILABLE geometry')
end

-- 2. Resume prime rejects a transient chain 0,0 -> 40,0 before the real destination.
do
  local e=harness({resumePrime=true});e.tick(0,1000,1000,1);e.tick(.25,1001,1000,1)
  e.st.played=.30;e.st.now=.30;e.listeners.PLAYER_LEAVING_WORLD()
  e.st.played=.50;e.st.now=.50;e.st.x=0;e.st.y=0;e.listeners.PLAYER_ENTERING_WORLD(false,false);assert(e.one())
  e.st.played=.65;e.st.now=.65;e.st.x=40;e.st.y=0;assert(e.one())
  e.st.played=.80;e.st.now=.80;e.st.x=5000;e.st.y=5000;assert(e.one())
  e.st.played=.95;e.st.now=.95;e.st.x=5001;e.st.y=5000;assert(e.one());e.flush()
  for _,p in ipairs(allPoints(e)) do assert(not (p[1]>=.5 and p[3]<100),'transient post-loading coordinate leaked') end
  local ps=allPoints(e);assert(ps[#ps][3]>=5000,'real resume destination not accepted')
end

-- 3. A long semantic hint cannot turn later ordinary motion into a teleport.
do
  local e=harness();e.tick(0,0,0,1);e.tick(.25,1,0,1)
  e.st.played=.30;e.st.now=.30;e.listeners.UNIT_SPELLCAST_SUCCEEDED('player','Cast',8690)
  e.tick(1.30,15,0,1)
  assert(stateCount(e,8)==0 and stateCount(e,9)==0,'unbound Hearth hint contaminated later normal movement')
end

-- 4. The same long hint survives an actual loading boundary and labels only that boundary.
do
  local e=harness({resumePrime=true});e.tick(0,0,0,1);e.tick(.25,1,0,1)
  e.st.played=.30;e.st.now=.30;e.listeners.UNIT_SPELLCAST_SUCCEEDED('player','Cast',8690)
  e.st.played=.35;e.st.now=.35;e.listeners.PLAYER_LEAVING_WORLD()
  e.st.played=30;e.st.now=30;e.st.x=5000;e.st.y=0;e.listeners.PLAYER_ENTERING_WORLD(false,false);assert(e.one())
  e.st.played=30.15;e.st.now=30.15;e.st.x=5001;e.st.y=0;assert(e.one());e.flush()
  assert(stateCount(e,8)>=1 and stateCount(e,9)==1,'Hearth boundary cause was not retained causally')
  assert(#(e.db.heroPath.semanticEvents or{})==1,'Hearth semantic event count wrong')
  local tr=assert((e.db.heroPath.transitions or{})[1],'correlated transition missing')
  assert(tr.cause==e.ns.Contract.Transition.Cause.HEARTH and tr.confidence==e.ns.Contract.Transition.Confidence.SEMANTIC_CONFIRMED,'Hearth transition cause/confidence wrong')
  assert(tr.departure and tr.arrival and tr.departure.positionKnown==1 and tr.arrival.positionKnown==1,'transition endpoints missing')
  assert(tr.departure.contextId and tr.arrival.contextId,'transition contexts not linked')
  local linked=0
  for _,ev in ipairs(e.db.heroPath.events or{}) do if ev[1]==2 and ev[9]==tr.id then linked=linked+1 end end
  assert(linked>=2,'state events are not linked to transition id')
  assert((e.db.heroPath.semanticEvents or{})[1][9]==tr.id,'semantic event is not linked to transition id')
  assert(#(e.db.heroPath.contextEvents or{})>=2,'semantic context snapshots missing')
end

-- 5. In-instance death uses the debounced state even if IsInInstance flickers false on PLAYER_DEAD.
do
  local e=harness();e.tick(0,0,0,1);e.tick(.25,1,0,1)
  e.st.inside=true;e.st.itype='party';e.st.iname='Scholomance';e.st.iid=289;e.tick(.50,2,0,1);e.tick(.75,2,0,1)
  assert(instanceLast(e),'instance event not opened')
  local before=#allPoints(e)
  e.st.inside=false;e.st.itype='none';e.st.dead=true;e.st.played=.80;e.st.now=.80;e.listeners.PLAYER_DEAD()
  local d=assert(deathLast(e),'death event missing');assert(d[6]==1,'one-frame instance false moved death outside')
  -- no interior polyline is ever recorded
  e.st.inside=true;e.st.dead=false;e.st.x=9000;e.st.y=9000;e.tick(1.0,9000,9000,1);e.tick(1.25,9100,9100,1)
  assert(#allPoints(e)==before,'interior instance positions leaked into Hero Path')
end

-- 6. More than 1.25 s without samples becomes an explicit unknown interval.
do
  local e=harness();e.tick(0,0,0,1);e.tick(.25,1,0,1);e.tick(1.75,10,0,1)
  assert(stateCount(e,5)>=1 and stateCount(e,6)>=1,'missed 4 Hz probes did not create explicit gap')
  local p=allPoints(e)[#allPoints(e)];assert(p[6]==1 and p[9]==5,'post-gap point not BREAK_UNAVAILABLE')
end

-- 7. Restored absurd coordinates are rejected and cannot poison later geometry.
do
  local db={heroPath={tail={{1,1,10,10,0,0,0,1,0},{2,1,1e300,-1e300,0,0,0,2,0},{3,1,20,20,0,0,0,3,0}},events={}}}
  local e=harness({},db);local ps=allPoints(e)
  assert(#ps==2,'absurd saved coordinate survived sanitation')
  assert(math.abs(ps[1][3])<1e7 and math.abs(ps[2][3])<1e7,'absurd coordinate remained')
  assert(ps[2][6]==1,'valid point after invalid saved coordinate was silently bridged')
end

-- 8. Restricted/secret spell arguments degrade to no hint rather than throwing.
do
  local secret={};local e=harness({secret=secret});e.tick(0,0,0,1)
  local ok=pcall(e.listeners.UNIT_SPELLCAST_SUCCEEDED,'player','Cast',secret)
  assert(ok,'secret spell payload escaped protected conversion')
  assert(#(e.db.heroPath.semanticEvents or{})==0,'secret payload invented semantic event')
end

-- 9. Restricted/non-string instance metadata must degrade to generic instance
-- identity instead of escaping through tostring/tonumber and killing a sample.
do
  local secret=setmetatable({}, {__tostring=function() error('secret tostring') end})
  local e=harness({secret=secret});e.tick(0,0,0,1);e.tick(.25,1,0,1)
  e.st.inside=true;e.st.itype=secret;e.st.iname=secret;e.st.iid=secret
  local ok,err=pcall(e.tick,.50,2,0,1);assert(ok,'restricted instance metadata escaped containment: '..tostring(err))
  ok,err=pcall(e.tick,.75,2,0,1);assert(ok,'restricted instance metadata escaped debounce: '..tostring(err))
  local inst=instanceLast(e);assert(inst,'generic instance event missing after restricted metadata')
  assert(inst[7]=='Instance' and inst[8]=='instance' and inst[9]==0,'restricted instance metadata was not normalized safely')
end

-- 10. Position-source telemetry is tiny, persistent, and distinguishes mismatches.
do
  local e=harness();e.st.source='dual';e.tick(0,0,0,1);e.st.source='cmap';e.tick(.25,1,0,1)
  e.st.missing=true;e.st.source='mismatch';e.tick(.50,1,0,1)
  local d=e.db.heroPath.positionDiagnostics
  assert(d.dual>=1 and d.cmap>=1 and d.mismatch>=1,'position source diagnostics incomplete')
  assert(e.db.heroPath.instanceTracePolicy=='no-interior-polyline;entry-exit-duration-events-only','instance trace policy changed')
end

print('RELEASE_BOUNDARIES_CORRUPT_CHUNK_BREAK=PASS')
print('RELEASE_BOUNDARIES_STRICT_RESUME_PRIME=PASS')
print('RELEASE_BOUNDARIES_CAUSAL_SEMANTIC_HINTS=PASS')
print('RELEASE_BOUNDARIES_INSTANCE_DEATH_DEBOUNCE=PASS')
print('RELEASE_BOUNDARIES_SAMPLE_GAP=PASS')
print('RELEASE_BOUNDARIES_COORD_SANITATION=PASS')
print('RELEASE_BOUNDARIES_SECRET_SPELL_SAFE=PASS')
print('RELEASE_BOUNDARIES_RESTRICTED_INSTANCE_SAFE=PASS')
print('RELEASE_BOUNDARIES_POSITION_DIAGNOSTICS=PASS')
print('REGRESSION_RELEASE_BOUNDARIES=PASS')
