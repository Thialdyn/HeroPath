-- Hero’sPath data model and chunk codec.
-- No WoW API calls or mutable runtime state.
local ADDON_NAME, ns = ...
local C = assert(ns.Contract, "HeroPath Contract.lua must load before DataModel.lua")
local L, Z, BR = C.Limits, C.Compression, C.Break

local D = {}

function D.IsFinite(v)
    v = tonumber(v)
    return v ~= nil and v == v and v ~= math.huge and v ~= -math.huge
end

function D.ValidWorldCoordinates(x, y)
    if not D.IsFinite(x) or not D.IsFinite(y) then return false end
    x, y = tonumber(x), tonumber(y)
    return math.abs(x) <= L.MAX_WORLD_COORD_ABS and math.abs(y) <= L.MAX_WORLD_COORD_ABS
end

function D.FiniteNonNegative(v)
    return D.IsFinite(v) and tonumber(v) >= 0
end

function D.ValidPlayed(v)
    return D.FiniteNonNegative(v) and tonumber(v) <= L.MAX_PLAYED_SECONDS
end

function D.SafeInt(v, minimum, maximum)
    if not D.IsFinite(v) then return nil end
    v = tonumber(v)
    if math.floor(v) ~= v then return nil end
    if minimum ~= nil and v < minimum then return nil end
    if maximum ~= nil and v > maximum then return nil end
    return v
end

function D.RoundNearestInt(v)
    if v >= 0 then return math.floor(v + 0.5) end
    return math.ceil(v - 0.5)
end

function D.RoundTenth(v)
    return D.RoundNearestInt(v * 10) / 10
end

function D.TrueStamp(played)
    if not D.ValidPlayed(played) then return nil end
    return math.floor(tonumber(played) * 1000 + 0.5) / 1000
end

function D.DistanceXY(ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy)
end

function D.PointValid(p)
    if type(p) ~= "table" or #p < 7 then return false end
    if not D.ValidPlayed(p[1]) then return false end
    if not D.SafeInt(p[2], 0, L.MAX_WORLD_ID) then return false end
    if not D.ValidWorldCoordinates(p[3], p[4]) then return false end
    if not D.SafeInt(p[5], 0, L.MAX_MOVEMENT_MODE) then return false end
    if not D.SafeInt(p[6], 0, 1) or not D.SafeInt(p[7], 0, 1) then return false end
    if p[8] ~= nil and not D.SafeInt(p[8], 0, L.MAX_ORDER) then return false end
    if p[9] ~= nil and not D.SafeInt(p[9], 0, BR.UNCERTAIN) then return false end
    return true
end

function D.NormalizePoint(p, forceBreak)
    if not D.PointValid(p) then return nil end
    local reason = D.SafeInt(p[9], 0, BR.UNCERTAIN) or BR.NONE
    local br = forceBreak or tonumber(p[6]) == 1
    if br and reason == BR.NONE then reason = BR.RESUME end
    return {
        D.TrueStamp(p[1]), tonumber(p[2]), tonumber(p[3]), tonumber(p[4]), tonumber(p[5]),
        br and 1 or 0, tonumber(p[7]) == 1 and 1 or 0,
        D.SafeInt(p[8], 0, L.MAX_ORDER) or 0, br and reason or BR.NONE,
    }
end

local VARINT_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

local function EncodeVarintSigned(n)
    n = math.floor(tonumber(n) or 0)
    local u = n >= 0 and (n * 2) or (-n * 2 - 1)
    local out = ""
    repeat
        local d = u % 32
        u = math.floor(u / 32)
        if u > 0 then d = d + 32 end
        out = out .. VARINT_ALPHABET:sub(d + 1, d + 1)
    until u == 0
    return out
end

local function RollingHash(str)
    local h = 5381
    for i = 1, #str do h = (h * 131 + str:byte(i)) % 2147483647 end
    return h
end

local function ChunkChecksumPayload(ch)
    local ints = {
        ch[3] or 0, D.RoundNearestInt((ch[4] or 0) * 1000), D.RoundNearestInt((ch[5] or 0) * 1000),
        ch[6] or 0, ch[7] or 0, ch[8] or 0, D.RoundNearestInt((ch[9] or 0) * 10),
        D.RoundNearestInt((ch[10] or 0) * 10), ch[11] or 0, ch[12] or 0, ch[13] or 0, ch[14] or 0, ch[16] or 0
    }
    local parts = {tostring(ch[1] or ""), tostring(ch[2] or "")}
    for i = 1, #ints do parts[#parts + 1] = tostring(math.floor(tonumber(ints[i]) or 0)) end
    return table.concat(parts, "|")
end

function D.EncodeChunk(points)
    if type(points) ~= "table" or #points == 0 then return nil end
    local pieces = {}
    local pt, pm, px, py, po, pMode = 0, 0, 0, 0, 0, 0
    local k = 0
    for index, p in ipairs(points) do
        local t = D.RoundNearestInt((tonumber(p[1]) or 0) * 1000)
        local m = tonumber(p[2]) or 0
        local x = D.RoundNearestInt((tonumber(p[3]) or 0) * 10)
        local y = D.RoundNearestInt((tonumber(p[4]) or 0) * 10)
        local mode = tonumber(p[5]) or 0
        local o = tonumber(p[8]) or 0
        local br = tonumber(p[6]) == 1
        local prot = tonumber(p[7]) == 1
        local reason = br and (D.SafeInt(p[9], 0, BR.UNCERTAIN) or BR.RESUME) or BR.NONE
        local flags = (br and 4 or 0) + (prot and 8 or 0) + reason * 16
        local vals
        if index == 1 then
            vals = {t, m, x, y, mode, flags, o}
        else
            local mapChanged = m ~= pm
            local modeChanged = mode ~= pMode
            if mapChanged then flags = flags + 1 end
            if modeChanged then flags = flags + 2 end
            vals = {flags, t - pt, x - px, y - py, o - po}
            if mapChanged then vals[#vals + 1] = m - pm end
            if modeChanged then vals[#vals + 1] = mode end
        end
        for i = 1, #vals do
            k = k + 1
            pieces[k] = EncodeVarintSigned(vals[i])
        end
        pt, pm, px, py, po, pMode = t, m, x, y, o, mode
    end
    local last = points[#points]
    local ch = {
        "HP1", table.concat(pieces), #points,
        points[1][1], last[1], points[1][8] or 0, last[8] or 0,
        last[2], last[3], last[4], last[5], last[6], last[7], last[9], 0
    }
    ch[15] = RollingHash(ChunkChecksumPayload(ch))
    ch[17] = 1
    return ch
end

function D.CopyChunkWithBreakBefore(ch)
    if type(ch) ~= "table" then return nil end
    local copy = {}
    for k, v in pairs(ch) do copy[k] = v end
    copy[16] = 1
    copy[15] = RollingHash(ChunkChecksumPayload(copy))
    return copy
end

function D.EncodedChunkValid(ch)
    if type(ch) ~= "table" or ch[1] ~= "HP1" or type(ch[2]) ~= "string" then return false end
    if not D.SafeInt(ch[3], 1, Z.RAW_CHUNK_POINTS * 2) then return false end
    if not D.ValidPlayed(ch[4]) or not D.ValidPlayed(ch[5]) or ch[5] < ch[4] then return false end
    if not D.SafeInt(ch[6], 0, L.MAX_ORDER) or not D.SafeInt(ch[7], 0, L.MAX_ORDER) or ch[7] < ch[6] then return false end
    if not D.SafeInt(ch[8], 0, L.MAX_WORLD_ID) or not D.ValidWorldCoordinates(ch[9], ch[10]) then return false end
    if not D.SafeInt(ch[11], 0, L.MAX_MOVEMENT_MODE) or not D.SafeInt(ch[12], 0, 1) or not D.SafeInt(ch[13], 0, 1) or not D.SafeInt(ch[14], 0, BR.UNCERTAIN) then return false end
    if not D.SafeInt(ch[15], 0) or not D.SafeInt(ch[16] or 0, 0, 1) or not D.SafeInt(ch[17] or 0, 0, 1) then return false end
    return ch[15] == RollingHash(ChunkChecksumPayload(ch))
end

function D.DecodeChunk(ch)
    if not D.EncodedChunkValid(ch) then return nil end
    local data, pos = ch[2], 1
    local function readv()
        local u, mul = 0, 1
        while true do
            local c = data:sub(pos, pos)
            if c == "" then return nil end
            local p = string.find(VARINT_ALPHABET, c, 1, true)
            if not p then return nil end
            pos = pos + 1
            local d = p - 1
            local more = d >= 32
            if more then d = d - 32 end
            u = u + d * mul
            if not more then break end
            mul = mul * 32
            if mul > 9007199254740992 then return nil end
        end
        if u % 2 == 0 then return u / 2 end
        return -(u + 1) / 2
    end

    local out = {}
    local pt, pm, px, py, po, pMode = 0, 0, 0, 0, 0, 0
    for index = 1, ch[3] do
        local t, m, x, y, mode, flags, o
        if index == 1 then
            t, m, x, y, mode, flags, o = readv(), readv(), readv(), readv(), readv(), readv(), readv()
            if t == nil or m == nil or x == nil or y == nil or mode == nil or flags == nil or o == nil then return nil end
        else
            local dt, dx, dy, doo
            flags, dt, dx, dy, doo = readv(), readv(), readv(), readv(), readv()
            if flags == nil or dt == nil or dx == nil or dy == nil or doo == nil then return nil end
            t, m, x, y, mode, o = pt + dt, pm, px + dx, py + dy, pMode, po + doo
            if flags % 2 >= 1 then local dm = readv(); if dm == nil then return nil end; m = pm + dm end
            if math.floor(flags / 2) % 2 >= 1 then mode = readv(); if mode == nil then return nil end end
        end
        local br = math.floor(flags / 4) % 2
        local prot = math.floor(flags / 8) % 2
        local reason = br == 1 and math.floor(flags / 16) or 0
        local point = {t / 1000, m, x / 10, y / 10, mode, br, prot, o, reason}
        if not D.PointValid(point) then return nil end
        out[#out + 1] = point
        pt, pm, px, py, po, pMode = t, m, x, y, o, mode
    end
    if pos ~= #data + 1 then return nil end
    if tonumber(ch[16]) == 1 and out[1] then
        if tonumber(out[1][6]) ~= 1 then
            out[1][6] = 1
            out[1][9] = BR.UNAVAILABLE
        end
        out[1][7] = 1
    end
    return out
end

function D.DeepValidateChunk(ch)
    if not D.EncodedChunkValid(ch) then return false, "checksum-or-metadata" end
    local points = D.DecodeChunk(ch)
    if type(points) ~= "table" or #points ~= (tonumber(ch[3]) or -1) or #points < 1 then return false, "decode-count" end
    local first, last = points[1], points[#points]
    local function near(a, b, eps) return math.abs((tonumber(a) or math.huge) - (tonumber(b) or -math.huge)) <= eps end
    if not near(first[1], ch[4], 0.0015) or (tonumber(first[8]) or 0) ~= (tonumber(ch[6]) or 0) then return false, "first-metadata" end
    if not near(last[1], ch[5], 0.0015) or (tonumber(last[8]) or 0) ~= (tonumber(ch[7]) or 0) then return false, "last-time-order" end
    if (tonumber(last[2]) or -1) ~= (tonumber(ch[8]) or -2) or not near(last[3], ch[9], 0.051) or not near(last[4], ch[10], 0.051) then return false, "last-position" end
    if (tonumber(last[5]) or -1) ~= (tonumber(ch[11]) or -2) or (tonumber(last[6]) or -1) ~= (tonumber(ch[12]) or -2) or (tonumber(last[7]) or -1) ~= (tonumber(ch[13]) or -2) or (tonumber(last[9]) or -1) ~= (tonumber(ch[14]) or -2) then return false, "last-flags" end
    return true
end

ns.DataModel = D
