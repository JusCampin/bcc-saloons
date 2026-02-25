fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

game 'rdr3'
lua54 'yes'
author 'BCC Team'

shared_scripts {
	'configs/*.lua',
	'shared/locales.lua',
	'shared/languages/*.lua'
}

client_scripts {
    'client/client_init.lua',
    'client/functions.lua',
	'client/prompts.lua',
	'client/spawner.lua',
	'client/placement.lua',
	'client/brewing.lua',
	'client/sync.lua',
	'client/main_loop.lua',
	'client/menus/*.lua',
	'client/main.lua'
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'server/bootstrap.lua',
	'server/launcher.lua'
}

files { 'items/*' }

version '1.0.0'