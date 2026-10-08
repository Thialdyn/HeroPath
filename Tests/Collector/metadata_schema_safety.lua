local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub('HeroPath.lua$','Contract.lua')
local DATAMODEL=MODULE:gsub('HeroPath.lua$','DataModel.lua')
local METADATA=MODULE:gsub('HeroPath.lua$','Metadata.lua')

local function harness(initialDB)
  local st={played=0,now=0,x=10,y=20,map=1}
  local listeners,onload={},nil
  local tickers={}
  local ns={EnableResumePrime=false,EnableCollectorWatchdog=false,RequireWorldEntryBeforeSampling=false}
  ns.Num=tonumber
  ns.Call=function(n,...)
    if n=='UnitGUID' then return 'Player-HEROPATH-TEST' end
    if n=='UnitFullName' then return 'Darwyn','Forever' end
    if n=='UnitName' then return 'Darwyn' end
    if n=='GetNormalizedRealmName' or n=='GetRealmName' then return 'Forever' end
    if n=='UnitClass' then return 'Warrior','WARRIOR' end
    if n=='UnitFactionGroup' then return 'Alliance' end
    if n=='UnitIsGhost' or n=='UnitIsDeadOrGhost' or n=='UnitOnTaxi' or n=='IsMounted' or n=='IsSwimming' or n=='IsFlying' or n=='UnitInVehicle' or n=='UnitHasVehicleUI' or n=='UnitIsPossessed' then return false end
  end
  ns.PlayedNow=function() return st.played end
  ns.WorldPos=function() return st.x,st.y,st.map,'dual' end
  ns.MapContext=function() return {uiMapID=42,mapType=3,parentMapID=1,mapName='Elwynn',zone='Elwynn Forest',subzone='Goldshire'} end
  ns.Listen=function(e,f) listeners[e]=f;return true end
  ns.OnLoad=function(f) onload=f end
  _G.GetTime=function() return st.now end
  _G.IsInInstance=function() return false,'none' end
  _G.GetInstanceInfo=function() return 'World','none',nil,nil,nil,nil,nil,nil,0 end
  _G.C_Timer={NewTicker=function(interval,cb)local t={interval=interval,cb=cb};tickers[#tickers+1]=t;return t end,After=function(_,fn) fn() end}
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
  assert(loadfile(CONTRACT))('HeroPath',ns)
  assert(loadfile(DATAMODEL))('HeroPath',ns)
  assert(loadfile(METADATA))('HeroPath',ns)
  assert(loadfile(MODULE))('HeroPath',ns)
  local db=initialDB or {}
  onload(db)
  return db,ns,listeners,tickers,st
end

-- A fresh database is initialized directly on the public schema.
do
  local db,ns=harness({})
  assert(db.schema==1,'root schema was not initialized')
  assert(db.heroPath.schema==1,'profile schema was not initialized')
  local ro=ns.GetArchiveState()
  assert(ro==false,'fresh schema entered archive mode')
end

-- A future schema is preserved structurally: no repair, ticker or write path
-- is allowed to touch data this build cannot understand.
do
  local db={schema=2,heroPath={schema=2,sentinel='preserve-me',tail={{1,1,2,3,0,0,0,1,0}}},customFutureField={alpha=1}}
  local beforeHero=db.heroPath
  local beforeTail=db.heroPath.tail
  local db2,ns,listeners,tickers=harness(db)
  local ro,schema,reason=ns.GetArchiveState()
  assert(ro==true and schema==2 and reason=='future-schema','future schema did not enter read-only archive mode')
  assert(db2.schema==2 and db2.heroPath==beforeHero and db2.heroPath.tail==beforeTail,'future schema structure was replaced')
  assert(db2.heroPath.sentinel=='preserve-me' and db2.customFutureField.alpha==1,'future schema data mutated')
  assert(#tickers==0,'collector ticker started in archive mode')
  if listeners.PLAYER_LOGOUT then listeners.PLAYER_LOGOUT() end
  assert(db2.heroPath.sentinel=='preserve-me' and db2.schema==2,'logout mutated read-only archive')
  local health=ns.GetCollectorHealth()
  assert(health.archiveReadOnly==true and health.sampleAttempts==0,'archive diagnostics incorrect')
end

-- Metadata sanitizers reject malformed rows while retaining trustworthy context.
do
  local db,ns=harness()
  local H=db.heroPath
  local id=assert(ns.Metadata.AddContextSnapshot(H,ns.Contract.Context.SESSION,1,1,10,20,1))
  assert(id==1 and H.contextEvents[1].uiMapID==42 and H.contextEvents[1].zone=='Elwynn Forest','map context snapshot incomplete')
  H.contextEvents[#H.contextEvents+1]={id=1,kind=999,played='bad'}
  local q=0
  local clean,maxId=ns.Metadata.SanitizeContextEvents(H,function() q=q+1 end)
  assert(#clean==1 and maxId==1 and q==1,'context sanitizer failed closed incorrectly')
end

print('METADATA_SCHEMA_INITIALIZATION=PASS')
print('METADATA_FUTURE_SCHEMA_ARCHIVE=PASS')
print('METADATA_CONTEXT_SANITATION=PASS')
print('METADATA_SCHEMA_SAFETY=PASS')
