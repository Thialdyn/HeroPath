-- Hero’sPath 1.0.0 - in-game diagnostics.
local ADDON_NAME, ns = ...
local C = assert(ns.Contract, "HeroPath Contract.lua must load before Diagnostics.lua")

local PREFIX = "|cff58c6ff[HP]|r "
local VERSION = C.VERSION

local function msg(text)
    text = PREFIX .. tostring(text or "")
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    elseif type(print) == "function" then
        print(text)
    end
end

local function fmtBytes(n)
    n = tonumber(n) or 0
    if n >= 1024 * 1024 then return string.format("%.2f MiB", n / 1024 / 1024) end
    if n >= 1024 then return string.format("%.2f KiB", n / 1024) end
    return string.format("%d B", n)
end

local function buildInfo()
    local version, build, _, interface = ns.Call("GetBuildInfo")
    return tostring(version or "?"), tostring(build or "?"), tostring(interface or "?")
end

local function currentPosition()
    if type(ns.WorldPos) ~= "function" then return nil,nil,nil,"unavailable" end
    local ok,x,y,mapID,source = pcall(ns.WorldPos)
    if not ok then return nil,nil,nil,"error" end
    return x,y,mapID,source
end

local function status(verbose)
    local version, build, interface = buildInfo()
    local h = type(ns.GetCollectorHealth)=="function" and ns.GetCollectorHealth() or {}
    local i = type(ns.GetIntegrationHealth)=="function" and ns.GetIntegrationHealth() or {}
    local s = type(ns.GetStorageStats)=="function" and ns.GetStorageStats() or {}
    local x,y,mapID,source = currentPosition()
    local inside,itype = ns.Call("IsInInstance")
    inside = inside == true
    itype = type(itype)=="string" and itype or "none"

    local now = tonumber(ns.Call("GetTimePreciseSec")) or tonumber(ns.Call("GetTime")) or 0
    local beat = tonumber(h.lastTickerBeat)
    local stale = beat and now > 0 and math.max(0, now-beat) or nil
    local problems = {}
    local interfaceNumber=tonumber(interface)
    if interfaceNumber then
        local supported=false
        for n=1,#C.SUPPORTED_INTERFACES do if C.SUPPORTED_INTERFACES[n]==interfaceNumber then supported=true;break end end
        if not supported then problems[#problems+1]="Interface non déclarée="..tostring(interfaceNumber) end
    end
    if h.archiveReadOnly then
        problems[#problems+1]="ARCHIVE READ-ONLY schema="..tostring(h.archiveSchema or "?")
    end
    if (tonumber(h.sampleErrors) or 0) > 0 then problems[#problems+1]="sampleErrors="..tostring(h.sampleErrors) end
    if (tonumber(i.apiCallErrors) or 0) > 0 then problems[#problems+1]="apiCallErrors="..tostring(i.apiCallErrors) end
    if (tonumber(i.eventRegistrationErrors) or 0) > 0 then problems[#problems+1]="eventRegistrationErrors="..tostring(i.eventRegistrationErrors) end
    if (tonumber(i.dispatchErrors) or 0) > 0 then problems[#problems+1]="dispatchErrors="..tostring(i.dispatchErrors) end
    if (tonumber(i.loadCallbackErrors) or 0) > 0 or i.lastLoadError then problems[#problems+1]="collector load error" end
    if not h.archiveReadOnly and stale and stale > 3 then problems[#problems+1]=string.format("ticker stale %.1fs",stale) end
    if not h.archiveReadOnly and (tonumber(i.playedResponses) or 0) < 1 then problems[#problems+1]="/played non ancré (retry="..tostring(i.playedRetryAttempts or 0)..")" end
    if (tonumber(i.savedVariablesTooLarge) or 0) > 0 then problems[#problems+1]="SavedVariables trop volumineuses" end
    if (tonumber(h.compressionErrors) or 0) > 0 then problems[#problems+1]="compressionErrors="..tostring(h.compressionErrors) end
    if h.compressionRecoveryNeeded then problems[#problems+1]="compression recovery required" end
    if not h.archiveReadOnly and not inside and not x then problems[#problems+1]="WorldPos indisponible dehors ("..tostring(source)..")" end
    if source=="mismatch" then problems[#problems+1]="C_Map/UnitPosition mismatch" end

    msg(string.format("v%s | WoW %s build %s | Interface %s", VERSION, version, build, interface))
    if h.archiveReadOnly then
        msg(string.format("Archive: READ-ONLY | schema détecté=%s | aucune écriture/compaction/collecte", tostring(h.archiveSchema or "?")))
    else
        msg(string.format("Collector: samples %d/%d, errors %d, avg %.3f ms, max %.3f ms%s",
            tonumber(h.sampleSuccesses) or 0, tonumber(h.sampleAttempts) or 0, tonumber(h.sampleErrors) or 0,
            tonumber(h.sampleAverageMs) or 0, tonumber(h.sampleMaxMs) or 0,
            stale and string.format(", beat %.2fs", stale) or ""))
        msg(string.format("Adaptive store: distance=%d corner=%d interval=%d mode=%d skipped=%d",
            tonumber(h.storeDistance) or 0, tonumber(h.storeCorner) or 0, tonumber(h.storeInterval) or 0,
            tonumber(h.storeMode) or 0, tonumber(h.storeSkipped) or 0))
    end
    msg(string.format("World: %s | instance=%s (%s) | source=%s%s",
        h.worldSuspended and "suspended" or "active", tostring(inside), itype, tostring(source or "none"),
        x and string.format(" | worldInstance=%s x=%.1f y=%.1f", tostring(mapID), x, y) or ""))
    local estimated=type(ns.EstimateSavedVariablesBytes)=="function" and ns.EstimateSavedVariablesBytes() or 0
    msg(string.format("Storage: %d chunks, %d packed pts, %d tail pts, %s payload, ~%s SV, %d events, %d transitions, %d contexts, quarantine=%d",
        tonumber(s.chunks) or 0, tonumber(s.packedPoints) or 0, tonumber(s.tailPoints) or 0,
        fmtBytes(s.encodedPayloadBytes), fmtBytes(estimated), tonumber(s.events) or 0,
        tonumber(s.transitions) or 0, tonumber(s.contexts) or 0, tonumber(s.quarantineEntries) or 0))
    msg(string.format("Sensors: dual=%d cmap=%d unit=%d mismatch=%d missing=%d | /played responses=%d retries=%d",
        tonumber(i.dualOK) or 0, tonumber(i.singleCMap) or 0, tonumber(i.singleUnit) or 0,
        tonumber(i.sourceMismatch) or 0, tonumber(i.sourceMissing) or 0, tonumber(i.playedResponses) or 0, tonumber(i.playedRetryAttempts) or 0))
    msg(string.format("UnitPosition axes: %s | calibration=%s | votes XY/YX=%d/%d | ambiguous=%d | resets=%d",
        tostring(i.unitOrder or "learning"), tostring(i.calibrationState or "learning"),
        tonumber(i.calibrationVotesXY) or 0, tonumber(i.calibrationVotesYX) or 0,
        tonumber(i.calibrationAmbiguous) or 0, tonumber(i.calibrationResets) or 0))

    if #problems==0 then
        msg("CHECK: |cff55ff55PASS|r - aucune anomalie immédiate détectée.")
    else
        msg("CHECK: |cffffaa00WARN|r - "..table.concat(problems," ; "))
    end
    if verbose and h.lastSampleError then msg("Dernière erreur sample: "..tostring(h.lastSampleError)) end
    if verbose and i.lastApiCallError then msg("Dernière erreur API: "..tostring(i.lastApiCallError)) end
    if verbose and i.lastEventRegistrationError then msg("Dernière erreur event: "..tostring(i.lastEventRegistrationError)) end
    if verbose and i.lastDispatchError then msg("Dernière erreur dispatch: "..tostring(i.lastDispatchError)) end
    if verbose and i.lastLoadError then msg("Erreur chargement collecteur: "..tostring(i.lastLoadError)) end
end

local function stats()
    local s = type(ns.GetStorageStats)=="function" and ns.GetStorageStats() or nil
    if not s then msg("Storage indisponible."); return end
    local estimated=type(ns.EstimateSavedVariablesBytes)=="function" and ns.EstimateSavedVariablesBytes() or 0
    msg(string.format("format=%s | chunks=%d | points=%d | tail=%d | payload=%s | SV~%s | events=%d | semantic=%d | transitions=%d | contexts=%d | quarantine=%d",
        tostring(s.format), tonumber(s.chunks) or 0, tonumber(s.packedPoints) or 0,
        tonumber(s.tailPoints) or 0, fmtBytes(s.encodedPayloadBytes), fmtBytes(estimated), tonumber(s.events) or 0,
        tonumber(s.semanticEvents) or 0, tonumber(s.transitions) or 0, tonumber(s.contexts) or 0,
        tonumber(s.quarantineEntries) or 0))
end

local function pos()
    local x,y,mapID,source=currentPosition()
    local i = type(ns.GetIntegrationHealth)=="function" and ns.GetIntegrationHealth() or {}
    if x then
        msg(string.format("WorldPos: worldInstance=%s x=%.2f y=%.2f source=%s",tostring(mapID),x,y,tostring(source)))
    else
        msg("Position monde indisponible (source="..tostring(source).."). En instance/BG c'est normal.")
    end
    if i.lastCMapX or i.lastUnitRawA then
        msg(string.format("RAW C_Map: inst=%s x=%s y=%s | UnitPosition raw: a=%s b=%s inst=%s | order=%s",
            tostring(i.lastCMapInstance or "?"), i.lastCMapX and string.format("%.2f",i.lastCMapX) or "?", i.lastCMapY and string.format("%.2f",i.lastCMapY) or "?",
            i.lastUnitRawA and string.format("%.2f",i.lastUnitRawA) or "?", i.lastUnitRawB and string.format("%.2f",i.lastUnitRawB) or "?",
            tostring(i.lastUnitInstance or "?"), tostring(i.unitOrder or "learning")))
        msg(string.format("UnitPosition normalisé: x=%s y=%s | delta=%s yd | hypothèses XY/YX=%s/%s yd",
            i.lastUnitX and string.format("%.2f",i.lastUnitX) or "?", i.lastUnitY and string.format("%.2f",i.lastUnitY) or "?",
            i.lastSourceDistance and string.format("%.3f",i.lastSourceDistance) or "?",
            i.lastUnitXYDistance and string.format("%.3f",i.lastUnitXYDistance) or "?",
            i.lastUnitYXDistance and string.format("%.3f",i.lastUnitYXDistance) or "?"))
    end
end

local function help()
    msg("Commandes: /hp check | status | stats | pos | contract | help")
    msg("Après une session de diagnostic : fais /reload ou quitte proprement WoW avant de récupérer les SavedVariables.")
end

SLASH_HEROPATH1 = "/hp"
SLASH_HEROPATH2 = "/heropath"
SlashCmdList["HEROPATH"] = function(input)
    input = tostring(input or ""):lower():match("^%s*(.-)%s*$")
    if input=="check" or input=="status" then status(true)
    elseif input=="stats" then stats()
    elseif input=="pos" or input=="position" then pos()
    elseif input=="contract" then
        msg(string.format("Contract: version=%s schema=%s api=%s interfaces=%s", tostring(C.VERSION), tostring(C.SAVED_VARIABLES_SCHEMA), tostring(C.PUBLIC_API_VERSION), table.concat(C.SUPPORTED_INTERFACES, ",")))
        msg(string.format("Sampling: observe %.2fs | adaptive store ON | RDP %.1f yd + curvature preserve | chunk=%d | tail trigger=%d", C.Sampling.SAMPLE_SECONDS, C.Compression.RDP_EPSILON_YARDS, C.Compression.RAW_CHUNK_POINTS, C.Compression.RAW_TAIL_TRIGGER))
    else help() end
end

local f=CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent",function()
    if f._announced then return end
    f._announced=true
    local text="Hero’sPath "..C.VERSION.." chargé. Utilise /hp check."
    if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(2,function() msg(text) end) else msg(text) end
end)
