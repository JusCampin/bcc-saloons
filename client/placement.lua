-- placement.lua: placement and saving of props
-- Expects globals: TipBottom, Config, PlayAnim, LoadModel, Core, Stills, ActiveProps, TempObj, LastPlaced

local M = {}
local function safeRequire(name)
    local ok, mod = pcall(require, name)
    if ok and mod then return mod end
    return _G[name] or mod
end
local funcs = safeRequire('functions')

local function savePlacedProp(propName, object, propCoords, propHeading, networked)
    local placingMsg = nil
    if propName == Config.props.still then
        placingMsg = locales.t('PlacingStill')
    elseif propName == Config.props.barrel then
        placingMsg = locales.t('PlacingBarrel')
    end
    TipBottom(placingMsg, (Config.timeToConstruct or 10) * 1000)
    local pedIsMale = IsPedMale(PlayerPedId())
    local animDict = pedIsMale and 'amb_work@world_human_crouch_inspect@male_c@idle_d' or 'amb_work@world_human_crouch_inspect@female_a@idle_a'
    local animName = pedIsMale and 'idle_k' or 'idle_a'
    local time = (Config.timeToConstruct or 10) * 1000
    funcs.PlayAnim(animDict, animName, time, true, nil)

    local placedMsg = (propName == Config.props.still) and locales.t('StillPlaced') or locales.t('BarrelPlaced')
    Core.NotifyRightTip(placedMsg, 4000)

    TempObj = CreateObject(object, propCoords.x, propCoords.y, propCoords.z, networked, true, false)
    SetEntityHeading(TempObj, propHeading)
    PlaceObjectOnGroundProperly(TempObj)
    LastPlaced = { obj = TempObj, propname = propName, x = propCoords.x, y = propCoords.y, z = propCoords.z, h = propHeading }
    CreateThread(function()
        local ok, uuid = pcall(function()
            return Core.Callback.TriggerAwait('bcc-saloons:SaveToDB', propName, propCoords.x, propCoords.y, propCoords.z, propHeading)
        end)
        if ok and uuid then
            if LastPlaced and LastPlaced.obj then
                local entry = {
                    id = uuid,
                    propname = LastPlaced.propname,
                    x = LastPlaced.x,
                    y = LastPlaced.y,
                    z = LastPlaced.z,
                    h = LastPlaced.h,
                    isbrewing = 0,
                    stage = 1,
                    currentbrew = 'None',
                    spawned = true,
                    obj = LastPlaced.obj
                }
                table.insert(Stills, entry)
                table.insert(ActiveProps, entry)
                LastPlaced = nil
            end
            Citizen.Wait(1000)
            TriggerEvent('bcc-saloons:sync')
        end
    end)
end

RegisterNetEvent('bcc-saloons:placeProp', function(propName)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local playerHeading = GetEntityHeading(PlayerPedId())
    local object = joaat(propName)

    funcs.LoadModel(object, propName)
    Placing = true
    PlacingObj = CreateObject(object, playerCoords.x, playerCoords.y, playerCoords.z, false, true, false)
    SetEntityHeading(PlacingObj, playerHeading)
    SetEntityAlpha(PlacingObj, 51, false)
    AttachEntityToEntity(PlacingObj, PlayerPedId(), 0, 0.0, 1.0, -0.7, 0.0, 0.0, 0.0, true, true, false, true, 2, true, false, false)
    while Placing do
        Wait(0)
        UiPromptSetActiveGroupThisFrame(BrewGroup, VarString(10, 'LITERAL_STRING', 'Placing'), 1, 0, 0, 0)
        if PlacingPromptsActive == false then
            UiPromptSetVisible(BuildPrompt, true)
            UiPromptSetVisible(DestroyPrompt, false)
            UiPromptSetVisible(BrewPrompt, false)
            PlacingPromptsActive = true
        end

        if Citizen.InvokeNative(0xE0F65F0640EF0617, BuildPrompt) then -- PromptHasHoldModeCompleted
            Wait(500)
            UiPromptSetVisible(BuildPrompt, false)
            PlacingPromptsActive = false
            local propCoords = GetEntityCoords(PlacingObj)
            local propHeading = GetEntityHeading(PlacingObj)

            if PlacingObj and DoesEntityExist(PlacingObj) then
                DeleteObject(PlacingObj)
            end

            if propName == Config.props.still then
                savePlacedProp(propName, object, propCoords, propHeading, false)
                Placing = false
            end

            if propName == Config.props.barrel then
                savePlacedProp(propName, object, propCoords, propHeading, true)
                Placing = false
            end
            break
        end
    end
end)

placement = M
placement.savePlacedProp = savePlacedProp

return M
