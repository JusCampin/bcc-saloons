-- globals are initialized in client_init.lua

-- Load client modules (split for maintainability)
local function safeRequire(name)
    local ok, mod = pcall(require, name)
    if ok and mod then return mod end
    return _G[name] or mod
end

local PromptsModule = safeRequire('prompts')
local Spawner = safeRequire('spawner')
-- Require modules for side-effects; they are used elsewhere but not referenced in this file
safeRequire('placement')
safeRequire('brewing')
safeRequire('sync')
local main_loop = safeRequire('main_loop')

function TipBottom(msg, time)
    TriggerEvent('vorp:TipBottom', msg, time)
end

-- prompts are started via SelectedCharacter or manually (restored original behavior)

RegisterNetEvent("vorp:SelectedCharacter", function()
    TriggerEvent('bcc-saloons:sync')
    if DBG then DBG:Info('SelectedCharacter: requested props sync from server') end
    -- start the spawner loop once the character is loaded
    if not SpawnerStarted then
        if Spawner and Spawner.StartSpawner then Spawner.StartSpawner() else StartSpawner() end
    end

    if not MainThreadStarted then
        if main_loop and main_loop.StartMainThread then main_loop.StartMainThread() else StartMainThread() end
    end
end)

-- Manually start Saloon functions after restarting the resource
if Config.devMode.active then
    RegisterCommand('restartSaloons', function()
        TriggerEvent('bcc-saloons:sync')
        if DBG then DBG:Info('restartSaloons: requested props sync from server') end
        if not SpawnerStarted then
            if Spawner and Spawner.StartSpawner then Spawner.StartSpawner() else StartSpawner() end
        end

        if not MainThreadStarted then
            if main_loop and main_loop.StartMainThread then main_loop.StartMainThread() else StartMainThread() end
        end
    end, false)
end

-- implementations moved to client modules: prompts.lua, spawner.lua,
-- placement.lua, brewing.lua, sync.lua and main_loop.lua

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    -- Shutdown prompts via prompts module if available
    pcall(function()
        if PromptsModule and PromptsModule.ShutdownPrompts then
            PromptsModule.ShutdownPrompts()
        elseif Prompts and Prompts.ShutdownPrompts then
            Prompts.ShutdownPrompts()
        else
            if BuildPrompt and BuildPrompt ~= 0 then
                UiPromptSetVisible(BuildPrompt, false)
                UiPromptSetEnabled(BuildPrompt, false)
                UiPromptDelete(BuildPrompt)
                BuildPrompt = 0
            end
            if BrewPrompt and BrewPrompt ~= 0 then
                UiPromptSetVisible(BrewPrompt, false)
                UiPromptSetEnabled(BrewPrompt, false)
                UiPromptDelete(BrewPrompt)
                BrewPrompt = 0
            end
            if DestroyPrompt and DestroyPrompt ~= 0 then
                UiPromptSetVisible(DestroyPrompt, false)
                UiPromptSetEnabled(DestroyPrompt, false)
                UiPromptDelete(DestroyPrompt)
                DestroyPrompt = 0
            end
            PromptsStarted = false
        end
    end)

    -- Stop any player tasks/animations
    pcall(function()
        ClearPedTasks(PlayerPedId())
        ClearPedSecondaryTask(PlayerPedId())
    end)

    -- Reset runtime flags
    PlacingPromptsActive = false
    Placing = false
    SpawnerStarted = false
    MainThreadStarted = false
    Destroying = nil
    LastPlaced = nil
    LastRemainingUpdate = 0
    recentlyDestroyed = {}

    -- Remove placing/temp objects
    if PlacingObj and DoesEntityExist(PlacingObj) then
        DeleteObject(PlacingObj)
        PlacingObj = 0
    end

    if TempObj and DoesEntityExist(TempObj) then
        DeleteEntity(TempObj)
        TempObj = 0
    end

    -- Delete spawned world props and clear lists
    for k, v in pairs(Stills) do
        if v and v.obj and DoesEntityExist(v.obj) then
            DeleteEntity(v.obj)
        end
        Stills[k] = nil
    end
    Stills = {}
    ActiveProps = {}
end)
