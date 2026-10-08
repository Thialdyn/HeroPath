local MODULE=(arg and arg[1]) or '../../Addon/HeroPath/HeroPath.lua'
local CONTRACT=MODULE:gsub('HeroPath.lua$','Contract.lua')
local DATAMODEL=MODULE:gsub('HeroPath.lua$','DataModel.lua')
local METADATA=MODULE:gsub('HeroPath.lua$','Metadata.lua')

local function harness(initial)
  initial=initial or {}
  local st={played=0,now=0,x=0,y=0,map=1,ghost=false,dead=false,taxi=false,mounted=false,swimming=false,inside=false,itype='none',iname='Instance',iid=0}
  for k,v in pairs(initial) do st[k]=v end
  local listeners,onload,ticker={},nil,nil; local q={}; local ns={}; local worldCalls=0
  ns.Num=tonumber
  ns.Call=function(n,...)
    if n=='UnitIsGhost' then return st.ghost end
    if n=='UnitIsDeadOrGhost' then return st.dead or st.ghost end
    if n=='UnitOnTaxi' then return st.taxi end
    if n=='IsMounted' then return st.mounted end
    if n=='IsSwimming' then return st.swimming end
    if n=='IsFlying' then return false end
    if n=='UnitInVehicle' or n=='UnitHasVehicleUI' or n=='UnitIsPossessed' then return false end
    if n=='UnitClass' then return 'Warrior','WARRIOR' end
    if n=='UnitFactionGroup' then return 'Alliance' end
  end
  ns.PlayedNow=function() return st.played end
  ns.WorldPos=function() worldCalls=worldCalls+1; return st.x,st.y,st.map end
  ns.Listen=function(e,f) listeners[e]=f end
  ns.OnLoad=function(f) onload=f end
  _G.GetTime=function() return st.now end
  _G.debugprofilestop=function() return os.clock()*1000 end
  _G.IsInInstance=function() return st.inside,st.itype end
  _G.GetInstanceInfo=function() return st.iname,st.itype,nil,nil,nil,nil,nil,st.iid end
  _G.C_Timer={NewTicker=function(_,f) ticker=f; return {} end,After=function(_,f) q[#q+1]=f end}
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
  assert(loadfile(CONTRACT))('HeroPath',ns)
  assert(loadfile(DATAMODEL))('HeroPath',ns)
  assert(loadfile(METADATA))('HeroPath',ns)
  assert(loadfile(MODULE))('HeroPath',ns)
  local db={}; onload(db)
  local function flush()
    local guard=0
    while #q>0 do
      guard=guard+1; assert(guard<10000,'timer queue runaway')
      local a=q;q={};for _,f in ipairs(a)do f() end
    end
  end
  local function tick(t,x,y)
    st.played=t;st.now=t;st.x=x;st.y=y;ticker('ticker');flush()
  end
  local function allPoints()
    local out={}
    for _,ch in ipairs(db.heroPath.chunks or {}) do
      local pts=assert(ns.DecodeHeroPathChunk(ch),'decode failed')
      for _,p in ipairs(pts) do out[#out+1]=p end
    end
    for _,p in ipairs(db.heroPath.tail or {}) do out[#out+1]=p end
    table.sort(out,function(a,b) if a[1]==b[1] then return (a[8] or 0)<(b[8] or 0) end return a[1]<b[1] end)
    return out
  end
  return st,listeners,db,tick,flush,allPoints,function() return worldCalls end,ns
end

local function pointSegmentDistance(px,py,ax,ay,bx,by)
  local vx,vy=bx-ax,by-ay
  local wx,wy=px-ax,py-ay
  local vv=vx*vx+vy*vy
  if vv<=1e-12 then local dx,dy=px-ax,py-ay;return math.sqrt(dx*dx+dy*dy) end
  local t=(wx*vx+wy*vy)/vv
  if t<0 then t=0 elseif t>1 then t=1 end
  local qx,qy=ax+t*vx,ay+t*vy
  local dx,dy=px-qx,py-qy
  return math.sqrt(dx*dx+dy*dy)
end

local function polylineError(px,py,pts)
  local best=math.huge
  for i=1,#pts-1 do
    if pts[i][2]==pts[i+1][2] and pts[i+1][6]~=1 then
      local d=pointSegmentDistance(px,py,pts[i][3],pts[i][4],pts[i+1][3],pts[i+1][4])
      if d<best then best=d end
    end
  end
  return best
end

-- 1. 4 Hz observation is retained, but straight-line persistence is sparse.
do
  local s,l,db,tick,flush,points,calls,ns=harness()
  for i=0,80 do tick(i*.25,i*1.75,0) end
  local pts=points()
  assert(calls()==81,'adaptive store changed 4 Hz world observation cadence')
  assert(#pts<40,'straight travel was not sparsified: '..#pts)
  assert(#pts>=20,'straight travel was over-sparsified: '..#pts)
  local h=ns.GetCollectorHealth()
  assert((h.storeDistance or 0)>0 and (h.storeSkipped or 0)>0,'adaptive store diagnostics missing')
  assert(db.heroPath.adaptiveSampling==1,'adaptive store metadata missing')
end

-- 2. A tight loop must remain round enough after clean-save compaction; this is the
-- regression for the "square around a tree" failure mode.
do
  local s,l,db,tick,flush,points,calls,ns=harness()
  local radius=6.0
  local observed={}
  for i=0,24 do
    local a=(2*math.pi*i)/24
    local x,y=radius*math.cos(a),radius*math.sin(a)
    observed[#observed+1]={x,y}
    tick(i*.25,x,y)
  end
  assert(l.PLAYER_LOGOUT,'logout handler missing')
  l.PLAYER_LOGOUT();flush()
  local pts=points()
  assert(#pts>=12,'tight loop lost too much curvature after compaction: '..#pts)
  local worst=0
  for _,o in ipairs(observed) do
    local d=polylineError(o[1],o[2],pts)
    if d>worst then worst=d end
  end
  assert(worst<=0.65,string.format('tight-loop polyline error too high: %.3f yd',worst))
  local h=ns.GetCollectorHealth()
  assert((h.storeCorner or 0)>0,'tight loop did not trigger curvature-aware storage')
end

-- 3. Swimming and ghost straight travel must not explode point density. They keep
-- the same 4 Hz observation stream but use mode-specific persistence spacing.
for _,case in ipairs({
  {name='swim',initial={swimming=true},step=1.20,mode=2},
  {name='ghost',initial={ghost=true},step=1.40,mode=4},
}) do
  local s,l,db,tick,flush,points,calls=harness(case.initial)
  for i=0,24 do tick(i*.25,i*case.step,0) end
  local pts=points()
  assert(calls()==25,case.name..' changed observation cadence')
  assert(#pts<=12,case.name..' straight movement stored too many points: '..#pts)
  assert(pts[#pts][5]==case.mode,case.name..' mode was not retained')
end

-- 4. A movement-mode change is always materialized immediately even when the
-- geometric distance threshold has not been reached.
do
  local s,l,db,tick,flush,points=harness()
  tick(0,0,0);tick(.25,1,0)
  s.mounted=true;tick(.50,1.2,0)
  local pts=points()
  assert(pts[#pts][5]==1,'mounted mode transition was skipped by adaptive store')
end


-- 5. A smaller, slower loop is the worst common "circle an object" case: per-tick
-- movement can stay below the persistence floor, so accumulated geometry still has
-- to retain enough vertices once the player has moved meaningfully.
do
  local s,l,db,tick,flush,points,calls,ns=harness()
  local radius=2.5
  local observed={}
  for i=0,48 do
    local a=(2*math.pi*i)/48
    local x,y=radius*math.cos(a),radius*math.sin(a)
    observed[#observed+1]={x,y}
    tick(i*.25,x,y)
  end
  l.PLAYER_LOGOUT();flush()
  local pts=points()
  assert(calls()==49,'small-loop changed observation cadence')
  assert(#pts>=8,'small slow loop collapsed to a coarse polygon: '..#pts)
  local worst=0
  for _,o in ipairs(observed) do
    local d=polylineError(o[1],o[2],pts)
    if d>worst then worst=d end
  end
  assert(worst<=0.45,string.format('small-loop polyline error too high: %.3f yd',worst))
end

-- 6. Sub-yard stationary coordinate jitter must not be mistaken for meaningful
-- curvature. This protects storage from exploding while the character is idle.
do
  local s,l,db,tick,flush,points,calls=harness()
  local pattern={{.45,.00},{.00,.45},{-.45,.00},{.00,-.45}}
  for i=0,120 do
    local p=pattern[(i%#pattern)+1]
    tick(i*.25,p[1],p[2])
  end
  local pts=points()
  assert(calls()==121,'jitter case changed observation cadence')
  assert(#pts<=4,'stationary jitter exploded storage density: '..#pts)
end



-- 7. The actual middle observation must be stored for a right-angle turn. Keeping
-- the post-turn observation instead shifts the corner diagonally and was the root
-- cause of visibly squared/offset local loops.
do
  local s,l,db,tick,flush,points=harness()
  tick(0.00,0,0)
  tick(0.25,2,0) -- below ordinary 4 yd foot spacing: candidate corner only
  tick(0.50,2,2) -- confirms a 90-degree turn at t=.25
  local pts=points()
  local found=false
  for _,p in ipairs(pts) do
    if math.abs(p[1]-.25)<.001 and math.abs(p[3]-2)<.11 and math.abs(p[4])<.11 then found=true break end
  end
  assert(found,'adaptive corner stored the post-turn point instead of the true corner observation')
end

-- 8. Adaptive sampling may skip the last observation during normal play, but a
-- clean save must preserve the exact trusted endpoint. This costs at most one
-- protected point per session/reload and prevents replay ending early.
do
  local s,l,db,tick,flush,points=harness()
  tick(0.00,0,0)
  tick(0.25,1,0) -- intentionally below normal foot persistence spacing
  assert(points()[#points()][1] < .25,'test endpoint was unexpectedly persisted before logout')
  l.PLAYER_LOGOUT();flush()
  local pts=points();local last=pts[#pts]
  assert(last and math.abs(last[1]-.25)<.001 and math.abs(last[3]-1)<.11,'clean save lost the last trusted adaptive observation')
end


-- 9. Storage efficiency guard: 10 minutes at 4 Hz on a straight path must not
-- become 2,401 permanent points. Adaptive persistence keeps the live tail bounded,
-- and clean-save RDP/keyframes reduce the final straight history to a few dozen
-- points while preserving the exact terminal observation.
for _,case in ipairs({
  {name='foot',initial={},step=1.75},
  {name='swim',initial={swimming=true},step=1.20},
  {name='ghost',initial={ghost=true},step=1.40},
}) do
  local s,l,db,tick,flush,points,calls=harness(case.initial)
  for i=0,2400 do tick(i*.25,i*case.step,0) end
  local before=#points()
  assert(calls()==2401,case.name..' efficiency case changed 4 Hz observation cadence')
  assert(before<1000,case.name..' adaptive live persistence became unbounded: '..before)
  l.PLAYER_LOGOUT();flush()
  local after=#points()
  assert(after<=40,case.name..' straight clean-save history stayed too dense: '..after)
  local last=points()[#points()]
  assert(last and math.abs(last[1]-600)<.001,'straight clean-save terminal time lost for '..case.name)
end

print('ADAPTIVE_GEOMETRY_4HZ_OBSERVE=PASS')
print('ADAPTIVE_GEOMETRY_STRAIGHT_SPARSE=PASS')
print('ADAPTIVE_GEOMETRY_TIGHT_LOOP_PRESERVED=PASS')
print('ADAPTIVE_GEOMETRY_SWIM_GHOST_BOUNDED=PASS')
print('ADAPTIVE_GEOMETRY_MODE_CHANGE=PASS')
print('ADAPTIVE_GEOMETRY_SMALL_LOOP=PASS')
print('ADAPTIVE_GEOMETRY_JITTER_BOUNDED=PASS')
print('ADAPTIVE_GEOMETRY_TRUE_CORNER=PASS')
print('ADAPTIVE_GEOMETRY_TERMINAL_ENDPOINT=PASS')
print('ADAPTIVE_GEOMETRY_LONG_STRAIGHT_EFFICIENCY=PASS')
print('ADAPTIVE_GEOMETRY_SAMPLING=PASS')
