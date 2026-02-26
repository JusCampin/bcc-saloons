-- This file defines the different mash recipes that players can use to create moonshine.
Mash = {
    ['CornMash'] = {
        label = 'Corn Mash', -- label for menu
        name = 'corn_mash', -- name of produced item in DB/inventory
        yield = 1,           -- amount of mash produced per batch
        lastStage = 3,       -- final stage index; used to detect completion
        [1] = {              -- stage 1
            fermentTime = 5, -- in minutes
            ingredients = {  -- list of ingredients required to start this mash
                { id = 'water', label = 'Water', qty = 1 },
                { id = 'corn',  label = 'Corn',  qty = 1 },
                { id = 'sugar', label = 'Sugar', qty = 1 },
            },
            Tip = 'Add required ingredients to start this mash.'
        },
        [2] = {              -- stage 2
            fermentTime = 5, -- in minutes
            ingredients = {  -- list of ingredients required to progress this mash; can be empty
                { id = 'hop', label = 'Hop', qty = 1 },
            },
            Tip = 'Mash fermenting — will progress automatically; do not disturb.'
        },
        [3] = {              -- stage 3
            fermentTime = 1, -- in minutes
            ingredients = {  -- list of ingredients required to complete this mash; can be empty
                { id = 'wateringcan_empty', label = 'Empty Watering Jug', qty = 1 }
            },
            Tip = 'Fermentation complete — collect the brew or use Reset to destroy.'
        },
    },
    -----------------------------------------------------

    ['FruitMash'] = {
        label = 'Fruit Mash', -- label for menu
        name = 'fruit_mash', -- name of produced item in DB/inventory
        yield = 1,            -- amount of mash produced per batch
        lastStage = 3,        -- final stage index; used to detect completion
        [1] = {               -- stage 1
            fermentTime = 5,  -- in minutes
            ingredients = {   -- list of ingredients required to start this mash
                { id = 'water', label = 'Water', qty = 1 },
                { id = 'apple', label = 'Apple', qty = 1 },
                { id = 'sugar', label = 'Sugar', qty = 1 },
            },
            Tip = 'Add required ingredients to start this mash.'
        },
        [2] = {              -- stage 2
            fermentTime = 5, -- in minutes
            ingredients = {  -- list of ingredients required to progress this mash; can be empty
                { id = 'hop', label = 'Hop', qty = 1 },
            },
            Tip = 'Mash fermenting — will progress automatically; do not disturb.'
        },
        [3] = {              -- stage 3
            fermentTime = 1, -- in minutes
            ingredients = {  -- list of ingredients required to complete this mash; can be empty
                { id = 'wateringcan_empty', label = 'Empty Watering Jug', qty = 1 }
            },
            Tip = 'Fermentation complete — collect the brew or use Reset to destroy.'
        },
    },
    -----------------------------------------------------

    ['SweetenedMash'] = {
        label = 'Sweetened Mash', -- label for menu
        name = 'sweetened_mash', -- name of produced item in DB/inventory
        yield = 1,                -- amount of mash produced per batch
        lastStage = 3,            -- final stage index; used to detect completion
        [1] = {                   -- stage 1
            fermentTime = 0.5,      -- in minutes
            ingredients = {       -- list of ingredients required to start this mash
                { id = 'water', label = 'Water', qty = 1 },
                { id = 'sugar', label = 'Sugar', qty = 1 },
            },
            Tip = 'Add required ingredients to start this mash.'
        },
        [2] = {              -- stage 2
            fermentTime = 0.5, -- in minutes
            ingredients = {  -- list of ingredients required to progress this mash; can be empty
                { id = 'hop', label = 'Hop', qty = 1 },
            },
            Tip = 'Mash fermenting — will progress automatically; do not disturb.'
        },
        [3] = {              -- stage 3
            fermentTime = 0.5, -- in minutes
            ingredients = {  -- list of ingredients required to complete this mash; can be empty
                { id = 'wateringcan_empty', label = 'Empty Watering Jug', qty = 1 },
            },
            Tip = 'Fermentation complete — collect the brew or use Reset to destroy.'
        },
    },
    -----------------------------------------------------
}
