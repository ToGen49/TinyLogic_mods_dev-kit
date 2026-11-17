-- sim/run.lua
--
-- Entry point for tools/tl-sim.
--
--   lua5.5 sim/run.lua <mod-folder>                 smoke run
--   lua5.5 sim/run.lua <mod-folder> --test FILE     run a test file
--
-- Everything mod-side runs inside the game's own prelude.lua: the real sandbox,
-- the real budgets, the real graph compiler. This file only supplies a fake
-- `host.*`, which is the entire engine boundary the game defines.

-- ---------------------------------------------------------------------------
-- paths

local self_path = arg and arg[0] or "sim/run.lua"
local SIM_DIR = self_path:match("^(.*)/[^/]*$") or "."
local KIT_ROOT = SIM_DIR:match("^(.*)/[^/]*$")
if not KIT_ROOT or KIT_ROOT == "" then KIT_ROOT = "." end

local function die(msg, code)
    io.stderr:write("tl-sim: " .. msg .. "\n")
    os.exit(code or 2)
end

local function isfile(p)
    local f = io.open(p, "rb")
    if f then f:close(); return true end
    return false
end

local function join(a, b)
    if a:sub(-1) == "/" then return a .. b end
    return a .. "/" .. b
end

-- ---------------------------------------------------------------------------
-- options

local USAGE = [[
tl-sim -- run a Tiny Logic mod without starting the game

  tl-sim <mod-folder>                  smoke run: load, run 2 s, report
  tl-sim <mod-folder> --test FILE      run a test file against the mod
  tl-sim --all                         run every test in sim/tests/

options
  --test FILE      test file to run (see sim/README.md for the format)
  --seconds N      how long a smoke run lasts (default 2)
  --fps N          frame rate (default 60)
  --no-budget      do not enforce the instruction budgets
  --prelude PATH   use this prelude.lua
  --install PATH   game install folder (used to find prelude.lua)
  --no-logs        do not print the mod's log lines in a smoke run
  --quiet          print only the final summary
  -h, --help       this text

prelude.lua is found in this order: --prelude, --install, $TINYLOGIC_INSTALL,
the usual game locations, then the copy bundled with this kit.
]]

local opts = {
    seconds = 2, fps = 60, budget = true,
    no_logs = false, quiet = false,
    test = nil, prelude = nil, install = nil,
}

local pos = {}
local i = 1
while i <= #arg do
    local a = arg[i]
    local function value()
        i = i + 1
        if not arg[i] then die(a .. " needs a value") end
        return arg[i]
    end
    if a == "-h" or a == "--help" then
        io.write(USAGE); os.exit(0)
    elseif a == "--test" then opts.test = value()
    elseif a == "--seconds" then opts.seconds = tonumber(value()) or die("--seconds needs a number")
    elseif a == "--fps" then opts.fps = tonumber(value()) or die("--fps needs a number")
    elseif a == "--prelude" then opts.prelude = value()
    elseif a == "--install" then opts.install = value()
    elseif a == "--no-budget" then opts.budget = false
    elseif a == "--no-logs" then opts.no_logs = true
    elseif a == "--quiet" then opts.quiet = true
    elseif a:sub(1, 1) == "-" then die("unknown option " .. a .. "\n\n" .. USAGE, 2)
    else pos[#pos + 1] = a end
    i = i + 1
end

if #pos == 0 then io.stderr:write(USAGE); os.exit(2) end
local MOD_DIR = pos[1]
if #pos > 1 then die("only one mod folder, got: " .. table.concat(pos, ", ")) end
if not isfile(join(MOD_DIR, "mod.json")) then
    die("no mod.json in " .. MOD_DIR .. " -- is that a mod folder?")
end

-- ---------------------------------------------------------------------------
-- find prelude.lua

local function list_dir(path)
    local p = io.popen('ls -1 "' .. path .. '" 2>/dev/null')
    if not p then return {} end
    local out = {}
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local function find_prelude()
    if opts.prelude then
        if isfile(opts.prelude) then return opts.prelude, "--prelude" end
        die("--prelude: no such file " .. opts.prelude)
    end

    local roots = {}
    local function add_install(p, why)
        if not p or p == "" then return end
        local direct = join(p, "assets/mods/prelude.lua")
        if isfile(direct) then roots[#roots + 1] = {direct, why} end
        local flat = join(p, "prelude.lua")
        if isfile(flat) then roots[#roots + 1] = {flat, why} end
    end

    if opts.install then add_install(opts.install, "--install") end
    add_install(os.getenv("TINYLOGIC_INSTALL"), "$TINYLOGIC_INSTALL")

    if not opts.install then
        local home = os.getenv("HOME") or ""
        local xdg = os.getenv("XDG_DATA_HOME") or (home ~= "" and join(home, ".local/share") or nil)
        local bases = {}
        if xdg then bases[#bases + 1] = join(xdg, "Mazell/TinyLogic") end
        if home ~= "" then
            bases[#bases + 1] = join(home, "Games")
            bases[#bases + 1] = home
        end
        for _, base in ipairs(bases) do
            -- one level of version folders: beta/<version>/, stable/<version>/, ...
            for _, branch in ipairs(list_dir(base)) do
                local b = join(base, branch)
                add_install(b, "auto-detected")
                for _, version in ipairs(list_dir(b)) do
                    add_install(join(b, version), "auto-detected")
                end
            end
        end
    end

    if roots[1] then return roots[1][1], roots[1][2] end

    local bundled = join(SIM_DIR, "prelude.lua")
    if isfile(bundled) then return bundled, "bundled with this kit" end
    die("could not find prelude.lua.\n"
        .. "  pass --install <game folder>, or --prelude <file>, or\n"
        .. "  run tools/sync-api.sh --install <game folder> to copy it into sim/.")
end

local prelude_path, prelude_how = find_prelude()

-- ---------------------------------------------------------------------------
-- modules

local function load_module(name, ...)
    local path = join(SIM_DIR, name)
    local chunk, err = loadfile(path, "t")
    if not chunk then die("can't compile " .. path .. ": " .. tostring(err)) end
    local ok, value = xpcall(chunk, function(e) return tostring(e) end, ...)
    if not ok then die("can't run " .. path .. ": " .. tostring(value)) end
    return value
end

local json = load_module("json.lua")
local Catalog = load_module("catalog.lua")
local Engine = load_module("engine.lua", Catalog)
local Harness = load_module("harness.lua", json)

-- ---------------------------------------------------------------------------
-- boot the real prelude

local engine = Engine.new(Catalog, {budget = opts.budget})

_G.__host = engine.host

local prelude_chunk, perr = loadfile(prelude_path, "t")
if not prelude_chunk then die("can't compile " .. prelude_path .. ": " .. tostring(perr)) end

local ok, err = xpcall(prelude_chunk, function(e) return tostring(e) end)
if not ok then die("prelude.lua failed to run: " .. tostring(err)) end
if type(__tl) ~= "table" then
    die("prelude.lua ran but did not expose __tl -- is it a game prelude?")
end

local harness = Harness.new(engine, {
    mod_dir = MOD_DIR,
    kit_root = KIT_ROOT,
    dt = 1 / opts.fps,
    quiet = opts.quiet,
})

-- ---------------------------------------------------------------------------

local function print_logs()
    if opts.no_logs then return end
    local logs = engine.logs
    if #logs == 0 then
        print(" -- log -- (nothing)")
        return
    end
    print(" -- log --")
    for _, l in ipairs(logs) do
        local mark = l.level >= 2 and "!!" or (l.level == 1 and " !" or "  ")
        print(string.format(" %s %6.2f [%s] %s", mark, l.t, l.mod, l.text))
    end
end

local function smoke()
    local id, ok_load, err_load = harness:load_mod()
    if not id then die(tostring(err_load)) end
    if not ok_load then
        print("note: the mod reported load problems (see the log)")
    end

    local frames = math.max(1, math.ceil(opts.seconds * opts.fps))
    harness:tick(frames * (1 / opts.fps))

    if not opts.quiet then
        print("== smoke: " .. MOD_DIR)
        print(string.format("   prelude : %s (%s)", prelude_path, prelude_how))
        print(string.format("   mod     : %s", id))
        print(string.format("   ran     : %d frames in %.2f s of virtual time", frames, opts.seconds))
        print_logs()
    end

    local st = engine:op_state()
    local faults, warnings = 0, 0
    for _, l in ipairs(engine.logs) do
        if l.level >= 2 then faults = faults + 1
        elseif l.level == 1 then warnings = warnings + 1 end
    end

    print(string.format(
        "   parts: %d · wires: %d · windows: %d · toasts: %d · warnings: %d · faults: %d",
        st.parts, st.wires, #engine.windows, #engine.toasts, warnings, faults))

    if #harness.frame_errors > 0 then
        print(string.format("   %d error(s) escaped prelude:", #harness.frame_errors))
        for _, fe in ipairs(harness.frame_errors) do
            print("      " .. (fe.budget and "[budget] " or "") .. fe.message)
        end
    end

    local passed = faults == 0 and #harness.frame_errors == 0
    print(passed and "   PASS" or "   FAIL")
    return passed
end

local function run_test()
    if not opts.test then die("--test needs a file") end
    local env, sim = harness:build_env()

    local chunk, terr = loadfile(opts.test, "t", env)
    if not chunk then die("can't compile the test: " .. tostring(terr)) end

    local ok, e = xpcall(chunk, function(m) return tostring(m) end)
    if not ok then
        harness:record(false, "the test file itself raised", tostring(e))
    end

    if next(harness.loaded) == nil then
        harness.notes[#harness.notes + 1] =
            "the test never called sim.load() -- the mod was loaded afterwards"
        harness:load_mod()
        harness:tick(1 / opts.fps)
    end

    local passed = harness:report(MOD_DIR .. "  (test: " .. opts.test .. ")")
    if not opts.quiet then
        print(string.format("   prelude: %s (%s)", prelude_path, prelude_how))
    end
    return passed
end

local passed
if opts.test then
    passed = run_test()
else
    passed = smoke()
end

os.exit(passed and 0 or 1)
