-- Tests for scripts/improved-chairs.lua with DFHack and the game stubbed.
--   lua test/run_tests.lua [path to the script]
local here = arg[0]:match('^(.*)/[^/]*$') or '.'
local SCRIPT = arg[1] or (here .. '/../scripts/improved-chairs.lua')

local failures, count = 0, 0
local function check(name, cond, detail)
    count = count + 1
    if not cond then
        failures = failures + 1
        print('FAIL ' .. name .. (detail and (': ' .. tostring(detail)) or ''))
    end
end
local function eq(name, got, want) check(name, got == want, ('got %s, want %s'):format(tostring(got), tostring(want))) end

-- ---- stubs --------------------------------------------------------------------------------------
local CHAIR_TYPE = {}
local function anything()
    local t = {}
    return setmetatable(t, {__index=function() return anything() end, __call=function() return anything() end})
end
local function zeros(n) local t = {}; for i = 0, n - 1 do t[i] = 0 end; return t end
-- a 0-based vector with a length, like the game's
local function vec(list) local t = {}; for i, v in ipairs(list) do t[i - 1] = v end; return setmetatable(t, {__len=function() return #list end}) end
local function viewport(dim_x, dim_y) return {dim_x=dim_x, dim_y=dim_y, screentexpos_building_one=zeros(dim_x * dim_y)} end

-- the game's default palette: shade i of ramp 0 is grey 10*i, of ramp 1 grey 100+10*i
local palette = {}
for ramp = 0, 1 do for i = 0, 8 do for c = 0, 2 do palette[ramp * 27 + i * 3 + c] = ramp * 100 + i * 10 + c end end end

local function new_world()
    local w = {site={}, buildings={}, chairs={}, saves=0, map_loaded=true, fortress=true, next_handle=0}
    w.gps = {main_viewport=viewport(25, 17), lower_viewport={}, default_palette={color=palette}}
    for i = 0, 7 do w.gps.lower_viewport[i] = viewport(25, 17) end
    return w
end
local W

local function chair(id, x, y, z, opts)
    opts = opts or {}
    local b = {id=id, centerx=x, centery=y, z=z, _type=CHAIR_TYPE, contained_items={}}
    function b:getBuildStage() return opts.unfinished and 0 or 1 end
    function b:getMaxBuildStage() return 1 end
    if opts.mat then
        local item = {}
        function item:getMaterial() return opts.mat[1] end
        function item:getMaterialIndex() return opts.mat[2] end
        b.contained_items = vec{{item=item}}
    end
    if opts.broken then setmetatable(b.contained_items, {__len=function() error('broken chair') end}) end
    W.buildings[id] = b
    W.chairs[#W.chairs + 1] = b
    return b
end

local function load_script()
    local function copy(v) if type(v) ~= 'table' then return v end; local t = {}; for k, x in pairs(v) do t[k] = copy(x) end; return t end
    -- globals DFHack provides that the tests do not care about (pens, colours, ...)
    local env = setmetatable({}, {__index=function(_, key) local v = _G[key]; if v ~= nil then return v end; if key:find('^COLOR_') then return 0 end end})
    env.dfhack_flags = {module=true}
    env.SC_MAP_LOADED, env.SC_WORLD_UNLOADED = 1, 2
    env.require = function() return anything() end
    env.defclass = function() return anything() end
    env.dfhack = {
        onStateChange={},
        printerr=function() end,
        findScript=function() return SCRIPT end,
        isMapLoaded=function() return W.map_loaded end,
        world={isFortressMode=function() return W.fortress end},
        matinfo={decode=function(t, i) return W.materials and W.materials[t .. ':' .. i] or nil end},
        persistent={
            getSiteData=function(key, default)
                if W.no_site then return default end
                local d = W.site[key]
                if d == 'UNDECODABLE' then error('json: unexpected end of input') end
                if d == nil then return default end
                return copy(d)
            end,
            saveSiteData=function(key, data)
                if W.no_site or W.no_save then error("unable to save data in key '" .. key .. "'") end
                W.site[key] = copy(data); W.saves = W.saves + 1
            end,
        },
        textures=setmetatable({
            createTile=function(px) W.next_handle = W.next_handle + 1; W.last_pixels = px; return W.next_handle end,
            getTexposByHandle=function(h) return 1000 + h end,
        }, {__index=function() return anything() end}),
    }
    setmetatable(env.dfhack, {__index=function() return anything() end})
    env.df = {
        building_chairst=CHAIR_TYPE,
        building={find=function(id)   -- like the game: integers only, and only 32 bits of them
            if math.type(id) ~= 'integer' then error('integer expected') end
            return W.buildings[id & 0xffffffff]
        end},
        global=setmetatable({}, {__index=function(_, k)
            if k == 'gps' then return W.gps end
            if k == 'world' then return {buildings={other={CHAIR=W.chairs}}, raws={descriptors=W.descriptors or {colors={}, patterns={}}}} end
            return W[k]
        end}),
    }
    local chunk = assert(loadfile(SCRIPT, 't', env))
    chunk()
    return env
end

local N, E, S, Wd = 0, 1, 2, 3

-- ---- the room a picture has ---------------------------------------------------------------------
W = new_world()
local m = load_script()
local I = m.internal
do
    local px = {}
    for i = 1, 1024 do px[i] = 0 end
    local r = I.tile_room(px)
    check('empty tile has no room', r[N] == 0 and r[E] == 0 and r[S] == 0 and r[Wd] == 0)
    px[7 * 32 + 5 + 1] = 0x000000ff
    r = I.tile_room(px)
    check('one pixel at (5,7)', r[N] == 7 and r[Wd] == 5 and r[E] == 26 and r[S] == 24, ('%d %d %d %d'):format(r[N], r[E], r[S], r[Wd]))
    px[20 * 32 + 30 + 1] = 0x00000001   -- barely visible still counts
    r = I.tile_room(px)
    check('two pixels', r[N] == 7 and r[Wd] == 5 and r[E] == 1 and r[S] == 11)
end

-- measured in the game with the released art
do
    local dx, dy = I.clamp_nudge(Wd, 40, -40); check('west chair clamp +', dx == 13 and dy == 0, dx .. ',' .. dy)
    dx, dy = I.clamp_nudge(Wd, -40, 40); check('west chair clamp -', dx == -5 and dy == 4, dx .. ',' .. dy)
    dx, dy = I.clamp_nudge(S, 0, -40); eq('south chair goes up 1', dy, -1)
    dx, dy = I.clamp_nudge(S, 0, 40); eq('south chair goes down 1', dy, 1)
    dx, dy = I.clamp_nudge(E, 0, -40); eq('east chair does not go up', dy, 0)
    dx, dy = I.clamp_nudge(S, 0.9, 0.9); check('fractions are floored', dx == 0 and dy == 0)
    eq('room for a bad facing', m.get_room(7, N), 0)
end

-- ---- painting -----------------------------------------------------------------------------------
do
    local function rgb(c) return c & 0xff, c >> 8 & 0xff, c >> 16 & 0xff, c >> 24 end
    local r, g, b, a = rgb(I.tone(palette, 0, 1))
    check('tone 1 is shade 2', r == 20 and g == 21 and b == 22 and a == 255, r .. ' ' .. g .. ' ' .. b)
    r, g, b = rgb(I.tone(palette, 0, 255))
    check('tone 255 is shade 8', r == 80 and g == 81 and b == 82, r .. ' ' .. g .. ' ' .. b)
    r = rgb(I.tone(palette, 27, 1)); eq('second ramp', r, 120)
    local last = -1
    for t = 1, 255 do
        local v = rgb(I.tone(palette, 0, t))
        if v < last then check('tone is monotonic', false, t) end
        last = v
    end
    r = rgb(I.tone(palette, 0, 128)); eq('tone 128 is shade 5', r, 50)
    -- a ramp that runs downhill rounds like one that runs uphill (floor, not truncation)
    local down = {}
    for i = 0, 8 do for c = 0, 2 do down[i * 3 + c] = 200 - i * 7 end end
    r = rgb(I.tone(down, 0, 100)); eq('downhill tone floors', r, 169)

    eq('transparent pixel', I.paint_pixel(0x12345600, palette, 27), 0)
    eq('own-ramp marker', I.paint_pixel(0x010000ff, palette, 27), I.tone(palette, 27, 1))
    eq('first-ramp marker', I.paint_pixel(0x0000ffff, palette, 27), I.tone(palette, 0, 255))
    eq('plain pixel is copied', I.paint_pixel(0x102030ff, palette, 27), 0xff000000 | 0x30 << 16 | 0x20 << 8 | 0x10)
    eq('marker needs full alpha', I.paint_pixel(0x80000080, palette, 27), 0x80 << 24 | (0x80 * 0x80 // 255))
    eq('see-through pixel is premultiplied', I.paint_pixel(0xff804080, palette, 27), 0x80 << 24 | (0x40 * 128 // 255) << 16 | (0x80 * 128 // 255) << 8 | 128)

    local base = I.paint_tile(2, S, 0, 0)
    eq('painted tile size', #base, 1024)
    local solid = 0
    for i = 1, 1024 do if base[i] ~= 0 then solid = solid + 1 end end
    check('painted tile is not empty', solid > 100, solid)
    local ok_shift = true
    local moved = I.paint_tile(2, S, 3, -2)
    for y = 0, 31 do for x = 0, 31 do
        local sx, sy = x - 3, y + 2
        local want = (sx >= 0 and sx < 32 and sy >= 0 and sy < 32) and base[sy * 32 + sx + 1] or 0
        if moved[y * 32 + x + 1] ~= want then ok_shift = false end
    end end
    check('a moved tile is the same tile, moved (+x east, +y south)', ok_shift)
    eq('no palette, no tile', I.paint_tile(8 * 5 + 2, S, 0, 0), nil)
    local wood, stone = I.paint_tile(1, S, 0, 0), I.paint_tile(2, S, 0, 0)
    local differ = false
    for i = 1, 1024 do if wood[i] ~= stone[i] then differ = true end end
    check('wood and stone are painted differently', differ)
    -- same picture, other ramp: wood (odd key) uses the first ramp, everything else the second,
    -- which the stub palette makes exactly 100 lighter
    local first, second, n = I.paint_tile(1, S, 0, 0), I.paint_tile(0, S, 0, 0), 0
    local ramps_ok = true
    for i = 1, 1024 do
        if first[i] ~= second[i] then
            n = n + 1
            if (second[i] & 0xff) - (first[i] & 0xff) ~= 100 then ramps_ok = false end
        end
    end
    check('wood is painted with the first ramp, the rest with the second', n > 50 and ramps_ok, n)
end

-- ---- facings, nudges and the save ---------------------------------------------------------------
do
    W = new_world(); chair(1, 5, 5, 10); chair(2, 6, 5, 10)
    m = load_script()
    eq('default facing', m.get_facing(1), S)
    m.set_facing(1, Wd)
    eq('facing set', m.get_facing(1), Wd)
    eq('facing saved', W.site['improved-chairs']['1'], Wd)
    local dx, dy = m.set_nudge(1, 40, 40)
    check('nudge clamped', dx == 13 and dy == 4, dx .. ',' .. dy)
    check('nudge saved', W.site['improved-chairs']['1:nudge'][1] == 13 and W.site['improved-chairs']['1:nudge'][2] == 4)
    m.set_facing(1, N)
    dx, dy = m.get_nudge(1); check('turning drops the nudge', dx == 0 and dy == 0)
    eq('turning drops the saved nudge', W.site['improved-chairs']['1:nudge'], nil)
    m.set_facing(1, S)
    eq('south is not stored', W.site['improved-chairs']['1'], nil)
    m.set_facing(1, 99); eq('bad facing means default', m.get_facing(1), S)
    m.set_nudge(2, 0, 1); m.set_nudge(2, 0, 0)
    eq('zero nudge is not stored', W.site['improved-chairs']['2:nudge'], nil)
end

do  -- reading a save in the current format
    W = new_world(); chair(1, 5, 5, 10); chair(2, 6, 5, 10)
    W.buildings[3] = {id=3, _type={}}      -- not a chair
    W.site['improved-chairs'] = {format=2, ['1']=Wd, ['1:nudge']={2, 1}, ['2:nudge']={0, 1}, ['3']=N, ['9']=E, ['9:nudge']={1, 1}, junk='x', ['2']=7}
    m = load_script()
    eq('facing restored', m.get_facing(1), Wd)
    local dx, dy = m.get_nudge(1); check('nudge restored as saved', dx == 2 and dy == 1, dx .. ',' .. dy)
    dx, dy = m.get_nudge(2); check('nudge of an unturned chair', dx == 0 and dy == 1)
    local d = W.site['improved-chairs']
    check('gone chair, non-chair and junk are dropped', d['9'] == nil and d['9:nudge'] == nil and d['3'] == nil and d.junk == nil and d['2'] == nil)
    eq('format kept', d.format, 2)
    -- a second load changes nothing and does not save
    local saves = W.saves
    m.restore()
    eq('clean data is not saved again', W.saves, saves)
    dx, dy = m.get_nudge(1); check('nudge stable over loads', dx == 2 and dy == 1)
end

do  -- a save from before nudges counted from the resting position, under the old name
    W = new_world(); chair(1, 5, 5, 10); chair(2, 6, 5, 10)
    W.site['chair-facing'] = {['1']=E, ['1:nudge']={5, -2}, ['2:nudge']={0, 1}}
    m = load_script()
    eq('old name: facing', m.get_facing(1), E)
    local dx, dy = m.get_nudge(1)
    check('old origin converted: same place on screen', dx == 5 - I.HOME[E][1] and dy == -2 - I.HOME[E][2], dx .. ',' .. dy)
    dx, dy = m.get_nudge(2); check('south chair unchanged by conversion', dx == 0 and dy == 1)
    local d = W.site['improved-chairs']
    check('saved under the new name in format 2', d and d.format == 2 and d['1:nudge'][1] == 2 and d['1:nudge'][2] == 0)
end

do  -- an adventurer's visit, and no map
    W = new_world(); W.fortress = false
    W.site['improved-chairs'] = {format=2, ['9']=E}
    m = load_script()
    eq('adventure mode leaves the data alone', W.site['improved-chairs']['9'], E)
    eq('adventure mode does not save', W.saves, 0)
    W = new_world(); W.map_loaded = false
    m = load_script(); eq('no map, no save', W.saves, 0)
end

-- ---- the map ------------------------------------------------------------------------------------
do
    W = new_world(); W.window_x, W.window_y, W.window_z = 100, 50, 10
    local main, lower = W.gps.main_viewport, W.gps.lower_viewport
    local function cell(x, y) return (x - 100) * 17 + (y - 50) end
    local function mark(vp, x, y) vp.screentexpos_building_one[cell(x, y)] = 7 end
    chair(1, 103, 52, 10); mark(main, 103, 52)                      -- in view
    chair(2, 104, 52, 10)                                           -- the game drew nothing there
    chair(3, 105, 52, 10, {unfinished=true}); mark(main, 105, 52)   -- still being built
    chair(4, 106, 52, 9); mark(lower[0], 106, 52); mark(main, 106, 52)   -- one level down
    chair(5, 107, 52, 2); mark(lower[7], 107, 52)                   -- eight levels down
    chair(6, 108, 52, 1); mark(main, 108, 52)                       -- nine down: too deep
    chair(7, 109, 52, 11); mark(main, 109, 52)                      -- above the view
    chair(8, 99, 52, 10); chair(9, 125, 52, 10); chair(10, 103, 49, 10); chair(11, 103, 67, 10)   -- out of view
    chair(12, 124, 66, 10); mark(main, 124, 66)                     -- last cell
    chair(13, 100, 50, 10); mark(main, 100, 50)                     -- first cell
    m = load_script(); I = m.internal
    m.set_facing(1, Wd)
    I.draw_chairs()
    local function got(vp, x, y) return vp.screentexpos_building_one[cell(x, y)] end
    check('chair in view is drawn', got(main, 103, 52) > 1000, got(main, 103, 52))
    eq('empty cell stays empty', got(main, 104, 52), 0)
    eq('unfinished chair is left alone', got(main, 105, 52), 7)
    check('chair one level down goes to lower_viewport[0]', got(lower[0], 106, 52) > 1000)
    eq('and not to the main viewport', got(main, 106, 52), 7)
    check('chair eight levels down goes to lower_viewport[7]', got(lower[7], 107, 52) > 1000)
    eq('nine levels down is left alone', got(main, 108, 52), 7)
    eq('a chair above is left alone', got(main, 109, 52), 7)
    check('corner cells', got(main, 124, 66) > 1000 and got(main, 100, 50) > 1000)
    local touched = 0
    for _, vp in ipairs{main, lower[0], lower[1], lower[2], lower[3], lower[4], lower[5], lower[6], lower[7]} do
        for i = 0, 25 * 17 - 1 do if vp.screentexpos_building_one[i] > 1000 then touched = touched + 1 end end
        for i in pairs(vp.screentexpos_building_one) do if i < 0 or i >= 25 * 17 then check('no write outside the layer', false, i) end end
    end
    eq('exactly the five drawable chairs were written', touched, 5)
    check('a turned chair gets another tile', got(main, 103, 52) ~= got(main, 100, 50))
    local tiles = W.next_handle
    I.draw_chairs()
    eq('tiles are painted once', W.next_handle, tiles)

    -- a wide, low viewport: the index is column * height + row
    W = new_world(); W.window_x, W.window_y, W.window_z = 0, 0, 10
    W.gps.main_viewport = viewport(40, 10)
    chair(1, 30, 3, 10); W.gps.main_viewport.screentexpos_building_one[30 * 10 + 3] = 7
    m = load_script(); m.internal.draw_chairs()
    check('index is column * dim_y + row', W.gps.main_viewport.screentexpos_building_one[30 * 10 + 3] > 1000)

    -- one chair that throws does not stop the ones after it, and the error is passed on
    W = new_world(); W.window_x, W.window_y, W.window_z = 0, 0, 10
    chair(1, 1, 1, 10, {broken=true}); chair(2, 2, 1, 10)
    W.gps.main_viewport.screentexpos_building_one[1 * 17 + 1] = 7
    W.gps.main_viewport.screentexpos_building_one[2 * 17 + 1] = 7
    m = load_script()
    local ok, err = pcall(m.internal.draw_chairs)
    check('the error is reported', not ok and tostring(err):find('broken chair'), err)
    eq('the broken chair keeps the game\'s picture', W.gps.main_viewport.screentexpos_building_one[1 * 17 + 1], 7)
    check('the chair after it is drawn', W.gps.main_viewport.screentexpos_building_one[2 * 17 + 1] > 1000)
end

-- ---- materials ----------------------------------------------------------------------------------
do
    local function material(flags, pattern) return {material={flags=flags, state_color={Solid=pattern}}} end
    local function descriptors()
        local shades = {}
        for i = 0, 53 do shades[i] = 200 - i end
        -- pattern 0 has no colour, pattern 1 is colour 2, pattern 2 is colour 0, pattern 3 names a colour that is not there
        return {colors=vec{{palette={color=palette}}, {palette={color=palette}}, {palette={color=shades}}},
                patterns=vec{{colors=vec{}}, {colors=vec{2}}, {colors=vec{0}}, {colors=vec{9}}}}
    end
    W = new_world(); W.window_x, W.window_y, W.window_z = 0, 0, 10
    W.descriptors = descriptors()
    W.materials = {['420:5']=material({WOOD=true}, 1), ['0:7']=material({IS_METAL=true, IS_STONE=true}, 2),
                   ['3:-1']=material({IS_GLASS=true, IS_METAL=true}, 0), ['0:8']=material({IS_STONE=true}, 3),
                   ['0:9']=material({}, -1), ['1:5']=material({IS_METAL=true}, 1)}
    m = load_script(); I = m.internal
    local wood = I.material_tint(420, 5)
    eq('wood key: colour 2, wood bit', wood & 1, 1); eq('wood key colour', wood // 8, 3)
    local metal = I.material_tint(0, 7)
    eq('colour 0 is key 8 and up, not the default palette', metal // 8, 1)
    eq('metal is not wood', metal & 1, 0)
    local glass = I.material_tint(3, -1)
    check('a pattern without colours gives the default palette', glass < 8, glass)
    check('glass wins over metal, metal over stone', (glass >> 1 & 3) ~= (metal >> 1 & 3) and (metal >> 1 & 3) ~= (I.material_tint(0, 8) >> 1 & 3))
    check('a colour that is not there gives the default palette', I.material_tint(0, 8) < 8)
    eq('no flags is stone', I.material_tint(0, 9), I.material_tint(0, 8))
    eq('unknown material is stone', I.material_tint(77, 77), I.material_tint(0, 8))
    eq('a chair with no item is stone', I.chair_tint({contained_items=vec{}}), I.material_tint(0, 8))

    local a = chair(1, 1, 1, 10, {mat={420, 5}})
    chair(2, 2, 1, 10, {mat={0, 7}}); chair(3, 3, 1, 10, {mat={420, 5}}); chair(4, 4, 1, 10, {mat={1, 5}})
    chair(5, 5, 1, 10, {mat={420, 5}}); chair(6, 6, 1, 10, {mat={420, 5}}); chair(7, 7, 1, 10, {mat={420, 5}})
    eq('chair takes the colour of its first item', I.chair_tint(a), wood)
    check('materials sharing an index or a type are told apart', I.chair_tint(W.buildings[4]) ~= wood and I.chair_tint(W.buildings[4]) ~= metal)
    eq('same type, other index: not the cached colour', I.chair_tint({contained_items=W.buildings[2].contained_items}) ~= nil and I.chair_tint(chair(8, 8, 1, 9, {mat={0, 8}})), I.material_tint(0, 8))
    local cells = W.gps.main_viewport.screentexpos_building_one
    for i = 0, 25 * 17 - 1 do cells[i] = 7 end
    m.set_nudge(5, 1, 0); m.set_nudge(6, 0, 1); m.set_nudge(7, 0, 40)
    I.draw_chairs()
    local function at(x) return cells[x * 17 + 1] end
    check('same material, same tile', at(1) == at(3) and at(1) > 1000)
    check('another material, another tile', at(2) ~= at(1) and at(4) ~= at(1) and at(4) ~= at(2))
    check('a chair moved sideways gets its own tile', at(5) ~= at(1))
    check('a chair moved down gets its own tile', at(6) ~= at(1) and at(6) ~= at(5))
    eq('a move past the edge stops at the edge', at(7), at(6))
    local changed = 0
    for i = 0, 25 * 17 - 1 do if cells[i] ~= 7 then changed = changed + 1 end end
    eq('only the seven chairs changed', changed, 7)

    -- the picture really is painted from the material's colour
    local dark = I.paint_tile(wood, S, 0, 0)
    local light = I.paint_tile(wood - 16, S, 0, 0)     -- same class, colour 0
    local differs = false
    for i = 1, 1024 do if dark[i] ~= light[i] then differs = true end end
    check('another colour, another picture', differs)
end

-- ---- the edges of the layers --------------------------------------------------------------------
do
    -- chairs just outside the view, every cell filled: nothing may change
    W = new_world(); W.window_x, W.window_y, W.window_z = 100, 50, 10
    local cells = W.gps.main_viewport.screentexpos_building_one
    for i = 0, 25 * 17 - 1 do cells[i] = 7 end
    chair(1, 103, 49, 10); chair(2, 103, 67, 10); chair(3, 99, 52, 10); chair(4, 125, 52, 10)
    chair(5, 100, 49, 10); chair(6, 124, 67, 10)
    m = load_script(); m.internal.draw_chairs()
    local changed = 0
    for i, v in pairs(cells) do if v ~= 7 or i < 0 or i >= 25 * 17 then changed = changed + 1 end end
    eq('a chair one tile outside the view changes nothing', changed, 0)

    -- a lower layer with its own size
    W = new_world(); W.window_x, W.window_y, W.window_z = 0, 0, 10
    W.gps.lower_viewport[0] = viewport(40, 10)
    W.gps.lower_viewport[0].screentexpos_building_one[30 * 10 + 3] = 7
    chair(1, 30, 3, 9)
    m = load_script(); m.internal.draw_chairs()
    check('a lower layer is indexed by its own size', W.gps.lower_viewport[0].screentexpos_building_one[30 * 10 + 3] > 1000)

    -- layers that are missing or not filled
    W = new_world(); W.window_x, W.window_y, W.window_z = 0, 0, 10
    W.gps.lower_viewport[0] = nil
    W.gps.lower_viewport[1].screentexpos_building_one = nil
    chair(1, 1, 1, 9); chair(2, 1, 1, 8); chair(3, 2, 1, 10)
    W.gps.main_viewport.screentexpos_building_one[2 * 17 + 1] = 7
    m = load_script()
    local ok, err = pcall(m.internal.draw_chairs)
    check('missing layers are skipped quietly', ok, err)
    check('and the rest is drawn', W.gps.main_viewport.screentexpos_building_one[2 * 17 + 1] > 1000)
end

-- ---- saves that cannot be trusted or cannot be made ----------------------------------------------
do  -- a reclaimed fortress: DFHack has no site to save to until the game's first save
    W = new_world(); chair(1, 5, 5, 10); chair(2, 6, 5, 10)
    W.no_site = true
    local ok, err = pcall(function() m = load_script() end)
    check('loading with no site does not fail', ok, err)
    I = m.internal
    ok, err = pcall(function() m.set_facing(1, Wd); m.set_nudge(1, 2, 0) end)
    check('turning and nudging with no site does not fail', ok, err)
    eq('the chair is turned meanwhile', m.get_facing(1), Wd)
    check('a save is owed', I.save_pending())
    I.retry_save(); check('still owed while there is no site', I.save_pending())
    W.no_site = false
    I.retry_save()
    local d = W.site['improved-chairs']
    check('saved once the site exists, with the format', d and d.format == 2 and d['1'] == Wd and d['1:nudge'][1] == 2, d and d.format)
    check('nothing owed any more', not I.save_pending())
    m.restore()
    local dx, dy = m.get_nudge(1)
    check('and it reads back the same', m.get_facing(1) == Wd and dx == 2 and dy == 0, dx .. ',' .. dy)
end

do  -- the site's own data turns up after a refused save: this session's changes go on top
    W = new_world(); chair(1, 5, 5, 10); chair(2, 6, 5, 10); chair(3, 7, 5, 10)
    W.site['improved-chairs'] = {format=2, ['1']=E, ['2']=N, ['2:nudge']={1, 1}}
    W.no_site = true
    m = load_script(); I = m.internal
    m.set_facing(1, Wd); m.set_nudge(3, 0, 1)
    W.no_site = false
    I.retry_save()
    local d = W.site['improved-chairs']
    check('changed chair wins', m.get_facing(1) == Wd and d['1'] == Wd)
    check('untouched chair keeps its saved state', m.get_facing(2) == N and d['2'] == N and d['2:nudge'][1] == 1)
    check('new nudge kept', d['3:nudge'] and d['3:nudge'][2] == 1)
end

do  -- `improved-chairs status` runs the file again in the same environment: owed changes survive
    W = new_world(); chair(1, 5, 5, 10); chair(2, 6, 5, 10)
    W.no_site = true
    m = load_script()
    m.set_facing(1, Wd); m.set_nudge(2, 0, 1)
    assert(loadfile(SCRIPT, 't', m))()
    I = m.internal
    local dx, dy = m.get_nudge(2)
    check('owed changes survive the file being run again', m.get_facing(1) == Wd and dy == 1 and I.save_pending())
    W.no_site = false
    I.retry_save()
    local d = W.site['improved-chairs']
    check('and are saved in the end', d and d['1'] == Wd and d['2:nudge'][2] == 1)
    assert(loadfile(SCRIPT, 't', m))()
    check('nothing is carried once saved', m.get_facing(1) == Wd and not m.internal.save_pending())
end

do  -- the data turns up but the save is refused once more: the changes are still owed
    W = new_world(); chair(1, 5, 5, 10); chair(2, 6, 5, 10)
    W.no_site = true
    m = load_script(); I = m.internal
    m.set_facing(1, Wd)
    W.no_site = false; W.no_save = true
    W.site['improved-chairs'] = {format=2, ['1']=E, ['2']=N}
    I.retry_save()
    check('still owed', I.save_pending())
    W.site['improved-chairs'] = {format=2, ['1']=E, ['2']=E}
    W.no_save = false
    I.retry_save()
    local d = W.site['improved-chairs']
    check('the change survives a second refusal', m.get_facing(1) == Wd and d['1'] == Wd, d['1'])
    check('and the untouched chair follows the save', m.get_facing(2) == E and d['2'] == E)
end

for _, bad in ipairs{5, true, 'abc', 'UNDECODABLE'} do  -- data that is not a table
    W = new_world(); chair(1, 5, 5, 10)
    W.site['improved-chairs'] = bad
    W.site['chair-facing'] = {['1']=E}
    local ok, err = pcall(function() m = load_script() end)
    check('bad site data (' .. tostring(bad) .. ') does not fail the load', ok, err)
    eq('bad site data does not bring the old name back', m.get_facing(1), S)
    ok, err = pcall(m.set_facing, 1, Wd)
    check('and is written over by the next change', ok and type(W.site['improved-chairs']) == 'table' and W.site['improved-chairs']['1'] == Wd, err)
end

do  -- odd keys and values
    W = new_world(); chair(7, 5, 5, 10); chair(8, 6, 5, 10); chair(9, 7, 5, 10)
    W.site['improved-chairs'] = {format=2, ['007']=E, ['008:nudge']={0, 1}, ['9']=1.5, ['9:nudge']={0/0, 'x'},
                                 ['99999999999999999999']=E, ['8']={1}}
    local ok, err = pcall(function() m = load_script() end)
    check('odd keys do not fail the load', ok, err)
    eq('zero-padded key read', m.get_facing(7), E)
    local d = W.site['improved-chairs']
    check('and saved again as the plain number', d['007'] == nil and d['7'] == E and d['008:nudge'] == nil and d['8:nudge'][2] == 1)
    m.set_facing(7, S); m.restore()
    eq('so it can be cleared', m.get_facing(7), S)
    eq('fractional facing floored', m.get_facing(9), E)
    local dx, dy = m.get_nudge(9); check('NaN and string nudge dropped', dx == 0 and dy == 0)
    dx, dy = m.set_nudge(8, 0/0, 1/0); check('NaN nudge is no nudge, infinity is clamped', dx == 0 and dy == math.floor(dy) and dy < 32, dx .. ',' .. dy)
    W.site['improved-chairs'] = {format=2, [tostring(4294967296 + 8)]=E}
    m.restore(); eq('an id beyond 32 bits does not land on another chair', m.get_facing(8), S)
end

do  -- a save from a newer format is shown and never written
    W = new_world(); chair(1, 5, 5, 10)
    W.site['improved-chairs'] = {format=3, ['1']=E, future={1, 2}}
    m = load_script()
    eq('newer format: facing shown', m.get_facing(1), E)
    m.set_facing(1, Wd)
    check('newer format: not written over', W.saves == 0 and W.site['improved-chairs'].future ~= nil and W.site['improved-chairs']['1'] == E)
end

do  -- two copies of the script each keep their own state-change handler
    W = new_world(); chair(1, 5, 5, 10)
    m = load_script()
    local n = 0
    for key in pairs(m.dfhack.onStateChange) do n = n + 1; check('handler key names the copy', key ~= 'improved-chairs', key) end
    eq('one handler', n, 1)
    W.site['improved-chairs'] = 5
    check('a failing restore does not escape the handler', pcall(m.dfhack.onStateChange[next(m.dfhack.onStateChange)], 1))
end

print(('%d checks, %d failed'):format(count, failures))
os.exit(failures == 0 and 0 or 1)
