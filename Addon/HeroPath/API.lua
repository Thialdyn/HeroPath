-- Hero’sPath public integration API.
-- Consumers should depend on this table, never on SavedVariables internals.
local ADDON_NAME, ns = ...
local C = assert(ns.Contract, "HeroPath Contract.lua must load before API.lua")

local API = {}

function API.GetAPIVersion()
    return C.PUBLIC_API_VERSION
end

function API.GetVersion()
    return C.VERSION
end

function API.GetSchema()
    return C.SAVED_VARIABLES_SCHEMA
end

function API.GetProduct()
    return C.PRODUCT
end

function API.GetAuthor()
    return C.AUTHOR
end

function API.GetArchiveState()
    if type(ns.GetArchiveState) ~= "function" then return false end
    return ns.GetArchiveState()
end

function API.GetHealth()
    return type(ns.GetCollectorHealth) == "function" and ns.GetCollectorHealth() or nil
end

function API.GetStorageStats()
    return type(ns.GetStorageStats) == "function" and ns.GetStorageStats() or nil
end

function API.GetCurrentWorldPosition()
    if type(ns.WorldPos) ~= "function" then return nil end
    return ns.WorldPos()
end

function API.GetCurrentMapContext()
    if type(ns.MapContext) ~= "function" then return nil end
    return ns.MapContext()
end

function API.GetExportSnapshot()
    return type(ns.GetHeroPathExportSnapshot) == "function" and ns.GetHeroPathExportSnapshot() or nil
end

function API.DecodeChunk(chunk)
    return type(ns.DecodeHeroPathChunk) == "function" and ns.DecodeHeroPathChunk(chunk) or nil
end

_G.HeroPathAPI = API
