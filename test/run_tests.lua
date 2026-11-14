-- Tests for scripts_modinstalled/improved-chairs.lua with DFHack and the game stubbed.
--   lua test/run_tests.lua [path to the script]
local here = arg[0]:match('^(.*)/[^/]*$') or '.'
local SCRIPT = arg[1] or (here .. '/../scripts_modinstalled/improved-chairs.lua')

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
local function viewport(dim_x, dim_y) return {dim_x=dim_x, dim_y=dim_y, screentexpos_building_one=zeros(dim_x * dim_y), screentexpos_item=zeros(dim_x * dim_y)} end

-- the game's default palette: shade i of ramp 0 is grey 10*i, of ramp 1 grey 100+10*i
local palette = {}
for ramp = 0, 1 do for i = 0, 8 do for c = 0, 2 do palette[ramp * 27 + i * 3 + c] = ramp * 100 + i * 10 + c end end end

local function new_world()
    local w = {site={}, buildings={}, chairs={}, items={}, ground={}, saves=0, map_loaded=true, fortress=true, next_handle=0}
    -- (the game has eight lower layers; asking for another is an error, as in DFHack)
    local lower = {}
    for i = 0, 7 do lower[i] = viewport(25, 17) end
    w.gps = {main_viewport=viewport(25, 17), default_palette={color=palette},
        lower_viewport=setmetatable({}, {__index=function(_, i) if math.type(i) ~= 'integer' or i < 0 or i > 7 then error('index out of bounds') end; return lower[i] end,
            __newindex=function(_, i, v) lower[i] = v end})}
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
    W.building_next_id = (W.building_next_id or 0) + 1      -- as the game does for every new building
    return b
end

-- An item: a chair unless opts.other, lying on the ground at x, y, z unless opts.carried.  The
-- game keeps a tile's items in the order of their ids; W.ground is that list for the whole map.
local function item(id, x, y, z, opts)
    opts = opts or {}
    local it = {id=id, pos={x=x, y=y, z=z}, flags={on_ground=not opts.carried, removed=false}}
    local mat = opts.mat or {0, 0}
    function it:getMaterial() if opts.broken then error('broken item') end; return mat[1] end
    function it:getMaterialIndex() return mat[2] end
    W.all_items = W.all_items or {}
    W.all_items[id] = it
    if not opts.other then W.items[#W.items + 1] = it end
    if not opts.carried then W.ground[#W.ground + 1] = id; table.sort(W.ground) end
    return it
end
local function vector_of(list) return setmetatable({}, {__index=function(_, i) return list()[i + 1] end, __len=function() return #list() end}) end

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
        maps={getTileBlock=function(x, y, z)
            W.block_reads = (W.block_reads or 0) + 1
            local ids = {}
            for _, id in ipairs(W.ground) do
                local p = W.all_items[id].pos
                if p.z == z and p.x >> 4 == x >> 4 and p.y >> 4 == y >> 4 then ids[#ids + 1] = id end
            end
            return {items=vector_of(function() return ids end)}
        end},
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
            getTexposByHandle=function(h) if W.texpos_of then return W.texpos_of(h) end; return 1000 + h end,
        }, {__index=function() return anything() end}),
    }
    setmetatable(env.dfhack, {__index=function() return anything() end})
    env.df = {
        building_chairst=CHAIR_TYPE,
        item={find=function(id) W.item_finds = (W.item_finds or 0) + 1; return W.all_items and W.all_items[id] end},
        building={find=function(id)   -- like the game: integers only, and only 32 bits of them
            if math.type(id) ~= 'integer' then error('integer expected') end
            if W.buildings[id] and W.buildings[id].find_fails then error('find failed') end
            return W.buildings[id & 0xffffffff]
        end},
        global=setmetatable({}, {__index=function(_, k)
            if k == 'gps' then return W.gps end
            if k == 'world' then return {items={other={CHAIR=vector_of(function() return W.items end)}}, buildings={other={CHAIR=setmetatable({}, {__index=function(_, i) if i < 0 or i >= #W.chairs then error('index out of bounds') end; return W.chairs[i + 1] end, __len=function() return #W.chairs end})}}, raws={descriptors=W.descriptors or {colors={}, patterns={}}}} end
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

-- ---- what the map overlay remembers ------------------------------------------------------------
do
    local main, cells
    local function start()
        W = new_world(); W.window_x, W.window_y, W.window_z = 100, 50, 10
        main = W.gps.main_viewport; cells = main.screentexpos_building_one
    end
    local function cell(x, y) return (x - W.window_x) * 17 + (y - W.window_y) end
    -- one frame: the game fills its layers again (a picture for every chair in `shown`), then the mod draws
    local shown
    local function frame()
        for i = 0, 25 * 17 - 1 do cells[i] = 0 end
        for _, b in ipairs(shown) do
            local sx, sy = b.centerx - W.window_x, b.centery - W.window_y
            if b.z == W.window_z and sx >= 0 and sx < 25 and sy >= 0 and sy < 17 then cells[sx * 17 + sy] = 7 end
        end
        I.draw_chairs()
    end
    local function at(x, y) return cells[cell(x, y)] end

    start()
    local a, b2 = chair(1, 103, 52, 10), chair(2, 105, 52, 10)
    shown = {a, b2}
    m = load_script(); I = m.internal
    for _ = 1, 100 do frame() end
    eq('a hundred frames standing still: one index', m.STATS.indexes, 1)
    check('and a view only every so often', m.STATS.views <= 5, m.STATS.views)
    check('both chairs drawn in the last frame', at(103, 52) > 1000 and at(105, 52) > 1000)
    eq('alike chairs share a tile', at(103, 52), at(105, 52))

    local before = at(103, 52)
    m.set_facing(1, Wd); frame()
    check('a turned chair shows turned in the next frame', at(103, 52) > 1000 and at(103, 52) ~= before, at(103, 52))
    eq('the other chair is as it was', at(105, 52), before)
    local turned = at(103, 52)
    m.set_nudge(1, 1, 0); frame()
    check('a nudged chair shows nudged in the next frame', at(103, 52) ~= turned and at(103, 52) ~= before)
    m.set_facing(1, S); frame()
    eq('turned back: the first tile again', at(103, 52), before)

    W.window_x = 101; frame()
    check('after a camera move the chairs are at their new cells', at(103, 52) > 1000 and at(105, 52) > 1000)
    local written = 0
    for i = 0, 25 * 17 - 1 do if cells[i] > 1000 then written = written + 1 end end
    eq('and nowhere else', written, 2)
    W.window_z = 11; frame()
    written = 0
    for i = 0, 25 * 17 - 1 do if cells[i] ~= 0 then written = written + 1 end end
    eq('another level: nothing of the old one is written', written, 0)
    W.window_z = 10; W.window_x = 100; frame()

    -- a chair the game stops showing, and shows again
    shown = {b2}; frame()
    eq('a chair the game does not show is not drawn', at(103, 52), 0)
    shown = {a, b2}; frame()
    check('shown again: drawn again in that frame', at(103, 52) > 1000)

    -- building
    local opts = {unfinished=true}
    local c = chair(3, 107, 52, 10, opts); shown = {a, b2, c}
    frame()
    eq('a chair being built keeps the game\'s picture', at(107, 52), 7)
    for _ = 1, 5 do frame() end
    opts.unfinished = false; frame()
    check('finished: drawn in the next frame', at(107, 52) > 1000)

    -- a chair a dwarf starts to take apart is left to the game within VIEW_FRAMES frames
    opts.unfinished = true
    for _ = 1, 31 do frame() end
    eq('a chair being taken apart goes back to the game\'s picture', at(107, 52), 7)
    opts.unfinished = false
    for _ = 1, 31 do frame() end
    check('removal called off: drawn again', at(107, 52) > 1000)

    -- removal: the chair leaves the game's list
    table.remove(W.chairs, 1); W.buildings[1] = nil; shown = {b2, c}
    frame()
    eq('a removed chair leaves nothing behind', at(103, 52), 0)
    check('the others are still drawn', at(105, 52) > 1000 and at(107, 52) > 1000)
    -- one removed and one built in the same frame: the list is as long as before
    table.remove(W.chairs, 1); W.buildings[2] = nil
    local d = chair(4, 110, 55, 10); shown = {c, d}
    frame()
    eq('removed and built in one frame: the old cell is empty', at(105, 52), 0)
    check('and the new chair is drawn', at(110, 55) > 1000 and at(107, 52) > 1000)

    -- the camera moves north-south or changes level while the game shows something at the old cells
    local function fill() for i = 0, 25 * 17 - 1 do cells[i] = 7 end end
    local function count_drawn() local n = 0; for i = 0, 25 * 17 - 1 do if cells[i] > 1000 then n = n + 1 end end; return n end
    W.window_y = 51; fill(); I.draw_chairs()
    check('a move north-south: the chairs are at their new cells', count_drawn() == 2 and at(107, 52) > 1000 and at(110, 55) > 1000, count_drawn())
    W.window_z = 11; fill(); I.draw_chairs()
    eq('a level up: its lower layer gets the chairs, the main one none', count_drawn(), 0)
    W.window_z = 10; W.window_y = 50; frame()

    -- saved facings read again (a map load): the view follows
    local was = at(107, 52)
    m.set_facing(3, E); frame()
    check('turned', at(107, 52) ~= was)
    W.site['improved-chairs'] = nil; m.restore(); frame()
    eq('facings read again from the save show in the next frame', at(107, 52), was)

    -- the game's list in another order with nothing else changed: no chair gets another's tile
    m.set_facing(3, E); frame()
    local turned3, plain4 = at(107, 52), at(110, 55)
    W.chairs[1], W.chairs[2] = W.chairs[2], W.chairs[1]
    m.set_nudge(4, 0, 0)        -- (anything that makes the view be worked out again)
    check('a reordered list raises nothing', pcall(frame))
    frame(); frame()
    check('and each chair keeps its own tile', at(107, 52) == turned3 and at(110, 55) == plain4)

    -- the chairs are looked up again every REINDEX_FRAMES frames, whatever happens
    local indexes = m.STATS.indexes
    for _ = 1, 1300 do frame() end
    eq('looked up again every 600 frames', m.STATS.indexes - indexes, 2)

    -- the world goes: nothing remembered may be written into the next one, even if it has as
    -- many chairs and the same next building id
    local count, next_id = #W.chairs, W.building_next_id
    m.dfhack.onStateChange[next(m.dfhack.onStateChange)](2)
    start(); shown = {chair(1, 120, 60, 10), chair(2, 121, 60, 10)}
    eq('(as many chairs as before)', #W.chairs, count)
    W.building_next_id = next_id
    fill(); I.draw_chairs()
    check('a new world: only its own chairs are drawn', count_drawn() == 2 and at(120, 60) > 1000 and at(121, 60) > 1000, count_drawn())

    -- a layer that changes size under a view
    start(); shown = {chair(1, 103, 52, 10)}
    m = load_script(); I = m.internal
    frame()
    W.gps.main_viewport = viewport(30, 12); main = W.gps.main_viewport; cells = main.screentexpos_building_one
    cells[3 * 12 + 2] = 7
    I.draw_chairs()
    check('a resized layer is indexed by its new size', cells[3 * 12 + 2] > 1000)
    for i in pairs(cells) do if i < 0 or i >= 30 * 12 then check('no write outside the resized layer', false, i) end end

    -- a lower layer that is not there when the view is made, and then is
    start()
    local kept = W.gps.lower_viewport[0]
    W.gps.lower_viewport[0] = nil
    chair(1, 103, 52, 9)
    m = load_script(); I = m.internal
    I.draw_chairs()
    W.gps.lower_viewport[0] = kept
    kept.screentexpos_building_one[cell(103, 52)] = 7
    I.draw_chairs()
    check('a lower layer that comes back is drawn in that frame', kept.screentexpos_building_one[cell(103, 52)] > 1000)

    -- the last chair goes and nothing is built: the list is shorter, and is not read past its end
    start(); local r1, r2 = chair(1, 103, 52, 10), chair(2, 105, 52, 10); shown = {r1, r2}
    m = load_script(); I = m.internal
    frame()
    table.remove(W.chairs, 2); W.buildings[2] = nil; shown = {r1}
    check('the last chair removed: no error', pcall(frame))
    local ok_later = true
    for _ = 1, 40 do ok_later = pcall(frame) and ok_later end
    check('nor in the frames after', ok_later)
    eq('and nothing left behind', at(105, 52), 0)
    check('the other is drawn', at(103, 52) > 1000)

    -- a chair nine levels down is out of reach of the eight lower layers
    start(); chair(1, 103, 52, 1); shown = {chair(2, 105, 52, 10)}
    m = load_script(); I = m.internal
    check('a chair nine levels down: no error', pcall(frame))
    check('and the chair in view is drawn', at(105, 52) > 1000)

    -- a layer that changes one of its sizes only
    for _, size in ipairs{{25, 12}, {30, 17}} do
        start(); shown = {chair(1, 103, 52, 10)}
        chair(2, 127, 52, 10)       -- (in view only once the layer is 30 wide)
        m = load_script(); I = m.internal
        frame()
        W.gps.main_viewport = viewport(size[1], size[2]); main = W.gps.main_viewport; cells = main.screentexpos_building_one
        for i = 0, size[1] * size[2] - 1 do cells[i] = 7 end
        I.draw_chairs()
        local n, where = 0
        for i, t in pairs(cells) do
            if i < 0 or i >= size[1] * size[2] then check('no write outside the layer', false, i) end
            if t > 1000 then n = n + 1 end
        end
        check(('a layer resized to %dx%d: the chair at its new cell'):format(size[1], size[2]), cells[3 * size[2] + 2] > 1000)
        eq('and every chair now in view is drawn', n, size[1] > 27 and 2 or 1)
    end

    -- the game gives a tile's texture another number, or takes it away
    start(); shown = {chair(1, 103, 52, 10)}
    m = load_script(); I = m.internal
    frame()
    local first = at(103, 52)
    W.texpos_of = function(h) return 5000 + h end
    frame()
    eq('a texture renumbered by the game: the new number in the next frame', at(103, 52), first + 4000)
    W.texpos_of = function() return 0 end
    frame()
    eq('a texture without a number leaves the game\'s picture', at(103, 52), 7)
    W.texpos_of = function() return -1 end
    frame()
    eq('so does a negative one', at(103, 52), 7)
    W.texpos_of = nil
    frame()
    eq('and back', at(103, 52), first)

    -- the list was reordered under the index
    start()
    local bad_opts = {mat={0, 1}}
    local good, bad = chair(1, 103, 52, 10), chair(2, 105, 52, 10, bad_opts); shown = {good, bad}
    m = load_script(); I = m.internal
    frame()
    -- (its id answers to another building: the id guard asks for the chairs to be looked up again)
    bad.id = 99; W.buildings[99] = bad
    m.set_facing(1, Wd)         -- (makes the view be worked out again)
    frame()
    eq('a chair whose id changed is not drawn from the old entry', at(105, 52), 7)
    frame()
    check('and is drawn once the chairs were looked up again', at(105, 52) > 1000, at(105, 52))

    -- a texture that is refused is asked for again
    start(); shown = {chair(1, 103, 52, 10)}
    m = load_script(); I = m.internal
    local create = m.dfhack.textures.createTile
    m.dfhack.textures.createTile = function() return 0 end
    frame()
    eq('a refused texture leaves the game\'s picture', at(103, 52), 7)
    m.dfhack.textures.createTile = create
    frame()
    check('and is had in the next frame', at(103, 52) > 1000)
end

-- ---- chairs lying on the ground ------------------------------------------------------------------
do
    local main, cells, icells
    local function start()
        W = new_world(); W.window_x, W.window_y, W.window_z = 100, 50, 10
        main = W.gps.main_viewport; cells, icells = main.screentexpos_building_one, main.screentexpos_item
    end
    local function cell(x, y) return (x - W.window_x) * 17 + (y - W.window_y) end
    -- one frame: the game puts 500 + id of the last item of each tile in the item layer, then the mod draws
    local function game(vp, z)
        local layer = vp.screentexpos_item
        for i = 0, vp.dim_x * vp.dim_y - 1 do layer[i] = 0 end
        for _, id in ipairs(W.ground) do
            local p = W.all_items[id].pos
            local sx, sy = p.x - W.window_x, p.y - W.window_y
            -- (the game does not draw a hidden item: seen in the game)
            if not W.all_items[id].flags.hidden and p.z == z and sx >= 0 and sx < vp.dim_x and sy >= 0 and sy < vp.dim_y then layer[sx * vp.dim_y + sy] = 500 + id end
        end
    end
    local function frame()
        game(main, W.window_z)
        for d = 0, 7 do if W.gps.lower_viewport[d] then game(W.gps.lower_viewport[d], W.window_z - d - 1) end end
        I.draw_chairs()
    end
    local function at(x, y) return icells[cell(x, y)] end
    local function pick_up(it) it.flags.on_ground = false; for i, id in ipairs(W.ground) do if id == it.id then table.remove(W.ground, i) end end end
    local function put_down(it, x, y, z) it.flags.on_ground = true; it.pos = {x=x, y=y, z=z}; W.ground[#W.ground + 1] = it.id; table.sort(W.ground) end

    start()
    local a = item(1, 103, 52, 10)
    item(2, 104, 52, 10); item(3, 104, 52, 10, {other=true})        -- a barrel on a chair
    item(4, 105, 52, 10, {other=true}); item(5, 105, 52, 10)        -- a chair on a barrel
    item(6, 106, 52, 10, {other=true})                              -- a barrel alone
    local carried = item(7, 107, 52, 10, {carried=true})
    item(8, 108, 52, 9); item(9, 109, 52, 2); item(10, 110, 52, 1); item(11, 111, 52, 11)
    item(12, 99, 52, 10); item(13, 125, 52, 10); item(14, 103, 49, 10); item(15, 103, 67, 10)
    item(16, 100, 50, 10); item(17, 124, 66, 10)
    -- the same tile of another level and of another block must not be taken for this one
    item(18, 103, 52, 9, {other=true}); item(19, 119, 52, 10, {other=true})
    m = load_script(); I = m.internal
    frame()
    check('a chair on the ground is drawn', at(103, 52) > 1000, at(103, 52))
    eq('a chair under another item is not', at(104, 52), 503)
    check('a chair on top of another item is', at(105, 52) > 1000)
    eq('another item is left alone', at(106, 52), 506)
    eq('a carried chair draws nothing', at(107, 52), 0)
    check('one level down: the lower layer', W.gps.lower_viewport[0].screentexpos_item[cell(108, 52)] > 1000)
    eq('and not the main one', at(108, 52), 0)
    check('eight levels down', W.gps.lower_viewport[7].screentexpos_item[cell(109, 52)] > 1000)
    check('corner cells', at(100, 50) > 1000 and at(124, 66) > 1000)
    local written = 0
    for _, vp in ipairs{main, W.gps.lower_viewport[0], W.gps.lower_viewport[1], W.gps.lower_viewport[7]} do
        for i, v in pairs(vp.screentexpos_item) do
            if v > 1000 then written = written + 1 end
            if i < 0 or i >= 25 * 17 then check('no write outside the item layer', false, i) end
        end
    end
    eq('exactly the six drawable chairs were written', written, 6)
    for i = 0, 25 * 17 - 1 do if cells[i] ~= 0 then check('the building layer is not touched', false, i) end end
    eq('chairs on the ground are counted', m.STATS.items, 6)

    -- it looks like a built chair nobody turned
    local b = chair(1, 112, 52, 10); cells[cell(112, 52)] = 7
    frame()
    eq('the same tile as an unturned built chair of that material', at(103, 52), cells[cell(112, 52)])

    -- picked up: what the game shows there now is left alone at once
    pick_up(a); item(20, 103, 52, 10, {other=true})
    frame()
    eq('a chair that was picked up: the item under it shows in the next frame', at(103, 52), 520)
    -- put down elsewhere: drawn within ITEM_FRAMES frames
    put_down(a, 113, 52, 10)
    frame()
    eq('(the game\'s picture at first)', at(113, 52), 501)
    for _ = 1, 31 do frame() end
    check('a chair put down is drawn within 30 frames', at(113, 52) > 1000, at(113, 52))
    -- something dropped on top of it
    item(21, 113, 52, 10, {other=true})
    frame()
    eq('an item dropped on a chair shows in the next frame', at(113, 52), 521)
    for _ = 1, 31 do frame() end
    eq('and keeps showing', at(113, 52), 521)

    -- a chair the game does not show (its tile is hidden): nothing is written there
    game(main, W.window_z); icells[cell(105, 52)] = 0
    m.set_facing(1, Wd)         -- (anything that makes the view be worked out again)
    I.draw_chairs()
    eq('a chair on the ground the game does not show stays unshown', at(105, 52), 0)
    for _ = 1, 3 do I.draw_chairs() end
    eq('in the frames after as well', at(105, 52), 0)

    -- an item the game has marked as removed is not drawn over
    local gone = item(23, 116, 52, 10); gone.flags.removed = true
    frame()
    eq('a removed chair item is left alone', at(116, 52), 523)

    -- a new chair item: the game's list grew, so it is drawn at once
    item(22, 115, 52, 10)
    frame()
    check('a chair that was just made is drawn in the next frame', at(115, 52) > 1000, at(115, 52))

    -- the game gives a chair on the ground another texture number: drawn again within a few frames
    do
        local function frame2()
            game(main, W.window_z); icells[cell(115, 52)] = 9000
            I.draw_chairs()
        end
        for _ = 1, 7 do frame2() end
        check('the game renumbers a chair\'s picture: drawn again within 7 frames', at(115, 52) > 1000 and at(115, 52) ~= 9000, at(115, 52))
        for _ = 1, 40 do frame() end
        check('and again when it goes back', at(115, 52) > 1000 and at(115, 52) ~= 522, at(115, 52))
    end

    -- the camera moves: at once at the new cells
    W.window_x = 101; frame()
    check('after a camera move the chairs are at their new cells', at(105, 52) > 1000 and at(104, 52) == 503 and at(106, 52) == 506)

    -- a tile's block is read once per look-up of the chairs, not once per frame
    W.window_x = 100; frame()
    local reads = W.block_reads
    for _ = 1, 20 do frame() end
    check('blocks are not read every frame', W.block_reads - reads <= 8, W.block_reads - reads)
    local finds = W.item_finds
    for _ = 1, 20 do frame() end
    check('and their items not looked at again while nothing came or went', W.item_finds - finds <= #W.ground, W.item_finds - finds)

    -- hidden items (the game draws the last item of a tile that is not hidden)
    start()
    item(1, 103, 52, 10, {other=true}); local h1 = item(2, 103, 52, 10)      -- a hidden chair on a barrel
    local h2 = item(3, 105, 52, 10)                                           -- a hidden chair alone
    local h3 = item(4, 107, 52, 10, {other=true}); item(5, 107, 52, 10); local h4 = item(6, 107, 52, 10)
    h1.flags.hidden, h2.flags.hidden, h3.flags.hidden, h4.flags.hidden = true, true, true, true
    m = load_script(); I = m.internal
    for _ = 1, 40 do frame() end
    eq('a hidden chair on a barrel: the barrel shows', at(103, 52), 501)
    eq('a hidden chair alone: nothing', at(105, 52), 0)
    check('a chair under a hidden item is drawn', at(107, 52) > 1000, at(107, 52))
    h1.flags.hidden = false
    for _ = 1, 40 do frame() end
    check('no longer hidden: drawn', at(103, 52) > 1000, at(103, 52))

    -- the view is worked out between an item coming or going and the next look-up of the chairs
    for _, how in ipairs{'camera', 'turn'} do
        start()
        item(1, 103, 52, 10, {other=true}); local top = item(2, 103, 52, 10)     -- a chair on a barrel
        item(3, 105, 52, 10)                                                      -- a chair alone
        chair(1, 110, 52, 10)
        m = load_script(); I = m.internal
        for _ = 1, 3 do frame() end
        check('(drawn at first)', at(103, 52) > 1000 and at(105, 52) > 1000)
        pick_up(top); item(4, 105, 52, 10, {other=true})                          -- and a barrel lands on the other
        if how == 'camera' then W.window_y = 49 else m.set_facing(1, Wd) end
        local wrong = 0
        for _ = 1, 40 do
            frame()
            if at(103, 52) ~= 501 or at(105, 52) ~= 504 then wrong = wrong + 1 end
        end
        eq('a chair picked up, a barrel dropped on another, then the ' .. how .. ': no frame with a chair over a barrel', wrong, 0)
    end

    -- the same when the chair picked up is not the newest item of its part of the map
    start()
    item(1, 103, 52, 10, {other=true}); local mid = item(2, 103, 52, 10); item(9, 110, 60, 10, {other=true})
    m = load_script(); I = m.internal
    for _ = 1, 3 do frame() end
    pick_up(mid); W.window_y = 49
    local wrong_mid = 0
    for _ = 1, 40 do frame(); if at(103, 52) ~= 501 then wrong_mid = wrong_mid + 1 end end
    eq('an older chair picked up, then the camera: no frame with a chair over the barrel', wrong_mid, 0)

    -- blocks that differ in one coordinate only are not mixed up
    start()
    item(1, 103, 52, 10); item(2, 103, 52 + 16, 10, {other=true}); item(3, 103 + 16, 52, 10, {other=true})
    item(4, 103, 60, 10, {other=true}); item(5, 103, 60 + 16, 10); item(6, 103 + 16, 60, 10)
    W.gps.main_viewport = viewport(25, 40); main = W.gps.main_viewport; icells = main.screentexpos_item
    local function at40(x, y) return icells[(x - 100) * 40 + (y - 50)] end
    m = load_script(); I = m.internal
    frame()
    check('chairs in three neighbouring blocks: each judged by its own block',
        at40(103, 52) > 1000 and at40(103, 76) > 1000 and at40(119, 60) > 1000 and at40(103, 68) == 502 and at40(119, 52) == 503 and at40(103, 60) == 504)

    -- a chair put down with nothing else going on: drawn within 30 frames
    start(); local loose = item(1, 103, 52, 10, {carried=true}); item(2, 120, 60, 10)
    m = load_script(); I = m.internal
    for _ = 1, 3 do frame() end
    put_down(loose, 103, 52, 10)
    local waited = 0
    repeat frame(); waited = waited + 1 until at(103, 52) > 1000 or waited > 100
    check('a chair put down is drawn within 30 frames', waited <= 31, waited)

    -- very many chair items: they are looked up less often
    start(); loose = item(1, 103, 52, 10, {carried=true})
    for id = 2, 801 do item(id, 0, 0, 0, {carried=true}) end
    m = load_script(); I = m.internal
    for _ = 1, 3 do frame() end
    put_down(loose, 103, 52, 10)
    waited = 0
    repeat frame(); waited = waited + 1 until at(103, 52) > 1000 or waited > 300
    check('among 800 chair items a chair put down is drawn within 100 frames, not 30', waited > 31 and waited <= 101, waited)

    -- a block with more items than are worth reading: its chairs keep the game's picture
    start(); item(1, 103, 52, 10)
    for id = 2, 1030 do item(id, 110, 60, 10, {other=true}) end
    item(1031, 120, 52, 10)                         -- (in the next block)
    m = load_script(); I = m.internal
    W.item_finds = 0
    for _ = 1, 40 do frame() end
    eq('a chair in a block of more than 1024 items keeps the game\'s picture', at(103, 52), 501)
    check('a chair in the block beside it is drawn', at(120, 52) > 1000)
    check('and the big block\'s items are not gone through', W.item_finds < 100, W.item_finds)

    -- no built chair at all: the chairs on the ground are still drawn
    start(); item(1, 103, 52, 10)
    m = load_script(); I = m.internal
    frame()
    check('no built chair: a chair on the ground is drawn', at(103, 52) > 1000)

    -- materials
    start()
    W.materials = {['420:5']={material={flags={WOOD=true}, state_color={Solid=-1}}}}
    item(1, 103, 52, 10, {mat={420, 5}}); item(2, 104, 52, 10, {mat={0, 7}})
    m = load_script(); I = m.internal
    frame()
    check('wood and stone chairs on the ground get different tiles', at(103, 52) > 1000 and at(104, 52) > 1000 and at(103, 52) ~= at(104, 52))

    -- a chair item that cannot be read: reported, the built chairs are drawn all the same
    start()
    item(1, 103, 52, 10, {broken=true}); chair(1, 105, 52, 10); cells[cell(105, 52)] = 7
    m = load_script(); I = m.internal
    local ok, err = pcall(frame)
    check('a broken chair item is reported', not ok and tostring(err):find('broken item'), err)
    check('and the built chair is drawn', cells[cell(105, 52)] > 1000)
    eq('the broken one keeps the game\'s picture', at(103, 52), 501)

    -- an item layer that is missing
    start(); item(1, 103, 52, 10); chair(1, 105, 52, 10); cells[cell(105, 52)] = 7
    main.screentexpos_item = nil
    m = load_script(); I = m.internal
    check('no item layer: no error', pcall(I.draw_chairs))
    check('and the built chair is drawn', cells[cell(105, 52)] > 1000)

    -- the world goes
    start(); item(1, 103, 52, 10)
    m = load_script(); I = m.internal
    frame()
    m.dfhack.onStateChange[next(m.dfhack.onStateChange)](2)
    start(); item(1, 110, 60, 10)
    for i = 0, 25 * 17 - 1 do icells[i] = 501 end
    I.draw_chairs()
    local n = 0
    for i = 0, 25 * 17 - 1 do if icells[i] > 1000 then n = n + 1 end end
    check('a new world: only its own chair on the ground is drawn', n == 1 and at(110, 60) > 1000, n)
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

do  -- a click lands after the site turned up but before the overlay's next retry
    W = new_world(); chair(1, 5, 5, 10); chair(2, 6, 5, 10); chair(3, 7, 5, 10)
    W.no_site = true
    m = load_script()
    m.set_facing(1, Wd)
    W.no_site = false
    W.site['improved-chairs'] = {format=2, ['2']=N, ['2:nudge']={1, 1}, ['3']=E}
    m.set_facing(1, E)
    local d = W.site['improved-chairs']
    check('the click does not write over the site\'s own data', d['1'] == E and d['2'] == N and d['2:nudge'][1] == 1 and d['3'] == E)
    check('and that data is shown', m.get_facing(2) == N and m.get_facing(3) == E and not m.internal.save_pending())
end

do  -- the world is unloaded: nothing of it is kept
    W = new_world(); chair(1, 5, 5, 10)
    m = load_script(); m.set_facing(1, Wd)
    local handler
    for k, f in pairs(m.dfhack.onStateChange) do handler = f end
    handler(m.SC_WORLD_UNLOADED)
    eq('facings dropped at unload', m.get_facing(1), S)
    W.buildings[1].find_fails = true
    local ok, err = pcall(handler, m.SC_MAP_LOADED)
    check('a restore that throws does not escape the handler', ok, err)
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
