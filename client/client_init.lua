Core = exports.vorp_core:GetCore()
BccUtils = exports['bcc-utils'].initiate()
FeatherMenu = exports['feather-menu'].initiate()
DBG = BccUtils.Debug:Get('bcc-saloons', Config.devMode.active)

if DBG then
    DBG:Enable()
    DBG:Info('Saloons debug initialized')
end

-- Client Globals
InMenu = false

-- Shared runtime state (globals used by client modules)
BrewGroup = GetRandomIntInRange(0, 0xffffff)
BuildPrompt, BrewPrompt, DestroyPrompt = 0, 0, 0
PromptsStarted = false
Placing = false
PlacingPromptsActive = false
PlacingObj = 0
TempObj = 0
Stills = {}
ActiveProps = {}
LastPlaced = nil
SpawnerStarted = false
MainThreadStarted = false
Destroying = nil
LastRemainingUpdate = 0
recentlyDestroyed = {}
