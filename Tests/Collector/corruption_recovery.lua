local MODULE=(arg and arg[1])or'../../Addon/HeroPath/HeroPath.lua';local CHUNK=assert(loadfile(MODULE));math.randomseed(560660)
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
local CASES=20000;local fail=0
local weird={nil,'x',math.huge,-math.huge,0/0,-1,0,1,1.5,99999999999999999}
local function pick()return weird[math.random(1,#weird)]end
for c=1,CASES do
 local st={played=2,now=2,x=1,y=1,map=1};local listeners,onload,sample={},nil,nil;local q={};local ns={Num=tonumber}
 ns.Call=function(n)if n=='UnitIsGhost'or n=='UnitIsDeadOrGhost'or n=='UnitOnTaxi'or n=='IsMounted'or n=='IsSwimming'then return false end end
 ns.PlayedNow=function()return st.played end;ns.WorldPos=function()return st.x,st.y,st.map end;ns.Listen=function(e,f)listeners[e]=f end;ns.OnLoad=function(f)onload=f end
 _G.GetTime=function()return st.now end;_G.IsInInstance=function()return false,'none'end;_G.GetInstanceInfo=function()return'I','none',nil,nil,nil,nil,nil,0 end
 _G.C_Timer={NewTicker=function(_,f)sample=f;return{}end,After=function(_,f)q[#q+1]=f end}
 local H={schema=1,sequence=pick(),lastPlayed=pick(),lastStrictPlayed=pick(),tail={},chunks={},events={}}
 for i=1,math.random(0,6)do H.tail[#H.tail+1]=(math.random()<.5)and pick()or{pick(),pick(),pick(),pick(),pick(),pick(),pick(),pick(),pick()}end
 for i=1,math.random(0,8)do local k=math.random(0,2);if k==0 then H.events[#H.events+1]={0,pick(),pick(),pick(),pick(),pick(),pick(),pick()}elseif k==1 then H.events[#H.events+1]={1,pick(),pick(),pick(),pick(),pick(),'I','party',pick(),pick(),pick()}else H.events[#H.events+1]={2,pick(),pick(),pick(),pick(),pick(),pick()}end end
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
  assert(loadfile(CONTRACT))('HeroPath',ns);assert(loadfile(DATAMODEL))('HeroPath',ns);assert(loadfile(METADATA))('HeroPath',ns);CHUNK('HeroPath',ns);local db={heroPath=H};onload(db)
  while #q>0 do local a=q;q={};for _,f in ipairs(a)do f()end end
  sample('ticker');while #q>0 do local a=q;q={};for _,f in ipairs(a)do f()end end
  local X=db.heroPath
  if type(X.chunks)~='table'or type(X.tail)~='table'or type(X.events)~='table'then error('shape')end
  if type(X.sequence)~='number'or X.sequence~=X.sequence or X.sequence==math.huge or X.sequence==-math.huge then error('sequence poison')end
  if type(X.lastPlayed)~='number'or X.lastPlayed~=X.lastPlayed or X.lastPlayed==math.huge or X.lastPlayed==-math.huge then error('time poison')end
  local opens=0;for _,e in ipairs(X.events)do if e[1]==1 and e[3]==0 then opens=opens+1 end end;if opens>1 then error('multiple opens')end
 end)
 if not ok then fail=fail+1;if fail<=5 then io.stderr:write('case '..c..' '..tostring(err)..'\n')end end
end
print('CASES='..CASES);print('FAILURES='..fail);if fail>0 then os.exit(1)end;print('CORRUPTION_RECOVERY=PASS')
