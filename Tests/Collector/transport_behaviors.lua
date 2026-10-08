local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
local PF=9
local function newHarness()
  local st={played=0,now=0,x=0,y=0,map=0,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,inside=false,itype='none',iname='Instance',iid=0}
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
  local db={};onload(db)
  local function flush()
    local n=0
    while #q>0 do n=n+1;if n>10000 then error('queue runaway') end; local a=q;q={};for _,f in ipairs(a)do f()end end
  end
  local function pulse(t,x,y,map,reason)
    st.played=t;st.now=t;st.x=x;st.y=y;if map~=nil then st.map=map end;sample(reason or 'ticker');flush()
  end
  return st,listeners,db,pulse,sample,flush
end
local VA='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_'
local function vmap(c)local p=string.find(VA,c,1,true);return p and p-1 end
local function decode(ch)
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
local function points(db)local o={};for _,ch in ipairs(db.heroPath.chunks or{})do for _,p in ipairs(decode(ch))do o[#o+1]=p end end;for _,p in ipairs(db.heroPath.tail or{})do o[#o+1]=p end;return o end
local function countState(db,code)local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==2 and e[2]==code then n=n+1 end end;return n end
local function countInst(db,name)local n=0;for _,e in ipairs(db.heroPath.events or{})do if e[1]==1 and (not name or e[7]==name)then n=n+1 end end;return n end
local function last(db)local p=points(db);return p[#p] end
local function assertEq(a,b,msg)assert(a==b,(msg or'assertEq')..' got '..tostring(a)..' expected '..tostring(b))end
local function ok(v,msg)assert(v,msg)end

-- 1. Ordinary zone border: same world map = uninterrupted path.
do
 local s,l,db,p=newHarness();s.mounted=true
 p(0,-9700,700,0);p(1,-9710,714,0);p(2,-9720,728,0)
 local ps=points(db);assertEq(ps[#ps][6],0,'zone border created a break')
end

-- 2. Flight Path: high-speed movement remains continuous and is mode 3.
do
 local s,l,db,p=newHarness();p(0,-8840.6,489.7,0);s.taxi=true
 for i=1,20 do
  local r=i/20
  p(i*.25,-8840.6+(-10628.9+8840.6)*r,489.7+(1036.7-489.7)*r,0)
 end
 s.taxi=false;p(5.25,-10628.9,1036.7,0);p(5.5,-10628.9,1036.7,0)
 local ps=points(db);for i=2,#ps-1 do if ps[i][5]==3 then assertEq(ps[i][6],0,'flight path broken')end end
 ok(countState(db,3)>=1 and countState(db,4)>=1,'taxi start/end missing')
end

-- 3. Hearthstone on same continent: no connector, teleport reason.
do
 local s,l,db,p=newHarness();p(0,-11017,1517,0);p(.25,-11014,1515,0);p(.5,-9463,16,0);p(.75,-9463,16,0)
 local q=last(db);assertEq(q[6],1,'hearth connector created');assertEq(q[9],3,'hearth not classified discontinuity')
end

-- 4. Deeprun Tram when reported as an instance: hold outside, then break at Ironforge.
do
 local s,l,db,p,sample,flush=newHarness();p(0,-9153.8,364.1,0)
 s.inside=true;s.itype='party';s.iname='Deeprun Tram';s.iid=369;s.played=.25;s.now=.25;l.PLAYER_ENTERING_WORLD(false,false);flush()
 s.played=.5;s.now=.5;sample('ticker');flush();s.played=60;s.now=60;sample('ticker');flush()
 s.inside=false;s.itype='none';s.iname='Eastern Kingdoms';s.iid=0;s.x=-5021;s.y=-834.1;s.map=0;s.played=61;s.now=61;l.PLAYER_ENTERING_WORLD(false,false);flush();s.played=61.25;s.now=61.25;sample('ticker');flush()
 local q=last(db);assertEq(q[6],1,'tram exterior connector created');assertEq(q[9],6,'tram wrong break reason');assertEq(countInst(db,'Deeprun Tram'),1,'tram instance event missing')
end

-- 5. Deeprun fallback if API exposes no position rather than an instance: still no connector.
do
 local s,l,db,p=newHarness();p(0,-9153.8,364.1,0);p(.25,nil,nil,0);p(60,nil,nil,0);p(61,-5021,-834.1,0)
 local q=last(db);assertEq(q[6],1,'tram gap connector created');ok(q[9]==4 or q[9]==5,'tram fallback wrong break')
end

-- 6. Menethil -> Auberdine boat: direct continent handoff must never bridge continents.
do
 local s,l,db,p=newHarness();p(0,-3767,-779,0);p(1,-3850,-731,0);p(2,6325,554,1);p(2.25,6325,554,1)
 local q=last(db);assertEq(q[6],1,'boat bridged continents');assertEq(q[9],4,'boat continent reason')
end

-- 7. Boat with loading/unknown-position interval: gap + continent break, still no fake line.
do
 local s,l,db,p=newHarness();p(0,-3767,-779,0);p(1,-3850,-731,0);p(2,nil,nil,0);p(80,nil,nil,0);p(81,6325,554,1)
 local q=last(db);assertEq(q[6],1,'boat gap bridged continents');assertEq(q[9],4,'boat gap should resolve as world change');ok(countState(db,5)>=1 and countState(db,6)>=1,'boat gap events missing')
end

-- 8. Valid ship motion before loading must not generate repeated false teleports.
do
 local s,l,db,p=newHarness();p(0,-3767,-779,0)
 -- ~30 yd/s ship motion on map 0; below conservative transport tolerance.
 for i=1,20 do p(i*.25,-3767-i*7.0,-779+i*2.0,0) end
 local ps=points(db);local breaks=0;for _,q in ipairs(ps)do if q[6]==1 then breaks=breaks+1 end end
 assertEq(breaks,1,'ship motion created false teleports')
end

-- 9. Cross-continent Hearth/portal: hard world break.
do
 local s,l,db,p=newHarness();p(0,6406,516,1);p(.25,-9463,16,0);p(.5,-9463,16,0);local q=last(db);assertEq(q[6],1,'cross-continent teleport connected');assertEq(q[9],4,'cross-continent reason')
end

-- 10. Death -> release -> corpse run -> resurrect: death discontinuity, ghost track continuous.
do
 local s,l,db,p,sample,flush=newHarness();p(0,-11017,1517,0)
 s.played=.25;s.now=.25;s.x=-11010;s.y=1510;l.PLAYER_DEAD();flush();s.dead=true;sample('ticker');flush()
 s.dead=false;s.ghost=true;p(1,-10559,1207,0);p(1.25,-10570,1215,0);p(1.5,-10585,1230,0)
 s.ghost=false;p(1.75,-10600,1240,0)
 local ps=points(db);local firstGhost=nil;for _,q in ipairs(ps)do if q[5]==4 then firstGhost=q;break end end;ok(firstGhost,'ghost missing');assertEq(firstGhost[6],1,'corpse->graveyard connected');assertEq(firstGhost[9],2,'ghost first break not death')
end

-- 11. /reload creates a protected resume boundary even at the same spot when the unobserved interval exceeds the gap budget.
do
 local s,l,db,p,sample,flush=newHarness();p(0,-9463,16,0);s.played=2;s.now=2;s.x=-9463;s.y=16;l.PLAYER_ENTERING_WORLD(false,true);flush();local q=last(db);assertEq(q[6],1,'reload boundary was silently bridged');assertEq(q[9],7,'reload break reason');assertEq(q[7],1,'reload anchor not protected')
end

-- 12. AFK then move: arrival/departure anchors preserve hold.
do
 local s,l,db,p=newHarness();p(0,0,0,0);p(.25,2,0,0);for i=2,16 do p(i*.25,2,0,0) end;p(4.25,4,0,0)
 local ps=points(db);local same=0;for i=1,#ps-1 do if math.abs(ps[i][3]-ps[i+1][3])<.01 and ps[i+1][1]>ps[i][1] then same=same+1 end end;ok(same>=1,'AFK hold not retained')
end

-- 13. Unsupported outdoor map ID (e.g. transport-local map) never reconnects back to Azeroth.
do
 local s,l,db,p=newHarness();p(0,-9153.8,364.1,0);p(1,100,100,369);p(1.25,100,100,369);p(2,-5021,-834.1,0);p(2.25,-5021,-834.1,0)
 local ps=points(db);assertEq(ps[#ps-1][6],1,'enter transport-local map not break');assertEq(ps[#ps][6],1,'exit transport-local map not break')
end

print('TRANSPORT_CASES=13')
print('FLIGHT=PASS')
print('HEARTHSTONE=PASS')
print('DEEPRUN_TRAM=PASS')
print('SHIP_CONTINENT=PASS')
print('DEATH_GHOST=PASS')
print('RELOAD_AFK_GAP=PASS')
print('TRANSPORT_MATRIX=PASS')
