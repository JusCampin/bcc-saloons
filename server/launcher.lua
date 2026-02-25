-- launcher.lua: primary server entry point
local function load_module(path)
    local res = GetCurrentResourceName()
    local src = LoadResourceFile(res, path)
    if not src then error('load_module: missing ' .. path) end
    local fn, err = load(src, path)
    if not fn then error(err) end
    return fn()
end

local cache = load_module('server/cache.lua')
local funcs = load_module('server/functions.lua')
-- expose shared instances so handlers reuse them instead of loading duplicates
_G['bcc_saloons_cache'] = cache
_G['bcc_saloons_funcs'] = funcs
local timers = load_module('server/timers.lua')
_G['bcc_saloons_timers'] = timers
local pending = load_module('server/pending_returns.lua')
_G['bcc_saloons_pending'] = pending
-- Composite global for convenience
_G['bcc_saloons'] = {
    cache = cache,
    funcs = funcs,
    timers = timers,
    pending = pending
}

-- populate cache on resource start and start timers for brews (handled by timers module elsewhere)
CreateThread(function()
    cache.LoadStillsCache()
    -- send current cache to clients on startup
    pcall(function()
        local payload = nil
        if funcs and funcs.ShallowCopyList then
            payload = funcs.ShallowCopyList(cache.StillsCache)
        else
            payload = cache.StillsCache
        end
        TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, payload)
        local payloadCount = (type(payload) == 'table') and #payload or 0
            if DBG then DBG:Info('SendPropsFromWorld: server sent payload count=' .. tostring(payloadCount) .. ' cacheCount=' .. tostring(#cache.StillsCache)) end
    end)
    -- resend after a short delay to catch clients that register events slightly later
    CreateThread(function()
        Wait(5000)
        pcall(function()
            local payload2 = (funcs and funcs.ShallowCopyList) and funcs.ShallowCopyList(cache.StillsCache) or cache.StillsCache
            TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, payload2)
            local pc2 = (type(payload2) == 'table') and #payload2 or 0
            if DBG then DBG:Info('SendPropsFromWorld (delayed): server sent payload count=' .. tostring(pc2) .. ' cacheCount=' .. tostring(#cache.StillsCache)) end
        end)
    end)
    for _, r in ipairs(cache.StillsCache) do
        if r and tonumber(r.isbrewing) == 1 then
            if timers and timers.StartPropTimer then
                timers.StartPropTimer(r.id)
            else
                pcall(function() load_module('server/timers.lua').StartPropTimer(r.id) end)
            end
        end
    end
end)

-- periodic cache refresher
CreateThread(function()
    while true do
        Wait(60000)
        local old = #cache.StillsCache
        local ok = cache.LoadStillsCache()
        if not ok then
            if DBG then DBG:Warning('Periodic cache refresh failed at ' .. os.date('%c') .. ' See earlier MySQL error.') end
        end
        if #cache.StillsCache ~= old then
            pcall(function()
                TriggerClientEvent('bcc-saloons:SendPropsFromWorld', -1, funcs.ShallowCopyList(cache.StillsCache))
            end)
        end
    end
end)

-- Handlers and usable-item registrations live in server/handlers.lua
load_module('server/handlers.lua')

BccUtils.Versioner.checkFile(GetCurrentResourceName(), 'https://github.com/BryceCanyonCounty/bcc-saloons')
