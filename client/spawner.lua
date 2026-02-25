-- spawner.lua: spawn/unspawn world props near player
-- Expects globals: Stills, TempObj, DBG, Config

local M = {}

function StartSpawner()
    if SpawnerStarted then return end
    SpawnerStarted = true
    if DBG then DBG:Info('Spawner started') end

    CreateThread(function()
        local spawnDistance = Config.spawnDistance or 50.0
        while true do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local sleep = 1000
            for _, v in pairs(Stills) do
                if v and v.x and v.y and v.z then
                    local coords = vector3(v.x, v.y, v.z)
                    local dist = #(playerCoords - coords)
                    if dist <= spawnDistance then
                        sleep = 200
                        if not v.spawned then
                            local existingObj = GetClosestObjectOfType(v.x, v.y, v.z, 5.0, GetHashKey(v.propname), false, false, false)
                            if existingObj and DoesEntityExist(existingObj) then
                                v.obj = existingObj
                                v.spawned = true
                            else
                                v.obj = CreateObject(v.propname, v.x, v.y, v.z - 1.0, false, true, false, false, false)
                                local timeout = 10000
                                local startTime = GetGameTimer()
                                while not DoesEntityExist(v.obj) do
                                    if GetGameTimer() - startTime > timeout then
                                        if DBG then DBG:Error('Failed to create object: ' .. tostring(v.propname)) end
                                        break
                                    end
                                    Wait(10)
                                end
                                if DoesEntityExist(v.obj) then
                                    SetEntityHeading(v.obj, v.h)
                                    PlaceObjectOnGroundProperly(v.obj, false)
                                    v.spawned = true
                                end
                            end
                            if TempObj and DoesEntityExist(TempObj) then
                                DeleteEntity(TempObj)
                            end
                        end
                    else
                        if v and v.spawned and (tonumber(v.isbrewing) or 0) == 0 then
                            if v.obj and DoesEntityExist(v.obj) then
                                DeleteEntity(v.obj)
                            end
                            v.spawned = false
                            v.obj = nil
                            if TempObj and DoesEntityExist(TempObj) then
                                DeleteEntity(TempObj)
                            end
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end)
end

Spawner = M
Spawner.StartSpawner = StartSpawner

return M
