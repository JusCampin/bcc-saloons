local function load_module(path)
    local res = GetCurrentResourceName()
    local src = LoadResourceFile(res, path)
    if not src then error('load_module: missing ' .. path) end
    local fn, err = load(src, path)
    if not fn then error(err) end
    return fn()
end

-- Prefer shared instances (set by launcher) to avoid duplicate module state
local cache = _G['bcc_saloons_cache'] or load_module('server/cache.lua')
_G['bcc_saloons_cache'] = cache
local timers = _G['bcc_saloons_timers'] or load_module('server/timers.lua')
_G['bcc_saloons_timers'] = timers
local funcs = _G['bcc_saloons_funcs'] or load_module('server/functions.lua')
_G['bcc_saloons_funcs'] = funcs
local pending = _G['bcc_saloons_pending'] or load_module('server/pending_returns.lua')
_G['bcc_saloons_pending'] = pending

-- register usable items
exports.vorp_inventory:registerUsableItem(Config.props.barrel, function(data)
    if not data or not data.source or not data.item or not data.item.item then
        if DBG then DBG:Warning('registerUsableItem: invalid data for barrel') end
        return
    end
    local src = data.source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        return
    end
    local itemname = data.item.item
    if itemname ~= Config.props.barrel then
        if DBG then DBG:Warning('registerUsableItem: unexpected item for barrel: ' .. tostring(itemname)) end
        return
    end
    pcall(function()
        TriggerClientEvent('bcc-saloons:placeProp', src, itemname)
    end)
    pcall(function()
        exports.vorp_inventory:closeInventory(src)
    end)
end)

exports.vorp_inventory:registerUsableItem(Config.props.still, function(data)
    if not data or not data.source or not data.item or not data.item.item then
        if DBG then DBG:Warning('registerUsableItem: invalid data for still') end
        return
    end
    local src = data.source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        return
    end
    local itemname = data.item.item
    if itemname ~= Config.props.still then
        if DBG then DBG:Warning('registerUsableItem: unexpected item for still: ' .. tostring(itemname)) end
        return
    end
    pcall(function()
        TriggerClientEvent('bcc-saloons:placeProp', src, itemname)
    end)
    pcall(function()
        exports.vorp_inventory:closeInventory(src)
    end)
end)

-- Callbacks (moved from main)
Core.Callback.Register('bcc-saloons:SaveToDB', function(source, cb, name, x, y, z, h)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end

    if not x or not y or not z then
        cb(false)
        return
    end

    local uuid = BccUtils.UUID()
    local character = user.getUsedCharacter
    local charid = character.charIdentifier
    local placed_by = tostring(charid)

    do
        local ok, _ = funcs.SafeMySQLQuery([[
            INSERT INTO `brewing` (`id`, `propname`, `x`, `y`, `z`, `h`, `isbrewing`, `stage`, `currentbrew`, `placed_by`)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], { uuid, name, x, y, z, h, 0, 1, 'None', placed_by })
        if not ok then
            cb(false)
            return
        end
    end

    pcall(function() exports.vorp_inventory:subItem(src, name, 1) end)

    do
        local ok, inserted = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { uuid })
        if not ok then
            cb(false)
            return
        end
        if inserted and inserted[1] then
            cache.UpsertCacheRow(inserted[1])
            pcall(function()
                TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, funcs.ShallowCopyList(inserted))
            end)
        end
    end

    if DBG then DBG:Success('Saved prop to DB: ' .. tostring(uuid) .. ' by source ' .. tostring(src)) end
    cb(uuid)
end)

Core.Callback.Register('bcc-saloons:CheckIngredients', function(source, cb, id, stage, currentbrew)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end

    local rowStage = stage
    local rowBrew = currentbrew
    local dbBrew = nil

    -- If we have an id, try to read the authoritative row from cache/DB
    if id then
        local idx = cache.FindCacheIndex(id)
        if idx then
            dbBrew = cache.StillsCache[idx].currentbrew
        else
            local ok, res = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
            if ok and res and res[1] then
                cache.UpsertCacheRow(res[1])
                dbBrew = res[1].currentbrew
            end
        end
    end

    local ingredientTable = nil
    if rowStage ~= nil then
        -- stage-specified checks: accept both Moonshine and Mash stage entries
        local brewKey = rowBrew
        if (not brewKey or brewKey == 'None') and dbBrew then brewKey = dbBrew end
        if Moonshine and Moonshine[brewKey] and Moonshine[brewKey][rowStage] then
            ingredientTable = Moonshine[brewKey][rowStage].ingredients
        elseif Mash and Mash[brewKey] and Mash[brewKey][rowStage] then
            ingredientTable = Mash[brewKey][rowStage].ingredients
        else
            Core.NotifyRightTip(src, locales.t('NoIngredients'), 4000)
            cb(false)
            return
        end
        rowBrew = brewKey
    else
        local brewKey = rowBrew
        if (not brewKey or brewKey == 'None') and dbBrew then brewKey = dbBrew end
        if not (Mash and Mash[brewKey]) then
            Core.NotifyRightTip(src, locales.t('NoIngredients'), 4000)
            cb(false)
            return
        end
        if Mash[brewKey][1] and Mash[brewKey][1].ingredients then
            ingredientTable = Mash[brewKey][1].ingredients
        else
            ingredientTable = Mash[brewKey].ingredients
        end
        rowBrew = brewKey
    end

    local canTake = true
    local missingIng = nil
    local normalized = funcs.NormalizeIngredients(ingredientTable)

    -- First pass: ensure player has all required ingredients
    for _, ing in ipairs(normalized) do
        local itemName = ing.id
        local required = tonumber(ing.qty) or 0
        local okcount, itemCount = pcall(function() return exports.vorp_inventory:getItemCount(src, nil, itemName) end)
        if not okcount then itemCount = nil end
        if DBG then
            DBG:Info('Checking ingredient for player ' .. tostring(src) .. ': ' .. tostring(itemName) .. ' required=' .. tostring(required) .. ' have=' .. tostring(itemCount))
        end
        if not itemCount or itemCount < required then
            canTake = false
            missingIng = { id = itemName, label = ing.label or itemName, required = required, have = itemCount or 0 }
            break
        end
    end

    if not canTake then
        if DBG then
            DBG:Error('Player ' .. tostring(src) .. ' does not have required ingredients for brew ' .. tostring(rowBrew) .. ' stage ' .. tostring(rowStage))
        end
        Core.NotifyRightTip(src, locales.t('NoIngredients'), 4000)
        if missingIng then
            Core.NotifyRightTip(src, 'Missing: ' .. tostring(missingIng.label) .. ' x' .. tostring(missingIng.required - (missingIng.have or 0)), 5000)
        end
        local tip = (Mash and Mash[rowBrew] and Mash[rowBrew][1] and Mash[rowBrew][1].Tip) or
            (Mash and Mash[rowBrew] and Mash[rowBrew].Tip) or
            (Moonshine and Moonshine[rowBrew] and Moonshine[rowBrew].Tip)
        if tip then Core.NotifyRightTip(src, tip, 4000) end
        cb(false)
        return
    end

    -- Remove items now that we've confirmed availability
    for _, ing in ipairs(normalized) do
        local itemName = ing.id
        local required = tonumber(ing.qty) or 0
        pcall(function() exports.vorp_inventory:subItem(src, itemName, required) end)
    end

    -- Compute wait time and persist brewing start
    local now_ms = math.floor(os.time() * 1000)
    local wait_ms = 0
    if rowStage ~= nil then
        local nextStage = tonumber(rowStage) + 1
        if Mash and Mash[rowBrew] then
            if Mash[rowBrew][nextStage] and Mash[rowBrew][nextStage].fermenttime then
                wait_ms = Mash[rowBrew][nextStage].fermenttime * 60000
            elseif Mash[rowBrew].fermenttime then
                wait_ms = Mash[rowBrew].fermenttime * 60000
            end
        end
    else
        if Mash and Mash[rowBrew] then
            if Mash[rowBrew][2] and Mash[rowBrew][2].fermenttime then
                wait_ms = Mash[rowBrew][2].fermenttime * 60000
            elseif Mash[rowBrew].fermenttime then
                wait_ms = Mash[rowBrew].fermenttime * 60000
            end
        end
    end
    if DBG then DBG:Info('CheckIngredients: computed wait_ms=' .. tostring(wait_ms) .. ' for brew=' .. tostring(rowBrew) .. ' id=' .. tostring(id)) end
    local end_ms = nil
    if wait_ms > 0 then end_ms = now_ms + wait_ms end
    local oku, _ = funcs.SafeMySQLQuery(
        "UPDATE brewing SET isbrewing = ?, currentbrew = ?, started_at_ms = ?, stage_end_ms = ? WHERE id = ?",
        { 1, rowBrew, now_ms, end_ms, id })
    if DBG then DBG:Info('CheckIngredients: updated DB for id=' .. tostring(id) .. ' ok=' .. tostring(oku) .. ' end_ms=' .. tostring(end_ms)) end
    if oku then
        local okr, updated = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
        if okr and updated and updated[1] then
            cache.UpsertCacheRow(updated[1])
            pcall(function()
                TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, funcs.ShallowCopyList(updated))
            end)
        end
    end
    if id then
        if DBG then DBG:Info('CheckIngredients: invoking timers.StartPropTimer for id=' .. tostring(id)) end
        timers.StartPropTimer(id)
    end

    if DBG then DBG:Info('Triggering StartBrewingMash to src ' .. tostring(src) .. ' brew ' .. tostring(rowBrew)) end
    local ok, err = pcall(function()
        TriggerClientEvent('bcc-saloons:StartBrewingMash', src, nil, true, rowBrew)
    end)
    if not ok then
        if DBG then DBG:Error('TriggerClientEvent StartBrewingMash failed: ' .. tostring(err)) end
    else
        if DBG then DBG:Info('StartBrewingMash TriggerClientEvent executed for src ' .. tostring(src) .. ' brew ' .. tostring(rowBrew)) end
    end

    Core.NotifyRightTip(src, locales.t('TookIngredients'), 4000)
    cb(true)
end)

Core.Callback.Register('bcc-saloons:FinishBrewing', function(source, cb, id, brew, tbl)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end
    local amount
    if tbl and type(tbl) == 'table' and tbl[brew] and tbl[brew].Yield then
        amount = tbl[brew].Yield
    else
        if id then
            local idx = cache.FindCacheIndex(id)
            local row = idx and cache.StillsCache[idx] or nil
            if not row then
                local ok, res = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
                if ok and res and res[1] then
                    cache.UpsertCacheRow(res[1])
                    row = res[1]
                end
            end
            if row then
                if row.stage ~= nil and Moonshine and Moonshine[row.currentbrew] and Moonshine[row.currentbrew][row.stage] and Moonshine[row.currentbrew][row.stage].Yield then
                    amount = Moonshine[row.currentbrew][row.stage].Yield
                elseif Mash and Mash[row.currentbrew] and Mash[row.currentbrew].Yield then
                    amount = Mash[row.currentbrew].Yield
                end
            end
        end
    end

    if not amount then
        cb(false)
        return
    end

    if not brew or type(brew) ~= 'string' then
        cb(false)
        return
    end

    amount = tonumber(amount)
    if not amount or amount <= 0 then
        cb(false)
        return
    end

    local okCanCarry = exports.vorp_inventory:canCarryItem(src, brew, amount)
    if not okCanCarry then
        Core.NotifyRightTip(src, locales.t('FullItem'), 4000)
        cb(false)
        return
    end

    local added = false
    pcall(function()
        exports.vorp_inventory:addItem(src, brew, amount)
        added = true
    end)

    if not added then
        cb(false)
        return
    end

    if id and Core and Core.Callback and Core.Callback.TriggerAwait then
        CreateThread(function()
            pcall(function()
                Core.Callback.TriggerAwait('bcc-saloons:ChangeStage', id, 0, 0, 'None')
            end)
        end)
    end
    cb(true)
end)

Core.Callback.Register('bcc-saloons:SyncSmokeServer', function(source, cb, waittime)
    local wt = tonumber(waittime) or 0
    if wt < 0 then wt = 0 end
    if wt > 600000 then wt = 600000 end
    local ok, err = pcall(function()
        TriggerClientEvent('bcc-saloons:SyncSmokeClient', -1, wt)
    end)
    if not ok then
        if DBG then DBG:Error('SyncSmokeServer TriggerClientEvent error: ' .. tostring(err)) end
        cb(false)
        return
    end
    cb(true)
end)

Core.Callback.Register('bcc-saloons:ChangeStage', function(source, cb, id, stage, isbrewing, currentbrew)
    local src = source
    if DBG then
        local info = ('ChangeStage called with source=%s id=%s stage=%s isbrewing=%s currentbrew=%s'):format(tostring(source), tostring(id), tostring(stage), tostring(isbrewing), tostring(currentbrew))
        DBG:Info(info)
    end
    local user = nil
    -- allow server-side callers (nil/0) to advance stages (timers call this)
    if type(src) == 'number' and src > 0 then
        user = Core.getUser(src)
        if not user then
            DBG:Error('User not found for source: ' .. tostring(src))
            cb(false)
            return
        end
    end
    if not id or type(stage) ~= 'number' then
        cb(false)
        return
    end
    stage = math.max(0, stage)
    currentbrew = currentbrew or 'None'
    local ok
    if tonumber(isbrewing) == 0 then
        ok, _ = funcs.SafeMySQLQuery(
            "UPDATE brewing SET `stage`= ?, currentbrew = ?, isbrewing = ?, started_at_ms = NULL, stage_end_ms = NULL WHERE id = ?",
            { stage + 1, currentbrew, isbrewing, id })
    else
        ok, _ = funcs.SafeMySQLQuery(
            "UPDATE brewing SET `stage`= ?, currentbrew = ?, isbrewing = ? WHERE id = ?",
            { stage + 1, currentbrew, isbrewing, id })
    end
    if not ok then
        cb(false)
        return
    end
    local ok2, updated = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
    if not ok2 then
        cb(false)
        return
    end
    if updated and updated[1] then
        cache.UpsertCacheRow(updated[1])
        pcall(function()
            TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, funcs.ShallowCopyList(updated))
        end)
            -- Notify clients that a stage has ended for this prop. Config will decide
            -- whether to show an action indicator based on proximity/ownership.
            pcall(function()
                -- Notify either only the owner (if online) or broadcast to all clients based on config
                local placed_by = updated[1].placed_by
                if Config and Config.notify_owner_only and placed_by then
                    local sent = false
                    local players = GetPlayers()
                    for _, pid in ipairs(players) do
                        local ok_user, candidate = pcall(function() return Core.getUser(tonumber(pid)) end)
                        if ok_user and candidate and candidate.getUsedCharacter then
                            local char = candidate.getUsedCharacter
                            local cid = char and char.charIdentifier
                            if cid and tostring(cid) == tostring(placed_by) then
                                pcall(function() TriggerClientEvent('bcc-saloons:StageEnded', tonumber(pid), updated[1].id, updated[1].stage, updated[1].currentbrew) end)
                                sent = true
                                break
                            end
                        end
                    end
                    -- fallback: if owner not found online, broadcast to all so nearby clients still get the tip
                    if not sent then pcall(function() TriggerClientEvent('bcc-saloons:StageEnded', -1, updated[1].id, updated[1].stage, updated[1].currentbrew) end) end
                else
                    pcall(function() TriggerClientEvent('bcc-saloons:StageEnded', -1, updated[1].id, updated[1].stage, updated[1].currentbrew) end)
                end
            end)
        if DBG then DBG:Info('Changed stage for id ' .. tostring(id) .. ' to ' .. tostring(stage)) end
    end
    cb(true)
end)

Core.Callback.Register('bcc-saloons:RemoveFromDb', function(source, cb, id, object, x, y, z)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end
    local character = user.getUsedCharacter
    local job = character.job

    if not id or not object then
        cb(false)
        return
    end

    local ok, _ = funcs.SafeMySQLQuery("DELETE FROM brewing WHERE id = ?", { id })
    if not ok then
        cb(false)
        return
    end
    cache.RemoveCacheRow(id)
    timers.StopPropTimer(id)
    pcall(function()
        TriggerClientEvent('bcc-saloons:DeleteProp', -1, object, x, y, z, id, src)
    end)
    pcall(function()
        TriggerClientEvent('bcc-saloons:DestroyProp', src, object, x, y, z, id)
    end)
    if DBG then DBG:Info('Removed prop from DB: ' .. tostring(id) .. ' by source ' .. tostring(src)) end
    cb(true)

    if Config.returnProps then
        pending.Enqueue({
            due_ms = math.floor(os.time() * 1000) + ((tonumber(Config.timeToDestroy) or 10) * 1000),
            src = src,
            job = job,
            object = object,
            returnProps = true,
        })
    end
end)

Core.Callback.Register('bcc-saloons:StopBrewing', function(source, cb, id)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end
    if not id or (type(id) ~= 'string' and type(id) ~= 'number') then
        cb(false)
        return
    end
    local ok, _ = funcs.SafeMySQLQuery(
    "UPDATE brewing SET `isbrewing`= 0, started_at_ms = NULL, stage_end_ms = NULL WHERE id = ?", { id })
    if not ok then
        cb(false)
        return
    end
    timers.StopPropTimer(id)
    cb(true)
end)

Core.Callback.Register('bcc-saloons:ResetMash', function(source, cb, id)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end
    if not id then
        DBG:Error('Invalid id provided by source: ' .. tostring(src))
        cb(false)
        return
    end
    local ok, _ = funcs.SafeMySQLQuery(
    "UPDATE brewing SET isbrewing = ?, stage = ?, currentbrew = ?, started_at_ms = NULL, stage_end_ms = NULL WHERE id = ?",
        { 0, 1, 'None', id })
    if not ok then
        cb(false)
        return
    end
    local ok2, updated = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
    if ok2 and updated and updated[1] then
        cache.UpsertCacheRow(updated[1])
        pcall(function()
            TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, funcs.ShallowCopyList(updated))
        end)
    end
    timers.StopPropTimer(id)
    if DBG then DBG:Info('Reset mash for id ' .. tostring(id) .. ' by source ' .. tostring(src)) end
    cb(true)
end)

Core.Callback.Register('bcc-saloons:GetProps', function(source, cb, ...)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end
    cb(funcs.ShallowCopyList(cache.StillsCache) or {})
end)

Core.Callback.Register('bcc-saloons:GetRemainingTime', function(source, cb, id)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end
    if not id then
        cb(false)
        return
    end
    local idx = cache.FindCacheIndex(id)
    local row = idx and cache.StillsCache[idx] or nil
    if not row then
        local ok, res = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
        if not ok or not res or not res[1] then
            cb(false)
            return
        end
        row = res[1]
        cache.UpsertCacheRow(row)
    end
    local end_ms = tonumber(row.stage_end_ms) or nil
    if not end_ms then
        cb(true, nil)
        return
    end
    local now_ms = math.floor(os.time() * 1000)
    local remaining = end_ms - now_ms
    if remaining < 0 then remaining = 0 end
    cb(true, remaining)
end)

Core.Callback.Register('bcc-saloons:GetPropById', function(source, cb, id)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end
    if not id then
        cb(false)
        return
    end
    local idx = cache.FindCacheIndex(id)
    if idx then
        cb(funcs.ShallowCopyRow(cache.StillsCache[idx]))
        return
    end
    local ok, result = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
    if not ok then
        cb(false)
        return
    end
    if result and result[1] then
        cache.UpsertCacheRow(result[1])
        cb(funcs.ShallowCopyRow(result[1]))
    else
        cb(false)
    end
end)

Core.Callback.Register('bcc-saloons:GetCoords', function(source, cb, x, y, z)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end
    local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
    if not nx or not ny or not nz then
        cb(false)
        return
    end
    if DBG then
        DBG:Info(('GetCoords called by %s at %s,%s,%s - cache size %d'):format(tostring(src), tostring(nx), tostring(ny), tostring(nz), #cache.StillsCache))
    end
    local nearby = {}
    local maxdist = math.max(0, tonumber(Config.interactDistance) or 5)
    local maxdist2 = maxdist * maxdist
    for _, v in ipairs(cache.StillsCache) do
        if v and v.x and v.y and v.z then
            local vx, vy, vz = tonumber(v.x), tonumber(v.y), tonumber(v.z)
            if vx and vy and vz then
                local dx = vx - nx
                local dy = vy - ny
                local dz = vz - nz
                local dist2 = dx * dx + dy * dy + dz * dz
                if dist2 <= maxdist2 then
                    table.insert(nearby, funcs.ShallowCopyRow(v))
                end
            end
        end
    end
    if DBG then DBG:Info(('GetCoords result: found %d nearby (maxdist %s)'):format(#nearby, tostring(maxdist))) end
    cb(nearby)
end)

Core.Callback.Register('bcc-saloons:ReloadCache', function(source, cb)
    local src = source
    local user = Core.getUser(src)
    if not user then
        DBG:Error('User not found for source: ' .. tostring(src))
        cb(false)
        return
    end
    local ok = cache.LoadStillsCache()
    cb(ok)
end)

-- Dev: console-only fast-forward command to trigger stage change for testing
RegisterCommand('bcc-saloons-fastforward', function(source, args, raw)
    -- allow players to run this in dev mode; otherwise require console (source 0)
    if tonumber(source) ~= 0 and not (Config and Config.devMode and Config.devMode.active) then
        if DBG then DBG:Info('bcc-saloons-fastforward: console-only command (or enable Config.devMode.active)') else print('bcc-saloons-fastforward: console-only command') end
        return
    end
    if DBG then DBG:Info(('bcc-saloons-fastforward invoked by source=%s args=%s'):format(tostring(source), tostring(args and args[1] or 'nil'))) end
    local id = args and args[1]
    if not id then
        if DBG then DBG:Info('Usage: bcc-saloons-fastforward <id>') else print('Usage: bcc-saloons-fastforward <id>') end
        return
    end
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
        if DBG then DBG:Info('bcc-saloons-fastforward: prop not found: ' .. tostring(id)) else print('bcc-saloons-fastforward: prop not found: ' .. tostring(id)) end
        return
    end
    local curStage = tonumber(row.stage) or 0
    -- Dev-only: perform the ChangeStage DB update and client notify directly for testing
    do
        local stage = math.max(0, curStage)
        local newStage = stage + 1
        local oku, _ = funcs.SafeMySQLQuery(
            "UPDATE brewing SET `stage`= ?, currentbrew = ?, isbrewing = ?, started_at_ms = NULL, stage_end_ms = NULL WHERE id = ?",
            { newStage, row.currentbrew or 'None', 0, id })
        if not oku then
            if DBG then DBG:Error('bcc-saloons-fastforward: DB update failed for id ' .. tostring(id)) end
            return
        end
        local ok2, updated = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
        if ok2 and updated and updated[1] then
            cache.UpsertCacheRow(updated[1])
            pcall(function()
                TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, funcs.ShallowCopyList(updated))
            end)
            pcall(function()
                local placed_by = updated[1].placed_by
                if Config and Config.notify_owner_only and placed_by then
                    local sent = false
                    local players = GetPlayers()
                    for _, pid in ipairs(players) do
                        local ok_user, candidate = pcall(function() return Core.getUser(tonumber(pid)) end)
                        if ok_user and candidate and candidate.getUsedCharacter then
                            local char = candidate.getUsedCharacter
                            local cid = char and char.charIdentifier
                            if cid and tostring(cid) == tostring(placed_by) then
                                pcall(function() TriggerClientEvent('bcc-saloons:StageEnded', tonumber(pid), updated[1].id, updated[1].stage, updated[1].currentbrew) end)
                                sent = true
                                break
                            end
                        end
                    end
                    if not sent then pcall(function() TriggerClientEvent('bcc-saloons:StageEnded', -1, updated[1].id, updated[1].stage, updated[1].currentbrew) end) end
                else
                    pcall(function() TriggerClientEvent('bcc-saloons:StageEnded', -1, updated[1].id, updated[1].stage, updated[1].currentbrew) end)
                end
            end)
            if DBG then DBG:Info('bcc-saloons-fastforward: advanced stage for id ' .. tostring(id) .. ' to ' .. tostring(newStage)) end
        else
            if DBG then DBG:Error('bcc-saloons-fastforward: failed to SELECT updated row for id ' .. tostring(id)) end
        end
    end
end, false)

return {}
