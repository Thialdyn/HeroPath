-- Hero’sPath 1.0.0 collector (SavedVariables schema 1).
--
-- The storage model retains TRUE /played time separate from total ordering, an explicit unknown/special movement mode,
-- and records instance/death events even when no trustworthy exterior anchor exists.
-- Point tuple (9 fields):
--   { played, worldInstanceID, worldX, worldY, movementMode, breakBefore,
--     protectedAnchor, order, breakReason }
--
-- Storage is chunked:
--   heroPath.chunks = { packedChunk, ... }  -- immutable compressed chunks
--   heroPath.tail   = { pointTuple, ... }   -- bounded mutable raw tail
-- Chunks use the HP1 sparse delta-varint format plus verified metadata. The codec stores only
-- fields that actually change between normal points while preserving 0.1 yd coordinates,
-- 1 ms /played timestamps, global ordering, mode, protected anchors and break reasons.
-- Finalized chunks are immutable.
--
-- Event tuples:
--   death:    { 0, played, mapID, X, Y, insideInstance, order, accuracy }
--   instance: { 1, startPlayed, endPlayed, entryMapID, entryX, entryY,
--               name, instanceType, instanceID, startOrder, endOrder, anchorKnown }
--             anchorKnown: 1 = exterior anchor is trustworthy, 0 = no exterior anchor available.
--   state:    { 2, stateCode, played, order, mapID, X, Y, positionKnown }
--
-- death accuracy: 1 exact world position, 2 last-known outdoor position,
--                 3 instance entrance anchor, 4 position unknown.
--
-- movementMode: 0 foot, 1 mounted, 2 swimming, 3 taxi, 4 ghost,
--               5 unknown/special world movement (e.g. an unclassified moving transport).
-- breakReason: 0 none, 1 initial, 2 death, 3 teleport, 4 world change,
--              5 coordinates unavailable, 6 instance exit, 7 resume mismatch,
--              8 continuity uncertain (rapid unexplained short relocation).

local ADDON_NAME, ns = ...
local RawCall, RawNum = ns.Call, ns.Num

-- Every game/API access is contained here. A single transient API failure must
-- degrade the current observation to "unknown", never abort the collector.
local function Call(name, ...)
    if type(RawCall) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(RawCall, name, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h
end

local function Num(value)
    local fn = type(RawNum) == "function" and RawNum or tonumber
    local ok, number = pcall(fn, value)
    if not ok then return nil end
    return number
end

local C = assert(ns.Contract, "HeroPath Contract.lua must load before HeroPath.lua")
local L, S, Z, H, I = C.Limits, C.Sampling, C.Compression, C.SemanticHints, C.Integration
local E, ST, BR, DA = C.Event, C.State, C.Break, C.DeathAccuracy

local FORMAT_VERSION = C.SAVED_VARIABLES_SCHEMA
local MAX_MOVEMENT_MODE = L.MAX_MOVEMENT_MODE
local MAX_ORDER = L.MAX_ORDER
local MAX_PLAYED_SECONDS = L.MAX_PLAYED_SECONDS
local STORED_LAST_PLAYED_AHEAD_TOLERANCE = L.STORED_LAST_PLAYED_AHEAD_TOLERANCE
local RECOVERY_SCHEMA_VERSION = C.RECOVERY_SCHEMA_VERSION
local MAX_WORLD_COORD_ABS = L.MAX_WORLD_COORD_ABS
local MAX_WORLD_ID = L.MAX_WORLD_ID

-- Collection policy is defined centrally in Contract.lua. These aliases keep the
-- state-machine code compact while making every threshold discoverable in one place.
local SAMPLE_SECONDS = S.SAMPLE_SECONDS
local SAMPLE_FAST_SECONDS = S.SAMPLE_FAST_SECONDS
local SAMPLE_MOVING_SECONDS = S.SAMPLE_MOVING_SECONDS
local SAMPLE_IDLE_SECONDS = S.SAMPLE_IDLE_SECONDS
local PLAYED_BACKSTEP_TOLERANCE = S.PLAYED_BACKSTEP_TOLERANCE
local PLAYED_FORWARD_SLACK_SECONDS = S.PLAYED_FORWARD_SLACK_SECONDS
local POSITION_MISSING_CONFIRM_SAMPLES = S.POSITION_MISSING_CONFIRM_SAMPLES
local STATE_CHANGE_CONFIRM_SAMPLES = S.STATE_CHANGE_CONFIRM_SAMPLES
local MIN_MOVE_YARDS = S.MIN_MOVE_YARDS
local RAW_IDLE_YARDS = S.RAW_IDLE_YARDS
local IDLE_HOLD_SECONDS = S.IDLE_HOLD_SECONDS
local SAMPLE_GAP_SECONDS = S.SAMPLE_GAP_SECONDS
local RESUME_CONTINUITY_YARDS = S.RESUME_CONTINUITY_YARDS
local POSITION_RETRY_SECONDS = S.POSITION_RETRY_SECONDS
local WORLD_EVENT_RETRIES = S.WORLD_EVENT_RETRIES
local TELEPORT_MARGIN_YARDS = S.TELEPORT_MARGIN_YARDS
local MAX_SPEED_YARDS_PER_SECOND = S.MAX_SPEED_YARDS_PER_SECOND
local SPECIAL_MOVEMENT_SPEED_YARDS_PER_SECOND = S.SPECIAL_MOVEMENT_SPEED_YARDS_PER_SECOND

local RDP_EPSILON_YARDS = Z.RDP_EPSILON_YARDS
local RDP_KEYFRAME_SECONDS = Z.RDP_KEYFRAME_SECONDS
local RAW_CHUNK_POINTS = Z.RAW_CHUNK_POINTS
local RAW_TAIL_TRIGGER = Z.RAW_TAIL_TRIGGER

local EVENT_DEATH, EVENT_INSTANCE, EVENT_STATE = E.DEATH, E.INSTANCE, E.STATE
local STATE_RELEASE, STATE_RESURRECT = ST.RELEASE, ST.RESURRECT
local STATE_TAXI_START, STATE_TAXI_END = ST.TAXI_START, ST.TAXI_END
local STATE_GAP_START, STATE_GAP_END = ST.GAP_START, ST.GAP_END
local STATE_WORLD_TRANSITION, STATE_TELEPORT, STATE_HEARTH = ST.WORLD_TRANSITION, ST.TELEPORT, ST.HEARTH
local STATE_TRAM_START, STATE_TRAM_END = ST.TRAM_START, ST.TRAM_END
local STATE_BOAT, STATE_ZEPPELIN, STATE_TRANSPORT_UNKNOWN = ST.BOAT, ST.ZEPPELIN, ST.TRANSPORT_UNKNOWN
local MIN_STATE_CODE, MAX_STATE_CODE = ST.RELEASE, ST.TRANSPORT_UNKNOWN

local BREAK_NONE, BREAK_INITIAL, BREAK_DEATH = BR.NONE, BR.INITIAL, BR.DEATH
local BREAK_TELEPORT, BREAK_WORLD, BREAK_UNAVAILABLE = BR.TELEPORT, BR.WORLD, BR.UNAVAILABLE
local BREAK_INSTANCE_EXIT, BREAK_RESUME, BREAK_UNCERTAIN = BR.INSTANCE_EXIT, BR.RESUME, BR.UNCERTAIN
local MAX_BREAK_REASON = BR.UNCERTAIN

local DEATH_POS_EXACT, DEATH_POS_LAST_KNOWN = DA.EXACT, DA.LAST_KNOWN
local DEATH_POS_INSTANCE_ANCHOR, DEATH_POS_UNKNOWN = DA.INSTANCE_ANCHOR, DA.UNKNOWN

local RuntimeState = {
    TELEPORT_MIN_GENERIC_YARDS = S.TELEPORT_MIN_GENERIC_YARDS,
    SEMANTIC_TELEPORT_MIN_YARDS = S.SEMANTIC_TELEPORT_MIN_YARDS,
    SHORT_RELOCATION_MIN_YARDS = S.SHORT_RELOCATION_MIN_YARDS,
    SHORT_RELOCATION_MARGIN_YARDS = S.SHORT_RELOCATION_MARGIN_YARDS,
    RESUME_PRIME_CONFIRM_SAMPLES = S.RESUME_PRIME_CONFIRM_SAMPLES,
    RESUME_PRIME_STABLE_YARDS = S.RESUME_PRIME_STABLE_YARDS,
    RESUME_PRIME_MOTION_SAMPLES = S.RESUME_PRIME_MOTION_SAMPLES,
    WATCHDOG_SECONDS = S.WATCHDOG_SECONDS,
    WATCHDOG_STALE_SECONDS = S.WATCHDOG_STALE_SECONDS,
    COMPRESSION_WORK_PER_SLICE = Z.WORK_PER_SLICE,
    COMPRESSION_SLICE_SECONDS = Z.SLICE_SECONDS,
    compressionJob = nil,
    compressionSlices = 0,
    compressionLastSliceMs = 0,
    compressionMaxSliceMs = 0,
    sampleProfileCount = 0,
    sampleProfileTotalMs = 0,
    sampleProfileLastMs = 0,
    sampleProfileMaxMs = 0,
    resumePrimeRequired = false,
    resumePrimeCandidate = nil,
    worldSuspended = false,
    collectorFaultPending = false,
    collectorFaultAnchor = nil,
    collectorFaultStartPlayed = nil,
    tickerGeneration = 0,
    watchdogTicker = nil,
    lastTickerBeat = nil,
    sampleAttempts = 0,
    sampleSuccesses = 0,
    sampleErrors = 0,
    lastSampleError = nil,
    storeDistance = 0,
    storeCorner = 0,
    storeInterval = 0,
    storeMode = 0,
    storeSkipped = 0,
    lastObservedPlayed = nil,
    lastObservedMapID = nil,
    lastObservedX = nil,
    lastObservedY = nil,
    lastObservedMode = nil,
    sessionContextRecorded = false,
    SEMANTIC_HEARTH = C.Semantic.HEARTH,
    SEMANTIC_TELEPORT_SPELL = C.Semantic.TELEPORT_SPELL,
    TELEPORT_SPELL_IDS = H.TELEPORT_SPELL_IDS,
    CONTINUOUS_MOVEMENT_SPELL_IDS = H.CONTINUOUS_MOVEMENT_SPELL_IDS,
    pendingContinuousHint = nil,
    archiveReadOnly = false,
    archiveSchema = nil,
    archiveReason = nil,
}

local db
local lastRaw
local idleStartRaw
local resumeAnchor
local resumeReason
local forceResumeAnchor = false
local currentInstanceEventIndex
local ticker
local forceBreakAfterDeath = false
local lastLifeState
local lastTaxi
local positionGapOpen = false
local compressionScheduled = false
local worldPulseGeneration = 0
local positionMissingCount = 0
local positionMissingStartPlayed = nil
local positionMissingAnchor = nil
local pendingDiscontinuity = nil
local playedUnavailable = false
local playedUnavailableStart = nil
local playedUnavailableAnchor = nil
local instanceStableSignature = nil
local instanceCandidateSignature = nil
local instanceCandidateCount = 0
local instanceUnknownCount = 0
local instanceUnknownStartPlayed = nil
local instanceUnknownAnchor = nil
local taxiCandidate = nil
local taxiCandidateCount = 0
local lifeCandidate = nil
local lifeCandidateCount = 0
local firstWorldEvent = true
local playedReferenceStamp = nil
local playedReferenceNow = nil
local pendingTransportHint = nil
local pendingTramExit = false
local AddPoint, PreserveTerminalObservation

local HEARTHSTONE_SPELL_IDS = H.HEARTHSTONE_SPELL_IDS
local SEMANTIC_HINT_DIRECT_SECONDS = H.DIRECT_SECONDS
local SEMANTIC_HINT_DESTINATION_SECONDS = H.DESTINATION_SECONDS

-- STATE_BOAT / STATE_ZEPPELIN are reserved for explicit imported semantics.
-- Current collection never infers them from terminal proximity.
-- Raw world positions are the source of truth. A future offline/site analysis may cluster
-- repeated trajectories and attach a route label without mutating the recorded journey.



local D = assert(ns.DataModel, "HeroPath DataModel.lua must load before HeroPath.lua")
assert(ns.Metadata, "HeroPath Metadata.lua must load before HeroPath.lua")
local IsFinite, ValidWorldCoordinates = D.IsFinite, D.ValidWorldCoordinates
local FiniteNonNegative, ValidPlayed, SafeInt = D.FiniteNonNegative, D.ValidPlayed, D.SafeInt
local RoundNearestInt, RoundTenth, TrueStamp, DistanceXY = D.RoundNearestInt, D.RoundTenth, D.TrueStamp, D.DistanceXY
local PointValid, NormalizePoint = D.PointValid, D.NormalizePoint
local EncodeChunk, EncodedChunkValid = D.EncodeChunk, D.EncodedChunkValid

local function IsTramInstance(name,instanceID)
    local safeID=SafeInt(Num(instanceID),0,MAX_WORLD_ID)
    if safeID==I.DEEPRUN_TRAM_INSTANCE_ID then return true end
    if type(name)~="string" then return false end
    local ok,n=pcall(string.lower,name)
    if not ok or type(n)~="string" then return false end
    return n:find("tram",1,true)~=nil or n:find("deeprun",1,true)~=nil
end

local function Hero()
    return db and db.heroPath or nil
end

local function SafeNow()
    local v = Num(Call("GetTime"))
    if not FiniteNonNegative(v) then return 0 end
    return tonumber(v)
end

local function ReadPlayedNow()
    local H = Hero()
    if type(ns.PlayedNow) ~= "function" then return nil,"unavailable" end
    local ok,v = pcall(ns.PlayedNow)
    if not ok then return nil,"error" end
    local stamp = TrueStamp(Num(v))
    if not stamp then return nil,"invalid" end
    local old = H and ValidPlayed(H.lastPlayed) and tonumber(H.lastPlayed) or nil
    if old and stamp + PLAYED_BACKSTEP_TOLERANCE < old then return nil,"regressed" end
    if old and stamp < old then stamp = old end

    local status=nil
    local now=SafeNow()
    if playedReferenceStamp and playedReferenceNow and stamp>playedReferenceStamp and now>=playedReferenceNow then
        local playedDelta=stamp-playedReferenceStamp
        local clockDelta=now-playedReferenceNow
        if playedDelta>clockDelta+PLAYED_FORWARD_SLACK_SECONDS then status="forward-discontinuity" end
    end
    if not playedReferenceStamp or stamp~=playedReferenceStamp then
        playedReferenceStamp=stamp;playedReferenceNow=now
    end
    return stamp,status
end

local function MarkPlayedUnavailable()
    if playedUnavailable then return end
    local H = Hero()
    playedUnavailable = true
    playedUnavailableStart = H and ValidPlayed(H.lastPlayed) and tonumber(H.lastPlayed) or nil
    playedUnavailableAnchor = lastRaw or resumeAnchor
end

local function TouchLastPlayed(played)
    local H = Hero()
    local stamp = TrueStamp(played)
    if not H or not stamp then return stamp end
    local old = FiniteNonNegative(H.lastPlayed) and tonumber(H.lastPlayed) or 0
    if stamp > old then H.lastPlayed = stamp end
    return stamp
end

local function NextOrder()
    local H = Hero()
    if not H then return 0 end
    local seq = SafeInt(H.sequence, 0, MAX_ORDER) or 0
    if seq >= MAX_ORDER then
        -- SavedVariables should never approach JS's integer precision bound, but
        -- rebuilding from history is safer than allowing non-total ordering.
        seq = 0
    end
    seq = seq + 1
    H.sequence = seq
    return seq
end

RuntimeState.DecodeChunk = D.DecodeChunk
RuntimeState.DeepValidateChunk = D.DeepValidateChunk

-- Recovery helpers intentionally live on RuntimeState rather than as top-level locals: the WoW Lua 5.1
-- chunk-local limit is tight, and recovery must not make the runtime un-loadable.
-- ===== Recovery / persisted-history reconstruction =====
function RuntimeState.NumericEntries(value)
    local out = {}
    if type(value) ~= "table" then return out, false end
    for k,v in pairs(value) do
        if type(k)=="number" and k>=1 and math.floor(k)==k then out[#out+1]={k,v} end
    end
    table.sort(out,function(a,b) return a[1]<b[1] end)
    local expected,holes=1,false
    for i=1,#out do
        if out[i][1]~=expected then holes=true end
        expected=out[i][1]+1
    end
    return out,holes
end

function RuntimeState.RecoveryCopy(value, depth, seen)
    depth=depth or 0
    if depth>4 then return "<depth-limit>" end
    local t=type(value)
    if t=="nil" or t=="number" or t=="boolean" or t=="string" then return value end
    if t~="table" then return "<"..t..">" end
    seen=seen or {}
    if seen[value] then return "<cycle>" end
    seen[value]=true
    local copy={}
    for k,v in pairs(value) do
        local kt=type(k)
        if kt=="number" or kt=="string" then copy[k]=RuntimeState.RecoveryCopy(v,depth+1,seen) end
    end
    seen[value]=nil
    return copy
end

function RuntimeState.Quarantine(H, kind, reason, payload, details)
    if type(H)~="table" then return end
    local box=type(H.recoveryQuarantine)=="table" and H.recoveryQuarantine or {}
    H.recoveryQuarantine=box
    box.schema=RECOVERY_SCHEMA_VERSION
    box.entries=type(box.entries)=="table" and box.entries or {}
    box.counters=type(box.counters)=="table" and box.counters or {}
    kind=tostring(kind or "unknown");reason=tostring(reason or "unspecified")
    box.counters[kind]=(SafeInt(box.counters[kind],0) or 0)+1
    box.entries[#box.entries+1]={kind=kind,reason=reason,payload=RuntimeState.RecoveryCopy(payload),details=RuntimeState.RecoveryCopy(details)}
end

local function LastPoint()
    local H = Hero()
    if not H then return nil end
    if type(H.tail) == "table" and #H.tail > 0 then
        local p = H.tail[#H.tail]
        return PointValid(p) and p or nil
    end
    if type(H.chunks) == "table" and #H.chunks > 0 then
        local ch = H.chunks[#H.chunks]
        if EncodedChunkValid(ch) then
            return {ch[5], ch[8], ch[9], ch[10], ch[11], ch[12], ch[13], ch[7], ch[14]}
        end
    end
    return nil
end

local function LastPointAnchor()
    local p = LastPoint()
    if not p then return nil end
    return { played=p[1], mapID=p[2], x=p[3], y=p[4], mode=p[5], order=p[8] or 0 }
end

local function BuildChunkedStorage(H)
    local chunks, buffer, tail = {}, {}, {}
    local lastPlayed, lastOrder = -math.huge, -math.huge
    local forceBreak = true

    local function flushBuffer()
        if #buffer == 0 then return end
        local ch = EncodeChunk(buffer)
        if ch then chunks[#chunks + 1] = ch end
        buffer = {}
    end

    local function accept(raw, toTail, source)
        local q = NormalizePoint(raw, forceBreak)
        if not q then
            RuntimeState.Quarantine(H,"point",tostring(source or "unknown")..": invalid point",raw)
            forceBreak = true
            return
        end
        local order = q[8] or 0
        local monotonic = q[1] > lastPlayed or (q[1] == lastPlayed and (order == 0 or lastOrder == 0 or order > lastOrder))
        if not monotonic then
            RuntimeState.Quarantine(H,"point",tostring(source or "unknown")..": non-monotonic point",raw,{lastPlayed=lastPlayed,lastOrder=lastOrder})
            forceBreak = true
            return
        end
        if toTail then
            tail[#tail + 1] = q
        else
            buffer[#buffer + 1] = q
            if #buffer >= RAW_CHUNK_POINTS then flushBuffer() end
        end
        lastPlayed, lastOrder = q[1], order
        forceBreak = false
    end

    local chunkEntries = RuntimeState.NumericEntries(H.chunks)
    local expectedChunkIndex=1
    for i=1,#chunkEntries do
        local key,ch=chunkEntries[i][1],chunkEntries[i][2]
        if key~=expectedChunkIndex then
            RuntimeState.Quarantine(H,"chunks","numeric-index-gap",nil,{expected=expectedChunkIndex,found=key})
            forceBreak=true
        end
        expectedChunkIndex=key+1
        if EncodedChunkValid(ch) then
            local certified=tonumber(ch[17])==1
            if not certified then
                local deepOK,deepReason=RuntimeState.DeepValidateChunk(ch)
                if not deepOK then
                    RuntimeState.Quarantine(H,"chunk","deep-check-failed:"..tostring(deepReason),ch,{index=key})
                    forceBreak=true
                    ch=nil
                else
                    local copy={};for k,v in pairs(ch) do copy[k]=v end;copy[17]=1;ch=copy
                end
            end
            if ch then
                local firstPlayed, firstOrder = ch[4], ch[6]
                local monotonic = firstPlayed > lastPlayed or (firstPlayed == lastPlayed and (firstOrder == 0 or lastOrder == 0 or firstOrder > lastOrder))
                if monotonic then
                    flushBuffer()
                    if forceBreak then
                        ch = D.CopyChunkWithBreakBefore(ch)
                    end
                    chunks[#chunks + 1] = ch
                    lastPlayed, lastOrder = ch[5], ch[7]
                    forceBreak = false
                else
                    RuntimeState.Quarantine(H,"chunk","non-monotonic-encoded-chunk",ch,{index=key,lastPlayed=lastPlayed,lastOrder=lastOrder})
                    forceBreak = true
                end
            end
        else
            RuntimeState.Quarantine(H,"chunk","encoded-chunk-invalid",ch,{index=key})
            forceBreak = true
        end
    end

    if H.points ~= nil then
        RuntimeState.Quarantine(H,"points","unexpected-storage-field",H.points)
        forceBreak = true
    end
    flushBuffer()

    local tailEntries=RuntimeState.NumericEntries(H.tail)
    local expectedTailIndex=1
    for i=1,#tailEntries do
        local key,p=tailEntries[i][1],tailEntries[i][2]
        if key~=expectedTailIndex then RuntimeState.Quarantine(H,"tail","numeric-index-gap",nil,{expected=expectedTailIndex,found=key});forceBreak=true end
        expectedTailIndex=key+1
        accept(p,true,"tail")
    end

    H.points = nil
    H.chunks = chunks
    H.tail = tail
end

local function EventTime(e)
    if e[1] == EVENT_INSTANCE then return tonumber(e[2]) or 0 end
    if e[1] == EVENT_STATE then return tonumber(e[3]) or 0 end
    return tonumber(e[2]) or 0
end

local function EventOrder(e)
    if e[1] == EVENT_DEATH then return tonumber(e[7]) or 0 end
    if e[1] == EVENT_INSTANCE then return tonumber(e[10]) or 0 end
    if e[1] == EVENT_STATE then return tonumber(e[4]) or 0 end
    return 0
end

local function SanitizeEvents(events)
    local out = {}
    if type(events) ~= "table" then return out end
    local eventEntries=RuntimeState.NumericEntries(events)
    local expectedEventIndex=1
    for row = 1, #eventEntries do
        local key,e = eventEntries[row][1],eventEntries[row][2]
        if key~=expectedEventIndex then RuntimeState.Quarantine(Hero(),"events","numeric-index-gap",nil,{expected=expectedEventIndex,found=key}) end
        expectedEventIndex=key+1
        local beforeCount=#out
        if type(e) == "table" then
            local kind = SafeInt(e[1], EVENT_DEATH, EVENT_STATE)
            if kind == EVENT_DEATH then
                local played = TrueStamp(e[2])
                local mapID = SafeInt(e[3], 0, MAX_WORLD_ID)
                local order = SafeInt(e[7], 0, MAX_ORDER) or 0
                local accuracy = SafeInt(e[8], DEATH_POS_EXACT, DEATH_POS_UNKNOWN) or DEATH_POS_EXACT
                if played and mapID then
                    local ex,ey=tonumber(e[4]) or 0,tonumber(e[5]) or 0
                    if not ValidWorldCoordinates(ex,ey) then mapID,ex,ey,accuracy=0,0,0,DEATH_POS_UNKNOWN end
                    out[#out + 1] = {EVENT_DEATH, played, mapID, ex, ey, tonumber(e[6]) == 1 and 1 or 0, order, accuracy}
                end
            elseif kind == EVENT_INSTANCE then
                local sp, ep = TrueStamp(e[2]), tonumber(e[3])
                local anchorKnown = e[12] == nil and 1 or (tonumber(e[12]) == 1 and 1 or 0)
                local mapID = SafeInt(e[4], 0, MAX_WORLD_ID) or 0
                local instanceID = SafeInt(e[9], 0, MAX_WORLD_ID) or 0
                local so, eo = SafeInt(e[10], 0, MAX_ORDER) or 0, SafeInt(e[11], 0, MAX_ORDER) or 0
                local ex,ey=tonumber(e[5]) or 0,tonumber(e[6]) or 0
                if anchorKnown==1 and not ValidWorldCoordinates(ex,ey) then anchorKnown,mapID,ex,ey=0,0,0,0 end
                if sp and IsFinite(ep) and ep >= 0 then
                    ep = ep == 0 and 0 or TrueStamp(ep)
                    if ep and (ep == 0 or ep >= sp) then
                        out[#out + 1] = {EVENT_INSTANCE, sp, ep, mapID, ex, ey, tostring(e[7] or "Instance"), tostring(e[8] or "instance"), instanceID, so, eo, anchorKnown}
                    end
                end
            elseif kind == EVENT_STATE then
                local code = SafeInt(e[2], MIN_STATE_CODE, MAX_STATE_CODE)
                local played = TrueStamp(e[3])
                local order = SafeInt(e[4], 0, MAX_ORDER) or 0
                local mapID = SafeInt(e[5], 0, MAX_WORLD_ID) or 0
                if code and played then
                    local ex,ey=tonumber(e[6]) or 0,tonumber(e[7]) or 0
                    -- State-event position validity is explicit. Events
                    -- had no flag; fail closed for the ambiguous 0/0/0 sentinel.
                    local positionKnown
                    if e[8] == nil then
                        positionKnown = not (mapID == 0 and ex == 0 and ey == 0) and 1 or 0
                    else
                        positionKnown = tonumber(e[8]) == 1 and 1 or 0
                    end
                    if positionKnown == 1 and not ValidWorldCoordinates(ex,ey) then
                        positionKnown,mapID,ex,ey=0,0,0,0
                    elseif positionKnown == 0 then
                        mapID,ex,ey=0,0,0
                    end
                    local row={EVENT_STATE, code, played, order, mapID, ex, ey, positionKnown}
                    local transitionId=SafeInt(e[9],1,L.MAX_TRANSITION_ID);if transitionId then row[9]=transitionId end
                    out[#out + 1] = row
                end
            end
        end
        if #out==beforeCount and e~=nil then RuntimeState.Quarantine(Hero(),"event","invalid-event",e,{index=key}) end
    end

    table.sort(out, function(a,b)
        local at, bt = EventTime(a), EventTime(b)
        if at ~= bt then return at < bt end
        return EventOrder(a) < EventOrder(b)
    end)

    -- Reconcile multiple open instances conservatively: only the newest may
    -- remain open. An older open event is closed at the next instance's start.
    local openIndex
    for i = 1, #out do
        local e = out[i]
        if e[1] == EVENT_INSTANCE then
            if openIndex and out[openIndex] and out[openIndex][3] == 0 then
                out[openIndex][3] = math.max(out[openIndex][2], e[2])
                out[openIndex][11] = math.max(out[openIndex][10] or 0, (e[10] or 0) - 1)
            end
            if e[3] == 0 then openIndex = i else openIndex = nil end
        end
    end
    return out
end

local function RebuildMetadata(H)
    local maxOrder, maxPlayed = 0, 0
    for _, ch in ipairs(H.chunks or {}) do
        if EncodedChunkValid(ch) then
            maxOrder = math.max(maxOrder, ch[7] or 0)
            maxPlayed = math.max(maxPlayed, ch[5] or 0)
        end
    end
    for _, p in ipairs(H.tail or {}) do
        if PointValid(p) then
            maxOrder = math.max(maxOrder, SafeInt(p[8],0,MAX_ORDER) or 0)
            maxPlayed = math.max(maxPlayed, tonumber(p[1]) or 0)
        end
    end
    for _,e in ipairs(H.events or {}) do
        maxOrder = math.max(maxOrder, EventOrder(e))
        if e[1] == EVENT_INSTANCE then
            maxOrder = math.max(maxOrder, SafeInt(e[11],0,MAX_ORDER) or 0)
            maxPlayed = math.max(maxPlayed, tonumber(e[2]) or 0, tonumber(e[3]) or 0)
        else
            maxPlayed = math.max(maxPlayed, EventTime(e))
        end
    end
    for _,e in ipairs(H.semanticEvents or {}) do
        if type(e)=="table" then
            maxPlayed = math.max(maxPlayed, ValidPlayed(e[1]) and tonumber(e[1]) or 0)
            maxOrder = math.max(maxOrder, SafeInt(e[2],0,MAX_ORDER) or 0)
        end
    end
    local storedLast = ValidPlayed(H.lastPlayed) and tonumber(H.lastPlayed) or nil
    H.sequence = maxOrder
    if storedLast and maxPlayed==0 and storedLast>0 then
        RuntimeState.Quarantine(H,"metadata","lastPlayed-without-history",storedLast,{historyMax=0})
        H.lastPlayed=0
    elseif storedLast and maxPlayed>0 and storedLast>maxPlayed+STORED_LAST_PLAYED_AHEAD_TOLERANCE then
        RuntimeState.Quarantine(H,"metadata","lastPlayed-ahead-of-history",storedLast,{historyMax=maxPlayed})
        H.lastPlayed=maxPlayed
    elseif storedLast then
        H.lastPlayed=math.max(maxPlayed,storedLast)
    else
        H.lastPlayed=maxPlayed
    end
    H.lastStrictPlayed = nil
    H.rawStartIndex = nil
end

local function SetPendingDeathBreak(value)
    forceBreakAfterDeath = value == true
    local H = Hero()
    if H then H.pendingDeathBreak = forceBreakAfterDeath and 1 or nil end
end

local function CurrentWorldPosition()
    if type(ns.WorldPos) ~= "function" then return nil,nil,nil,"none" end
    local ok,x,y,mapID,source = pcall(ns.WorldPos)
    if not ok then return nil,nil,nil,"error" end
    if type(source) ~= "string" then source = nil end
    x,y,mapID = Num(x),Num(y),Num(mapID)
    mapID = SafeInt(mapID,0,MAX_WORLD_ID)
    if not ValidWorldCoordinates(x,y) or not mapID then return nil,nil,nil,source or "invalid" end
    return tonumber(x),tonumber(y),mapID,source
end

local function RecordPositionSource(source)
    local H=Hero(); if not H then return end
    local d=type(H.positionDiagnostics)=="table" and H.positionDiagnostics or {}
    H.positionDiagnostics=d
    if source=="dual" then d.dual=(SafeInt(d.dual,0) or 0)+1
    elseif source=="cmap" then d.cmap=(SafeInt(d.cmap,0) or 0)+1
    elseif source=="unit" then d.unit=(SafeInt(d.unit,0) or 0)+1
    elseif source=="mismatch" then d.mismatch=(SafeInt(d.mismatch,0) or 0)+1
    else d.missing=(SafeInt(d.missing,0) or 0)+1 end
    d.lastSource=tostring(source or "none")
    if type(ns.GetIntegrationHealth)=="function" then
        local ok,ih=pcall(ns.GetIntegrationHealth)
        if ok and type(ih)=="table" then
            if ih.unitOrder=="XY" or ih.unitOrder=="YX" then d.unitOrder=ih.unitOrder end
            d.calibrationResets=SafeInt(ih.calibrationResets,0) or (SafeInt(d.calibrationResets,0) or 0)
            d.calibrationAmbiguous=SafeInt(ih.calibrationAmbiguous,0) or (SafeInt(d.calibrationAmbiguous,0) or 0)
        end
    end
end

local function DeathState()
    local ghost = Call("UnitIsGhost", "player")
    local deadOrGhost = Call("UnitIsDeadOrGhost", "player")
    if ghost == true then return "ghost" end
    if deadOrGhost == true then return "dead" end
    if ghost == false and deadOrGhost == false then return "alive" end
    return nil
end

local function MovementMode(onTaxi, taxiKnown, lifeState)
    if lifeState == "ghost" then return 4 end
    if onTaxi == true then return 3 end
    local swimming = Call("IsSwimming")
    local mounted = Call("IsMounted")
    -- Retail can move far faster while flying/skyriding than a Forever ground mount.
    -- Treat actual player flight as special continuous movement so Retail flight behavior
    -- session cannot be polluted by false teleport breaks. On Forever this is simply false/nil.
    local flying = Call("IsFlying", "player")
    local inVehicle = Call("UnitInVehicle","player")
    if inVehicle ~= true then inVehicle = Call("UnitHasVehicleUI","player") end
    local possessed = Call("UnitIsPossessed","player")
    if swimming == true then return 2 end
    if flying == true then return 5 end
    if mounted == true then return 1 end
    if inVehicle == true or possessed == true then return 5 end
    if taxiKnown == false then return 5 end
    if swimming == false and mounted == false and (inVehicle == false or inVehicle == nil) and (possessed == false or possessed == nil) then return 0 end
    -- Do not turn a missing/unsupported movement API into a false "walking" fact.
    return 5
end

-- ===== Semantic events and causal annotations =====
local function AddStateEvent(code, played, mapID, x, y, transitionId)
    local profile = Hero()
    local stamp = TouchLastPlayed(played)
    if RuntimeState.archiveReadOnly or not profile or not stamp or not SafeInt(code,MIN_STATE_CODE,MAX_STATE_CODE) then return nil end
    local safeMap = SafeInt(mapID,0,MAX_WORLD_ID)
    local sx,sy=tonumber(x),tonumber(y)
    local positionKnown = (safeMap ~= nil and sx ~= nil and sy ~= nil and ValidWorldCoordinates(sx,sy)) and 1 or 0
    if positionKnown == 0 then safeMap,sx,sy=0,0,0 end
    local order = NextOrder()
    local e = {EVENT_STATE, code, stamp, order, safeMap, sx, sy, positionKnown}
    local tid = SafeInt(transitionId, 1, L.MAX_TRANSITION_ID)
    if tid then e[9] = tid end
    profile.events[#profile.events+1] = e
    if not tid then ns.Metadata.AddContextSnapshot(Hero(),C.Context.STATE, stamp, safeMap, sx, sy, order) end
    return e
end

function RuntimeState.SemanticHintActive()
    if not pendingTransportHint then return nil end
    local now=SafeNow()
    local h=pendingTransportHint
    if h.boundWorld then
        -- While the loading boundary is active the hint is causal, not time based.
        -- Once the destination world is entered it gets only a short window to be
        -- consumed by the first stable destination transition.
        if h.destinationAt and now-h.destinationAt>SEMANTIC_HINT_DESTINATION_SECONDS then
            pendingTransportHint=nil
            return nil
        end
        return h
    end
    if now-(h.at or now)>SEMANTIC_HINT_DIRECT_SECONDS then
        pendingTransportHint=nil
        return nil
    end
    return h
end

function RuntimeState.BindSemanticHintToWorldBoundary()
    local h=RuntimeState.SemanticHintActive()
    if not h then return end
    h.boundWorld=true
    h.destinationAt=nil
end

function RuntimeState.MarkSemanticDestinationEntered()
    if pendingTransportHint and pendingTransportHint.boundWorld then
        pendingTransportHint.destinationAt=SafeNow()
    end
end

function RuntimeState.AddSemanticEvent(hint,played,mapID,x,y,transitionId)
    local profile=Hero(); local stamp=TouchLastPlayed(played)
    if RuntimeState.archiveReadOnly or not profile or not stamp or type(hint)~="table" then return end
    profile.semanticEvents=type(profile.semanticEvents)=="table" and profile.semanticEvents or {}
    local code=hint.kind=="hearth" and RuntimeState.SEMANTIC_HEARTH or RuntimeState.SEMANTIC_TELEPORT_SPELL
    local sx,sy=x or 0,y or 0;if not ValidWorldCoordinates(sx,sy) then sx,sy=0,0 end
    local known=ValidWorldCoordinates(sx,sy) and 1 or 0
    if known==0 then sx,sy=0,0 end
    local row={stamp,NextOrder(),code,SafeInt(hint.spellID,0,MAX_WORLD_ID) or 0,SafeInt(mapID,0,MAX_WORLD_ID) or 0,RoundTenth(sx),RoundTenth(sy),known}
    local tid=SafeInt(transitionId,1,L.MAX_TRANSITION_ID);if tid then row[9]=tid end
    profile.semanticEvents[#profile.semanticEvents+1]=row
end

local function RecordSemanticTransition(defaultCode, played, mapID, x, y)
    -- Observation and cause remain separate. The state event says what happened;
    -- the transition record links a measured departure/arrival pair and labels the
    -- cause only when the evidence supports it.
    local profile=Hero();if RuntimeState.archiveReadOnly or not profile then return nil end
    local hint=RuntimeState.SemanticHintActive()
    local transitionId=ns.Metadata.NextTransitionId(profile)
    if not transitionId then return AddStateEvent(defaultCode,played,mapID,x,y) end
    local observed = AddStateEvent(defaultCode,played,mapID,x,y,transitionId)
    local observedOrder=observed and observed[4] or 0
    local departure = hint and hint.departure or lastRaw or resumeAnchor or LastPointAnchor()
    local departureContext = hint and hint.departureContext or false
    local arrival = {played=played,mapID=mapID,x=x,y=y,order=observedOrder}
    local cause,confidence=ns.Metadata.TransitionCause(defaultCode,hint)
    local row={
        id=transitionId, observedState=defaultCode, cause=cause, confidence=confidence,
        spellID=hint and (SafeInt(hint.spellID,0,MAX_WORLD_ID) or 0) or 0,
        departure=ns.Metadata.BuildTransitionEndpoint(profile,departure,C.Context.TRANSITION_DEPARTURE,departureContext),
        arrival=ns.Metadata.BuildTransitionEndpoint(profile,arrival,C.Context.TRANSITION_ARRIVAL,nil),
    }
    profile.transitions=type(profile.transitions)=="table" and profile.transitions or {}
    profile.transitions[#profile.transitions+1]=row
    if hint then
        if hint.kind=="hearth" then AddStateEvent(STATE_HEARTH,played,mapID,x,y,transitionId) end
        RuntimeState.AddSemanticEvent(hint,played,mapID,x,y,transitionId)
        pendingTransportHint=nil
    end
    -- Hero’sPath deliberately does not infer boat/zeppelin from endpoints. If the client
    -- exposes positions while the platform moves, they are sampled normally; if
    -- positions disappear/reappear, the gap/world break is kept as measured truth.
    return observed
end

-- ===== Geometry preservation and time-sliced compaction =====
-- Curvature is detected with dot/cross products only: no acos, no allocations.
-- The 4 Hz observation cadence is unchanged; this decides whether a sample is
-- geometrically meaningful enough to persist and whether compaction may remove it.
function RuntimeState.CurvatureSignificant(ax,ay,bx,by,cx,cy)
    local v1x,v1y=bx-ax,by-ay
    local v2x,v2y=cx-bx,cy-by
    local d1sq=v1x*v1x+v1y*v1y
    local d2sq=v2x*v2x+v2y*v2y
    local minLegSq=S.CORNER_MIN_LEG_YARDS*S.CORNER_MIN_LEG_YARDS
    if d1sq<minLegSq or d2sq<minLegSq then return false end
    local d1,d2=math.sqrt(d1sq),math.sqrt(d2sq)
    local cos=(v1x*v2x+v1y*v2y)/(d1*d2)
    if cos>S.CORNER_COS_MAX then return false end
    if cos<=S.SHARP_CORNER_COS_MAX then return true end
    local acx,acy=cx-ax,cy-ay
    local aclen=math.sqrt(acx*acx+acy*acy)
    local deviation
    if aclen<=S.INTERPOLATION_TIME_EPSILON_SECONDS then
        deviation=math.min(d1,d2)
    else
        deviation=math.abs(acx*(ay-by)-acy*(ax-bx))/aclen
    end
    return deviation>=S.CORNER_MIN_DEVIATION_YARDS
end

function RuntimeState.GeometryPointSignificant(points,i)
    if Z.PRESERVE_CURVATURE~=true or i<=1 or i>=#points then return false end
    local a,b,c=points[i-1],points[i],points[i+1]
    if not a or not b or not c then return false end
    if a[2]~=b[2] or b[2]~=c[2] or a[5]~=b[5] or b[5]~=c[5] then return false end
    if b[6]==1 or c[6]==1 then return false end
    return RuntimeState.CurvatureSignificant(a[3],a[4],b[3],b[4],c[3],c[4])
end

local function ReplayInterpolationError(a,b,c)
    local dt = c[1]-a[1]
    if dt <= S.INTERPOLATION_TIME_EPSILON_SECONDS then return DistanceXY(a[3],a[4],b[3],b[4]) end
    local r=(b[1]-a[1])/dt
    if r<0 then r=0 elseif r>1 then r=1 end
    return DistanceXY(b[3],b[4],a[3]+(c[3]-a[3])*r,a[4]+(c[4]-a[4])*r)
end

local function IsProtectedPoint(p)
    return p[6] == 1 or p[7] == 1
end

local function RDPKeep(points, first, last, keep)
    if last <= first+1 then return end
    local a,c=points[first],points[last]
    local maxDistance,maxIndex=-1,nil
    for i=first+1,last-1 do
        local p=points[i]
        local mustKeep = IsProtectedPoint(p) or RuntimeState.GeometryPointSignificant(points,i) or p[5]~=a[5] or p[5]~=c[5] or p[2]~=a[2] or p[2]~=c[2] or (p[1]-a[1])>=RDP_KEYFRAME_SECONDS
        if mustKeep then maxDistance,maxIndex=math.huge,i;break end
        local d=ReplayInterpolationError(a,p,c)
        if d>maxDistance then maxDistance,maxIndex=d,i end
    end
    if maxIndex and maxDistance>RDP_EPSILON_YARDS then
        keep[maxIndex]=true
        RDPKeep(points,first,maxIndex,keep)
        RDPKeep(points,maxIndex,last,keep)
    end
end

local function CompressPoints(points)
    if #points <= 2 then return points end
    local keep={[1]=true,[#points]=true}
    RDPKeep(points,1,#points,keep)
    local out={}
    for i=1,#points do if keep[i] then out[#out+1]=points[i] end end
    return out
end

local function FinalizeRawChunk()
    local timerAvailable = C_Timer and type(C_Timer.After) == "function"
    local J = RuntimeState.compressionJob
    if not J then
        local H = Hero()
        if not H or type(H.tail) ~= "table" or #H.tail < RAW_TAIL_TRIGGER then
            compressionScheduled = false
            return
        end
        local raw = {}
        local take = math.min(RAW_CHUNK_POINTS, #H.tail)
        for i = 1, take do
            if not PointValid(H.tail[i]) then
                local message="invalid raw tail point at index "..tostring(i)
                RuntimeState.Quarantine(H,"tail-live","invalid-point-blocked-compaction",H.tail[i],{index=i})
                RuntimeState.compressionJob=nil;compressionScheduled=false
                -- A structurally invalid raw point is not a transient compressor
                -- exception. Signal an explicit fatal block so RunCompressionSlice
                -- does not immediately clear recoveryNeeded or spin retries.
                return false,message,true
            end
            raw[i] = H.tail[i]
        end
        J = {
            hero = H, tail = H.tail, points = raw, take = take,
            keep = {[1] = true, [take] = true}, stack = {{1, take}}, frame = nil,
        }
        RuntimeState.compressionJob = J
    end

    -- If sanitation/owner switching replaced the mutable tail, abort rather than
    -- compact a stale table. No recorded point is removed in this path.
    if not J.hero or J.hero.tail ~= J.tail then
        RuntimeState.compressionJob = nil
        compressionScheduled = false
        return
    end

    local profileStart = type(debugprofilestop) == "function" and debugprofilestop() or nil
    local budget = timerAvailable and RuntimeState.COMPRESSION_WORK_PER_SLICE or math.huge
    while budget > 0 do
        local frame = J.frame
        if not frame then
            local pair = table.remove(J.stack)
            if not pair then break end
            local first, last = pair[1], pair[2]
            if last > first + 1 then
                frame = {first = first, last = last, i = first + 1, a = J.points[first], c = J.points[last], maxDistance = -1, maxIndex = nil}
                J.frame = frame
            end
        end
        frame = J.frame
        if frame then
            while frame.i < frame.last and budget > 0 do
                local i = frame.i
                local p = J.points[i]
                local mustKeep = IsProtectedPoint(p) or RuntimeState.GeometryPointSignificant(J.points,i) or p[5] ~= frame.a[5] or p[5] ~= frame.c[5] or p[2] ~= frame.a[2] or p[2] ~= frame.c[2] or (p[1] - frame.a[1]) >= RDP_KEYFRAME_SECONDS
                budget = budget - 1
                if mustKeep then
                    frame.maxDistance, frame.maxIndex, frame.i = math.huge, i, frame.last
                else
                    local d = ReplayInterpolationError(frame.a, p, frame.c)
                    if d > frame.maxDistance then frame.maxDistance, frame.maxIndex = d, i end
                    frame.i = i + 1
                end
            end
            if frame.i >= frame.last then
                if frame.maxIndex and frame.maxDistance > RDP_EPSILON_YARDS then
                    J.keep[frame.maxIndex] = true
                    -- Push right first so the left branch is processed first, matching
                    -- the recursive implementation's deterministic traversal.
                    J.stack[#J.stack + 1] = {frame.maxIndex, frame.last}
                    J.stack[#J.stack + 1] = {frame.first, frame.maxIndex}
                end
                J.frame = nil
            end
        end
        if not J.frame and #J.stack == 0 then break end
    end

    if profileStart then
        local elapsed = debugprofilestop() - profileStart
        if elapsed >= 0 then
            RuntimeState.compressionSlices = RuntimeState.compressionSlices + 1
            RuntimeState.compressionLastSliceMs = elapsed
            if elapsed > RuntimeState.compressionMaxSliceMs then RuntimeState.compressionMaxSliceMs = elapsed end
        end
    end

    if J.frame or #J.stack > 0 then
        compressionScheduled = true
        if timerAvailable then
            C_Timer.After(RuntimeState.COMPRESSION_SLICE_SECONDS, RuntimeState.RunCompressionSlice)
        else
            -- Harness/very old client fallback: without a scheduler, finish now.
            RuntimeState.RunCompressionSlice()
        end
        return
    end

    local simplified = {}
    for i = 1, #J.points do if J.keep[i] then simplified[#simplified + 1] = J.points[i] end end
    local packed = EncodeChunk(simplified)
    if packed and J.hero.tail == J.tail then
        J.hero.chunks[#J.hero.chunks + 1] = packed
        local rest = {}
        for i = J.take + 1, #J.hero.tail do rest[#rest + 1] = J.hero.tail[i] end
        J.hero.tail = rest
        J.hero.compactions = (SafeInt(J.hero.compactions, 0) or 0) + 1
        J.hero.lastCompactionInput = J.take
        J.hero.lastCompactionOutput = #simplified
    end
    RuntimeState.compressionJob = nil
    compressionScheduled = false

    local H = Hero()
    if H and type(H.tail) == "table" and #H.tail >= RAW_TAIL_TRIGGER then
        compressionScheduled = true
        if timerAvailable then C_Timer.After(RuntimeState.COMPRESSION_SLICE_SECONDS, RuntimeState.RunCompressionSlice) else RuntimeState.RunCompressionSlice() end
    end
end

function RuntimeState.RunCompressionSlice()
    local ok,status,detail,fatal=pcall(FinalizeRawChunk)
    if ok and status~=false then
        RuntimeState.compressionFailureStreak=0
        local H=Hero();if H then H.compressionRecoveryNeeded=nil end
        return true
    end

    local message
    if ok then message=detail or "compression blocked"
    else message=status end
    RuntimeState.compressionErrors=(tonumber(RuntimeState.compressionErrors) or 0)+1
    RuntimeState.lastCompressionError=tostring(message)
    -- The source tail is only replaced after a packed chunk exists. Resetting the job
    -- therefore preserves the authoritative raw points and lets a transient exception retry.
    RuntimeState.compressionJob=nil;compressionScheduled=false
    local H=Hero()

    if ok and fatal==true then
        -- Structural corruption is deterministic, not transient. Do not repeatedly
        -- retry/quarantine the same broken point; preserve raw data and fail closed.
        RuntimeState.compressionFailureStreak=0
        if H then H.compressionRecoveryNeeded=1 end
        return false
    end

    RuntimeState.compressionFailureStreak=(tonumber(RuntimeState.compressionFailureStreak) or 0)+1
    if RuntimeState.compressionFailureStreak<=Z.RETRY_MAX_FAILURES and C_Timer and type(C_Timer.After)=="function" then
        if H then H.compressionRecoveryNeeded=nil end
        C_Timer.After(Z.RETRY_SECONDS,function()
            local current=Hero()
            if current and type(current.tail)=="table" and #current.tail>=RAW_TAIL_TRIGGER then RuntimeState.ScheduleCompression() end
        end)
    else
        -- No scheduler or repeated exceptions: fail closed for the live session. Raw
        -- points remain authoritative and a clean save/reload can recover safely.
        if H then H.compressionRecoveryNeeded=1 end
    end
    return false
end

function RuntimeState.ScheduleCompression()
    local H = Hero()
    if not H or H.compressionRecoveryNeeded==1 or compressionScheduled or RuntimeState.compressionJob or #H.tail < RAW_TAIL_TRIGGER then return end
    if C_Timer and type(C_Timer.After) == "function" then
        compressionScheduled = true
        C_Timer.After(RuntimeState.COMPRESSION_SLICE_SECONDS, RuntimeState.RunCompressionSlice)
    else
        compressionScheduled = true
        RuntimeState.RunCompressionSlice()
    end
end

-- Clean logout/reload optimization. The live collector never blocks on a full RDP
-- pass, but once the client is leaving we can compact the bounded raw tail so the
-- SavedVariables file stays small. Raw data remains authoritative if packing fails.
function RuntimeState.FlushForSave()
    if RuntimeState.archiveReadOnly then return true end
    local H = Hero()
    if not H or type(H.tail) ~= "table" then return true end
    PreserveTerminalObservation()
    if #H.tail == 0 then return true end
    RuntimeState.compressionJob = nil
    compressionScheduled = false
    while #H.tail > 0 do
        local take = math.min(RAW_CHUNK_POINTS, #H.tail)
        local raw = {}
        for i = 1, take do raw[i] = H.tail[i] end
        local simplified = CompressPoints(raw)
        local packed = EncodeChunk(simplified)
        if not packed then return false end
        H.chunks[#H.chunks + 1] = packed
        local rest = {}
        for i = take + 1, #H.tail do rest[#rest + 1] = H.tail[i] end
        H.tail = rest
        H.compactions = (SafeInt(H.compactions, 0) or 0) + 1
        H.lastCompactionInput = take
        H.lastCompactionOutput = #simplified
    end
    H.lastSaveCompaction = TrueStamp(H.lastPlayed) or H.lastPlayed or 0
    H.compressionRecoveryNeeded=nil
    RuntimeState.compressionFailureStreak=0
    return true
end

AddPoint=function(played,mapID,x,y,mode,breakBefore,protectedAnchor,breakReason)
    local H=Hero()
    local stamp=TouchLastPlayed(played)
    if not H or not stamp or not SafeInt(mapID,0,MAX_WORLD_ID) or not ValidWorldCoordinates(x,y) or not SafeInt(mode,0,MAX_MOVEMENT_MODE) then return nil end
    local previous=LastPoint()
    if previous and stamp < previous[1] then
        RuntimeState.Quarantine(H,"point-live","runtime-non-monotonic-append",{stamp,mapID,x,y,mode},{lastPlayed=previous[1],lastOrder=previous[8]})
        return nil
    end
    local reason=breakBefore and (SafeInt(breakReason,0,MAX_BREAK_REASON) or BREAK_RESUME) or BREAK_NONE
    local p={stamp,mapID,RoundTenth(x),RoundTenth(y),mode,breakBefore and 1 or 0,protectedAnchor and 1 or 0,NextOrder(),reason}
    H.tail[#H.tail+1]=p
    RuntimeState.ScheduleCompression()
    return p
end

local function ProtectOrInsertAnchor(raw)
    if not raw then return nil end
    local p=LastPoint()
    if p and p[2]==raw.mapID and math.abs(p[1]-raw.played)<S.ANCHOR_TIME_EPSILON_SECONDS and DistanceXY(p[3],p[4],raw.x,raw.y)<=S.ANCHOR_POSITION_EPSILON_YARDS then
        p[7]=1
        return p
    end
    return AddPoint(raw.played,raw.mapID,raw.x,raw.y,raw.mode,false,true,BREAK_NONE)
end

PreserveTerminalObservation=function()
    -- Adaptive storage may legitimately skip the newest 4 Hz observations. On a
    -- clean logout/reload preserve the last trusted observation so replay keeps the
    -- exact session endpoint (and the duration of a final idle hold) for one point
    -- of overhead per session at most.
    if not lastRaw then return nil end
    local p=LastPoint()
    if p and lastRaw.played < p[1] then return nil end
    if p and p[2]==lastRaw.mapID and math.abs(p[1]-lastRaw.played)<S.ANCHOR_TIME_EPSILON_SECONDS and
       DistanceXY(p[3],p[4],lastRaw.x,lastRaw.y)<=S.ANCHOR_POSITION_EPSILON_YARDS and p[5]==lastRaw.mode then
        p[7]=1
        return p
    end
    return AddPoint(lastRaw.played,lastRaw.mapID,lastRaw.x,lastRaw.y,lastRaw.mode,false,true,BREAK_NONE)
end

-- ===== Instance / death / life-state tracking =====
local function CurrentInstanceInfo()
    local inside,itype=Call("IsInInstance")
    if inside~=true and inside~=false and inside~=nil then return nil,nil,nil,nil end
    if inside==nil then return nil,nil,nil,nil end
    if type(itype)~="string" then itype=nil end
    local name,infoType,instanceID
    local n,t,_,_,_,_,_,id=Call("GetInstanceInfo")
    if n~=nil or t~=nil or id~=nil then
        name=type(n)=="string" and n or nil
        infoType=type(t)=="string" and t or nil
        instanceID=SafeInt(Num(id),0,MAX_WORLD_ID)
    end
    -- Deeprun Tram is a real separate map (InstanceID 369), but Classic/fork
    -- clients may expose an unusual/blank instance type. Identity wins here.
    if IsTramInstance(name,instanceID) then
        return true,"transport",name or "Deeprun Tram",SafeInt(instanceID,0,MAX_WORLD_ID) or I.DEEPRUN_TRAM_INSTANCE_ID
    end
    if inside~=true or itype=="none" then return false,nil,nil,nil end
    return true,itype or infoType or "instance",name or "Instance",SafeInt(instanceID,0,MAX_WORLD_ID) or 0
end

local function FindOpenInstanceEvent()
    local H=Hero(); if not H then return nil end
    for i=#H.events,1,-1 do
        local e=H.events[i]
        if e[1]==EVENT_INSTANCE and tonumber(e[3])==0 then return i end
    end
    return nil
end

local function BeginInstance(played,itype,name,instanceID)
    local H=Hero(); if not H then return end
    local stamp=TouchLastPlayed(played); if not stamp then return end
    local open=currentInstanceEventIndex or FindOpenInstanceEvent()
    if open then
        local e=H.events[open]
        local oldID,newID=SafeInt(Num(e[9]),0,MAX_WORLD_ID) or 0,SafeInt(Num(instanceID),0,MAX_WORLD_ID) or 0
        local oldName=type(e[7])=="string" and e[7] or "Instance"
        local newName=type(name)=="string" and name or "Instance"
        local idCompatible=oldID==0 or newID==0 or oldID==newID
        local nameCompatible=oldName==newName or oldName=="Instance" or newName=="Instance" or newName==""
        if idCompatible and nameCompatible then
            if oldID==0 and newID~=0 then e[9]=newID end
            if (oldName=="Instance" or oldName=="") and newName~="" then e[7]=newName end
            if (tostring(e[8] or "instance")=="instance") and itype and itype~="instance" then e[8]=tostring(itype) end
            currentInstanceEventIndex=open
            return
        end
        e[3]=math.max(e[2],stamp); e[11]=NextOrder(); currentInstanceEventIndex=nil
    end
    -- Only a position observed immediately before the transition is a trustworthy
    -- exterior entrance anchor. A stale historical point from a login/relaunch is not.
    local anchor=nil
    if lastRaw and stamp-(lastRaw.played or stamp)<=SAMPLE_GAP_SECONDS then
        anchor=lastRaw
    elseif resumeAnchor and resumeReason=="world" and stamp-(resumeAnchor.played or stamp)<=SAMPLE_GAP_SECONDS*2 then
        anchor=resumeAnchor
    end
    local anchorKnown=anchor and 1 or 0
    local amap,ax,ay=0,0,0
    if anchor then amap,ax,ay=anchor.mapID,RoundTenth(anchor.x),RoundTenth(anchor.y) end
    local safeName=type(name)=="string" and name or "Instance"
    local safeType=type(itype)=="string" and itype or "instance"
    local safeInstanceID=SafeInt(Num(instanceID),0,MAX_WORLD_ID) or 0
    local startOrder=NextOrder()
    H.events[#H.events+1]={EVENT_INSTANCE,stamp,0,amap,ax,ay,safeName,safeType,safeInstanceID,startOrder,0,anchorKnown}
    ns.Metadata.AddContextSnapshot(Hero(),C.Context.INSTANCE_ENTER,stamp,amap,ax,ay,startOrder)
    currentInstanceEventIndex=#H.events
    if IsTramInstance(name,instanceID) then AddStateEvent(STATE_TRAM_START,stamp,amap,ax,ay) end
    lastRaw=nil; idleStartRaw=nil
end

local function EndInstance(played)
    local H=Hero(); if not H then return end
    local stamp=TouchLastPlayed(played); if not stamp then return end
    local idx=currentInstanceEventIndex or FindOpenInstanceEvent()
    if idx and H.events[idx] and H.events[idx][1]==EVENT_INSTANCE then
        local e=H.events[idx]
        e[3]=math.max(e[2],stamp); e[11]=NextOrder()
        if tonumber(e[12]) ~= 0 then
            resumeAnchor={played=e[3],mapID=e[4],x=e[5],y=e[6],mode=0,order=e[11]}
            resumeReason="instance"
        else
            resumeAnchor=nil
            resumeReason="instance-no-anchor"
        end
        pendingTramExit=IsTramInstance(e[7],e[9])
        forceResumeAnchor=true
    end
    currentInstanceEventIndex=nil
    lastRaw=nil; idleStartRaw=nil
end

local function InstanceSignature(inside,itype,name,instanceID)
    if inside~=true then return "outside" end
    local safeID=SafeInt(Num(instanceID),0,MAX_WORLD_ID) or 0
    local safeType=type(itype)=="string" and itype or "instance"
    local safeName=type(name)=="string" and name or "Instance"
    return table.concat({"inside",safeID,safeType,safeName},"|")
end

local function UpdateInstanceState(played)
    local inside,itype,name,instanceID=CurrentInstanceInfo()
    if inside==nil then
        instanceUnknownCount=instanceUnknownCount+1
        if instanceUnknownCount==1 then
            instanceUnknownStartPlayed=played
            instanceUnknownAnchor=lastRaw or resumeAnchor or LastPointAnchor()
        end
        -- Never close a known/open instance because the API disappeared.
        if currentInstanceEventIndex or FindOpenInstanceEvent() or (instanceStableSignature and instanceStableSignature~="outside") then
            return true
        end
        -- One failed probe after a stable outside state is treated as transient.
        -- A sustained failure becomes an explicit unavailable interval in Sample().
        if instanceStableSignature=="outside" and instanceUnknownCount<STATE_CHANGE_CONFIRM_SAMPLES then return false end
        return nil
    end
    instanceUnknownCount=0;instanceUnknownStartPlayed=nil;instanceUnknownAnchor=nil
    local sig=InstanceSignature(inside,itype,name,instanceID)
    if not instanceStableSignature then
        instanceStableSignature=sig
    elseif sig~=instanceStableSignature then
        if instanceCandidateSignature==sig then instanceCandidateCount=instanceCandidateCount+1
        else instanceCandidateSignature=sig;instanceCandidateCount=1 end
        if instanceCandidateCount<STATE_CHANGE_CONFIRM_SAMPLES then
            -- A possible entry suspends exterior sampling immediately; a possible
            -- exit keeps the instance active until confirmed. Both choices avoid
            -- contaminating the exterior path during one-frame API flicker.
            return (instanceStableSignature~="outside") or inside==true
        end
        instanceStableSignature=sig
        instanceCandidateSignature=nil;instanceCandidateCount=0
    else
        instanceCandidateSignature=nil;instanceCandidateCount=0
    end
    if inside then BeginInstance(played,itype,name,instanceID); return true end
    if currentInstanceEventIndex or FindOpenInstanceEvent() then EndInstance(played) end
    return false
end

local function LatestDeathWasInside()
    local H=Hero(); if not H then return false end
    for i=#H.events,1,-1 do
        local e=H.events[i]
        if e[1]==EVENT_DEATH then return e[6]==1 end
    end
    return false
end

local function RecordDeathAt(stamp)
    local H=Hero(); if not H or not stamp then return end
    if lastLifeState=="dead" and tonumber(H.deathActive)==1 then return end

    local x,y,mapID,accuracy
    local openInstance=currentInstanceEventIndex or FindOpenInstanceEvent()
    -- Death classification uses the debounced instance state. A one-frame false
    -- IsInInstance() result must never move an in-instance death outside.
    local stableInside=openInstance~=nil or (instanceStableSignature and instanceStableSignature~="outside")
    local candidateInside=type(instanceCandidateSignature)=="string" and instanceCandidateSignature:sub(1,7)=="inside|"
    local inside=stableInside or candidateInside
    if not inside and instanceStableSignature==nil then
        local instanceProbe=CurrentInstanceInfo()
        inside=instanceProbe==true
    end
    if inside then
        local e=openInstance and H.events[openInstance]
        if e and e[1]==EVENT_INSTANCE and tonumber(e[12])~=0 then
            mapID,x,y=e[4],e[5],e[6];accuracy=DEATH_POS_INSTANCE_ANCHOR
        else
            -- If PLAYER_DEAD races the instance-entry debounce, a very recent outdoor
            -- observation may still be a valid entrance anchor. Never reuse an old
            -- login/reload resumeAnchor from an unrelated place.
            local a
            if lastRaw and stamp-(lastRaw.played or stamp)<=SAMPLE_GAP_SECONDS then
                a=lastRaw
            elseif resumeAnchor and resumeReason=="world" and stamp-(resumeAnchor.played or stamp)<=SAMPLE_GAP_SECONDS*2 then
                a=resumeAnchor
            end
            if a then mapID,x,y=a.mapID,a.x,a.y;accuracy=DEATH_POS_INSTANCE_ANCHOR
            else mapID,x,y,accuracy=0,0,0,DEATH_POS_UNKNOWN end
        end
    else
        x,y,mapID=CurrentWorldPosition()
        if x then accuracy=DEATH_POS_EXACT
        else
            local a=lastRaw or resumeAnchor or LastPointAnchor()
            if a then mapID,x,y=a.mapID,a.x,a.y;accuracy=DEATH_POS_LAST_KNOWN
            else mapID,x,y,accuracy=0,0,0,DEATH_POS_UNKNOWN end
        end
    end
    local deathStamp=TouchLastPlayed(stamp);local deathOrder=NextOrder()
    H.events[#H.events+1]={EVENT_DEATH,deathStamp,mapID,RoundTenth(x),RoundTenth(y),inside and 1 or 0,deathOrder,accuracy}
    ns.Metadata.AddContextSnapshot(Hero(),C.Context.DEATH,deathStamp,mapID,x,y,deathOrder)
    H.deathActive=1; SetPendingDeathBreak(true); lastLifeState="dead"
    lifeCandidate=nil;lifeCandidateCount=0
    lastRaw=nil;idleStartRaw=nil;resumeAnchor=nil;resumeReason="death";forceResumeAnchor=false
end

local function RecordDeath()
    if RuntimeState.archiveReadOnly then return end
    local stamp=ReadPlayedNow()
    if not stamp then MarkPlayedUnavailable(); return end
    RecordDeathAt(stamp)
end

local function ResolveLifeState(observed,played,mapID,x,y)
    local H=Hero(); if not H then return observed or lastLifeState end
    if observed==nil then return lastLifeState end
    if lastLifeState==nil then lastLifeState=observed;lifeCandidate=nil;lifeCandidateCount=0;return observed end
    if observed==lastLifeState then lifeCandidate=nil;lifeCandidateCount=0;return lastLifeState end
    if lifeCandidate==observed then lifeCandidateCount=lifeCandidateCount+1 else lifeCandidate=observed;lifeCandidateCount=1 end
    if lifeCandidateCount<STATE_CHANGE_CONFIRM_SAMPLES then return lastLifeState end
    local old=lastLifeState
    lastLifeState=observed;lifeCandidate=nil;lifeCandidateCount=0
    if observed=="dead" and tonumber(H.deathActive)~=1 then
        -- Event fallback: if PLAYER_DEAD was missed, the stable API transition still records the death.
        lastLifeState=old
        RecordDeathAt(played)
        return "dead"
    elseif old=="dead" and observed=="ghost" then
        AddStateEvent(STATE_RELEASE,played,mapID,x,y); H.deathActive=nil
    elseif old=="ghost" and observed=="alive" then
        AddStateEvent(STATE_RESURRECT,played,mapID,x,y); H.deathActive=nil
    elseif old=="dead" and observed=="alive" then
        AddStateEvent(STATE_RESURRECT,played,mapID,x,y); H.deathActive=nil
    end
    return lastLifeState
end

local function ProbeTaxi()
    local v=Call("UnitOnTaxi","player")
    if v==true then return true,true end
    if v==false then return false,true end
    return lastTaxi,false
end

local function ResolveTaxi(played,mapID,x,y)
    local observed,known=ProbeTaxi()
    if not known then return lastTaxi,false end
    if lastTaxi==nil then lastTaxi=observed;taxiCandidate=nil;taxiCandidateCount=0;return lastTaxi,true end
    if observed==lastTaxi then taxiCandidate=nil;taxiCandidateCount=0;return lastTaxi,true end
    if taxiCandidate==observed then taxiCandidateCount=taxiCandidateCount+1 else taxiCandidate=observed;taxiCandidateCount=1 end
    if taxiCandidateCount<STATE_CHANGE_CONFIRM_SAMPLES then return lastTaxi,true end
    lastTaxi=observed;taxiCandidate=nil;taxiCandidateCount=0
    AddStateEvent(lastTaxi and STATE_TAXI_START or STATE_TAXI_END,played,mapID,x,y)
    return lastTaxi,true
end

-- ===== Continuity classification and discontinuity handling =====
local function JumpIsImplausible(mode,distance,dt)
    if mode==3 or not distance or distance<=0 then return false end
    -- Distance-only TELEPORT inference has a hard floor. Shorter impossible
    -- relocations are handled separately as continuity-uncertain unless a known
    -- continuous movement ability proves the traversal.
    if distance < RuntimeState.TELEPORT_MIN_GENERIC_YARDS then return false end
    if not dt or dt<=0 then return distance>TELEPORT_MARGIN_YARDS end
    local limit=MAX_SPEED_YARDS_PER_SECOND[mode] or MAX_SPEED_YARDS_PER_SECOND[0]
    return distance > (limit*dt + TELEPORT_MARGIN_YARDS)
end

function RuntimeState.ShortRelocationImplausible(mode,distance,dt,onTaxi)
    if onTaxi==true or mode==3 or not distance or distance<RuntimeState.SHORT_RELOCATION_MIN_YARDS then return false end
    if not dt or dt<=0 then return distance>RuntimeState.SHORT_RELOCATION_MARGIN_YARDS end
    local limit=MAX_SPEED_YARDS_PER_SECOND[mode] or MAX_SPEED_YARDS_PER_SECOND[0]
    return distance > (limit*dt + RuntimeState.SHORT_RELOCATION_MARGIN_YARDS)
end

function RuntimeState.ContinuousHintActive(distance)
    local hint=RuntimeState.pendingContinuousHint
    if not hint then return false end
    local now=SafeNow()
    if now-(hint.at or now)>(hint.ttl or H.CONTINUOUS_TTL_SECONDS) then RuntimeState.pendingContinuousHint=nil;return false end
    if distance and distance>(hint.maxYards or H.CONTINUOUS_MAX_YARDS) then return false end
    return true
end

function RuntimeState.ConsumeContinuousHint(distance)
    if not RuntimeState.ContinuousHintActive(distance) then return false end
    RuntimeState.pendingContinuousHint=nil
    return true
end

function RuntimeState.SustainedMotionCoherent(anchor,candidate,stamp,mapID,x,y)
    if not anchor or not candidate or anchor.mapID~=candidate.mapID or candidate.mapID~=mapID then return false end
    local v1x,v1y=candidate.x-anchor.x,candidate.y-anchor.y
    local v2x,v2y=x-candidate.x,y-candidate.y
    local d1=math.sqrt(v1x*v1x+v1y*v1y)
    local d2=math.sqrt(v2x*v2x+v2y*v2y)
    if d1<RuntimeState.SHORT_RELOCATION_MIN_YARDS or d2<S.SUSTAINED_MOTION_MIN_SECOND_LEG_YARDS then return false end
    local ratio=d2/d1
    if ratio<S.SUSTAINED_DISTANCE_RATIO_MIN or ratio>S.SUSTAINED_DISTANCE_RATIO_MAX then return false end
    local cos=(v1x*v2x+v1y*v2y)/(d1*d2)
    if cos<S.SUSTAINED_DIRECTION_COS_MIN then return false end
    local dt1=math.max(S.MOTION_TIME_EPSILON_SECONDS,(candidate.played or stamp)-(anchor.played or candidate.played or stamp))
    local dt2=math.max(S.MOTION_TIME_EPSILON_SECONDS,stamp-(candidate.played or stamp))
    local speedRatio=(d2/dt2)/(d1/dt1)
    return speedRatio>=S.SUSTAINED_SPEED_RATIO_MIN and speedRatio<=S.SUSTAINED_SPEED_RATIO_MAX
end

local function OpenGap(played,mapID,x,y)
    if positionGapOpen then return end
    AddStateEvent(STATE_GAP_START,played,mapID,x,y)
    positionGapOpen=true
end

local function CloseGap(played,mapID,x,y)
    if not positionGapOpen then return end
    AddStateEvent(STATE_GAP_END,played,mapID,x,y)
    positionGapOpen=false
end

local function RecoverPlayedGap(stamp)
    if not playedUnavailable then return end
    local a=playedUnavailableAnchor or lastRaw or resumeAnchor or LastPointAnchor()
    local startStamp=playedUnavailableStart or (a and a.played) or stamp
    OpenGap(startStamp,a and a.mapID,a and a.x,a and a.y)
    resumeAnchor=a
    resumeReason="unavailable"
    forceResumeAnchor=true
    lastRaw=nil;idleStartRaw=nil
    playedUnavailable=false;playedUnavailableStart=nil;playedUnavailableAnchor=nil
    playedReferenceStamp=nil;playedReferenceNow=nil
end

local function HandleMissingPosition(stamp)
    positionMissingCount=positionMissingCount+1
    if positionMissingCount==1 then
        positionMissingStartPlayed=stamp
        positionMissingAnchor=lastRaw or resumeAnchor or LastPointAnchor()
    end
    if positionMissingCount<POSITION_MISSING_CONFIRM_SAMPLES then return end
    local a=positionMissingAnchor or lastRaw or resumeAnchor or LastPointAnchor()
    OpenGap(positionMissingStartPlayed or stamp,a and a.mapID,a and a.x,a and a.y)
    resumeAnchor=a;resumeReason="unavailable";forceResumeAnchor=true
    lastRaw=nil;idleStartRaw=nil
end

local function ClearMissingPosition()
    positionMissingCount=0
    positionMissingStartPlayed=nil
    positionMissingAnchor=nil
end

local function HandleInstanceUnavailable(stamp)
    if instanceUnknownCount<STATE_CHANGE_CONFIRM_SAMPLES then return end
    local a=instanceUnknownAnchor or lastRaw or resumeAnchor or LastPointAnchor()
    if not a and not LastPoint() then return end
    OpenGap(instanceUnknownStartPlayed or stamp,a and a.mapID,a and a.x,a and a.y)
    resumeAnchor=a;resumeReason="unavailable";forceResumeAnchor=true
    lastRaw=nil;idleStartRaw=nil
end

local function ObservationSuspicious(anchor,stamp,mapID,x,y,mode,onTaxi)
    if not anchor then return nil end
    if mapID~=anchor.mapID then return "world" end
    local dt=stamp-(anchor.played or stamp)
    local moved=DistanceXY(anchor.x,anchor.y,x,y)
    local continuousHint=RuntimeState.ContinuousHintActive(moved)
    -- Charge/Intercept/Feral Charge are evidence for one movement only. Consume
    -- that evidence on the first meaningful displacement so it cannot leak into
    -- a different action (summon/script teleport/etc.) a moment later.
    if continuousHint and moved>=S.CONTINUOUS_HINT_CONSUME_YARDS and not RuntimeState.ShortRelocationImplausible(mode,moved,dt,onTaxi) then
        RuntimeState.pendingContinuousHint=nil
        continuousHint=false
    end
    if onTaxi~=true and JumpIsImplausible(mode,moved,dt) then return "jump" end
    if RuntimeState.ShortRelocationImplausible(mode,moved,dt,onTaxi) then
        local semantic=RuntimeState.SemanticHintActive()
        if semantic and semantic.short==true then return "jump" end
        if continuousHint and RuntimeState.ConsumeContinuousHint(moved) then return nil end
        return "uncertain"
    end
    return nil
end

local function ObservationConsistent(anchor,stamp,mapID,x,y,mode,onTaxi)
    if not anchor or mapID~=anchor.mapID then return false end
    if onTaxi==true then return true end
    local dt=math.max(S.MOTION_TIME_EPSILON_SECONDS,stamp-(anchor.played or stamp))
    local moved=DistanceXY(anchor.x,anchor.y,x,y)
    return not JumpIsImplausible(mode,moved,dt) and not RuntimeState.ShortRelocationImplausible(mode,moved,dt,onTaxi)
end

function RuntimeState.ResumeObservationConsistent(a,stamp,mapID,x,y,mode,onTaxi)
    if not a or a.mapID~=mapID then return false end
    local moved=DistanceXY(a.x,a.y,x,y)
    if onTaxi==true then return true end
    return moved<=RuntimeState.RESUME_PRIME_STABLE_YARDS
end

function RuntimeState.ConfirmResumeObservation(stamp,mapID,x,y,mode,onTaxi)
    if not RuntimeState.resumePrimeRequired then return true end
    local c=RuntimeState.resumePrimeCandidate
    local current={played=stamp,mapID=mapID,x=x,y=y,mode=mode}
    if not c then
        RuntimeState.resumePrimeCandidate={first=current}
        return false
    end
    local first=c.first
    if not first or first.mapID~=mapID then
        RuntimeState.resumePrimeCandidate={first=current}
        return false
    end
    -- A confirmed taxi is explicit transport evidence; two destination-side
    -- observations on the same map are sufficient.
    if onTaxi==true then
        RuntimeState.resumePrimeCandidate=nil;RuntimeState.resumePrimeRequired=false
        return true
    end
    if RuntimeState.ResumeObservationConsistent(first,stamp,mapID,x,y,mode,onTaxi) then
        RuntimeState.resumePrimeCandidate=nil;RuntimeState.resumePrimeRequired=false
        return true
    end
    if not c.second then
        c.second=current
        return false
    end
    if RuntimeState.SustainedMotionCoherent(first,c.second,stamp,mapID,x,y) then
        RuntimeState.resumePrimeCandidate=nil;RuntimeState.resumePrimeRequired=false
        return true
    end
    -- Neither a stable destination nor a coherent three-sample movement was
    -- demonstrated. Throw away the transient chain and prime from the newest point.
    RuntimeState.resumePrimeCandidate={first=current}
    return false
end

local function ConfirmWorldObservation(stamp,mapID,x,y,mode,onTaxi)
    if not lastRaw or positionGapOpen then pendingDiscontinuity=nil;return true,nil,nil end
    local suspiciousKind=ObservationSuspicious(lastRaw,stamp,mapID,x,y,mode,onTaxi)
    local suspicious=suspiciousKind~=nil
    if pendingDiscontinuity then
        -- Taxi state itself is stronger evidence than a speed-based jump candidate.
        if onTaxi==true then
            pendingDiscontinuity=nil
            return true,nil,nil
        end
        if pendingDiscontinuity.kind=="uncertain" then
            local cand=pendingDiscontinuity
            local backToAnchor=(mapID==lastRaw.mapID) and DistanceXY(lastRaw.x,lastRaw.y,x,y)<=S.DISCONTINUITY_SETTLE_YARDS
            if backToAnchor then
                -- One-frame short coordinate spike: discard it completely.
                pendingDiscontinuity=nil
                return true,nil,nil
            end
            local settled=(mapID==cand.mapID) and DistanceXY(cand.x,cand.y,x,y)<=S.DISCONTINUITY_SETTLE_YARDS
            if settled then
                pendingDiscontinuity=nil
                return true,"uncertain",nil
            end
            if RuntimeState.SustainedMotionCoherent(lastRaw,cand,stamp,mapID,x,y) then
                pendingDiscontinuity=nil
                return true,"continuous-special",cand
            end
            -- Still ambiguous: keep observing from the newest candidate.
            pendingDiscontinuity={played=stamp,mapID=mapID,x=x,y=y,mode=mode,kind=suspiciousKind or "uncertain"}
            return false,nil,nil
        end
        if ObservationConsistent(pendingDiscontinuity,stamp,mapID,x,y,mode,onTaxi) then
            local kind=pendingDiscontinuity.kind
            pendingDiscontinuity=nil
            return true,kind,nil
        end
        if not suspicious then
            -- One-frame spike: the world position returned to the prior continuous track.
            pendingDiscontinuity=nil
            return true,nil,nil
        end
        pendingDiscontinuity={played=stamp,mapID=mapID,x=x,y=y,mode=mode,kind=suspiciousKind or "uncertain"}
        return false,nil,nil
    end
    if suspicious then
        pendingDiscontinuity={played=stamp,mapID=mapID,x=x,y=y,mode=mode,kind=suspiciousKind}
        return false,nil,nil
    end
    return true,nil,nil
end

function RuntimeState.CornerObservation(previous,lastObservation,stamp,mapID,x,y,mode)
    if not previous or not lastObservation then return nil end
    if previous[2]~=mapID or previous[5]~=mode or lastObservation.mapID~=mapID or lastObservation.mode~=mode then return nil end
    if (lastObservation.played or 0)<=(previous[1] or 0) or (lastObservation.played or stamp)>=stamp then return nil end
    if DistanceXY(previous[3],previous[4],lastObservation.x,lastObservation.y)<S.CORNER_STORE_MIN_YARDS then return nil end
    if RuntimeState.CurvatureSignificant(previous[3],previous[4],lastObservation.x,lastObservation.y,x,y) then return lastObservation end
    return nil
end

function RuntimeState.StoreReason(previous,stamp,mapID,x,y,mode)
    if not previous then return "initial" end
    if previous[2]~=mapID or previous[5]~=mode then return "mode" end
    local moved=DistanceXY(previous[3],previous[4],x,y)
    if moved<MIN_MOVE_YARDS then return nil end
    local spacing=S.STORE_DISTANCE_YARDS[mode] or S.STORE_DISTANCE_YARDS[0] or MIN_MOVE_YARDS
    if moved>=spacing then return "distance" end
    local interval=S.STORE_MAX_INTERVAL_SECONDS[mode] or S.STORE_MAX_INTERVAL_SECONDS[0] or RDP_KEYFRAME_SECONDS
    if stamp-(previous[1] or stamp)>=interval then return "interval" end
    return nil
end

function RuntimeState.CountStoreDecision(reason)
    if reason=="corner" then RuntimeState.storeCorner=RuntimeState.storeCorner+1
    elseif reason=="distance" then RuntimeState.storeDistance=RuntimeState.storeDistance+1
    elseif reason=="interval" then RuntimeState.storeInterval=RuntimeState.storeInterval+1
    elseif reason=="mode" then RuntimeState.storeMode=RuntimeState.storeMode+1 end
end

-- ===== 4 Hz observation state machine =====
local function Sample(reason)
    if RuntimeState.archiveReadOnly or not db or RuntimeState.worldSuspended then return end
    local stamp,playedStatus=ReadPlayedNow()
    local now=SafeNow()
    if not stamp then MarkPlayedUnavailable(); return end
    if playedStatus=="forward-discontinuity" then MarkPlayedUnavailable() end
    TouchLastPlayed(stamp)
    RecoverPlayedGap(stamp)
    if RuntimeState.collectorFaultPending then
        local a=RuntimeState.collectorFaultAnchor or LastPointAnchor()
        OpenGap(RuntimeState.collectorFaultStartPlayed or (a and a.played) or stamp,a and a.mapID,a and a.x,a and a.y)
        resumeAnchor=a;resumeReason="unavailable";forceResumeAnchor=true
        RuntimeState.resumePrimeRequired=ns.EnableResumePrime==true;RuntimeState.resumePrimeCandidate=nil
        RuntimeState.collectorFaultPending=false;RuntimeState.collectorFaultAnchor=nil;RuntimeState.collectorFaultStartPlayed=nil
    end

    local observedLife=DeathState()
    if observedLife==nil and lastLifeState==nil then return end

    local inside=UpdateInstanceState(stamp)
    if inside==nil then
        HandleInstanceUnavailable(stamp)
        return
    end
    if inside then
        local a=LastPointAnchor()
        local lifeState=ResolveLifeState(observedLife,stamp,a and a.mapID or 0,a and a.x or 0,a and a.y or 0)
        if forceBreakAfterDeath and lifeState=="alive" and LatestDeathWasInside() then SetPendingDeathBreak(false) end
        return
    end

    local effectiveLife=lastLifeState or observedLife
    if effectiveLife=="dead" then
        ResolveLifeState(observedLife,stamp,0,0,0)
        lastRaw=nil;idleStartRaw=nil
        return
    end

    -- World position is observed on every 4 Hz ticker. Movement APIs never gate
    -- whether we look at coordinates; they only qualify what the measured motion means.
    local x,y,mapID,positionSource=CurrentWorldPosition()
    RecordPositionSource(positionSource)
    if not x then
        HandleMissingPosition(stamp)
        return
    end

    local hadGap=positionGapOpen
    ClearMissingPosition()

    local lifeState=ResolveLifeState(observedLife,stamp,mapID,x,y)
    if lifeState=="dead" then lastRaw=nil;idleStartRaw=nil;return end

    local onTaxi,taxiKnown=ResolveTaxi(stamp,mapID,x,y)
    local mode=MovementMode(onTaxi,taxiKnown,lifeState)

    if not RuntimeState.ConfirmResumeObservation(stamp,mapID,x,y,mode,onTaxi) then return end
    if hadGap then CloseGap(stamp,mapID,x,y) end
    local observationAccepted,confirmedDiscontinuity,replayCandidate=ConfirmWorldObservation(stamp,mapID,x,y,mode,onTaxi)
    if not observationAccepted then return end

    if confirmedDiscontinuity=="continuous-special" and replayCandidate then
        local rp=AddPoint(replayCandidate.played,replayCandidate.mapID,replayCandidate.x,replayCandidate.y,5,false,false,BREAK_NONE)
        if rp then lastRaw={x=replayCandidate.x,y=replayCandidate.y,mapID=replayCandidate.mapID,at=now,played=rp[1],mode=5} end
        confirmedDiscontinuity=nil
        mode=5
    end

    local breakBefore=forceBreakAfterDeath
    local breakReason=breakBefore and BREAK_DEATH or BREAK_NONE
    local rawMoved
    local shouldAnchor=forceResumeAnchor or hadGap

    if lastRaw then
        local dt=stamp-lastRaw.played
        rawMoved=(mapID==lastRaw.mapID) and DistanceXY(lastRaw.x,lastRaw.y,x,y) or nil
        if mode==0 and rawMoved and dt>0 and rawMoved/dt>SPECIAL_MOVEMENT_SPEED_YARDS_PER_SECOND then mode=5 end
        if confirmedDiscontinuity=="world" or mapID~=lastRaw.mapID then
            breakBefore,breakReason=true,BREAK_WORLD;RecordSemanticTransition(STATE_WORLD_TRANSITION,stamp,mapID,x,y)
        elseif confirmedDiscontinuity=="jump" then
            breakBefore,breakReason=true,BREAK_TELEPORT;RecordSemanticTransition(STATE_TELEPORT,stamp,mapID,x,y)
        elseif confirmedDiscontinuity=="uncertain" then
            breakBefore,breakReason=true,BREAK_UNCERTAIN
        elseif dt>SAMPLE_GAP_SECONDS and reason~="world-prime" then
            -- We cannot know the shape between these timestamps. Represent the
            -- interval as unknown instead of inventing a long interpolation.
            OpenGap(lastRaw.played,lastRaw.mapID,lastRaw.x,lastRaw.y);CloseGap(stamp,mapID,x,y)
            breakBefore,breakReason=true,BREAK_UNAVAILABLE;shouldAnchor=true
            local gapHint=RuntimeState.SemanticHintActive()
            if gapHint and rawMoved and rawMoved>=RuntimeState.SEMANTIC_TELEPORT_MIN_YARDS then
                RecordSemanticTransition(STATE_TELEPORT,stamp,mapID,x,y)
            end
        else
            local hint=RuntimeState.SemanticHintActive()
            if onTaxi~=true and hint and hint.short==true and rawMoved and rawMoved>=RuntimeState.SEMANTIC_TELEPORT_MIN_YARDS then
                breakBefore,breakReason=true,BREAK_TELEPORT;RecordSemanticTransition(STATE_TELEPORT,stamp,mapID,x,y)
            elseif onTaxi~=true and JumpIsImplausible(mode,rawMoved,dt) then
                breakBefore,breakReason=true,BREAK_TELEPORT;RecordSemanticTransition(STATE_TELEPORT,stamp,mapID,x,y)
            end
        end
    elseif resumeAnchor then
        local sameMap=mapID==resumeAnchor.mapID
        local moved=sameMap and DistanceXY(resumeAnchor.x,resumeAnchor.y,x,y) or nil
        local dt=math.max(S.MOTION_TIME_EPSILON_SECONDS,stamp-(resumeAnchor.played or stamp))
        if mode==0 and moved and moved/dt>SPECIAL_MOVEMENT_SPEED_YARDS_PER_SECOND then mode=5 end
        if not sameMap then
            breakBefore,breakReason=true,BREAK_WORLD;RecordSemanticTransition(STATE_WORLD_TRANSITION,stamp,mapID,x,y)
        elseif resumeReason=="unavailable" then
            breakBefore,breakReason=true,BREAK_UNAVAILABLE
        elseif forceBreakAfterDeath then
            breakBefore,breakReason=true,BREAK_DEATH
        elseif resumeReason=="instance" then
            -- No exterior polyline may bridge time spent inside an instance/BG/tram.
            breakBefore,breakReason=true,BREAK_INSTANCE_EXIT
            ns.Metadata.AddContextSnapshot(Hero(),C.Context.INSTANCE_EXIT,stamp,mapID,x,y,0)
        elseif (resumeReason=="login" or resumeReason=="load" or resumeReason=="login-or-reload") and mode~=3 then
            -- A new game session cannot prove continuity with the last persisted point.
            breakBefore,breakReason=true,BREAK_RESUME
        elseif resumeReason=="reload" and dt>SAMPLE_GAP_SECONDS and mode~=3 then
            breakBefore,breakReason=true,BREAK_RESUME
        elseif resumeReason=="world" and mode~=3 then
            -- A loading-screen boundary hides geometry. A spell hint bound to this
            -- exact boundary may explain the relocation, but never removes the break.
            local boundHint=RuntimeState.SemanticHintActive()
            if boundHint and boundHint.boundWorld then
                breakBefore,breakReason=true,BREAK_TELEPORT
                RecordSemanticTransition(STATE_TELEPORT,stamp,mapID,x,y)
            else
                breakBefore,breakReason=true,BREAK_RESUME
            end
        elseif moved and (((mode~=3 and mode~=5) and moved>RESUME_CONTINUITY_YARDS) or JumpIsImplausible(mode,moved,dt)) then
            breakBefore=true
            if resumeReason=="instance" then breakReason=BREAK_INSTANCE_EXIT else breakReason=BREAK_RESUME end
            if breakReason==BREAK_RESUME then RecordSemanticTransition(STATE_TELEPORT,stamp,mapID,x,y) end
        end
        if pendingTramExit then AddStateEvent(STATE_TRAM_END,stamp,mapID,x,y);pendingTramExit=false end
        rawMoved=moved; shouldAnchor=true
        resumeAnchor=nil;resumeReason=nil;forceResumeAnchor=false
    elseif forceResumeAnchor and not resumeAnchor then
        shouldAnchor=true
        if resumeReason=="instance-no-anchor" then
            breakBefore,breakReason=true,BREAK_INSTANCE_EXIT
            ns.Metadata.AddContextSnapshot(Hero(),C.Context.INSTANCE_EXIT,stamp,mapID,x,y,0)
            if pendingTramExit then AddStateEvent(STATE_TRAM_END,stamp,mapID,x,y);pendingTramExit=false end
        elseif resumeReason=="unavailable" then
            breakBefore,breakReason=true,BREAK_UNAVAILABLE
        elseif not LastPoint() then
            breakBefore,breakReason=true,BREAK_INITIAL
        else
            breakBefore,breakReason=true,BREAK_RESUME
        end
        resumeReason=nil;forceResumeAnchor=false
    elseif not LastPoint() then
        breakBefore,breakReason=true,BREAK_INITIAL
    end

    -- Runtime-only observability: this is the last accepted outdoor observation,
    -- regardless of whether adaptive persistence keeps it. It never changes the
    -- SavedVariables schema and lets /hp check distinguish observation from storage.
    RuntimeState.lastObservedPlayed=stamp
    RuntimeState.lastObservedMapID=mapID
    RuntimeState.lastObservedX=x
    RuntimeState.lastObservedY=y
    RuntimeState.lastObservedMode=mode

    -- Record one semantic map snapshot per runtime session. It is deliberately
    -- sparse: geometry remains in world yards, while this snapshot gives tools
    -- and integrations enough map context to explain where the session began.
    if not RuntimeState.sessionContextRecorded then
        if ns.Metadata.AddContextSnapshot(Hero(),C.Context.SESSION,stamp,mapID,x,y,0) then
            RuntimeState.sessionContextRecorded=true
        end
    end

    local previous=LastPoint()

    -- Preserve both ends of a genuine idle hold.
    if not breakBefore and lastRaw and rawMoved then
        if rawMoved<=RAW_IDLE_YARDS then
            if not idleStartRaw then
                idleStartRaw={x=lastRaw.x,y=lastRaw.y,mapID=lastRaw.mapID,at=lastRaw.at,played=lastRaw.played,mode=lastRaw.mode}
                ProtectOrInsertAnchor(idleStartRaw);previous=LastPoint()
            end
        elseif idleStartRaw and (lastRaw.played-idleStartRaw.played)>=IDLE_HOLD_SECONDS then
            AddPoint(lastRaw.played,lastRaw.mapID,lastRaw.x,lastRaw.y,lastRaw.mode,false,true,BREAK_NONE)
            previous=LastPoint();idleStartRaw=nil
        else idleStartRaw=nil end
    else idleStartRaw=nil end

    -- A resume point is always written and protected, even at zero distance.
    if shouldAnchor then
        local p=AddPoint(stamp,mapID,x,y,mode,breakBefore,true,breakReason)
        if p then
            lastRaw={x=x,y=y,mapID=mapID,at=now,played=p[1],mode=mode}
            SetPendingDeathBreak(false)
            -- A one-shot resume request must never leak into later samples.
            forceResumeAnchor=false
            if resumeAnchor==nil then resumeReason=nil end
        end
        return
    end

    -- If the last 4 Hz observation is the geometric corner, persist that actual
    -- middle observation before deciding whether the current point is also needed.
    -- Storing the post-turn point instead would shift a 90-degree corner diagonally.
    if not breakBefore then
        local corner=RuntimeState.CornerObservation(previous,lastRaw,stamp,mapID,x,y,mode)
        if corner then
            local cp=AddPoint(corner.played,corner.mapID,corner.x,corner.y,corner.mode,false,false,BREAK_NONE)
            if cp then RuntimeState.CountStoreDecision("corner");previous=cp end
        end
    end

    local storeReason=breakBefore and "break" or RuntimeState.StoreReason(previous,stamp,mapID,x,y,mode)
    if not storeReason then
        RuntimeState.storeSkipped=RuntimeState.storeSkipped+1
        lastRaw={x=x,y=y,mapID=mapID,at=now,played=stamp,mode=mode}
        SetPendingDeathBreak(false)
        return
    end

    local p=AddPoint(stamp,mapID,x,y,mode,breakBefore,false,breakReason)
    if p then
        RuntimeState.CountStoreDecision(storeReason)
        lastRaw={x=x,y=y,mapID=mapID,at=now,played=p[1],mode=mode}
        SetPendingDeathBreak(false)
    end
end

local function ReconstructGapState(events)
    local open=false
    for _,e in ipairs(events or {}) do
        if e[1]==EVENT_STATE then
            if e[2]==STATE_GAP_START then open=true elseif e[2]==STATE_GAP_END then open=false end
        end
    end
    return open
end

local function HasDeathEvent()
    local H=Hero();if not H then return false end
    for i=#H.events,1,-1 do if H.events[i][1]==EVENT_DEATH then return true end end
    return false
end

-- ===== Character ownership, schema and resume =====
local function CurrentOwnerKey()
    local guid=Call("UnitGUID","player")
    local guidKey=type(guid)=="string" and guid~="" and ("guid:"..guid) or nil
    local name,realm=Call("UnitFullName","player")
    if type(name)~="string" or name=="" then name=Call("UnitName","player") end
    if type(realm)~="string" or realm=="" then realm=Call("GetNormalizedRealmName") or Call("GetRealmName") end
    local nameKey
    if type(name)=="string" and name~="" and type(realm)=="string" and realm~="" then nameKey="name:"..name.."@"..realm end
    return guidKey or nameKey,nameKey,guidKey
end

local function SelectOwnerHero()
    if not db then return nil,false end
    if db.heroPath~=nil and type(db.heroPath)~="table" then
        db.recoveryRootQuarantine=type(db.recoveryRootQuarantine)=="table" and db.recoveryRootQuarantine or {}
        db.recoveryRootQuarantine[#db.recoveryRootQuarantine+1]={kind="heroPath-root",capturedType=type(db.heroPath),payload=RuntimeState.RecoveryCopy(db.heroPath)}
    end
    local H=type(db.heroPath)=="table" and db.heroPath or {};db.heroPath=H
    local key,nameKey,guidKey=CurrentOwnerKey()
    if not key then return H,false end
    if type(H.ownerKey)~="string" or H.ownerKey=="" then
        H.ownerKey=key;H.ownerNameKey=nameKey;return H,false
    end
    -- A character may expose only name@realm during PLAYER_LOGIN and its GUID a
    -- moment later at PLAYER_ENTERING_WORLD. Upgrade that identity in place.
    if H.ownerKey==key or (nameKey and (H.ownerKey==nameKey or H.ownerNameKey==nameKey)) then
        if guidKey then H.ownerKey=guidKey end
        if nameKey then H.ownerNameKey=nameKey end
        return H,false
    end

    local inactive=type(db.heroPathInactiveProfiles)=="table" and db.heroPathInactiveProfiles or {}
    db.heroPathInactiveProfiles=inactive
    inactive[H.ownerKey]=H
    local target=inactive[key]
    local targetKey=key
    if type(target)~="table" and nameKey then
        target=inactive[nameKey];targetKey=nameKey
        if type(target)~="table" then
            for k,v in pairs(inactive) do
                if type(v)=="table" and v.ownerNameKey==nameKey then target=v;targetKey=k;break end
            end
        end
    end
    if type(target)=="table" then inactive[targetKey]=nil else target={} end
    target.ownerKey=guidKey or key
    target.ownerNameKey=nameKey
    db.heroPath=target
    return target,true
end

local function ConfigureHero(H)
    BuildChunkedStorage(H)
    H.events=SanitizeEvents(H.events)
    local semantic={}
    local semanticEntries=RuntimeState.NumericEntries(H.semanticEvents)
    local expectedSemanticIndex=1
    for row=1,#semanticEntries do
        local key,e=semanticEntries[row][1],semanticEntries[row][2]
        if key~=expectedSemanticIndex then RuntimeState.Quarantine(H,"semantic-events","numeric-index-gap",nil,{expected=expectedSemanticIndex,found=key}) end
        expectedSemanticIndex=key+1
        if type(e)=="table" and ValidPlayed(e[1]) and SafeInt(e[2],0,MAX_ORDER) and SafeInt(e[3],RuntimeState.SEMANTIC_HEARTH,RuntimeState.SEMANTIC_TELEPORT_SPELL) and SafeInt(e[4],0,MAX_WORLD_ID) and SafeInt(e[5],0,MAX_WORLD_ID) then
            local ex,ey=tonumber(e[6]) or 0,tonumber(e[7]) or 0
            local known=e[8]==nil and (ValidWorldCoordinates(ex,ey) and not (tonumber(e[5])==0 and ex==0 and ey==0) and 1 or 0) or (tonumber(e[8])==1 and 1 or 0)
            if known==1 and not ValidWorldCoordinates(ex,ey) then known,ex,ey=0,0,0 end
            if known==0 then ex,ey=0,0 end
            local row={e[1],e[2],e[3],e[4],e[5],ex,ey,known}
            local transitionId=SafeInt(e[9],1,L.MAX_TRANSITION_ID);if transitionId then row[9]=transitionId end
            semantic[#semantic+1]=row
        elseif e~=nil then
            RuntimeState.Quarantine(H,"semantic-event","invalid-semantic-event",e,{index=key})
        end
    end
    table.sort(semantic,function(a,b) return (a[2] or 0)<(b[2] or 0) end)
    H.semanticEvents=semantic
    local contexts,maxContextId=ns.Metadata.SanitizeContextEvents(H,function(kind,reason,payload,details) RuntimeState.Quarantine(H,kind,reason,payload,details) end)
    H.contextEvents=contexts
    H.contextSequence=math.max(SafeInt(H.contextSequence,0,MAX_ORDER) or 0,maxContextId or 0)
    local transitions,maxTransitionId=ns.Metadata.SanitizeTransitions(H,MIN_STATE_CODE,MAX_STATE_CODE,function(kind,reason,payload,details) RuntimeState.Quarantine(H,kind,reason,payload,details) end)
    H.transitions=transitions
    H.transitionSequence=math.max(SafeInt(H.transitionSequence,0,L.MAX_TRANSITION_ID) or 0,maxTransitionId or 0)
    H.schema=FORMAT_VERSION
    H.transportInference="raw-position-only"
    H.collectionPolicy="fixed-world-position-4hz-observe+curvature-aware-adaptive-store"
    H.storagePolicy="HP1-sparse-delta-varint+RDP-3yd+curvature-preserve+20s-keyframes"
    H.compactionPolicy="time-sliced-live+full-clean-logout+transactional-retry"
    H.recoveryPolicy="fail-closed+quarantine+strict-bits+hole-aware+history-authoritative-clock"
    H.positionSourcePolicy="C_Map-primary+UnitPosition-auto-XY/YX-calibrated-crosscheck-with-safe-fallback"
    H.resumePrimePolicy="stable-pair-or-coherent-three-sample-motion-after-world-boundary"
    H.genericTeleportMinYards=RuntimeState.TELEPORT_MIN_GENERIC_YARDS
    H.shortRelocationPolicy="cut-unexplained-rapid-short-moves;preserve-known-continuous-gap-closers"
    H.sampleSeconds=SAMPLE_SECONDS
    H.sampleGapSeconds=SAMPLE_GAP_SECONDS
    H.instanceTracePolicy="no-interior-polyline;entry-exit-duration-events-only"
    H.adaptiveSampling=1
    H.sampleFast=SAMPLE_FAST_SECONDS;H.sampleMoving=SAMPLE_MOVING_SECONDS;H.sampleIdle=SAMPLE_IDLE_SECONDS
    local _,classFile=Call("UnitClass","player"); if type(classFile)=="string" and classFile~="" then H.playerClass=string.lower(classFile) end
    local faction=Call("UnitFactionGroup","player"); if type(faction)=="string" and faction~="" then H.playerFaction=string.lower(faction) end
    local clientVersion,clientBuild,clientDate,clientInterface=Call("GetBuildInfo")
    if type(clientVersion)=="string" then H.clientVersion=clientVersion end
    if type(clientBuild)=="string" or type(clientBuild)=="number" then H.clientBuild=tostring(clientBuild) end
    if type(clientDate)=="string" then H.clientBuildDate=clientDate end
    local interfaceNumber=SafeInt(Num(clientInterface),0,MAX_WORLD_ID);if interfaceNumber then H.clientInterface=interfaceNumber end
    H.spellRegistryPolicy="build-tagged-advisory;geometry-is-authoritative;unknown-relocations-break-uncertain"
    local pd=type(H.positionDiagnostics)=="table" and H.positionDiagnostics or {}
    H.positionDiagnostics={
        dual=SafeInt(pd.dual,0) or 0,cmap=SafeInt(pd.cmap,0) or 0,unit=SafeInt(pd.unit,0) or 0,
        mismatch=SafeInt(pd.mismatch,0) or 0,missing=SafeInt(pd.missing,0) or 0,
        lastSource=type(pd.lastSource)=="string" and pd.lastSource or nil,
        unitOrder=(pd.unitOrder=="XY" or pd.unitOrder=="YX") and pd.unitOrder or nil,
        calibrationResets=SafeInt(pd.calibrationResets,0) or 0,
        calibrationAmbiguous=SafeInt(pd.calibrationAmbiguous,0) or 0,
    }
    RebuildMetadata(H)
    H.compressionRecoveryNeeded=nil
    H.compactions=SafeInt(H.compactions,0) or 0
end

local function ResetRuntimeFromHero(resumeWhy)
    local H=Hero();if not H then return end
    lastRaw=nil;idleStartRaw=nil
    currentInstanceEventIndex=FindOpenInstanceEvent()
    positionGapOpen=ReconstructGapState and ReconstructGapState(H.events) or false
    resumeAnchor=LastPointAnchor();resumeReason=resumeWhy or "load";forceResumeAnchor=true
    pendingDiscontinuity=nil
    positionMissingCount=0;positionMissingStartPlayed=nil;positionMissingAnchor=nil
    playedUnavailable=false;playedUnavailableStart=nil;playedUnavailableAnchor=nil
    instanceStableSignature=nil;instanceCandidateSignature=nil;instanceCandidateCount=0
    instanceUnknownCount=0;instanceUnknownStartPlayed=nil;instanceUnknownAnchor=nil
    taxiCandidate=nil;taxiCandidateCount=0
    lifeCandidate=nil;lifeCandidateCount=0
    pendingTramExit=false
    RuntimeState.pendingContinuousHint=nil
    RuntimeState.resumePrimeRequired=false;RuntimeState.resumePrimeCandidate=nil
    RuntimeState.worldSuspended=ns.RequireWorldEntryBeforeSampling==true
    RuntimeState.collectorFaultPending=false;RuntimeState.collectorFaultAnchor=nil;RuntimeState.collectorFaultStartPlayed=nil
    RuntimeState.lastObservedPlayed=nil;RuntimeState.lastObservedMapID=nil;RuntimeState.lastObservedX=nil;RuntimeState.lastObservedY=nil;RuntimeState.lastObservedMode=nil
    RuntimeState.sessionContextRecorded=false

    local currentLife=DeathState()
    local persistedPending=tonumber(H.pendingDeathBreak)==1
    if currentLife=="dead" then
        H.deathActive=1;forceBreakAfterDeath=true
    elseif currentLife=="ghost" then
        H.deathActive=nil;forceBreakAfterDeath=persistedPending or HasDeathEvent()
    elseif currentLife=="alive" then
        H.deathActive=nil;forceBreakAfterDeath=persistedPending
    else
        forceBreakAfterDeath=persistedPending
        if tonumber(H.deathActive)==1 then currentLife="dead" end
    end
    H.pendingDeathBreak=forceBreakAfterDeath and 1 or nil
    lastLifeState=currentLife
    local taxi=Call("UnitOnTaxi","player")
    if taxi==true then lastTaxi=true elseif taxi==false then lastTaxi=false else lastTaxi=nil end
end

local function PrimeWorldState(generation,attempt)
    if generation~=worldPulseGeneration or not db then return end
    RuntimeState.SafeSample("world-prime")
    if (positionMissingCount>0 or RuntimeState.resumePrimeRequired) and attempt<WORLD_EVENT_RETRIES and C_Timer and type(C_Timer.After)=="function" then
        C_Timer.After(POSITION_RETRY_SECONDS,function() PrimeWorldState(generation,attempt+1) end)
    end
end

local function EnsureOwnerRuntime(resumeWhy)
    if RuntimeState.archiveReadOnly then return false end
    local H,changed=SelectOwnerHero()
    if changed then
        ConfigureHero(H)
        ResetRuntimeFromHero(resumeWhy or "login")
    end
    return changed
end

local function PrepareResume(isInitialLogin,isReloadingUi)
    if RuntimeState.archiveReadOnly or not db then return end
    local why
    if isReloadingUi==true then why="reload"
    elseif isInitialLogin==true then why="login"
    elseif firstWorldEvent and isInitialLogin==nil and isReloadingUi==nil then why="login-or-reload"
    else why="world" end
    firstWorldEvent=false
    RuntimeState.worldSuspended=false
    RuntimeState.resumePrimeRequired=ns.EnableResumePrime==true
    RuntimeState.resumePrimeCandidate=nil
    RuntimeState.MarkSemanticDestinationEntered()

    EnsureOwnerRuntime(why)
    -- EnsureOwnerRuntime may have switched/upgraded the owner and reset runtime.
    -- PLAYER_ENTERING_WORLD is authoritative: sampling is allowed after this point.
    RuntimeState.worldSuspended=false
    RuntimeState.resumePrimeRequired=ns.EnableResumePrime==true
    RuntimeState.resumePrimeCandidate=nil
    local stamp=ReadPlayedNow();if not stamp then MarkPlayedUnavailable() end
    lastRaw=nil;idleStartRaw=nil;resumeAnchor=LastPointAnchor();resumeReason=why;forceResumeAnchor=true
    pendingDiscontinuity=nil
    worldPulseGeneration=worldPulseGeneration+1
    local generation=worldPulseGeneration
    if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(0,function() PrimeWorldState(generation,1) end)
    else PrimeWorldState(generation,1) end
end

local function StatePulse()
    if RuntimeState.archiveReadOnly then return end
    if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(0,function() RuntimeState.SafeSample("event") end)
    else RuntimeState.SafeSample("event") end
end

local function SpellSucceeded(...)
    if RuntimeState.archiveReadOnly then return end
    local argc=select("#",...)
    local okUnit,isPlayer=pcall(function(v) return v=="player" end,select(1,...))
    if not okUnit or not isPlayer then return end
    for i=2,argc do
        -- Num() is itself protected; restricted/secret event payloads degrade to
        -- "no semantic hint" instead of aborting the listener. Geometry remains truth.
        -- select('#', ...) is deliberate: nil holes in fork-specific event payloads
        -- must not hide a later spellID.
        local id=SafeInt(Num(select(i,...)),0,MAX_WORLD_ID)
        if id and HEARTHSTONE_SPELL_IDS[id] then
            local played=ReadPlayedNow();local x,y,mapID=CurrentWorldPosition();local anchor=LastPointAnchor()
            pendingTransportHint={kind="hearth",spellID=id,at=SafeNow(),played=played,short=false,
                departure={played=played,mapID=mapID,x=x,y=y,order=anchor and anchor.order or 0},departureContext=ns.Metadata.ReadMapContext()}
            return
        elseif id and RuntimeState.TELEPORT_SPELL_IDS[id] then
            local short=RuntimeState.TELEPORT_SPELL_IDS[id]=="short"
            local played=ReadPlayedNow();local x,y,mapID=CurrentWorldPosition();local anchor=LastPointAnchor()
            pendingTransportHint={kind="teleport",spellID=id,at=SafeNow(),played=played,short=short,
                departure={played=played,mapID=mapID,x=x,y=y,order=anchor and anchor.order or 0},departureContext=ns.Metadata.ReadMapContext()}
            return
        elseif id and RuntimeState.CONTINUOUS_MOVEMENT_SPELL_IDS[id] then
            RuntimeState.pendingContinuousHint={spellID=id,at=SafeNow(),ttl=H.CONTINUOUS_TTL_SECONDS,maxYards=H.CONTINUOUS_MAX_YARDS}
            return
        end
    end
end

-- ===== Supervision, watchdog and public diagnostics =====
function RuntimeState.MarkCollectorFault(err)
    RuntimeState.sampleErrors=RuntimeState.sampleErrors+1
    RuntimeState.lastSampleError=tostring(err or "unknown")
    local H=Hero()
    RuntimeState.collectorFaultPending=true
    RuntimeState.collectorFaultAnchor=lastRaw or resumeAnchor or LastPointAnchor()
    RuntimeState.collectorFaultStartPlayed=H and ValidPlayed(H.lastPlayed) and tonumber(H.lastPlayed) or nil
    lastRaw=nil;idleStartRaw=nil;pendingDiscontinuity=nil
end

function RuntimeState.SafeSample(reason)
    if RuntimeState.archiveReadOnly then return false end
    RuntimeState.sampleAttempts=RuntimeState.sampleAttempts+1
    RuntimeState.lastTickerBeat=SafeNow()
    local profileStart=type(debugprofilestop)=="function" and debugprofilestop() or nil
    local ok,err=pcall(Sample,reason)
    if profileStart then
        local elapsed=debugprofilestop()-profileStart
        if elapsed>=0 then
            RuntimeState.sampleProfileCount=RuntimeState.sampleProfileCount+1
            RuntimeState.sampleProfileTotalMs=RuntimeState.sampleProfileTotalMs+elapsed
            RuntimeState.sampleProfileLastMs=elapsed
            if elapsed>RuntimeState.sampleProfileMaxMs then RuntimeState.sampleProfileMaxMs=elapsed end
        end
    end
    if ok then RuntimeState.sampleSuccesses=RuntimeState.sampleSuccesses+1;return true end
    RuntimeState.MarkCollectorFault(err)
    return false
end

function RuntimeState.CancelTicker()
    if type(ticker)=="table" and type(ticker.Cancel)=="function" then pcall(ticker.Cancel,ticker) end
    ticker=nil
end

local function StartTicker(force)
    if RuntimeState.archiveReadOnly then return false end
    if ticker and not force then return false end
    if force then RuntimeState.CancelTicker() end
    RuntimeState.tickerGeneration=RuntimeState.tickerGeneration+1
    local generation=RuntimeState.tickerGeneration
    if C_Timer and type(C_Timer.NewTicker)=="function" then
        ticker=C_Timer.NewTicker(SAMPLE_SECONDS,function()
            if generation~=RuntimeState.tickerGeneration then return end
            RuntimeState.SafeSample("ticker")
        end)
    elseif ns.WrappedTick then
        ns.WrappedTick(function() if generation==RuntimeState.tickerGeneration then RuntimeState.SafeSample("ticker") end end)
        ticker=true
    else return false end
    RuntimeState.lastTickerBeat=SafeNow()
    return true
end

function RuntimeState.EnsureTickerHealthy()
    if RuntimeState.archiveReadOnly or not db or RuntimeState.worldSuspended then return end
    local now=SafeNow()
    if not ticker or not RuntimeState.lastTickerBeat or now-RuntimeState.lastTickerBeat>RuntimeState.WATCHDOG_STALE_SECONDS then
        if ticker then RuntimeState.MarkCollectorFault("ticker-stalled") end
        StartTicker(true)
    end
    local H=Hero()
    if H and type(H.tail)=="table" and #H.tail>=RAW_TAIL_TRIGGER and not compressionScheduled and not RuntimeState.compressionJob then
        RuntimeState.ScheduleCompression()
    end
end

function RuntimeState.StartWatchdog()
    if RuntimeState.archiveReadOnly or ns.EnableCollectorWatchdog~=true then return end
    if RuntimeState.watchdogTicker or not C_Timer or type(C_Timer.NewTicker)~="function" then return end
    RuntimeState.watchdogTicker=C_Timer.NewTicker(RuntimeState.WATCHDOG_SECONDS,function()
        local ok,err=pcall(RuntimeState.EnsureTickerHealthy)
        if not ok then RuntimeState.MarkCollectorFault(err) end
    end)
end

function RuntimeState.SuspendWorld(reason)
    if RuntimeState.archiveReadOnly or not db then return end
    RuntimeState.BindSemanticHintToWorldBoundary()
    local stamp=ReadPlayedNow()
    local a=lastRaw or LastPointAnchor()
    if lastRaw then ProtectOrInsertAnchor(lastRaw) end
    if stamp then OpenGap(stamp,a and a.mapID,a and a.x,a and a.y) end
    resumeAnchor=a
    resumeReason=reason or "world"
    forceResumeAnchor=true
    RuntimeState.resumePrimeRequired=ns.EnableResumePrime==true;RuntimeState.resumePrimeCandidate=nil
    RuntimeState.worldSuspended=true
    lastRaw=nil;idleStartRaw=nil;pendingDiscontinuity=nil
end

ns.Listen("PLAYER_ENTERING_WORLD",PrepareResume)
ns.Listen("PLAYER_LEAVING_WORLD",function() RuntimeState.SuspendWorld("world") end)
ns.Listen("PLAYER_LOGIN",function() EnsureOwnerRuntime("login") end)
ns.Listen("ZONE_CHANGED_NEW_AREA",StatePulse)
ns.Listen("ZONE_CHANGED",StatePulse)
ns.Listen("ZONE_CHANGED_INDOORS",StatePulse)
ns.Listen("PLAYER_ALIVE",StatePulse)
ns.Listen("PLAYER_UNGHOST",StatePulse)
ns.Listen("PLAYER_DEAD",RecordDeath)
ns.Listen("UNIT_SPELLCAST_SUCCEEDED",SpellSucceeded)
ns.Listen("PLAYER_LOGOUT",function()
    if RuntimeState.archiveReadOnly then return end
    local ok,err=pcall(RuntimeState.FlushForSave)
    if not ok then RuntimeState.lastSampleError="save-compaction: "..tostring(err) end
end)

ns.OnLoad(function(saved)
    db=type(saved)=="table" and saved or {}
    local futureSchema=ns.Metadata.DetectFutureSchema(db)
    if C.Compatibility.FUTURE_SCHEMA_READ_ONLY and futureSchema then
        RuntimeState.archiveReadOnly=true
        RuntimeState.archiveSchema=futureSchema
        RuntimeState.archiveReason="future-schema"
        RuntimeState.worldSuspended=true
        return
    end
    RuntimeState.archiveReadOnly=false
    RuntimeState.archiveSchema=nil
    RuntimeState.archiveReason=nil
    local profile=SelectOwnerHero()
    ConfigureHero(profile)
    if C.Compatibility.WRITE_ROOT_SCHEMA then db.schema=FORMAT_VERSION end
    ResetRuntimeFromHero("load")
    StartTicker()
    RuntimeState.StartWatchdog()
end)

ns.GetCollectorHealth=function()
    local H=Hero()
    local stored=LastPoint()
    local tail=H and type(H.tail)=="table" and H.tail or nil
    local tailFirst=tail and tail[1] or nil
    local tailLast=tail and tail[#tail] or nil
    return {
        sampleAttempts=RuntimeState.sampleAttempts,sampleSuccesses=RuntimeState.sampleSuccesses,sampleErrors=RuntimeState.sampleErrors,lastSampleError=RuntimeState.lastSampleError,
        lastTickerBeat=RuntimeState.lastTickerBeat,worldSuspended=RuntimeState.worldSuspended,positionGapOpen=positionGapOpen,resumePrimeRequired=RuntimeState.resumePrimeRequired,
        playedUnavailable=playedUnavailable,instanceUnknownCount=instanceUnknownCount,positionMissingCount=positionMissingCount,
        pendingDiscontinuity=pendingDiscontinuity and pendingDiscontinuity.kind or nil,
        sampleLastMs=RuntimeState.sampleProfileLastMs,sampleMaxMs=RuntimeState.sampleProfileMaxMs,
        sampleAverageMs=RuntimeState.sampleProfileCount>0 and (RuntimeState.sampleProfileTotalMs/RuntimeState.sampleProfileCount) or 0,
        storeDistance=RuntimeState.storeDistance,storeCorner=RuntimeState.storeCorner,storeInterval=RuntimeState.storeInterval,storeMode=RuntimeState.storeMode,storeSkipped=RuntimeState.storeSkipped,
        lastObservedPlayed=RuntimeState.lastObservedPlayed,lastObservedMapID=RuntimeState.lastObservedMapID,lastObservedX=RuntimeState.lastObservedX,lastObservedY=RuntimeState.lastObservedY,lastObservedMode=RuntimeState.lastObservedMode,
        lastStoredPlayed=stored and stored[1] or nil,storeLagSeconds=(RuntimeState.lastObservedPlayed and stored and math.max(0,RuntimeState.lastObservedPlayed-stored[1])) or nil,
        tailSpanSeconds=(tailFirst and tailLast and math.max(0,(tailLast[1] or 0)-(tailFirst[1] or 0))) or 0,
        compressionSlices=RuntimeState.compressionSlices,compressionLastSliceMs=RuntimeState.compressionLastSliceMs,compressionMaxSliceMs=RuntimeState.compressionMaxSliceMs,
        compressionActive=RuntimeState.compressionJob~=nil,compressionErrors=tonumber(RuntimeState.compressionErrors) or 0,lastCompressionError=RuntimeState.lastCompressionError,
        compressionRecoveryNeeded=H and H.compressionRecoveryNeeded==1 or false,
        positionDiagnostics=H and H.positionDiagnostics or nil,
        archiveReadOnly=RuntimeState.archiveReadOnly==true,archiveSchema=RuntimeState.archiveSchema,archiveReason=RuntimeState.archiveReason,
    }
end
ns.GetStorageStats=function()
    local H=Hero()
    if not H then return nil end
    local bytes,points,validChunks=0,0,0
    for _,ch in ipairs(type(H.chunks)=="table" and H.chunks or {}) do
        if EncodedChunkValid(ch) then
            validChunks=validChunks+1;points=points+(tonumber(ch[3]) or 0);bytes=bytes+#(ch[2] or "")
        end
    end
    local q=type(H.recoveryQuarantine)=="table" and H.recoveryQuarantine or {}
    local qEntries=type(q.entries)=="table" and #q.entries or 0
    return {format=H.storagePolicy or "mixed",chunks=validChunks,packedPoints=points,encodedPayloadBytes=bytes,tailPoints=type(H.tail)=="table" and #H.tail or 0,events=type(H.events)=="table" and #H.events or 0,semanticEvents=type(H.semanticEvents)=="table" and #H.semanticEvents or 0,transitions=type(H.transitions)=="table" and #H.transitions or 0,contexts=type(H.contextEvents)=="table" and #H.contextEvents or 0,quarantineEntries=qEntries,compressionErrors=tonumber(RuntimeState.compressionErrors) or 0,archiveReadOnly=RuntimeState.archiveReadOnly==true}
end
function RuntimeState.EstimateSerializedBytes(value,seen)
    local t=type(value)
    if t=="nil" then return 3 elseif t=="boolean" then return value and 4 or 5 elseif t=="number" then return #tostring(value) elseif t=="string" then return #value+2 elseif t~="table" then return 0 end
    seen=seen or {};if seen[value] then return 0 end;seen[value]=true
    local n=2
    for k,v in pairs(value) do n=n+4+RuntimeState.EstimateSerializedBytes(k,seen)+RuntimeState.EstimateSerializedBytes(v,seen) end
    seen[value]=nil;return n
end
ns.EstimateSavedVariablesBytes=function() return db and RuntimeState.EstimateSerializedBytes(db) or 0 end
ns.DecodeHeroPathChunk=function(ch) return RuntimeState.DecodeChunk(ch) end
ns.GetHeroPathExport=function() return db and db.heroPath or nil end
ns.GetHeroPathExportSnapshot=function() return db and RuntimeState.RecoveryCopy(db.heroPath) or nil end
ns.GetArchiveState=function() return RuntimeState.archiveReadOnly==true,RuntimeState.archiveSchema,RuntimeState.archiveReason end
