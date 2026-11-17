-- 05-player-input -- keys, clicks and the capture flag.
-- Recipe 10.5 in docs/10-recipes.md.

sim.load()
sim.tick(0.05)

-- ---- the mod grabs the keyboard on load ---------------------------------------
eq(sim.captured(), true, "the mod takes the keys on load")
logged("capture on", "and says so out loud")

ok(sim.window("Input"), "the window opens")

local function window_text()
    local out = {}
    for _, w in ipairs(sim.widgets()) do
        if w.text then out[#out + 1] = w.text end
    end
    return table.concat(out, "\n")
end

-- ---- keys reach the mod --------------------------------------------------------
sim.key("space", true)
local sounds = {}
for _, s in ipairs(sim.sounds()) do sounds[#sounds + 1] = s.name end
contains(table.concat(sounds, " "), "click", "space plays a click")

sim.key("return", true)
ok(#sim.notes() > 0, "return plays a note")
eq(sim.notes()[1].hz, 440, "at 440 Hz")
eq(sim.notes()[1].tone, "square", "as a square wave")

-- ---- clicks carry a board position --------------------------------------------
sim.click(10, 20)
logged("clicked tile 10 20", "a click reports the tile it landed on")

-- ---- a held key reads back as held, a released one as not ----------------------
sim.key("space", false)
sim.tick(0.05)

contains(window_text(), "last key: return", "a released key is not the last key")
contains(window_text(), "up: false", "no arrow key is held yet")
contains(window_text(), "space: false", "and space is no longer held")

sim.key("up", true)
sim.tick(0.05)
contains(window_text(), "up: true", "a held key reads back as true")
contains(window_text(), "last key: up", "and becomes the last key")

-- ---- ESCAPE puts the mod's own flag down ----------------------------------------
-- The game owns escape and hands the keys back itself, so the mod only keeps
-- its local state honest -- it never calls tl.input.capture() here.
sim.key("escape", true)
sim.tick(0.05)
eq(sim.widget("capture keys").value, false, "escape clears the mod's flag")
eq(sim.captured(), true, "but the engine capture is untouched by escape")
not_contains(sim.logs(), "capture off", "because the mod never asked for it")

-- ---- the toggle really round-trips through the engine ---------------------------
sim.ui_set("capture keys", true)
sim.tick(0.05)
eq(sim.widget("capture keys").value, true, "the window agrees it is on")
eq(sim.captured(), true, "and the engine has it")

sim.ui_set("capture keys", false)
sim.tick(0.05)
eq(sim.widget("capture keys").value, false, "off again")
eq(sim.captured(), false, "and the engine let go")
logged("capture off", "the change was logged")

no_faults()
