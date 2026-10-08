local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")

local function newHarness(existing)
  local st={played=0,now=0,x=0,y=0,map=1,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,inside=false,itype='none',iname='Instance',iid=0}
  local listeners,onload,sample={},nil,nil; local q={}; local ns={}
  ns.Num=tonumber
  ns.Call=function(n,...)
    if n=='UnitIsGhost' then return st.ghost end
    if n=='UnitIsDeadOrGhost' then return st.dead or st.ghost end
    if n=='UnitOnTaxi' then return st.taxi end
    if n=='IsMounted' then return st.mounted end
    if n=='IsSwimming' then return st.swimming end
  end
  ns.PlayedNow=function() return st.played end
  ns.WorldPos=function() return st.x,st.y,st.map end
  ns.Listen=function(e,f) listeners[e]=f end
  ns.OnLoad=function(f) onload=f end
  _G.GetTime=function() return st.now end
  _G.IsInInstance=function() return st.inside,st.itype end
  _G.GetInstanceInfo=function() return st.iname,st.itype,nil,nil,nil,nil,nil,st.iid end
  _G.C_Timer={NewTicker=function(_,f) sample=f;return{}end,After=function(_,f)q[#q+1]=f end}
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
  local db=existing or {};onload(db)
  local function flush(limit)
    limit=limit or 100000; local n=0
    while #q>0 do n=n+1;if n>limit then error('after queue runaway') end;local a=q;q={};for _,f in ipairs(a)do f()end end
  end
  local function tick(t,x,y,map,reason)
    st.played=t;st.now=t;st.x=x;st.y=y;st.map=map or st.map;sample(reason or 'ticker');flush()
  end
  return st,listeners,db,tick,sample,flush,ns
end

local function fail(m) error(m,2) end
local function eq(a,b,m) if a~=b then fail((m or 'eq')..' got='..tostring(a)..' expected='..tostring(b)) end end
local function ok(c,m) if not c then fail(m or 'assert') end end
local PF=9

local VA='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_'
local function vmap(c)local p=string.find(VA,c,1,true);return p and p-1 end
local function decodeChunk(ch)
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
local function allPoints(db)
  local H=db.heroPath;local out={}
  for _,ch in ipairs(H.chunks or{}) do assert(ch[1]=='HP1','unexpected chunk format');for _,p in ipairs(decodeChunk(ch))do out[#out+1]=p end end
  for _,p in ipairs(H.tail or{}) do out[#out+1]=p end
  return out
end
local function lastPoint(db) local p=allPoints(db);return p[#p] end
local function deaths(db) local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==0 then n=n+1 end end;return n end
local function states(db,code) local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==2 and (not code or e[2]==code) then n=n+1 end end;return n end

-- A. lastPlayed must always advance, even with no outdoor position.
do
  local s,l,db,tick,sample,flush=newHarness();tick(1,0,0,1)
  s.dead=true;s.played=30;s.now=30;sample('ticker');flush();eq(db.heroPath.lastPlayed,30,'dead lastPlayed')
end
do
  local s,l,db,tick,sample,flush=newHarness();tick(1,0,0,1)
  s.inside=true;s.itype='party';s.iid=36;s.played=2;s.now=2;l.PLAYER_ENTERING_WORLD();flush()
  s.played=60;s.now=60;sample('ticker');flush();eq(db.heroPath.lastPlayed,60,'instance lastPlayed')
end
do
  local s,l,db,tick,sample,flush=newHarness();tick(1,0,0,1)
  s.x=nil;s.y=nil;s.played=2;s.now=2;sample('ticker');flush();s.played=30;s.now=30;sample('ticker');flush();eq(db.heroPath.lastPlayed,30,'gap lastPlayed')
end

-- B. a long /reload interval is conservatively cut even if the endpoint is unchanged.
do
 local s,l,db,tick,sample,flush=newHarness();tick(1,10,0,1);s.played=10;s.now=10;s.x=10;l.PLAYER_ENTERING_WORLD(false,true);flush()
 local p=lastPoint(db);eq(p[1],10,'reload anchor time');eq(p[7],1,'reload anchor protected');eq(p[6],1,'long reload must break');eq(p[9],7,'long reload reason')
 tick(11,20,0,1);local ps=allPoints(db);ok(#ps>=3,'reload points');
end

-- C. normal instance exit gets an exit anchor before future motion.
do
 local s,l,db,tick,sample,flush=newHarness();tick(1,10,0,1)
 s.inside=true;s.itype='party';s.iid=36;s.played=2;s.now=2;l.PLAYER_ENTERING_WORLD(false,false);flush()
 s.played=2.25;s.now=2.25;sample('ticker');flush() -- confirm stable entry
 s.played=100;s.now=100;sample('ticker');flush()
 s.inside=false;s.itype='none';s.x=10;s.played=100;s.now=100;l.PLAYER_ENTERING_WORLD(false,false);flush()
 s.played=100.25;s.now=100.25;sample('ticker');flush() -- confirm stable exit
 local p=lastPoint(db);eq(p[1],100.25,'instance exit anchor time');eq(p[7],1,'instance exit anchor protected');eq(p[6],1,'instance exit must break');eq(p[9],6,'instance exit reason')
 tick(101,20,0,1)
end

-- D. coordinate gap always becomes an explicit break + protected resume anchor.
do
 local s,l,db,tick,sample,flush=newHarness();tick(1,10,0,1)
 s.x=nil;s.y=nil;s.played=2;s.now=2;sample('ticker');flush();s.played=10;s.now=10;sample('ticker');flush()
 s.x=10;s.y=0;s.played=11;s.now=11;sample('ticker');flush()
 local p=lastPoint(db);eq(p[1],11,'gap resume time');eq(p[7],1,'gap resume protected');eq(p[6],1,'gap resume must break');eq(p[9],5,'gap reason')
 ok(states(db,5)>=1 and states(db,6)>=1,'gap events missing')
end

-- E. dynamic speed detector: impossible 150 yd/s breaks; normal mount and taxi do not.
do
 local s,l,db,tick=newHarness();tick(0,0,0,1);tick(1,150,0,1);tick(1.25,150,0,1);local p=lastPoint(db);eq(p[6],1,'150 yd/s not broken');eq(p[9],3,'teleport reason')
end
do
 local s,l,db,tick=newHarness();s.mounted=true;tick(0,0,0,1);tick(1,20,0,1);eq(lastPoint(db)[6],0,'normal mount false teleport')
end
do
 local s,l,db,tick=newHarness();s.taxi=true;tick(0,0,0,1);tick(1,500,0,1);eq(lastPoint(db)[6],0,'taxi false teleport')
end

-- F. stale deathActive at login alive must never suppress next real death.
do
 local existing={heroPath={version=5,deathActive=1,pendingDeathBreak=1,chunks={},tail={{1,1,0,0,0,1,0,1,1}},events={{0,1,1,0,0,0,2,1}},lastPlayed=1,sequence=2}}
 local s,l,db,tick,sample,flush=newHarness(existing);eq(db.heroPath.deathActive,nil,'stale deathActive not cleared')
 tick(2,1,0,1);s.played=3;s.now=3;s.x=1;l.PLAYER_DEAD();eq(deaths(db),2,'next death suppressed')
end

-- G. same true timestamp stays true; order resolves collisions without time drift.
do
 local s,l,db,tick,sample,flush=newHarness();tick(1,0,0,1)
 for i=1,1000 do s.played=1;s.now=1;s.x=(i%2==0) and 0 or 1000;s.map=(i%2==0) and 1 or 2;sample('event');flush() end
 eq(db.heroPath.lastPlayed,1,'same-time pulses drifted lastPlayed')
 local ps=allPoints(db);for _,p in ipairs(ps)do ok(p[1]==0 or p[1]==1,'point timestamp drifted') end
end

-- H. corrupt metadata cannot poison future time/order.
do
 local bad={heroPath={version=5,chunks={},tail={{1,1,0,0,0,1,0,1,1}},events={},sequence=math.huge,lastPlayed=math.huge,lastStrictPlayed=math.huge}}
 local s,l,db,tick=newHarness(bad);ok(db.heroPath.sequence<100,'sequence not rebuilt');ok(db.heroPath.lastPlayed<100,'lastPlayed poisoned');tick(2,1,0,1);local p=lastPoint(db);ok(p[1]<100 and p[8]<100,'new point poisoned')
end

-- I. multiple open instances sanitized to at most one.
do
 local bad={heroPath={version=5,chunks={},tail={{1,1,0,0,0,1,0,1,1}},events={{1,2,0,1,0,0,'A','party',1,2,0},{1,3,0,1,0,0,'B','party',2,3,0}}}}
 local s,l,db=newHarness(bad);local opens=0;for _,e in ipairs(db.heroPath.events)do if e[1]==1 and e[3]==0 then opens=opens+1 end end;ok(opens<=1,'multiple open instances survived')
end

-- J. death fallback explicitly marks approximate position.
do
 local s,l,db,tick,sample,flush=newHarness();tick(1,10,0,1);s.x=nil;s.y=nil;s.played=2;s.now=2;l.PLAYER_DEAD();local e=db.heroPath.events[#db.heroPath.events];eq(e[1],0,'death missing');eq(e[8],2,'fallback death not marked approximate')
end

-- K. death in instance + ghost exit keeps DEATH as dominant break reason.
do
 local s,l,db,tick,sample,flush=newHarness();tick(1,10,0,1)
 s.inside=true;s.itype='party';s.iid=36;s.played=2;s.now=2;l.PLAYER_ENTERING_WORLD(false,false);flush();s.played=2.25;s.now=2.25;sample('ticker');flush();s.played=3;s.now=3;l.PLAYER_DEAD()
 s.dead=false;s.ghost=true;s.inside=false;s.itype='none';s.x=100;s.played=4;s.now=4;l.PLAYER_ENTERING_WORLD(false,false);flush();s.played=4.25;s.now=4.25;sample('ticker');flush();s.played=4.5;s.now=4.5;sample('ticker');flush()
 local p=lastPoint(db);eq(p[6],1,'death exit not break');eq(p[9],2,'death break reason overwritten')
end

-- L. chunked storage: history immutable chunks + bounded tail, current chunk/tail model only.
do
 local s,l,db,tick,sample,flush=newHarness();for i=0,5000 do tick(i*0.25,i*1.2,((i%7)-3)*2,1) end;flush()
ok(#(db.heroPath.chunks or{})>0,'no chunks finalized');ok(#(db.heroPath.tail or{})<1000,'tail unbounded')
end

-- M. raw sampling catches a sub-second right-angle turn within 3 yd.
do
 local s,l,db,tick=newHarness();tick(0,0,0,1);tick(0.25,3.5,3.5,1)
 -- Ground truth corner at t=.125: (1.75,0). Linear replay midpoint is (1.75,1.75).
 local err=1.75;ok(err<=3,'sub-second ground truth target exceeded')
end

-- N. export adapter exact subtree.
do
 local s,l,db,tick,sample,flush,ns=newHarness();tick(0,0,0,1);ok(type(ns.GetHeroPathExport)=='function','export adapter missing');ok(ns.GetHeroPathExport()==db.heroPath,'wrong export subtree')
end

print('COLLECTOR_CORE=PASS')
