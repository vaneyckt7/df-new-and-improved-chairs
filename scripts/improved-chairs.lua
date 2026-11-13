-- New and Improved Chairs: every built chair is drawn from this mod's art, in the colour of its
-- material, and can be turned (N/E/S/W) and nudged inside its tile from its view sheet.  Cosmetic.
--@ module = true
--
-- All of it is this script.  Two overlay widgets do the work:
--   map    after the game has drawn the map, puts the chair pictures in the map's building layer
--   sheet  the turn and nudge controls, and the chair's icons, on the chair's view sheet
-- Facings and nudges are kept here and saved with the fortress (DFHack site data, keyed by
-- building id).  A chair that has never been turned faces south.
--
-- Site data: ["<building id>"] = facing 0..3 (south is not stored), and for a chair that has been nudged
-- ["<building id>:nudge"] = {dx, dy}, pixels from where the chair rests for its facing (+x east, +y south).

local overlay = require('plugins.overlay')

local SITE_KEY = 'improved-chairs'

-- The folder next to this script that holds the art.
local function data_dir()
    local src = debug.getinfo(1, 'S').source
    local path = src:sub(1, 1) == '@' and src:sub(2) or dfhack.findScript('improved-chairs')
    local dir = path and path:gsub('\\', '/'):match('^(.*)/[^/]*$')
    return (dir or '.') .. '/internal/improved-chairs/'
end
local DATA = data_dir()

-- Facing values: 0..3 = N E S W.  A chair that has not been turned faces DEFAULT.
local NORTH, EAST, SOUTH, WEST = 0, 1, 2, 3
local DEFAULT = SOUTH
local TILE, FACINGS = 32, 4
local ROW_WOOD, ROW_STONE, ROW_METAL, ROW_GLASS = 0, 1, 2, 3

-- Where a chair with each facing rests before any nudge, as an offset from where the template
-- draws it: a chair seen from behind sits up against the table north of it, one seen from the
-- side sits a little higher and nearer its table.  Nudges count from here.
local HOME = {[NORTH]={0, -6}, [EAST]={3, -2}, [SOUTH]={0, 0}, [WEST]={-4, -2}}

-- ---- the art ----------------------------------------------------------------------------------
--
-- The tint template (template.lua, made from art/sets/slat_template.png by art/make_template.py)
-- is four rows (wood, stone, metal, glass) of four facings, 32x32 each, so each class of
-- material carries its own surface texture.  Two kinds of pixel are markers:
--   (t, 0, 0, 255)  the material's own ramp, tone t = 1 (shade 2) .. 255 (shade 8)
--   (0, 0, t, 255)  first ramp whatever the material, same tones: the game draws the legs of
--                   its own chair with the dark shades of the first ramp
-- Every other pixel (outline, shadow, transparent) is copied unchanged.
--
-- The game gives every colour a palette of 18 shades: two ramps of nine, dark to light.  Its own
-- wooden furniture is drawn with the first ramp, stone/metal/glass with the second.  The chair
-- uses the ramp the game would use for that material.

local FRAME_LO, FRAME_HI = 2, 8       -- ramp shades the tones 1..255 are spread over
local PALETTE_BYTES = 54              -- 18 shades, rgb

local template        -- [row * FACINGS + facing + 1] = 1024 pixels, each an integer 0xRRGGBBAA
local room_of         -- same index -> {[NORTH]=, [EAST]=, [SOUTH]=, [WEST]=} pixels of empty margin

-- How far the picture in a tile can move before a pixel that is not fully transparent would
-- leave the tile.  All zero for an empty tile.
local function tile_room(px)
    local x0, y0, x1, y1 = TILE, TILE, -1, -1
    for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
            if px[y * TILE + x + 1] & 0xff ~= 0 then
                if x < x0 then x0 = x end
                if x > x1 then x1 = x end
                if y < y0 then y0 = y end
                if y > y1 then y1 = y end
            end
        end
    end
    if x1 < 0 then return {[NORTH]=0, [EAST]=0, [SOUTH]=0, [WEST]=0} end
    return {[NORTH]=y0, [EAST]=TILE - 1 - x1, [SOUTH]=TILE - 1 - y1, [WEST]=x0}
end

-- Read template.lua.  Returns true when the template is in place.
local function load_template()
    local ok, data = pcall(dofile, DATA .. 'template.lua')
    if not ok or type(data) ~= 'table' or #data ~= 4 * FACINGS then return false end
    local tiles, rooms = {}, {}
    for i, hex in ipairs(data) do
        if type(hex) ~= 'string' or #hex ~= TILE * TILE * 8 or hex:find('%X') then return false end
        local px, n = {}, 0
        for v in hex:gmatch('%x%x%x%x%x%x%x%x') do
            n = n + 1
            px[n] = tonumber(v, 16)
        end
        tiles[i], rooms[i] = px, tile_room(px)
    end
    template, room_of = tiles, rooms
    return true
end

if not load_template() then
    dfhack.printerr('improved-chairs: could not read ' .. DATA .. 'template.lua; chairs keep the game\'s own look')
end

-- Which template row a material uses.
local function class_row(flags)
    if flags.IS_GLASS then return ROW_GLASS end
    if flags.IS_METAL then return ROW_METAL end
    if flags.IS_STONE then return ROW_STONE end
    if flags.WOOD then return ROW_WOOD end
    return ROW_STONE
end

-- The tint key of a material: (index of its game colour + 1) * 8 + class row * 2, plus 1 for wood.
-- The colour is the first colour of the material's solid-state colour pattern; index 0 (the game's
-- default palette) stands in when the raws give none.
local function material_tint(mat_type, mat_index)
    local info = dfhack.matinfo.decode(mat_type, mat_index)
    if not info then return ROW_STONE << 1 end
    local flags = info.material.flags
    local wood = (flags.WOOD and 1 or 0) | class_row(flags) << 1
    local d = df.global.world.raws.descriptors
    local p = info.material.state_color.Solid
    if p < 0 or p >= #d.patterns or #d.patterns[p].colors == 0 then return wood end
    local c = d.patterns[p].colors[0]
    if c < 0 or c >= #d.colors then return wood end
    return (c + 1) * 8 + wood
end

-- (global, like tile_handles below: running `improved-chairs status` executes this file again
-- and must not throw the caches away)
tint_of_material = tint_of_material or {}     -- (mat_type, mat_index) -> tint key; emptied with the world

-- The tint key of a built chair: that of the chair item it holds.
local function chair_tint(b)
    local items = b.contained_items
    if #items == 0 then return ROW_STONE << 1 end
    local item = items[0].item
    local mat_type, mat_index = item:getMaterial(), item:getMaterialIndex()
    local key = mat_type << 32 | mat_index & 0xffffffff
    local tint = tint_of_material[key]
    if not tint then
        tint = material_tint(mat_type, mat_index)
        tint_of_material[key] = tint
    end
    return tint
end

-- The 18-shade palette the game holds for a tint key's colour, as a table of PALETTE_BYTES
-- numbers; nil if it is not there.
local function key_palette(tint)
    local src
    if tint < 8 then
        src = df.global.gps.default_palette.color
    else
        local colors = df.global.world.raws.descriptors.colors
        local c = tint // 8 - 1
        if c >= #colors then return nil end
        src = colors[c].palette.color
    end
    local pal = {}
    for i = 0, PALETTE_BYTES - 1 do pal[i] = src[i] end
    return pal
end

-- The colour for tone t (1..255) on the ramp starting at pal[base], packed for a texture (red in
-- the low byte, opaque).  // rounds down, so a ramp that runs downhill rounds the same way as
-- one that runs uphill.
local function tone(pal, base, t)
    local x = (t - 1) * (FRAME_HI - FRAME_LO)
    local i = FRAME_LO + x // 254
    local a, b, n = base + i * 3, base + (i < 8 and i + 1 or 8) * 3, x % 254
    local r = pal[a] + (pal[b] - pal[a]) * n // 254
    local g = pal[a + 1] + (pal[b + 1] - pal[a + 1]) * n // 254
    local bl = pal[a + 2] + (pal[b + 2] - pal[a + 2]) * n // 254
    return 0xff000000 | bl << 16 | g << 8 | r
end

-- One template pixel (0xRRGGBBAA) painted with a palette and packed for a texture.
local function paint_pixel(v, pal, own_base)
    local r, g, b, a = v >> 24, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff
    if a == 0 then return 0 end
    if a == 255 and g == 0 and b == 0 and r > 0 then return tone(pal, own_base, r) end
    if a == 255 and r == 0 and g == 0 and b > 0 then return tone(pal, 0, b) end
    -- A see-through pixel (the shadow under the seat) is handed over with its colour already
    -- scaled by its alpha.  The game then blends it darker than the template says, which is the
    -- look the chair was drawn and judged with.
    if a < 255 then r, g, b = r * a // 255, g * a // 255, b * a // 255 end
    return a << 24 | b << 16 | g << 8 | r
end

-- The pixels of one chair tile: the template tile for the tint key's material row and the
-- facing, moved by (dx, dy) and painted.  What moves in is transparent; what moves out is
-- dropped, so the caller keeps the move within the tile's room.  nil without a palette.
local function paint_tile(tint, facing, dx, dy)
    local pal = key_palette(tint)
    if not pal then return nil end
    local src = template[(tint >> 1 & 3) * FACINGS + facing + 1]
    local own_base = tint & 1 == 1 and 0 or 27      -- second ramp unless wood
    local out, painted = {}, {}
    for y = 0, TILE - 1 do
        local sy = y - dy
        for x = 0, TILE - 1 do
            local sx = x - dx
            local c = 0
            if sx >= 0 and sx < TILE and sy >= 0 and sy < TILE then
                local v = src[sy * TILE + sx + 1]
                c = painted[v]
                if not c then
                    c = paint_pixel(v, pal, own_base)
                    painted[v] = c
                end
            end
            out[y * TILE + x + 1] = c
        end
    end
    return out
end

-- Tiles are painted once and kept: tile key (tint key, facing, move) -> texture handle.  They are
-- dropped from the table when the world goes (colour indexes belong to a world's raws) but the
-- textures are never deleted: DFHack does not hand a deleted handle's slot back cleanly.
tile_handles = tile_handles or {}
STATS = STATS or {frames=0, cells=0, tiles=0}

-- Texpos of the chair tile for a tint key, facing and move from the template position; nil if
-- it cannot be had.
local function tile_texpos(tint, facing, dx, dy)
    local key = tint | facing << 32 | (dx + TILE) << 40 | (dy + TILE) << 48
    local handle = tile_handles[key]
    if not handle then
        local px = template and paint_tile(tint, facing, dx, dy)
        handle = px and dfhack.textures.createTile(px, TILE, TILE)
        -- a refused texture is left out, so the next draw asks again
        if not handle or handle == 0 then return nil end
        tile_handles[key] = handle
        STATS.tiles = STATS.tiles + 1
    end
    local texpos = dfhack.textures.getTexposByHandle(handle)
    return texpos and texpos > 0 and texpos or nil
end

-- ---- facings and nudges -------------------------------------------------------------------------

local facing_of = {}    -- building id -> NORTH..WEST; absent = DEFAULT
local nudge_of = {}     -- building id -> {dx, dy}; absent = none

-- Saves made before the mod was renamed hold the data under the old name; it is read from there
-- once and saved under the new name from then on.
local OLD_SITE_KEY = 'chair-facing'

local function load_data()
    return dfhack.persistent.getSiteData(SITE_KEY) or dfhack.persistent.getSiteData(OLD_SITE_KEY, {})
end

-- What saved nudges count from.  1 (no marker): where the template draws the chair.  2: the
-- resting position for the chair's facing.  restore() converts older data once.
local FORMAT_KEY, FORMAT = 'format', 2

local function save_data(data)
    dfhack.persistent.saveSiteData(SITE_KEY, data)
end

-- Facing of a chair building (DEFAULT if it has never been turned).
function get_facing(building_id)
    return facing_of[building_id] or DEFAULT
end

local function nudge_key(building_id)
    return tostring(building_id) .. ':nudge'
end

-- Set a chair's facing, here and in the save; anything but NORTH..WEST means DEFAULT.
-- A chair that is turned starts where it rests for the new facing: any nudge it had belonged to the old view
-- and is dropped.
function set_facing(building_id, facing)
    if type(facing) ~= 'number' or facing < NORTH or facing > WEST then facing = DEFAULT end
    facing = math.floor(facing)
    facing_of[building_id] = facing ~= DEFAULT and facing or nil
    nudge_of[building_id] = nil
    local data = load_data()
    data[tostring(building_id)] = facing_of[building_id]
    data[nudge_key(building_id)] = nil
    save_data(data)
end

-- How many pixels a chair with this facing can be nudged toward dir (NORTH..WEST) from where it
-- rests.  The chair is never clipped or resized, so this is the empty margin of its picture: the
-- least of the four material rows, so the answer holds whatever the chair is made of.
function get_room(facing, dir)
    if not template or not HOME[facing] or not HOME[dir] then return 0 end
    local least = TILE
    for row = ROW_WOOD, ROW_GLASS do
        least = math.min(least, room_of[row * FACINGS + facing + 1][dir])
    end
    -- room is measured from the template position; resting has used some of it up or freed some
    local hx, hy = HOME[facing][1], HOME[facing][2]
    local used = dir == NORTH and -hy or dir == EAST and hx or dir == SOUTH and hy or -hx
    return math.max(0, least - used)
end

local function clamp_nudge(facing, dx, dy)
    dx = math.max(-get_room(facing, WEST), math.min(get_room(facing, EAST), math.floor(dx)))
    dy = math.max(-get_room(facing, NORTH), math.min(get_room(facing, SOUTH), math.floor(dy)))
    return dx, dy
end

-- A chair's nudge: dx, dy in pixels (+x east, +y south); 0, 0 when it sits where it rests for its facing.
function get_nudge(building_id)
    local n = nudge_of[building_id]
    if n then return n[1], n[2] end
    return 0, 0
end

-- Move a chair's picture inside its tile, here and in the save.  The move is held to the room
-- the picture has; returns the dx, dy actually set.
function set_nudge(building_id, dx, dy)
    -- without the template the room is unknown: leave the chair's nudge as it is
    if not template then return get_nudge(building_id) end
    dx, dy = clamp_nudge(get_facing(building_id), dx, dy)
    local moved = dx ~= 0 or dy ~= 0
    nudge_of[building_id] = moved and {dx, dy} or nil
    local data = load_data()
    data[nudge_key(building_id)] = moved and {dx, dy} or nil
    save_data(data)
    return dx, dy
end

-- After a map load: read the saved facings and nudges, dropping entries whose chair is gone (and
-- anything else that is neither, such as the art-set choices earlier versions saved).
function restore()
    facing_of, nudge_of = {}, {}
    -- only a fortress owns its chairs; an adventurer visiting the site must not prune the table
    if not dfhack.isMapLoaded() or not dfhack.world.isFortressMode() then return end
    local data = load_data()
    local dirty = false
    -- Only data older than this format is converted; data from a newer one is left alone.
    local old_origin = (tonumber(data[FORMAT_KEY]) or 0) < FORMAT
    if old_origin then dirty = true end
    local nudges = {}
    for key, value in pairs(data) do
        if key == FORMAT_KEY then goto continue end
        local id = tostring(key):match('^%d+$') and tonumber(key)
        local b = id and df.building.find(id)
        if b and b._type == df.building_chairst and type(value) == 'number'
                and value >= NORTH and value <= WEST and value ~= DEFAULT then
            facing_of[b.id] = math.floor(value)
        elseif tostring(key):match('^%d+:nudge$') then
            nudges[key] = value
        else
            data[key] = nil
            dirty = true
        end
        ::continue::
    end
    -- nudges after facings: the room a nudge has depends on the facing.  Without the template the
    -- room is unknown, so the saved nudges are left alone for the next load.
    if not template then nudges = {}; if old_origin then return end end
    for key, value in pairs(nudges) do
        local id = tonumber(key:match('^%d+'))
        local facing = get_facing(id)
        local b = df.building.find(id)
        local dx, dy = 0, 0
        if b and b._type == df.building_chairst and type(value) == 'table' and type(value[1]) == 'number' and type(value[2]) == 'number' then
            dx, dy = value[1], value[2]
            -- a nudge saved from the template position: keep the chair where it was drawn
            if old_origin then dx, dy = dx - HOME[facing][1], dy - HOME[facing][2] end
            dx, dy = clamp_nudge(facing, dx, dy)
        end
        if dx ~= 0 or dy ~= 0 then
            nudge_of[id] = {dx, dy}
            if dx ~= value[1] or dy ~= value[2] then data[key] = {dx, dy}; dirty = true end
        else
            data[key] = nil
            dirty = true
        end
    end
    if dirty then data[FORMAT_KEY] = FORMAT; save_data(data) end
end

dfhack.onStateChange[SITE_KEY] = function(event)
    if event == SC_MAP_LOADED then
        restore()
    elseif event == SC_WORLD_UNLOADED then
        -- building ids, materials and colour indexes are per world
        facing_of, nudge_of, tint_of_material, tile_handles = {}, {}, {}, {}
    end
end

-- The overlay plugin loads this module at startup, before any map; restore() then finds no map
-- and the state-change hook does the work.  When the module is (re)loaded with a map already
-- up, restore now.
restore()

-- ---- the map ------------------------------------------------------------------------------------
--
-- The game draws the map into the viewport's layers of texture numbers, one cell per map tile; a
-- chair's picture is in the building layer (screentexpos_building_one).  Each frame, after the
-- game has filled the layers and before they reach the screen, the cell of every finished chair
-- in view is given this mod's tile instead.  Only cells the game put a building picture in are
-- touched, so a chair the game does not show (unrevealed, say) stays unshown.  Creatures and
-- items are other layers, drawn over this one as before.

-- The tile for a chair as it stands: its facing, resting offset and nudge, held to what its
-- material's picture has room for so it never leaves the tile.
local function chair_texpos(b)
    local facing = facing_of[b.id] or DEFAULT
    local tint = chair_tint(b)
    local dx, dy = HOME[facing][1], HOME[facing][2]
    local n = nudge_of[b.id]
    if n then dx, dy = dx + n[1], dy + n[2] end
    local room = room_of[(tint >> 1 & 3) * FACINGS + facing + 1]
    dx = math.max(-room[WEST], math.min(room[EAST], dx))
    dy = math.max(-room[NORTH], math.min(room[SOUTH], dy))
    return tile_texpos(tint, facing, dx, dy)
end

-- The game draws the level in view into main_viewport and, where the floor is open, up to
-- eight levels below it into lower_viewport[0..7] (0 = one level down).
local LOWER_LEVELS = 8

local function draw_chair(b, main, lower, wx, wy, wz)
    local depth = wz - b.z
    local vp = main
    if depth ~= 0 then vp = depth >= 1 and depth <= LOWER_LEVELS and lower[depth - 1] or nil end
    if not vp then return end
    local dim_x, dim_y = vp.dim_x, vp.dim_y
    local sx, sy = b.centerx - wx, b.centery - wy
    if sx < 0 or sx >= dim_x or sy < 0 or sy >= dim_y then return end
    local cells = vp.screentexpos_building_one
    local cell = sx * dim_y + sy
    -- a chair still being built is drawn by the game as a construction site
    if cells[cell] ~= 0 and b:getBuildStage() >= b:getMaxBuildStage() then
        local texpos = chair_texpos(b)
        if texpos then
            cells[cell] = texpos
            STATS.cells = STATS.cells + 1
        end
    end
end

-- A chair that cannot be drawn keeps the game's picture and does not stop the others; the
-- first error of the frame is passed on once every chair has had its turn.
local function draw_chairs()
    if not template then return end
    local gps = df.global.gps
    local main, lower = gps.main_viewport, gps.lower_viewport
    local wx, wy, wz = df.global.window_x, df.global.window_y, df.global.window_z
    local first_err
    for _, b in ipairs(df.global.world.buildings.other.CHAIR) do
        local ok, err = pcall(draw_chair, b, main, lower, wx, wy, wz)
        if not ok and not first_err then first_err = err end
    end
    if first_err then error(first_err, 0) end
end

ImprovedChairsMapOverlay = defclass(ImprovedChairsMapOverlay, overlay.OverlayWidget)
ImprovedChairsMapOverlay.ATTRS{
    desc='Draws chairs from the New and Improved Chairs art, turned and nudged as set on their sheets.',
    default_enabled=true,
    viewscreens='dwarfmode',
    frame={w=0, h=0},
}

local draw_failed = false

function ImprovedChairsMapOverlay:onRenderFrame(dc, rect)
    ImprovedChairsMapOverlay.super.onRenderFrame(self, dc, rect)
    STATS.frames = STATS.frames + 1
    local ok, err = pcall(draw_chairs)
    -- say so once, not sixty times a second
    if not ok and not draw_failed then
        draw_failed = true
        dfhack.printerr('improved-chairs: drawing failed: ' .. tostring(err))
    end
end

-- Texpos of the picture of this chair with the given facing, where the art draws it (no resting
-- offset, no nudge), for showing the chair outside the map (the view sheet's icons).
local function icon_texpos(b, facing)
    if not template then return nil end
    return tile_texpos(chair_tint(b), facing, 0, 0)
end

-- ---- the sheet control ----------------------------------------------------------------------
--
-- The controls sit after the chair's name in the view sheet title:
--
--   Granite Throne  @ <^v> x
--
-- "@" is the turn button, a circle with an arrow. Clicking it turns the chair a quarter:
-- south (where every chair starts) -> west -> north -> east.
--
-- Then four small triangles. Each click moves the chair's picture one pixel
-- that way inside its tile; a triangle goes dim when the picture has reached the edge of the
-- tile. Once the chair has been moved an "x" appears that puts it back.
--
-- Every control is one interface cell drawn from CONTROLS (art/make_controls.py), with a blank
-- cell after the turn button and before the "x".
--
-- The widget redraws the title from its first character, so what the game wrote there is
-- covered. The sheet is a fixed width anchored to the right edge of the screen and the title
-- always starts 90 columns from that edge, so the widget is anchored there. (A negative overlay
-- x anchors the widget's right edge: x = -(r + 1) where r is the gap to the screen edge.)

-- nudge buttons in the order drawn: fallback glyph (CP437 triangles), pixel step, direction for get_room
local NUDGES = {
    {glyph=string.char(17), dx=-1, dy=0, dir=WEST},
    {glyph=string.char(30), dx=0, dy=-1, dir=NORTH},
    {glyph=string.char(31), dx=0, dy=1, dir=SOUTH},
    {glyph=string.char(16), dx=1, dy=0, dir=EAST},
}
local PEN_OFF  = dfhack.pen.parse{fg=COLOR_DARKGREY, bg=COLOR_BLACK}
local PEN_LIT  = dfhack.pen.parse{fg=COLOR_LIGHTGREEN, bg=COLOR_BLACK}
local PEN_RESET = dfhack.pen.parse{fg=COLOR_LIGHTRED, bg=COLOR_BLACK}
local PEN_NAME = dfhack.pen.parse{fg=COLOR_WHITE, bg=COLOR_BLACK}
local TITLE_COL = 90      -- first character of the title is this many columns from the right edge
local MAX_TITLE = 60
local GAP = 2             -- blank columns between the name and the controls
local NUDGE_AT = 2                          -- nudge buttons, counted from the turn button's column
local RESET_AT = NUDGE_AT + #NUDGES + 1     -- the "x"
local WIDTH = MAX_TITLE + GAP + RESET_AT + 1

-- The controls' art: 8x12 interface cells in a row, 1 turn, 2-5 nudges lit, 6-9 nudges dim,
-- 10 reset.  Without the file (or in a text-mode game) the controls fall back to characters.
local CONTROLS = DATA .. 'chair_controls.png'
local TURN_CELL, LIT_CELL, DIM_CELL, RESET_CELL = 1, 1, 5, 10    -- nudge i is LIT_CELL + i or DIM_CELL + i
local control_handles = dfhack.textures.loadTileset(CONTROLS, 8, 12, true)

local function control_pen(cell, ch, fallback)
    local texpos = control_handles and control_handles[cell] and dfhack.textures.getTexposByHandle(control_handles[cell])
    if texpos and texpos > 0 then
        return dfhack.pen.parse{tile=texpos, ch=ch, fg=fallback.fg, bg=COLOR_BLACK}
    end
    return fallback
end

local function selected_chair()
    local b = dfhack.gui.getSelectedBuilding(true)
    if b and b._type == df.building_chairst then return b end
end

-- the name, capitalised as the title shows it
local function base_name(b)
    local str = df.new('string')
    b:getName(str)
    local name = str.value
    df.delete(str)
    return name:sub(1, 1):upper() .. name:sub(2, MAX_TITLE)
end

-- Whether a chair with this facing and nudge can still move one step the way of NUDGES[i].
local function can_nudge(facing, dx, dy, i)
    local n = NUDGES[i]
    local ndx, ndy = clamp_nudge(facing, dx + n.dx, dy + n.dy)
    return ndx ~= dx or ndy ~= dy
end

ImprovedChairsOverlay = defclass(ImprovedChairsOverlay, overlay.OverlayWidget)
ImprovedChairsOverlay.ATTRS{
    desc='Puts turn and nudge controls in the title of chair view sheets (cosmetic).',
    default_pos={x=-(TITLE_COL - WIDTH + 1), y=7},
    version=8,
    default_enabled=true,
    viewscreens='dwarfmode/ViewSheets/BUILDING/Chair',
    frame={w=WIDTH, h=1},
}

function ImprovedChairsOverlay:init()
    self.facing = DEFAULT
    self.name = ''
    self.dx, self.dy = 0, 0
end

-- column of the first control for the name now shown
function ImprovedChairsOverlay:controls_col()
    return #self.name + GAP
end

function ImprovedChairsOverlay:cycle(b)
    local cur = get_facing(b.id)
    set_facing(b.id, (cur + 1) % 4)
end

function ImprovedChairsOverlay:onInput(keys)
    if keys._MOUSE_L then
        local x, y = self:getMousePos()
        local b = x and y == 0 and selected_chair()
        if b then
            local facing = get_facing(b.id)
            local c = x - self:controls_col()      -- 0 = first control column
            local i = c - NUDGE_AT + 1
            if c == 0 then
                self:cycle(b)
                return true
            elseif NUDGES[i] then
                local dx, dy = get_nudge(b.id)
                set_nudge(b.id, dx + NUDGES[i].dx, dy + NUDGES[i].dy)
                return true
            elseif c == RESET_AT then
                local dx, dy = get_nudge(b.id)
                if dx ~= 0 or dy ~= 0 then
                    set_nudge(b.id, 0, 0)
                    return true
                end
            end
        end
    end
    return ImprovedChairsOverlay.super.onInput(self, keys)
end

function ImprovedChairsOverlay:onRenderBody(dc)
    local col = self:controls_col()
    -- the name, then blanks under the controls
    dc:seek(0, 0):string(self.name, PEN_NAME):string((' '):rep(GAP + RESET_AT + 1), PEN_NAME)
    dc:seek(col, 0):char('o', control_pen(TURN_CELL, 'o', PEN_LIT))
    dc:seek(col + NUDGE_AT, 0)
    for i, n in ipairs(NUDGES) do
        if can_nudge(self.facing, self.dx, self.dy, i) then
            dc:char(n.glyph, control_pen(LIT_CELL + i, n.glyph, PEN_LIT))
        else
            dc:char(n.glyph, control_pen(DIM_CELL + i, n.glyph, PEN_OFF))
        end
    end
    if self.dx ~= 0 or self.dy ~= 0 then
        dc:seek(col + RESET_AT, 0):char('x', control_pen(RESET_CELL, 'x', PEN_RESET))
    end
end

-- The sheet shows two pictures of the chair: the building's icon left of the title and, on the
-- Items tab, the icon of the chair item it was built from.  The game draws each as one map-size
-- tile anchored over a block of ICON_W x ICON_H interface cells (gps.screentexpos_anchored), the
-- title's block ending ICON_GAP cells before the name.  Putting our tile's texpos in those cells
-- swaps the picture and leaves the placement to the game.  Only cells the game filled are
-- touched, so a sheet laid out some other way is left as it is.
local ICON_W, ICON_H, ICON_GAP = 5, 3, 2

-- Swap the icon whose top left cell is (x, y); false if the game drew no icon there.
local function swap_icon(x, y, texpos)
    local g = df.global.gps
    if x < 0 or y < 0 or x + ICON_W > g.dimx or y + ICON_H > g.dimy then return false end
    for cx = x, x + ICON_W - 1 do
        for cy = y, y + ICON_H - 1 do
            if g.screentexpos_anchored[cx * g.dimy + cy] == 0 then return false end
        end
    end
    for cx = x, x + ICON_W - 1 do
        for cy = y, y + ICON_H - 1 do
            g.screentexpos_anchored[cx * g.dimy + cy] = texpos
        end
    end
    return true
end

local function swap_icons(b, facing, name_x, name_y)
    local x, y = name_x - ICON_GAP - ICON_W, name_y - 1
    -- the building's icon shows the chair as it stands; the item's shows it from the front
    local texpos = icon_texpos(b, facing)
    if not texpos or not swap_icon(x, y, texpos) then return end
    -- the item list: a built chair holds just the chair, so the first icon below is its
    if #b.contained_items ~= 1 or b.contained_items[0].item:getType() ~= df.item_type.CHAIR then return end
    if not dfhack.gui.matchFocusString('dwarfmode/ViewSheets/BUILDING/Chair/Items') then return end
    texpos = icon_texpos(b, DEFAULT)
    if not texpos then return end
    local g = df.global.gps
    for cy = y + ICON_H, g.dimy - ICON_H do
        if g.screentexpos_anchored[x * g.dimy + cy] ~= 0 then
            swap_icon(x, cy, texpos)
            return
        end
    end
end

function ImprovedChairsOverlay:render(dc)
    local b = selected_chair()
    if not b then return end
    self.facing = get_facing(b.id)
    self.name = base_name(b)
    self.dx, self.dy = get_nudge(b.id)
    ImprovedChairsOverlay.super.render(self, dc)
    -- a chair still being built is drawn by the game on the map, so in the sheet too
    if b:getBuildStage() >= b:getMaxBuildStage() then
        swap_icons(b, self.facing, self.frame_body.x1, self.frame_body.y1)
    end
end

OVERLAY_WIDGETS = { sheet = ImprovedChairsOverlay, map = ImprovedChairsMapOverlay }

-- For test/run_tests.lua only.
internal = {tile_room=tile_room, tone=tone, paint_pixel=paint_pixel, paint_tile=paint_tile,
            clamp_nudge=clamp_nudge, draw_chairs=draw_chairs, HOME=HOME}

-- ---- command line ---------------------------------------------------------------------------
--
--   improved-chairs reload     read the art again and repaint every chair (for working on the art)
--   improved-chairs status     what the map overlay has drawn so far

if not dfhack_flags.module then
    local args = {...}
    if args[1] == 'reload' and not args[2] then
        if not load_template() then qerror('improved-chairs: could not read ' .. DATA .. 'template.lua') end
        tile_handles = {}
        print('improved-chairs: reloaded ' .. DATA .. 'template.lua')
    elseif args[1] == 'status' and not args[2] then
        local facings, nudges = 0, 0
        for _ in pairs(facing_of) do facings = facings + 1 end
        for _ in pairs(nudge_of) do nudges = nudges + 1 end
        print(('improved-chairs: template %s, %d frames, %d chair cells drawn, %d tiles painted, %d turned, %d nudged')
            :format(template and 'loaded' or 'MISSING', STATS.frames, STATS.cells, STATS.tiles, facings, nudges))
    else
        qerror('usage: improved-chairs reload | status')
    end
end
