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
            if DBG then DBG:Info('Timer loop: FindCacheIndex(' .. tostring(id) .. ') -> ' .. tostring(ridx)) end
            if not r then
                local ok, res = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
                if ok and res and res[1] then
                    cache.UpsertCacheRow(res[1])
                    r = res[1]
                else
                    if DBG then DBG:Info('Timer loop: DB lookup failed for id ' .. tostring(id)) end
                    break
                end
            end
            if not r or tonumber(r.isbrewing) ~= 1 then
                if DBG then DBG:Info('Timer loop: stopping because not brewing for id ' .. tostring(id) .. ' r=' .. tostring(r and r.isbrewing)) end
                break
            end

            local curStage = tonumber(r.stage) or 1
            -- Prefer authoritative persisted end time if present (survives restarts)
            local now_ms = math.floor(os.time() * 1000)
            local end_ms = tonumber(r.stage_end_ms) or nil
            local wait_ms = nil
            if end_ms and end_ms > now_ms then
                wait_ms = end_ms - now_ms
                if DBG then DBG:Info('Timer for prop ' .. tostring(id) .. ' using persisted end_ms=' .. tostring(end_ms) .. ' wait_ms=' .. tostring(wait_ms) .. ' brew=' .. tostring(r.currentbrew)) end
            else
                -- compute expected wait from recipe and persist end_ms
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
                if wait_ms and wait_ms > 0 then
                    end_ms = now_ms + wait_ms
                    if DBG then DBG:Info('Timer for prop ' .. tostring(id) .. ' computed end_ms=' .. tostring(end_ms) .. ' wait_ms=' .. tostring(wait_ms) .. ' brew=' .. tostring(r.currentbrew)) end
                    pcall(function()
                        funcs.SafeMySQLQuery("UPDATE brewing SET stage_end_ms = ? WHERE id = ?", { end_ms, id })
                    end)
                    local okr, updated = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
                    if okr and updated and updated[1] then cache.UpsertCacheRow(updated[1]) end
                end
                -- recompute now_ms/wait_ms if end_ms was just set
                now_ms = math.floor(os.time() * 1000)
                if end_ms then wait_ms = math.max(0, end_ms - now_ms) end
            end

            if not wait_ms or wait_ms <= 0 then
                if DBG then DBG:Info('Timer for prop ' .. tostring(id) .. ' has non-positive wait_ms; exiting timer (brew=' .. tostring(r.currentbrew) .. ', curStage=' .. tostring(curStage) .. ')') end
                break
            end

            -- Wait in small increments but check authoritative DB-stored end time to be robust
            while wait_ms > 0 do
                if timer.cancel then break end
                local towait = math.min(1000, wait_ms)
                Wait(towait)
                now_ms = math.floor(os.time() * 1000)
                -- refresh authoritative row's end time (in case it was updated)
                local ridx2 = cache.FindCacheIndex(id)
                local r2 = ridx2 and cache.StillsCache[ridx2] or nil
                if not r2 then
                    local ok2, res2 = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
                    if ok2 and res2 and res2[1] then
                        cache.UpsertCacheRow(res2[1])
                        r2 = res2[1]
                    end
                end
                local authoritative_end = r2 and tonumber(r2.stage_end_ms) or end_ms
                if authoritative_end and authoritative_end > now_ms then
                    wait_ms = authoritative_end - now_ms
                else
                    wait_ms = 0
                end
            end
            if timer.cancel then break end

            if DBG then DBG:Info('Timer for prop ' .. tostring(id) .. ' elapsed; invoking ChangeStage (non-blocking) curStage=' .. tostring(curStage) .. ' currentbrew=' .. tostring(r.currentbrew)) end
            local calledOk, calledRes = false, nil
            local completed = false
            CreateThread(function()
                local okc, resc = pcall(function()
                    return Core.Callback.TriggerAwait('bcc-saloons:ChangeStage', id, curStage, 0, r.currentbrew)
                end)
                calledOk, calledRes = okc, resc
                completed = true
            end)
            -- wait for callback to complete but with timeout to avoid blocking thread
            local waited = 0
            local timeout_ms = 5000
            while not completed and waited < timeout_ms do
                Wait(100)
                waited = waited + 100
            end
            if not completed then
                if DBG then DBG:Error('Timer ChangeStage call timed out for id ' .. tostring(id) .. ' after ' .. tostring(timeout_ms) .. 'ms') end
            else
                if DBG then DBG:Info('Timer ChangeStage call finished for id ' .. tostring(id) .. ' ok=' .. tostring(calledOk) .. ' res=' .. tostring(calledRes)) end
            end
            -- After attempting ChangeStage, verify DB row actually advanced; if not, perform fallback update
            local ok2, updated = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
            if not ok2 or not updated or not updated[1] then
                if DBG then DBG:Error('Timer verify: failed to read updated row for id ' .. tostring(id)) end
            else
                local newStage = tonumber(updated[1].stage) or 0
                local db_isbrewing = tonumber(updated[1].isbrewing) or 0
                local db_brew = tostring(updated[1].currentbrew)
                if DBG then DBG:Info(('Timer verify: db row for id %s => stage=%s isbrewing=%s currentbrew=%s stage_end_ms=%s'):format(tostring(id), tostring(newStage), tostring(db_isbrewing), tostring(db_brew), tostring(updated[1].stage_end_ms))) end
                if newStage <= (tonumber(curStage) or 0) then
                    if DBG then DBG:Info('Timer verify: stage did not advance (cur=' .. tostring(curStage) .. ' db=' .. tostring(newStage) .. '), applying fallback update for id ' .. tostring(id)) end
                    -- Fallback: perform DB update and notify clients directly (mirror ChangeStage behavior)
                    local stageNext = math.max(0, curStage) + 1
                    local isbrewing_flag = 0
                    local currentbrew = r.currentbrew or 'None'
                    local sqlok, _ = pcall(function()
                        funcs.SafeMySQLQuery(
                            "UPDATE brewing SET `stage`= ?, currentbrew = ?, isbrewing = ?, started_at_ms = NULL, stage_end_ms = NULL WHERE id = ?",
                            { stageNext, currentbrew, isbrewing_flag, id }
                        )
                    end)
                    if not sqlok then
                        if DBG then DBG:Error('Timer fallback DB update failed for id ' .. tostring(id)) end
                    else
                        local ok3, updated2 = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
                        if ok3 and updated2 and updated2[1] then
                            cache.UpsertCacheRow(updated2[1])
                            pcall(function()
                                TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, funcs.ShallowCopyList(updated2))
                            end)
                            -- notify clients about stage end (owner-only config respected)
                            pcall(function()
                                local placed_by = updated2[1].placed_by
                                if Config and Config.notify_owner_only and placed_by then
                                    local sent = false
                                    local players = GetPlayers()
                                    for _, pid in ipairs(players) do
                                        local ok_user, candidate = pcall(function() return Core.getUser(tonumber(pid)) end)
                                        if ok_user and candidate and candidate.getUsedCharacter then
                                            local char = candidate.getUsedCharacter
                                            local cid = char and char.charIdentifier
                                            if cid and tostring(cid) == tostring(placed_by) then
                                                pcall(function() TriggerClientEvent('bcc-saloons:StageEnded', tonumber(pid), updated2[1].id, updated2[1].stage, updated2[1].currentbrew) end)
                                                sent = true
                                                break
                                            end
                                        end
                                    end
                                    if not sent then pcall(function() TriggerClientEvent('bcc-saloons:StageEnded', -1, updated2[1].id, updated2[1].stage, updated2[1].currentbrew) end) end
                                else
                                    pcall(function() TriggerClientEvent('bcc-saloons:StageEnded', -1, updated2[1].id, updated2[1].stage, updated2[1].currentbrew) end)
                                end
                            end)
                            if DBG then DBG:Info('Timer fallback advanced stage for id ' .. tostring(id) .. ' to ' .. tostring(stageNext)) end
                        end
                    end
                else
                    if DBG then DBG:Info('Timer verify: stage advanced in DB to ' .. tostring(newStage) .. ' for id ' .. tostring(id)) end
                end
            end
        end
        ActiveTimers[id] = nil
        if DBG then DBG:Info('Timer thread exited for prop ' .. tostring(id)) end
    end)
end

M.StartPropTimer = StartPropTimer
M.StopPropTimer = StopPropTimer
M.ActiveTimers = ActiveTimers
return M
