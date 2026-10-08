local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")

local function harness(initialDB,initialState)
  local st={played=0,now=0,x=0,y=0,map=1,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,inside=false,itype='none',iname='World',iid=0,guid='Player-TEST-001',name='TestCharacter',realm='TestRealm'}
  for k,v in pairs(initialState or {}) do st[k]=v end
  local listeners,onload={},nil
  local afterQ={};local tickers={}
  local ns={EnableResumePrime=false,EnableCollectorWatchdog=false,RequireWorldEntryBeforeSampling=false,Num=tonumber}
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
  end
  ns.PlayedNow=function() return st.played end
  ns.WorldPos=function() return st.x,st.y,st.map,'dual' end
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
  local function sampler()for i=#tickers,1,-1 do if tickers[i].interval==.25 and not tickers[i].cancelled then return tickers[i] end end end
  local function tick(t,x,y)
    st.played=t;st.now=t;st.x=x or st.x;st.y=y or st.y
    assert(sampler(),'sampler missing').cb()
  end
  local function one()local q=table.remove(afterQ,1);if q then q.cb();return true end;return false end
  return {st=st,ns=ns,db=db,listeners=listeners,tick=tick,one=one,afterQ=afterQ}
end

local function allPoints(e)
  local H=e.db.heroPath;local out={}
  for _,ch in ipairs(H.chunks or{}) do local d=assert(e.ns.DecodeHeroPathChunk(ch));for _,p in ipairs(d)do out[#out+1]=p end end
  for _,p in ipairs(H.tail or{})do out[#out+1]=p end
  table.sort(out,function(a,b)return (a[8]or 0)<(b[8]or 0)end)
  return out
end
local function qcount(H)return H.recoveryQuarantine and H.recoveryQuarantine.entries and #H.recoveryQuarantine.entries or 0 end
local function point(t,x,o,br,prot)return {t,1,x,0,0,br or 0,prot or 0,o,br==1 and 1 or 0} end

-- Strict integrity bits: invalid truthy values are corruption, not silently coerced to false.
do
  local db={heroPath={tail={point(1,10,1),{2,1,20,0,0,999,0,2,0},point(3,30,3)},events={}}}
  local e=harness(db);local p=allPoints(e)
  assert(#p==2,'invalid integrity bit survived')
  assert(p[2][6]==1,'point after corrupted integrity bit was bridged')
  assert(qcount(e.db.heroPath)>=1,'corrupted point not quarantined')
end

-- Sparse numeric tables must not hide valid data after a nil hole.
do
  local pts={[1]=point(1,10,1),[3]=point(3,30,3)}
  local e=harness({heroPath={tail=pts,events={}}});local p=allPoints(e)
  assert(#p==2,'tail data after numeric hole was lost')
  assert(p[2][6]==1,'numeric hole did not force discontinuity')
  assert(qcount(e.db.heroPath)>=1,'numeric hole not recorded')
end

-- lastPlayed is reconstructed from trustworthy history; absurd but finite metadata cannot lock future /played.
do
  local e=harness({heroPath={tail={point(1,10,1),point(3,30,3)},lastPlayed=1000000000,events={}}})
  assert(e.db.heroPath.lastPlayed==3,'corrupt lastPlayed remained authoritative')
  assert(qcount(e.db.heroPath)>=1,'lastPlayed anomaly not quarantined')
end

-- lastPlayed without any surviving history is not trusted either.
do
  local e=harness({heroPath={lastPlayed=1000000000,events={}}})
  assert(e.db.heroPath.lastPlayed==0,'orphan lastPlayed blocked an empty history')
end


-- Malformed heroPath root is preserved outside the active model.
do
  local db={heroPath='damaged-root'};local e=harness(db)
  assert(type(e.db.heroPath)=='table','heroPath root not rebuilt')
  assert(type(e.db.recoveryRootQuarantine)=='table' and #e.db.recoveryRootQuarantine>=1,'malformed heroPath root not preserved')
end

-- Semantic coordinates carry explicit validity; impossible coordinates become unknown, not fake 0/0 positions.
do
  local e=harness({heroPath={semanticEvents={{1,1,1,8690,1,1e300,-1e300}},events={}}})
  local se=e.db.heroPath.semanticEvents[1];assert(se and se[8]==0 and se[6]==0 and se[7]==0,'semantic invalid position not made explicit')
end

-- Encoded chunks without the trusted flag are deep-validated before use.
do
  local pts={};for i=1,800 do pts[i]=point(i*.25,i,i) end
  local seed=harness()
  local ch=assert(seed.ns.DataModel.EncodeChunk(pts),'chunk encode failed')
  ch[17]=nil
  local b=harness({heroPath={chunks={ch},tail={},events={}}})
  assert(b.db.heroPath.chunks[1] and b.db.heroPath.chunks[1][17]==1,'chunk was not deep-certified')
end

-- Starting/reloading already inside an instance must never reuse an old outdoor
-- resume anchor as the location of a new death. If no fresh entrance anchor exists,
-- the location is explicitly unknown instead of confidently wrong.
do
  local old=point(1,123,1);old[4]=456
  local e=harness({heroPath={tail={old},events={},lastPlayed=1}},
                  {played=100,now=100,inside=true,itype='party',iname='Dungeon',iid=777,dead=false})
  assert(e.listeners.PLAYER_DEAD,'death listener missing')
  e.st.dead=true;e.st.played=100;e.st.now=100
  e.listeners.PLAYER_DEAD()
  local ev=e.db.heroPath.events[#e.db.heroPath.events]
  assert(ev and ev[1]==0,'death event missing')
  assert(ev[6]==1,'startup in-instance death was classified outside')
  assert(ev[8]==4,'stale outdoor resume anchor was reused for in-instance death')
  assert(ev[3]==0 and ev[4]==0 and ev[5]==0,'unknown in-instance death fabricated coordinates')
end

-- Structural corruption discovered by live compaction is deterministic: preserve
-- the raw tail, quarantine once, latch recovery, and do not spin automatic retries.
do
  local tail={};for i=1,999 do tail[i]=point(i*.25,i,i) end
  local e=harness({heroPath={tail=tail,events={}}})
  e.st.played=250;e.st.now=250;e.st.x=1000;e.st.y=0
  e.tick(250,1000,0)
  assert(#e.db.heroPath.tail>=1000,'test did not schedule structural compaction')
  e.db.heroPath.tail[500]={}
  assert(e.one(),'structural compression callback missing')
  local h=e.ns.GetCollectorHealth()
  assert((h.compressionErrors or 0)>=1,'structural compression fault was not diagnosed')
  assert(#e.db.heroPath.tail>=1000,'structural compression fault discarded authoritative tail')
  assert(h.compressionRecoveryNeeded==true,'structural compression fault did not latch recovery')
  assert(#e.afterQ==0,'structural corruption scheduled pointless automatic retries')
end

-- A genuinely transient compaction exception must preserve the authoritative raw
-- tail, surface a diagnostic, and retry after the transient fault clears.
-- Regression: an older recovery flag also blocked ScheduleCompression(), making the
-- delayed retry impossible.
do
  local tail={};for i=1,999 do tail[i]=point(i*.25,i,i) end
  local e=harness({heroPath={tail=tail,events={}}})
  e.st.played=250;e.st.now=250;e.st.x=1000;e.st.y=0
  e.tick(250,1000,0)
  assert(#e.db.heroPath.tail>=1000,'test did not schedule transient compaction')

  _G.debugprofilestop=function() error('synthetic transient compression profiler fault') end
  assert(e.one(),'transient compression callback missing')
  _G.debugprofilestop=nil
  local h=e.ns.GetCollectorHealth()
  assert((h.compressionErrors or 0)>=1,'transient compression fault was not diagnosed')
  assert(#e.db.heroPath.tail>=1000,'transient compression fault discarded authoritative tail')
  assert(h.compressionRecoveryNeeded==false,'transient first failure prematurely latched recovery mode')
  assert(#e.afterQ>=1,'transient compression fault did not schedule a retry')

  local guard=0
  while #e.afterQ>0 do
    guard=guard+1;assert(guard<10000,'compression retry queue runaway')
    assert(e.one(),'queued retry disappeared')
  end
  h=e.ns.GetCollectorHealth()
  assert(#e.db.heroPath.chunks>=1,'transient compression failure never retried successfully')
  assert(#e.db.heroPath.tail<1000,'successful retry did not compact the raw tail')
  assert(h.compressionRecoveryNeeded==false,'recovery flag remained latched after successful retry')
end

print('RECOVERY_STRICT_BITS=PASS')
print('RECOVERY_NUMERIC_HOLES=PASS')
print('RECOVERY_LASTPLAYED=PASS')
print('RECOVERY_ROOT_QUARANTINE=PASS')
print('RECOVERY_SEMANTIC_POSITION=PASS')
print('RECOVERY_DEEP_VALIDATION=PASS')
print('RECOVERY_STALE_INSTANCE_DEATH_ANCHOR=PASS')
print('RECOVERY_COMPACTION_TRANSACTION=PASS')
print('RECOVERY_COMPACTION_RETRY=PASS')
print('RECOVERY_INTEGRITY=PASS')
