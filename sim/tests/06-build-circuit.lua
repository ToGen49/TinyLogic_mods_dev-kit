-- 06-build-circuit -- build a small circuit from code, then undo it.
-- Recipe 10.6 in docs/10-recipes.md.

sim.load()
sim.tick(0.05)

eq(#sim.parts(), 0, "the board starts empty")
eq(#sim.wires(), 0, "and wire-free")
eq(sim.eval_value("tl.board.count()"), 0,
   "tl.board.count() returns two values; the test reads the first")

-- ---- building ------------------------------------------------------------------
sim.command("build")

eq(#sim.parts(), 3, "the build places 3 parts")
eq(#sim.wires(), 2, "and joins them with 2 wires")
contains(sim.logs(), "built 3 parts", "and says what it did")

local labels = {}
for _, p in ipairs(sim.parts()) do labels[#labels + 1] = p.label end
table.sort(labels)
eq(table.concat(labels, ","), "A,B,Y", "the parts are labelled A, B and Y")

eq(sim.eval_value("tl.board.count()"), 3, "the mod sees the same count")
eq(#sim.parts("switch"), 2, "two of them are switches")
eq(#sim.parts("light"), 1, "and one is a light")

-- ---- one undo reverses the whole build -----------------------------------------
sim.undo()
eq(#sim.parts(), 0, "one undo reverses the entire build")
eq(#sim.wires(), 0, "wires included")

sim.redo()
eq(#sim.parts(), 3, "redo puts it all back")
eq(#sim.wires(), 2, "wires too")

-- ---- the commands, driven straight ---------------------------------------------
sim.command("clear")
eq(#sim.parts(), 0, "clear removes everything")
logged("removed", "and reports it")

sim.command("clear")
contains(sim.logs(), "nothing built yet", "clearing twice is not an error")

-- ---- the window runs exactly the same code --------------------------------------
sim.click_button("build")
sim.tick(0.05)
eq(#sim.parts(), 3, "the window's build button does the same job")
eq(#sim.wires(), 2)

sim.click_button("undo")
sim.tick(0.05)
eq(#sim.parts(), 0, "and so does its undo button")

no_faults()
