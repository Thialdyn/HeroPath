local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
local st={played=0,now=0,x=100,y=100,map=1,guid=nil,name='TestCharacter',realm='TestRealm'}
local listeners,onload,ticker={},nil,nil;local q={};local ns={EnableResumePrime=true,EnableCollectorWatchdog=false,RequireWorldEntryBeforeSampling=true}
ns.Num=tonumber
ns.Call=function(n)
 if n=='UnitGUID' then return st.guid end
 if n=='UnitFullName' then return st.name,st.realm end
 if n=='UnitName' then return st.name end
 if n=='GetNormalizedRealmName' or n=='GetRealmName' then return st.realm end
 if n=='UnitClass' then return 'Warrior','WARRIOR' end
 if n=='UnitFactionGroup' then return 'Alliance' end
 if n=='UnitIsGhost' or n=='UnitIsDeadOrGhost' or n=='UnitOnTaxi' or n=='IsMounted' or n=='IsSwimming' or n=='UnitInVehicle' or n=='UnitHasVehicleUI' or n=='UnitIsPossessed' then return false end
end
ns.PlayedNow=function()return st.played end
ns.WorldPos=function()return st.x,st.y,st.map,'dual' end
ns.Listen=function(e,f)listeners[e]=f end
ns.OnLoad=function(f)onload=f end
_G.GetTime=function()return st.now end
_G.IsInInstance=function()return false,'none' end
_G.GetInstanceInfo=function()return 'World','none',nil,nil,nil,nil,nil,nil,0 end
_G.C_Timer={NewTicker=function(_,f)ticker=f;return{Cancel=function()end}end,After=function(_,f)q[#q+1]=f end}
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
assert(db.heroPath.ownerKey=='name:TestCharacter@TestRealm','expected startup name identity')
st.guid='Player-123-ABC'
listeners.PLAYER_ENTERING_WORLD(true,false)
local guard=0;while #q>0 do guard=guard+1;assert(guard<100);table.remove(q,1)() end
assert(db.heroPath.ownerKey=='guid:Player-123-ABC','name identity not upgraded to GUID in place')
local n=0;for _ in pairs(db.heroPathInactiveProfiles or{})do n=n+1 end
assert(n==0,'same character was forked into inactive profile')
assert(ns.GetCollectorHealth().worldSuspended==false,'collector stayed suspended after GUID upgrade')
print('CHARACTER_IDENTITY_NAME_TO_GUID=PASS')
