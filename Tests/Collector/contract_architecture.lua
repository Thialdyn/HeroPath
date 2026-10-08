local CONTRACT='../../Addon/HeroPath/Contract.lua'
local MODEL='../../Addon/HeroPath/DataModel.lua'
local METADATA='../../Addon/HeroPath/Metadata.lua'
local ENGINE='../../Addon/HeroPath/HeroPath.lua'
local TOC='../../Addon/HeroPath/HeroPath.toc'
local ADDON='../../Addon/HeroPath/'

local function readAll(path)
    local f=assert(io.open(path,'rb')); local data=f:read('*a'); f:close(); return data
end

-- Every shipped Lua module must parse independently. This catches distribution drift,
-- truncated copies and TOC/source mismatches before runtime.
for _,name in ipairs({'Contract.lua','DataModel.lua','Bootstrap.lua','Metadata.lua','HeroPath.lua','API.lua','Diagnostics.lua'}) do
    local chunk,err=loadfile(ADDON..name)
    assert(chunk,('Lua syntax error in %s: %s'):format(name,tostring(err)))
end

-- Pure data code must remain detached from WoW runtime APIs and SavedVariables globals.
local modelSource=readAll(MODEL)
for _,forbidden in ipairs({'CreateFrame','C_Timer','C_Map','UnitPosition','GetTime','HeroPathDB'}) do
    assert(not modelSource:find(forbidden,1,true),'pure DataModel leaked runtime dependency: '..forbidden)
end

local ns={}
assert(loadfile(CONTRACT))('HeroPath',ns)
assert(type(ns.Contract)=='table','contract missing')
local C=ns.Contract
assert(C.PRODUCT=="Hero’sPath",'product identity')
assert(C.AUTHOR=='Darwyn','author identity')
assert(C.VERSION=='1.0.0','product version')
assert(C.PUBLIC_API_VERSION==1,'public API version')
assert(C.SAVED_VARIABLES_SCHEMA==1,'schema contract')
assert(C.Compatibility.FUTURE_SCHEMA_READ_ONLY==true,'future schema policy')
assert(C.Sampling.SAMPLE_SECONDS==0.25,'sampling contract')
assert(C.Integration.SOURCE_AGREE_YARDS==6,'integration contract')
assert(C.Integration.DEEPRUN_TRAM_INSTANCE_ID==369,'transport identity contract')
assert(C.Sampling.ANCHOR_POSITION_EPSILON_YARDS==0.25,'anchor tolerance contract')
assert(C.Sampling.CORNER_MIN_LEG_YARDS==0.45,'corner min leg contract')
assert(C.Sampling.MIN_MOVE_YARDS==1.0,'minimum persisted movement contract')
assert(C.Sampling.CORNER_STORE_MIN_YARDS==1.0,'corner store distance contract')
assert(C.Sampling.STORE_DISTANCE_YARDS[0]==4.0 and C.Sampling.STORE_DISTANCE_YARDS[3]==20.0,'adaptive store spacing contract')
assert(C.Compression.PRESERVE_CURVATURE==true,'curvature preservation contract')
assert(C.SemanticHints.CONTINUOUS_TTL_SECONDS==2,'continuous hint ttl contract')
assert(C.Break.UNCERTAIN==8,'break enum contract')
assert(C.State.TRANSPORT_UNKNOWN==14,'state enum contract')
assert(C.SemanticHints.TELEPORT_SPELL_IDS[1297659]==true,'Forever teleport semantic hint')
assert(C.Transition.Cause.HEARTH==1 and C.Transition.Confidence.SEMANTIC_CONFIRMED==2,'transition contract')
assert(C.Context.TRANSITION_ARRIVAL==7,'context contract')

assert(loadfile(MODEL))('HeroPath',ns)
assert(type(ns.DataModel)=='table','data model missing')
local p={12.345,0,100.1,-200.2,1,1,1,7,3}
assert(ns.DataModel.PointValid(p),'point contract rejected valid tuple')
local ch=assert(ns.DataModel.EncodeChunk({p}))
assert(ns.DataModel.EncodedChunkValid(ch),'encoded chunk invalid')
local out=assert(ns.DataModel.DecodeChunk(ch))
assert(#out==1 and out[1][8]==7 and out[1][9]==3,'codec roundtrip')

assert(loadfile(METADATA))('HeroPath',ns)
assert(type(ns.Metadata)=='table','metadata module missing')
assert(ns.Metadata.DetectFutureSchema({schema=15})==15,'future schema detection')

local toc=readAll(TOC)
local positions={}
for _,name in ipairs({'Contract.lua','DataModel.lua','Bootstrap.lua','Metadata.lua','HeroPath.lua','API.lua','Diagnostics.lua'}) do
    positions[name]=assert(toc:find(name,1,true),name..' missing from TOC')
end
assert(positions['Contract.lua']<positions['DataModel.lua'] and positions['DataModel.lua']<positions['Bootstrap.lua'] and
       positions['Bootstrap.lua']<positions['Metadata.lua'] and positions['Metadata.lua']<positions['HeroPath.lua'] and
       positions['HeroPath.lua']<positions['API.lua'] and positions['API.lua']<positions['Diagnostics.lua'],'runtime load order')
assert(toc:find('## Interface: 120100, 120105, 16001',1,true),'supported interface declaration')
assert(toc:find("## Title: Hero’sPath",1,true),'TOC title')
assert(toc:find('## Author: Darwyn',1,true),'TOC author')
assert(toc:find('## Version: 1.0.0',1,true),'TOC version')
assert(toc:find('## X-HeroPath-Schema: 1',1,true),'TOC schema metadata')
assert(toc:find('## X-HeroPath-API: 1',1,true),'TOC API metadata')
assert(toc:find('## SavedVariablesPerCharacter: HeroPathDB',1,true),'SavedVariables identity')

local bootstrapSource=readAll(ADDON..'Bootstrap.lua')
assert(not bootstrapSource:find('xy >= yx + 3',1,true) and not bootstrapSource:find('yx >= xy + 3',1,true),'calibration vote margin leaked into Bootstrap')
assert(bootstrapSource:find('function ns.SafeRead',1,true),'central SafeRead API boundary missing')
assert(bootstrapSource:find('function ns.Public',1,true),'public/secret value boundary missing')
assert(bootstrapSource:find('issecretvalue',1,true),'secret-value handling missing')
assert(bootstrapSource:find('apiCallErrors',1,true),'API boundary diagnostics missing')

local metadataSource=readAll(METADATA)
assert(metadataSource:find('DetectFutureSchema',1,true),'future-schema policy leaked out of metadata layer')
assert(metadataSource:find('BuildTransitionEndpoint',1,true),'correlated transition ownership missing')
assert(metadataSource:find('AddContextSnapshot',1,true),'map-context ownership missing')
assert(not metadataSource:find('C_Map',1,true) and not metadataSource:find('UnitPosition',1,true),'metadata bypasses Bootstrap API boundary')

local engine=readAll(ENGINE)
assert(engine:find('assert(ns.Contract',1,true),'engine does not fail fast on missing contract')
assert(engine:find('assert(ns.DataModel',1,true),'engine does not fail fast on missing data model')
assert(engine:find('ns.Metadata',1,true),'engine does not use metadata boundary')
assert(not engine:find('local FORMAT_VERSION = 1',1,true),'schema magic number leaked back into engine')
assert(not engine:find('local SAMPLE_SECONDS = 0.25',1,true),'sampling magic number leaked back into engine')
for _,literal in ipairs({'ttl=2','maxYards=45','ratio<0.20','cos<0.35','instanceID)==369','compressionFailureStreak<=3','C_Timer.After(1','breakReason=true,8'}) do
    assert(not engine:find(literal,1,true),'decision magic number leaked back into engine: '..literal)
end

local apiSource=readAll(ADDON..'API.lua')
assert(apiSource:find('_G.HeroPathAPI = API',1,true),'public API export missing')
assert(not apiSource:find('HeroPathDB',1,true),'public API must not expose SavedVariables internals')

print('CONTRACT_ARCHITECTURE=PASS')
