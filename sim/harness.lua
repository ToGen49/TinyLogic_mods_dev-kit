-- sim/harness.lua
--
-- Runs a mod the way the game does (through prelude.lua, never around it) and
-- gives a test file something to hold on to: a `sim` control object and a set
-- of assertions.
--
-- The test file runs BEFORE the mod is loaded, so it can put parts on the board
-- first; it calls sim.load() when it wants the mod to start.

local json = ...

local Harness = {}
Harness.__index = Harness

-- ---------------------------------------------------------------------------
-- path helpers

local function isabs(p) return p:sub(1, 1) == "/" end

local function dirname(p)
    local d = p:match("^(.*)/[^/]*$")
    if not d or d == "" then return "." end
    return d
end

local function join(a, b)
    if a:sub(-1) == "/" then return a .. b end
    return a .. "/" .. b
end

local function normalise(p)
    local abs = isabs(p)
    local out = {}
    for seg in p:gmatch("[^/]+") do
        if seg == ".." then
            if #out > 0 and out[#out] ~= ".." then
                table.remove(out)
            elseif not abs then
                out[#out + 1] = ".."
            end
        elseif seg ~= "." then
            out[#out + 1] = seg
        end
    end
    local s = table.concat(out, "/")
    if abs then return "/" .. s end
    return s ~= "" and s or "."
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- ---------------------------------------------------------------------------
-- formatting

local function fmt(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" then
        if #v > 60 then return string.format("%q...(%d chars)", v:sub(1, 60), #v) end
        return string.format("%q", v)
    end
    if t ~= "table" then return tostring(v) end
    if depth > 2 then return "{...}" end
    local array = #v > 0
    local parts = {}
    if array then
        for i = 1, math.min(#v, 12) do parts[#parts + 1] = fmt(v[i], depth + 1) end
        if #v > 12 then parts[#parts + 1] = "..." end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for i = 1, math.min(#keys, 12) do
        local k = keys[i]
        local raw = v[k] or v[tonumber(k)]
        parts[#parts + 1] = k .. " = " .. fmt(raw, depth + 1)
    end
    if #keys > 12 then parts[#parts + 1] = "..." end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function deep_eq(a, b, depth)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    depth = depth or 0
    if depth > 6 then return true end
    for k, v in pairs(a) do
        if not deep_eq(v, b[k], depth + 1) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function as_text(hay)
    if type(hay) == "table" then
        local parts = {}
        for _, x in ipairs(hay) do parts[#parts + 1] = tostring(x) end
        return table.concat(parts, "\n")
    end
    return tostring(hay or "")
end

-- ---------------------------------------------------------------------------

function Harness.new(engine, opts)
    opts = opts or {}
    local self = setmetatable({}, Harness)
    self.engine = engine
    self.host = engine.host
    self.mod_dir = opts.mod_dir
    self.kit_root = opts.kit_root
    self.test_dir = opts.test_dir
    self.dt = opts.dt or (1 / 60)
    self.results = {}
    self.passed, self.failed = 0, 0
    self.frame_errors = {}
    self.loaded = {}
    self.main_id = nil
    self.expect_faults = 0
    self.notes = {}
    self.quiet = opts.quiet and true or false
    return self
end

-- ---------------------------------------------------------------------------
-- running prelude entry points

-- One action == one undo step, exactly as the game groups them.
function Harness:call(fn, ...)
    self.engine:begin_action()
    local r, over = self.engine:run(fn, ...)
    self.engine:end_action()
    if not r[1] then
        self.frame_errors[#self.frame_errors + 1] =
            {message = tostring(r[2]), budget = over and true or false, t = self.engine.time}
    end
    return r, over
end

-- ---------------------------------------------------------------------------
-- loading mods

function Harness:resolve(p, base)
    if isabs(p) then return normalise(p) end
    local b = base or self.test_dir
    if b then return normalise(join(b, p)) end
    return normalise(p)
end

function Harness:resolve(p, base)
    if isabs(p) then return normalise(p) end
    local b = base or self.kit_root
    if b then return normalise(join(b, p)) end
    return normalise(p)
end

-- sim.load(folder?) -> mod id, ok, err
-- No folder: the mod given on the command line. Otherwise the path is resolved
-- against the kit root, so a test can pull in a sibling mod:
--     sim.load("examples/08-mod-library")
function Harness:load_mod(folder)
    local abs
    if folder then
        abs = self:resolve(folder, self.kit_root)
    else
        abs = self.mod_dir
        if not abs then return nil, "no mod folder to load" end
        if not isabs(abs) then abs = normalise(abs) end
    end

    local meta, err = json.read(join(abs, "mod.json"))
    if not meta then return nil, err end
    if type(meta.id) ~= "string" or meta.id == "" then
        return nil, join(abs, "mod.json") .. " has no id"
    end

    local script = read_file(join(abs, "main.lua"))
    local graph = json.read(join(abs, "graph.json"))
    if graph == nil then graph = nil end   -- no graph.json is perfectly normal

    local r = self:call(__tl.load, meta.id, script, graph)
    self.loaded[meta.id] = true
    if folder == nil then self.main_id = meta.id end
    self.main_id = self.main_id or meta.id

    if not r[1] then
        return meta.id, false, "the mod raised: " .. tostring(r[2])
    end
    if r[2] == false then
        self.notes[#self.notes + 1] =
            "the mod reported load problems for `" .. meta.id .. "` (see the log)"
    end
    return meta.id, r[2] ~= false
end

function Harness:unload(id)
    id = id or self.main_id
    if id then __tl.unload(id); self.loaded[id] = nil end
    return id
end

-- ---------------------------------------------------------------------------
-- time and events

-- Advance the virtual clock, one frame at a time, exactly like the game's
-- main loop: timers and watches, then frame, then draw, then the windows.
function Harness:tick(seconds)
    seconds = tonumber(seconds) or self.dt
    local steps = math.max(1, math.ceil(seconds / self.dt - 1e-9))
    for _ = 1, steps do
        self.engine.time = self.engine.time + self.dt
        self.engine.draws = {}
        self.engine.windows = {}
        local r = self:call(__tl.frame, self.dt)
        -- anything queued for a widget that never showed up is dropped:
        -- sim.click_button / sim.ui_set only apply to the next tick
        self.engine.clicks = {}
        self.engine.ui_values = {}
        if not r[1] then self.tick_failed = true end
    end
    return self
end

function Harness:dispatch(event, ...)
    return self:call(__tl.dispatch, event, ...)
end

function Harness:command(text)
    local r = self:call(__tl.eval, self.main_id or "", tostring(text))
    return r[2] or ""
end

-- prelude's show() prints one value at a time, space separated, and leaves a
-- top-level string unquoted. So: try the text as Lua first (numbers, booleans,
-- nil and tables all survive that round trip), then try it as a list of
-- literals, and only then give up and hand back the raw text.
local function try_eval(body)
    local chunk = load("return " .. body, "=sim", "t")
    if not chunk then return nil, false end
    local ok, val = pcall(chunk)
    if not ok then return nil, false end
    return val, true
end

local function is_literal(tok)
    if tok == "true" or tok == "false" or tok == "nil" then return true end
    if tok:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*$") then return true end
    if tok:sub(1, 1) == "\"" and tok:sub(-1) == "\"" then return true end
    if tok:sub(1, 1) == "{" then return true end
    return false
end

-- Split on spaces, but never inside a double-quoted run.
local function split_values(s)
    local out, cur, quoted, escaped = {}, {}, false, false
    for i = 1, #s do
        local c = s:sub(i, i)
        if quoted then
            cur[#cur + 1] = c
            if escaped then escaped = false
            elseif c == "\\" then escaped = true
            elseif c == "\"" then quoted = false end
        elseif c == "\"" then
            quoted = true
            cur[#cur + 1] = c
        elseif c:match("%s") then
            if #cur > 0 then out[#out + 1] = table.concat(cur); cur = {} end
        else
            cur[#cur + 1] = c
        end
    end
    if #cur > 0 then out[#out + 1] = table.concat(cur) end
    return out
end

-- Run an expression inside the mod's own environment and give the value back:
-- a number / boolean / nil / table as itself, anything else as its text.
-- Returns nil plus the raw text when the expression raised.
function Harness:eval_value(text)
    local out = self:command(text)
    if out == "" then return nil end
    if out:sub(1, 2) ~= "= " then return nil, out end
    local body = out:sub(3)

    local val, ok = try_eval(body)
    if ok then return val end

    -- several values, joined with spaces: tl.board.count() prints "3 0"
    local parts = split_values(body)
    if #parts > 1 then
        local all_literal = true
        for _, p in ipairs(parts) do
            if not is_literal(p) then all_literal = false; break end
        end
        if all_literal then
            val, ok = try_eval(table.concat(parts, ", "))
            if ok then return val end
        end
    end

    return body
end

-- ---------------------------------------------------------------------------
-- assertions

function Harness:record(ok, message, detail)
    message = message or "(unnamed check)"
    if ok then
        self.passed = self.passed + 1
        self.results[#self.results + 1] = {ok = true, message = message}
    else
        self.failed = self.failed + 1
        self.results[#self.results + 1] = {ok = false, message = message, detail = detail}
    end
    return ok
end

function Harness:assert_true(cond, message, detail)
    return self:record(cond and true or false, message, detail)
end

function Harness:assert_eq(got, want, message)
    local same = deep_eq(got, want)
    return self:record(same, message,
        same and nil or ("expected " .. fmt(want) .. ", got " .. fmt(got)))
end

function Harness:assert_neq(got, unwanted, message)
    local same = deep_eq(got, unwanted)
    return self:record(not same, message,
        same and ("did not expect " .. fmt(unwanted)) or nil)
end

function Harness:assert_near(got, want, tolerance, message)
    tolerance = tolerance or 1e-6
    local ok = type(got) == "number" and math.abs(got - want) <= tolerance
    return self:record(ok, message,
        ok and nil or ("expected about " .. tostring(want) .. " (+/- " ..
                       tostring(tolerance) .. "), got " .. fmt(got)))
end

function Harness:assert_contains(haystack, needle, message)
    local text = as_text(haystack)
    local ok = text:find(tostring(needle), 1, true) ~= nil
    return self:record(ok, message,
        ok and nil or ("no " .. string.format("%q", tostring(needle)) .. " in: " ..
                       (text ~= "" and text:gsub("\n", " | ") or "(nothing)")))
end

function Harness:assert_not_contains(haystack, needle, message)
    local text = as_text(haystack)
    local found = text:find(tostring(needle), 1, true) ~= nil
    return self:record(not found, message,
        found and ("unexpectedly found " .. string.format("%q", tostring(needle))) or nil)
end

function Harness:assert_fails(fn, message)
    local ok = pcall(fn)
    return self:record(not ok, message,
        ok and "expected an error, but the call succeeded" or nil)
end

-- ---------------------------------------------------------------------------
-- the control object handed to a test file

function Harness:build_sim()
    local H = self
    local E = self.engine
    local sim = {}

    -- -- loading ------------------------------------------------------------
    function sim.load(folder)
        local id, ok, err = H:load_mod(folder)
        if not id then error(err, 2) end
        if ok == false and err then error(err, 2) end
        return id
    end
    function sim.reload() return sim.load() end
    function sim.unload(id) return H:unload(id) end
    function sim.running() return {table.unpack(__tl.running())} end
    function sim.is_loaded(id) return H.loaded[id or H.main_id] == true end

    -- -- time and events -----------------------------------------------------
    function sim.tick(seconds) H:tick(seconds); return sim end
    function sim.frames(n) H:tick((tonumber(n) or 1) * H.dt); return sim end
    function sim.seconds(s) H:tick(s); return sim end
    function sim.time() return E.time end
    function sim.event(name, ...) H:dispatch(name, ...); return sim end

    function sim.key(name, down)
        E.keys[tostring(name):lower()] = down ~= false
        H:dispatch("key", tostring(name), down ~= false)
        return sim
    end
    function sim.click(x, y) H:dispatch("click", x, y); return sim end
    function sim.mouse(x, y, down)
        E.mouse.x, E.mouse.y, E.mouse.down = x or E.mouse.x, y or E.mouse.y, down == true
        return sim
    end
    function sim.captured(id) return E.captured[id or H.main_id or ""] == true end
    function sim.capture_on() return sim end

    -- -- the board (engine-side, so a test can set a scene up) ---------------
    local function call(op, args)
        local res, err = E.host.call(op, args or {})
        if res == nil and err then error(op .. ": " .. err, 2) end
        return res
    end
    sim.call = call

    function sim.place(kind, x, y, opts)
        local args = {name = kind, x = x, y = y}
        for k, v in pairs(opts or {}) do args[k] = v end
        return call("place", args).id
    end
    function sim.wire(a, pa, b, pb, color)
        return call("wire", {from = {a, pa}, to = {b, pb}, color = color}).id
    end
    function sim.part(id) return call("part", {part = id}) end
    function sim.parts(kind)
        local res = call("board", kind and {kinds = {kind}} or {})
        return res.parts
    end
    function sim.wires(paths) return call("board", {paths = paths and true or false}).wires end
    function sim.count()
        local st = call("state", {})
        return st.parts, st.wires
    end
    function sim.set(id, on) call("set", {part = id, on = on and true or false}); return sim end
    function sim.toggle(id)
        local p = call("part", {part = id})
        if p then call("set", {part = id, on = not p.on}) end
        return sim
    end
    function sim.read(id, pin)
        local res = call("probe", {probes = {pin ~= nil and {id, pin} or id}})
        local r = res[1]
        if not r or r.error then return nil, r and r.error end
        return r.value, r.volts
    end
    function sim.clear() call("clear", {confirm = true, level = "main"}); return sim end
    function sim.undo() call("undo", {}); return sim end
    function sim.redo() call("redo", {}); return sim end
    function sim.select(ids) call("select", {parts = ids or {}}); return sim end
    function sim.selection() return call("state", {}).selection end
    function sim.camera() return call("state", {}).camera end
    function sim.state() return call("state", {}) end
    function sim.find_space(w, h) return call("find_space", {w = w, h = h}) end
    function sim.catalog() return call("catalog", {}) end

    -- -- the mod's console ----------------------------------------------------
    function sim.command(text) return H:command(text) end
    function sim.eval(text) return H:command(text) end
    function sim.eval_value(expr) return H:eval_value(expr) end

    -- -- what the mod did -----------------------------------------------------
    function sim.log_list() return E.logs end
    function sim.logs()
        local out = {}
        for _, l in ipairs(E.logs) do out[#out + 1] = l.text end
        return table.concat(out, "\n")
    end
    function sim.logged(needle)
        for _, l in ipairs(E.logs) do
            if l.text:find(tostring(needle), 1, true) then return true end
        end
        return false
    end
    function sim.toasts() return E.toasts end
    function sim.sounds() return E.sounds end
    function sim.notes() return E.notes end
    function sim.draws() return E.draws end
    function sim.windows() return E.windows end
    function sim.frame_errors() return H.frame_errors end

    function sim.errors(id)
        if id then return __tl.errors(id) or 0 end
        local total = 0
        for _, m in ipairs(__tl.running()) do total = total + (__tl.errors(m) or 0) end
        return total
    end
    function sim.warns()
        local n = 0
        for _, l in ipairs(E.logs) do if l.level == 1 then n = n + 1 end end
        return n
    end
    function sim.allow_faults() H.expect_faults = math.huge; return sim end
    function sim.expect_faults(n) H.expect_faults = tonumber(n) or 0; return sim end

    -- -- driving the UI a mod opened ------------------------------------------
    -- Queue for the next tick only: sim.click_button("build") sim.tick()
    function sim.click_button(label)
        E.clicks[#E.clicks + 1] = label
        return sim
    end
    function sim.ui_set(label, value)
        E.ui_values[label] = value
        return sim
    end
    function sim.window(title)
        for _, w in ipairs(E.windows) do
            if w.title == title then return w end
        end
        return nil
    end
    -- Exact `label` match first, then a label widget whose text contains the
    -- needle: tl.ui.label() records its words as `text`, not as `label`.
    function sim.widget(needle)
        local loose
        for _, w in ipairs(E.windows) do
            for _, widget in ipairs(w.widgets) do
                if widget.label == needle then return widget end
                if not loose and widget.text
                   and tostring(widget.text):find(tostring(needle), 1, true) then
                    loose = widget
                end
            end
        end
        return loose
    end
    function sim.widgets()
        local out = {}
        for _, w in ipairs(E.windows) do
            for _, widget in ipairs(w.widgets) do out[#out + 1] = widget end
        end
        return out
    end

    -- -- persistence -----------------------------------------------------------
    function sim.store(id)
        id = id or H.main_id
        E.stores[id] = E.stores[id] or {}
        return E.stores[id]
    end
    function sim.store_value(key, id)
        local s = E.stores[id or H.main_id]
        return s and s[key]
    end

    -- -- misc ------------------------------------------------------------------
    function sim.path(rel) return H:resolve(rel) end
    function sim.mod_id() return H.main_id end
    function sim.engine() return E end
    function sim.note(text) H.notes[#H.notes + 1] = text; return sim end
    function sim.node_types()
        local out = {}
        for _, t in ipairs(__tl.catalog()) do out[#out + 1] = t.id end
        return out
    end
    function sim.node_info(id)
        for _, t in ipairs(__tl.catalog()) do
            if t.id == id then return t end
        end
        return nil
    end
    function sim.nodes() return __tl.catalog() end

    return sim
end

-- ---------------------------------------------------------------------------
-- the globals a test file sees

function Harness:build_env()
    local H = self
    local sim = self:build_sim()
    local env = setmetatable({}, {__index = _G})

    env.sim = sim
    env.print = function(...) io.write(table.concat({...}, "\t"), "\n") end

    env.ok = function(cond, message)
        return H:assert_true(cond, message)
    end
    env.eq = function(got, want, message)
        return H:assert_eq(got, want, message)
    end
    env.neq = function(got, unwanted, message)
        return H:assert_true(not deep_eq(got, unwanted), message,
            "did not expect " .. fmt(unwanted))
    end
    env.near = function(got, want, tolerance, message)
        return H:assert_near(got, want, tolerance, message)
    end
    env.contains = function(haystack, needle, message)
        return H:assert_contains(haystack, needle, message)
    end
    env.not_contains = function(haystack, needle, message)
        return H:assert_not_contains(haystack, needle, message)
    end
    env.fails = function(fn, message)
        return H:assert_fails(fn, message)
    end
    env.logged = function(needle, message)
        return H:assert_contains(sim.logs(), needle, message or ("logs mention " .. tostring(needle)))
    end
    env.no_faults = function(message)
        local n = sim.errors()
        return H:record(n <= H.expect_faults, message or "the mod did not fault",
            n > H.expect_faults and (n .. " fault(s): see the log below") or nil)
    end
    env.note = function(text) H.notes[#H.notes + 1] = text; return true end
    env.fmt = fmt

    return env, sim
end

-- ---------------------------------------------------------------------------
-- reporting

function Harness:total_faults()
    local total = 0
    for _, id in ipairs(__tl.running()) do
        total = total + (__tl.errors(id) or 0)
    end
    for _, fe in ipairs(self.frame_errors) do
        -- a budget fault is already counted by prelude as a mod error
        if not fe.budget then total = total + 1 end
    end
    return total
end

function Harness:report(label)
    local lines = {}
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== " .. (label or self.mod_dir or "sim")

    for _, n in ipairs(self.notes) do lines[#lines + 1] = "   note: " .. n end

    for _, r in ipairs(self.results) do
        if r.ok then
            lines[#lines + 1] = "   ok    " .. r.message
        else
            lines[#lines + 1] = "   FAIL  " .. r.message
            if r.detail then lines[#lines + 1] = "         " .. r.detail end
        end
    end

    local faults = self:total_faults()
    local fault_ok = faults <= self.expect_faults

    lines[#lines + 1] = "   ----"
    lines[#lines + 1] = string.format("   %d passed, %d failed", self.passed, self.failed)

    if #self.frame_errors > 0 then
        lines[#lines + 1] = string.format("   %d error(s) escaped prelude:", #self.frame_errors)
        for _, fe in ipairs(self.frame_errors) do
            lines[#lines + 1] = "      " .. (fe.budget and "[budget] " or "") .. fe.message
        end
    end

    if fault_ok then
        lines[#lines + 1] = string.format("   mod faults: %d", faults)
    else
        lines[#lines + 1] = string.format(
            "   FAIL  the mod faulted %d time(s) (allowed %s)",
            faults, self.expect_faults == math.huge and "any" or tostring(self.expect_faults))
        for _, l in ipairs(self.engine.logs) do
            if l.level >= 2 then lines[#lines + 1] = "      [" .. l.mod .. "] " .. l.text end
        end
    end

    local ok = self.failed == 0 and fault_ok and #self.frame_errors == 0
    lines[#lines + 1] = "   " .. (ok and "PASS" or "FAIL")

    print(table.concat(lines, "\n"))
    return ok, self.passed, self.failed, faults
end

Harness.dirname = dirname
Harness.normalise = normalise

return Harness
