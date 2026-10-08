local BOOT=(arg and arg[1]) or '../../Addon/HeroPath/Bootstrap.lua'
local CONTRACT=BOOT:gsub("Bootstrap.lua$","Contract.lua")
local now=100
_G.GetTime=function() return now end
_G.GetTimePreciseSec=function() return now end
local requests=0
local secretSentinel={}
_G.issecretvalue=function(v) return v==secretSentinel end
_G.RequestTimePlayed=function() requests=requests+1 end
_G.HeroPathDB='malformed-root'
_G.C_Map={GetBestMapForUnit=function() return 1 end,GetPlayerMapPosition=function() return {x=.5,y=.5} end,GetWorldPosFromMapPos=function() return 0,{x=100,y=200} end}
_G.UnitPosition=function() return 100,200,0,0 end
local eventScript,afterQ,frameObj
local events={};afterQ={}
_G.CreateFrame=function()
 local f={};frameObj=f;function f:RegisterEvent(e)events[e]=true end;function f:SetScript(kind,fn)if kind=='OnEvent'then eventScript=fn end end;return f
end
_G.C_Timer={After=function(delay,fn)afterQ[#afterQ+1]={delay=delay,fn=fn}end}
local ns={};assert(loadfile(CONTRACT))('HeroPath',ns);assert(loadfile(BOOT))('HeroPath',ns)
local loadedDB
ns.OnLoad(function(db)loadedDB=db end)
eventScript(nil,'ADDON_LOADED','HeroPath');eventScript(nil,'PLAYER_LOGIN')
assert(type(loadedDB)=='table','collector not initialized')
assert(type(loadedDB.recoveryRootQuarantine)=='table' and #loadedDB.recoveryRootQuarantine==1,'malformed SavedVariables root not quarantined')
assert(requests==1,'initial /played request missing')
for i=1,3 do local q=table.remove(afterQ,1);assert(q,'played retry timer missing');now=now+q.delay;q.fn() end
assert(requests>=4,'lost /played response did not trigger retries')
assert(ns.GetIntegrationHealth().playedRetryAttempts>=3,'retry diagnostics missing')
eventScript(nil,'TIME_PLAYED_MSG',1234,100)
assert(math.abs(ns.PlayedNow()-1234)<.001,'played anchor failed after retry')
eventScript(nil,'SAVED_VARIABLES_TOO_LARGE')
assert(ns.GetIntegrationHealth().savedVariablesTooLarge==1,'SavedVariables-too-large signal not recorded')
_G.IsMounted=function() error('synthetic API failure') end
assert(ns.Call('IsMounted')==nil,'throwing API did not fail closed')
assert(ns.GetIntegrationHealth().apiCallErrors==1,'API call failure diagnostic missing')
assert(tostring(ns.GetIntegrationHealth().lastApiCallError):find('IsMounted',1,true),'API failure source missing')
assert(ns.Num(math.huge)==nil and ns.Num(-math.huge)==nil and ns.Num(0/0)==nil,'non-finite external number was accepted')
assert(ns.SafeRead('nan-test',function()return 0/0 end)==nil,'NaN crossed SafeRead')
assert(ns.SafeRead('inf-test',function()return math.huge end)==nil,'Infinity crossed SafeRead')
assert(ns.Public(secretSentinel)==nil,'secret value crossed Public boundary')
assert(ns.SafeRead('secret-test',function() return secretSentinel end)==nil,'secret API return crossed SafeRead boundary')
assert(ns.Num(secretSentinel)==nil,'secret numeric value crossed conversion boundary')
-- A restricted client may throw while attempting to classify a returned value.
-- Such values must be dropped rather than implicitly treated as public.
local oldSecretChecker=_G.issecretvalue
_G.issecretvalue=function(v)
  if v==secretSentinel then error('restricted secret classifier') end
  return false
end
assert(ns.Public(secretSentinel)==nil,'failing secret classifier leaked a protected value')
assert(ns.SafeRead('restricted',function() return secretSentinel end)==nil,'SafeRead leaked an unclassifiable value')
_G.issecretvalue=oldSecretChecker
local originalRegister=frameObj.RegisterEvent
frameObj.RegisterEvent=function(self,e) if e=='SYNTHETIC_UNSUPPORTED_EVENT' then error('synthetic registration failure') end return originalRegister(self,e) end
assert(ns.Listen('SYNTHETIC_UNSUPPORTED_EVENT',function()end)==false,'unsupported event registration did not fail closed')
local ih=ns.GetIntegrationHealth()
assert(ih.eventRegistrationErrors>=1,'event registration failure diagnostic missing')
assert(tostring(ih.lastEventRegistrationError):find('SYNTHETIC_UNSUPPORTED_EVENT',1,true),'event registration failure source missing')
frameObj.RegisterEvent=originalRegister
assert(ns.Listen('SYNTHETIC_DISPATCH_ERROR',function() error('synthetic listener failure') end)==true,'synthetic listener registration failed')
local okDispatch=pcall(eventScript,nil,'SYNTHETIC_DISPATCH_ERROR')
assert(okDispatch,'listener exception escaped Bootstrap dispatch containment')
ih=ns.GetIntegrationHealth()
assert(ih.dispatchErrors>=1 and tostring(ih.lastDispatchError):find('synthetic listener failure',1,true),'dispatch failure diagnostic missing')
print('RELEASE_PLAYED_RETRY=PASS')
print('RELEASE_ROOT_RECOVERY=PASS')
print('RELEASE_SV_SIZE_SIGNAL=PASS')
print('RELEASE_API_EXCEPTION_CONTAINMENT=PASS')
print('RELEASE_NONFINITE_NUMBER_CONTAINMENT=PASS')
print('RELEASE_SECRET_VALUE_CONTAINMENT=PASS')
print('RELEASE_EVENT_REGISTRATION_DIAGNOSTICS=PASS')
print('RELEASE_DISPATCH_EXCEPTION_CONTAINMENT=PASS')
print('INTEGRATION_BOOTSTRAP=PASS')
