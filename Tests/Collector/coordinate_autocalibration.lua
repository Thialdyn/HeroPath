local BOOT=(arg and arg[1]) or '../../Addon/HeroPath/Bootstrap.lua'
local CONTRACT=BOOT:gsub("Bootstrap.lua$","Contract.lua")

local function makeFrame()
  local f={}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
CreateFrame=function() return makeFrame() end
GetTime=function() return 100 end
GetTimePreciseSec=function() return 100 end
RequestTimePlayed=function() end

local x,y,inst=-8912.50,-115.63,0
C_Map={
 GetBestMapForUnit=function() return 84 end,
 GetPlayerMapPosition=function() return {x=.5,y=.5} end,
 GetWorldPosFromMapPos=function() return inst,{x=x,y=y} end,
}

local function loadBootstrap(unitFn)
 UnitPosition=unitFn
 local ns={}
 assert(loadfile(CONTRACT))('HeroPath',ns);assert(loadfile(BOOT))('HeroPath',ns)
 return ns
end

-- Retail-like XY raw order.
do
 local ns=loadBootstrap(function() return x,y,0,inst end)
 for i=1,5 do
  local ax,ay,ai,src=ns.WorldPos(); assert(src=='dual'); assert(math.abs(ax-x)<.001 and math.abs(ay-y)<.001 and ai==inst)
 end
 local d=ns.GetIntegrationHealth(); assert(d.unitOrder=='XY', 'expected XY lock, got '..tostring(d.unitOrder)); assert(d.calibrationVotesXY>=4); assert(d.sourceMismatch==0)
 print('PASS retail XY calibration')
end

-- Forever/documentation-like YX raw order.
do
 local ns=loadBootstrap(function() return y,x,0,inst end)
 for i=1,5 do
  local ax,ay,ai,src=ns.WorldPos(); assert(src=='dual'); assert(math.abs(ax-x)<.001 and math.abs(ay-y)<.001 and ai==inst)
 end
 local d=ns.GetIntegrationHealth(); assert(d.unitOrder=='YX', 'expected YX lock, got '..tostring(d.unitOrder)); assert(d.calibrationVotesYX>=4); assert(d.sourceMismatch==0)
 print('PASS forever YX calibration')
end

-- Ambiguous point near X==Y: keep C_Map, do not guess an order.
do
 x,y=100,100
 local ns=loadBootstrap(function() return 100,100,0,inst end)
 for i=1,8 do local ax,ay,ai,src=ns.WorldPos(); assert(src=='cmap'); assert(ax==100 and ay==100) end
 local d=ns.GetIntegrationHealth(); assert(d.unitOrder==nil); assert(d.calibrationAmbiguous>=8); assert(d.sourceMismatch==0)
 print('PASS ambiguous safe C_Map fallback')
end

-- Recover from a client/API axis-order change: fail closed briefly, reset, then relearn.
do
 x,y=-5000,250
 local rawOrder='XY'
 local ns=loadBootstrap(function() if rawOrder=='XY' then return x,y,0,inst else return y,x,0,inst end end)
 for i=1,5 do assert(select(4,ns.WorldPos())=='dual') end
 assert(ns.GetIntegrationHealth().unitOrder=='XY')
 rawOrder='YX'
 for i=1,3 do assert(select(4,ns.WorldPos())=='mismatch') end
 for i=1,5 do assert(select(4,ns.WorldPos())=='dual') end
 local d=ns.GetIntegrationHealth(); assert(d.unitOrder=='YX'); assert(d.calibrationResets>=1)
 print('PASS contradiction reset and YX relearn')
end

print('AUTOCAL ALL PASS')
