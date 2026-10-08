-- Hero’sPath 1.0.0 - WoW API integration layer.
local ADDON_NAME, ns = ...
local C = assert(ns.Contract, "HeroPath Contract.lua must load before Bootstrap.lua")
local I = C.Integration

local listeners = {}
local loadCallbacks = {}
local loaded = false
local initialized = false
local savedRef

local diagnostics = {
    worldCalls = 0,
    cmapOK = 0,
    unitOK = 0,
    dualOK = 0,
    singleCMap = 0,
    singleUnit = 0,
    sourceMismatch = 0,
    sourceMissing = 0,
    playedResponses = 0,
    playedRequests = 0,
    playedResponseBackstepsClamped = 0,
    playedRetryAttempts = 0,
    playedRetryScheduled = false,
    savedVariablesTooLarge = 0,
    recoveredMalformedRoot = 0,
    apiCallErrors = 0,
    lastApiCallError = nil,
    eventRegistrationErrors = 0,
    lastEventRegistrationError = nil,
    dispatchErrors = 0,
    lastDispatchError = nil,
    loadCallbackErrors = 0,
    lastLoadError = nil,
    lastWorldSource = nil,
    lastWorldError = nil,
    unitOrder = nil,
    calibrationState = "learning",
    calibrationVotesXY = 0,
    calibrationVotesYX = 0,
    calibrationDecisive = 0,
    calibrationAmbiguous = 0,
    calibrationResets = 0,
    orientationContradictions = 0,
}
ns.EnableCollectorWatchdog = C.FeatureFlags.ENABLE_COLLECTOR_WATCHDOG
ns.EnableResumePrime = C.FeatureFlags.ENABLE_RESUME_PRIME
ns.RequireWorldEntryBeforeSampling = C.FeatureFlags.REQUIRE_WORLD_ENTRY_BEFORE_SAMPLING

local function isFiniteNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Reject API errors and restricted values before they reach the collector.
local function isPublicValue(v)
    if v == nil then return true end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, v)
        -- Never assume the value is public if the client cannot answer.
        if not ok or secret == true then return false end
    end
    return true
end

function ns.Public(v)
    return isPublicValue(v) and v or nil
end

local function safeResult(v)
    if not isPublicValue(v) then return nil end
    if type(v) == "number" and not isFiniteNumber(v) then return nil end
    return v
end

function ns.SafeRead(label, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j = pcall(fn, ...)
    if not ok then
        diagnostics.apiCallErrors = diagnostics.apiCallErrors + 1
        diagnostics.lastApiCallError = tostring(label or "api") .. ": " .. tostring(a)
        return nil
    end
    return safeResult(a), safeResult(b), safeResult(c), safeResult(d), safeResult(e),
           safeResult(f), safeResult(g), safeResult(h), safeResult(i), safeResult(j)
end

local function safeNumber(v)
    if not isPublicValue(v) then return nil end
    local ok,n=pcall(tonumber,v)
    if ok and isFiniteNumber(n) then return n end
    return nil
end

local function safeField(value, key)
    -- WoW APIs may expose vectors and structured return values as userdata on
    -- one client and tables on another. Treat indexability, not Lua type, as
    -- the contract and keep the access behind the same public-value boundary.
    if value == nil or not isPublicValue(value) then return nil end
    local ok, result = pcall(function() return value[key] end)
    if not ok or not isPublicValue(result) then return nil end
    return result
end

local function monotonicNow()
    if type(GetTimePreciseSec) == "function" then
        local v = ns.SafeRead("GetTimePreciseSec", GetTimePreciseSec)
        if isFiniteNumber(v) and v >= 0 then return v end
    end
    if type(GetTime) == "function" then
        local v = ns.SafeRead("GetTime", GetTime)
        if isFiniteNumber(v) and v >= 0 then return v end
    end
    return 0
end

function ns.Num(v)
    return safeNumber(v)
end

function ns.Call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return nil end
    return ns.SafeRead(name, fn, ...)
end

local frame = CreateFrame("Frame")
local registered = {}

function ns.Listen(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return false end
    if not registered[event] then
        local ok,err = pcall(frame.RegisterEvent, frame, event)
        if not ok then
            diagnostics.eventRegistrationErrors = diagnostics.eventRegistrationErrors + 1
            diagnostics.lastEventRegistrationError = tostring(event) .. ": " .. tostring(err)
            return false
        end
        registered[event] = true
        listeners[event] = {}
    end
    listeners[event][#listeners[event] + 1] = fn
    return true
end

function ns.OnLoad(fn)
    if type(fn) ~= "function" then return end
    if initialized then
        local ok,err=pcall(fn,savedRef)
        if not ok then
            diagnostics.loadCallbackErrors=diagnostics.loadCallbackErrors+1
            diagnostics.lastLoadError=tostring(err)
        end
    else
        loadCallbacks[#loadCallbacks + 1] = fn
    end
end

local function dispatch(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            diagnostics.dispatchErrors = diagnostics.dispatchErrors + 1
            diagnostics.lastDispatchError = tostring(err)
            if type(geterrorhandler) == "function" then
                local handler = geterrorhandler()
                if type(handler) == "function" then pcall(handler, err) end
            end
        end
    end
end

-- /played anchor. RequestTimePlayed asynchronously gives the authoritative total;
-- after that, a monotonic local clock advances it between server responses.
local playedBase
local playedBaseClock
local lastPlayedRequestClock = -math.huge
local PLAYED_REQUEST_COOLDOWN = I.PLAYED_REQUEST_COOLDOWN
local playedRetryStep = 1
local PLAYED_RETRY_DELAYS = I.PLAYED_RETRY_DELAYS

local function requestPlayedAnchor()
    if type(RequestTimePlayed) ~= "function" then return false end
    local now = monotonicNow()
    if now - lastPlayedRequestClock < PLAYED_REQUEST_COOLDOWN then return false end
    lastPlayedRequestClock = now
    local before = diagnostics.apiCallErrors
    ns.SafeRead("RequestTimePlayed", RequestTimePlayed)
    local ok = diagnostics.apiCallErrors == before
    if ok then diagnostics.playedRequests = diagnostics.playedRequests + 1 end
    return ok
end

local function schedulePlayedAnchorRetry()
    if playedBase ~= nil or diagnostics.playedRetryScheduled then return end
    if not C_Timer or type(C_Timer.After) ~= "function" then return end
    local delay = PLAYED_RETRY_DELAYS[math.min(playedRetryStep, #PLAYED_RETRY_DELAYS)]
    diagnostics.playedRetryScheduled = true
    C_Timer.After(delay, function()
        diagnostics.playedRetryScheduled = false
        if playedBase ~= nil then return end
        diagnostics.playedRetryAttempts = diagnostics.playedRetryAttempts + 1
        requestPlayedAnchor()
        playedRetryStep = math.min(playedRetryStep + 1, #PLAYED_RETRY_DELAYS)
        schedulePlayedAnchorRetry()
    end)
end

local function ensurePlayedAnchor()
    if playedBase ~= nil then return end
    requestPlayedAnchor()
    schedulePlayedAnchorRetry()
end

function ns.PlayedNow()
    if not isFiniteNumber(playedBase) or not isFiniteNumber(playedBaseClock) then return nil end
    local now = monotonicNow()
    if now < playedBaseClock then return nil end
    return playedBase + (now - playedBaseClock)
end

-- C_Map and UnitPosition are independent outdoor position paths.
-- UnitPosition's historical axis labels differ between client families/documentation. Never
-- hardcode XY vs YX. Calibrate the raw pair against C_Map, then keep cross-checking it.
local SOURCE_AGREE_YARDS = I.SOURCE_AGREE_YARDS
local CALIBRATION_REQUIRED_DECISIVE = I.CALIBRATION_REQUIRED_DECISIVE
local CALIBRATION_WINNER_MIN = I.CALIBRATION_WINNER_MIN
local CALIBRATION_VOTE_MARGIN = I.CALIBRATION_VOTE_MARGIN
local ORIENTATION_CONTRADICTION_RESET = I.ORIENTATION_CONTRADICTION_RESET

local unitCalibration = {
    order = nil,
    votesXY = 0,
    votesYX = 0,
    decisive = 0,
    ambiguous = 0,
    contradictionStreak = 0,
}

local function calibrationSyncDiagnostics()
    diagnostics.unitOrder = unitCalibration.order
    diagnostics.calibrationState = unitCalibration.order and "locked" or "learning"
    diagnostics.calibrationVotesXY = unitCalibration.votesXY
    diagnostics.calibrationVotesYX = unitCalibration.votesYX
    diagnostics.calibrationDecisive = unitCalibration.decisive
    diagnostics.calibrationAmbiguous = unitCalibration.ambiguous
    diagnostics.orientationContradictions = unitCalibration.contradictionStreak
end

local function resetUnitCalibration(reason)
    unitCalibration.order = nil
    unitCalibration.votesXY = 0
    unitCalibration.votesYX = 0
    unitCalibration.decisive = 0
    unitCalibration.ambiguous = 0
    unitCalibration.contradictionStreak = 0
    diagnostics.calibrationResets = (tonumber(diagnostics.calibrationResets) or 0) + 1
    diagnostics.lastCalibrationResetReason = reason
    calibrationSyncDiagnostics()
end

local function maybeLockCalibration()
    if unitCalibration.order then return unitCalibration.order end
    if unitCalibration.decisive < CALIBRATION_REQUIRED_DECISIVE then return nil end
    local xy, yx = unitCalibration.votesXY, unitCalibration.votesYX
    if xy >= CALIBRATION_WINNER_MIN and xy >= yx + CALIBRATION_VOTE_MARGIN then
        unitCalibration.order = "XY"
    elseif yx >= CALIBRATION_WINNER_MIN and yx >= xy + CALIBRATION_VOTE_MARGIN then
        unitCalibration.order = "YX"
    end
    calibrationSyncDiagnostics()
    return unitCalibration.order
end

local function readProjectedWorldPosition()
    if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" or
       type(C_Map.GetPlayerMapPosition) ~= "function" or type(C_Map.GetWorldPosFromMapPos) ~= "function" then
        return nil
    end
    local uiMapID = safeNumber(ns.SafeRead("C_Map.GetBestMapForUnit", C_Map.GetBestMapForUnit, "player"))
    if not uiMapID then return nil end
    local pos = ns.SafeRead("C_Map.GetPlayerMapPosition", C_Map.GetPlayerMapPosition, uiMapID, "player")
    if not pos then return nil end
    local instanceID, world = ns.SafeRead("C_Map.GetWorldPosFromMapPos", C_Map.GetWorldPosFromMapPos, uiMapID, pos)
    instanceID=safeNumber(instanceID)
    if not instanceID or not world then return nil end
    local x, y = safeNumber(safeField(world, "x")), safeNumber(safeField(world, "y"))
    if not x or not y then return nil end
    diagnostics.cmapOK = diagnostics.cmapOK + 1
    diagnostics.lastCMapX, diagnostics.lastCMapY, diagnostics.lastCMapInstance = x, y, instanceID
    return x, y, instanceID
end

local function readUnitWorldPair()
    if type(UnitPosition) ~= "function" then return nil end
    local a, b, z, instanceID = ns.SafeRead("UnitPosition", UnitPosition, "player")
    a, b, z, instanceID = safeNumber(a), safeNumber(b), safeNumber(z), safeNumber(instanceID)
    if not a or not b or not instanceID then return nil end
    diagnostics.unitOK = diagnostics.unitOK + 1
    diagnostics.lastUnitRawA, diagnostics.lastUnitRawB, diagnostics.lastUnitZ = a, b, z
    diagnostics.lastUnitInstance = instanceID
    return a, b, instanceID
end

local function planarDistance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Returns normalized UnitPosition x/y when the current sample can prove an orientation.
-- During learning an unambiguous sample is already safe enough to cross-check C_Map, but the
-- session-level order is only locked after several decisive samples.
local function resolveUnitAxes(ax, ay, ai, a, b, bi)
    if ai ~= bi then
        diagnostics.lastUnitXYDistance = nil
        diagnostics.lastUnitYXDistance = nil
        return nil, nil, "instance"
    end

    local dXY = planarDistance(ax, ay, a, b)
    local dYX = planarDistance(ax, ay, b, a)
    diagnostics.lastUnitXYDistance = dXY
    diagnostics.lastUnitYXDistance = dYX

    local order = unitCalibration.order
    if order then
        local lockedD = order == "XY" and dXY or dYX
        local alternateD = order == "XY" and dYX or dXY
        diagnostics.lastSourceDistance = lockedD
        if lockedD <= SOURCE_AGREE_YARDS then
            unitCalibration.contradictionStreak = 0
            calibrationSyncDiagnostics()
            local x, y = order == "XY" and a or b, order == "XY" and b or a
            diagnostics.lastUnitX, diagnostics.lastUnitY = x, y
            return x, y, order
        end
        if alternateD <= SOURCE_AGREE_YARDS then
            unitCalibration.contradictionStreak = unitCalibration.contradictionStreak + 1
            diagnostics.orientationContradictions = unitCalibration.contradictionStreak
            if unitCalibration.contradictionStreak >= ORIENTATION_CONTRADICTION_RESET then
                resetUnitCalibration("alternate-order-now-matches")
            end
            return nil, nil, "contradiction"
        end
        unitCalibration.contradictionStreak = 0
        calibrationSyncDiagnostics()
        return nil, nil, "mismatch"
    end

    local xyOK, yxOK = dXY <= SOURCE_AGREE_YARDS, dYX <= SOURCE_AGREE_YARDS
    local sampleOrder
    if xyOK and not yxOK then sampleOrder = "XY"
    elseif yxOK and not xyOK then sampleOrder = "YX"
    elseif xyOK and yxOK then
        unitCalibration.ambiguous = unitCalibration.ambiguous + 1
        diagnostics.calibrationAmbiguous = unitCalibration.ambiguous
        -- Both interpretations are numerically plausible (for example close to x==y).
        -- C_Map remains usable, but UnitPosition is not counted as an independent verifier yet.
        return nil, nil, "ambiguous"
    else
        return nil, nil, "mismatch"
    end

    unitCalibration.decisive = unitCalibration.decisive + 1
    if sampleOrder == "XY" then unitCalibration.votesXY = unitCalibration.votesXY + 1
    else unitCalibration.votesYX = unitCalibration.votesYX + 1 end
    maybeLockCalibration()
    calibrationSyncDiagnostics()

    local x, y = sampleOrder == "XY" and a or b, sampleOrder == "XY" and b or a
    diagnostics.lastUnitX, diagnostics.lastUnitY = x, y
    diagnostics.lastSourceDistance = sampleOrder == "XY" and dXY or dYX
    return x, y, sampleOrder
end

local function useCalibratedUnitPair(a, b, bi)
    local order = unitCalibration.order
    if not order then return nil end
    local x, y = order == "XY" and a or b, order == "XY" and b or a
    diagnostics.lastUnitX, diagnostics.lastUnitY = x, y
    return x, y, bi
end

function ns.WorldPos()
    diagnostics.worldCalls = diagnostics.worldCalls + 1
    local ax, ay, ai = readProjectedWorldPosition()
    local a, b, bi = readUnitWorldPair()

    if ax and a then
        local bx, by, calibrationResult = resolveUnitAxes(ax, ay, ai, a, b, bi)
        if bx then
            local d = planarDistance(ax, ay, bx, by)
            diagnostics.lastSourceDistance = d
            if d > SOURCE_AGREE_YARDS then
                diagnostics.sourceMismatch = diagnostics.sourceMismatch + 1
                diagnostics.lastWorldSource = "mismatch"
                diagnostics.lastWorldError = ("C_Map/UnitPosition disagree after %s normalization: %.2f yd"):format(tostring(calibrationResult), d)
                return nil,nil,nil,"mismatch"
            end
            diagnostics.dualOK = diagnostics.dualOK + 1
            diagnostics.lastWorldSource = "dual"
            diagnostics.lastWorldError = nil
            return ax, ay, ai, "dual"
        end

        if calibrationResult == "ambiguous" then
            -- Safe single-source fallback while the axis order cannot yet be distinguished.
            diagnostics.singleCMap = diagnostics.singleCMap + 1
            diagnostics.lastWorldSource = "cmap"
            diagnostics.lastWorldError = "UnitPosition axis order still ambiguous; using C_Map"
            return ax, ay, ai, "cmap"
        end

        diagnostics.sourceMismatch = diagnostics.sourceMismatch + 1
        diagnostics.lastWorldSource = "mismatch"
        diagnostics.lastWorldError = ("C_Map/UnitPosition calibration mismatch: %s (XY %.2f yd / YX %.2f yd)"):format(
            tostring(calibrationResult), tonumber(diagnostics.lastUnitXYDistance) or -1, tonumber(diagnostics.lastUnitYXDistance) or -1)
        return nil,nil,nil,"mismatch"
    elseif ax then
        diagnostics.singleCMap = diagnostics.singleCMap + 1
        diagnostics.lastWorldSource = "cmap"
        diagnostics.lastWorldError = nil
        return ax, ay, ai, "cmap"
    elseif a then
        local bx, by, bmap = useCalibratedUnitPair(a, b, bi)
        if bx then
            diagnostics.singleUnit = diagnostics.singleUnit + 1
            diagnostics.lastWorldSource = "unit"
            diagnostics.lastWorldError = nil
            return bx, by, bmap, "unit"
        end
        diagnostics.sourceMissing = diagnostics.sourceMissing + 1
        diagnostics.lastWorldSource = "none"
        diagnostics.lastWorldError = "UnitPosition available but axis order is not calibrated and C_Map is unavailable"
        return nil,nil,nil,"none"
    end

    diagnostics.sourceMissing = diagnostics.sourceMissing + 1
    diagnostics.lastWorldSource = "none"
    diagnostics.lastWorldError = "no outdoor world-position source"
    return nil,nil,nil,"none"
end

function ns.MapContext()
    local out = {}
    if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
        out.uiMapID = safeNumber(ns.SafeRead("C_Map.GetBestMapForUnit", C_Map.GetBestMapForUnit, "player"))
        if out.uiMapID and type(C_Map.GetMapInfo) == "function" then
            local info = ns.SafeRead("C_Map.GetMapInfo", C_Map.GetMapInfo, out.uiMapID)
            if type(info) == "table" then
                out.mapName = ns.Public(safeField(info, "name"))
                out.mapType = safeNumber(safeField(info, "mapType"))
                out.parentMapID = safeNumber(safeField(info, "parentMapID"))
            end
        end
    end
    local zone = ns.Call("GetZoneText")
    local subzone = ns.Call("GetSubZoneText")
    if type(zone) == "string" and zone ~= "" then out.zone = zone end
    if type(subzone) == "string" and subzone ~= "" then out.subzone = subzone end
    return next(out) and out or nil
end

function ns.GetIntegrationHealth()
    return diagnostics
end

local function initializeCollector()
    if initialized or not loaded then return end
    local priorRoot = HeroPathDB
    if type(priorRoot) ~= "table" then
        local fresh = {}
        if priorRoot ~= nil then
            local payloadType=type(priorRoot)
            local payload=(payloadType=="string" or payloadType=="number" or payloadType=="boolean") and priorRoot or ("<"..payloadType..">")
            fresh.recoveryRootQuarantine={{kind="saved-variable-root",capturedType=payloadType,payload=payload}}
            diagnostics.recoveredMalformedRoot = diagnostics.recoveredMalformedRoot + 1
        end
        HeroPathDB=fresh
    end
    savedRef = HeroPathDB
    initialized = true
    for i = 1, #loadCallbacks do
        local ok, err = pcall(loadCallbacks[i], savedRef)
        if not ok then
            diagnostics.loadCallbackErrors=diagnostics.loadCallbackErrors+1
            diagnostics.lastLoadError = tostring(err)
        end
    end
    for i = #loadCallbacks, 1, -1 do loadCallbacks[i] = nil end
end

-- Bootstrap owns only events needed to make the integration layer usable. All
-- collector state events are registered through ns.Listen and dispatched below.
local function bootstrapRegister(event)
    local ok,err = pcall(frame.RegisterEvent, frame, event)
    if not ok then
        diagnostics["eventUnsupported_" .. event] = true
        diagnostics.eventRegistrationErrors = diagnostics.eventRegistrationErrors + 1
        diagnostics.lastEventRegistrationError = tostring(event) .. ": " .. tostring(err)
    end
    return ok
end
bootstrapRegister("ADDON_LOADED")
bootstrapRegister("PLAYER_LOGIN")
bootstrapRegister("PLAYER_ENTERING_WORLD")
bootstrapRegister("TIME_PLAYED_MSG")
bootstrapRegister("SAVED_VARIABLES_TOO_LARGE")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON_NAME then return end
        loaded = true
        -- Defer collector initialization until PLAYER_LOGIN. This prevents the 4 Hz
        -- ticker from sampling character/world APIs during the pre-world addon-load phase.
        return
    elseif event == "PLAYER_LOGIN" then
        initializeCollector()
        ensurePlayedAnchor()
    elseif event == "PLAYER_ENTERING_WORLD" then
        initializeCollector()
        ensurePlayedAnchor()
    elseif event == "TIME_PLAYED_MSG" then
        local total = safeNumber((...))
        if total and total >= 0 then
            local nowClock = monotonicNow()
            local prior
            if isFiniteNumber(playedBase) and isFiniteNumber(playedBaseClock) and nowClock >= playedBaseClock then prior = playedBase + (nowClock - playedBaseClock) end
            if prior and total < prior then
                -- Server /played is integer-granularity while our anchored clock is sub-second.
                -- Never let a later response move the clock backwards merely because of rounding.
                total = prior
                diagnostics.playedResponseBackstepsClamped = diagnostics.playedResponseBackstepsClamped + 1
            end
            playedBase = total
            playedBaseClock = nowClock
            playedRetryStep = 1
            diagnostics.playedRetryScheduled = false
            diagnostics.playedResponses = diagnostics.playedResponses + 1
        end
    elseif event == "SAVED_VARIABLES_TOO_LARGE" then
        diagnostics.savedVariablesTooLarge = diagnostics.savedVariablesTooLarge + 1
        diagnostics.lastWorldError = "WoW reported SAVED_VARIABLES_TOO_LARGE"
    end
    dispatch(event, ...)
end)
