-- This file defines the different liquor recipes that players can use to create liquor from mash.
Moonshine = {
    ['WhiteWhiskey'] = {
        label = 'White Whiskey',
        Yield = 2,
        LastStage = 3,     -- highest stage index; used to detect completion and smoke behavior
        [1] = {
            stilltime = 1, -- in minutes
            ingredients = {
                { id = 'water', label = 'Water', qty = 1 },
            },
            Tip = 'You need 1x Water'
        },

        [2] = {
            stilltime = 3, -- in minutes
            ingredients = {
                { id = 'sugarcube', label = 'Sugar Cube', qty = 1 },
            },
            Tip = 'You need 1x Sugarcube'
        },

        [3] = {
            stilltime = 6, -- in minutes
            ingredients = {
                { id = 'hop', label = 'Hop', qty = 5 },
            },
            Tip = 'You need 5x hop'
        },
    },
    -----------------------------------------------------

    ['BlackberryMoonshine'] = {
        label = 'Blackberry Moonshine',
        Yield = 15,
        LastStage = 3,
        [1] = {
            stilltime = 1, -- in minutes
            ingredients = {
                { id = 'Water', label = 'Water', qty = 1 },
            },
            Tip = 'You need 1x Water'
        },

        [2] = {
            stilltime = 3, -- in minutes
            ingredients = {
                { id = 'BlackberryMash', label = 'Blackberry Mash', qty = 1 },
                { id = 'Sugar', label = 'Sugar', qty = 1 },
            },
            Tip = 'You need 1x Blackberry Mash and 1x Sugar'
        },

        [3] = {
            stilltime = 6, -- in minutes
            ingredients = {
                { id = 'GlassBottles', label = 'Empty Bottles', qty = 15 },
            },
            Tip = 'You need 15x Empty Bottles'
        },
    },
    -----------------------------------------------------

    ['ApplePieMoonshine'] = {
        label = 'Apple Moonshine',
        Yield = 5,
        LastStage = 3,
        [1] = {
            stilltime = 1, -- in minutes
            ingredients = {
                { id = 'Water', label = 'Water', qty = 1 },
            },
            Tip = 'You need 1x Water'
        },

        [2] = {
            stilltime = 3, -- in minutes
            ingredients = {
                { id = 'BlackberryMash', label = 'Blackberry Mash', qty = 1 },
                { id = 'Sugar', label = 'Sugar', qty = 1 },
            },
            Tip = 'You need 1x Blackberry Mash and 1x Sugar'
        },

        [3] = {
            stilltime = 6, -- in minutes
            ingredients = {
                { id = 'GlassBottles', label = 'Empty Bottles', qty = 15 },
            },
            Tip = 'You need 15x Empty Bottles'
        },
    },
}