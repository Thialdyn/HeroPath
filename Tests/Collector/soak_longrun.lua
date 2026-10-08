local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
local TICKS=500000
local st={played=0,now=0,x=0,y=0,map=1,ghost=false,dead=false,taxi=false,mounted=true,swimming=false,inside=false,itype='none',iname='I',iid=1}
local lis,onload,sample={},nil,nil;local q={};local ns={}
ns.Num=tonumber;ns.Call=function(n)if n=='UnitIsGhost'then return st.ghost elseif n=='UnitIsDeadOrGhost'then return st.dead or st.ghost elseif n=='UnitOnTaxi'then return st.taxi elseif n=='IsMounted'then return st.mounted elseif n=='IsSwimming'then return st.swimming end end
ns.PlayedNow=function()return st.played end;ns.WorldPos=function()return st.x,st.y,st.map end;ns.Listen=function(e,f)lis[e]=f end;ns.OnLoad=function(f)onload=f end
_G.GetTime=function()return st.now end;_G.IsInInstance=function()return st.inside,st.itype end;_G.GetInstanceInfo=function()return st.iname,st.itype,nil,nil,nil,nil,nil,st.iid end
local maxCallback=0
local function timed(f)local a=os.clock();f();local d=os.clock()-a;if d>maxCallback then maxCallback=d end end
_G.C_Timer={NewTicker=function(_,f)sample=f;return{}end,After=function(_,f)q[#q+1]=f end}
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
assert(loadfile(CONTRACT))('HeroPath',ns);assert(loadfile(DATAMODEL))('HeroPath',ns);assert(loadfile(METADATA))('HeroPath',ns);assert(loadfile(MODULE))('HeroPath',ns);local db={};onload(db)
local function flush()while #q>0 do local a=q;q={};for _,f in ipairs(a)do timed(f)end end end
for i=0,TICKS do
 st.played=i*0.25;st.now=st.played;st.x=i*1.0;st.y=(i%2==0) and 0 or 7 -- adversarial zigzag, intentionally hard to compress
 timed(function()sample('ticker')end);flush()
end
flush()
local H=db.heroPath;local stored=0
for _,ch in ipairs(H.chunks or{})do assert(ch[1]=='HP1','unexpected chunk format');stored=stored+(ch[3]or 0)end;stored=stored+#(H.tail or{})
collectgarbage('collect')
print('TICKS='..(TICKS+1));print('STORED_POINTS='..stored);print('CHUNKS='..#(H.chunks or{}));print('TAIL='..#(H.tail or{}));print('COMPACTIONS='..tostring(H.compactions or 0));print(string.format('MAX_CALLBACK_MS=%.3f',maxCallback*1000));print(string.format('LUA_MEMORY_KB=%.1f',collectgarbage('count')))
if #(H.tail or{})>=1000 then error('tail unbounded')end
if maxCallback>0.050 then error('maintenance callback exceeded 50ms in diagnostic runtime')end
if H.lastPlayed~=st.played then error('lastPlayed')end
print('SOAK_LONGRUN=PASS')
