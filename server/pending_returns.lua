local M = {}

local PendingReturns = {}

local function CheckTable(tbl, element)
    if not tbl then return false end
    for _, v in pairs(tbl) do
        if v == element then
            return true
        end
    end
    return false
end

CreateThread(function()
    while true do
        local now_ms = math.floor(os.time() * 1000)
        for i = #PendingReturns, 1, -1 do
            local entry = PendingReturns[i]
            if entry and entry.due_ms <= now_ms then
                table.remove(PendingReturns, i)
                local ok, err = pcall(function()
                    if entry.returnProps then
                        if CheckTable(Config.jobs, entry.job) then
                            local destroyMsg = (entry.object == Config.props.still) and locales.t('StillDestroyed') or locales.t('BarrelDestroyed')
                            Core.NotifyRightTip(entry.src, destroyMsg, 4000)
                        else
                            if entry.object == Config.props.still then
                                pcall(function() exports.vorp_inventory:addItem(entry.src, Config.props.still, 1) end)
                                Core.NotifyRightTip(entry.src, locales.t('StillPickedUp'), 4000)
                            else
                                pcall(function() exports.vorp_inventory:addItem(entry.src, Config.props.barrel, 1) end)
                                Core.NotifyRightTip(entry.src, locales.t('BarrelPickedUp'), 4000)
                            end
                        end
                    end
                end)
                if not ok then
                    if DBG then DBG:Error('PendingReturns worker error: ' .. tostring(err)) end
                end
            end
        end
        Wait(1000)
    end
end)

function M.Enqueue(entry)
    table.insert(PendingReturns, entry)
end

return M
