local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
local MODULE_CHUNK=assert(loadfile(MODULE))
local actions={'move','mount','taxi','death','release','resurrect','instance_in','instance_out','gap','reload','teleport','world'}
local failures,total=0,0
local function run(seq)
 local st={played=0,now=0,x=0,y=0,map=1,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,inside=false,itype='none',iname='I',iid=1}
 local lis,onload,sample={},nil,nil;local q={};local ns={}
 ns.Num=tonumber;ns.Call=function(n)if n=='UnitIsGhost'then return st.ghost elseif n=='UnitIsDeadOrGhost'then return st.dead or st.ghost elseif n=='UnitOnTaxi'then return st.taxi elseif n=='IsMounted'then return st.mounted elseif n=='IsSwimming'then return st.swimming end end
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
  local function flush()local g=0;while #q>0 do g=g+1;if g>5000 then error('queue')end;local a=q;q={};for _,f in ipairs(a)do f()end end end
  local function pulse()sample('ticker');flush()end
  pulse()
  for _,a in ipairs(seq)do
   st.played=st.played+0.25;st.now=st.now+0.25
   if a=='move' then if st.x then st.x=st.x+2 end
   elseif a=='mount' then st.mounted=not st.mounted
   elseif a=='taxi' then st.taxi=not st.taxi
   elseif a=='death' then lis.PLAYER_DEAD();st.dead=true
   elseif a=='release' then st.dead=false;st.ghost=true
   elseif a=='resurrect' then st.dead=false;st.ghost=false
   elseif a=='instance_in' then st.inside=true;st.itype='party';lis.PLAYER_ENTERING_WORLD();flush()
   elseif a=='instance_out' then st.inside=false;st.itype='none';lis.PLAYER_ENTERING_WORLD();flush()
   elseif a=='gap' then if st.x==nil then st.x=0;st.y=0 else st.x=nil;st.y=nil end
   elseif a=='reload' then lis.PLAYER_ENTERING_WORLD();flush()
   elseif a=='teleport' then if st.x then st.x=st.x+200 end
   elseif a=='world' then st.map=st.map==1 and 2 or 1 end
   pulse()
  end
  local H=db.heroPath;if type(H)~='table'or type(H.chunks)~='table'or type(H.tail)~='table'or type(H.events)~='table'then error('shape')end
  if H.lastPlayed~=st.played then error('lastPlayed')end
  local lastT,lastO=-math.huge,-math.huge
  local function chk(p)if p[1]<lastT or(p[1]==lastT and p[8]>0 and lastO>0 and p[8]<=lastO)then error('point order')end;lastT,lastO=p[1],p[8]end
  for _,ch in ipairs(H.chunks)do for i=1,math.floor(#ch/9)do local b=(i-1)*9;local p={};for j=1,9 do p[j]=ch[b+j]end;chk(p)end end
  for _,p in ipairs(H.tail)do chk(p)end
 end)
 if not ok then failures=failures+1;if failures<=10 then io.stderr:write(table.concat(seq,',')..': '..tostring(err)..'\n')end end
end
for a=1,#actions do for b=1,#actions do for c=1,#actions do for d=1,#actions do total=total+1;run({actions[a],actions[b],actions[c],actions[d]}) end end end end
print('SEQUENCES='..total);print('FAILURES='..failures);if failures>0 then os.exit(1)end;print('STATE_COMBINATIONS=PASS')
