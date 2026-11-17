-- 04-timer-watch -- drive the circuit on a timer, read it with a watch.
-- Recipe 10.4 in docs/10-recipes.md.

-- A switch wired to a light, so there is something for the watch to see.
local sw = sim.place("switch", 2, 2, {label = "A"})
local lt = sim.place("light", 6, 2, {label = "Y"})
sim.wire(sw, "out", lt, 0, 4)

sim.load()
sim.tick(0.1)

-- ---- the mod picked the parts up at load time ---------------------------------
eq(#sim.parts("switch"), 1, "the switch was already on the board when it loaded")
eq(#sim.parts("light"), 1, "and so was the light")
not_contains(sim.logs(), "no light", "so it did not warn about a missing light")
eq(sim.read(sw), 0, "the switch starts open")
eq(sim.read(lt), 0, "and the light is off with it")

-- ---- a command starts the timer ------------------------------------------------
sim.command("flip")
logged("flipping on", "the command was accepted")

sim.tick(0.55)          -- crosses t = 0.5, where the repeating timer is due
eq(sim.read(sw), 1, "the timer closed the switch")
eq(sim.read(lt), 1, "the light followed it through the wire")
logged("light 0 -> 1", "the watch fired on the first change")

sim.tick(0.5)           -- crosses t = 1.0
eq(sim.read(sw), 0, "the timer opened it again")
eq(sim.read(lt), 0, "and the light followed")
logged("light 1 -> 0", "and again on the second change")

-- ---- the window can drive the same thing --------------------------------------
ok(sim.window("Timer"), "the window opens")
eq(sim.widget("flipping: on") ~= nil, true, "and shows the timer is running")

sim.click_button("add switch")
sim.tick(0.05)
eq(#sim.parts("switch"), 2, "the window can add parts")

sim.command("flip off")
logged("flipping off", "the timer can be stopped")
local before = sim.read(sw)
sim.tick(0.6)
eq(sim.read(sw), before, "and nothing moves while it is stopped")

no_faults()
