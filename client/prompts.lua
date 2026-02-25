-- prompts.lua: register and shutdown UI prompts
-- Expects globals: Config, DBG, BrewGroup, locales (from shared/locales.lua), UiPrompt* natives
local M = {}

function StartPrompts()
    DBG:Info('Starting prompts...')
    if PromptsStarted then
        DBG:Success('Prompts are already started')
        return true
    end

    if not BrewGroup then
        DBG:Error('Prompt group is not initialized')
        return false
    end

    if not Config.keys or not Config.keys.build or not Config.keys.brew or not Config.keys.destroy then
        DBG:Error('Required keys are not defined in config')
        return false
    end

    BuildPrompt = UiPromptRegisterBegin()
    DBG:Info('Creating BuildPrompt...')
    if not BuildPrompt or BuildPrompt == 0 then
        DBG:Error('Failed to register BuildPrompt')
        return false
    end
    UiPromptSetControlAction(BuildPrompt, Config.keys.build)
    UiPromptSetText(BuildPrompt, VarString(10, 'LITERAL_STRING', locales.t('BuildPrompt')))
    UiPromptSetVisible(BuildPrompt, false)
    UiPromptSetEnabled(BuildPrompt, true)
    Citizen.InvokeNative(0x74C7D7B72ED0D3CF, BuildPrompt, 'MEDIUM_TIMED_EVENT')
    UiPromptSetGroup(BuildPrompt, BrewGroup, 0)
    UiPromptRegisterEnd(BuildPrompt)

    BrewPrompt = UiPromptRegisterBegin()
    DBG:Info('Creating BrewPrompt...')
    if not BrewPrompt or BrewPrompt == 0 then
        DBG:Error('Failed to register BrewPrompt')
        return false
    end
    UiPromptSetControlAction(BrewPrompt, Config.keys.brew)
    UiPromptSetText(BrewPrompt, VarString(10, 'LITERAL_STRING', locales.t('BrewPrompt')))
    UiPromptSetVisible(BrewPrompt, false)
    UiPromptSetEnabled(BrewPrompt, true)
    Citizen.InvokeNative(0x74C7D7B72ED0D3CF, BrewPrompt, 'MEDIUM_TIMED_EVENT')
    UiPromptSetGroup(BrewPrompt, BrewGroup, 0)
    UiPromptRegisterEnd(BrewPrompt)

    DestroyPrompt = UiPromptRegisterBegin()
    DBG:Info('Creating DestroyPrompt...')
    if not DestroyPrompt or DestroyPrompt == 0 then
        DBG:Error('Failed to register DestroyPrompt')
        return false
    end
    UiPromptSetControlAction(DestroyPrompt, Config.keys.destroy)
    UiPromptSetText(DestroyPrompt, VarString(10, 'LITERAL_STRING', locales.t('DestroyPrompt')))
    UiPromptSetVisible(DestroyPrompt, false)
    UiPromptSetEnabled(DestroyPrompt, true)
    Citizen.InvokeNative(0x74C7D7B72ED0D3CF, DestroyPrompt, 'MEDIUM_TIMED_EVENT')
    UiPromptSetGroup(DestroyPrompt, BrewGroup, 0)
    UiPromptRegisterEnd(DestroyPrompt)

    PromptsStarted = true
    DBG:Success('All prompts started successfully')
    return true
end

function ShutdownPrompts()
    pcall(function()
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
    end)
end

-- export
Prompts = M
Prompts.StartPrompts = StartPrompts
Prompts.ShutdownPrompts = ShutdownPrompts

-- provide lowercase global fallback
prompts = M

return M
