local M = {}

local StillsCache = {}

local function FindCacheIndex(id)
    for i, v in ipairs(StillsCache) do
        if v and v.id == id then return i end
    end
    return nil
end

local function UpsertCacheRow(row)
    if not row or not row.id then return end
    local idx = FindCacheIndex(row.id)
    if idx then
        StillsCache[idx] = row
    else
        table.insert(StillsCache, row)
    end
end

local function RemoveCacheRow(id)
    local idx = FindCacheIndex(id)
    if idx then
        table.remove(StillsCache, idx)
    end
end

local function LoadStillsCache()
    local ok, result = pcall(function()
        return MySQL.query.await('SELECT * FROM brewing')
    end)
    if not ok then
        if DBG then DBG:Error('LoadStillsCache MySQL error: ' .. tostring(result)) end
        return false
    end

    if result and result[1] then
        -- clear existing cache table while preserving reference
        for i = #StillsCache, 1, -1 do table.remove(StillsCache, i) end
        for i, r in ipairs(result) do
            if r then
                r.x = r.x ~= nil and tonumber(r.x) or r.x
                r.y = r.y ~= nil and tonumber(r.y) or r.y
                r.z = r.z ~= nil and tonumber(r.z) or r.z
                r.h = r.h ~= nil and tonumber(r.h) or r.h
                r.stage = r.stage ~= nil and tonumber(r.stage) or r.stage
                r.isbrewing = r.isbrewing ~= nil and tonumber(r.isbrewing) or r.isbrewing
                r.currentbrew = r.currentbrew or 'None'
                table.insert(StillsCache, r)
            end
        end
    else
        -- ensure cache is empty but keep original table reference
        for i = #StillsCache, 1, -1 do table.remove(StillsCache, i) end
    end
    return true
end

M.StillsCache = StillsCache
M.FindCacheIndex = FindCacheIndex
M.UpsertCacheRow = UpsertCacheRow
M.RemoveCacheRow = RemoveCacheRow
M.LoadStillsCache = LoadStillsCache

return M
