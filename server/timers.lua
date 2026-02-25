local function load_module(path)
    local res = GetCurrentResourceName()
    local src = LoadResourceFile(res, path)
    if not src then error('load_module: missing ' .. path) end
    local fn, err = load(src, path)
    if not fn then error(err) end
    return fn()
end

local cache = _G['bcc_saloons_cache'] or load_module('server/cache.lua')
_G['bcc_saloons_cache'] = cache
local funcs = _G['bcc_saloons_funcs'] or load_module('server/functions.lua')
_G['bcc_saloons_funcs'] = funcs

local M = {}
local ActiveTimers = {}

local function StopPropTimer(id)
    if not id then return end
    local t = ActiveTimers[id]
    if t then
        t.cancel = true
        ActiveTimers[id] = nil
        if DBG then DBG:Info('Stopped timer for prop ' .. tostring(id)) end
    end
end

local function StartPropTimer(id)
    if not id then return end
    if ActiveTimers[id] then return end -- already running
    local idx = cache.FindCacheIndex(id)
    local row = idx and cache.StillsCache[idx] or nil
    if not row then
        local ok, res = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
        if ok and res and res[1] then
            cache.UpsertCacheRow(res[1])
            row = res[1]
        end
    end
    if not row then
        if DBG then DBG:Info('StartPropTimer: no row found for id ' .. tostring(id)) end
        return
    end
    if DBG then DBG:Info('StartPropTimer: starting for id ' .. tostring(id) .. ' stage=' .. tostring(row.stage) .. ' isbrewing=' .. tostring(row.isbrewing) .. ' brew=' .. tostring(row.currentbrew)) end
    if tonumber(row.isbrewing) ~= 1 then
        if DBG then DBG:Info('StartPropTimer: isbrewing != 1 for id ' .. tostring(id) .. ', skipping timer') end
        return
    end

    local timer = { cancel = false }
    ActiveTimers[id] = timer

    CreateThread(function()
        if DBG then DBG:Info('Timer thread created for prop ' .. tostring(id)) end
        while true do
            if timer.cancel then break end
            -- refresh authoritative row
            local ridx = cache.FindCacheIndex(id)
            local r = ridx and cache.StillsCache[ridx] or nil
            if not r then
                local ok, res = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
                if ok and res and res[1] then
                    cache.UpsertCacheRow(res[1])
                    r = res[1]
                else
                    break
                end
            end
            if not r or tonumber(r.isbrewing) ~= 1 then break end

            local curStage = tonumber(r.stage) or 1
            local wait_ms = 0
            if Moonshine and Moonshine[r.currentbrew] and Moonshine[r.currentbrew][curStage] then
                if Moonshine[r.currentbrew][curStage].stilltime then
                    wait_ms = Moonshine[r.currentbrew][curStage].stilltime * 60000
                else
                    if DBG then DBG:Info('Timer exit: Moonshine entry missing stilltime for ' .. tostring(r.currentbrew) .. ' stage ' .. tostring(curStage)) end
                    break
                end
            elseif Mash and Mash[r.currentbrew] then
                local nextStage = curStage + 1
                if Mash[r.currentbrew][nextStage] and Mash[r.currentbrew][nextStage].fermenttime then
                    wait_ms = Mash[r.currentbrew][nextStage].fermenttime * 60000
                elseif Mash[r.currentbrew].fermenttime then
                    wait_ms = Mash[r.currentbrew].fermenttime * 60000
                else
                    if DBG then DBG:Info('Timer exit: Mash entry missing fermenttime for ' .. tostring(r.currentbrew) .. ' nextStage ' .. tostring(nextStage)) end
                    break
                end
            else
                if DBG then DBG:Info('Timer exit: No recipe found for currentbrew=' .. tostring(r.currentbrew)) end
                break
            end

            if wait_ms > 0 then
                local now_ms = math.floor(os.time() * 1000)
                local end_ms = now_ms + wait_ms
                if DBG then DBG:Info('Timer for prop ' .. tostring(id) .. ' curStage=' .. tostring(curStage) .. ' wait_ms=' .. tostring(wait_ms) .. ' end_ms=' .. tostring(end_ms) .. ' brew=' .. tostring(r.currentbrew)) end
                pcall(function()
                    funcs.SafeMySQLQuery("UPDATE brewing SET stage_end_ms = ? WHERE id = ?", { end_ms, id })
                end)
                local okr, updated = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
                if okr and updated and updated[1] then cache.UpsertCacheRow(updated[1]) end
            end

            if wait_ms <= 0 then
                if DBG then DBG:Info('Timer for prop ' .. tostring(id) .. ' computed non-positive wait_ms; exiting timer without advancing stage (brew=' .. tostring(r.currentbrew) .. ', curStage=' .. tostring(curStage) .. ')') end
                break
            end

            local elapsed = 0
            local step = 1000
            while elapsed < wait_ms do
                if timer.cancel then break end
                local towait = math.min(step, wait_ms - elapsed)
                Wait(towait)
                elapsed = elapsed + towait
            end
            if timer.cancel then break end

            if DBG then DBG:Info('Timer for prop ' .. tostring(id) .. ' elapsed; triggering ChangeStage with curStage=' .. tostring(curStage)) end
            pcall(function()
                Core.Callback.TriggerAwait('bcc-saloons:ChangeStage', id, curStage, 0, r.currentbrew)
            end)
        end
        ActiveTimers[id] = nil
        if DBG then DBG:Info('Timer thread exited for prop ' .. tostring(id)) end
    end)
end

M.StartPropTimer = StartPropTimer
M.StopPropTimer = StopPropTimer
M.ActiveTimers = ActiveTimers
return M
