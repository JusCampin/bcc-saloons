Config = {

    defaultlang = 'en_lang', -- Default: 'en_lang'; default language code (must match with a file in `shared/languages/`)
    -----------------------------------------------------

    devMode = {
        active = true -- if true, debug messages will be printed to console
    },
    -----------------------------------------------------

    interactDistance = 1.5, -- Default: 1.5; max distance to interact with a prop
    spawnDistance = 50.0,   -- Default: 50.0; clients spawn existing props within this range
    -----------------------------------------------------

    timeToConstruct = 10, -- Default: 10; in seconds; placement animation / construction time
    timeToDestroy = 10,   -- Default: 10; in seconds; destroy animation / delay before returning item
    -----------------------------------------------------

    keys = {
        brew = 0xA1ABB953,    -- [G] 'Brew' key
        build = 0x41AC83D1,   -- [E] 'Build' key
        destroy = 0xE3BF959B, -- [R] 'Destroy' key
    },
    -----------------------------------------------------

    props = {                          -- model names for placed props (must match with database entries)
        barrel = 'p_barrelmoonshine',  -- mash barrel model
        still = 'mp001_p_mp_still02x', -- still model
    },
    -----------------------------------------------------

    returnProps = true, -- Default: true; if true, destroyed props are returned to player's inventory
    jobs = {            -- Jobs that will destroy props instead of picking them up
        'police',
        'sheriff',
        'marshal'
    },
    -----------------------------------------------------
}
