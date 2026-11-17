-- 09-mod-consumer -- use another mod's exports, and talk over the event bus.
-- Recipe 10.8 + 10.9 in docs/10-recipes.md.

-- Load order matters: tl.require only sees mods that are already running, so
-- the library has to be installed and saved + run FIRST.
sim.load("examples/08-mod-library")
sim.load()
sim.tick(0.05)

-- ---- both mods are up ------------------------------------------------------------
local running = table.concat(sim.running(), " ")
eq(#sim.running(), 2, "both mods are running")
contains(running, "08-mod-library", "the library is in tl.mods()")
contains(running, "09-mod-consumer", "and so is the consumer")

-- ---- the window found it ----------------------------------------------------------
local function window_text()
    local out = {}
    for _, w in ipairs(sim.widgets()) do
        if w.text then out[#out + 1] = w.text end
    end
    return table.concat(out, "\n")
end

ok(sim.window("Consumer"), "the consumer opens its window")
contains(window_text(), "library: found", "it found the library")
contains(window_text(), "08-mod-library v0.2-beta", "describe() worked across mods")
contains(window_text(), "  08-mod-library", "the running-mods list shows it")

-- ---- the event bus ------------------------------------------------------------------
sim.event("score", 10)
contains(sim.logs(), "scored 10", "the listener received the event")
contains(sim.logs(), "doubled: 20", "and called the library's export inside it")

sim.event("my-mod:pulse", 1, 2, 3)
contains(sim.logs(), "pulse 1 2 3", "custom events carry arbitrary arguments")

-- ---- sending from the window does the same thing -------------------------------------
sim.click_button("emit score")
sim.tick(0.05)
contains(sim.logs(), "scored 10", "a window button can send an event too")

sim.click_button("emit pulse")
sim.tick(0.05)
contains(sim.logs(), "pulse 1 2 3", "with any arguments you like")

-- ---- the two mods keep their own state -----------------------------------------------
eq(sim.eval_value("tl.id"), "09-mod-consumer", "the consumer sees its own id")
eq(sim.errors(), 0, "neither mod faulted")

no_faults()
