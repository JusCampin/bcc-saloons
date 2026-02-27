-- brewing.lua: handles brewing events and client particle sync
-- Expects globals: Moonshine, Mash, ActiveProps, Config, PlayAnim, TipBottom, Core

local M = {}
local function safeRequire(name)
    local ok, mod = pcall(require, name)
    if ok and mod then return mod end
    return _G[name] or mod
end
local funcs = safeRequire('functions')

RegisterNetEvent('bcc-saloons:StartBrewingMoonshine', function(stage, isbrewing, currentbrew)
    if isbrewing then
        local playerPed = PlayerPedId()
        RequestAnimDict("script_re@moonshine_camp@player_put_in_herbs")
        while (not HasAnimDictLoaded("script_re@moonshine_camp@player_put_in_herbs")) do
            Wait(100)
        end
        Citizen.InvokeNative(0xEA47FE3719165B94, playerPed, "script_re@moonshine_camp@player_put_in_herbs", "put_in_still", 8.0, -8.0, -1, 31, 0,
            true, 0, false, 0, false)
        Wait(4000)
        ClearPedSecondaryTask(playerPed)

        local stilltime_ms = 0
        if Moonshine and Moonshine[currentbrew] and Moonshine[currentbrew][stage] and Moonshine[currentbrew][stage].stilltime then
            stilltime_ms = Moonshine[currentbrew][stage].stilltime * 60000
        end
        funcs.CallServerAsync('bcc-saloons:SyncSmokeServer', stilltime_ms)
        for _, v in pairs(ActiveProps) do
            funcs.CallServerAsync('bcc-saloons:ChangeStage', v.id, v.stage, 1, currentbrew)
            Wait(stilltime_ms)
            funcs.CallServerAsync('bcc-saloons:StopBrewing', v.id)
        end
    end
end)

RegisterNetEvent('bcc-saloons:StartBrewingMash', function(stage, isbrewing, currentbrew)
    DBG:Info('Received StartBrewingMash event: stage=' .. tostring(stage) .. ' isbrewing=' .. tostring(isbrewing) .. ' brew=' .. tostring(currentbrew))
    if isbrewing then
        local animDict = "script_re@moonshine_camp@player_put_in_herbs"
        local animName = "put_in_still"
        funcs.PlayAnim(animDict, animName, 4000, false, 31)
        -- clear the keep-kneeling flag so menu closes behave normally
        TriggerEvent('bcc-saloons:ClearKeepKneeling')
        -- notify UI to close mash menu now that brewing is starting
        TriggerEvent('bcc-saloons:CloseMashMenu')
        -- RequestAnimDict("script_re@moonshine_camp@player_put_in_herbs")
        -- while (not HasAnimDictLoaded("script_re@moonshine_camp@player_put_in_herbs")) do
        --     Wait(100)
        -- end
        -- Citizen.InvokeNative(0xEA47FE3719165B94, playerPed, "script_re@moonshine_camp@player_put_in_herbs", "put_in_still", 8.0, -8.0, -1, 31, 0,
        --     true, 0, false, 0, false)
        -- Wait(4000)
        -- ClearPedSecondaryTask(playerPed)

        if stage == nil then
            local ferment_ms = 0
            if Mash and Mash[currentbrew] and Mash[currentbrew][2] and Mash[currentbrew][2].fermentTime then
                ferment_ms = Mash[currentbrew][2].fermentTime * 60000
            elseif Mash and Mash[currentbrew] and Mash[currentbrew].fermentTime then
                ferment_ms = Mash[currentbrew].fermentTime * 60000
            end
            funcs.CallServerAsync('bcc-saloons:SyncSmokeServer', ferment_ms)
        end
    end
end)

RegisterNetEvent('bcc-saloons:SyncSmokeClient', function(waitTime)
    local wt = tonumber(waitTime) or 0
    if wt < 0 then wt = 0 end
    if wt > 600000 then wt = 600000 end

    if not ActiveProps or #ActiveProps == 0 then return end

    local assetName = 'scr_distance_smoke'
    local assetHash = GetHashKey(assetName)
    if not HasNamedPtfxAssetLoaded(assetHash) then
        RequestNamedPtfxAsset(assetHash)

        local timeout = 10000
        local startTime = GetGameTimer()
        while not HasNamedPtfxAssetLoaded(assetHash) do
            if GetGameTimer() - startTime > timeout then
                if DBG then DBG:Error('Failed to load particle asset: ' .. tostring(assetName)) end
                return
            end
            Wait(10)
        end
    end

    UseParticleFxAsset(assetName)

    local particles = {}
    for _, v in pairs(ActiveProps) do
        if v and v.x and v.y and v.z then
            local ok, smoke = pcall(function()
                return StartParticleFxLoopedAtCoord('scr_campfire_distance_smoke_lod', v.x, v.y, v.z, 0.0, 0.0, 0.0, 0.5, false, false, false, true)
            end)
            if ok and smoke then table.insert(particles, smoke) end
        end
    end

    Wait(wt)

    for _, h in ipairs(particles) do
        if h then
            pcall(function() StopParticleFxLooped(h, true) end)
        end
    end
end)

brewing = M
return M
