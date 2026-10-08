local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
local PLAYERS=2000
local STEPS=420
local PF=9
local MODULE_CHUNK=assert(loadfile(MODULE))
math.randomseed(560056)


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
local totals={ticks=0,points=0,events=0,fail=0,terminal=0}

local function points(db)
 local out={};local H=db.heroPath
 for _,ch in ipairs(H.chunks or{})do assert(ch[1]=='HP1','unexpected chunk format');for _,p in ipairs(decodeChunk(ch))do out[#out+1]=p end end
 for _,p in ipairs(H.tail or{})do out[#out+1]=p end
 return out
end

local function run(id)
 local st={played=0,now=0,x=0,y=0,map=1,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,inside=false,itype='none',iname='Instance',iid=0}
 local lis,onload,sample={},nil,nil;local q={};local ns={}
 ns.Num=tonumber;ns.Call=function(n)
  if n=='UnitIsGhost'then return st.ghost end;if n=='UnitIsDeadOrGhost'then return st.dead or st.ghost end;if n=='UnitOnTaxi'then return st.taxi end;if n=='IsMounted'then return st.mounted end;if n=='IsSwimming'then return st.swimming end
 end
 ns.PlayedNow=function()return st.played end;ns.WorldPos=function()return st.x,st.y,st.map end;ns.Listen=function(e,f)lis[e]=f end;ns.OnLoad=function(f)onload=f end
 _G.GetTime=function()return st.now end;_G.IsInInstance=function()return st.inside,st.itype end;_G.GetInstanceInfo=function()return st.iname,st.itype,nil,nil,nil,nil,nil,st.iid end
 _G.C_Timer={NewTicker=function(_,f)sample=f;return{}end,After=function(_,f)q[#q+1]=f end}
 local ok,err=pcall(function()
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
  assert(loadfile(CONTRACT))('HeroPath',ns);assert(loadfile(DATAMODEL))('HeroPath',ns);assert(loadfile(METADATA))('HeroPath',ns);MODULE_CHUNK('HeroPath',ns);local db={};onload(db)
  local function flush()local g=0;while #q>0 do g=g+1;if g>10000 then error('queue')end;local a=q;q={};for _,f in ipairs(a)do f()end end end
  local function pulse(reason)sample(reason or'ticker');flush();totals.ticks=totals.ticks+1 end
  pulse()
  for step=1,STEPS do
   st.played=st.played+0.25;st.now=st.now+0.25
   local r=math.random()
   if not st.dead and not st.ghost and not st.inside then
    if r<0.006 then st.mounted=not st.mounted
    elseif r<0.010 then st.swimming=not st.swimming
    elseif r<0.014 then st.taxi=not st.taxi
    elseif r<0.018 then lis.PLAYER_ENTERING_WORLD();flush()
    elseif r<0.022 then lis.PLAYER_DEAD();st.dead=true
    elseif r<0.026 then st.inside=true;st.itype='party';st.iid=(id%100)+1;lis.PLAYER_ENTERING_WORLD();flush()
    elseif r<0.030 then st.x=st.x+120 -- should normally trigger speed-based teleport
    elseif r<0.034 then st.map=st.map==1 and 2 or 1
    elseif r<0.038 then st.x=nil;st.y=nil
    end
   elseif st.dead then
    if r<0.25 then st.dead=false;st.ghost=true end
   elseif st.ghost then
    if r<0.10 then st.ghost=false end
   elseif st.inside then
    if r<0.08 then st.inside=false;st.itype='none';st.x=(st.x or 0)+math.random()*5;st.y=st.y or 0;lis.PLAYER_ENTERING_WORLD();flush()
    elseif r<0.10 then lis.PLAYER_DEAD();st.dead=true end
   end
   if st.x==nil and r<0.25 then st.x=id%10;st.y=0 end
   if st.x~=nil and not st.inside and not st.dead then
    local speed=st.taxi and 80 or(st.mounted and 14 or(st.swimming and 5 or 7))
    st.x=st.x+speed*0.25*(0.75+math.random()*0.5);st.y=st.y+(math.random()-0.5)*2
   end
   pulse()
  end
  -- deliberately leave 75% of players in unresolved states to verify timeline truth
  local terminal=id%4
  if terminal==1 then st.dead=true;st.ghost=false
  elseif terminal==2 then st.inside=true;st.itype='party';st.iid=999
  elseif terminal==3 then st.x=nil;st.y=nil end
  for k=1,20 do st.played=st.played+0.25;st.now=st.now+0.25;pulse() end
  if math.abs((db.heroPath.lastPlayed or-1)-st.played)>0.001 then error('lastPlayed terminal mismatch '..tostring(db.heroPath.lastPlayed)..' '..st.played) end
  local ps=points(db);local lt=-math.huge;local lo=-math.huge
  for _,p in ipairs(ps)do
   if p[1]<lt or(p[1]==lt and p[8]>0 and lo>0 and p[8]<=lo)then error('point ordering')end
   if p[8]~=p[8] or p[1]~=p[1] then error('nan')end
   lt,lo=p[1],p[8]
  end
  if #db.heroPath.tail>=1000 then error('tail bound')end
  totals.points=totals.points+#ps;totals.events=totals.events+#(db.heroPath.events or{});totals.terminal=totals.terminal+1
 end)
 if not ok then totals.fail=totals.fail+1;if totals.fail<=8 then io.stderr:write('player '..id..': '..tostring(err)..'\n')end end
end

for i=1,PLAYERS do run(i) end
print('PLAYERS='..PLAYERS);print('TICKS='..totals.ticks);print('POINTS='..totals.points);print('EVENTS='..totals.events);print('TERMINAL_CHECKS='..totals.terminal);print('FAILURES='..totals.fail)
if totals.fail>0 then os.exit(1)end
print('STRESS_PROFILES_2000=PASS')
