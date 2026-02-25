-- Shared client helper functions
local M = {}

local _cb_results = {}

function M.CallServerAwait(name, timeout_ms, ...)
    local args = { ... }
    local id = tostring(math.random(1,1000000000)) .. tostring(GetGameTimer())
    _cb_results[id] = { done = false, ok = false, res = nil }
    CreateThread(function()
        local ok, res = pcall(function()
            return Core.Callback.TriggerAwait(name, table.unpack(args))
        end)
        _cb_results[id].done = true
        _cb_results[id].ok = ok
        _cb_results[id].res = res
    end)
    local waited = 0
    local interval = 50
    timeout_ms = timeout_ms or 3000
    while waited < timeout_ms do
        if _cb_results[id].done then
            local ok, res = _cb_results[id].ok, _cb_results[id].res
            _cb_results[id] = nil
            return ok, res
        end
        Wait(interval)
        waited = waited + interval
    end
    -- timeout
    _cb_results[id] = nil
    -- notify player of server timeout
    pcall(function()
        Core.NotifyRightTip(locales.t('ServerNoResponse'), 4000)
    end)
    return false, nil
end

function M.CallServerAsync(name, ...)
    local args = { ... }
    CreateThread(function()
        pcall(function()
            Core.Callback.TriggerAwait(name, table.unpack(args))
        end)
    end)
end

function M.LoadModel(model, modelName)
    if not IsModelValid(model) then
        DBG:Error('Invalid model:' .. tostring(modelName))
        return
    end

    if not HasModelLoaded(model) then
        RequestModel(model, false)

        local timeout = 10000
        local startTime = GetGameTimer()

        while not HasModelLoaded(model) do
            if GetGameTimer() - startTime > timeout then
                DBG:Error('Failed to load model:' .. tostring(modelName))
                return
            end
            Wait(10)
        end
    end
end

function M.PlayAnim(animDict, animName, time,loopUntilTimeOver)
    -- Validate inputs
    if not animDict or not animName then
        DBG:Error('Invalid animation dictionary or name for PlayAnim: ' .. tostring(animDict) .. ', ' .. tostring(animName))
        return
    end

    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) or playerPed == 0 then
        DBG:Error('Player ped does not exist')
        return
    end

    -- Load animation dictionary
    if not HasAnimDictLoaded(animDict) then
        RequestAnimDict(animDict)
        local timeout = 10000
        local startTime = GetGameTimer()

        while not HasAnimDictLoaded(animDict) do
            if GetGameTimer() - startTime > timeout then
                DBG:Error('Failed to load animation dictionary:' .. tostring(animDict))
                return
            end
            Wait(10)
        end
    end

    local animTime = time

    -- Set animation flags
    local flag = 16 -- Default flag for one-time playback
    if loopUntilTimeOver then
        flag = 1    -- Flag for looping
        animTime = -1
    end

    -- Play animation
    TaskPlayAnim(playerPed, animDict, animName, 1.0, 1.0, animTime, flag, 0, true, 0, false, 0, false)

    -- Wait for animation to complete
    Wait(time)

    ClearPedTasks(playerPed)
end

-- export global fallback for environments where `require` fails
functions = M
return M
