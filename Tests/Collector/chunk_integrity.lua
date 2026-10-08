local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub("HeroPath.lua$","Contract.lua")
local DATAMODEL=MODULE:gsub("HeroPath.lua$","DataModel.lua")
local METADATA=MODULE:gsub("HeroPath.lua$","Metadata.lua")
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
local st={played=0,now=0,x=0,y=0,map=0,ghost=false,dead=false,taxi=false,mounted=true,swimming=false,inside=false,itype='none',iname='Instance',iid=0}
local listeners,onload,sample={},nil,nil;local q={};local ns={}
ns.Num=tonumber
ns.Call=function(n)
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
  local guard=0
  while #q>0 do
    guard=guard+1;assert(guard<10000,'timer queue runaway')
    local a=q;q={};for _,f in ipairs(a)do f() end
  end
end
local function pulse()
  sample('ticker');flush()
end

-- Generate enough points for multiple immutable chunks. Vary the path so RDP
-- cannot collapse everything, and force meaningful transitions on both sides
-- of the first chunk boundary.
pulse()
for i=1,10000 do
  st.played=i*0.25;st.now=st.played
  local phase=i%11
  st.x=st.x + 2.15 + (phase==0 and 0.8 or 0)
  st.y=st.y + ((i%7)-3)*0.31
  if i==790 then st.x=st.x+120 end -- speed-based teleport inside first finalized chunk
  if i==805 then st.map=1 end      -- world transition near chunk boundary
  if i==820 then st.map=0 end
  if i==1710 then st.taxi=true end
  if i==1760 then st.taxi=false end
  pulse()
end
flush()

local H=assert(db.heroPath)
assert(type(H.chunks)=='table' and #H.chunks>=3,'expected >=3 finalized chunks')
assert(type(H.tail)=='table' and #H.tail<1000,'tail must remain bounded')

local decoded={};local declared=0
for ci,ch in ipairs(H.chunks) do
  assert(ch[1]=='HP1','chunk '..ci..' is not encoded')
  assert(type(ch[3])=='number' and ch[3]>0,'invalid declared point count')
  local ps=decodeChunk(ch)
  assert(#ps==ch[3],'decoded count mismatch in chunk '..ci)
  declared=declared+ch[3]
  -- Header metadata must agree with the actual payload.
  assert(math.abs(ps[1][1]-ch[4])<0.0011,'firstPlayed header mismatch')
  assert(math.abs(ps[#ps][1]-ch[5])<0.0011,'lastPlayed header mismatch')
  assert(ps[1][8]==ch[6],'firstOrder header mismatch')
  assert(ps[#ps][8]==ch[7],'lastOrder header mismatch')
  for _,p in ipairs(ps) do decoded[#decoded+1]=p end
end
for _,p in ipairs(H.tail) do decoded[#decoded+1]=p end
assert(#decoded==declared+#H.tail,'total point count mismatch')

local lastT,lastO=-math.huge,-math.huge
local teleportBreak,worldBreak,taxiPoint=false,false,false
for i,p in ipairs(decoded) do
  assert(type(p)=='table' and #p>=9,'bad decoded point '..i)
  assert(p[1]==p[1] and p[3]==p[3] and p[4]==p[4],'NaN point')
  assert(p[1]>=lastT,'non-monotonic played at '..i)
  if p[1]==lastT then assert(p[8]>lastO,'non-monotonic order at '..i) end
  assert(p[5]>=0 and p[5]<=4 and math.floor(p[5])==p[5],'invalid mode')
  assert(p[6]==0 or p[6]==1,'invalid break flag')
  assert(p[9]>=0 and p[9]<=7 and math.floor(p[9])==p[9],'invalid break reason')
  if p[6]==1 and p[9]==3 then teleportBreak=true end
  if p[6]==1 and p[9]==4 then worldBreak=true end
  if p[5]==3 then taxiPoint=true end
  lastT,lastO=p[1],p[8]
end
assert(teleportBreak,'forced teleport break was lost during compression/encoding')
assert(worldBreak,'world-change break near chunk boundary was lost')
assert(taxiPoint,'taxi mode points were lost')

-- Ensure chunk immutability: after adding more data, already-finalized payloads
-- must stay byte-for-byte identical.
local old={}
for i,ch in ipairs(H.chunks) do old[i]=ch[2] end
for i=10001,12000 do
  st.played=i*0.25;st.now=st.played
  st.x=st.x+2.2;st.y=st.y+((i%5)-2)*0.25
  pulse()
end
flush()
for i,payload in ipairs(old) do assert(H.chunks[i] and H.chunks[i][2]==payload,'historical chunk mutated '..i) end

print('CHUNKS='..#H.chunks)
print('TAIL='..#H.tail)
print('DECODED_INITIAL='..#decoded)
print('TELEPORT_BREAK=PASS')
print('WORLD_BREAK=PASS')
print('IMMUTABILITY=PASS')
print('CHUNK_INTEGRITY=PASS')
