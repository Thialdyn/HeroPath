-- Hero’sPath semantic metadata layer.
-- Owns low-frequency map context, correlated transitions and compatibility checks.
-- The 4 Hz movement hot path remains in HeroPath.lua; this module is event-oriented.
local ADDON_NAME, ns = ...
local C = assert(ns.Contract, "HeroPath Contract.lua must load before Metadata.lua")
local D = assert(ns.DataModel, "HeroPath DataModel.lua must load before Metadata.lua")
local L, TR, CTX = C.Limits, C.Transition, C.Context

local M = {}
local MAX_WORLD_ID = L.MAX_WORLD_ID
local MAX_ORDER = L.MAX_ORDER
local MAX_TRANSITION_ID = L.MAX_TRANSITION_ID
local MAX_CONTEXT_TEXT = L.MAX_CONTEXT_TEXT
local FORMAT_VERSION = C.SAVED_VARIABLES_SCHEMA

local function safeText(value)
    if type(value) ~= "string" or value == "" then return nil end
    if #value > MAX_CONTEXT_TEXT then return value:sub(1, MAX_CONTEXT_TEXT) end
    return value
end

local function readMapContext()
    if type(ns.MapContext) ~= "function" then return nil end
    local ok, raw = pcall(ns.MapContext)
    if not ok or type(raw) ~= "table" then return nil end
    local out = {
        uiMapID = D.SafeInt(raw.uiMapID, 0, MAX_WORLD_ID),
        mapType = D.SafeInt(raw.mapType, 0, MAX_WORLD_ID),
        parentMapID = D.SafeInt(raw.parentMapID, 0, MAX_WORLD_ID),
        mapName = safeText(raw.mapName),
        zone = safeText(raw.zone),
        subzone = safeText(raw.subzone),
    }
    if not out.uiMapID and not out.mapName and not out.zone and not out.subzone then return nil end
    return out
end

function M.ReadMapContext()
    return readMapContext()
end

function M.NextContextId(profile)
    if type(profile) ~= "table" then return nil end
    local id = D.SafeInt(profile.contextSequence, 0, MAX_ORDER) or 0
    if id >= MAX_ORDER then return nil end
    id = id + 1
    profile.contextSequence = id
    return id
end

function M.AddContextSnapshot(profile, kind, played, mapID, x, y, timelineOrder, overrideContext)
    if type(profile) ~= "table" then return nil end
    kind = D.SafeInt(kind, CTX.SESSION, CTX.TRANSITION_ARRIVAL)
    local stamp = D.TrueStamp(played)
    if not kind or not stamp then return nil end
    local sx, sy = tonumber(x), tonumber(y)
    local worldID = D.SafeInt(mapID, 0, MAX_WORLD_ID)
    local known = worldID and sx and sy and D.ValidWorldCoordinates(sx, sy) and 1 or 0
    if known == 0 then worldID, sx, sy = 0, 0, 0 end
    local context = type(overrideContext) == "table" and overrideContext or readMapContext()
    local id = M.NextContextId(profile)
    if not id then return nil end
    local row = {
        id = id, kind = kind, played = stamp,
        timelineOrder = D.SafeInt(timelineOrder, 0, MAX_ORDER) or 0,
        worldInstanceID = worldID,
        x = known == 1 and D.RoundTenth(sx) or 0,
        y = known == 1 and D.RoundTenth(sy) or 0,
        positionKnown = known,
    }
    if context then
        row.uiMapID = D.SafeInt(context.uiMapID, 0, MAX_WORLD_ID)
        row.mapType = D.SafeInt(context.mapType, 0, MAX_WORLD_ID)
        row.parentMapID = D.SafeInt(context.parentMapID, 0, MAX_WORLD_ID)
        row.mapName = safeText(context.mapName)
        row.zone = safeText(context.zone)
        row.subzone = safeText(context.subzone)
    end
    profile.contextEvents = type(profile.contextEvents) == "table" and profile.contextEvents or {}
    profile.contextEvents[#profile.contextEvents + 1] = row
    return id
end

function M.TransitionCause(defaultCode, hint)
    if type(hint) == "table" and hint.kind == "hearth" then
        return TR.Cause.HEARTH, TR.Confidence.SEMANTIC_CONFIRMED
    end
    if type(hint) == "table" and hint.kind == "teleport" then
        return TR.Cause.TELEPORT_SPELL, TR.Confidence.SEMANTIC_CONFIRMED
    end
    if defaultCode == C.State.WORLD_TRANSITION then return TR.Cause.WORLD_BOUNDARY, TR.Confidence.OBSERVED end
    if defaultCode == C.State.TELEPORT then return TR.Cause.OBSERVED_TELEPORT, TR.Confidence.OBSERVED end
    return TR.Cause.UNKNOWN, TR.Confidence.OBSERVED
end

function M.NextTransitionId(profile)
    if type(profile) ~= "table" then return nil end
    local id = D.SafeInt(profile.transitionSequence, 0, MAX_TRANSITION_ID) or 0
    if id >= MAX_TRANSITION_ID then return nil end
    id = id + 1
    profile.transitionSequence = id
    return id
end

function M.BuildTransitionEndpoint(profile, anchor, contextKind, contextOverride)
    if type(profile) ~= "table" or type(anchor) ~= "table" then return nil end
    local played = D.TrueStamp(anchor.played)
    if not played then return nil end
    local mapID = D.SafeInt(anchor.mapID, 0, MAX_WORLD_ID)
    local x, y = tonumber(anchor.x), tonumber(anchor.y)
    local known = mapID and x and y and D.ValidWorldCoordinates(x, y) and 1 or 0
    if known == 0 then mapID, x, y = 0, 0, 0 end
    local order = D.SafeInt(anchor.order, 0, MAX_ORDER) or 0
    return {
        played = played, order = order, worldInstanceID = mapID,
        x = known == 1 and D.RoundTenth(x) or 0,
        y = known == 1 and D.RoundTenth(y) or 0,
        positionKnown = known,
        contextId = contextOverride == false and nil or M.AddContextSnapshot(
            profile, contextKind, played, mapID, x, y, order, contextOverride),
    }
end

local function numericEntries(value)
    local out = {}
    if type(value) ~= "table" then return out end
    for k, v in pairs(value) do
        if type(k) == "number" and k >= 1 and math.floor(k) == k then out[#out + 1] = {k, v} end
    end
    table.sort(out, function(a,b) return a[1] < b[1] end)
    return out
end

function M.SanitizeContextEvents(profile, quarantine)
    local out, seen, maxId = {}, {}, 0
    for _, pair in ipairs(numericEntries(profile and profile.contextEvents)) do
        local key, row = pair[1], pair[2]
        local valid = false
        if type(row) == "table" then
            local id = D.SafeInt(row.id, 1, MAX_ORDER)
            local kind = D.SafeInt(row.kind, CTX.SESSION, CTX.TRANSITION_ARRIVAL)
            local played = D.TrueStamp(row.played)
            local order = D.SafeInt(row.timelineOrder, 0, MAX_ORDER) or 0
            local worldID = D.SafeInt(row.worldInstanceID, 0, MAX_WORLD_ID) or 0
            local x, y = tonumber(row.x) or 0, tonumber(row.y) or 0
            local known = tonumber(row.positionKnown) == 1 and 1 or 0
            if known == 1 and not D.ValidWorldCoordinates(x, y) then known, worldID, x, y = 0, 0, 0, 0 end
            if known == 0 then worldID, x, y = 0, 0, 0 end
            if id and kind and played and not seen[id] then
                seen[id] = true
                maxId = math.max(maxId, id)
                out[#out + 1] = {
                    id=id,kind=kind,played=played,timelineOrder=order,worldInstanceID=worldID,
                    x=known==1 and D.RoundTenth(x) or 0,y=known==1 and D.RoundTenth(y) or 0,positionKnown=known,
                    uiMapID=D.SafeInt(row.uiMapID,0,MAX_WORLD_ID),mapType=D.SafeInt(row.mapType,0,MAX_WORLD_ID),
                    parentMapID=D.SafeInt(row.parentMapID,0,MAX_WORLD_ID),mapName=safeText(row.mapName),
                    zone=safeText(row.zone),subzone=safeText(row.subzone),
                }
                valid = true
            end
        end
        if not valid and row ~= nil and type(quarantine) == "function" then
            quarantine("context-event", "invalid-context", row, {index=key})
        end
    end
    table.sort(out, function(a,b) return a.id < b.id end)
    return out, maxId
end

local function sanitizeEndpoint(endpoint)
    if type(endpoint) ~= "table" then return nil end
    local played = D.TrueStamp(endpoint.played)
    if not played then return nil end
    local order = D.SafeInt(endpoint.order, 0, MAX_ORDER) or 0
    local worldID = D.SafeInt(endpoint.worldInstanceID, 0, MAX_WORLD_ID) or 0
    local x, y = tonumber(endpoint.x) or 0, tonumber(endpoint.y) or 0
    local known = tonumber(endpoint.positionKnown) == 1 and 1 or 0
    if known == 1 and not D.ValidWorldCoordinates(x, y) then known, worldID, x, y = 0, 0, 0, 0 end
    if known == 0 then worldID, x, y = 0, 0, 0 end
    return {
        played=played,order=order,worldInstanceID=worldID,
        x=known==1 and D.RoundTenth(x) or 0,y=known==1 and D.RoundTenth(y) or 0,
        positionKnown=known,contextId=D.SafeInt(endpoint.contextId,1,MAX_ORDER),
    }
end

function M.SanitizeTransitions(profile, minStateCode, maxStateCode, quarantine)
    local out, seen, maxId = {}, {}, 0
    for _, pair in ipairs(numericEntries(profile and profile.transitions)) do
        local key, row = pair[1], pair[2]
        local valid = false
        if type(row) == "table" then
            local id = D.SafeInt(row.id, 1, MAX_TRANSITION_ID)
            local state = D.SafeInt(row.observedState, minStateCode, maxStateCode)
            local cause = D.SafeInt(row.cause, TR.Cause.UNKNOWN, TR.Cause.OBSERVED_TELEPORT)
            local confidence = D.SafeInt(row.confidence, TR.Confidence.OBSERVED, TR.Confidence.SEMANTIC_CONFIRMED)
            local arrival = sanitizeEndpoint(row.arrival)
            local departure = row.departure == nil and nil or sanitizeEndpoint(row.departure)
            if id and state and cause and confidence and arrival and not seen[id] then
                seen[id] = true
                maxId = math.max(maxId, id)
                out[#out + 1] = {
                    id=id,observedState=state,cause=cause,confidence=confidence,
                    spellID=D.SafeInt(row.spellID,0,MAX_WORLD_ID) or 0,departure=departure,arrival=arrival,
                }
                valid = true
            end
        end
        if not valid and row ~= nil and type(quarantine) == "function" then
            quarantine("transition", "invalid-transition", row, {index=key})
        end
    end
    table.sort(out, function(a,b) return a.id < b.id end)
    return out, maxId
end

function M.DetectFutureSchema(root)
    if type(root) ~= "table" then return nil end
    local maxFuture
    local function inspect(value)
        local n = D.SafeInt(value, 1, MAX_WORLD_ID)
        if n and n > FORMAT_VERSION and (not maxFuture or n > maxFuture) then maxFuture = n end
    end
    inspect(root.schema)
    if type(root.heroPath) == "table" then inspect(root.heroPath.schema) end
    if type(root.heroPathInactiveProfiles) == "table" then
        for _, profile in pairs(root.heroPathInactiveProfiles) do
            if type(profile) == "table" then inspect(profile.schema) end
        end
    end
    return maxFuture
end

ns.Metadata = M
