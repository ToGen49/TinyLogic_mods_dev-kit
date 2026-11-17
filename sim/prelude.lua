-- Tiny Logic mods: the part of the mod system that is written in Lua itself.
--
-- The game starts one Lua VM and runs this file in it once. It builds the `tl` table every mod sees, keeps each
-- mod's handlers and timers, turns node graphs into Lua, and hands the game a small table of functions (`__tl`)
-- to drive it all. A mod never sees this file's globals: its code runs in its own environment (see `sandbox`).

local host = __host
__host = nil

local VERSION = "0.2-beta"
local FRAME_BUDGET, LOAD_BUDGET = 3000000, 30000000   -- Lua instructions one handler / one load may take

local mods = {}          -- id -> the mod's record
local order = {}         -- ids in the order they were loaded (handlers run in this order)
local nodes = {}         -- node type id -> its definition
local node_order = {}    -- node type ids, in the order they were defined

local unpack, pack = table.unpack, table.pack
local fmt = string.format

-- ---------------------------------------------------------------------------------------------- colours

local NAMED = {
    white = {255, 255, 255}, black = {20, 16, 30}, ink = {236, 235, 245}, muted = {150, 147, 176},
    red = {229, 72, 77}, green = {95, 224, 138}, yellow = {245, 211, 60}, blue = {86, 156, 255},
    cyan = {80, 220, 235}, purple = {176, 120, 255}, pink = {255, 110, 180}, orange = {255, 150, 60},
    gray = {92, 89, 118}, grey = {92, 89, 118}, board = {28, 27, 42},
}

-- anything a mod may hand over as a colour -> r, g, b, a
local function rgba(c, alpha)
    if c == nil then return 236, 235, 245, alpha or 255 end
    if type(c) == "string" then
        local n = NAMED[c:lower()]
        if n then return n[1], n[2], n[3], alpha or 255 end
        local hex = c:match("^#?(%x%x%x%x%x%x%x?%x?)$")
        if hex then
            return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16),
                   #hex == 8 and tonumber(hex:sub(7, 8), 16) or alpha or 255
        end
        return 236, 235, 245, alpha or 255
    end
    if type(c) == "table" then
        return c.r or c[1] or 255, c.g or c[2] or 255, c.b or c[3] or 255, c.a or c[4] or alpha or 255
    end
    return 236, 235, 245, alpha or 255
end

local function hsv(h, s, v)
    h = (h % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    local r, g, b
    if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
    return {r = math.floor(r * 255), g = math.floor(g * 255), b = math.floor(b * 255), a = 255}
end

-- ---------------------------------------------------------------------------------------------- logging

local function show(v, depth)
    if type(v) == "string" then return depth > 0 and ('"' .. v .. '"') or v end
    if type(v) ~= "table" then return tostring(v) end
    if depth >= 2 then return "{...}" end
    local parts, n, seen = {}, 0, {}
    for k = 1, #v do
        seen[k] = true
        n = n + 1
        if n > 12 then parts[#parts + 1] = "..." break end
        parts[#parts + 1] = show(v[k], depth + 1)
    end
    if n <= 12 then
        local keys = {}
        for k in pairs(v) do if not seen[k] then keys[#keys + 1] = k end end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            n = n + 1
            if n > 12 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. show(v[k], depth + 1)
        end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end
local function text_of(...)
    local t = pack(...)
    for i = 1, t.n do t[i] = show(t[i], 0) end
    return table.concat(t, " ", 1, t.n)
end

local function fault(mod, what, err)
    mod.errors = mod.errors + 1
    host.log(mod.id, 2, what .. ": " .. tostring(err))
    if mod.errors >= 25 and not mod.dead then            -- (a mod that faults every frame is stopped, not left to flood)
        mod.dead = true
        host.log(mod.id, 2, "stopped after 25 errors (fix it, then save + run)")
    end
end

-- runs a mod's function with a fresh instruction budget; a fault is written to that mod's console
local function guarded(mod, what, fn, ...)
    if mod.dead then return nil end
    host.budget(FRAME_BUDGET)
    local r = pack(xpcall(fn, function(e)
        if type(e) ~= "string" then e = tostring(e) end
        return e
    end, ...))
    if not r[1] then
        fault(mod, what, r[2])
        return nil
    end
    return unpack(r, 2, r.n)
end

-- ---------------------------------------------------------------------------------------------- the sandbox

local function safe_pcall(f, ...)
    local r = pack(pcall(f, ...))
    if not r[1] and host.over() then error(r[2], 0) end   -- (running out of time can't be caught and carried on from)
    return unpack(r, 1, r.n)
end
local function safe_xpcall(f, h, ...)
    local r = pack(xpcall(f, h, ...))
    if not r[1] and host.over() then error(r[2], 0) end
    return unpack(r, 1, r.n)
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local SAFE = {
    assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs, select = select,
    tonumber = tonumber, tostring = tostring, type = type, pcall = safe_pcall, xpcall = safe_xpcall,
    setmetatable = setmetatable, rawget = rawget, rawset = rawset,
    rawequal = rawequal, rawlen = rawlen, _VERSION = _VERSION,
}

-- (only a table's metatable: the one every string shares stays out of reach, so no mod can change text for the rest)
function SAFE.getmetatable(v)
    if type(v) == "table" then return getmetatable(v) end
    return nil
end

-- ---------------------------------------------------------------------------------------------- the api

local make_api   -- (below)

local function new_mod(id)
    local mod = {
        id = id, handlers = {}, next_handle = 1, timers = {}, next_timer = 1, exports = {}, commands = {},
        windows = {}, watches = {}, errors = 0, vars = {},
    }
    local env = {}
    for k, v in pairs(SAFE) do env[k] = v end
    env.math, env.string, env.table, env.utf8, env.coroutine = copy(math), copy(string), copy(table), copy(utf8), copy(coroutine)
    env.print = function(...) host.log(id, 0, text_of(...)) end
    env.vars = mod.vars
    env._G = env
    env.tl = make_api(mod)
    mod.env = env
    return mod
end

-- an engine call: the result table, or nil and why (the reason also goes to the mod's console)
local function call(mod, op, args)
    local res, err = host.call(op, args or {})
    if res == nil and err then host.log(mod.id, 1, op .. ": " .. err) end
    return res, err
end

local function part_id(p)
    if type(p) == "table" then return p.id end
    return p
end

function make_api(mod)
    local tl = {version = VERSION, id = mod.id}

    -- events ------------------------------------------------------------------------------------
    function tl.on(event, fn)
        assert(type(event) == "string" and type(fn) == "function", "tl.on(event, function)")
        local h = mod.next_handle
        mod.next_handle = h + 1
        local list = mod.handlers[event]
        if not list then list = {} mod.handlers[event] = list end
        list[#list + 1] = {h = h, fn = fn}
        return h
    end
    function tl.off(handle)
        for _, list in pairs(mod.handlers) do
            for i = #list, 1, -1 do
                if list[i].h == handle then table.remove(list, i) end
            end
        end
    end
    function tl.emit(event, ...)        -- to every mod (this one too)
        __tl.dispatch(event, ...)
    end

    -- time --------------------------------------------------------------------------------------
    local function timer(sec, fn, every)
        assert(type(fn) == "function", "a timer needs a function")
        local id = mod.next_timer
        mod.next_timer = id + 1
        sec = math.max(tonumber(sec) or 0, 0)
        mod.timers[id] = {at = host.now() + sec, fn = fn, every = every and math.max(sec, 0.01) or nil}
        return id
    end
    function tl.after(sec, fn) return timer(sec, fn, false) end
    function tl.every(sec, fn) return timer(sec, fn, true) end
    function tl.cancel(id) mod.timers[id] = nil end
    function tl.time() return host.now() end

    -- words -------------------------------------------------------------------------------------
    function tl.log(...) host.log(mod.id, 0, text_of(...)) end
    function tl.warn(...) host.log(mod.id, 1, text_of(...)) end
    function tl.command(name, fn)       -- typed in the mod console: `name the rest`
        mod.commands[tostring(name)] = fn
    end

    -- other mods --------------------------------------------------------------------------------
    function tl.export(name, value) mod.exports[name] = value end
    function tl.require(id)
        local other = mods[id]
        if not other then return nil, "no mod called " .. tostring(id) .. " is running" end
        return other.exports
    end
    function tl.mods()
        local out = {}
        for _, id in ipairs(order) do out[#out + 1] = id end
        return out
    end

    -- the raw engine interface (everything below is built on it) ---------------------------------
    function tl.call(op, args) return call(mod, op, args) end

    -- colour ------------------------------------------------------------------------------------
    function tl.color(r, g, b, a)
        if type(r) == "number" then return {r = r, g = g or r, b = b or r, a = a or 255} end
        local R, G, B, A = rgba(r)
        return {r = R, g = G, b = B, a = A}
    end
    tl.hsv = hsv

    -- the board ---------------------------------------------------------------------------------
    local board = {}
    tl.board = board
    function board.place(name, x, y, opts)
        local a = {}
        if type(opts) == "table" then for k, v in pairs(opts) do a[k] = v end end
        a.name = name
        if x and y then a.x, a.y = math.floor(x), math.floor(y) end
        local res, err = call(mod, "place", a)
        if not res then return nil, err end
        return res.id, res
    end
    function board.chip(name, x, y)
        local a = {chip = name}
        if x and y then a.x, a.y = math.floor(x), math.floor(y) end
        local res, err = call(mod, "place", a)
        if not res then return nil, err end
        return res.id, res
    end
    local function pin_of(part, pin)      -- a pin by its number (they count from 0, as the game shows them) or its name
        if type(pin) ~= "string" then return pin or 0 end
        local res = call(mod, "part", {part = part})
        local want = pin:lower()
        for _, q in ipairs(res and res.pins or {}) do
            if tostring(q.name):lower() == want then return q.pin end
        end
        for _, q in ipairs(res and res.pins or {}) do
            if tostring(q.name):lower():find(want, 1, true) then return q.pin end
        end
        return -1
    end
    function board.wire(a, pin_a, b, pin_b, color)
        a, b = part_id(a), part_id(b)
        if type(a) ~= "number" or type(b) ~= "number" then
            host.log(mod.id, 1, "wire: that needs two parts (one of them is nil)")
            return nil, "no such part"
        end
        local res, err = call(mod, "wire", {from = {a, pin_of(a, pin_a)}, to = {b, pin_of(b, pin_b)}, color = color})
        if not res then return nil, err end
        return res.id
    end
    function board.remove(...)
        local ids = {}
        for _, p in ipairs({...}) do
            if type(p) == "table" and not p.id then for _, q in ipairs(p) do ids[#ids + 1] = part_id(q) end
            else ids[#ids + 1] = part_id(p) end
        end
        if #ids == 0 then return 0 end
        local res = call(mod, "delete", {parts = ids})
        return res and res.deleted or 0
    end
    function board.remove_wire(...)
        local res = call(mod, "delete", {wires = {...}})
        return res and res.deleted or 0
    end
    function board.parts(kind)          -- every part on this level (or only one kind: "light", "switch"...)
        local res = call(mod, "board", kind and {kinds = {kind}} or {})
        return res and res.parts or {}
    end
    function board.wires(paths)
        local res = call(mod, "board", {paths = paths and true or false})
        return res and res.wires or {}
    end
    -- asking about a part that is gone is an ordinary question, not a mistake: no warning in the console
    function board.part(id) return host.call("part", {part = part_id(id)}) end
    function board.pins(id)
        local res = host.call("part", {part = part_id(id)})
        return res and res.pins or {}
    end
    function board.set(id, props)
        local a = {}
        for k, v in pairs(props or {}) do a[k] = v end
        a.part = part_id(id)
        return call(mod, "set", a)
    end
    function board.label(id, text) return board.set(id, {label = tostring(text)}) end
    function board.move(id, x, y) return call(mod, "move", {part = part_id(id), x = math.floor(x), y = math.floor(y)}) end
    function board.rotate(id, flip) return call(mod, "rotate", {parts = {part_id(id)}, flip = flip and true or false}) end
    function board.wire_color(wire, color) return call(mod, "wire_color", {wire = wire, color = color}) end
    function board.clear()
        local st = call(mod, "state", {})
        local level = st and st.level or "main"
        if type(level) ~= "string" then level = "main" end
        return call(mod, "clear", {confirm = true, level = level})
    end
    function board.find_space(w, h, near_x, near_y)
        local a = {w = w, h = h}
        if near_x and near_y then a.near = {math.floor(near_x), math.floor(near_y)} end
        local res, err = call(mod, "find_space", a)
        if not res then return nil, err end
        return res.x, res.y
    end
    function board.catalog()
        local res = call(mod, "catalog", {})
        return res or {}
    end
    function board.select(ids) return call(mod, "select", {parts = ids or {}}) end
    function board.selection()
        local st = call(mod, "state", {})
        return st and st.selection or {}
    end
    function board.count()
        local st = call(mod, "state", {})
        if not st then return 0, 0 end
        return st.parts or 0, st.wires or 0
    end
    function board.undo() return call(mod, "undo", {}) end
    function board.redo() return call(mod, "redo", {}) end

    -- the simulation ----------------------------------------------------------------------------
    local sim = {}
    tl.sim = sim
    function sim.read(id, pin)          -- what a part shows (or one of its pins carries)
        local probe = pin and {part_id(id), pin} or part_id(id)
        local res = call(mod, "probe", {probes = {probe}})
        local r = res and res[1]
        if not r or r.error then return nil, r and r.error end
        return r.value, r.volts
    end
    function sim.read_all(ids)
        local probes = {}
        for i, p in ipairs(ids) do probes[i] = type(p) == "table" and not p.id and p or part_id(p) end
        local res = call(mod, "probe", {probes = probes})
        local out = {}
        for i, r in ipairs(res or {}) do out[i] = r.value end
        return out
    end
    function sim.set(id, on)            -- a switch closed or open
        return call(mod, "set", {part = part_id(id), on = on and true or false})
    end
    function sim.toggle(id)
        local v = sim.read(id)
        return sim.set(id, not (v == 1 or v == true))
    end
    function sim.press(id, down) return call(mod, "press", {part = part_id(id), down = down ~= false}) end
    function sim.tap(id, seconds)       -- a push button pressed and let go
        sim.press(id, true)
        tl.after(seconds or 0.15, function() sim.press(id, false) end)
    end
    function sim.number(id, n) return call(mod, "set", {part = part_id(id), number = n}) end
    function sim.clock(action, id)      -- "play", "pause", "step" or "restart"
        return call(mod, "clock", {action = action, part = id and part_id(id) or nil})
    end
    function sim.speed(n, id) return call(mod, "clock", {speed = n, part = id and part_id(id) or nil}) end
    function sim.step(times, id) return call(mod, "clock", {action = "step", times = times or 1, part = id and part_id(id) or nil}) end
    function sim.watch(id, pin, fn)     -- fn(value, before) whenever the reading changes
        if type(pin) == "function" then fn, pin = pin, nil end
        local w = {probe = pin and {part_id(id), pin} or part_id(id), fn = fn}
        mod.watches[#mod.watches + 1] = w
        return w
    end
    function sim.unwatch(w)
        for i = #mod.watches, 1, -1 do
            if mod.watches[i] == w then table.remove(mod.watches, i) end
        end
    end
    function sim.state() return call(mod, "state", {}) end
    function sim.truth_table(args) return call(mod, "truth_table", args or {}) end

    -- electric parts: their settings by name, and what they measure ------------------------------
    -- (settings in SI units: volts, amps, ohms, farads, henries, hz; "height" is a wave's peak, "width" its duty, 0..1)
    local elec = {}
    tl.elec = elec
    function elec.settings(id)          -- every setting by name, as it is now (and their names, in order)
        local p = host.call("part", {part = part_id(id)})
        if not p then return nil, "no part " .. tostring(id) end
        return p.settings or {}, p.setting_names or {}
    end
    function elec.get(id, name)
        local all, err = elec.settings(id)
        if not all then return nil, err end
        return all[name]
    end
    function elec.set(id, name, value)  -- one setting (name, value) or several ({hz = 440, height = 2})
        local list = type(name) == "table" and name or {[name] = value}
        return call(mod, "set", {part = part_id(id), settings = list})
    end
    function elec.volts(id, pin, other)  -- the volts on a pin (against ground), or between two pins of one part
        local _, v = sim.read(id, pin or 0)
        if other == nil or v == nil then return v end
        local _, w = sim.read(id, other)
        return w and v - w
    end
    function elec.amps(id)              -- the current through a part, in amps (0 when none flows)
        local p = host.call("part", {part = part_id(id)})
        return p and p.amps or 0
    end
    function elec.meter(id)             -- what a voltmeter or ammeter reads
        return (sim.read(id))
    end
    function elec.watch(id, pin, fn, step)  -- fn(volts, before) when a pin's volts move by `step` (0.1 V unless given)
        if type(pin) == "function" then fn, step, pin = pin, fn, 0 end
        local w = {probe = {part_id(id), pin or 0}, fn = fn, volts = true, step = math.abs(tonumber(step) or 0.1)}
        mod.watches[#mod.watches + 1] = w
        return w
    end
    function elec.unwatch(w) return sim.unwatch(w) end

    -- drawing: on the board (in tiles and board pixels) and on the screen ------------------------
    local function drawer(on_board)
        local d = {}
        function d.rect(x, y, w, h, c, alpha)
            local r, g, b, a = rgba(c, alpha)
            host.draw(0, on_board, x, y, w, h, r, g, b, a)
        end
        function d.frame(x, y, w, h, c, alpha)
            local r, g, b, a = rgba(c, alpha)
            host.draw(1, on_board, x, y, w, h, r, g, b, a)
        end
        function d.text(text, x, y, c, scale)
            local r, g, b, a = rgba(c)
            host.draw(2, on_board, x, y, 0, 0, r, g, b, a, tostring(text), scale or 1)
        end
        function d.measure(text, scale) return host.measure(tostring(text), scale or 1) end
        function d.pixel(x, y, c) d.rect(x, y, 1, 1, c) end
        function d.line(x0, y0, x1, y1, c)
            local r, g, b, a = rgba(c)
            x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
            if y0 == y1 then host.draw(0, on_board, math.min(x0, x1), y0, math.abs(x1 - x0) + 1, 1, r, g, b, a) return end
            if x0 == x1 then host.draw(0, on_board, x0, math.min(y0, y1), 1, math.abs(y1 - y0) + 1, r, g, b, a) return end
            local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
            local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
            local e, n = dx + dy, 0
            while n < 2000 do
                host.draw(0, on_board, x0, y0, 1, 1, r, g, b, a)
                if x0 == x1 and y0 == y1 then break end
                local e2 = 2 * e
                if e2 >= dy then e = e + dy x0 = x0 + sx end
                if e2 <= dx then e = e + dx y0 = y0 + sy end
                n = n + 1
            end
        end
        return d
    end
    tl.draw = drawer(true)
    tl.hud = drawer(false)
    function tl.draw.tile(tx, ty, c, alpha)         -- one whole board tile (16 x 16 board pixels)
        local r, g, b, a = rgba(c, alpha)
        host.draw(0, true, tx * 16, ty * 16, 16, 16, r, g, b, a)
    end
    function tl.draw.cell(tx, ty, c, inset)         -- a tile with a gap round it
        local r, g, b, a = rgba(c)
        inset = inset or 1
        host.draw(0, true, tx * 16 + inset, ty * 16 + inset, 16 - inset * 2, 16 - inset * 2, r, g, b, a)
    end
    function tl.hud.size() return host.viewport() end

    -- little windows ----------------------------------------------------------------------------
    local ui = {}
    tl.ui = ui
    function ui.toast(text, c)
        local r, g, b = rgba(c or "yellow")
        host.toast(tostring(text), r, g, b)
    end
    function ui.window(title, fn, opts)             -- fn runs every frame while the window is open
        opts = opts or {}
        local w = {title = tostring(title), fn = fn, x = opts.x, y = opts.y, w = opts.w or 110, open = true, ui = ui}
        function w.close() w.open = false end
        mod.windows[#mod.windows + 1] = w
        return w
    end
    function ui.label(text, c)
        local r, g, b = rgba(c or "ink")
        host.ui_label(tostring(text), r, g, b)
    end
    function ui.button(label) return host.ui_button(tostring(label)) end
    function ui.toggle(label, value) return host.ui_toggle(tostring(label), value and true or false) end
    function ui.slider(label, value, lo, hi) return host.ui_slider(tostring(label), tonumber(value) or 0, lo or 0, hi or 1) end
    function ui.bar(label, frac, c)
        if type(label) == "number" then label, frac, c = "", label, frac end
        local r, g, b = rgba(c or "green")
        host.ui_bar(tostring(label), math.max(0, math.min(1, tonumber(frac) or 0)), r, g, b)
    end
    function ui.space(px) host.ui_space(px or 3) end

    -- keys and the mouse -------------------------------------------------------------------------
    tl.input = {
        key = function(name) return host.key(tostring(name)) end,
        -- while a mod holds the keys, the editor's own shortcuts stay quiet (escape always gives them back)
        capture = function(on) host.capture(mod.id, on and true or false) end,
        mouse = function()
            local x, y, tx, ty, down = host.mouse()
            return {x = x, y = y, tile_x = tx, tile_y = ty, down = down}
        end,
    }

    -- sound -------------------------------------------------------------------------------------
    tl.sound = {
        play = function(name, pitch) host.sound(tostring(name), pitch or 1) end,
        note = function(hz, seconds, volume, tone) host.note(hz, seconds or 0.15, volume or 0.1, tone or "square") end,
    }

    -- what a mod keeps between sessions ------------------------------------------------------------
    local stored
    local function store()
        if not stored then stored = host.store_read(mod.id) or {} end
        return stored
    end
    tl.store = {
        get = function(key, default)
            local v = store()[key]
            if v == nil then return default end
            return v
        end,
        set = function(key, value)
            store()[key] = value
            host.store_write(mod.id, stored)
        end,
    }

    -- the view ----------------------------------------------------------------------------------
    tl.camera = {
        get = function()
            local st = call(mod, "state", {})
            return st and st.camera
        end,
        go = function(x, y, zoom) return call(mod, "camera", {x = x, y = y, zoom = zoom}) end,
        fit = function() return call(mod, "camera", {fit = true}) end,
        focus = function(ids) return call(mod, "focus", {parts = ids}) end,
    }

    -- the visual scripting editor: a mod can add its own node types --------------------------------
    tl.graph = {
        node = function(def)
            def.from = mod.id
            return __tl.node(def)
        end,
    }

    return tl
end

-- ---------------------------------------------------------------------------------------------- node types

local function pin_list(list)
    local out = {}
    for i, p in ipairs(list or {}) do
        if type(p) == "string" then p = {p, "any"} end
        out[i] = {name = p[1] or p.name, type = p[2] or p.type or "any", def = p[3] ~= nil and p[3] or p.def, const = p.const or false}
    end
    return out
end

local function define(def)
    assert(type(def) == "table" and type(def.id) == "string", "a node needs an id")
    local t = {
        id = def.id, cat = def.cat or "Mod", title = def.title or def.id, kind = def.kind or "action",
        ins = pin_list(def.ins), outs = pin_list(def.outs), flows = def.flows or {}, tip = def.tip or "",
        code = def.code, expr = def.expr, exprs = def.exprs, head = def.head, tail = def.tail,
        nonext = def.nonext or false, from = def.from,
    }
    if not nodes[t.id] then node_order[#node_order + 1] = t.id end
    nodes[t.id] = t
    return t
end

local N = define

-- Events: where a chain starts. `head` opens the handler; its parameters are the node's outputs.
N{id = "event.load", cat = "Events", title = "When the mod starts", kind = "event", head = 'tl.on("load", function()',
  tip = "Runs once, when the mod is loaded or reloaded."}
N{id = "event.frame", cat = "Events", title = "Every frame", kind = "event", head = 'tl.on("frame", function(dt)',
  outs = {{"dt", "number"}}, tip = "Runs every frame. dt is the seconds since the last one."}
N{id = "event.every", cat = "Events", title = "Every N seconds", kind = "event", head = "tl.every($seconds, function()",
  ins = {{"seconds", "number", 1, const = true}}, tip = "Runs again and again, this many seconds apart."}
N{id = "event.draw", cat = "Events", title = "When drawing", kind = "event", head = 'tl.on("draw", function()',
  tip = "Runs every frame, the place for Draw nodes."}
N{id = "event.key", cat = "Events", title = "When a key is pressed", kind = "event",
  head = 'tl.on("key", function(key, down) if not (down and key == $key) then return end',
  ins = {{"key", "string", "space", const = true}}, tip = "A key going down: a letter, space, return, up, down, left, right..."}
N{id = "event.click", cat = "Events", title = "When the board is clicked", kind = "event", head = 'tl.on("click", function(x, y)',
  outs = {{"x", "number"}, {"y", "number"}}, tip = "A left click on the board. x, y is the tile."}
N{id = "event.placed", cat = "Events", title = "When a part is placed", kind = "event", head = 'tl.on("part_placed", function(part, kind)',
  outs = {{"part", "number"}, {"kind", "string"}}, tip = "Any new part on this level, by the player or a mod."}
N{id = "event.removed", cat = "Events", title = "When a part is removed", kind = "event", head = 'tl.on("part_removed", function(part)',
  outs = {{"part", "number"}}}
N{id = "event.wired", cat = "Events", title = "When a wire is added", kind = "event", head = 'tl.on("wire_added", function(wire)',
  outs = {{"wire", "number"}}}
N{id = "event.custom", cat = "Events", title = "When an event arrives", kind = "event", head = "tl.on($name, function(a, b, c)",
  ins = {{"name", "string", "my_event", const = true}}, outs = {{"a", "any"}, {"b", "any"}, {"c", "any"}},
  tip = "Any event by name: one sent with Send event, by a script (tl.emit) or by another mod."}
N{id = "event.command", cat = "Events", title = "When a command is typed", kind = "event", head = "tl.command($name, function(text)",
  ins = {{"name", "string", "go", const = true}}, outs = {{"text", "string"}}, tip = "Typed in the mod's console: the name, then anything after it."}
N{id = "event.window", cat = "Events", title = "Window", kind = "event", head = "tl.ui.window($title, function()",
  ins = {{"title", "string", "My window", const = true}}, tip = "A little window on screen. Its chain runs every frame: put Label and Button nodes in it."}
N{id = "event.function", cat = "Events", title = "Function", kind = "event", head = "function $name(a, b)", tail = "end",
  ins = {{"name", "name", "my_function", const = true}}, outs = {{"a", "any"}, {"b", "any"}},
  tip = "A function the mod's script (main.lua) can call by this name."}

-- Flow
N{id = "flow.if", cat = "Flow", title = "If", kind = "flow", ins = {{"condition", "bool", true}}, flows = {"then", "else"},
  code = "if $condition then\n#then\nelse\n#else\nend", tip = "One branch or the other, then on to next."}
N{id = "flow.repeat", cat = "Flow", title = "Repeat", kind = "flow", ins = {{"count", "number", 4}}, outs = {{"i", "number"}}, flows = {"body"},
  code = "for i_ = 1, $count do\n    @i = i_\n#body\nend", tip = "Runs body this many times. i counts from 1."}
N{id = "flow.each_part", cat = "Flow", title = "For each part", kind = "flow", ins = {{"kind", "string", ""}},
  outs = {{"part", "number"}, {"kind", "string"}, {"x", "number"}, {"y", "number"}}, flows = {"body"},
  code = "for _, p_ in ipairs(tl.board.parts($kind ~= \"\" and $kind or nil)) do\n    @part, @kind, @x, @y = p_.id, p_.kind, p_.x, p_.y\n#body\nend",
  tip = "Runs body once for every part on the board (or only one kind, like light)."}
N{id = "flow.each_wire", cat = "Flow", title = "For each wire", kind = "flow", outs = {{"wire", "number"}, {"index", "number"}}, flows = {"body"},
  code = "for i_, w_ in ipairs(tl.board.wires()) do\n    @wire, @index = w_.id, i_\n#body\nend"}
N{id = "flow.delay", cat = "Flow", title = "Wait, then", kind = "flow", ins = {{"seconds", "number", 1}}, flows = {"later"},
  code = "tl.after($seconds, function()\n#later\nend)", tip = "Carries on at once through next, and runs later after the wait."}
N{id = "flow.while", cat = "Flow", title = "While", kind = "flow", ins = {{"condition", "bool", false}}, flows = {"body"},
  code = "while $condition do\n#body\nend"}
N{id = "flow.stop", cat = "Flow", title = "Stop here", kind = "flow", nonext = true, code = "do return end"}

-- Board
N{id = "board.place", cat = "Board", title = "Place part", ins = {{"name", "string", "light"}, {"x", "number", 0}, {"y", "number", 0}},
  outs = {{"part", "number"}}, code = "@part = tl.board.place($name, $x, $y)", tip = "A part by its name in the part finder, at a tile."}
N{id = "board.wire", cat = "Board", title = "Wire", ins = {{"from", "number", 0}, {"pin", "number", 0}, {"to", "number", 0}, {"to pin", "number", 0}, {"color", "number", 0}},
  outs = {{"wire", "number"}}, code = "@wire = tl.board.wire($from, $pin, $to, $topin, $color)", tip = "A wire between two pins. Pins count from 0."}
N{id = "board.remove", cat = "Board", title = "Remove part", ins = {{"part", "number", 0}}, code = "tl.board.remove($part)"}
N{id = "board.move", cat = "Board", title = "Move part", ins = {{"part", "number", 0}, {"x", "number", 0}, {"y", "number", 0}}, code = "tl.board.move($part, $x, $y)"}
N{id = "board.label", cat = "Board", title = "Label part", ins = {{"part", "number", 0}, {"text", "string", "hello"}}, code = "tl.board.label($part, $text)"}
N{id = "board.wire_color", cat = "Board", title = "Colour wire", ins = {{"wire", "number", 0}, {"color", "number", 0}}, code = "tl.board.wire_color($wire, $color)",
  tip = "One of the nine wire colours, 0 to 8."}
N{id = "board.clear", cat = "Board", title = "Clear board", code = "tl.board.clear()", tip = "Everything on this level. One undo brings it back."}
N{id = "board.count", cat = "Board", title = "Count", kind = "value", outs = {{"parts", "number"}, {"wires", "number"}},
  exprs = {parts = "(select(1, tl.board.count()))", wires = "(select(2, tl.board.count()))"}}
N{id = "board.rotate", cat = "Board", title = "Rotate part", ins = {{"part", "number", 0}}, code = "tl.board.rotate($part)"}

-- Sim
N{id = "sim.read", cat = "Sim", title = "Read part", kind = "value", ins = {{"part", "number", 0}}, outs = {{"value", "number"}},
  expr = "(tl.sim.read($part) or 0)", tip = "What a part shows: a light lit is 1, a switch closed is 1, a display its number."}
N{id = "sim.read_pin", cat = "Sim", title = "Read pin", kind = "value", ins = {{"part", "number", 0}, {"pin", "number", 0}}, outs = {{"value", "number"}},
  expr = "(tl.sim.read($part, $pin) or 0)"}
N{id = "sim.set", cat = "Sim", title = "Set switch", ins = {{"part", "number", 0}, {"on", "bool", true}}, code = "tl.sim.set($part, $on)"}
N{id = "sim.toggle", cat = "Sim", title = "Flip switch", ins = {{"part", "number", 0}}, code = "tl.sim.toggle($part)"}
N{id = "sim.tap", cat = "Sim", title = "Tap button", ins = {{"part", "number", 0}}, code = "tl.sim.tap($part)"}
N{id = "sim.number", cat = "Sim", title = "Set dial", ins = {{"part", "number", 0}, {"number", "number", 0}}, code = "tl.sim.number($part, $number)"}
N{id = "sim.clock", cat = "Sim", title = "Clock", ins = {{"action", "string", "play"}}, code = "tl.sim.clock($action)", tip = "play, pause, step or restart."}
-- Electric
N{id = "elec.volts", cat = "Electric", title = "Volts on pin", kind = "value", ins = {{"part", "number", 0}, {"pin", "number", 0}}, outs = {{"volts", "number"}},
  expr = "(tl.elec.volts($part, $pin) or 0)", tip = "The volts on one of a part's pins, against ground."}
N{id = "elec.amps", cat = "Electric", title = "Amps through", kind = "value", ins = {{"part", "number", 0}}, outs = {{"amps", "number"}},
  expr = "(tl.elec.amps($part) or 0)", tip = "The current through a part. 0 when none flows."}
N{id = "elec.meter", cat = "Electric", title = "Meter reading", kind = "value", ins = {{"part", "number", 0}}, outs = {{"reading", "number"}},
  expr = "(tl.elec.meter($part) or 0)", tip = "What a voltmeter (volts) or an ammeter (amps) reads."}
N{id = "elec.get", cat = "Electric", title = "Get setting", kind = "value", ins = {{"part", "number", 0}, {"name", "string", "volts"}}, outs = {{"value", "number"}},
  expr = "(tl.elec.get($part, $name) or 0)", tip = "One of an electric part's settings: volts, ohms, farads, hz..."}
N{id = "elec.set", cat = "Electric", title = "Set setting", ins = {{"part", "number", 0}, {"name", "string", "volts"}, {"value", "number", 5}},
  code = "tl.elec.set($part, $name, $value)", tip = "Change a setting the way its card would. One undo brings it back."}

-- Math
N{id = "math.number", cat = "Math", title = "Number", kind = "value", ins = {{"value", "number", 0, const = true}}, outs = {{"value", "number"}}, expr = "$value"}
N{id = "math.add", cat = "Math", title = "Add", kind = "value", ins = {{"a", "number", 0}, {"b", "number", 0}}, outs = {{"result", "number"}}, expr = "($a + $b)"}
N{id = "math.sub", cat = "Math", title = "Subtract", kind = "value", ins = {{"a", "number", 0}, {"b", "number", 0}}, outs = {{"result", "number"}}, expr = "($a - $b)"}
N{id = "math.mul", cat = "Math", title = "Multiply", kind = "value", ins = {{"a", "number", 1}, {"b", "number", 1}}, outs = {{"result", "number"}}, expr = "($a * $b)"}
N{id = "math.div", cat = "Math", title = "Divide", kind = "value", ins = {{"a", "number", 1}, {"b", "number", 1}}, outs = {{"result", "number"}}, expr = "($a / $b)"}
N{id = "math.mod", cat = "Math", title = "Remainder", kind = "value", ins = {{"a", "number", 0}, {"b", "number", 2}}, outs = {{"result", "number"}}, expr = "($a % $b)"}
N{id = "math.floor", cat = "Math", title = "Round down", kind = "value", ins = {{"a", "number", 0}}, outs = {{"result", "number"}}, expr = "math.floor($a)"}
N{id = "math.random", cat = "Math", title = "Random", kind = "value", ins = {{"from", "number", 1}, {"to", "number", 6}}, outs = {{"result", "number"}}, expr = "math.random($from, $to)"}
N{id = "math.sin", cat = "Math", title = "Sine", kind = "value", ins = {{"a", "number", 0}}, outs = {{"result", "number"}}, expr = "math.sin($a)"}
N{id = "math.min", cat = "Math", title = "Smaller", kind = "value", ins = {{"a", "number", 0}, {"b", "number", 0}}, outs = {{"result", "number"}}, expr = "math.min($a, $b)"}
N{id = "math.max", cat = "Math", title = "Bigger", kind = "value", ins = {{"a", "number", 0}, {"b", "number", 0}}, outs = {{"result", "number"}}, expr = "math.max($a, $b)"}
N{id = "math.time", cat = "Math", title = "Time", kind = "value", outs = {{"seconds", "number"}}, expr = "tl.time()", tip = "Seconds since the mods started."}

-- Logic
N{id = "logic.equal", cat = "Logic", title = "Equals", kind = "value", ins = {{"a", "any", 0}, {"b", "any", 0}}, outs = {{"result", "bool"}}, expr = "($a == $b)"}
N{id = "logic.less", cat = "Logic", title = "Less than", kind = "value", ins = {{"a", "number", 0}, {"b", "number", 0}}, outs = {{"result", "bool"}}, expr = "($a < $b)"}
N{id = "logic.greater", cat = "Logic", title = "Greater than", kind = "value", ins = {{"a", "number", 0}, {"b", "number", 0}}, outs = {{"result", "bool"}}, expr = "($a > $b)"}
N{id = "logic.and", cat = "Logic", title = "And", kind = "value", ins = {{"a", "bool", true}, {"b", "bool", true}}, outs = {{"result", "bool"}}, expr = "($a and $b)"}
N{id = "logic.or", cat = "Logic", title = "Or", kind = "value", ins = {{"a", "bool", false}, {"b", "bool", false}}, outs = {{"result", "bool"}}, expr = "($a or $b)"}
N{id = "logic.not", cat = "Logic", title = "Not", kind = "value", ins = {{"a", "bool", false}}, outs = {{"result", "bool"}}, expr = "(not $a)"}
N{id = "logic.pick", cat = "Logic", title = "Pick", kind = "value", ins = {{"condition", "bool", true}, {"yes", "any", 1}, {"no", "any", 0}}, outs = {{"result", "any"}},
  expr = "(function() if $condition then return $yes end return $no end)()"}

-- Text
N{id = "text.text", cat = "Text", title = "Text", kind = "value", ins = {{"value", "string", "hello", const = true}}, outs = {{"value", "string"}}, expr = "$value"}
N{id = "text.join", cat = "Text", title = "Join", kind = "value", ins = {{"a", "any", ""}, {"b", "any", ""}}, outs = {{"result", "string"}}, expr = "(tostring($a) .. tostring($b))"}
N{id = "text.number", cat = "Text", title = "To number", kind = "value", ins = {{"text", "any", "0"}}, outs = {{"result", "number"}}, expr = "(tonumber($text) or 0)"}

-- Variables (one table a mod's graph and script share: `vars`)
N{id = "var.set", cat = "Variables", title = "Set variable", ins = {{"name", "string", "score", const = true}, {"value", "any", 0}}, code = "vars[$name] = $value"}
N{id = "var.get", cat = "Variables", title = "Get variable", kind = "value", ins = {{"name", "string", "score", const = true}}, outs = {{"value", "any"}}, expr = "vars[$name]"}
N{id = "var.add", cat = "Variables", title = "Change variable", ins = {{"name", "string", "score", const = true}, {"by", "number", 1}},
  outs = {{"value", "number"}}, code = "vars[$name] = (tonumber(vars[$name]) or 0) + $by\n@value = vars[$name]"}
N{id = "var.store_set", cat = "Variables", title = "Save value", ins = {{"key", "string", "best", const = true}, {"value", "any", 0}}, code = "tl.store.set($key, $value)",
  tip = "Kept on disk: still there next session."}
N{id = "var.store_get", cat = "Variables", title = "Saved value", kind = "value", ins = {{"key", "string", "best", const = true}, {"default", "any", 0}},
  outs = {{"value", "any"}}, expr = "tl.store.get($key, $default)"}

-- Draw
N{id = "draw.tile", cat = "Draw", title = "Draw tile", ins = {{"x", "number", 0}, {"y", "number", 0}, {"color", "color", "green"}}, code = "tl.draw.cell($x, $y, $color)",
  tip = "Fills one board tile. Use it in a When drawing chain."}
N{id = "draw.rect", cat = "Draw", title = "Draw box", ins = {{"x", "number", 0}, {"y", "number", 0}, {"w", "number", 16}, {"h", "number", 16}, {"color", "color", "yellow"}},
  code = "tl.draw.rect($x, $y, $w, $h, $color)", tip = "In board pixels: one tile is 16."}
N{id = "draw.text", cat = "Draw", title = "Draw text", ins = {{"text", "any", "hi"}, {"x", "number", 0}, {"y", "number", 0}, {"color", "color", "white"}},
  code = "tl.draw.text($text, $x, $y, $color)"}
N{id = "draw.hud_text", cat = "Draw", title = "Screen text", ins = {{"text", "any", "hi"}, {"x", "number", 8}, {"y", "number", 30}, {"color", "color", "white"}},
  code = "tl.hud.text($text, $x, $y, $color)", tip = "On the screen, not the board. The screen is 480 by 270."}
N{id = "draw.rainbow", cat = "Draw", title = "Rainbow", kind = "value", ins = {{"hue", "number", 0}}, outs = {{"color", "color"}}, expr = "tl.hsv($hue, 0.8, 1)"}

-- UI
N{id = "ui.toast", cat = "UI", title = "Toast", ins = {{"text", "any", "hello!"}, {"color", "color", "yellow"}}, code = "tl.ui.toast($text, $color)"}
N{id = "ui.label", cat = "UI", title = "Label", ins = {{"text", "any", "hello"}, {"color", "color", "ink"}}, code = "tl.ui.label($text, $color)", tip = "A line of text in a Window chain."}
N{id = "ui.button", cat = "UI", title = "Button", kind = "flow", ins = {{"label", "string", "press me"}}, flows = {"clicked"},
  code = "if tl.ui.button($label) then\n#clicked\nend", tip = "A button in a Window chain. clicked runs when it is pressed."}
N{id = "ui.bar", cat = "UI", title = "Bar", ins = {{"label", "string", "power"}, {"amount", "number", 0.5}, {"color", "color", "green"}}, code = "tl.ui.bar($label, $amount, $color)"}
N{id = "ui.log", cat = "UI", title = "Log", ins = {{"text", "any", "hello"}}, code = "tl.log($text)", tip = "A line in the mod's console."}

-- Sound
N{id = "sound.play", cat = "Sound", title = "Play sound", ins = {{"name", "string", "pop"}, {"pitch", "number", 1}}, code = "tl.sound.play($name, $pitch)",
  tip = "click, confirm, tick, pop, boom, whoosh, zap, error, switch, thump, sparkle..."}
N{id = "sound.note", cat = "Sound", title = "Play note", ins = {{"hz", "number", 440}, {"seconds", "number", 0.15}}, code = "tl.sound.note($hz, $seconds)"}

-- Camera
N{id = "camera.go", cat = "Camera", title = "Look at", ins = {{"x", "number", 0}, {"y", "number", 0}}, code = "tl.camera.go($x, $y)"}
N{id = "camera.fit", cat = "Camera", title = "Fit the board", code = "tl.camera.fit()"}

-- Script: the bridge between a graph and the mod's Lua
N{id = "script.call", cat = "Script", title = "Call Lua function", ins = {{"name", "name", "my_function", const = true}, {"a", "any", 0}, {"b", "any", 0}},
  outs = {{"result", "any"}}, code = "@result = $name($a, $b)", tip = "Calls a function written in the mod's script (main.lua)."}
N{id = "script.value", cat = "Script", title = "Lua value", kind = "value", ins = {{"code", "name", "math.pi", const = true}}, outs = {{"value", "any"}}, expr = "($code)",
  tip = "Any name from the script: a variable, or a table field."}
N{id = "script.emit", cat = "Script", title = "Send event", ins = {{"name", "string", "my_event", const = true}, {"a", "any", 0}, {"b", "any", 0}}, code = "tl.emit($name, $a, $b)",
  tip = "Every mod listening for this name hears it, scripts and graphs alike."}
N{id = "script.engine", cat = "Script", title = "Engine call", ins = {{"op", "string", "state", const = true}}, outs = {{"result", "any"}}, code = "@result = tl.call($op, {})",
  tip = "The raw engine interface, for anything the nodes don't cover yet."}

-- ---------------------------------------------------------------------------------------------- graph -> Lua

local function literal(ptype, v)
    if ptype == "number" then return tostring(tonumber(v) or 0) end
    if ptype == "bool" then return (v == true or v == "true" or v == "1" or v == "yes" or v == "on") and "true" or "false" end
    if ptype == "name" then
        local s = tostring(v or ""):gsub("[^%w_%.]", "")
        if s == "" or s:match("^%d") then s = "nothing_" end
        return s
    end
    if ptype == "string" or ptype == "color" then return fmt("%q", tostring(v == nil and "" or v)) end
    if v == nil then return "nil" end
    if type(v) == "number" then return tostring(v) end
    if type(v) == "boolean" then return tostring(v) end
    local s = tostring(v)
    if tonumber(s) then return tostring(tonumber(s)) end
    if s == "true" or s == "false" or s == "nil" then return s end
    return fmt("%q", s)
end

local function key_of(name) return (name:gsub("[^%w_]", "")) end

-- a graph (a table: nodes, links) as Lua source; also returns the list of problems found on the way
local function compile(graph)
    local out, problems = {}, {}
    local byid, data_in, exec_out = {}, {}, {}
    for _, n in ipairs(graph.nodes or {}) do byid[n.id] = n end
    for _, l in ipairs(graph.links or {}) do
        if l.exec then
            exec_out[l.from] = exec_out[l.from] or {}
            exec_out[l.from][l.out] = l.to
        else
            data_in[l.to] = data_in[l.to] or {}
            data_in[l.to][l["in"]] = l
        end
    end
    local function problem(n, text)
        problems[#problems + 1] = {node = n and n.id or 0, text = text}
    end
    local function pin_def(t, name)
        for _, p in ipairs(t.ins) do
            if p.name == name or key_of(p.name) == name then return p end
        end
    end
    local value_of
    local function input(n, t, name, visiting)
        local p = pin_def(t, name)
        if not p then return "nil" end
        local l = data_in[n.id] and data_in[n.id][p.name]
        if l and byid[l.from] and not p.const then return value_of(byid[l.from], l.out, visiting) end
        local v = n.values and n.values[p.name]
        if v == nil then v = p.def end
        return literal(p.type, v)
    end
    function value_of(src, pin, visiting)
        local t = nodes[src.type]
        if not t then return "nil" end
        if t.kind ~= "value" then return fmt("v.n%d_%s", src.id, key_of(pin)) end
        if visiting[src.id] then
            problem(src, "this value feeds itself")
            return "nil"
        end
        visiting[src.id] = true
        local e = (t.exprs and t.exprs[pin]) or t.expr or "nil"
        e = e:gsub("%$([%w_]+)", function(name) return input(src, t, name, visiting) end)
        visiting[src.id] = nil
        return e
    end
    local function line(depth, text) out[#out + 1] = string.rep("    ", depth) .. text end
    local emit
    function emit(id, depth, path)
        local mine = {}
        while id do
            local n = byid[id]
            local t = n and nodes[n.type]
            if not t then break end
            if path[id] then
                problem(n, "a chain can't loop back on itself: use Repeat or While")
                break
            end
            if t.kind == "event" then
                problem(n, "an event starts a chain, it can't be in the middle of one")
                break
            end
            path[id] = true
            mine[#mine + 1] = id
            local code = t.code or ""
            code = code:gsub("%$([%w_]+)", function(name) return input(n, t, name, {}) end)
            code = code:gsub("@([%w_]+)", function(name) return fmt("v.n%d_%s", n.id, name) end)
            for text in (code .. "\n"):gmatch("(.-)\n") do
                local flow = text:match("^%s*#([%w_]+)%s*$")
                if flow then emit(exec_out[id] and exec_out[id][flow], depth + 1, path)
                elseif text ~= "" then line(depth, text) end
            end
            if t.nonext then break end
            id = exec_out[id] and exec_out[id].next
        end
        for _, m in ipairs(mine) do path[m] = nil end
    end
    local list = {}
    for _, n in ipairs(graph.nodes or {}) do
        local t = nodes[n.type]
        if not t then problem(n, "no node type called " .. tostring(n.type) .. " (is the mod that adds it running?)")
        elseif t.kind == "event" then list[#list + 1] = n end
    end
    table.sort(list, function(a, b)
        if (a.y or 0) ~= (b.y or 0) then return (a.y or 0) < (b.y or 0) end
        return a.id < b.id
    end)
    line(0, "-- made from the mod's node graph")
    for _, n in ipairs(list) do
        local t = nodes[n.type]
        local head = t.head:gsub("%$([%w_]+)", function(name) return input(n, t, name, {}) end)
        line(0, "")
        line(0, "-- " .. t.title)
        line(0, head)
        line(1, "local v = {}")
        local params = t.head:match("function[^%(]*%(([^%)]*)%)") or ""
        for _, o in ipairs(t.outs) do
            if params:find(o.name, 1, true) then line(1, fmt("v.n%d_%s = %s", n.id, key_of(o.name), o.name)) end
        end
        emit(exec_out[n.id] and exec_out[n.id].next, 1, {})
        line(0, t.tail or "end)")
    end
    return table.concat(out, "\n") .. "\n", problems
end

-- ---------------------------------------------------------------------------------------------- the game's handle

__tl = {}

function __tl.node(def) return define(def) end

function __tl.catalog()
    local out = {}
    for i, id in ipairs(node_order) do
        local t = nodes[id]
        out[i] = {id = t.id, cat = t.cat, title = t.title, kind = t.kind, ins = t.ins, outs = t.outs, flows = t.flows, tip = t.tip,
                  nonext = t.nonext, from = t.from or ""}
    end
    return out
end

function __tl.compile(graph)
    host.budget(LOAD_BUDGET)
    local ok, src, problems = pcall(compile, graph)
    if not ok then return "", {{node = 0, text = tostring(src)}} end
    return src, problems
end

local function drop(id)
    local mod = mods[id]
    if not mod then return end
    local list = mod.handlers.unload
    if list then
        for _, h in ipairs(list) do guarded(mod, "unload", h.fn) end
    end
    mods[id] = nil
    for i = #order, 1, -1 do
        if order[i] == id then table.remove(order, i) end
    end
    for i = #node_order, 1, -1 do                      -- (and the node types it added)
        local t = nodes[node_order[i]]
        if t and t.from == id then
            nodes[node_order[i]] = nil
            table.remove(node_order, i)
        end
    end
end

-- load (or reload) a mod: its script first, then its graph, both in the same environment
function __tl.load(id, script, graph)
    drop(id)
    local mod = new_mod(id)
    mods[id] = mod
    order[#order + 1] = id
    local good = true
    local function run(source, name)
        local chunk, err = load(source, "=" .. name, "t", mod.env)
        if not chunk then
            fault(mod, "can't read " .. name, err)
            good = false
            return
        end
        host.budget(LOAD_BUDGET)
        local ok, e = xpcall(chunk, function(m) return tostring(m) end)
        if not ok then
            fault(mod, name, e)
            good = false
        end
    end
    if script and script ~= "" then run(script, "main.lua") end
    if graph and graph.nodes and #graph.nodes > 0 then
        local src, problems = __tl.compile(graph)
        for _, p in ipairs(problems) do host.log(id, 1, "graph: " .. p.text) end
        run(src, "graph")
    end
    local list = mod.handlers.load
    if list then
        for _, h in ipairs(list) do guarded(mod, "load", h.fn) end
    end
    return good and mod.errors == 0
end

function __tl.unload(id) drop(id) end

function __tl.errors(id)
    local mod = mods[id]
    return mod and mod.errors or 0
end

function __tl.dispatch(event, ...)
    for i = 1, #order do
        local mod = mods[order[i]]
        local list = mod and mod.handlers[event]
        if list then
            for k = 1, #list do
                local h = list[k]
                if h then guarded(mod, event, h.fn, ...) end
            end
        end
    end
end

-- one frame: timers, watches, then the frame and draw events and every mod's windows
local second_at = 0
function __tl.frame(dt)
    local now = host.now()
    for i = 1, #order do
        local mod = mods[order[i]]
        if mod then
            local due
            for id, t in pairs(mod.timers) do
                if now >= t.at then
                    due = due or {}
                    due[#due + 1] = id
                end
            end
            if due then
                table.sort(due)
                for _, id in ipairs(due) do
                    local t = mod.timers[id]
                    if t then
                        if t.every then t.at = math.max(t.at + t.every, now) else mod.timers[id] = nil end
                        guarded(mod, "timer", t.fn)
                    end
                end
            end
            if #mod.watches > 0 then
                local probes = {}
                for k, w in ipairs(mod.watches) do probes[k] = w.probe end
                local res = host.call("probe", {probes = probes})
                for k, w in ipairs(mod.watches) do
                    if w.volts then  -- (tl.elec.watch: a move of `step` volts from the last one told)
                        local v = res and res[k] and res[k].volts
                        if v and (not w.seen or math.abs(v - w.last) >= w.step) then
                            if w.seen then guarded(mod, "watch", w.fn, v, w.last) end
                            w.seen, w.last = true, v
                        end
                    else
                        local v = res and res[k] and res[k].value
                        if type(v) == "table" then v = table.concat(v, ",") end
                        if w.seen and v ~= w.last then guarded(mod, "watch", w.fn, res[k].value, w.last_raw) end
                        w.seen, w.last, w.last_raw = true, v, res and res[k] and res[k].value
                    end
                end
            end
        end
    end
    __tl.dispatch("frame", dt)
    if now - second_at >= 1 then
        second_at = now
        __tl.dispatch("second")
    end
    __tl.dispatch("draw")
    for i = 1, #order do
        local mod = mods[order[i]]
        if mod then
            for k = #mod.windows, 1, -1 do
                if not mod.windows[k].open then table.remove(mod.windows, k) end
            end
            for k = 1, #mod.windows do
                local w = mod.windows[k]
                if not mod.dead then
                    host.ui_begin(mod.id, w.title, w.x or -1, w.y or -1, w.w)
                    guarded(mod, "window " .. w.title, w.fn, w.ui, w)
                    host.ui_end()
                end
            end
        end
    end
end

-- a line typed in a mod's console: a command the mod set up, or Lua run in the mod's own environment
function __tl.eval(id, text)
    local mod = mods[id]
    if not mod then return "that mod isn't running (save + run it first)" end
    local name, rest = text:match("^%s*(%S+)%s*(.-)%s*$")
    if name and mod.commands[name] then
        guarded(mod, name, mod.commands[name], rest)
        return ""
    end
    local chunk = load("return " .. text, "=console", "t", mod.env)
    if not chunk then
        local err
        chunk, err = load(text, "=console", "t", mod.env)
        if not chunk then return "? " .. tostring(err) end
    end
    host.budget(LOAD_BUDGET)
    local r = pack(pcall(chunk))
    if not r[1] then return "! " .. tostring(r[2]) end
    if r.n < 2 then return "" end
    return "= " .. text_of(unpack(r, 2, r.n))
end

function __tl.running()
    local out = {}
    for i, id in ipairs(order) do out[i] = id end
    return out
end
