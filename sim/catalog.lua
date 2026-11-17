-- sim/catalog.lua
--
-- Part kinds the simulator understands, and how the circuit approximation
-- treats each one.
--
--   pins     pin names; index 1 holds pin 0 (pins count from 0, as the game does)
--   role     "source"   drives its output pin from its own state
--                     "rail"     a fixed 0 or 1 (power / ground)
--                     "gate"     computes its output pin from its input pins
--                     "sink"     reads its input pin (light, display)
--                     "passive"  passes its input net through to its output
--   in_pins  pins a gate / passive / sink reads
--   out_pin  the pin a source / gate / passive drives
--   value    fixed value for a "rail"
--   eval     gate function, eval(input_a, input_b) -> 0 | 1
--
-- Kinds we do not know are still placeable: they get default pins and behave
-- as passive blocks reading 0, so a mod that uses an unusual kind is not
-- blocked -- it just gets no circuit behaviour from it.

local C = {}

-- Finder names arrive in whatever case the mod used ("AND", "and_gate", ...),
-- so lookup goes through a normalised form: lowercase, no spaces / _ / -.
function C.norm(kind)
    return (tostring(kind or ""):lower():gsub("[%s_%-]", ""))
end

local function gate(pins, ins, eval)
    return {pins = pins, role = "gate", in_pins = ins, out_pin = #pins - 1, eval = eval}
end

local function bin(a, b) return a == 1 and b == 1 and 1 or 0 end

C.kinds = {
    -- rails ------------------------------------------------------------------------
    power    = {pins = {"out"}, role = "rail", value = 1, out_pin = 0},
    ground   = {pins = {"out"}, role = "rail", value = 0, out_pin = 0},
    gnd      = {pins = {"out"}, role = "rail", value = 0, out_pin = 0},
    vcc      = {pins = {"out"}, role = "rail", value = 1, out_pin = 0},

    -- sources: they decide their own output ----------------------------------------
    switch   = {pins = {"in", "out"}, role = "source", in_pins = {0}, out_pin = 1},
    button   = {pins = {"in", "out"}, role = "source", in_pins = {0}, out_pin = 1},
    pushbutton = {pins = {"in", "out"}, role = "source", in_pins = {0}, out_pin = 1},
    clock    = {pins = {"out"}, role = "source", out_pin = 0, hz = 1},
    number   = {pins = {"out"}, role = "source", out_pin = 0},

    -- sinks: they read a net -------------------------------------------------------
    light    = {pins = {"in", "out"}, role = "sink", in_pins = {0}, out_pin = 1},
    lamp     = {pins = {"in", "out"}, role = "sink", in_pins = {0}, out_pin = 1},
    led      = {pins = {"in", "out"}, role = "sink", in_pins = {0}, out_pin = 1},
    buzzer   = {pins = {"in", "out"}, role = "sink", in_pins = {0}, out_pin = 1},
    display  = {pins = {"in"}, role = "sink", in_pins = {0}, w = 2, h = 1},

    -- passives: input net -> output net --------------------------------------------
    resistor = {pins = {"in", "out"}, role = "passive", in_pins = {0}, out_pin = 1, w = 2, h = 1},
    capacitor = {pins = {"in", "out"}, role = "passive", in_pins = {0}, out_pin = 1, w = 2, h = 1},
    coil     = {pins = {"in", "out"}, role = "passive", in_pins = {0}, out_pin = 1, w = 2, h = 1},
    diode    = {pins = {"in", "out"}, role = "passive", in_pins = {0}, out_pin = 1, w = 2, h = 1},
    -- transistors and other analogue parts are NOT modelled: they read 0.
    transistor = {pins = {"in", "out", "q"}, role = "passive", in_pins = {0, 1}, out_pin = 2, w = 1, h = 2},

    -- gates ------------------------------------------------------------------------
    ["and"]   = gate({"a", "b", "out"}, {0, 1}, function(x, y) return bin(x, y) end),
    ["or"]    = gate({"a", "b", "out"}, {0, 1}, function(x, y) return (x == 1 or y == 1) and 1 or 0 end),
    ["not"]   = gate({"in", "out"}, {0}, function(x) return x == 1 and 0 or 1 end),
    nand      = gate({"a", "b", "out"}, {0, 1}, function(x, y) return (x == 1 and y == 1) and 0 or 1 end),
    nor       = gate({"a", "b", "out"}, {0, 1}, function(x, y) return (x == 1 or y == 1) and 0 or 1 end),
    xor       = gate({"a", "b", "out"}, {0, 1}, function(x, y) return (x ~= y) and 1 or 0 end),
    xnor      = gate({"a", "b", "out"}, {0, 1}, function(x, y) return (x == y) and 1 or 0 end),
    buffer    = gate({"in", "out"}, {0}, function(x) return x == 1 and 1 or 0 end),
}

-- The same gates under the longer finder names ("and_gate", "AND Gate", ...).
local ALIASES = {
    andgate = "and", orgate = "or", notgate = "not", nandgate = "nand",
    norgate = "nor", xorgate = "xor", xnorgate = "xnor", buffergate = "buffer",
    bufgate = "buffer", inverter = "not", truthgate = "and",
}

C.DEFAULT = {
    pins = {"in", "out"}, role = "passive", in_pins = {0}, out_pin = 1, w = 1, h = 1,
}

-- Normalised lookup table, built once.
C.by_norm = {}
for kind, def in pairs(C.kinds) do
    local d = def
    d.kind_name = kind
    C.by_norm[C.norm(kind)] = d
end
for alias, target in pairs(ALIASES) do
    C.by_norm[alias] = C.by_norm[target]
end

function C.get(kind)
    return C.by_norm[C.norm(kind)] or C.DEFAULT
end

-- The part finder's list (the `catalog` op).
function C.list()
    local out, seen = {}, {}
    for _, kind in ipairs({
        "power", "ground", "switch", "button", "clock", "number",
        "light", "display", "resistor", "capacitor", "coil", "diode", "transistor",
        "and", "or", "not", "nand", "nor", "xor", "xnor", "buffer",
    }) do
        if not seen[kind] then
            seen[kind] = true
            local def = C.get(kind)
            out[#out + 1] = {
                name = kind, kind = kind,
                w = def.w or 1, h = def.h or 1,
                pins = def.pins,
            }
        end
    end
    return out
end

-- Default electric settings, by normalised kind (SI units, as the game uses).
local SETTINGS = {
    resistor  = {ohms = 1000},
    capacitor = {farads = 0.000001},
    coil      = {henries = 0.001},
    generator = {hz = 100, height = 1, center = 0, width = 0.5},
    supply    = {volts = 5, limit = 0.1},
    clock     = {hz = 1},
}

function C.settings_for(kind)
    local s = SETTINGS[C.norm(kind)]
    if not s then return {}, {} end
    local out, names = {}, {}
    for k, v in pairs(s) do out[k] = v end
    for _, k in ipairs({"ohms", "farads", "henries", "hz", "height", "center", "width", "volts", "limit"}) do
        if out[k] ~= nil then names[#names + 1] = k end
    end
    return out, names
end

return C
