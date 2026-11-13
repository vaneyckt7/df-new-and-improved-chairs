# New and Improved Chairs

A DFHack script for Dwarf Fortress that replaces the picture of every built chair with a heavy
dwarven slat-back chair, and lets you turn it to face north, east, south or west. All of it is
purely cosmetic: the game has no notion of chair facing, so nothing about the chair or the room
changes; the save only gains a small DFHack note of each turned or moved chair. Remove the mod
and every chair looks exactly as it did before.

![A dining room with chairs facing all four ways](docs/room.png)

The chair is coloured from the material it is made of:

![The chair in every material, front and side view](docs/materials.png)

## Requirements

DFHack. The mod is plain Lua run by DFHack: there is no compiled plugin, so it is not tied to
one DFHack build. Tested on:

- Dwarf Fortress 53.16 (Steam version, on Windows under Wine), with the graphical tiles
- DFHack 53.16-r1.1

Native Windows, Linux and Proton are untested.

## Using it

![The chair's sheet with the turn and move controls](docs/sheet.png)

Click a chair. After its name in the view sheet there is a small circle with an arrow: click it
to turn the chair. A chair starts out facing south, toward you; each click turns it a quarter:
west, north, east and south again.

Next to it are four small triangles, `◄ ▲ ▼ ►`. Each click moves the chair's picture one
pixel that way inside its tile, to pull it up to a table for example. The chair is never clipped
or resized: a triangle goes dim once the picture has reached the edge of the tile. After a move
a red `x` appears that puts the chair back where it rests. Turning the chair also puts it back.

Where a chair rests depends on its facing: a chair facing north sits 6 pixels up, against the
table behind it; one facing east or west sits 2 pixels up and 3 or 4 pixels toward its table;
one facing south sits where the art draws it. Moves count from there.

The two chair icons in the sheet show the same chair. Facings and positions are saved with the
fortress and come back when you load it.

From the DFHack console or Lua:

```lua
local cf = reqscript('improved-chairs')
cf.set_facing(building_id, 0)   -- 0 N, 1 E, 2 S (the default), 3 W
cf.get_facing(building_id)
cf.set_nudge(building_id, dx, dy)   -- pixels from the resting position, +x east, +y south
cf.get_nudge(building_id)           -- dx, dy
cf.get_room(facing, 0)              -- pixels of room toward 0 N, 1 E, 2 S, 3 W
```

The mod is two DFHack overlay widgets. `improved-chairs.map` draws the chairs; `overlay disable
improved-chairs.map` gives every chair the game's own picture back until you enable it again.
`improved-chairs.sheet` is the control on the sheet; `overlay disable improved-chairs.sheet`
hides it. Leave that one where it is: it is drawn over the sheet's title, so a moved widget no
longer lines up with the sheet.

## Installation

There are two ways to install: subscribe on the Steam Workshop, or copy the files in by hand.
Use one or the other, not both.

### From the Steam Workshop

1. Subscribe and wait for Steam to finish downloading.
2. Fully exit the game, start it again through DFHack and load your fortress.

Existing saves work. Do not add the mod to a world's mod list at world generation; it does
nothing there.

DFHack runs scripts straight from a Workshop mod, so there is no install step. The mod is three
files, used where they are:

```
scripts_modinstalled/improved-chairs.lua                             the script
scripts_modinstalled/internal/improved-chairs/template.lua           the chair art
scripts_modinstalled/internal/improved-chairs/chair_controls.png     the control symbols
```

It writes no files of its own (DFHack notes the two widgets in `dfhack-config/overlay.json`),
does not use the network, and stores each chair's facing and position in
your save as a small DFHack note. To uninstall, unsubscribe. Also delete any copy of the mod
left under `mods` and `data/installed_mods` in the game's data folder: the game keeps its own
copy there.

All messages go to the DFHack console. If chairs do not change, look there for lines starting
with `improved-chairs:`, and check that `overlay list improved-chairs` shows both widgets
enabled.

### By hand

1. Download the release archive.
2. Extract it into the Dwarf Fortress folder (the one that contains `dfhack-config`). It adds
   three files and a licence text:

   ```
   dfhack-config/scripts/improved-chairs.lua
   dfhack-config/scripts/internal/improved-chairs/template.lua
   dfhack-config/scripts/internal/improved-chairs/chair_controls.png
   ```

3. Start the game through DFHack. There is nothing to enable.

To update, extract the newer archive over the old files. To uninstall, delete them.

### Coming from version 1.0

Version 1.0 drew the chairs with a compiled plugin that it copied into DFHack's own folder.
Nothing uses it any more. With the game closed, delete these two files from the folder that
contains DFHack's `hack` folder:

```
hack/plugins/improved-chairs.plug.dll
hack/lua/plugins/improved-chairs.lua
```

If you installed 1.0 by hand from its archive, also delete these, or a Workshop install of 1.1
loses to the old script and no chair changes:

```
hack/scripts/improved-chairs.lua
hack/data/art/chair_slat_template.png
hack/data/art/chair_controls.png
```

A world whose mod list includes version 1.0 keeps using the 1.0 script. The mod was never meant
to be in a world's mod list; in such a world, keep the two plugin files or start a new world.

Left in place the old plugin does nothing, but after
a DFHack update DFHack reports at every start that it was not built for that version. Facings
and positions saved with 1.0 are read as they are.

## How it works

Every frame the game draws the map into layers of texture numbers, one cell per map tile; a
chair's picture goes in the building layer. DFHack lets an overlay widget run after the game
has filled those layers and before they reach the screen. The `improved-chairs.map` widget
goes through the built chairs, and for each one in view puts the texture for its material,
facing and position in the chair's cell. Chairs up to eight levels below, seen through open space, are in
the game's lower layers and get the same treatment. Creatures and items are separate layers that the game
draws over the building layer as before, so a dwarf on the chair's tile is drawn over the chair
(verified, as is scrolling).

Only a cell the game has put a building picture in is changed, so a chair the game does not
show stays unshown. A chair that is still being built is drawn as the game draws it, and so is
a chair that is an item (in a stockpile, or being hauled).

Facings and nudges are stored per fortress in DFHack site data (`improved-chairs`), keyed by
building id. They are restored on map load, and entries for chairs that no longer exist are
dropped.

## The art

There is no sheet of finished sprites. `art/sets/slat_template.png` holds the chair once per
class of material (rows: wood, stone, metal, glass, each with its own surface texture) and
facing (columns: N, E, S, W), 32x32 pixels per tile, drawn in marker colours:

- `(t, 0, 0)` red: a shade of the material's own colour ramp
- `(0, 0, t)` blue: a shade of the first ramp, used for the legs as on the game's own chair
- everything else (outline, floor shadow, the clear openings between the slats) is kept as it is

The game holds 18 shades for every material colour, in two ramps of nine; it draws wooden
furniture with the first and stone, metal and glass with the second. The script paints the
template with those shades the first time a chair of a given material is drawn, so every
material gets its own chair and there is no table of colours to maintain. A nudged chair is
painted the same way from the template tile moved by its offset.

DFHack's Lua cannot read the pixels of a PNG, so the script reads the template from
`scripts/internal/improved-chairs/template.lua`, which `art/make_template.py` writes from the
PNG (it needs Python with Pillow). To try a changed template in a running game, run
`art/make_template.py`, copy `template.lua` over the installed one and run
`improved-chairs reload`. `improved-chairs status` prints how many chair tiles have been
painted and drawn.

## Tests

```sh
lua test/run_tests.lua      # any Lua 5.3 or later; DFHack and the game are stubbed
```

The tests cover the painting (tones, see-through pixels, moved tiles), the room a chair has in
its tile, the saved data (reading, the conversion of old saves, dropping chairs that are gone)
and which map cell a chair is drawn in. `package.sh` runs them.

## Releasing

1. In `steam/info.txt`, raise `NUMERIC_VERSION` (keep it three digits: DFHack compares it as
   text and uses the highest copy it finds) and `DISPLAYED_VERSION`, and write a new
   `STEAM_CHANGELOG`.
2. `./package.sh <version>` writes `dist/improved-chairs-<version>.zip` (the hand install) and
   the Workshop mod folder `dist/workshop/new_and_improved_chairs`. It refuses to run when
   `template.lua` does not match the PNG.
3. Copy `dist/workshop/new_and_improved_chairs` to the game's `mods/mod_upload/` and upload from the Mods
   screen.
4. After the first upload the game adds a `STEAM_FILE_ID` line to the uploaded `info.txt`. Copy
   that line into `steam/info.txt`; without it the next upload creates a second Workshop item.
5. `STEAM_DESCRIPTION` replaces the Workshop page's description on every upload. The full text
   is `steam/description.txt`; paste it on the page, then remove `STEAM_DESCRIPTION` from
   `steam/info.txt` to keep it.

## Known limitations

- The controls are placed from where the sheet title starts, 90 columns from the right edge
  of the interface. An interface change that moves the title would leave them behind.
- A nudge moves only the chair's picture. A dwarf sitting on the chair is drawn by the game where
  it always is, in the middle of the tile, so a chair moved far to one side sticks out beside
  its sitter.
- A chair cannot be nudged out of its tile: the game lets a building draw only on its own tile.
  How far it can go from its resting position depends on the view: up to 13 pixels sideways for
  a chair seen from the side, 1 pixel up or down for a chair facing south, which nearly fills
  the height of the tile, and not up at all for a chair facing east or west.
- The script reads the game's map layers by the names DFHack gives them. A game update that
  changes how the map is drawn can stop the chairs from changing until the script is updated;
  the game's own chairs show in the meantime.
- Semi-transparent pixels (the shadow under the seat) can differ from version 1.0 by one step
  of 255 in a colour channel.
- On DFHack 53.16-r1.1 and older, a reclaimed fortress cannot store anything until the game has
  saved it once. Chairs turned or nudged before that first save are kept and stored right after
  it, so they reach the save file with the second save: save once more before quitting.
  DFHack 53.16-r2 and later do not have this gap.
- Fortress mode only. In adventure mode chairs are drawn by the game; visiting your old fort as
  an adventurer leaves the stored facings untouched but does not draw them.

## License

MIT.
