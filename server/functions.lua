local M = {}

local function SafeMySQLQuery(query, params)
    local ok, res = pcall(function()
        return MySQL.query.await(query, params)
    end)
    if not ok then
        if DBG then DBG:Error('MySQL error: ' .. tostring(res)) end
        return false, nil
    end
    return true, res
end

local function ShallowCopyRow(row)
    if not row then return nil end
    local c = {}
    for k, v in pairs(row) do c[k] = v end
    return c
end

local function ShallowCopyList(list)
    if not list then return nil end
    local out = {}
    for i, v in ipairs(list) do out[i] = ShallowCopyRow(v) end
    return out
end

-- Normalize ingredient definitions to a list of { id=..., label=..., qty=NUMBER }
local function NormalizeIngredients(raw)
    if not raw then return {} end
    local out = {}
    if type(raw) ~= 'table' then return out end
    for _, v in ipairs(raw) do
        if type(v) == 'table' then
            local id = tostring(v.id or v[1])
            local label = v.label or v[2] or id
            local qty = tonumber(v.qty or v.q or v[3]) or 0
            table.insert(out, { id = id, label = label, qty = qty })
        end
    end
    return out
end

M.SafeMySQLQuery = SafeMySQLQuery
M.ShallowCopyRow = ShallowCopyRow
M.ShallowCopyList = ShallowCopyList
M.NormalizeIngredients = NormalizeIngredients

return M
