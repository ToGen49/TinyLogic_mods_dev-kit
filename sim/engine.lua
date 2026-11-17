-- sim/engine.lua
--
-- Answers every `host.*` question the game's prelude.lua asks, over an
-- in-memory board. Mod code never runs here: it runs inside prelude.lua's real
-- sandbox, and this file only responds to it.
--
-- Circuit model -- a deliberate approximation (see sim/README.md):
--   * wires join pins into nets (union-find)
--   * power / ground / switch / button / number / clock drive their output net
--   * and / or / not / nand / nor / xor / xnor / buffer reach a fixpoint
--   * resistors and friends pass their input net through to their output
--   * lights / displays read their input net
--   * transistors and other analogue parts are NOT modelled: they read 0

-- Loaded as `loadfile(path)(Catalog)`: the chunk takes the catalogue as its
-- first vararg and returns the Engine table.
local Catalog = ...

local FRAME_STEP = 1 / 60

-- ---------------------------------------------------------------------------
-- small helpers

-- Parts arrive either as an id or as a part table, all the way down.
local function part_id_of(v)
    if type(v) == "table" then return v.id end
    return v
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = copy(val) end
    return out
end

local function title_of(kind)
    return (tostring(kind):gsub("(%a)([%w_]*)", function(a, b) return a:upper() .. b end))
end

local function endpoint_key(pid, pin)
    -- pins stay well under 2^20, part ids under 2^40: unique without strings
    return (pid or 0) * 1048576 + (pin or 0)
end

-- ---------------------------------------------------------------------------
-- the engine

local Engine = {}
Engine.__index = Engine

function Engine.new(catalog, opts)
    opts = opts or {}
    local self = setmetatable({}, Engine)
    self.catalog = catalog or Catalog

    self.time = 0.0
    self.parts = {}
    self.by_id = {}
    self.next_id = 1
    self.wires = {}
    self.wire_by_id = {}
    self.next_wire = 1

    self.project = "sim"
    self.level = "main"
    self.camera = {x = 0, y = 0, zoom = 1}
    self.selection = {}
    self.short_circuit = false
    self.unstable = false
    self.clock_running = true
    self.clock_speed = 5

    self.stores = {}
    self.logs = {}
    self.toasts = {}
    self.sounds = {}
    self.notes = {}
    self.draws = {}
    self.windows = {}
    self.cur = nil

    self.clicks = {}       -- button labels that "click" during the next tick
    self.ui_values = {}    -- label -> value forced into the next toggle/slider
    self.keys = {}
    self.mouse = {x = 0, y = 0, down = false}
    self.captured = {}     -- mod id -> key capture on/off

    self.undo_stack = {}
    self.redo_stack = {}
    self.in_action = false
    self.action_taken = false

    self.net_cache = nil
    self.budget_on = opts.budget ~= false
    self.ctx = {armed = false, over = false, limit = 0}

    self.host = self:_make_host()
    return self
end

-- ---------------------------------------------------------------------------
-- instruction budgets
--
-- prelude.lua calls host.budget(n) right before running one handler, and asks
-- host.over() afterwards to tell "out of time" apart from an ordinary error.
-- A Lua count hook gives us exactly that, and it fires only while a handler is
-- actually running: Engine:run() disarms it again on the way out, so the hook
-- can never blow up the harness's own code.

function Engine:budget(n)
    local ctx = self.ctx
    ctx.limit = n
    ctx.over = false
    if not self.budget_on then return end
    ctx.armed = true
    debug.sethook(function()
        if not ctx.armed then
            debug.sethook()
            return
        end
        ctx.armed = false
        ctx.over = true
        debug.sethook()
        error("instruction budget exceeded (" .. tostring(ctx.limit) .. " instructions)", 0)
    end, "", n)
end

function Engine:over()
    return self.ctx.over
end

-- Run one prelude entry point. Returns (packed results, budget_was_hit).
function Engine:run(fn, ...)
    debug.sethook()
    self.ctx.armed = false
    self.ctx.over = false
    local r = table.pack(xpcall(fn, function(e)
        if type(e) ~= "string" then e = tostring(e) end
        return e
    end, ...))
    local over = self.ctx.over
    debug.sethook()
    self.ctx.armed = false
    self.ctx.over = false
    return r, over
end

-- Everything a mod does inside one action (one command, one timer tick, one
-- load) lands in the player's undo history as a single step -- which is what
-- the game's own documentation promises.
function Engine:begin_action()
    self.in_action = true
    self.action_taken = false
end

function Engine:end_action()
    self.in_action = false
    self.action_taken = false
end

-- ---------------------------------------------------------------------------
-- undo / redo (snapshot based: simple, and the boards here are small)

local function snapshot(self)
    local s = {
        parts = {}, wires = {}, selection = copy(self.selection),
        next_id = self.next_id, next_wire = self.next_wire,
        camera = copy(self.camera),
    }
    for _, p in ipairs(self.parts) do s.parts[#s.parts + 1] = copy(p) end
    for _, w in ipairs(self.wires) do s.wires[#s.wires + 1] = copy(w) end
    return s
end

local function restore(self, s)
    self.parts, self.by_id = {}, {}
    for _, p in ipairs(s.parts) do
        self.parts[#self.parts + 1] = p
        self.by_id[p.id] = p
    end
    self.wires, self.wire_by_id = {}, {}
    for _, w in ipairs(s.wires) do
        self.wires[#self.wires + 1] = w
        self.wire_by_id[w.id] = w
    end
    self.selection = copy(s.selection)
    self.next_id, self.next_wire = s.next_id, s.next_wire
    self.camera = copy(s.camera)
    self.net_cache = nil
end

function Engine:txn()
    -- one snapshot per action, taken just before its first mutation
    if self.in_action and self.action_taken then return end
    self.undo_stack[#self.undo_stack + 1] = snapshot(self)
    if #self.undo_stack > 64 then table.remove(self.undo_stack, 1) end
    self.redo_stack = {}
    self.action_taken = true
end

function Engine:op_undo()
    local s = table.remove(self.undo_stack)
    if not s then return nil end
    self.redo_stack[#self.redo_stack + 1] = snapshot(self)
    restore(self, s)
    return nil
end

function Engine:op_redo()
    local s = table.remove(self.redo_stack)
    if not s then return nil end
    self.undo_stack[#self.undo_stack + 1] = snapshot(self)
    restore(self, s)
    return nil
end

-- ---------------------------------------------------------------------------
-- the circuit approximation

-- Wires merge pins into nets; nets carry a 0/1 (or a number) value.
function Engine:nets()
    if self.net_cache then return self.net_cache end

    local parent = {}
    local function find(k)
        local r = parent[k]
        if not r then parent[k] = k; return k end
        if r ~= k then parent[k] = find(r) end
        return parent[k]
    end
    local function union(a, b)
        local ra, rb = find(a), find(b)
        if ra ~= rb then parent[ra] = rb end
    end

    for _, w in ipairs(self.wires) do
        union(endpoint_key(w.from[1], w.from[2]), endpoint_key(w.to[1], w.to[2]))
    end
    for _, p in ipairs(self.parts) do
        for i = 1, #p.pins do find(endpoint_key(p.id, i - 1)) end
    end

    local vals = {}
    local function get(p, pin)
        if pin == nil then return nil end
        local k = endpoint_key(p.id, pin)
        if parent[k] == nil then return nil end
        return vals[find(k)]
    end
    local function set(p, pin, v)
        if pin == nil then return end
        local k = endpoint_key(p.id, pin)
        if parent[k] == nil then find(k) end
        vals[find(k)] = v
    end

    -- rails and sources drive their own output net
    for _, p in ipairs(self.parts) do
        local def = self.catalog.get(p.kind)
        if (def.role == "rail" or def.role == "source") and def.out_pin then
            set(p, def.out_pin, self:own_value(p, def))
        end
    end

    -- combinational logic, until nothing changes any more
    for _ = 1, 64 do
        local changed = false
        for _, p in ipairs(self.parts) do
            local def = self.catalog.get(p.kind)
            if def.role == "passive" and def.out_pin then
                local v = get(p, def.in_pins and def.in_pins[1]) or 0
                if get(p, def.out_pin) ~= v then set(p, def.out_pin, v); changed = true end
            elseif def.role == "gate" and def.out_pin then
                local a = get(p, def.in_pins[1]) or 0
                local b = get(p, def.in_pins[2]) or 0
                local v = def.eval(a == 1 and 1 or 0, b == 1 and 1 or 0)
                if get(p, def.out_pin) ~= v then set(p, def.out_pin, v); changed = true end
            end
        end
        if not changed then break end
    end

    local N = {get = get, set = set, vals = vals, key = endpoint_key, find = find}
    self.net_cache = N
    return N
end

-- What a source contributes to its own output net.
function Engine:own_value(p, def)
    if def.role == "rail" then return def.value or 0 end
    local kind = self.catalog.norm(p.kind)
    if kind == "number" then return tonumber(p.value) or 0 end
    if kind == "clock" then
        if not self.clock_running then return p.on and 1 or 0 end
        local hz = tonumber(p.settings and p.settings.hz) or def.hz or 1
        if hz <= 0 then hz = 1 end
        return (math.floor(self.time * hz) % 2 == 0) and 1 or 0
    end
    return p.on and 1 or 0
end

-- What a whole-part probe reports (`tl.sim.read(id)`).
function Engine:display_value(p)
    local def = self.catalog.get(p.kind)
    if def.role == "rail" or def.role == "source" then
        return self:own_value(p, def)
    end
    local N = self:nets()
    if def.role == "sink" then
        local pin = def.in_pins and def.in_pins[1]
        local v = pin and N.get(p, pin)
        if v ~= nil then return v end
        return tonumber(p.value) or 0
    end
    local v = def.out_pin and N.get(p, def.out_pin)
    if v ~= nil then return v end
    return 0
end

-- What one pin carries (`tl.sim.read(id, pin)`).
function Engine:pin_value(p, pin, N)
    if pin == nil then return self:display_value(p) end
    N = N or self:nets()
    local v = N.get(p, pin)
    if v == nil then
        local def = self.catalog.get(p.kind)
        if def.out_pin == pin and (def.role == "source" or def.role == "rail") then
            v = self:own_value(p, def)
        end
    end
    return v or 0
end

-- Volts: a high digital net reads 5 V, anything else reads itself.
local function volts_of(v)
    if v == 0 or v == 1 then return v * 5 end
    return tonumber(v) or 0
end

function Engine:amps_of(p)
    if self.catalog.norm(p.kind) == "resistor" then
        local r = tonumber(p.settings and p.settings.ohms) or 1000
        if r <= 0 then return 0 end
        return volts_of(self:pin_value(p, 0)) / r
    end
    return tonumber(p.amps) or 0
end

-- ---------------------------------------------------------------------------
-- parts

function Engine:find_space(w, h, near)
    w = math.max(1, math.floor(tonumber(w) or 1))
    h = math.max(1, math.floor(tonumber(h) or 1))
    local function free(x, y)
        for _, p in ipairs(self.parts) do
            if x < p.x + p.w and p.x < x + w and y < p.y + p.h and p.y < y + h then
                return false
            end
        end
        return true
    end
    local x0, y0 = 0, 0
    if type(near) == "table" then
        x0, y0 = math.floor(tonumber(near[1]) or 0), math.floor(tonumber(near[2]) or 0)
    end
    if free(x0, y0) then return x0, y0 end
    for r = 1, 512 do
        for dx = -r, r do
            if free(x0 + dx, y0 - r) then return x0 + dx, y0 - r end
            if free(x0 + dx, y0 + r) then return x0 + dx, y0 + r end
        end
        for dy = -r + 1, r - 1 do
            if free(x0 - r, y0 + dy) then return x0 - r, y0 + dy end
            if free(x0 + r, y0 + dy) then return x0 + r, y0 + dy end
        end
    end
    return nil, nil
end

-- A pin by its number (they count from 0) or by name, mirroring prelude's pin_of.
local function resolve_pin(p, pin)
    if type(pin) == "number" then
        local n = math.floor(pin)
        if n >= 0 and n < #p.pins then return n end
        return -1
    end
    if type(pin) ~= "string" then return -1 end
    local want = pin:lower()
    for i, q in ipairs(p.pins) do
        if tostring(q.name):lower() == want then return i - 1 end
    end
    for i, q in ipairs(p.pins) do
        if tostring(q.name):lower():find(want, 1, true) then return i - 1 end
    end
    return -1
end

function Engine:part_out(p)
    local names = {}
    for i = 1, #p.pins do names[i] = p.pins[i].name end
    return {
        id = p.id, kind = p.kind, name = p.name,
        x = p.x, y = p.y, w = p.w, h = p.h,
        rot = p.rot, flip = p.flip,
        on = p.on, value = p.value, number = p.number,
        bits = p.bits, label = p.label, color = p.color,
        pins = copy(p.pins), pin_names = names,
        settings = copy(p.settings), setting_names = copy(p.setting_names),
        amps = self:amps_of(p),
        level = p.level,
    }
end

function Engine:op_place(a)
    if type(a) ~= "table" then return nil, "place needs a table of options" end
    local kind = a.name or a.chip
    if not kind or kind == "" then return nil, "place needs a part name" end

    local def = self.catalog.get(kind)
    local w, h = def.w or 1, def.h or 1
    local x, y
    if a.x ~= nil and a.y ~= nil then
        x, y = math.floor(a.x), math.floor(a.y)
    else
        x, y = self:find_space(w, h)
    end
    if not x then return nil, "no room for a " .. tostring(kind) end

    self:txn()
    local pins = {}
    for i, name in ipairs(def.pins) do pins[i] = {pin = i - 1, name = name} end
    local settings, setting_names = self.catalog.settings_for(kind)

    local p = {
        id = self.next_id, kind = kind, name = title_of(kind),
        x = x, y = y, w = w, h = h,
        rot = 0, flip = false,
        on = a.on and true or false,
        value = tonumber(a.number) or 0,
        number = tonumber(a.number) or 0,
        bits = tonumber(a.bits) or 1,
        label = a.label or "",
        color = a.color or 0,
        pins = pins,
        settings = settings, setting_names = setting_names,
        amps = 0,
        level = self.level,
    }
    self.next_id = self.next_id + 1
    self.parts[#self.parts + 1] = p
    self.by_id[p.id] = p
    self.net_cache = nil
    return self:part_out(p)
end

function Engine:op_part(a)
    local p = self.by_id[a.part]
    if not p then return nil end
    return self:part_out(p)
end

function Engine:op_probe(a)
    local out = {}
    local N = self:nets()
    for i, pr in ipairs(a.probes or {}) do
        local pid, pin
        if type(pr) == "table" then pid, pin = pr[1], pr[2] else pid = pr end
        local p = self.by_id[pid]
        if not p then
            out[i] = {error = "no part " .. tostring(pid)}
        else
            local v = self:pin_value(p, pin, N)
            out[i] = {value = v, volts = volts_of(v)}
        end
    end
    return out
end

function Engine:op_wire(a)
    local from, to = a.from, a.to
    if type(from) ~= "table" or type(to) ~= "table" then
        return nil, "wire needs from = {part, pin} and to = {part, pin}"
    end
    local fp, tp = self.by_id[from[1]], self.by_id[to[1]]
    if not fp then return nil, "no part " .. tostring(from[1]) end
    if not tp then return nil, "no part " .. tostring(to[1]) end

    local fpin, tpin = resolve_pin(fp, from[2]), resolve_pin(tp, to[2])
    if fpin < 0 then return nil, "part " .. fp.id .. " has no pin " .. tostring(from[2]) end
    if tpin < 0 then return nil, "part " .. tp.id .. " has no pin " .. tostring(to[2]) end

    self:txn()
    local w = {
        id = self.next_wire,
        from = {fp.id, fpin},
        to = {tp.id, tpin},
        color = a.color or 0,
    }
    w.path = {
        fp.x * 16 + fp.w * 8, fp.y * 16 + fp.h * 8,
        tp.x * 16 + tp.w * 8, tp.y * 16 + tp.h * 8,
    }
    self.next_wire = self.next_wire + 1
    self.wires[#self.wires + 1] = w
    self.wire_by_id[w.id] = w
    self.net_cache = nil
    return {id = w.id}
end

function Engine:op_delete(a)
    local n = 0
    if type(a.parts) == "table" then
        local doomed = {}
        for _, id in ipairs(a.parts) do
            local p = self.by_id[part_id_of(id)]
            if p then doomed[p.id] = true end
        end
        if next(doomed) then
            self:txn()
            local keep = {}
            for _, p in ipairs(self.parts) do
                if doomed[p.id] then n = n + 1 else keep[#keep + 1] = p end
            end
            self.parts = keep
            for id in pairs(doomed) do self.by_id[id] = nil end
            local kw = {}
            for _, w in ipairs(self.wires) do
                if doomed[w.from[1]] or doomed[w.to[1]] then
                    self.wire_by_id[w.id] = nil
                else
                    kw[#kw + 1] = w
                end
            end
            self.wires = kw
        end
    end
    if type(a.wires) == "table" then
        local doomed = {}
        for _, id in ipairs(a.wires) do
            local w = self.wire_by_id[part_id_of(id)]
            if w then doomed[w.id] = true; n = n + 1 end
        end
        if next(doomed) then
            self:txn()
            local keep = {}
            for _, w in ipairs(self.wires) do
                if not doomed[w.id] then keep[#keep + 1] = w end
            end
            self.wires = keep
            for id in pairs(doomed) do self.wire_by_id[id] = nil end
        end
    end
    self.net_cache = nil
    return {deleted = n}
end

function Engine:op_board(a)
    if a.paths ~= nil then
        local out = {}
        for _, w in ipairs(self.wires) do
            out[#out + 1] = {
                id = w.id,
                from = copy(w.from), to = copy(w.to),
                color = w.color,
                path = a.paths and copy(w.path) or nil,
                amps = a.paths and 0 or nil,
            }
        end
        return {wires = out}
    end

    local kinds
    if type(a.kinds) == "table" then
        kinds = {}
        for _, k in ipairs(a.kinds) do kinds[self.catalog.norm(k)] = true end
    end
    local out = {}
    for _, p in ipairs(self.parts) do
        if not kinds or kinds[self.catalog.norm(p.kind)] then
            out[#out + 1] = self:part_out(p)
        end
    end
    return {parts = out}
end

local SET_KEYS = {"on", "number", "bits", "value", "label", "color", "rot", "flip"}

function Engine:op_set(a)
    local p = self.by_id[part_id_of(a.part)]
    if not p then return nil, "no part " .. tostring(a.part) end
    self:txn()
    for _, k in ipairs(SET_KEYS) do
        if a[k] ~= nil then p[k] = a[k] end
    end
    if a.number ~= nil then p.value = tonumber(a.number) or p.value end
    if type(a.settings) == "table" then
        for k, v in pairs(a.settings) do p.settings[k] = v end
    end
    if p.flip == nil then p.flip = false end
    self.net_cache = nil
    return self:part_out(p)
end

function Engine:op_move(a)
    local p = self.by_id[part_id_of(a.part)]
    if not p then return nil, "no part " .. tostring(a.part) end
    self:txn()
    p.x, p.y = math.floor(a.x or p.x), math.floor(a.y or p.y)
    for _, w in ipairs(self.wires) do
        if w.from[1] == p.id then
            w.path[1], w.path[2] = p.x * 16 + p.w * 8, p.y * 16 + p.h * 8
        elseif w.to[1] == p.id then
            w.path[3], w.path[4] = p.x * 16 + p.w * 8, p.y * 16 + p.h * 8
        end
    end
    return self:part_out(p)
end

function Engine:op_rotate(a)
    for _, id in ipairs(a.parts or {}) do
        local p = self.by_id[part_id_of(id)]
        if p then
            self:txn()
            if a.flip then
                p.flip = not p.flip
            else
                p.rot = (p.rot + 1) % 4
            end
        end
    end
    return nil
end

function Engine:op_press(a)
    local p = self.by_id[part_id_of(a.part)]
    if not p then return nil, "no part " .. tostring(a.part) end
    self:txn()
    p.on = a.down and true or false
    self.net_cache = nil
    return nil
end

function Engine:op_clock(a)
    if a.speed ~= nil then self.clock_speed = tonumber(a.speed) or self.clock_speed end
    if a.action == "play" then self.clock_running = true
    elseif a.action == "pause" then self.clock_running = false
    elseif a.action == "restart" then self.time = 0
    elseif a.action == "step" then self.time = self.time + (tonumber(a.times) or 1) * 0.1 end
    local p = a.part and self.by_id[part_id_of(a.part)]
    if p and a.action then p.on = (a.action ~= "pause") end
    self.net_cache = nil
    return nil
end

function Engine:op_clear()
    self:txn()
    self.parts, self.by_id = {}, {}
    self.wires, self.wire_by_id = {}, {}
    self.selection = {}
    self.net_cache = nil
    return nil
end

function Engine:op_select(a)
    self.selection = {}
    for _, id in ipairs(a.parts or {}) do
        local p = self.by_id[part_id_of(id)]
        if p then self.selection[#self.selection + 1] = p.id end
    end
    return nil
end

function Engine:op_state()
    return {
        project = self.project, level = self.level,
        camera = copy(self.camera),
        parts = #self.parts, wires = #self.wires,
        selection = copy(self.selection),
        short_circuit = self.short_circuit,
        unstable = self.unstable,
        clock_running = self.clock_running,
        clock_speed = self.clock_speed,
        time = self.time,
    }
end

function Engine:op_camera(a)
    if a.fit then
        local minx, miny, maxx, maxy = 0, 0, 0, 0
        for _, p in ipairs(self.parts) do
            minx = math.min(minx, p.x); miny = math.min(miny, p.y)
            maxx = math.max(maxx, p.x + p.w); maxy = math.max(maxy, p.y + p.h)
        end
        local w, h = math.max(1, maxx - minx), math.max(1, maxy - miny)
        self.camera.x = (minx + w / 2) * 16
        self.camera.y = (miny + h / 2) * 16
        self.camera.zoom = math.max(0.25, math.min(4, 480 / (w * 16), 270 / (h * 16)))
    else
        if a.x ~= nil then self.camera.x = tonumber(a.x) or self.camera.x end
        if a.y ~= nil then self.camera.y = tonumber(a.y) or self.camera.y end
        if a.zoom ~= nil then self.camera.zoom = tonumber(a.zoom) or self.camera.zoom end
    end
    return nil
end

function Engine:op_focus(a)
    local sx, sy, n = 0, 0, 0
    for _, id in ipairs(a.parts or {}) do
        local p = self.by_id[part_id_of(id)]
        if p then sx, sy, n = sx + p.x, sy + p.y, n + 1 end
    end
    if n > 0 then
        self.camera.x = (sx / n) * 16
        self.camera.y = (sy / n) * 16
    end
    return nil
end

function Engine:op_find_space(a)
    local x, y = self:find_space(a.w, a.h, a.near)
    if not x then return nil, "no room for " .. tostring(a.w) .. "x" .. tostring(a.h) end
    return {x = x, y = y}
end

function Engine:op_catalog()
    return self.catalog.list()
end

function Engine:op_duplicate(a)
    local made = {}
    for _, id in ipairs(a.parts or {}) do
        local p = self.by_id[part_id_of(id)]
        if p then
            self:txn()
            local c = copy(p)
            c.id = self.next_id
            c.x, c.y = p.x + 1, p.y + 1
            self.next_id = self.next_id + 1
            self.parts[#self.parts + 1] = c
            self.by_id[c.id] = c
            made[#made + 1] = c.id
        end
    end
    self.net_cache = nil
    return {ids = made}
end

-- Best effort: api.json describes this only as "work out a circuit's truth
-- table", so we take inputs = {part ids} and outputs = {part ids} and drive
-- every combination of the inputs through the approximation above.
function Engine:op_truth_table(a)
    local inputs, outputs = a.inputs or {}, a.outputs or {}
    if #inputs == 0 then return nil, "truth_table needs inputs = {part ids}" end
    if #inputs > 12 then return nil, "truth_table: at most 12 inputs" end

    local originals = {}
    for _, id in ipairs(inputs) do
        local p = self.by_id[part_id_of(id)]
        if not p then return nil, "truth_table: no part " .. tostring(id) end
        originals[#originals + 1] = p.on
    end

    local rows = {}
    for mask = 0, 2 ^ #inputs - 1 do
        local row_in = {}
        for i, id in ipairs(inputs) do
            local p = self.by_id[part_id_of(id)]
            local on = (math.floor(mask / 2 ^ (i - 1)) % 2) == 1
            p.on = on
            row_in[i] = on and 1 or 0
        end
        self.net_cache = nil
        local row_out = {}
        for i, id in ipairs(outputs) do
            local p = self.by_id[part_id_of(id)]
            row_out[i] = p and self:display_value(p) or 0
        end
        rows[#rows + 1] = {inputs = row_in, outputs = row_out}
    end

    for i, id in ipairs(inputs) do
        local p = self.by_id[part_id_of(id)]
        p.on = originals[i]
    end
    self.net_cache = nil

    return {inputs = copy(inputs), outputs = copy(outputs), rows = rows}
end

-- ---------------------------------------------------------------------------
-- the host surface

function Engine:_make_host()
    local e = self

    local host = {}

    function host.now() return e.time end

    function host.budget(n) e:budget(n) end
    function host.over() return e:over() end

    function host.log(mod, level, text)
        e.logs[#e.logs + 1] = {
            mod = tostring(mod), level = tonumber(level) or 0,
            text = tostring(text), t = e.time,
        }
    end

    function host.call(op, args)
        local f = Engine.OPS[op]
        if not f then return nil, "the simulator does not model the op '" .. tostring(op) .. "'" end
        return f(e, args or {})
    end

    function host.measure(text, scale)
        scale = tonumber(scale) or 1
        return #tostring(text) * 6 * scale, 8 * scale
    end

    function host.viewport() return 480, 270 end

    function host.draw(kind, on_board, x, y, w, h, r, g, b, a, text, scale)
        e.draws[#e.draws + 1] = {
            kind = kind, board = on_board and true or false,
            x = x, y = y, w = w, h = h,
            r = r, g = g, b = b, a = a,
            text = text, scale = scale,
        }
    end

    function host.mouse()
        local m, cam = e.mouse, e.camera
        return m.x, m.y,
               math.floor((m.x - cam.x) / 16),
               math.floor((m.y - cam.y) / 16),
               m.down and true or false
    end

    function host.key(name)
        return e.keys[tostring(name):lower()] == true
    end

    function host.capture(mod, on)
        e.captured[tostring(mod)] = on and true or false
    end

    function host.toast(text, r, g, b)
        e.toasts[#e.toasts + 1] = {text = tostring(text), r = r, g = g, b = b, t = e.time}
    end

    function host.sound(name, pitch)
        e.sounds[#e.sounds + 1] = {name = tostring(name), pitch = pitch or 1, t = e.time}
    end

    function host.note(hz, seconds, volume, tone)
        e.notes[#e.notes + 1] = {
            hz = hz, seconds = seconds, volume = volume, tone = tone, t = e.time,
        }
    end

    function host.store_read(mod)
        return e.stores[tostring(mod)]
    end

    function host.store_write(mod, t)
        e.stores[tostring(mod)] = t
    end

    -- ---- windows ------------------------------------------------------------

    function host.ui_begin(mod, title, x, y, w)
        e.cur = {mod = tostring(mod), title = tostring(title), x = x, y = y, w = w, widgets = {}}
    end

    function host.ui_end()
        if e.cur then
            e.windows[#e.windows + 1] = e.cur
            e.cur = nil
        end
    end

    local function widget(w)
        if e.cur then e.cur.widgets[#e.cur.widgets + 1] = w end
    end

    function host.ui_label(text, r, g, b)
        widget {type = "label", text = tostring(text), color = {r, g, b}}
    end

    function host.ui_button(label)
        local hit = false
        for i, l in ipairs(e.clicks) do
            if l == label then table.remove(e.clicks, i); hit = true; break end
        end
        widget {type = "button", label = tostring(label), clicked = hit}
        return hit
    end

    function host.ui_toggle(label, value)
        local forced = e.ui_values[label]
        local out = value and true or false
        if forced ~= nil then
            out = forced and true or false
            e.ui_values[label] = nil
        end
        widget {type = "toggle", label = tostring(label), value = out, forced = forced ~= nil}
        return out
    end

    function host.ui_slider(label, value, lo, hi)
        lo = tonumber(lo) or 0
        hi = tonumber(hi) or 1
        if lo > hi then lo, hi = hi, lo end
        local out = tonumber(value) or lo
        local forced = e.ui_values[label]
        if forced ~= nil then
            out = tonumber(forced) or out
            e.ui_values[label] = nil
        end
        if out < lo then out = lo elseif out > hi then out = hi end
        widget {type = "slider", label = tostring(label), value = out, min = lo, max = hi}
        return out
    end

    function host.ui_bar(label, frac, r, g, b)
        widget {type = "bar", label = tostring(label), value = tonumber(frac) or 0, color = {r, g, b}}
    end

    function host.ui_space(px)
        widget {type = "space", px = tonumber(px) or 3}
    end

    return host
end

-- ---------------------------------------------------------------------------
-- the op table (what tl.call / every tl.* helper ends up asking for)

Engine.OPS = {
    place      = Engine.op_place,
    part       = Engine.op_part,
    probe      = Engine.op_probe,
    wire       = Engine.op_wire,
    delete     = Engine.op_delete,
    board      = Engine.op_board,
    set        = Engine.op_set,
    move       = Engine.op_move,
    rotate     = Engine.op_rotate,
    press      = Engine.op_press,
    clock      = Engine.op_clock,
    clear      = Engine.op_clear,
    select     = Engine.op_select,
    state      = Engine.op_state,
    camera     = Engine.op_camera,
    focus      = Engine.op_focus,
    find_space = Engine.op_find_space,
    catalog    = Engine.op_catalog,
    duplicate  = Engine.op_duplicate,
    truth_table = Engine.op_truth_table,
    undo       = Engine.op_undo,
    redo       = Engine.op_redo,
    wire_color = function(self, a)
        local w = self.wire_by_id[part_id_of(a.wire)]
        if not w then return nil, "no wire " .. tostring(a.wire) end
        self:txn()
        w.color = a.color or 0
        return nil
    end,
}

return Engine
