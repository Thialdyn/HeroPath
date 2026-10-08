local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
local st={played=0,now=0,x=0,y=0,map=1,ghost=false,dead=false,taxi=false,mounted=true,swimming=false,inside=false,itype='none',iname='Instance',iid=0}
local listeners,onload,ticker={},nil,nil;local q={};local ns={}
ns.Num=tonumber
ns.Call=function(n)
 if n=='UnitIsGhost' then return st.ghost end
 if n=='UnitIsDeadOrGhost' then return st.dead or st.ghost end
 if n=='UnitOnTaxi' then return st.taxi end
 if n=='IsMounted' then return st.mounted end
 if n=='IsSwimming' then return st.swimming end
end
ns.PlayedNow=function()return st.played end
ns.WorldPos=function()return st.x,st.y,st.map end
ns.Listen=function(e,f)listeners[e]=f end
ns.OnLoad=function(f)onload=f end
_G.GetTime=function()return st.now end
_G.debugprofilestop=function()return os.clock()*1000 end
_G.IsInInstance=function()return st.inside,st.itype end
_G.GetInstanceInfo=function()return st.iname,st.itype,nil,nil,nil,nil,nil,st.iid end
_G.C_Timer={NewTicker=function(_,f)ticker=f;return{}end,After=function(delay,f)q[#q+1]={delay=delay,cb=f} end}
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
 limit=limit or 100000;local n=0
 while #q>0 do n=n+1;assert(n<=limit,'timer queue runaway');local item=table.remove(q,1);item.cb() end
end
local function tick(i)
 st.played=i*.25;st.now=st.played;st.x=i*1.1;st.y=(i%5==0)and 2 or 0;ticker('ticker');flush()
end
for i=0,5000 do tick(i) end
local H=db.heroPath
assert(H.schema==1,'schema 1 metadata missing')
assert(H.storagePolicy=='HP1-sparse-delta-varint+RDP-3yd+curvature-preserve+20s-keyframes','HP1 storage policy missing')
assert(#H.chunks>=1,'expected live-compacted chunks')
for i,ch in ipairs(H.chunks) do
 assert(ch[1]=='HP1','new chunk '..i..' is not HP1')
 local pts=assert(ns.DecodeHeroPathChunk(ch),'HP1 decoder rejected own chunk')
 assert(#pts==ch[3],'decoded HP1 count mismatch')
end
local stats=assert(ns.GetStorageStats())
assert(stats.encodedPayloadBytes>0 and stats.packedPoints>0,'storage stats missing')
local health=assert(ns.GetCollectorHealth())
assert(health.compressionSlices>0,'time-sliced compression did not run')
assert(health.compressionMaxSliceMs>=0,'compression profiler missing')
local tailBefore=#H.tail
assert(tailBefore>0,'test expected a raw tail before clean save')
assert(listeners.PLAYER_LOGOUT,'logout handler missing')
listeners.PLAYER_LOGOUT();flush()
assert(#H.tail==0,'clean logout did not compact raw tail')
assert(#H.chunks>=2,'clean logout did not create final chunk')
local lastChunk=H.chunks[#H.chunks]
assert(lastChunk[1]=='HP1','logout chunk is not HP1')
local lastDecoded=assert(ns.DecodeHeroPathChunk(lastChunk))
assert(#lastDecoded==lastChunk[3],'logout HP1 decode mismatch')
assert(math.abs(lastDecoded[#lastDecoded][1]-H.lastPlayed)<0.0011,'last played lost during logout compaction')
print('STORAGE_COMPACTION_HP1_STORAGE=PASS')
print('STORAGE_COMPACTION_SLICED_COMPACTION=PASS')
print('STORAGE_COMPACTION_CLEAN_SAVE_COMPACTION=PASS')
print('REGRESSION_STORAGE_COMPACTION=PASS')
