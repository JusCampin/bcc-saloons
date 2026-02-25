Core = exports.vorp_core:GetCore()
BccUtils = exports['bcc-utils'].initiate()
DBG = BccUtils.Debug:Get('bcc-saloons', Config.devMode.active)

if DBG then
    DBG:Enable()
    DBG:Info('Saloons debug initialized')
end
