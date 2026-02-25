local function safeRequire(name)
    local ok, mod = pcall(require, name)
    if ok and mod then return mod end
    return _G[name] or mod
end
local funcs = safeRequire('functions')
local SaloonsStillMenu = FeatherMenu:RegisterMenu('saloons:still:menu', {
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

function OpenStillMenu(id, stage, currentbrew)
    local MainPage = SaloonsStillMenu:RegisterPage('still:main')

    MainPage:RegisterElement('header', {
        value = locales.t('StillHeader') or 'Moonshine',
        slot = "header",
        style = { ['color'] = '#999' }
    })

    MainPage:RegisterElement('subheader', {
        value = locales.t('StillSubheader') or 'Distill spirits',
        slot = "header",
        style = { ['font-size'] = '0.94vw', ['color'] = '#CC9900' }
    })

    MainPage:RegisterElement('line', { slot = "header", style = {} })

    if Moonshine then
        for key, cfg in pairs(Moonshine) do
            local disabled = (tonumber(stage) or 0) == 0 and false or ((tonumber(cfg.Locked) == 1) and true or false)
            MainPage:RegisterElement('button', {
                label = cfg.label or key,
                slot = "content",
                style = { ['color'] = '#E0E0E0' },
                disabled = false
            }, function()
                -- build detail page
                local DetailPage = SaloonsStillMenu:RegisterPage('still:detail:' .. key)

                DetailPage:RegisterElement('header', {
                    value = locales.t('StillHeader') or 'Moonshine',
                    slot = "header",
                    style = { ['color'] = '#999' }
                })

                DetailPage:RegisterElement('subheader', {
                    value = cfg.label or key,
                    slot = "header",
                    style = { ['font-size'] = '0.94vw', ['color'] = '#CC9900' }
                })

                DetailPage:RegisterElement('line', { slot = "header", style = {} })

                local last = cfg.LastStage or (#cfg)
                for si = 1, last do
                    local scfg = cfg[si] or {}
                    local stime = scfg.stilltime or scfg.fermenttime or ''
                    DetailPage:RegisterElement('textdisplay', {
                        value = 'Stage ' .. tostring(si) .. ' - Time: ' .. tostring(stime) .. ' min',
                        slot = "content",
                        style = {
                            ['font-size'] = '0.90vw',
                            ['font-variant'] = 'small-caps',
                            ['color'] = '#D0D0D0'
                        }
                    })

                    if scfg and scfg.ingredients and type(scfg.ingredients) == 'table' and #scfg.ingredients > 0 then
                        DetailPage:RegisterElement('textdisplay', {
                            value = '  Ingredients:',
                            slot = "content",
                            style = {
                                ['font-size'] = '0.83vw',
                                ['font-variant'] = 'small-caps',
                                ['color'] = '#BFBFBF'
                            }
                        })
                        for _, ing in ipairs(scfg.ingredients) do
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

                    -- stage Tip
                    if scfg and scfg.Tip then
                        DetailPage:RegisterElement('textdisplay', {
                            value = scfg.Tip,
                            slot = "content",
                            style = { ['color'] = '#E0E0E0' }
                        })
                    end
                end

                DetailPage:RegisterElement('textdisplay', {
                    value = locales.t('StillProduced') and (locales.t('StillProduced') .. ' ' .. tostring(cfg.Yield or 1)) or '',
                    slot = "content",
                    style = { ['font-size'] = '0.90vw', ['color'] = '#BFBFBF' }
                })

                -- Start brew (stage==nil means starting)
                DetailPage:RegisterElement('button', {
                    label = locales.t('Start') .. ' ' .. (cfg.label or key),
                    slot = "content",
                    style = { ['color'] = '#E0E0E0' }
                }, function()
                            funcs.CallServerAsync('bcc-saloons:CheckIngredients', id, nil, key)
                end)

                -- Continue/Collect depending on current stage
                if currentbrew and currentbrew == key and stage and tonumber(stage) > 1 then
                    local curStage = tonumber(stage)
                    if curStage < (cfg.LastStage or last) then
                        DetailPage:RegisterElement('button', {
                            label = locales.t('ContinueBrew') .. ' ' .. (cfg.label or key),
                            slot = "content",
                            style = { ['color'] = '#E0E0E0' }
                        }, function()
                            funcs.CallServerAsync('bcc-saloons:CheckIngredients', id, curStage, key)
                        end)
                    else
                        DetailPage:RegisterElement('button', {
                            label = locales.t('CollectBrew') .. ' ' .. (cfg.label or key),
                            slot = "content",
                            style = { ['color'] = '#E0E0E0' }
                        }, function()
                            funcs.CallServerAsync('bcc-saloons:FinishBrewing', id, key, Moonshine)
                        end)
                    end
                end

                -- Reset mash / destroy option when brewing
                if tonumber(stage) == 1 and (currentbrew and currentbrew ~= 'None' and currentbrew == key) then
                    DetailPage:RegisterElement('button', {
                        label = locales.t('DestroyMash') or 'Reset',
                        slot = "content",
                        style = { ['color'] = '#FF6666' }
                    }, function()
                        funcs.CallServerAsync('bcc-saloons:ResetMash', id)
                    end)
                end

                DetailPage:RegisterElement('bottomline', { slot = 'footer', style = {} })

                DetailPage:RegisterElement('button', {
                    label = locales.t('Back'),
                    slot = "footer",
                    style = { ['color'] = '#CCCCCC' }
                }, function()
                    SaloonsStillMenu:Open({ startupPage = MainPage })
                end)

                DetailPage:RegisterElement('button', {
                    label = locales.t('Close'),
                    slot = "footer",
                    style = { ['color'] = '#CCCCCC' }
                }, function()
                    SaloonsStillMenu:Close()
                end)

                SaloonsStillMenu:Open({ startupPage = DetailPage })
            end)
        end
    end

    MainPage:RegisterElement('bottomline', { slot = 'footer', style = {} })

    MainPage:RegisterElement('button', {
        label = locales.t('Close'),
        slot = "footer",
        style = { ['color'] = '#CCCCCC' }
    }, function()
        SaloonsStillMenu:Close()
    end)

    SaloonsStillMenu:Open({ startupPage = MainPage })
end
