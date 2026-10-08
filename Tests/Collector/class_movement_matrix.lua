local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")

local function newEnv(classFile)
  local st={played=0,now=0,x=0,y=0,map=1,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,inside=false,itype='none',iname='World',iid=0,
            guid='Player-1-ABC',name='Tester',realm='Forever',vehicle=false,possessed=false}
  local listeners,onload,ticker={},nil,nil
  local q={}
  local ns={}
  ns.Num=tonumber
  ns.Call=function(n,...)
    if n=='UnitGUID' then return st.guid end
    if n=='UnitFullName' then return st.name,st.realm end
    if n=='UnitName' then return st.name end
    if n=='GetNormalizedRealmName' or n=='GetRealmName' then return st.realm end
    if n=='UnitClass' then return classFile or 'Warrior',string.upper(classFile or 'WARRIOR') end
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
  ns.WorldPos=function() return st.x,st.y,st.map,'dual' end
  ns.Listen=function(e,f) listeners[e]=f end
  ns.OnLoad=function(f) onload=f end
  ns.RequireWorldEntryBeforeSampling=false
  ns.EnableResumePrime=false
  ns.EnableCollectorWatchdog=false
  _G.GetTime=function() return st.now end
  _G.debugprofilestop=function() return os.clock()*1000 end
  _G.IsInInstance=function() return st.inside,st.itype end
  _G.GetInstanceInfo=function() return st.iname,st.itype,nil,nil,nil,nil,nil,nil,st.iid end
  _G.C_Timer={NewTicker=function(_,f) ticker=f;return{Cancel=function()end}end,After=function(_,f) q[#q+1]=f end}
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
  local function flush(limit)
    limit=limit or 100000
    local n=0
    while #q>0 do n=n+1;assert(n<=limit,'timer runaway');local f=table.remove(q,1);f() end
  end
  local function sample(dt,x,y)
    st.played=st.played+(dt or .25);st.now=st.now+(dt or .25)
    if x~=nil then st.x=x end;if y~=nil then st.y=y end
    ticker();flush()
  end
  local function cast(spellID)
    assert(listeners.UNIT_SPELLCAST_SUCCEEDED,'spell listener absent')
    listeners.UNIT_SPELLCAST_SUCCEEDED('player','Cast-1',spellID)
  end
  return {st=st,ns=ns,db=db,listeners=listeners,flush=flush,sample=sample,cast=cast}
end

local function points(env)
  local out={}
  local H=env.db.heroPath
  for _,ch in ipairs(H.chunks or {}) do
    local d=assert(env.ns.DecodeHeroPathChunk(ch))
    for _,p in ipairs(d) do out[#out+1]=p end
  end
  for _,p in ipairs(H.tail or {}) do out[#out+1]=p end
  table.sort(out,function(a,b) return (a[8] or 0)<(b[8] or 0) end)
  return out
end
local function hasBreak(env,reason)
  for _,p in ipairs(points(env)) do if p[6]==1 and p[9]==reason then return true end end
  return false
end
local function countBreak(env,reason)
  local n=0;for _,p in ipairs(points(env)) do if p[6]==1 and p[9]==reason then n=n+1 end end;return n
end
local function eventsByCode(env,code)
  local n=0;for _,e in ipairs(env.db.heroPath.events or {}) do if e[1]==2 and e[2]==code then n=n+1 end end;return n
end

-- Baseline first anchor.
local function anchor(e) e.sample(.25,0,0);e.sample(.25,1,0) end

-- WARRIOR: Charge/Intercept are continuous gap closers, not teleports.
do
 local e=newEnv('WARRIOR');anchor(e);e.cast(100);e.sample(.25,26,0);e.sample(.25,27,0)
 assert(not hasBreak(e,8),'Warrior Charge falsely uncertain')
 local p=points(e);assert(p[#p][5]==5 or p[#p-1][5]==5,'Warrior Charge not marked special movement')
end
do
 local e=newEnv('WARRIOR');anchor(e);e.cast(20252);e.sample(.25,25,0);e.sample(.25,26,0)
 assert(not hasBreak(e,8),'Warrior Intercept falsely uncertain')
end

-- A continuous-movement hint belongs to one action only. A small first movement
-- consumes it; an unrelated short relocation immediately afterwards must still cut.
do
 local e=newEnv('WARRIOR');anchor(e);e.cast(100);e.sample(.25,6,0)
 e.sample(.25,36,0);e.sample(.25,36,0)
 assert(hasBreak(e,8),'Charge hint leaked into a later unrelated relocation')
end

-- DRUID: Forever Feral Charge is a continuous leap; Dash/Travel are ordinary continuous speed.
do
 local e=newEnv('DRUID');anchor(e);e.cast(1238122);e.sample(.25,24,0);e.sample(.25,25,0)
 assert(not hasBreak(e,8),'Druid Feral Charge falsely uncertain')
 for i=1,20 do e.sample(.25,25+i*3,0) end
 assert(countBreak(e,8)==0,'Druid Dash-like run falsely cut')
end

-- MAGE: Blink and city/Dalaran teleports must cut, with semantic teleport evidence.
do
 local e=newEnv('MAGE');anchor(e);e.cast(1953);e.sample(.25,21,0);e.sample(.25,21,0)
 assert(hasBreak(e,3),'Mage Blink not recorded as teleport')
end
do
 local e=newEnv('MAGE');anchor(e);e.cast(1297659);e.sample(.25,500,500);e.sample(.25,500,500)
 assert(hasBreak(e,3),'Teleport: Dalaran not recorded as teleport')
 assert(#(e.db.heroPath.semanticEvents or {})>=1,'Dalaran semantic event missing')
end

-- SHAMAN: Astral Recall is a hearth-like semantic teleport.
do
 local e=newEnv('SHAMAN');anchor(e);e.cast(556);e.sample(.25,600,0);e.sample(.25,600,0)
 assert(hasBreak(e,3),'Astral Recall not teleport break')
 assert(eventsByCode(e,9)>=1,'Astral Recall hearth state missing')
end

-- ROGUE / HUNTER / PALADIN: speed buffs should not produce breaks.
for _,cls in ipairs({'ROGUE','HUNTER','PALADIN'}) do
 local e=newEnv(cls);anchor(e)
 for i=1,80 do e.sample(.25,1+i*4,math.sin(i/8)*2) end
 assert(countBreak(e,8)==0 and countBreak(e,3)==0,cls..' normal speed buff falsely cut')
end

-- PRIEST: remote camera/control does not move the player; no invented points/breaks.
do
 local e=newEnv('PRIEST');anchor(e);local before=#points(e)
 for i=1,40 do e.sample(.25,1,0) end
 assert(not hasBreak(e,8),'Priest stationary remote-view falsely cut')
 assert(#points(e)<=before+2,'Priest stationary generated excessive points')
end

-- WARLOCK / unknown scripted short relocation: no false straight line; continuity is explicitly uncertain.
do
 local e=newEnv('WARLOCK');anchor(e);e.sample(.25,36,0);e.sample(.25,36,0)
 assert(hasBreak(e,8),'Short unhinted summon/script relocation was drawn as continuous')
end

-- Boat/zeppelin/platform: sustained fast coherent world motion must stay continuous special movement.
do
 local e=newEnv('WARRIOR');anchor(e)
 e.sample(.25,21,0);e.sample(.25,41,0);e.sample(.25,61,0);e.sample(.25,81,0)
 assert(not hasBreak(e,8),'Sustained transport motion falsely cut')
 local ps=points(e);local special=0;for _,p in ipairs(ps) do if p[5]==5 then special=special+1 end end
 assert(special>=2,'Sustained transport motion not marked special')
end

-- One-frame short coordinate spike must be discarded, not create a break.
do
 local e=newEnv('WARRIOR');anchor(e);e.sample(.25,35,0);e.sample(.25,1.5,0);e.sample(.25,2,0)
 assert(not hasBreak(e,8),'One-frame short position spike produced break')
end

-- Taxi can move fast without teleport breaks.
do
 local e=newEnv('HUNTER');anchor(e);e.st.taxi=true;e.sample(.25,40,0);e.sample(.25,80,0);e.sample(.25,120,0)
 assert(not hasBreak(e,3) and not hasBreak(e,8),'Taxi falsely classified')
end

-- Swimming / mounted / vehicle/possession modes.
do
 local e=newEnv('DRUID');anchor(e);e.st.swimming=true;e.sample(.25,3,0);assert(points(e)[#points(e)][5]==2,'swim mode')
 e.st.swimming=false;e.st.mounted=true;e.sample(.25,6,0);assert(points(e)[#points(e)][5]==1,'mount mode')
 e.st.mounted=false;e.st.vehicle=true;e.sample(.25,10,0);assert(points(e)[#points(e)][5]==5,'vehicle mode')
end

-- Death -> ghost -> resurrection outside preserves explicit break/state.
do
 local e=newEnv('PRIEST');anchor(e);e.st.dead=true;e.listeners.PLAYER_DEAD();e.st.played=e.st.played+.25;e.st.now=e.st.now+.25;ticker=nil
 -- drive with sampler through API state changes
 e.sample(.25,1,0);e.st.dead=false;e.st.ghost=true;e.sample(.25,2,0);e.sample(.25,3,0)
 e.st.ghost=false;e.sample(.25,4,0);e.sample(.25,5,0)
 assert(#(e.db.heroPath.events or {})>=1,'death events absent')
end

-- Install inside unknown instance/BG: no exterior coordinates should be fabricated.
do
 local e=newEnv('MAGE');e.st.inside=true;e.st.itype='pvp';e.st.iname='Warsong Gulch';e.st.iid=489;e.sample(.25,100,100);e.sample(.25,110,100)
 assert(#points(e)==0,'BG/instance install leaked exterior points')
 local found=false;for _,ev in ipairs(e.db.heroPath.events or {}) do if ev[1]==1 then found=true end end;assert(found,'instance event missing')
end

-- Install/reload in odd live states: ghost and taxi must initialize without
-- inventing a normal walking state or a teleport.
do
 local e=newEnv('SHAMAN');e.st.ghost=true;e.sample(.25,10,10);e.sample(.25,11,10)
 local ps=points(e);assert(#ps>=1 and ps[#ps][5]==4,'install while ghost not classified ghost')
end
do
 local e=newEnv('HUNTER');e.st.taxi=true;e.sample(.25,10,10);e.sample(.25,40,10);e.sample(.25,70,10)
 assert(not hasBreak(e,3) and not hasBreak(e,8),'install while taxi produced false break')
end

print('CLASS_MOVEMENT_MATRIX=PASS')
