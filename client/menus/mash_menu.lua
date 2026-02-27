local function safeRequire(name)
    local ok, mod = pcall(require, name)
    if ok and mod then return mod end
    return _G[name] or mod
end

local funcs = safeRequire('functions')
local KeepKneeling = false
local SaloonsMashMenu = FeatherMenu:RegisterMenu('saloons:mash:menu', {
    top = '3%',
    left = '3%',
    ['720width'] = '400px',
    ['1080width'] = '500px',
    ['2kwidth'] = '600px',
    ['4kwidth'] = '800px',
    style = {
    },
    contentslot = {
        style = {
            ['height'] = '500px',
            ['min-height'] = '300px'
        }
    },
    draggable = true,
    canclose = true
}, {
    opened = function()
        DisplayRadar(false)
        InMenu = true
    end,
    closed = function()
        DisplayRadar(true)
        InMenu = false
        -- preserve kneel animation if requested (set by action click)
        if not KeepKneeling then
            ClearPedTasks(PlayerPedId())
        end
    end
})

RegisterNetEvent('bcc-saloons:ClearKeepKneeling', function()
    KeepKneeling = false
end)

local headerStyle = { ['color'] = '#999' }
local subheaderStyle = { ['font-size'] = '0.94vw', ['color'] = '#CC9900' }
local smallTextStyle = { ['font-size'] = '0.83vw', ['font-variant'] = 'small-caps', ['color'] = '#BFBFBF' }
local medTextStyle = { ['font-size'] = '0.90vw', ['font-variant'] = 'small-caps', ['color'] = '#F5F5DC' }
local activeButton = { ['color'] = '#E0E0E0' }
local disabledButton = { ['color'] = '#666666' }

local function addText(page, value, slot, style)
    page:RegisterElement('textdisplay', { value = value, slot = slot, style = style })
end

local function addButton(page, label, slot, style, cb, disabled)
    page:RegisterElement('button', { label = label, slot = slot, style = style, disabled = disabled }, cb)
end
-- Client-side inventory count cache and lookup (server-backed)
local _invCache = {}
local INV_CACHE_TTL = 3000 -- ms
local function getLocalItemCount(itemName)
    if not itemName then return nil end
    local now = GetGameTimer()
    local cacheEntry = _invCache[itemName]
    if cacheEntry and (now - cacheEntry.t) < INV_CACHE_TTL then
        return cacheEntry.count
    end
    local ok, res = funcs.CallServerAwait('bcc-saloons:GetItemCount', 2000, itemName)
    if ok and res ~= nil then
        local cnt = tonumber(res) or 0
        _invCache[itemName] = { count = cnt, t = GetGameTimer() }
        return cnt
    end
    return nil
end

RegisterNetEvent('bcc-saloons:CloseMashMenu', function()
    pcall(function() SaloonsMashMenu:Close() end)
end)

function OpenMashMenu(id, stage, currentbrew, isbrewing, startupItem)
    -- Main list page
    local MainPage = SaloonsMashMenu:RegisterPage('main:page')

    MainPage:RegisterElement('header', {
        value = locales.t('MashHeader'),
        slot = "header",
        style = headerStyle
    })

    MainPage:RegisterElement('subheader', {
        value = locales.t('MashSubheader'),
        slot = "header",
        style = subheaderStyle
    })

    MainPage:RegisterElement('line', { slot = "header", style = {} })

    local function BuildAndOpenDetail(item, propId, propStage, propCurrentBrew, propIsBrewing)
        local itemCfg = Mash[item]
        if not itemCfg then return end
        -- normalize a few frequently-used values
        local isBrewingNum = tonumber(propIsBrewing) or 0
        local propCurStr = tostring(propCurrentBrew)
        local itemStr = tostring(item)
        -- don't open detail if this prop is currently brewing a different mash
        if isBrewingNum == 1 and propCurStr ~= itemStr then
            if DBG then DBG:Warn('BuildAndOpenDetail: item disabled for this prop: ' .. itemStr) end
            if not DBG then print('BuildAndOpenDetail: item disabled for this prop: ' .. itemStr) end
            return
        end
        local DetailPage = SaloonsMashMenu:RegisterPage('detail:page:' .. item)

        DetailPage:RegisterElement('header', {
            value = locales.t('MashHeader'),
            slot = "header",
            style = headerStyle
        })

        DetailPage:RegisterElement('subheader', {
            value = itemCfg.label,
            slot = "header",
            style = subheaderStyle
        })

        addText(DetailPage, locales.t('Produces') .. ' ' .. tostring(itemCfg.yield or 1) .. ' ' .. locales.t('Buckets'),
            'header', smallTextStyle)

        DetailPage:RegisterElement('line', { slot = "header", style = {} })

        local last = itemCfg.lastStage or 1
        for si = 1, last do
            local scfg = (itemCfg[si] or {})
            local stime = scfg.fermentTime or ''
            local ingr = scfg.ingredients or {}
            addText(DetailPage, 'Stage ' .. tostring(si) .. ' - Time: ' .. tostring(stime) .. ' min', 'content',
                medTextStyle)
            if ingr and type(ingr) == 'table' and #ingr > 0 then
                addText(DetailPage, '  Ingredients:', 'content', smallTextStyle)
                for _, ing in ipairs(ingr) do
                    local qty = tonumber(ing.qty) or 1
                    local have = getLocalItemCount(ing.id)
                    local itemLabel = (ing.label or ing.id) .. ' x' .. tostring(qty)
                    local style = smallTextStyle
                    if have ~= nil and have < qty then
                        style = { ['font-size'] = smallTextStyle['font-size'], ['font-variant'] = smallTextStyle
                        ['font-variant'], ['color'] = '#FF6666' }
                    end
                    addText(DetailPage, '    - ' .. itemLabel, 'content', style)
                end
            end
        end

        DetailPage:RegisterElement('bottomline', { slot = 'footer', style = {} })

        DetailPage:RegisterElement('line', { slot = "footer", style = {} })

        -- Dynamic action button: Start / Continue / Collect
        do
            local disabled = isBrewingNum == 1 and propCurStr ~= itemStr
            local actionLabel = locales.t('StartMash')
            local actionFunc = function()
                funcs.CallServerAsync('bcc-saloons:CheckIngredients', propId, nil, item)
            end

            if propCurrentBrew and propCurrentBrew == item and propStage and tonumber(propStage) >= 1 then
                local curStage = tonumber(propStage)
                local lastStage = itemCfg.lastStage or last
                if curStage >= 1 and curStage <= lastStage then
                    local fmt = locales.t('StageContinue') or 'Stage %s Continue'
                    actionLabel = string.format(fmt, tostring(curStage))
                    actionFunc = function()
                        funcs.CallServerAsync('bcc-saloons:CheckIngredients', propId, curStage, item)
                    end
                elseif curStage > lastStage then
                    actionLabel = locales.t('CollectMash')
                    actionFunc = function()
                        CreateThread(function()
                            -- await server finish call so we can clear the kneel flag afterwards
                            funcs.CallServerAwait('bcc-saloons:FinishBrewing', 5000, propId, item)
                            TriggerEvent('bcc-saloons:ClearKeepKneeling')
                        end)
                    end
                end
            end

            DetailPage:RegisterElement('button', {
                label = actionLabel,
                slot = "footer",
                style = disabled and disabledButton or activeButton,
                disabled = disabled
            }, function()
                if disabled then return end
                -- close immediately but keep the kneel animation until brewing confirms
                KeepKneeling = true
                pcall(function() SaloonsMashMenu:Close() end)
                actionFunc()
            end)
        end

        -- Reset mash / destroy option when brewing
        local showDestroy = false
        if tonumber(propIsBrewing) == 1 then showDestroy = true end
        if propStage and tonumber(propStage) and tonumber(propStage) >= 2 then showDestroy = true end
        if showDestroy then
            addButton(DetailPage, locales.t('DestroyMash'), 'footer', { ['color'] = '#FF6666' }, function()
                SaloonsMashMenu:Close()
                funcs.CallServerAsync('bcc-saloons:ResetMash', propId)
            end)
        end

        -- hide Back once this mash has been started (any stage >= 1)
        -- so players can't return and pick other recipes while a brew is in-progress
        local startedNum = tonumber(propStage) or 0
        local isStarted = (startedNum >= 1 and propCurStr == itemStr)
        if not isStarted then
            addButton(DetailPage, locales.t('Back'), 'footer', activeButton, function()
                -- do not Close the menu here; keep `InMenu` true so player remains kneeling
                OpenMashMenu(propId, propStage, propCurrentBrew, propIsBrewing)
            end)
        end

        DetailPage:RegisterElement('line', { slot = "footer", style = {} })

        -- open the detail page we just built
        pcall(function() SaloonsMashMenu:Open({ startupPage = DetailPage }) end)
    end

    for item, itemCfg in pairs(Mash) do
        local disabled = (tonumber(isbrewing) or 0) == 1 and tostring(currentbrew) ~= tostring(item)
        -- Button opens a detail page for this mash
        MainPage:RegisterElement('button', {
            label = itemCfg.label,
            slot = "content",
            style = disabled and disabledButton or activeButton,
            disabled = disabled
        }, function()
            if disabled then return end
            local clickMsg = 'Mash button clicked: item=' ..
                tostring(item) ..
                ' id=' ..
                tostring(id) ..
                ' stage=' ..
                tostring(stage) ..
                ' currentbrew=' ..
                tostring(currentbrew) .. ' isbrewing=' .. tostring(isbrewing) .. ' disabled=' .. tostring(disabled)
            if not Mash or not Mash[item] then
                if DBG then
                    DBG:Warn('BuildAndOpenDetail: missing Mash config for ' ..
                        tostring(item) .. ' -- ' .. clickMsg)
                end
                if not DBG then print('BuildAndOpenDetail: missing Mash config for ' .. tostring(item)) end
                return
            end
            if DBG then DBG:Info(clickMsg) else print(clickMsg) end
            local ok, err = pcall(function() BuildAndOpenDetail(item, id, stage, currentbrew, isbrewing) end)
            if not ok then
                if DBG then DBG:Error('BuildAndOpenDetail failed: ' .. tostring(err)) end
                if not DBG then print('BuildAndOpenDetail failed: ' .. tostring(err)) end
            end
        end)
    end

    MainPage:RegisterElement('bottomline', { slot = 'footer', style = {} })

    MainPage:RegisterElement('line', { slot = "footer", style = {} })

    -- Main page Close button
    MainPage:RegisterElement('button', {
        label = locales.t('Close'),
        slot = "footer",
        style = activeButton
    }, function()
        SaloonsMashMenu:Close()
    end)

    MainPage:RegisterElement('line', { slot = "footer", style = {} })

    -- If a startupItem was provided, try to open its detail page directly
    if startupItem then
        local startupDisabled = (tonumber(isbrewing) or 0) == 1 and tostring(currentbrew) ~= tostring(startupItem)
        if startupDisabled then
            if DBG then DBG:Warn('Startup item disabled, falling back to main page: ' .. tostring(startupItem)) end
            if not DBG then print('Startup item disabled: ' .. tostring(startupItem)) end
            SaloonsMashMenu:Open({ startupPage = MainPage })
            return
        end
        BuildAndOpenDetail(startupItem, id, stage, currentbrew, isbrewing)
        return
    end

    -- If no startupItem was specified but the prop already has a current brew
    -- and is at or past stage 1, open that brew's detail page by default.
    if stage and tonumber(stage) and tonumber(stage) >= 1 and currentbrew and tostring(currentbrew) ~= 'None' then
        BuildAndOpenDetail(currentbrew, id, stage, currentbrew, isbrewing)
        return
    end

    SaloonsMashMenu:Open({ startupPage = MainPage })
end
