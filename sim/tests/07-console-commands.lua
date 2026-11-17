-- 07-console-commands -- commands typed in this mod's console.
-- Recipe 10.7 in docs/10-recipes.md.

sim.place("switch", 2, 2)
sim.place("switch", 5, 2)
sim.place("light", 8, 2)

sim.load()
sim.tick(0.05)

logged("commands ready", "the mod announces itself")

-- ---- a command with no arguments ------------------------------------------------
sim.command("count")
contains(sim.logs(), "switch", "count lists the kinds on the board")
contains(sim.logs(), "light", "including the light")
contains(sim.logs(), "total 3 parts, 0 wires", "and the totals")

-- ---- a command with words, all of it as one argument ----------------------------
sim.command("say hello world")
contains(sim.logs(), "hello world", "say prints its words")
ok(#sim.toasts() > 0, "and toasts them")
eq(sim.toasts()[#sim.toasts()].text, "hello world", "with the exact text")

-- ---- a command that explains itself ---------------------------------------------
sim.command("say")
contains(sim.logs(), "usage: say <words>", "say without words prints usage")
eq(sim.warns() > 0, true, "as a warning, not an error")

sim.command("help")
contains(sim.logs(), "go <x> <y>", "help lists the commands")

-- ---- a command that parses the rest of the line ----------------------------------
sim.command("go")
contains(sim.logs(), "usage: go <x> <y>", "go without a pair prints usage")
eq(sim.camera().x, 0, "and leaves the camera alone")
eq(sim.camera().y, 0)

sim.command("go 5 10")
eq(sim.camera().x, 5, "go moves the camera")
eq(sim.camera().y, 10)
contains(sim.logs(), "camera -> 5 10", "and reports where it went")

sim.command("go -3 -4")
eq(sim.camera().x, -3, "negative coordinates work")
eq(sim.camera().y, -4)

-- ---- an unknown command is the engine's problem, not a crash ---------------------
sim.command("nope")
eq(sim.errors(), 0, "an unknown command does not fault the mod")

no_faults()
