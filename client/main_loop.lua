-- main_loop.lua: main client loop handling prompts, interaction and menus
-- Expects globals: PromptsStarted, StartPrompts, StartSpawner, StartMainThread (this file provides StartMainThread), StartMainThread calls other modules' functions

local M = {}
local function safeRequire(name)
    local ok, mod = pcall(require, name)
    if ok and mod then return mod end
    return _G[name] or mod
end
local funcs = safeRequire('functions')

function StartMainThread()
    if MainThreadStarted then return end
    MainThreadStarted = true
    if DBG then DBG:Info('Main thread started') end

    CreateThread(function()
        if not PromptsStarted and not (Prompts and Prompts.StartPrompts and Prompts.StartPrompts()) then
            DBG:Error('Failed to start prompts')
            return
        end

        while true do
            local sleep = 1000
            local px, py, pz = table.unpack(GetEntityCoords(PlayerPedId()))
            local interactDist = tonumber(Config.interactDistance) or 1.5
            local interactDist2 = interactDist * interactDist

            local nearestStillDist2 = math.huge
            local nearestBarrelDist2 = math.huge
            for _, v in pairs(Stills) do
                if v and v.x and v.y and v.z then
                    local dx = tonumber(v.x) - px
                    local dy = tonumber(v.y) - py
                    local dz = tonumber(v.z) - pz
                    local d2 = dx * dx + dy * dy + dz * dz
                    if v.propname == Config.props.still and d2 < nearestStillDist2 then
                        nearestStillDist2 = d2
                    end
                    if v.propname == Config.props.barrel and d2 < nearestBarrelDist2 then
                        nearestBarrelDist2 = d2
                    end
                end
            end

            local isNearStill = nearestStillDist2 <= interactDist2
            local isNearBarrel = nearestBarrelDist2 <= interactDist2

            if (isNearStill or isNearBarrel) and not Placing then
                sleep = 0
                local label = isNearStill and locales.t('Still') or locales.t('Barrel')
                UiPromptSetActiveGroupThisFrame(BrewGroup, CreateVarString(10, 'LITERAL_STRING', label), 1, 0, 0, 0)
                UiPromptSetVisible(BuildPrompt, false)
                UiPromptSetVisible(DestroyPrompt, true)
                UiPromptSetVisible(BrewPrompt, true)

                if Citizen.InvokeNative(0xE0F65F0640EF0617, BrewPrompt) then -- PromptHasHoldModeCompleted
                    Wait(500)
                    local ok, result = funcs.CallServerAwait('bcc-saloons:GetCoords', 2000, px, py, pz)
                    if ok and result then
                        ActiveProps = result
                    end
                    if DBG then DBG:Info('Brew Prompt completed; ActiveProps count: ' .. tostring(#ActiveProps)) end

                    -- If a StageActionTarget exists, prioritize opening the menu for that prop
                    if StageActionTarget and StageActionTarget.expires_at and GetGameTimer() > StageActionTarget.expires_at then
                        StageActionTarget = nil
                    end
                    local openedForTarget = false
                    if StageActionTarget and not InMenu then
                        for _, v in pairs(ActiveProps) do
                            if v and tostring(v.id) == tostring(StageActionTarget.id) then
                                if v.propname == Config.props.still then
                                    OpenStillMenu(v.id, tonumber(v.stage) or 1, v.currentbrew)
                                else
                                    OpenMashMenu(v.id, tonumber(v.stage) or 1, v.currentbrew, tonumber(v.isbrewing) or 0)
                                end
                                openedForTarget = true
                                StageActionTarget = nil
                                break
                            end
                        end
                    end
                    if not openedForTarget then
                        for _, v in pairs(ActiveProps) do
                            if not InMenu and (tonumber(v.isbrewing) or 0) == 0 then
                                if isNearStill then
                                    OpenStillMenu(v.id, tonumber(v.stage) or 1, v.currentbrew)
                                else
                                    OpenMashMenu(v.id, tonumber(v.stage) or 1, v.currentbrew, tonumber(v.isbrewing) or 0)
                                end
                            end

                            if (tonumber(v.isbrewing) or 0) == 1 then
                                Core.NotifyRightTip(locales.t('CurrentlyBrewing'), 4000)
                                local now = GetGameTimer()
                                if now - LastRemainingUpdate >= 1000 then
                                    LastRemainingUpdate = now
                                    if v.stage_end_ms and tonumber(v.stage_end_ms) then
                                        if type(os) == 'table' and type(os.time) == 'function' then
                                            local remaining = tonumber(v.stage_end_ms) - (os.time() * 1000)
                                            if remaining < 0 then remaining = 0 end
                                            local secs = math.ceil(remaining / 1000)
                                            TipBottom(locales.t('BrewingTimer') .. ' ' .. tostring(secs) .. 's', 2000)
                                        else
                                            -- `os` not available in this environment; skip epoch-based timer display
                                        end
                                    end
                                end
                            end
                        end
                    end

                    if InMenu then
                        TaskStartScenarioInPlace(PlayerPedId(), `WORLD_PLAYER_DYNAMIC_KNEEL`, 0, true)
                    end
                end

                if Citizen.InvokeNative(0xE0F65F0640EF0617, DestroyPrompt) then -- PromptHasHoldModeCompleted
                    Wait(500)
                    if not Destroying then
                        Destroying = true
                        UiPromptSetVisible(BuildPrompt, false)
                        UiPromptSetVisible(DestroyPrompt, false)
                        UiPromptSetVisible(BrewPrompt, false)
                        local ok, result = funcs.CallServerAwait('bcc-saloons:GetCoords', 2000, px, py, pz)
                        if ok and result then
                            ActiveProps = result
                        end

                        for _, v in pairs(ActiveProps) do
                            funcs.CallServerAsync('bcc-saloons:RemoveFromDb', v.id, v.propname, v.x, v.y, v.z)
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end)
end

main_loop = M
main_loop.StartMainThread = StartMainThread

return M
