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

    -- saved
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

    local character = user.getUsedCharacter
    local starter_id = character and character.charIdentifier or nil

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

    local normalized = funcs.NormalizeIngredients(ingredientTable) or {}

    -- Take a snapshot of the player's inventory (single call) to build counts map
    pcall(function()
        exports.vorp_inventory:getUserInventoryItems(src, function(items)
            local counts = {}
            for _, it in ipairs(items or {}) do
                local iname = it.name or it.item or it.id
                local qty = tonumber(it.count or it.qty or it.amount or it.quantity) or 1
                if iname then counts[tostring(iname)] = (counts[tostring(iname)] or 0) + qty end
            end

            -- check against snapshot
            local missing = {}
            for _, ing in ipairs(normalized) do
                local itemName = tostring(ing.id)
                local required = tonumber(ing.qty) or 0
                local have = counts[itemName] or 0
                if have < required then
                    table.insert(missing, { id = itemName, label = ing.label or itemName, required = required, have = have })
                end
            end

            if #missing > 0 then
                if DBG then
                    DBG:Error('Player ' .. tostring(src) .. ' missing ingredients for brew ' .. tostring(rowBrew) .. ' stage ' .. tostring(rowStage))
                end
                Core.NotifyRightTip(src, locales.t('NoIngredients'), 4000)
                for _, m in ipairs(missing) do
                    Core.NotifyRightTip(src, 'Missing: ' .. tostring(m.label) .. ' x' .. tostring(m.required - (m.have or 0)), 5000)
                end
                local tip = (Mash and Mash[rowBrew] and Mash[rowBrew][1] and Mash[rowBrew][1].Tip) or
                    (Mash and Mash[rowBrew] and Mash[rowBrew].Tip) or
                    (Moonshine and Moonshine[rowBrew] and Moonshine[rowBrew].Tip)
                if tip then Core.NotifyRightTip(src, tip, 4000) end
                cb(false)
                return
            end

            -- Re-check availability immediately before removing to avoid race conditions
            for _, ing in ipairs(normalized) do
                local itemName = ing.id
                local required = tonumber(ing.qty) or 0
                local okcount, itemCount = pcall(function() return exports.vorp_inventory:getItemCount(src, nil, itemName) end)
                if not okcount or not itemCount or itemCount < required then
                    if DBG then DBG:Error('Player ' .. tostring(src) .. ' lost ingredients before removal for brew ' .. tostring(rowBrew) .. ' stage ' .. tostring(rowStage)) end
                    Core.NotifyRightTip(src, locales.t('NoIngredients'), 4000)
                    Core.NotifyRightTip(src, 'Missing: ' .. tostring(ing.label or itemName) .. ' x' .. tostring(required - (itemCount or 0)), 5000)
                    cb(false)
                    return
                end
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
                            if Mash[rowBrew][nextStage] then
                                local mf = Mash[rowBrew][nextStage].fermenttime or Mash[rowBrew][nextStage].fermentTime
                                if mf then wait_ms = mf * 60000 end
                            end
                            if not wait_ms then
                                local mf = Mash[rowBrew].fermenttime or Mash[rowBrew].fermentTime
                                if mf then wait_ms = mf * 60000 end
                            end
                        end
            else
                if Mash and Mash[rowBrew] then
                    if Mash[rowBrew][2] then
                        local mf = Mash[rowBrew][2].fermenttime or Mash[rowBrew][2].fermentTime
                        if mf then wait_ms = mf * 60000 end
                    end
                    if not wait_ms then
                        local mf = Mash[rowBrew].fermenttime or Mash[rowBrew].fermentTime
                        if mf then wait_ms = mf * 60000 end
                    end
                end
            end
            -- computed wait_ms
            local end_ms = nil
            if wait_ms > 0 then end_ms = now_ms + wait_ms end
            local oku, _ = funcs.SafeMySQLQuery(
                "UPDATE brewing SET isbrewing = ?, currentbrew = ?, started_at_ms = ?, stage_end_ms = ?, started_by = ? WHERE id = ?",
                { 1, rowBrew, now_ms, end_ms, starter_id, id })
            -- DB updated for brewing start
            if oku then
                local okr, updated = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
                if okr and updated and updated[1] then
                    cache.UpsertCacheRow(updated[1])
                    pcall(function()
                        TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, funcs.ShallowCopyList(updated))
                    end)
                end
            end
            if id then timers.StartPropTimer(id) end

            -- If we computed an end_ms when starting brewing, also send a tick-synced event immediately
            if end_ms then
                local server_now_ms = math.floor(os.time() * 1000)
                pcall(function()
                    TriggerClientEvent('bcc-saloons:StageEndTick', -1, id, end_ms, server_now_ms)
                end)
            end

            pcall(function() TriggerClientEvent('bcc-saloons:StartBrewingMash', src, nil, true, rowBrew) end)

            Core.NotifyRightTip(src, locales.t('TookIngredients'), 4000)
            cb(true)
        end)
    end)
end)

-- Return the player's item count for a given item (used by client UI)
Core.Callback.Register('bcc-saloons:GetItemCount', function(source, cb, itemName)
    local src = source
    if not itemName then cb(nil) return end
    local ok, count = pcall(function() return exports.vorp_inventory:getItemCount(src, nil, itemName) end)
    if not ok then
        if DBG then DBG:Warn('GetItemCount export failed for source ' .. tostring(src) .. ' item ' .. tostring(itemName)) end
        cb(nil)
        return
    end
    cb(tonumber(count) or 0)
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
    if tbl and type(tbl) == 'table' and tbl[brew] then
        amount = tbl[brew].Yield or tbl[brew].yield
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
                    if row.stage ~= nil and Moonshine and Moonshine[row.currentbrew] and Moonshine[row.currentbrew][row.stage] then
                        amount = Moonshine[row.currentbrew][row.stage].Yield or Moonshine[row.currentbrew][row.stage].yield
                    end
                    if not amount and Mash and Mash[row.currentbrew] then
                        amount = Mash[row.currentbrew].Yield or Mash[row.currentbrew].yield
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

    -- Prefer configured yield from recipe to avoid unexpected amounts
    local configYield = nil
    if Mash and Mash[brew] then
        configYield = Mash[brew].yield or Mash[brew].Yield
    end
    if Moonshine and Moonshine[brew] then
        local stageYield = nil
        -- fetch authoritative row for this prop if available so we can read its stage
        local row = nil
        if id then
            local idx = cache.FindCacheIndex(id)
            row = idx and cache.StillsCache[idx] or nil
            if not row then
                local ok, res = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
                if ok and res and res[1] then
                    cache.UpsertCacheRow(res[1])
                    row = res[1]
                end
            end
        end
        if row and row.stage and Moonshine[brew][row.stage] then
            stageYield = Moonshine[brew][row.stage].yield or Moonshine[brew][row.stage].Yield
        end
        configYield = stageYield or Moonshine[brew].yield or configYield
    end
    if configYield then
        amount = tonumber(configYield) or 1
    else
        amount = tonumber(amount)
    end
    if not amount or amount <= 0 then
        cb(false)
        return
    end

    -- determine product/item name to give player
    local productName = nil
    if tbl and type(tbl) == 'table' and tbl[brew] and tbl[brew].name then
        productName = tbl[brew].name
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
            if row and row.currentbrew then
                if Mash and Mash[row.currentbrew] and Mash[row.currentbrew].name then
                    productName = Mash[row.currentbrew].name
                elseif Moonshine and Moonshine[row.currentbrew] and Moonshine[row.currentbrew].name then
                    productName = Moonshine[row.currentbrew].name
                end
            end
        end
        -- fallback: if caller supplied a brew key that maps in configs
        if not productName then
            if Mash and Mash[brew] and Mash[brew].name then
                productName = Mash[brew].name
            elseif Moonshine and Moonshine[brew] and Moonshine[brew].name then
                productName = Moonshine[brew].name
            else
                productName = brew
            end
        end
    end

    local okCanCarry = exports.vorp_inventory:canCarryItem(src, productName, amount)
    if not okCanCarry then
        Core.NotifyRightTip(src, locales.t('FullItem'), 4000)
        cb(false)
        return
    end

    local added = false
    pcall(function()
        exports.vorp_inventory:addItem(src, productName, amount)
        added = true
    end)

    if not added then
        cb(false)
        return
    end

    if id and _G and _G['bcc_saloons_doChangeStage'] then
        local ok, res = pcall(function()
            return _G['bcc_saloons_doChangeStage'](0, id, 0, 0, 'None')
        end)
        if not ok and DBG then DBG:Error('FinishBrewing doChangeStage failed: ' .. tostring(res)) end
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
    -- ChangeStage wrapper
    -- delegate to implementation so timers can call it directly
    local ok, res = pcall(function()
        return _G['bcc_saloons_doChangeStage'](src, id, stage, isbrewing, currentbrew)
    end)
    if not ok then
        if DBG then DBG:Error('ChangeStage wrapper failed: ' .. tostring(res)) end
        cb(false)
        return
    end
    cb(res)
end)

-- Implementation of ChangeStage logic callable directly from timers (source may be nil/0)
_G['bcc_saloons_doChangeStage'] = function(source, id, stage, isbrewing, currentbrew)
    local src = source
    -- doChangeStage implementation
    local user = nil
    if type(src) == 'number' and src > 0 then
        user = Core.getUser(src)
        if not user then
            if DBG then DBG:Error('User not found for source: ' .. tostring(src)) end
            return false
        end
    end
    if not id or type(stage) ~= 'number' then
        return false
    end
    stage = math.max(0, stage)
    currentbrew = currentbrew or 'None'
    local ok
    if tonumber(isbrewing) == 0 then
        ok, _ = funcs.SafeMySQLQuery(
            "UPDATE brewing SET `stage`= ?, currentbrew = ?, isbrewing = ?, started_at_ms = NULL, stage_end_ms = NULL, started_by = NULL WHERE id = ?",
            { stage + 1, currentbrew, isbrewing, id })
    else
        ok, _ = funcs.SafeMySQLQuery(
            "UPDATE brewing SET `stage`= ?, currentbrew = ?, isbrewing = ? WHERE id = ?",
            { stage + 1, currentbrew, isbrewing, id })
    end
    if not ok then
        return false
    end
    local ok2, updated = funcs.SafeMySQLQuery("SELECT * FROM brewing WHERE id = ?", { id })
    if not ok2 then
        return false
    end
    if updated and updated[1] then
        cache.UpsertCacheRow(updated[1])
        pcall(function()
            TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, funcs.ShallowCopyList(updated))
        end)
        -- StageEnded notifications removed (no notifications sent)
        if DBG then DBG:Info('Changed stage for id ' .. tostring(id) .. ' to ' .. tostring(stage)) end
    end
    return true
end

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
    -- removed prop
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
    "UPDATE brewing SET `isbrewing`= 0, started_at_ms = NULL, stage_end_ms = NULL, started_by = NULL WHERE id = ?", { id })
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
    "UPDATE brewing SET isbrewing = ?, stage = ?, currentbrew = ?, started_at_ms = NULL, stage_end_ms = NULL, started_by = NULL WHERE id = ?",
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
    -- reset mash
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
    -- GetCoords called
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
    -- returning nearby props
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

-- Dev fast-forward command removed (use timers or tests). To re-enable, restore a development helper here.

return {}
