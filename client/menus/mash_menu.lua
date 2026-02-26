local function safeRequire(name)
    local ok, mod = pcall(require, name)
    if ok and mod then return mod end
    return _G[name] or mod
end
local funcs = safeRequire('functions')
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
            ClearPedTasks(PlayerPedId())
        end
    }
)

function OpenMashMenu(id, stage, currentbrew, isbrewing, startupItem)
    -- Main list page
    local MainPage = SaloonsMashMenu:RegisterPage('main:page')

    MainPage:RegisterElement('header', {
        value = locales.t('MashHeader'),
        slot = "header",
        style = { ['color'] = '#999' }
    })

    MainPage:RegisterElement('subheader', {
        value = locales.t('MashSubheader'),
        slot = "header",
        style = { ['font-size'] = '0.94vw', ['color'] = '#CC9900' }
    })

    MainPage:RegisterElement('line', { slot = "header", style = {} })

    local function BuildAndOpenDetail(item, id, stage, currentbrew, isbrewing)
        local itemCfg = Mash[item]
        if not itemCfg then return end
        local DetailPage = SaloonsMashMenu:RegisterPage('detail:page:' .. item)

        DetailPage:RegisterElement('header', {
            value = locales.t('MashHeader'),
            slot = "header",
            style = { ['color'] = '#999' }
        })

        DetailPage:RegisterElement('subheader', {
            value = itemCfg.label,
            slot = "header",
            style = { ['font-size'] = '0.94vw', ['color'] = '#CC9900' }
        })

        DetailPage:RegisterElement('line', { slot = "header", style = {} })

        local last = itemCfg.lastStage or 1
        for si = 1, last do
            local scfg = (itemCfg[si] or {})
            local stime = scfg.fermentTime or ''
            local ingr = scfg.ingredients or {}
            DetailPage:RegisterElement('textdisplay', {
                value = 'Stage ' .. tostring(si) .. ' - Time: ' .. tostring(stime) .. ' min',
                slot = "content",
                style = {
                    ['font-size'] = '0.90vw',
                    ['font-variant'] = 'small-caps',
                    ['color'] = '#D0D0D0'
                }
            })
            if ingr and type(ingr) == 'table' and #ingr > 0 then
                DetailPage:RegisterElement('textdisplay', {
                    value = '  Ingredients:',
                    slot = "content",
                    style = {
                        ['font-size'] = '0.83vw',
                        ['font-variant'] = 'small-caps',
                        ['color'] = '#BFBFBF'
                    }
                })
                for _, ing in ipairs(ingr) do
                    DetailPage:RegisterElement('textdisplay', {
                        value = '    - ' .. (ing.label or ing.id) .. ' x' .. tostring(ing.qty or 1),
                        slot = "content",
                        style = {
                            ['font-size'] = '0.83vw',
                            ['font-variant'] = 'small-caps',
                            ['color'] = '#BFBFBF'
                        }
                    })
                end
            end
        end

        DetailPage:RegisterElement('textdisplay', {
            value = locales.t('MashProduced') .. ' ' .. tostring(itemCfg.yield or 1) .. ' ' .. (itemCfg.label or ''),
            slot = "content",
            style = {
                ['font-size'] = '0.90vw',
                ['font-variant'] = 'small-caps',
                ['color'] = '#BFBFBF'
            }
        })

        -- Dynamic action button: Start / Continue / Collect
        do
            local disabled = (tonumber(isbrewing) or 0) == 1
            local actionLabel = locales.t('Start') .. ' ' .. itemCfg.label
            local actionFunc = function()
                funcs.CallServerAsync('bcc-saloons:CheckIngredients', id, nil, item)
            end

            if currentbrew and currentbrew == item and stage and tonumber(stage) > 1 then
                local curStage = tonumber(stage)
                if curStage < (itemCfg.lastStage or last) then
                    actionLabel = locales.t('ContinueBrew') .. ' ' .. itemCfg.label
                    actionFunc = function()
                        funcs.CallServerAsync('bcc-saloons:CheckIngredients', id, curStage, item)
                    end
                else
                    actionLabel = locales.t('CollectBrew') .. ' ' .. itemCfg.label
                    actionFunc = function()
                        funcs.CallServerAsync('bcc-saloons:FinishBrewing', id, item, Mash)
                    end
                end
            end

            DetailPage:RegisterElement('button', {
                label = actionLabel,
                slot = "content",
                style = { ['color'] = '#E0E0E0' },
                disabled = disabled
            }, function()
                if disabled then return end
                actionFunc()
            end)
        end

        -- Reset mash / destroy option when brewing
        if tonumber(isbrewing) == 1 then
            DetailPage:RegisterElement('button', {
                label = locales.t('DestroyMash'),
                slot = "content",
                style = { ['color'] = '#FF6666' }
            }, function()
                funcs.CallServerAsync('bcc-saloons:ResetMash', id)
            end)
        end

        DetailPage:RegisterElement('bottomline', {
            slot = 'footer',
            style = {}
        })

        DetailPage:RegisterElement('button', {
            label = locales.t('Back'),
            slot = "footer",
            style = { ['color'] = '#CCCCCC' }
        }, function()
            SaloonsMashMenu:Open({ startupPage = MainPage })
        end)

        DetailPage:RegisterElement('button', {
            label = locales.t('Close'),
            slot = "footer",
            style = { ['color'] = '#CCCCCC' }
        }, function()
            SaloonsMashMenu:Close()
        end)

        -- show contextual tip if this mash is between stages and not currently brewing
        if id and currentbrew and currentbrew == item and tonumber(stage) and tonumber(stage) > 1 and tonumber(isbrewing) == 0 then
            pcall(function() TipBottom(locales.t('ContinueBrew'), 4000) end)
        end

        SaloonsMashMenu:Open({ startupPage = DetailPage })
    end

    for item, itemCfg in pairs(Mash) do
        local disabled = (tonumber(isbrewing) or 0) == 1
        -- Button opens a detail page for this mash
        MainPage:RegisterElement('button', {
            label = itemCfg.label,
            slot = "content",
            style = { ['color'] = disabled and '#666666' or '#E0E0E0' },
            disabled = disabled
        }, function()
            if disabled then return end
            BuildAndOpenDetail(item, id, stage, currentbrew, isbrewing)
        end)
    end

    MainPage:RegisterElement('bottomline', {
        slot = 'footer',
        style = {}
    })

    -- Main page Close button
    MainPage:RegisterElement('button', {
        label = locales.t('Close'),
        slot = "footer",
        style = { ['color'] = '#CCCCCC' }
    }, function()
        SaloonsMashMenu:Close()
    end)

    -- If a startupItem was provided, try to open its detail page directly
    if startupItem then
        BuildAndOpenDetail(startupItem, id, stage, currentbrew, isbrewing)
        return
    end

    SaloonsMashMenu:Open({ startupPage = MainPage })
end