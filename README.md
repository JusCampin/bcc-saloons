# bcc-saloons

## Features

- Smoke from stills when brewing
- Stills that are brewing can not be opened until done brewing
- Ingredients are shown in the menu
- Stills auto spawn and despawn when entering and leaving the area
- Animations on placing and destroying etc

## Dependencies

- *Requires MariaDB version 10.11 and above or MySQL verions 8.0 and above*
- [vorp_core](https://github.com/VORPCORE/vorp-core-lua)
- [vorp_inventory](https://github.com/VORPCORE/vorp_inventory-lua)
- [feather-menu](https://github.com/FeatherFramework/feather-menu/releases)
- [bcc-utils](https://github.com/BryceCanyonCounty/bcc-utils)

## Installation

1. Make sure all dependencies are installed/updated and ensured before this script.
2. Add `ensure bcc-saloons` to your `server.cfg`.
3. Run the `brewing.sql` file to create the `brewing` table in the database
4. Add images to: `...\vorp_inventory\html\img`.
5. Restart your server to apply the changes.

## Usage

### Brewing Moonshine

Brewing moonshine is a step-by-step process. You must first ferment your mash and alcohol. Then once distilling is started each stage will require different ingredients and different amount of time. Once completed you collect your brew.

### Stills

Stills produce smoke when brewing, and are multi staged crafting. This could be for any drink or moonshine you want, using the still prop will take stages no matter what.

### Barrels

Barrels are a single stage brewing system usually used to create alcohols and mashes

## Contributing

Contributions to the bcc-saloons script are welcome! If you have any bug fixes, improvements, or new feature suggestions, feel free to open a pull request on the GitHub repository.
