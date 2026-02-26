-- sync.lua: network handlers for props and deletion coordination
-- Expects globals: Stills, ActiveProps, DBG, Core, Config, TempObj, recentlyDestroyed

local M = {}
local function safeRequire(name)
    local ok, mod = pcall(require, name)
    if ok and mod then return mod end
    return _G[name] or mod
end
local funcs = safeRequire('functions')

RegisterNetEvent("bcc-saloons:SendPropsFromWorld", function(...)
    local args = { ... }
    local serverMap = {}
    -- minimal processing: log total arg count when debug enabled
    if DBG then DBG:Info('SendPropsFromWorld (recv): argCount=' .. tostring(#args)) end
    -- find first non-empty table argument to use as payload
    local payload = nil
    for i = 1, #args do
        local a = args[i]
        if type(a) == 'table' then
            local cnt = 0
            for _ in pairs(a) do cnt = cnt + 1 end
            if cnt > 0 then
                payload = a
                break
            end
        end
    end
    if payload then
        for _, v in ipairs(payload) do
            if v and v.id then serverMap[v.id] = v end
        end
        if DBG then DBG:Info('SendPropsFromWorld: processed payload with ' .. tostring(#payload) .. ' array entries') end
    end
    -- no fallback; expect server to send payload reliably

    local localMap = {}
    for _, v in pairs(Stills) do
        if v and v.id then localMap[v.id] = v end
    end

    local newStills = {}
    for id, v in pairs(serverMap) do
        local existing = localMap[id]
        if existing then
            v.spawned = existing.spawned or false
            v.obj = existing.obj or nil
        else
            local foundObj = GetClosestObjectOfType(v.x, v.y, v.z, 5.0, GetHashKey(v.propname), false, false, false)
            if foundObj and DoesEntityExist(foundObj) then
                v.obj = foundObj
                v.spawned = true
            else
                v.spawned = false
                v.obj = nil
            end
        end
        table.insert(newStills, v)

        if (tonumber(v.isbrewing) or 0) == 1 then
            v._stageTimerStarted = v._stageTimerStarted or true
        end
    end

    Stills = newStills
    -- After updating Stills, if a nearby prop exists ensure BrewPrompt visibility/enabled state
    if BrewPrompt and BrewPrompt ~= 0 then
        local px, py, pz = table.unpack(GetEntityCoords(PlayerPedId()))
        local interactDist = tonumber(Config.interactDistance) or 1.5
        local interactDist2 = interactDist * interactDist
        local nearest = nil
        local nearestDist2 = math.huge
        for _, v in pairs(Stills) do
            if v and tonumber(v.x) and tonumber(v.y) and tonumber(v.z) then
                local dx = tonumber(v.x) - px
                local dy = tonumber(v.y) - py
                local dz = tonumber(v.z) - pz
                local d2 = dx * dx + dy * dy + dz * dz
                if d2 < nearestDist2 then
                    nearestDist2 = d2
                    nearest = v
                end
            end
        end
        if nearest and nearestDist2 <= interactDist2 then
            UiPromptSetVisible(BrewPrompt, true)
            UiPromptSetEnabled(BrewPrompt, (tonumber(nearest.isbrewing) or 0) == 0)
            if DBG then DBG:Info('SendPropsFromWorld (client): nearest prop id=' .. tostring(nearest.id) .. ' isbrewing=' .. tostring(nearest.isbrewing) .. ' stage_end_ms=' .. tostring(nearest.stage_end_ms)) end
        else
            if DBG then DBG:Info('SendPropsFromWorld (client): no nearby prop within interactDist') end
        end
    end
end)

RegisterNetEvent('bcc-saloons:GetPropData', function(propdata)
    ActiveProps = propdata
end)

RegisterNetEvent('bcc-saloons:sync', function()
    local ok, result = funcs.CallServerAwait('bcc-saloons:GetProps', 3000)
    if ok and result then
        TriggerEvent('bcc-saloons:SendPropsFromWorld', result)
    end
end)

RegisterNetEvent('bcc-saloons:DestroyProp', function(object, x, y, z, propId)
    if propId then
        recentlyDestroyed[tostring(propId)] = true
        CreateThread(function()
            Wait((Config.timeToDestroy * 1000) + 500)
            recentlyDestroyed[tostring(propId)] = nil
        end)
    end

    local prop = GetClosestObjectOfType(x, y, z, 1.0, GetHashKey(object), false, false, false)
    local destroyMsg = nil
    if object == Config.props.still then
        destroyMsg = locales.t('DestroyingStill')
    elseif object == Config.props.barrel then
        destroyMsg = locales.t('DestroyingBarrel')
    end
    TipBottom(destroyMsg, (Config.timeToDestroy * 1000) or 10000)

    local pedIsMale = IsPedMale(PlayerPedId())
    local animDict = pedIsMale and 'amb_work@world_human_crouch_inspect@male_c@idle_d' or 'amb_work@world_human_crouch_inspect@female_a@idle_a'
    local animName = pedIsMale and 'idle_k' or 'idle_a'
    local time = (Config.timeToDestroy * 1000) or 10000
    funcs.PlayAnim(animDict, animName, time, true)

    if prop and DoesEntityExist(prop) then
        DeleteObject(prop)
    end
    if propId then
        for k, v in pairs(Stills) do
            if v and tostring(v.id) == tostring(propId) then
                if v.obj and DoesEntityExist(v.obj) then
                    DeleteObject(v.obj)
                end
                Stills[k] = nil
                break
            end
        end
    end
end)

RegisterNetEvent('bcc-saloons:DeleteProp', function(object, x, y, z, propId, initiatorId)
    local myServerId = GetPlayerServerId(PlayerId())

    if initiatorId and initiatorId == myServerId then
        TriggerEvent('bcc-saloons:sync')
        if DBG then DBG:Info('DeleteProp: initiator is local player, skipping local delete') end
        return
    end

    if propId and recentlyDestroyed[tostring(propId)] then
        TriggerEvent('bcc-saloons:sync')
        if DBG then DBG:Info('DeleteProp: recently destroyed, skipping for propId ' .. tostring(propId)) end
        return
    end

    local removed = false
    if propId then
        for k, v in pairs(Stills) do
            if v and tostring(v.id) == tostring(propId) then
                if v.obj and DoesEntityExist(v.obj) then
                    DeleteObject(v.obj)
                end
                Stills[k] = nil
                removed = true
                break
            end
        end
    end

    if not removed then
        local prop = GetClosestObjectOfType(x, y, z, 5.0, GetHashKey(object), false, false, false)
        Wait((Config.timeToDestroy * 1000) or 10000)
        if prop and DoesEntityExist(prop) then
            DeleteObject(prop)
        end
        for k, v in pairs(Stills) do
            if v and tonumber(v.x) and tonumber(v.y) and tonumber(v.z) then
                local dx = tonumber(v.x) - tonumber(x)
                local dy = tonumber(v.y) - tonumber(y)
                local dz = tonumber(v.z) - tonumber(z)
                local d2 = dx * dx + dy * dy + dz * dz
                if d2 <= (1.5 * 1.5) then
                    if v.obj and DoesEntityExist(v.obj) then
                        DeleteObject(v.obj)
                    end
                    Stills[k] = nil
                    break
                end
            end
        end
    end

    if TempObj and DoesEntityExist(TempObj) then
        local tx, ty, tz = table.unpack(GetEntityCoords(TempObj))
        local distance = #(vector3(tx, ty, tz) - vector3(x, y, z))
        if distance < 1.5 then
            DeleteEntity(TempObj)
        end
    end

    TriggerEvent('bcc-saloons:sync')
    if DBG then DBG:Info('DeleteProp: requested props sync from server') end
end)

sync = M
return M
