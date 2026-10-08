local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")

local function harness(opts)
  opts=opts or {}
  local st={played=0,now=0,x=0,y=0,map=1,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,vehicle=false,possessed=false,
            inside=false,itype='none',iname='Instance',iid=0,guid='Player-TEST-A',name='Tester',realm='Realm'}
  local listeners,onload={},nil
  local afterQ={}; local tickers={}; local worldCalls=0; local ns={EnableResumePrime=opts.resumePrime==true,EnableCollectorWatchdog=opts.watchdog==true}
  ns.Num=tonumber
  ns.Call=function(n,...)
    if n=='UnitIsGhost' then return st.ghost end
    if n=='UnitIsDeadOrGhost' then return st.dead or st.ghost end
    if n=='UnitOnTaxi' then return st.taxi end
    if n=='IsMounted' then return st.mounted end
    if n=='IsSwimming' then return st.swimming end
    if n=='UnitInVehicle' or n=='UnitHasVehicleUI' then return st.vehicle end
    if n=='UnitIsPossessed' then return st.possessed end
    if n=='UnitGUID' then return st.guid end
    if n=='UnitFullName' then return st.name,st.realm end
    if n=='UnitName' then return st.name end
    if n=='GetNormalizedRealmName' or n=='GetRealmName' then return st.realm end
    if n=='UnitClass' then return 'Warrior','WARRIOR' end
    if n=='UnitFactionGroup' then return 'Alliance' end
  end
  ns.PlayedNow=function() return st.played end
  ns.WorldPos=function() worldCalls=worldCalls+1; return st.x,st.y,st.map,'dual' end
  ns.Listen=function(e,f) listeners[e]=f; return true end
  ns.OnLoad=function(f) onload=f end
  _G.GetTime=function() return st.now end
  _G.IsInInstance=function() return st.inside,st.itype end
  _G.GetInstanceInfo=function() return st.iname,st.itype,nil,nil,nil,nil,nil,st.iid end
  _G.C_Timer={
    NewTicker=function(interval,f)
      local o={interval=interval,cb=f,cancelled=false}; function o:Cancel() self.cancelled=true end
      tickers[#tickers+1]=o; return o
    end,
    After=function(delay,f) afterQ[#afterQ+1]={delay=delay,cb=f} end,
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
  local db={}; onload(db)
  local function sampleTicker()
    for i=#tickers,1,-1 do if tickers[i].interval==0.25 and not tickers[i].cancelled then return tickers[i] end end
  end
  local function watchdogTicker()
    for i=#tickers,1,-1 do if tickers[i].interval==2 and not tickers[i].cancelled then return tickers[i] end end
  end
  local function tick(t,x,y,map)
    st.played=t;st.now=t;if x~=nil then st.x=x end;if y~=nil then st.y=y end;if map~=nil then st.map=map end
    local o=assert(sampleTicker(),'no sample ticker');o.cb()
  end
  local function runOneAfter()
    local q=table.remove(afterQ,1); if q then q.cb(); return true end; return false
  end
  local function flush(n)
    n=n or 100;local i=0;while #afterQ>0 do i=i+1;assert(i<=n,'after runaway');runOneAfter() end
  end
  return st,listeners,db,tick,runOneAfter,flush,function()return worldCalls end,sampleTicker,watchdogTicker,ns,tickers
end

local function points(db) return db.heroPath.tail or {} end
local function stateCount(db,code)local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==2 and e[2]==code then n=n+1 end end;return n end
local function semanticCount(db,code)local n=0;for _,e in ipairs(db.heroPath.semanticEvents or{})do if not code or e[3]==code then n=n+1 end end;return n end
local function ok(v,m) assert(v,m) end
local function eq(a,b,m) assert(a==b,(m or 'eq')..' got='..tostring(a)..' expected='..tostring(b)) end

-- 1. Resume stabilization: a transient first post-loading coordinate must never become an anchor.
do
  local s,l,db,tick,one,flush=harness({resumePrime=true})
  tick(0,1000,1000,1);tick(.25,1002,1000,1)
  s.played=.50;s.now=.50;s.x=0;s.y=0;l.PLAYER_ENTERING_WORLD(false,false)
  ok(one(),'missing first world prime') -- captures bogus candidate only
  s.played=.65;s.now=.65;s.x=5000;s.y=4000;ok(one(),'missing second world prime') -- rejects/replaces bogus candidate
  s.played=.80;s.now=.80;s.x=5001;s.y=4000;ok(one(),'missing third world prime') -- stable destination accepted
  flush()
  for _,p in ipairs(points(db)) do ok(not (p[3]==0 and p[4]==0 and p[1]>=.5),'transient 0,0 leaked into history') end
  local last=points(db)[#points(db)];ok(last and last[3]>=5000,'stable post-loading position not accepted')
end

-- 2. A short forced/charge-like displacement is special movement, not a generic teleport.
do
  local s,l,db,tick=harness();tick(0,0,0,1);tick(.25,2,0,1);s.played=.30;s.now=.30;l.UNIT_SPELLCAST_SUCCEEDED('player','cast-guid',100);tick(.50,27,0,1);tick(.75,28,0,1)
  eq(stateCount(db,8),0,'30yd rapid move became generic teleport')
  local special=false;for _,p in ipairs(points(db))do if p[5]==5 then special=true end end
  ok(special,'rapid short movement was not preserved as unknown/special')
end

-- 3. Blink is a semantic short teleport: geometry alone would not break at this distance.
do
  local s,l,db,tick=harness();tick(0,0,0,1);tick(.25,1,0,1)
  s.played=.30;s.now=.30;l.UNIT_SPELLCAST_SUCCEEDED('player','cast-guid',1953)
  tick(.50,21,0,1);tick(.75,21,0,1)
  eq(stateCount(db,8),1,'Blink semantic teleport missing')
  eq(semanticCount(db,2),1,'Blink spell evidence not persisted')
  local ev=db.heroPath.semanticEvents[#db.heroPath.semanticEvents];eq(ev[4],1953,'wrong semantic spell id')
end

-- 4. Astral Recall is treated as hearth-like cause, but observed TELEPORT remains the primary fact.
do
  local s,l,db,tick=harness();tick(0,0,0,1);tick(.25,1,0,1)
  s.played=.30;s.now=.30;l.UNIT_SPELLCAST_SUCCEEDED('player','cast-guid',556)
  tick(.50,1000,0,1);tick(.75,1001,0,1)
  eq(stateCount(db,8),1,'Astral Recall observed teleport missing')
  eq(stateCount(db,9),1,'Astral Recall hearth-like cause missing')
  eq(semanticCount(db,1),1,'Astral Recall semantic record missing')
end

-- 5. PLAYER_LEAVING_WORLD explicitly suspends collection and opens an unknown interval.
do
  local s,l,db,tick,one,flush,wc=harness({resumePrime=true});tick(0,0,0,1);tick(.25,1,0,1)
  local before=wc();s.played=.30;s.now=.30;l.PLAYER_LEAVING_WORLD()
  tick(.50,9999,9999,1);eq(wc(),before,'world API was queried while world was suspended')
  s.played=.60;s.now=.60;s.x=10;s.y=0;l.PLAYER_ENTERING_WORLD(false,false);flush()
  ok(stateCount(db,5)>=1 and stateCount(db,6)>=1,'loading boundary was not represented as explicit gap')
  local last=points(db)[#points(db)];ok(last and last[6]==1,'post-loading path was silently bridged')
end

-- 6. Watchdog restarts a stalled ticker and marks the unobserved interval unknown.
do
  local s,l,db,tick,one,flush,wc,getSample,getWatchdog,ns,tickers=harness({watchdog=true})
  tick(0,0,0,1);tick(.25,1,0,1)
  local old=getSample();s.played=3.5;s.now=3.5
  local w=assert(getWatchdog(),'watchdog missing');w.cb()
  ok(old.cancelled==true,'stalled sample ticker was not cancelled')
  local newer=getSample();ok(newer and newer~=old,'sample ticker was not restarted')
  s.x=5;newer.cb()
  ok(stateCount(db,5)>=1 and stateCount(db,6)>=1,'watchdog recovery did not create unknown interval')
  local h=ns.GetCollectorHealth();ok(h.sampleErrors>=1 and tostring(h.lastSampleError):find('ticker%-stalled'),'watchdog fault not exposed in health')
end

print('RESUME_STABILITY_RESUME_PRIME=PASS')
print('RESUME_STABILITY_SHORT_FORCED_MOVEMENT=PASS')
print('RESUME_STABILITY_SEMANTIC_TELEPORTS=PASS')
print('RESUME_STABILITY_WORLD_SUSPEND_GAP=PASS')
print('RESUME_STABILITY_WATCHDOG=PASS')
print('REGRESSION_RESUME_STABILITY=PASS')
