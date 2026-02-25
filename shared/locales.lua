-- shared/locales.lua
-- Minimal locales loader: loads shared/languages/<code>.lua via LoadResourceFile

local M = {}
local _languages = {}
local defaultLang = 'en_lang'

local function safeFormat(fmt, ...)
    if fmt == nil then return nil end
    local ok, out = pcall(string.format, tostring(fmt), ...)
    if ok then return out end
    return tostring(fmt)
end

local function loadFromSource(code, src, srcName)
    if type(code) ~= 'string' or type(src) ~= 'string' then return false end
    local fn = load(src, srcName)
    if not fn then return false end
    local ok, ret = pcall(fn)
    if not ok or type(ret) ~= 'table' then return false end
    _languages[code] = ret
    return true
end

local function tryLoadLanguage(code)
    if type(code) ~= 'string' then return false end
    if type(LoadResourceFile) ~= 'function' or type(GetCurrentResourceName) ~= 'function' then return false end
    local path = ('shared/languages/%s.lua'):format(code)
    local res = GetCurrentResourceName()
    local src = LoadResourceFile(res, path)
    if src and type(src) == 'string' then
        return loadFromSource(code, src, path)
    end
    return false
end

function M.setDefault(code)
    if type(code) ~= 'string' then return false end
    if tostring(code):match('%.lua') then return false end
    if _languages[code] then defaultLang = code; return true end
    if tryLoadLanguage(code) then defaultLang = code; return true end
    return false
end

function M.getDefault()
    return defaultLang
end

function M.t(key, ...)
    local lang = _languages[defaultLang] or {}
    local val = lang[key]
    if not val then
        return ('Translation [%s][%s] does not exist'):format(tostring(defaultLang), tostring(key))
    end
    return safeFormat(val, ...)
end

function M.tu(key, ...)
    local translated = M.t(key, ...)
    if type(translated) ~= 'string' then translated = tostring(translated) end
    return translated:gsub('^%l', string.upper)
end

-- Auto-export locales into _G so resources can simply include this file and use locales.t()/locales.tu()
pcall(function()
    if type(_G) == 'table' and rawget(_G, 'locales') == nil then rawset(_G, 'locales', M) end
end)

-- Try to load default language on init (non-fatal)
pcall(function() M.setDefault(defaultLang) end)

return M
